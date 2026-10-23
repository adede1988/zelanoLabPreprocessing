# fr_launch.ps1 - lab side.  Starts fr_driver.ps1 DETACHED from the calling (ssh) session through WMI Win32_Process.Create, at
# below-normal priority, unless a driver is already running (idempotent: never two drivers).  Called by home\fr_start.ps1 over ssh.
#   fr_launch.ps1 [-DriverArgs '-Set validation -HonorGates'] [-Root ...] [-RepoRoot ...]
param(
    [string]$DriverArgs = '',
    [string]$DriverArgsB64 = '',      # the same, base64 of the UTF-8 text (no quoting problems through ssh / cmd.exe)
    [string]$Root = 'E:\claudeWork\rerun1022',
    [string]$RepoRoot = 'E:\GitHub\zlp-main',
    [string]$ScriptRoot = '',         # where fr_driver.ps1 lives (default <RepoRoot>\batch\fullRerun)
    [string]$Manifest = ''
)
$ErrorActionPreference = 'Stop'
if (-not $Manifest) { $Manifest = Join-Path $Root 'manifest.csv' }
if ($DriverArgsB64) { $DriverArgs = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($DriverArgsB64)) }
if (-not $ScriptRoot) { $ScriptRoot = Join-Path $RepoRoot 'batch\fullRerun' }
$driver = Join-Path $ScriptRoot 'fr_driver.ps1'
if (-not (Test-Path -LiteralPath $driver)) { Write-Output "NO DRIVER SCRIPT at $driver"; exit 2 }
if (-not (Test-Path -LiteralPath $Manifest)) { Write-Output "NO MANIFEST at $Manifest"; exit 2 }
New-Item -ItemType Directory -Force -Path (Join-Path $Root 'control'), (Join-Path $Root 'logs') | Out-Null

# is a driver alive?  (the driver holds driver.lock with an exclusive share mode for its whole life)
# ONE MATLAB at a time on the lab desktop: a REAL driver and a SCRATCH driver (own root, own driver.lock) are never both started - the
# launcher looks at both locks.  (The machine-wide MATLAB lock, fr_lib.ps1, is the hard guarantee for everything else: foreground
# fr_runFinal rows, the manifest build.)
$isScratch = ($DriverArgs -match '(^|\s)-Scratch(\s|$)')
$scratchRoot = Join-Path $Root 'scratch'
if ($DriverArgs -match '-ScratchRoot\s+("[^"]+"|\S+)') { $scratchRoot = $Matches[1].Trim('"') }
$realLock = Join-Path $Root 'driver.lock'
$scratchLock = Join-Path $scratchRoot 'driver.lock'
function Test-LockHeld([string]$p) {
    if (-not (Test-Path -LiteralPath $p)) { return $false }
    try { $fs = [IO.File]::Open($p, 'Open', 'ReadWrite', 'None'); $fs.Dispose(); return $false } catch { return $true }
}
$lockPath = if ($isScratch) { $scratchLock } else { $realLock }
$otherLock = if ($isScratch) { $realLock } else { $scratchLock }
if (Test-LockHeld $lockPath) {
    $pj = Join-Path (Split-Path -Parent $lockPath) 'driver.pid.json'
    $info = $null; try { if (Test-Path -LiteralPath $pj) { $info = (Get-Content -LiteralPath $pj -Raw | ConvertFrom-Json) } } catch { }
    Write-Output ("DRIVER ALREADY RUNNING (pid {0}) - not starting another one" -f $(if ($info) { $info.pid } else { '?' }))
    exit 0
}
if (Test-LockHeld $otherLock) {
    Write-Output ("A {0} DRIVER IS RUNNING ({1} is held) - one MATLAB at a time on the lab desktop: not starting a {2} driver. Stop it first (fr_stop.ps1{3})." -f $(if ($isScratch) { 'REAL' } else { 'SCRATCH' }), $otherLock, $(if ($isScratch) { 'scratch' } else { 'real' }), $(if ($isScratch) { '' } else { ' -Scratch' }))
    exit 5
}
# fresh start: clear the stop request left by an earlier run
$ctlRoot = if ($isScratch) { $scratchRoot } else { $Root }
Remove-Item -LiteralPath (Join-Path $ctlRoot 'control\STOP'), (Join-Path $ctlRoot 'control\STOP_NOW') -Force -ErrorAction SilentlyContinue

$cmdLine = 'powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "{0}" -Manifest "{1}" -Root "{2}" -RepoRoot "{3}" {4}' -f $driver, $Manifest, $Root, $RepoRoot, $DriverArgs
$startup = New-CimInstance -ClassName Win32_ProcessStartup -ClientOnly -Property @{ PriorityClass = [uint32]16384; ShowWindow = [uint16]0 }
$r = Invoke-CimMethod -ClassName Win32_Process -MethodName Create -Arguments @{ CommandLine = $cmdLine; CurrentDirectory = $Root; ProcessStartupInformation = $startup }
if ($r.ReturnValue -ne 0) { Write-Output ("WMI Create FAILED, return value {0}" -f $r.ReturnValue); exit 3 }
Write-Output ("DRIVER STARTED pid {0} (detached, below normal priority)" -f $r.ProcessId)
# wait for the first heartbeat
$hbRoot = $ctlRoot      # a scratch driver keeps its own state folder
$hb = Join-Path $hbRoot 'heartbeat.json'
$t0 = Get-Date
while (((Get-Date) - $t0).TotalSeconds -lt 40) {
    Start-Sleep -Seconds 2
    try {
        if (Test-Path -LiteralPath $hb) {
            $j = Get-Content -LiteralPath $hb -Raw | ConvertFrom-Json
            if ([int]$j.pid -eq [int]$r.ProcessId) { Write-Output ("first heartbeat: state={0} {1}" -f $j.state, $j.extra); exit 0 }
        }
    } catch { }
    if (-not (Get-Process -Id $r.ProcessId -ErrorAction SilentlyContinue)) { Write-Output 'the driver exited right away - see logs\driver.log'; exit 4 }
}
Write-Output 'no heartbeat within 40 s (the driver may be waiting for R:) - check status'
exit 0

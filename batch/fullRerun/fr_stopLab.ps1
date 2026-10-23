# fr_stopLab.ps1 - lab side.  Asks the driver to stop, and handles the other control files.
#   (default)  create control\STOP : the driver finishes the final it is working on, then exits ("graceful").
#   -Now       create control\STOP_NOW : MATLAB is killed at once, the final in progress is restored from its backup at the next start.
#   -Wait N    wait up to N minutes for the driver to exit.
#   -Clear     remove the STOP / STOP_NOW / PAUSE files (before a restart; fr_launch.ps1 removes STOP / STOP_NOW too).  GATE_OPEN stays.
#   -Pause / -Resume  create / remove control\PAUSE (hold before the next final).
#   -Continue  create control\GATE_OPEN : opens the persistent validation gate (the file stays; the gate does not close again).
#   -CloseGate remove control\GATE_OPEN (re-arms the gate for a later start).
#   -ClearCred delete the credential blob.
param([string]$Root = 'E:\claudeWork\rerun1022', [switch]$Now, [int]$Wait = 0, [switch]$Clear, [switch]$Pause, [switch]$Resume, [switch]$Continue, [switch]$CloseGate, [switch]$ClearCred)
$ErrorActionPreference = 'Continue'
$ctl = Join-Path $Root 'control'
New-Item -ItemType Directory -Force -Path $ctl | Out-Null
if ($ClearCred) {
    Get-ChildItem -LiteralPath (Join-Path $Root 'secret') -Filter 'netid*' -ErrorAction SilentlyContinue | Remove-Item -Force
    Write-Output 'credential blob deleted'
}
if ($Clear) { 'STOP', 'STOP_NOW', 'PAUSE' | ForEach-Object { Remove-Item -LiteralPath (Join-Path $ctl $_) -Force -ErrorAction SilentlyContinue }; Write-Output 'control files cleared (STOP, STOP_NOW, PAUSE; GATE_OPEN is untouched)'; return }
if ($Pause) { Set-Content -LiteralPath (Join-Path $ctl 'PAUSE') -Value (Get-Date -Format s); Write-Output 'PAUSE created: the driver holds before the next final'; return }
if ($Resume) { Remove-Item -LiteralPath (Join-Path $ctl 'PAUSE') -Force -ErrorAction SilentlyContinue; Write-Output 'PAUSE removed'; return }
if ($Continue) { Set-Content -LiteralPath (Join-Path $ctl 'GATE_OPEN') -Value ('opened ' + (Get-Date -Format s)); Write-Output 'GATE_OPEN created: the validation gate is open (rows after the validation set may start)'; return }
if ($CloseGate) { Remove-Item -LiteralPath (Join-Path $ctl 'GATE_OPEN') -Force -ErrorAction SilentlyContinue; Write-Output 'GATE_OPEN removed: the validation gate is closed again'; return }
if ($ClearCred -and -not $Now -and $Wait -eq 0) { return }
$f = if ($Now) { 'STOP_NOW' } else { 'STOP' }
Set-Content -LiteralPath (Join-Path $ctl $f) -Value (Get-Date -Format s)
Write-Output ("{0} created" -f $f)
if ($Wait -gt 0) {
    $lp = Join-Path $Root 'driver.lock'
    $t0 = Get-Date
    while (((Get-Date) - $t0).TotalMinutes -lt $Wait) {
        $held = $false
        if (Test-Path -LiteralPath $lp) { try { $fs = [IO.File]::Open($lp, 'Open', 'ReadWrite', 'None'); $fs.Dispose() } catch { $held = $true } }
        if (-not $held) { Write-Output 'driver has exited'; return }
        Start-Sleep -Seconds 5
    }
    Write-Output ("driver still running after {0} min" -f $Wait)
}

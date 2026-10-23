# fr_runFinal.ps1 - lab side.  Runs ONE manifest row through the driver's state machine (fr_final.ps1), in a SCRATCH universe by
# default (used by the validation agent) or, with -Real, against the real R: final exactly as the driver does.
#
#   .\fr_runFinal.ps1 -Key cueTask__251002_Dupi_NMH_AB_3                    # scratch universe: everything on E:
#   .\fr_runFinal.ps1 -Task cueTask -Id 251002_Dupi_NMH_AB_3 -NoCarry        # without the respiration carry
#   .\fr_runFinal.ps1 -Key ... -Reset                                        # forget the scratch state of the key first
#   .\fr_runFinal.ps1 -Key ... -Real                                         # REAL: backs up, MOVES and rewrites the final on R:
#
# The scratch universe is described in fr_scratch.ps1: the session folder and the behavior folders of the task are COPIED from R:
# (read-only on R:) into <ScratchRoot>\lc, the master sheet is copied there as the STAGING sheet, a labPaths_local.m points
# labCommon at it.  No R: write, no master-sheet write, no sheet lock.  The state machine is the same as the real one.
# Do not run scratch rows while the real driver runs a final (one MATLAB at a time on the shared lab desktop).
[CmdletBinding()]
param(
    [string]$Manifest = 'E:\claudeWork\rerun1022\manifest.csv',
    [string]$Key = '',
    [string]$Task = '',
    [string]$Id = '',
    [string]$ScratchRoot = 'E:\claudeWork\rerun1022\scratch',
    [string]$RepoRoot = 'E:\GitHub\zlp-main',
    [string]$SecretDir = 'E:\claudeWork\rerun1022\secret',
    [string]$RealRoot = 'E:\claudeWork\rerun1022',
    [switch]$Real,
    [switch]$NoMirror,
    [switch]$Reset,
    [switch]$NoCarry,
    [int]$Threads = 4,
    [int]$WaitMatlabMin = 0,          # 0 = fail at once when another MATLAB of this family runs (one MATLAB at a time); N = wait up to N minutes
    [string]$MatlabLockFile = 'E:\claudeWork\rerun1022\matlab.lock'
)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'fr_lib.ps1')
. (Join-Path $PSScriptRoot 'fr_final.ps1')
. (Join-Path $PSScriptRoot 'fr_scratch.ps1')

if ($Real) { $root = $RealRoot; $backup = 'E:\reprocBackup_261022' } else { $root = $ScratchRoot; $backup = Join-Path $ScratchRoot 'backup' }
$FR = Initialize-Fr -Root $root -RepoRoot $RepoRoot -BackupRoot $backup -Threads $Threads -SecretDir $SecretDir -MatlabLockFile $MatlabLockFile -MatlabLockWaitMin $WaitMatlabMin
$script:FrConsole = $true

$rows = @(Import-Csv -LiteralPath $Manifest)
if (-not $Key) { if ($Task -and $Id) { $Key = "${Task}__${Id}" } else { throw 'give -Key or -Task and -Id' } }
$row = $rows | Where-Object { $_.key -eq $Key } | Select-Object -First 1
if (-not $row) { throw "no manifest row with key $Key in $Manifest" }
if ($NoCarry) { $row.carry = '0' }
if ($row.enabled -eq '0') { Write-FrLog 'WARN' "the manifest row is DISABLED: $($row.note)" }

if (-not (Wait-FrR -MaxWaitSec 120)) { throw 'R: is not available' }
$head = Get-FrRepoHead; $script:FrCtx.Head = $head.Head
if (-not $head.Ok) { throw "git cannot be run for $($FR.RepoRoot): $($head.Error)" }
Write-FrLog 'INFO' ("fr_runFinal {0} universe={1} code {2} dirty={3}" -f $Key, $(if ($Real) { 'REAL' } else { 'scratch' }), $head.Head, $head.Dirty)

if ($Real) {
    # never beside a running driver (same state files, same MATLAB-at-a-time rule)
    $lp = Join-Path $FR.Root 'driver.lock'
    if (Test-Path -LiteralPath $lp) { try { $fs = [IO.File]::Open($lp, 'Open', 'ReadWrite', 'None'); $fs.Dispose() } catch { throw 'the real driver is running (driver.lock is held): stop it first, or use the scratch universe' } }
    if ((Initialize-FrSheetLockScript) -eq 'missing') { throw "the sheet-lock script $($FR.SheetLockScript) does not exist: the master sheet cannot be written safely" }
    $U = New-FrUniverse 'real'
    Write-FrLog 'WARN' 'REAL universe: the final on R: is backed up, MOVED to superseded_261022 and rewritten (the sheet lock is taken)'
} else {
    $U = New-FrUniverse 'scratch' -ScratchRoot $ScratchRoot
    Initialize-FrScratchRow -Row $row -U $U -NoMirror:$NoMirror -Reset:$Reset
}

$out = Invoke-FrFinal -Row $row -U $U
[void](Update-FrStatus @($row) $U)
Write-Output ''
Write-Output ('== {0}: {1} {2}' -f $Key, $out.Outcome, $out.Msg)
$st = Read-FrJson (Join-Path $U.State "$Key.json")
if ($st) {
    Write-Output ('   state={0} attempts={1} interruptions={2} restores={3} runSecs={4} verifyOk={5}' -f $st.state, $st.attempts, $st.interruptions, $st.restores, $st.runSecs, $st.verifyOk)
    if ($st.verifyWarnings) { Write-Output ('   warnings: ' + $st.verifyWarnings) }
    if ($st.lastError) { Write-Output ('   last error: ' + $st.lastError) }
    if ($st.compareFile) { Write-Output ('   comparison: ' + $st.compareFile) }
    if ($st.runLog) { Write-Output ('   MATLAB log: ' + $st.runLog) }
}
if ($out.Outcome -eq 'done') { exit 0 } else { exit 1 }

# fr_start.ps1 - HOME side.  Starts (or restarts) the full-EEG-rerun driver on the lab desktop.  Idempotent: if a driver is already
# running nothing is started (never two drivers).  The driver is created detached on the lab (WMI), so closing this ssh session or
# losing the VPN does not stop it.
#
#   .\fr_start.ps1                              # deliver the credential if the lab has none, start the driver on the whole manifest;
#                                               # the real universe arms the PERSISTENT validation gate by itself (nothing after the validation
#                                               # set starts - also not after a restart or a reboot - until the gate is opened)
#   .\fr_start.ps1 -Set validation              # only the validation set
#   .\fr_start.ps1 -Continue                    # open the validation gate (creates control\GATE_OPEN on the lab; the file stays)
#   .\fr_start.ps1 -CloseGate                   # remove GATE_OPEN again
#   .\fr_start.ps1 -Restart                     # graceful stop (waits), then start again
#   .\fr_start.ps1 -RefreshCred                 # re-deliver the credential (after a password change)
#   .\fr_start.ps1 -RetryFailed                 # put failed finals back to pending (their originals are in place) and run
#   .\fr_start.ps1 -PlanOnly                    # show the plan, start nothing
# The credential travels home DPAPI blob -> memory -> ssh stdin (base64) -> lab user-scope DPAPI blob.  -AllowMachineScope permits
# the machine-scope fallback ONLY if the user-scope blob could not be created under the ssh logon (it is reported when used).
[CmdletBinding()]
param(
    [string]$Set = '',
    [string]$Keys = '',
    [switch]$HonorGates,             # arm the validation gate (the default for the real universe; for a scratch driver that should honour it)
    [switch]$NoGate,                 # do not arm / honour the gate (a deliberate start without the human checkpoint)
    [switch]$CloseGate,
    [switch]$RetryFailed,
    [switch]$AllowCodeChange,
    [switch]$KeepCredential,
    [switch]$Restart,
    [switch]$RefreshCred,
    [switch]$AllowMachineScope,
    [switch]$Continue,
    [switch]$PlanOnly,
    [switch]$Scratch,                # run the loop in the SCRATCH universe (copies on E:, staging sheet; for the validation agent)
    [int]$GapSec = 45,
    [int]$Threads = 4,
    [string]$Manifest = '',          # default <lab root>\manifest.csv
    [string]$ExtraDriverArgs = '',   # raw extra arguments for fr_driver.ps1 (tests: -BackupRoot ... -SecretDir ... -RWatchSec 15)
    [string]$ScriptRoot = ''
)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'fr_homelib.ps1')
$H = $script:FrHome
if (-not (Test-FrSsh)) { Write-Output 'ssh labdesktop does not answer - connect the Northwestern VPN (GlobalProtect) and try again'; exit 2 }

$ctlRoot = if ($Scratch) { $H.Root.TrimEnd([char]92) + [char]92 + 'scratch' } else { $H.Root }
if ($Continue) {
    Invoke-FrLabPs (Get-FrLabScript 'fr_stopLab.ps1' $ScriptRoot) "-Root $ctlRoot -Continue"
    return
}
if ($CloseGate) {
    Invoke-FrLabPs (Get-FrLabScript 'fr_stopLab.ps1' $ScriptRoot) "-Root $ctlRoot -CloseGate"
    return
}
if ($Restart) {
    Write-Output 'graceful stop first ...'
    Invoke-FrLabPs (Get-FrLabScript 'fr_stopLab.ps1' $ScriptRoot) "-Root $ctlRoot -Wait 90"
}

# credential on the lab?
$have = Invoke-FrSsh ('if exist {0}\secret\netid.dpapi (echo CRED_YES) else if exist {0}\secret\netid.machine.dpapi (echo CRED_YES) else (echo CRED_NO)' -f $H.Root)
$hasCred = [bool]($have -match 'CRED_YES')
if ((-not $hasCred -or $RefreshCred) -and -not $PlanOnly) {
    Write-Output 'delivering the R: credential to the lab (ssh stdin -> user-scope DPAPI blob) ...'
    $r = Send-FrCredential -AllowMachineScope:$AllowMachineScope -ScriptRoot $ScriptRoot
    $r.Output | ForEach-Object { Write-Output ("   lab: $_") }
    if ($r.Exit -eq 10) { Write-Output 'NOTE: the credential is stored with MACHINE scope (the user-scope blob could not be created under the ssh logon)' }
    elseif ($r.Exit -ne 0) { Write-Output "credential delivery failed (exit $($r.Exit))"; exit 3 }
}

$da = @()
if ($Set) { $da += "-Set $Set" }
if ($Keys) { $da += "-Keys $Keys" }
if ($NoGate) { $da += '-NoGate' } elseif ($HonorGates -or -not $Scratch) { $da += '-HonorGates' }      # the real universe always arms the gate
if ($RetryFailed) { $da += '-RetryFailed' }
if ($AllowCodeChange) { $da += '-AllowCodeChange' }
if ($KeepCredential) { $da += '-KeepCredential' }
if ($PlanOnly) { $da += '-PlanOnly' }
if ($Scratch) { $da += '-Scratch' }
$da += "-GapSec $GapSec"; $da += "-Threads $Threads"
if ($ExtraDriverArgs) { $da += $ExtraDriverArgs }
$daStr = ($da -join ' ')
if ($PlanOnly) {
    # the plan is printed by a foreground driver call
    $drv = Get-FrLabScript 'fr_driver.ps1' $ScriptRoot
    $mf0 = if ($Manifest) { "-Manifest $Manifest" } else { "-Manifest $($H.Root)\manifest.csv" }
    Invoke-FrLabPs $drv ("-Root $($H.Root) -RepoRoot $($H.RepoRoot) $mf0 " + $daStr)
    return
}
$b64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($daStr))
$sr = if ($ScriptRoot) { "-ScriptRoot $ScriptRoot" } else { '' }
$mf = if ($Manifest) { "-Manifest $Manifest" } else { '' }
Invoke-FrLabPs (Get-FrLabScript 'fr_launch.ps1' $ScriptRoot) "-Root $($H.Root) -RepoRoot $($H.RepoRoot) $sr $mf -DriverArgsB64 $b64"

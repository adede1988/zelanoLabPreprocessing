# fr_stop.ps1 - HOME side.  Stops the full-EEG-rerun driver on the lab desktop.
#   .\fr_stop.ps1                 graceful: the driver finishes the final it is working on, then exits (files: control\STOP)
#   .\fr_stop.ps1 -Wait 60        ... and wait up to 60 min for it to exit
#   .\fr_stop.ps1 -Now            hard: MATLAB is killed at once; the final in progress is restored from its backup at the next start
#   .\fr_stop.ps1 -Pause / -Resume   hold / release the driver before its next final
#   .\fr_stop.ps1 -ClearCred      also delete the R: credential blob on the lab (the driver does that itself when the batch finishes)
[CmdletBinding()]
param([switch]$Now, [int]$Wait = 0, [switch]$Pause, [switch]$Resume, [switch]$ClearCred, [switch]$Scratch, [string]$ScriptRoot = '')
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'fr_homelib.ps1')
$H = $script:FrHome
if (-not (Test-FrSsh)) { Write-Output 'ssh labdesktop does not answer - connect the VPN and try again'; exit 2 }
$a = "-Root $(if ($Scratch) { $H.Root.TrimEnd([char]92) + [char]92 + 'scratch' } else { $H.Root })"
if ($Pause) { $a += ' -Pause' } elseif ($Resume) { $a += ' -Resume' }
else {
    if ($Now) { $a += ' -Now' }
    if ($Wait -gt 0) { $a += " -Wait $Wait" }
    if ($ClearCred) { $a += ' -ClearCred' }
}
Invoke-FrLabPs (Get-FrLabScript 'fr_stopLab.ps1' $ScriptRoot) $a

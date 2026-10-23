# fr_status.ps1 - HOME side.  One screen: is the lab driver alive, what it is doing, one line per state, the last N finals, failures.
#   .\fr_status.ps1 [-Last 10] [-Watch 60]      (-Watch N repeats every N seconds until Ctrl-C)
[CmdletBinding()]
param([int]$Last = 8, [int]$Watch = 0, [switch]$Scratch, [string]$ScriptRoot = '')
$ErrorActionPreference = 'Continue'
. (Join-Path $PSScriptRoot 'fr_homelib.ps1')
$H = $script:FrHome
$rootArg = if ($Scratch) { $H.Root.TrimEnd([char]92) + [char]92 + 'scratch' } else { $H.Root }
do {
    if (-not (Test-FrSsh)) { Write-Output 'ssh labdesktop does not answer (VPN down?).  The driver on the lab keeps running without it.' }
    else { Invoke-FrLabPs (Get-FrLabScript 'fr_statusLab.ps1' $ScriptRoot) "-Root $rootArg -Last $Last" }
    if ($Watch -gt 0) { Write-Output ('-' * 60); Start-Sleep -Seconds $Watch }
} while ($Watch -gt 0)

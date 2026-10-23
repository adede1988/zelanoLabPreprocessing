# fr_withR.ps1 - lab side.  Runs a payload script with R: mapped for THIS logon session, using the rerun credential blob
# (user-scope DPAPI; the password never appears on a command line).  The replacement of runRemote.ps1 for this job: the
# home side only needs `ssh labdesktop "powershell -File ...\fr_withR.ps1 -Payload <script.ps1> [-PayloadArgs ...]"`.
#   Used for: the manifest build (fr_buildManifest), the scratch universe set-up (fr_runFinal.ps1 -Scratch), ad-hoc reads.
#   -MatlabLock  the payload starts a MATLAB: hold the machine-wide MATLAB lock (one MATLAB at a time across the real and the scratch
#                universe) for the payload's whole run; when another MATLAB of the family holds it nothing is started (exit 5).
#                (The lock is taken HERE, in this script's scope: a payload script cannot use the lock functions.)
param(
    [Parameter(Mandatory = $true)][string]$Payload,
    [string]$PayloadArgs = '',
    [string]$Root = 'E:\claudeWork\rerun1022',
    [string]$SecretDir = '',
    [switch]$MatlabLock,
    [string]$MatlabLockFile = 'E:\claudeWork\rerun1022\matlab.lock'
)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'fr_lib.ps1')
$FR = Initialize-Fr -Root $Root -SecretDir $SecretDir -MatlabLockFile $MatlabLockFile
$script:FrNoHeartbeat = $true       # a payload run must never overwrite the heartbeat of the driver that may be running in the same root
$script:FrConsole = $true
if (-not (Wait-FrR -MaxWaitSec 120)) { Write-Output 'R: could not be mapped (credential missing or refused, or the network is down)'; exit 2 }
Write-Output ('R: mapped for this session ({0})' -f [FrNet]::Remote('R:'))
if ($MatlabLock) {
    if ((Enter-FrMatlabLock -Who ('fr_withR ' + (Split-Path -Leaf $Payload)) -WaitMin 0) -ne $true) {
        Write-Output 'another MATLAB of this family is running (the machine MATLAB lock is held) - the payload does not start; try again when it is free'
        exit 5
    }
}
$ErrorActionPreference = 'Continue'
try {
    if ($PayloadArgs) { Invoke-Expression ("& '$Payload' $PayloadArgs") } else { & $Payload }
    $code = $LASTEXITCODE
} finally {
    if ($MatlabLock) { Exit-FrMatlabLock }
}
exit $code

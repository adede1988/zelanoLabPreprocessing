# fr_receiveCred.ps1 - lab side.  Receives the NetID password on STDIN (one line, base64 of the UTF-8 text) and stores it as a
# user-scope DPAPI blob (ConvertFrom-SecureString) in <Root>\secret\netid.dpapi, readable only by this Windows account.
# The password is never a parameter, never on a command line, never printed, never logged.
#   home:  $b64 | ssh labdesktop "powershell -NoProfile -NonInteractive -ExecutionPolicy Bypass -File ...\fr_receiveCred.ps1 [-AllowMachineScope]"
# Exit codes: 0 stored (user scope) | 10 stored with MACHINE scope (only with -AllowMachineScope, after user scope failed) | 20 user
# scope failed and the fallback was not allowed | 21 nothing received.
param(
    [string]$Root = 'E:\claudeWork\rerun1022',
    [string]$User = 'fsm\dtf8829',
    [switch]$AllowMachineScope
)
$ErrorActionPreference = 'Stop'
$line = [Console]::In.ReadLine()
if (-not $line) { Write-Output 'NOTHING RECEIVED ON STDIN'; exit 21 }
$secretDir = Join-Path $Root 'secret'
New-Item -ItemType Directory -Force -Path $secretDir | Out-Null
$pw = $null
try {
    # a pipe from Windows PowerShell may start with a byte-order mark: keep only the base64 alphabet
    $clean = ($line -replace '[^A-Za-z0-9+/=]', '')
    $pw = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($clean))
    $line = $null
    $blob = Join-Path $secretDir 'netid.dpapi'
    $stored = $false
    try {
        # built char by char: no cmdlet ever receives the plaintext as a parameter (module / script-block logging would record it)
        $sec = New-Object Security.SecureString
        foreach ($ch in $pw.ToCharArray()) { $sec.AppendChar($ch) }
        $sec.MakeReadOnly()
        $enc = ConvertFrom-SecureString $sec        # CurrentUser DPAPI
        # prove that this logon can read it back before the old blob is replaced
        $back = ConvertTo-SecureString $enc
        [void][Runtime.InteropServices.Marshal]::SecureStringToBSTR($back)
        [IO.File]::WriteAllText($blob + '.new', $enc, [Text.Encoding]::ASCII)
        Move-Item -LiteralPath ($blob + '.new') -Destination $blob -Force
        Remove-Item -LiteralPath (Join-Path $secretDir 'netid.machine.dpapi') -Force -ErrorAction SilentlyContinue
        $stored = $true
        Write-Output 'STORED: user-scope DPAPI blob'
    } catch {
        Write-Output ('USER-SCOPE DPAPI FAILED: ' + $_.Exception.GetType().Name)
    }
    if (-not $stored) {
        if (-not $AllowMachineScope) { Write-Output 'machine-scope fallback not allowed (use -AllowMachineScope to permit it)'; exit 20 }
        Add-Type -AssemblyName System.Security
        $ent = [Text.Encoding]::UTF8.GetBytes('zlp-rerun1022')
        $enc = [Security.Cryptography.ProtectedData]::Protect([Text.Encoding]::UTF8.GetBytes($pw), $ent, [Security.Cryptography.DataProtectionScope]::LocalMachine)
        [IO.File]::WriteAllText((Join-Path $secretDir 'netid.machine.dpapi'), [Convert]::ToBase64String($enc), [Text.Encoding]::ASCII)
        $blob = Join-Path $secretDir 'netid.machine.dpapi'
        Write-Output 'STORED: MACHINE-scope DPAPI blob (any process on this machine can decrypt it)'
    }
    [IO.File]::WriteAllText((Join-Path $secretDir 'netid.user'), $User, [Text.Encoding]::ASCII)
    # restrict the folder to this account (inheritance off)
    try {
        & icacls.exe $secretDir /inheritance:r /grant:r ("{0}:(OI)(CI)F" -f [Security.Principal.WindowsIdentity]::GetCurrent().Name) 2>&1 | Out-Null
    } catch { }
    if ($stored) { exit 0 } else { exit 10 }
} finally { $pw = $null }

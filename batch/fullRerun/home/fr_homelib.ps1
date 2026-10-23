# fr_homelib.ps1 - home-side helpers of the full-EEG-rerun driver (dot-sourced by fr_start / fr_status / fr_stop).
# Everything goes through `ssh labdesktop` (key based); the VPN must be up.  A dropped VPN does NOT stop the driver on the lab.
$script:FrHome = @{
    Ssh      = 'labdesktop'
    Root     = 'E:\claudeWork\rerun1022'
    RepoRoot = 'E:\GitHub\zlp-main'
}
# tests can point the home commands at another lab root / repo (the production defaults are above)
if ($env:FR_LAB_ROOT) { $script:FrHome.Root = $env:FR_LAB_ROOT }
if ($env:FR_LAB_REPO) { $script:FrHome.RepoRoot = $env:FR_LAB_REPO }
function Get-FrLabScript {
    param([string]$Name, [string]$ScriptRoot = '')
    # lab paths are plain strings (the lab drives do not exist on this machine, so no Join-Path)
    if (-not $ScriptRoot) { $ScriptRoot = $script:FrHome.RepoRoot.TrimEnd('\') + '\batch\fullRerun' }
    return ($ScriptRoot.TrimEnd('\') + '\' + $Name)
}
function Invoke-FrSsh {
    # one ssh call with retries: sshd on the lab sometimes refuses a connection (kex_exchange_identification / reset) when several
    # sessions connect at once - that is not a VPN drop unless it persists.  Returns the output lines; $global:FrLastExit = exit code.
    param([Parameter(Mandatory)][string]$Command, [string]$Stdin = $null, [int]$Tries = 4)
    $out = @()
    for ($i = 1; $i -le $Tries; $i++) {
        if ($null -ne $Stdin) {
            $saved = $OutputEncoding; $OutputEncoding = New-Object Text.UTF8Encoding($false)
            try { $out = $Stdin | & ssh -o ConnectTimeout=20 $script:FrHome.Ssh $Command 2>&1 | ForEach-Object { "$_" } } finally { $OutputEncoding = $saved }
        } else {
            $out = & ssh -o ConnectTimeout=20 $script:FrHome.Ssh $Command 2>&1 | ForEach-Object { "$_" }
        }
        $global:FrLastExit = $LASTEXITCODE
        if ($global:FrLastExit -ne 255) { break }
        if ($i -lt $Tries) { Start-Sleep -Seconds 15 }
    }
    return $out
}
function Invoke-FrLabPs {
    # runs a lab-side .ps1 with a plain argument string (no quotes inside it); returns the output lines
    param([Parameter(Mandatory)][string]$Script, [string]$ArgString = '')
    $cmd = 'powershell -NoProfile -NonInteractive -ExecutionPolicy Bypass -File {0} {1}' -f $Script, $ArgString
    return (Invoke-FrSsh $cmd)
}
function Test-FrSsh {
    $o = Invoke-FrSsh 'echo FR_SSH_OK'
    return [bool]($o -match 'FR_SSH_OK')
}
function Send-FrCredential {
    # decrypts the home DPAPI blob in memory and sends it through the ssh STDIN pipe (base64) to the lab receiver.
    # The password is never an argument of any command, never printed.
    param([switch]$AllowMachineScope, [string]$ScriptRoot = '')
    $blobPath = Join-Path $env:USERPROFILE '.fsmcreds\netid.sec'
    if (-not (Test-Path -LiteralPath $blobPath)) { throw "no home credential blob at $blobPath (create it as described in CLAUDE.md, Remote compute)" }
    $sec = Get-Content -LiteralPath $blobPath | ConvertTo-SecureString
    $bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($sec)
    $b64 = $null
    try { $b64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes([Runtime.InteropServices.Marshal]::PtrToStringAuto($bstr))) }
    finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr) }
    $rx = Get-FrLabScript 'fr_receiveCred.ps1' $ScriptRoot
    $flag = if ($AllowMachineScope) { '-AllowMachineScope' } else { '' }
    $cmd = 'powershell -NoProfile -NonInteractive -ExecutionPolicy Bypass -File {0} -Root {1} {2}' -f $rx, $script:FrHome.Root, $flag
    $out = Invoke-FrSsh $cmd -Stdin $b64
    $code = $global:FrLastExit
    $b64 = $null
    return @{ Exit = $code; Output = $out }
}

# fr_lib.ps1 - shared library of the full-EEG-rerun lab driver (dot-source it; Windows PowerShell 5.1 on the lab desktop).
#
# What lives here: configuration, logging, atomic JSON state files, the heartbeat, the control files (STOP / PAUSE),
# the R: mapping (own credential handling), thread-wrapped file operations on R:, the machine-wide MATLAB lock (one MATLAB at a
# time across the real and the scratch universe), the MATLAB launcher with its watchdogs (R:, time/CPU, sheet-lock liveness),
# the sheet-lock holder and the code-freeze helpers (git).  The per-final state machine is in fr_final.ps1, the loop in fr_driver.ps1.
#
# Security: the NetID password is only ever (1) in the home DPAPI blob, (2) on the ssh stdin pipe (base64), (3) in the lab's
# user-scope DPAPI blob <Root>\secret\netid.dpapi, (4) in this process's memory while WNetAddConnection2 runs.  It is never
# put on a command line, in a log, in a state file or in the repo.  No participant data or notes are handled here.

$script:FR = $null
$script:FrLibDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$script:FrConsole = $false
$script:FrNoHeartbeat = $false
$script:FrCtx = @{ Key = ''; Step = ''; State = 'init'; MatlabPid = 0; RLast = $null; RLastTime = [DateTime]::MinValue; Counts = $null; Extra = '' }
$script:FrHbLast = [DateTime]::MinValue
$script:FrAuthFails = 0
$script:FrInProbe = $false
$script:FrAuthBlockStamp = $null
$script:FrLockHandle = $null
$script:FrMatlabLockHandle = $null    # the machine-wide MATLAB lock (one MATLAB at a time across the real AND the scratch universe)
$script:FrMatlabLockInfo = $null
$script:FrGit = ''
$script:FrWarnedLockSnap = $false

function Initialize-Fr {
    param(
        [string]$Root = 'E:\claudeWork\rerun1022',
        [string]$RepoRoot = 'E:\GitHub\zlp-main',
        [string]$BackupRoot = 'E:\reprocBackup_261022',
        [int]$Threads = 4,
        [double]$MinFreeE_GB = 40,
        [double]$MinFreeR_GB = 60,
        [double]$MinFreeMem_GB = 16,
        [int]$RWatchSec = 45,
        [string]$SecretDir = '',
        [string]$SheetLockScript = '',
        [string]$SheetLockFile = '',
        [string]$MatlabLockFile = 'E:\claudeWork\rerun1022\matlab.lock',
        [int]$MatlabLockWaitMin = 0
    )
    $here = $script:FrLibDir
    $FR = @{}
    $FR.Root = $Root; $FR.RepoRoot = $RepoRoot; $FR.BackupRoot = $BackupRoot
    $FR.Here = $here
    $FR.State = Join-Path $Root 'state'
    $FR.Logs = Join-Path $Root 'logs'
    $FR.Control = Join-Path $Root 'control'
    $FR.Compare = Join-Path $Root 'compare'
    $FR.Cmd = Join-Path $Root 'cmd'
    $FR.Secret = $(if ($SecretDir) { $SecretDir } else { Join-Path $Root 'secret' })
    $FR.SheetTmp = Join-Path $Root 'sheettmp'
    $FR.Superseded = 'superseded_261022'
    $FR.CanonLC = 'R:\Neurology\Zelano_Lab\Lab_Common\'
    $FR.RProbe = 'R:\Neurology\Zelano_Lab\Lab_Common\Admin\Data\dataTracking.xlsx'
    $FR.RShare = '\\fsmresfiles.fsm.northwestern.edu\fsmresfiles'
    $FR.RUser = 'fsm\dtf8829'
    # the lab's shared write lock of dataTracking.xlsx (a test may point these at a test copy of the script)
    $FR.RealSheetLockFile = 'E:\claudeWork\u1012\sheet.lock'
    $FR.SheetLockScript = $(if ($SheetLockScript) { $SheetLockScript } else { 'E:\claudeWork\u1012\withSheetLock.ps1' })
    $FR.SheetLockFile = $(if ($SheetLockFile) { $SheetLockFile } else { $FR.RealSheetLockFile })
    $FR.LockOwner = 'rerun1022'
    # the lab's lock script is another job's file: a copy is kept under <Root>\locklib and used if the original ever disappears
    $FR.SheetLockSnap = Join-Path $Root 'locklib\withSheetLock.ps1'
    # lab convention (AGENT_BRIEF): the master sheet is backed up here before any write
    $FR.SheetBackupDir = 'R:\Neurology\Zelano_Lab\Lab_Common\Admin\Data\sheetBackups'
    # ONE MATLAB at a time on the lab desktop whatever the universe: every MATLAB this family starts holds this lock (an OS-held
    # exclusive file handle: released by the OS if the holder dies).  Wait: 0 = fail fast, N = wait up to N minutes (the driver).
    $FR.MatlabLockFile = $MatlabLockFile
    $FR.MatlabLockWaitMin = $MatlabLockWaitMin
    $FR.Threads = $Threads
    $FR.MinFreeE_GB = $MinFreeE_GB
    $FR.MinFreeR_GB = $MinFreeR_GB
    $FR.MinFreeMem_GB = $MinFreeMem_GB
    $FR.HeartbeatSec = 20
    $FR.RWatchSec = $RWatchSec
    $FR.CpuWindowMin = 10      # a MATLAB past its time limit is killed only if it used < 3 CPU-s per minute of this window
    $FR.Matlab = 'matlab'
    foreach ($d in @($FR.State, $FR.Logs, $FR.Control, $FR.Compare, $FR.Cmd, $FR.Secret, $FR.SheetTmp, $FR.BackupRoot)) {
        if (-not (Test-Path -LiteralPath $d)) { New-Item -ItemType Directory -Force -Path $d | Out-Null }
    }
    $script:FR = $FR
    if (-not ('FrJob' -as [type])) {
        Add-Type -Path (Join-Path $here 'fr_native.cs') -ErrorAction Stop
    }
    return $FR
}

# ----------------------------------------------------------------------------------------------- logging
function Write-FrLog {
    param([string]$Level = 'INFO', [Parameter(Mandatory)][string]$Msg, [string]$File = '')
    $line = '{0} [{1}] {2}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Level, $Msg
    if (-not $File) { $File = Join-Path $script:FR.Logs 'driver.log' }
    try { [IO.File]::AppendAllText($File, $line + [Environment]::NewLine) } catch { }
    if ($script:FrConsole) { Write-Host $line }
}

# ----------------------------------------------------------------------------------------------- JSON state
function Save-FrJson {
    param([Parameter(Mandatory)]$Obj, [Parameter(Mandatory)][string]$Path, [int]$Depth = 8)
    $tmp = $Path + '.tmp'
    $json = $Obj | ConvertTo-Json -Depth $Depth
    [IO.File]::WriteAllText($tmp, $json, (New-Object Text.UTF8Encoding($false)))
    # replace the old file; a reader (the status command) may hold it open for a moment: retry, then overwrite in place
    for ($i = 1; $i -le 6; $i++) {
        try { Move-Item -LiteralPath $tmp -Destination $Path -Force -ErrorAction Stop; return } catch { Start-Sleep -Milliseconds 250 }
    }
    [IO.File]::WriteAllText($Path, $json, (New-Object Text.UTF8Encoding($false)))
    Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue
}
function Read-FrJson {
    param([Parameter(Mandatory)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return $null }
    for ($i = 0; $i -lt 5; $i++) {
        try {
            # share mode ReadWrite+Delete: never blocks the atomic replace done by the writer
            $fs = [IO.File]::Open($Path, 'Open', 'Read', 'ReadWrite, Delete')
            try { $sr = New-Object IO.StreamReader($fs, [Text.Encoding]::UTF8); $txt = $sr.ReadToEnd() } finally { $fs.Dispose() }
            return ($txt | ConvertFrom-Json)
        } catch { Start-Sleep -Milliseconds 200 }
    }
    return $null
}

# ----------------------------------------------------------------------------------------------- heartbeat
function Update-FrHeartbeat {
    param([switch]$Force)
    if (-not $script:FR -or $script:FrNoHeartbeat) { return }      # only the driver (and scratch runs, in their own root) write a heartbeat
    $now = Get-Date
    if (-not $Force -and ($now - $script:FrHbLast).TotalSeconds -lt $script:FR.HeartbeatSec) { return }
    $script:FrHbLast = $now
    # keep the R: health fresh in the heartbeat (idle waits, sheet-lock waits, gaps): a probe at most every 2 min
    if (-not $script:FrInProbe -and ($now - $script:FrCtx.RLastTime).TotalSeconds -gt 120) {
        $script:FrInProbe = $true
        try { [void](Test-FrR 20) } finally { $script:FrInProbe = $false }
    }
    $me = Get-Process -Id $PID
    $hb = [ordered]@{
        time = $now.ToString('s'); pid = $PID; procStartTicks = $me.StartTime.ToUniversalTime().Ticks
        host = $env:COMPUTERNAME; state = $script:FrCtx.State; key = $script:FrCtx.Key; step = $script:FrCtx.Step
        matlabPid = $script:FrCtx.MatlabPid; rOk = $script:FrCtx.RLast; rChecked = $(if ($script:FrCtx.RLastTime -gt [DateTime]::MinValue) { $script:FrCtx.RLastTime.ToString('s') } else { '' })
        counts = $script:FrCtx.Counts; extra = $script:FrCtx.Extra; repoHead = $script:FrCtx.Head
    }
    try { Save-FrJson -Obj $hb -Path (Join-Path $script:FR.Root 'heartbeat.json') } catch { }
}
function Set-FrCtx {
    param([string]$State, [string]$Key, [string]$Step, [string]$Extra)
    if ($PSBoundParameters.ContainsKey('State')) { $script:FrCtx.State = $State }
    if ($PSBoundParameters.ContainsKey('Key')) { $script:FrCtx.Key = $Key }
    if ($PSBoundParameters.ContainsKey('Step')) { $script:FrCtx.Step = $Step }
    if ($PSBoundParameters.ContainsKey('Extra')) { $script:FrCtx.Extra = $Extra }
    Update-FrHeartbeat -Force
}

# ----------------------------------------------------------------------------------------------- control files
function Get-FrControl {
    # 'now' (STOP_NOW) | 'stop' (STOP) | 'pause' (PAUSE) | ''
    $c = $script:FR.Control
    if (Test-Path -LiteralPath (Join-Path $c 'STOP_NOW')) { return 'now' }
    if (Test-Path -LiteralPath (Join-Path $c 'STOP')) { return 'stop' }
    if (Test-Path -LiteralPath (Join-Path $c 'PAUSE')) { return 'pause' }
    return ''
}
function Start-FrSleep {
    # sleep with heartbeats; returns early (true) when a stop is requested
    param([double]$Seconds)
    $t0 = Get-Date
    while (((Get-Date) - $t0).TotalSeconds -lt $Seconds) {
        Update-FrHeartbeat
        $c = Get-FrControl
        if ($c -eq 'now' -or $c -eq 'stop') { return $true }
        Start-Sleep -Milliseconds 500
    }
    return $false
}

# ----------------------------------------------------------------------------------------------- thread-wrapped fs ops
function Wait-FrJob {
    # waits for a FrJob; throws on failure or a stall (no progress for StallSec); returns Result
    param([Parameter(Mandatory)]$Job, [int]$StallSec = 120, [string]$What = 'fs op')
    while (-not $Job.Done) {
        Start-Sleep -Milliseconds 300
        Update-FrHeartbeat
        if ($Job.IdleSec -gt $StallSec) { throw ("FRSTALL: {0} made no progress for {1} s" -f $What, $StallSec) }
    }
    if ($Job.Failed) { throw ("FRFS: {0}: {1}" -f $What, $Job.Error) }
    return $Job.Result
}
function Get-FrHash { param([string]$Path, [int]$StallSec = 180) Wait-FrJob ([FrJob]::Hash($Path)) $StallSec "hash $Path" }
function Copy-FrHash { param([string]$Src, [string]$Dst, [int]$StallSec = 180, [switch]$Overwrite) Wait-FrJob ([FrJob]::CopyHash($Src, $Dst, [bool]$Overwrite)) $StallSec "copy $Src" }
function Move-FrFile { param([string]$Src, [string]$Dst, [int]$StallSec = 120) Wait-FrJob ([FrJob]::Move($Src, $Dst)) $StallSec "move $Src" | Out-Null }
function New-FrDir { param([string]$Dir, [int]$StallSec = 60) Wait-FrJob ([FrJob]::Mkdir($Dir)) $StallSec "mkdir $Dir" | Out-Null }
function Test-FrPath { param([string]$Path, [int]$StallSec = 60) return ((Wait-FrJob ([FrJob]::Exists($Path)) $StallSec "exists $Path") -eq '1') }
function Get-FrFileInfo {
    # @{ Exists; Length; MTimeUtc } for a file ; throws on stall
    param([string]$Path, [int]$StallSec = 60)
    $r = Wait-FrJob ([FrJob]::Info($Path)) $StallSec "info $Path"
    if ($r -eq 'missing') { return @{ Exists = $false; Length = 0L; MTimeUtc = [DateTime]::MinValue } }
    $p = $r.Split('|')
    return @{ Exists = $true; Length = [long]$p[0]; MTimeUtc = (New-Object DateTime ([long]$p[1]), ([DateTimeKind]::Utc)) }
}
function Get-FrFreeGB { param([string]$Path) return ([double](Wait-FrJob ([FrJob]::FreeSpace($Path)) 60 "freespace $Path") / 1GB) }

# ----------------------------------------------------------------------------------------------- credential + R: mapping
function Get-FrCredential {
    # returns @{ User; Pw } or $null.  User scope blob first; the machine-scope fallback blob only if it exists.
    $u = Join-Path $script:FR.Secret 'netid.dpapi'
    $m = Join-Path $script:FR.Secret 'netid.machine.dpapi'
    $pw = $null
    if (Test-Path -LiteralPath $u) {
        try {
            $sec = ConvertTo-SecureString (Get-Content -LiteralPath $u -Raw).Trim()
            $b = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($sec)
            try { $pw = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($b) } finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($b) }
        } catch { Write-FrLog 'WARN' 'user-scope credential blob could not be decrypted'; $pw = $null }
    }
    if (-not $pw -and (Test-Path -LiteralPath $m)) {
        try {
            Add-Type -AssemblyName System.Security
            $enc = [Convert]::FromBase64String((Get-Content -LiteralPath $m -Raw).Trim())
            $ent = [Text.Encoding]::UTF8.GetBytes('zlp-rerun1022')
            $pw = [Text.Encoding]::UTF8.GetString([Security.Cryptography.ProtectedData]::Unprotect($enc, $ent, [Security.Cryptography.DataProtectionScope]::LocalMachine))
        } catch { Write-FrLog 'WARN' 'machine-scope credential blob could not be decrypted'; $pw = $null }
    }
    if (-not $pw) { return $null }
    $user = $script:FR.RUser
    $uf = Join-Path $script:FR.Secret 'netid.user'
    if (Test-Path -LiteralPath $uf) { $t = (Get-Content -LiteralPath $uf -Raw).Trim(); if ($t) { $user = $t } }
    return @{ User = $user; Pw = $pw }
}
function Get-FrCredStamp {
    $f = Get-ChildItem -LiteralPath $script:FR.Secret -Filter 'netid*.dpapi' -ErrorAction SilentlyContinue | Sort-Object LastWriteTimeUtc -Descending | Select-Object -First 1
    if ($f) { return $f.LastWriteTimeUtc.Ticks.ToString() }
    return ''
}
function Test-FrR {
    param([int]$TimeoutSec = 25)
    $j = [FrJob]::Probe($script:FR.RProbe)
    $t0 = [DateTime]::UtcNow
    while (-not $j.Done -and ([DateTime]::UtcNow - $t0).TotalSeconds -lt $TimeoutSec) { Start-Sleep -Milliseconds 200 }
    $ok = ($j.Done -and -not $j.Failed)
    # a sharing violation (somebody holds the sheet exclusively for a moment) means the share ANSWERS (counts as up)
    if ($j.Done -and $j.Failed -and $j.Error -match 'being used by another process') { $ok = $true }
    $script:FrCtx.RLast = $ok; $script:FrCtx.RLastTime = Get-Date
    return $ok
}
function Connect-FrR {
    # (Re)maps R: for this logon session.  Returns 'ok' | 'nocred' | 'authblock' | 'auth:<code>' | 'net:<code>'
    $stamp = Get-FrCredStamp
    if ($script:FrAuthBlockStamp -and $script:FrAuthBlockStamp -eq $stamp) { return 'authblock' }   # same credential already refused: wait for a new one
    $cred = Get-FrCredential
    if (-not $cred) { return 'nocred' }
    $rc = -1
    try {
        [void][FrNet]::Cancel('R:')
        $rc = [FrNet]::Add('R:', $script:FR.RShare, $cred.User, $cred.Pw)
        if ($rc -eq 85) { [void][FrNet]::Cancel('R:'); $rc = [FrNet]::Add('R:', $script:FR.RShare, $cred.User, $cred.Pw) }
        if ($rc -eq 1219) { [void][FrNet]::Cancel($script:FR.RShare); [void][FrNet]::Cancel('R:'); $rc = [FrNet]::Add('R:', $script:FR.RShare, $cred.User, $cred.Pw) }
    } finally { $cred.Pw = $null }
    if ($rc -eq 0) { $script:FrAuthFails = 0; $script:FrAuthBlockStamp = $null; return 'ok' }
    if (@(86, 1326, 1331, 1909, 1385, 1330, 1244) -contains $rc) {
        $script:FrAuthFails++
        if ($script:FrAuthFails -ge 2) { $script:FrAuthBlockStamp = $stamp }   # never hammer a refused credential (account lock-out)
        return ('auth:' + $rc)
    }
    return ('net:' + $rc)
}
function Wait-FrR {
    # blocks until R: answers; remaps when it does not.  Returns $true, or $false when a stop was requested / the credential is refused.
    param([int]$MaxWaitSec = 0)
    $t0 = Get-Date; $backoff = 15; $first = $true
    while ($true) {
        if (Test-FrR) { if (-not $first) { Write-FrLog 'INFO' ('R: is back after {0} s' -f [int]((Get-Date) - $t0).TotalSeconds) }; Set-FrCtx -Extra ''; return $true }
        if ($first) { Write-FrLog 'WARN' 'R: does not answer - remapping'; $first = $false }
        $res = Connect-FrR
        if ($res -eq 'ok') { if (Test-FrR) { Write-FrLog 'INFO' 'R: remapped'; Set-FrCtx -Extra ''; return $true } ; $res = 'net:probe-failed' }
        Write-FrLog 'WARN' ("remap result: $res")
        Set-FrCtx -State 'waitR' -Extra ("R: unavailable ($res)")
        if ($res -like 'auth*' -or $res -eq 'authblock' -or $res -eq 'nocred') {
            # a refused / missing credential cannot be fixed by retrying: wait for a new blob (or a stop)
            Set-FrCtx -State 'pausedAuth' -Extra ("R: credential problem ($res) - deliver a new one with fr_start.ps1 -RefreshCred")
            if (Start-FrSleep 60) { return $false }
            continue
        }
        if (Start-FrSleep $backoff) { return $false }
        $backoff = [Math]::Min($backoff * 2, 300)
        if ($MaxWaitSec -gt 0 -and ((Get-Date) - $t0).TotalSeconds -gt $MaxWaitSec) { return $false }
    }
}

# ----------------------------------------------------------------------------------------------- processes
function Stop-FrOrphanMatlab {
    # a MATLAB left by a driver that was killed (not possible with the kill-on-close job object, but checked): kill that tree
    $f = Join-Path $script:FR.Root 'matlab.pid.json'
    $j = Read-FrJson $f
    if (-not $j) { return }
    $pr = Get-Process -Id ([int]$j.pid) -ErrorAction SilentlyContinue
    if ($pr -and $pr.StartTime.ToUniversalTime().Ticks -eq [long]$j.startTicks) {
        Write-FrLog 'WARN' ("killing an orphaned MATLAB (pid {0}) of the previous driver (pid {1})" -f $j.pid, $j.driverPid)
        Stop-FrTree ([int]$j.pid)
        Start-Sleep -Seconds 3
    }
    Remove-Item -LiteralPath $f -Force -ErrorAction SilentlyContinue
}
function Stop-FrTree {
    param([int]$ProcId)
    if ($ProcId -le 0) { return }
    & taskkill /PID $ProcId /T /F 2>&1 | Out-Null
}
function Get-FrTreeCpu {
    # CPU seconds used so far by a process and all its descendants
    param([int]$RootPid)
    $ids = New-Object Collections.Generic.List[int]; $ids.Add($RootPid)
    $all = @(Get-CimInstance Win32_Process -Property ProcessId, ParentProcessId -ErrorAction SilentlyContinue)
    $k = 0
    while ($k -lt $ids.Count) {
        $par = $ids[$k]; $k++
        foreach ($c in ($all | Where-Object { $_.ParentProcessId -eq $par })) { if (-not $ids.Contains([int]$c.ProcessId)) { $ids.Add([int]$c.ProcessId) } }
    }
    $sum = 0.0
    foreach ($i in $ids) { $pr = Get-Process -Id $i -ErrorAction SilentlyContinue; if ($pr -and $null -ne $pr.CPU) { $sum += [double]$pr.CPU } }
    return $sum
}
# ----------------------------------------------------------------------------------------------- the machine-wide MATLAB lock
# ONE MATLAB at a time on the lab desktop, whatever the universe (real driver, scratch driver, a foreground fr_runFinal row, the
# manifest build): every MATLAB this family starts runs under this lock.  The lock is an OS-held exclusive file handle, so it is
# released by the OS when its holder dies (no stale lock); <file>.json says who holds it (informational, for status and messages).
# The per-final unit (Invoke-FrFinal) takes it BEFORE the sheet lock and the move and holds it for the run and the verification;
# Invoke-FrMatlab takes it by itself (fail fast) when the caller did not.
function Get-FrMatlabLockState {
    # @{ Held; Info } - read-only
    $f = $script:FR.MatlabLockFile
    $held = $false
    if ($script:FrMatlabLockHandle) { $held = $true }
    elseif (Test-Path -LiteralPath $f) {
        try { $fs = [IO.File]::Open($f, 'Open', 'ReadWrite', 'None'); $fs.Dispose() } catch { $held = $true }
    }
    $info = $null
    if ($held) { $info = Read-FrJson ($f + '.json') }
    return @{ Held = $held; Info = $info }
}
function Enter-FrMatlabLock {
    # $true: taken (or already held by this process) | $false: held by another process (WaitMin 0) or the wait ran out | $null: a stop was requested while waiting
    param([string]$Who = '', [double]$WaitMin = -1)
    if ($WaitMin -lt 0) { $WaitMin = [double]$script:FR.MatlabLockWaitMin }
    if ($script:FrMatlabLockHandle) { return $true }
    $f = $script:FR.MatlabLockFile
    $dir = Split-Path -Parent $f
    if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    $t0 = Get-Date; $logged = $false
    while ($true) {
        try { $script:FrMatlabLockHandle = [IO.File]::Open($f, 'OpenOrCreate', 'ReadWrite', 'None'); break }
        catch {
            $st = Get-FrMatlabLockState
            $by = if ($st.Info) { "{0} (pid {1}, since {2})" -f $st.Info.who, $st.Info.pid, $st.Info.since } else { 'another process' }
            if ($WaitMin -le 0) { Write-FrLog 'WARN' ("the machine MATLAB lock is held by $by - one MATLAB at a time"); return $false }
            if (-not $logged) { $logged = $true; Write-FrLog 'WARN' ("waiting for the machine MATLAB lock held by $by (one MATLAB at a time)") }
            Set-FrCtx -Extra ("waiting for the machine MATLAB lock held by $by - {0} s" -f [int]((Get-Date) - $t0).TotalSeconds)
            if (Start-FrSleep 15) { return $null }
            if (((Get-Date) - $t0).TotalMinutes -gt $WaitMin) { return $false }
        }
    }
    if ($logged) { Set-FrCtx -Extra ''; Write-FrLog 'INFO' ('the machine MATLAB lock is mine after {0} s' -f [int]((Get-Date) - $t0).TotalSeconds) }
    try {
        $script:FrMatlabLockInfo = [ordered]@{ pid = $PID; who = $(if ($Who) { $Who } else { "pid $PID" }); root = $script:FR.Root; since = (Get-Date -Format s); host = $env:COMPUTERNAME }
        Save-FrJson -Obj $script:FrMatlabLockInfo -Path ($f + '.json')
    } catch { }
    return $true
}
function Exit-FrMatlabLock {
    if (-not $script:FrMatlabLockHandle) { return }
    $f = $script:FR.MatlabLockFile
    # the info file first, then the handle: another process that takes the lock right after the release must not lose its own info file
    Remove-Item -LiteralPath ($f + '.json') -Force -ErrorAction SilentlyContinue
    try { $script:FrMatlabLockHandle.Dispose() } catch { }
    $script:FrMatlabLockHandle = $null; $script:FrMatlabLockInfo = $null
}

function Invoke-FrMatlab {
    # Runs one MATLAB command file as a child (below normal), waits with watchdogs.
    #   returns @{ Exit; TimedOut; RLost; Stopped; LockLost; LockBusy; Secs; Pid }
    #   LockBusy: another MATLAB of this family holds the machine lock (nothing was started)
    #   LockLost: the sheet-lock holder (LockHolder) died or the lab's sheet.lock is no longer ours while MATLAB ran (MATLAB killed)
    param(
        [Parameter(Mandatory)][string]$CmdFile,        # .m script run with -batch "run('<file>')"
        [Parameter(Mandatory)][string]$LogFile,
        [Parameter(Mandatory)][int]$TimeoutSec,
        [hashtable]$EnvVars = @{},
        [string]$WorkDir = '',
        [switch]$WatchR,
        $LockHolder = $null
    )
    if (-not $WorkDir) { $WorkDir = $script:FR.RepoRoot }
    $res = @{ Exit = $null; TimedOut = $false; RLost = $false; Stopped = $false; LockLost = $false; LockBusy = $false; Secs = 0; Pid = 0 }
    $ownLock = $false
    if (-not $script:FrMatlabLockHandle) {
        if ((Enter-FrMatlabLock -Who 'Invoke-FrMatlab' -WaitMin 0) -ne $true) { $res.LockBusy = $true; return $res }
        $ownLock = $true
    }
    $saved = @{}
    foreach ($k in $EnvVars.Keys) { $saved[$k] = [Environment]::GetEnvironmentVariable($k, 'Process'); [Environment]::SetEnvironmentVariable($k, [string]$EnvVars[$k], 'Process') }
    try {
        if (Test-Path -LiteralPath $LogFile) { Remove-Item -LiteralPath $LogFile -Force -ErrorAction SilentlyContinue }
        $batch = "run('" + $CmdFile.Replace("'", "''") + "')"
        $args = @('-sd', ('"' + $WorkDir + '"'), '-batch', ('"' + $batch + '"'), '-logfile', ('"' + $LogFile + '"'))
        $t0 = Get-Date
        $p = Start-Process -FilePath $script:FR.Matlab -ArgumentList $args -PassThru -WindowStyle Hidden
        $null = $p.Handle   # keep the handle so ExitCode survives
        $res.Pid = $p.Id
        $script:FrCtx.MatlabPid = $p.Id
        # the OS kills the MATLAB tree if this driver dies (job object); and the pid is recorded for a restarted driver
        $jr = [FrKillJob]::Assign($p.Handle)
        if ($jr -ne 0) { Write-FrLog 'WARN' ("MATLAB could not be put in the kill-on-close job object (win32 error {0}); the pid file is the only protection" -f $jr) }
        try { Save-FrJson -Obj ([ordered]@{ pid = $p.Id; startTicks = $p.StartTime.ToUniversalTime().Ticks; driverPid = $PID; started = (Get-Date).ToString('s') }) -Path (Join-Path $script:FR.Root 'matlab.pid.json') } catch { }
        try { $p.PriorityClass = [Diagnostics.ProcessPriorityClass]::BelowNormal } catch { }
        Start-Sleep -Seconds 3
        # the MATLAB.exe worker is a child of the launcher: lower it too
        Get-CimInstance Win32_Process -Filter "ParentProcessId=$($p.Id)" -ErrorAction SilentlyContinue | ForEach-Object {
            try { (Get-Process -Id $_.ProcessId -ErrorAction Stop).PriorityClass = [Diagnostics.ProcessPriorityClass]::BelowNormal } catch { }
        }
        Update-FrHeartbeat -Force
        $rBad = 0; $nextR = (Get-Date).AddSeconds($script:FR.RWatchSec); $nextLk = (Get-Date).AddSeconds(10)
        # The time limit is a STALL limit, not a wall-clock one: on the shared lab desktop a below-normal MATLAB can be starved for
        # hours by other jobs.  Past the limit it is killed only when its process tree used < 3 CPU-s per minute over the last 10 minutes
        # (hung), or at 4 x the limit whatever it does.
        $cpuLog = New-Object Collections.Generic.List[object]; $nextCpu = Get-Date; $busy = $true; $warnedBusy = $false
        while (-not $p.HasExited) {
            Start-Sleep -Seconds 2
            Update-FrHeartbeat
            $el = ((Get-Date) - $t0).TotalSeconds
            if ((Get-Date) -ge $nextCpu) {
                $nextCpu = (Get-Date).AddSeconds(60)
                $cpuNow = Get-FrTreeCpu $p.Id
                $cpuLog.Add(@{ t = Get-Date; cpu = $cpuNow })
                $win = [double]$script:FR.CpuWindowMin
                while ($cpuLog.Count -gt 1 -and ((Get-Date) - $cpuLog[0].t).TotalMinutes -gt ($win + 2)) { $cpuLog.RemoveAt(0) }
                if (((Get-Date) - $cpuLog[0].t).TotalMinutes -ge (0.9 * $win)) { $busy = (($cpuNow - $cpuLog[0].cpu) -gt (3 * $win)) }
            }
            if ($el -gt $TimeoutSec) {
                if (-not $busy -or $el -gt 4 * $TimeoutSec) { $res.TimedOut = $true; break }
                if (-not $warnedBusy) { $warnedBusy = $true; Write-FrLog 'WARN' ("MATLAB is past its time limit ({0} min) but still computing (starved by other jobs?): not killed, hard limit {1} min" -f [int]($TimeoutSec / 60), [int](4 * $TimeoutSec / 60)) }
            }
            if ((Get-FrControl) -eq 'now') { $res.Stopped = $true; break }
            # the sheet lock must stay ours for the whole run (MATLAB writes the master sheet through writeParams / writePreProcX):
            # a holder that exited (its hold limit, a crash) or a lock file that is no longer ours ends the run
            if ($LockHolder -and (Get-Date) -ge $nextLk) {
                $nextLk = (Get-Date).AddSeconds(10)
                $why = Test-FrSheetLockHeld $LockHolder
                if ($why) { $res.LockLost = $true; Write-FrLog 'ERROR' ("the sheet lock is no longer held while MATLAB runs ($why): MATLAB is killed"); break }
            }
            if ($WatchR -and (Get-Date) -ge $nextR) {
                $nextR = (Get-Date).AddSeconds($script:FR.RWatchSec)
                if (Test-FrR 20) { $rBad = 0 } else { $rBad++; Write-FrLog 'WARN' ("R: probe failed while MATLAB runs ({0}/3)" -f $rBad) }
                if ($rBad -ge 3) { $res.RLost = $true; break }
            }
        }
        if (-not $p.HasExited) { Stop-FrTree $p.Id; Start-Sleep -Seconds 2 }
        else { $p.WaitForExit(); $res.Exit = $p.ExitCode }
        $res.Secs = [int]((Get-Date) - $t0).TotalSeconds
    } finally {
        foreach ($k in $saved.Keys) { [Environment]::SetEnvironmentVariable($k, $saved[$k], 'Process') }
        $script:FrCtx.MatlabPid = 0
        if ($ownLock) { Exit-FrMatlabLock }
    }
    return $res
}

# ----------------------------------------------------------------------------------------------- sheet lock (the lab's shared protocol)
function Clear-FrStaleSheetLock {
    # removes a sheet.lock left by a dead rerun1022 process; never touches a lock of another owner
    $f = $script:FR.SheetLockFile
    if (-not (Test-Path -LiteralPath $f)) { return }
    $txt = ''
    try { $txt = (Get-Content -LiteralPath $f -ErrorAction Stop | Select-Object -First 1) } catch { return }
    if ($txt -match '^rerun1022 \S+ pid=(\d+)') {
        $holder = [int]$Matches[1]
        if (-not (Get-Process -Id $holder -ErrorAction SilentlyContinue)) {
            Remove-Item -LiteralPath $f -Force -ErrorAction SilentlyContinue
            Write-FrLog 'WARN' "removed a stale sheet.lock of a dead rerun1022 process (pid $holder)"
        }
    }
}
function Initialize-FrSheetLockScript {
    # The lab's withSheetLock.ps1 is another job's file (E:\claudeWork\u1012).  At driver start a copy is kept under <Root>\locklib;
    # Get-FrSheetLockScript falls back to it if the original ever disappears.  Returns 'original' | 'snapshot' | 'missing'.
    $o = $script:FR.SheetLockScript; $s = $script:FR.SheetLockSnap
    if (Test-Path -LiteralPath $o) {
        try {
            $d = Split-Path -Parent $s
            if (-not (Test-Path -LiteralPath $d)) { New-Item -ItemType Directory -Force -Path $d | Out-Null }
            if (-not (Test-Path -LiteralPath $s) -or (Get-FileHash -LiteralPath $o -Algorithm SHA256).Hash -ne (Get-FileHash -LiteralPath $s -Algorithm SHA256).Hash) {
                Copy-Item -LiteralPath $o -Destination $s -Force
                Write-FrLog 'INFO' "sheet-lock script snapshot refreshed: $s"
            }
        } catch { Write-FrLog 'WARN' ("sheet-lock script snapshot not written: " + $_.Exception.Message) }
        return 'original'
    }
    if (Test-Path -LiteralPath $s) { return 'snapshot' }
    return 'missing'
}
function Get-FrSheetLockScript {
    # the script that takes the lab's lock: the original, else the snapshot; neither = FRLOCKSCRIPT (the driver halts: with no lock
    # script nothing may write the master sheet, and retrying cannot help)
    $o = $script:FR.SheetLockScript; $s = $script:FR.SheetLockSnap
    if (Test-Path -LiteralPath $o) { return $o }
    if (Test-Path -LiteralPath $s) {
        if (-not $script:FrWarnedLockSnap) { $script:FrWarnedLockSnap = $true; Write-FrLog 'WARN' "the lab's lock script $o is gone - using the snapshot $s" }
        return $s
    }
    throw ("FRLOCKSCRIPT: the sheet-lock script {0} is missing and there is no snapshot ({1}) - the master sheet cannot be written safely" -f $o, $s)
}
function Test-FrSheetLockHeld {
    # '' = the sheet lock is still held by this holder ; otherwise the reason it is not (holder exited, lock file gone or taken over)
    param($Holder)
    if (-not $Holder) { return 'no lock holder' }
    if ($Holder.Proc.HasExited) { return 'the holder process has exited' }
    $f = $script:FR.SheetLockFile
    if (-not (Test-Path -LiteralPath $f)) { return 'the lock file is gone' }
    $txt = ''
    try { $txt = [string](Get-Content -LiteralPath $f -ErrorAction Stop | Select-Object -First 1) } catch { return '' }   # unreadable for a moment: not proof of loss
    if ($txt -match '^(\S+) \S+ pid=(\d+)') {
        if ($Matches[1] -ne $script:FR.LockOwner -or [int]$Matches[2] -ne $Holder.Proc.Id) { return ("the lock file now belongs to '{0}' (pid {1})" -f $Matches[1], $Matches[2]) }
    }
    return ''
}
function Enter-FrSheetLock {
    # Starts the holder process: it takes the lab's lock through withSheetLock.ps1 and keeps it until the release file appears
    # (or this process dies, or MaxHoldMin passes).  The driver keeps its heartbeat and its STOP handling while it waits.
    # MaxHoldMin must be >= the longest MATLAB run the caller will start (Invoke-FrMatlab also watches the holder and kills MATLAB
    # when the lock is lost, but a hold limit shorter than the run would end every long run).
    # returns a holder object, or $null when stopped while waiting / the holder could not get the lock.
    param([int]$WaitMin = 360, [int]$MaxHoldMin = 240)
    $lockScript = Get-FrSheetLockScript          # throws FRLOCKSCRIPT when there is none
    Clear-FrStaleSheetLock
    $tok = [guid]::NewGuid().ToString('N').Substring(0, 8)
    $ack = Join-Path $script:FR.Cmd "lock_$tok.ack"
    $rel = Join-Path $script:FR.Cmd "lock_$tok.release"
    $hold = Join-Path $script:FR.Here 'fr_lockholder.ps1'
    $argl = @('-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass', '-File', ('"' + $hold + '"'),
        '-LockScript', ('"' + $lockScript + '"'), '-Owner', $script:FR.LockOwner, '-WaitMin', $WaitMin,
        '-Ack', ('"' + $ack + '"'), '-Release', ('"' + $rel + '"'), '-ParentPid', $PID, '-MaxHoldMin', $MaxHoldMin)
    $p = Start-Process -FilePath 'powershell.exe' -ArgumentList $argl -PassThru -WindowStyle Hidden
    $null = $p.Handle
    $t0 = Get-Date
    while (-not (Test-Path -LiteralPath $ack)) {
        Start-Sleep -Milliseconds 700
        Update-FrHeartbeat
        if ($p.HasExited) { Write-FrLog 'ERROR' 'sheet-lock holder exited before it got the lock'; return $null }
        $c = Get-FrControl
        if ($c -eq 'now' -or $c -eq 'stop') { Exit-FrSheetLock ([pscustomobject]@{ Proc = $p; Release = $rel; Ack = $ack }); return $null }
        if (((Get-Date) - $t0).TotalMinutes -gt ($WaitMin + 2)) { Stop-FrTree $p.Id; return $null }
        Set-FrCtx -Extra ("waiting for the sheet lock {0} s" -f [int]((Get-Date) - $t0).TotalSeconds)
    }
    Set-FrCtx -Extra ''
    return [pscustomobject]@{ Proc = $p; Release = $rel; Ack = $ack; Since = Get-Date; MaxHoldMin = $MaxHoldMin }
}
function Exit-FrSheetLock {
    param($Holder)
    if (-not $Holder) { return }
    try { Set-Content -LiteralPath $Holder.Release -Value 'release' -Encoding ASCII } catch { }
    $t0 = Get-Date
    while (-not $Holder.Proc.HasExited -and ((Get-Date) - $t0).TotalSeconds -lt 30) { Start-Sleep -Milliseconds 300 }
    if (-not $Holder.Proc.HasExited) { Stop-FrTree $Holder.Proc.Id; Clear-FrStaleSheetLock }
    Remove-Item -LiteralPath $Holder.Ack, $Holder.Release -Force -ErrorAction SilentlyContinue
}

# ----------------------------------------------------------------------------------------------- misc
function Resolve-FrGit {
    # git.exe: the PATH of this process first (a process created through WMI can have another PATH than the ssh logon), then the usual
    # install folders.  '' = not found.
    if ($script:FrGit -and (Test-Path -LiteralPath $script:FrGit)) { return $script:FrGit }
    $cand = @()
    $c = Get-Command git.exe -ErrorAction SilentlyContinue
    if ($c) { $cand += $c.Source }
    $cand += 'C:\Program Files\Git\cmd\git.exe', 'C:\Program Files\Git\bin\git.exe', 'C:\Program Files (x86)\Git\cmd\git.exe'
    foreach ($g in $cand) { if ($g -and (Test-Path -LiteralPath $g)) { $script:FrGit = $g; return $g } }
    return ''
}
function Get-FrRepoHead {
    # @{ Ok; Head; Dirty; Error } of the lab repo.  The driver refuses to run code that changes under it, so a git that cannot be run is
    # NOT "no change": Ok = $false and the caller refuses to start / pauses.  Head is only ever a 40-hex commit id.
    $r = @{ Ok = $false; Head = ''; Dirty = $false; Error = '' }
    $git = Resolve-FrGit
    if (-not $git) { $r.Error = 'git.exe not found (PATH of this process and the usual install folders)'; return $r }
    $repo = $script:FR.RepoRoot
    # the driver runs with $ErrorActionPreference = 'Stop', under which any stderr line of a native command (a harmless git warning
    # included) becomes a terminating error: judge git by its exit code and its stdout only
    $eap = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
    try {
        $h = (& $git -C $repo rev-parse HEAD 2>$null)
        if ($LASTEXITCODE -ne 0) { $r.Error = "git rev-parse HEAD failed in $repo (exit $LASTEXITCODE)"; return $r }
        $h = ([string]($h | Select-Object -First 1)).Trim()
        if ($h -notmatch '^[0-9a-f]{40}$') { $r.Error = "git rev-parse HEAD gave '$h', not a commit id"; return $r }
        $d = (& $git -C $repo status --porcelain --untracked-files=no 2>$null)
        if ($LASTEXITCODE -ne 0) { $r.Error = "git status failed in $repo (exit $LASTEXITCODE)"; return $r }
        $r.Head = $h; $r.Dirty = [bool]($d | Where-Object { $_ }); $r.Ok = $true
    } catch { $r.Error = 'git could not be run: ' + $_.Exception.Message }
    finally { $ErrorActionPreference = $eap }
    return $r
}
function Get-FrFreeMemGB { return [double]((Get-CimInstance Win32_OperatingSystem).FreePhysicalMemory / 1MB) }
function ConvertTo-FrKeyName { param([string]$Task, [string]$Id) return ("{0}__{1}" -f $Task, $Id) }
function Resolve-FrScratchPath {
    # maps a canonical R: path into a scratch universe (identity for the real one)
    param([string]$Path, $U)
    if ($U.Scratch -and $Path.StartsWith($script:FR.CanonLC, [StringComparison]::OrdinalIgnoreCase)) { return ($U.LabCommon + $Path.Substring($script:FR.CanonLC.Length)) }
    return $Path
}

# fr_driver.ps1 - the lab-side driver of the full EEG rerun.  Runs on the lab desktop, DETACHED from any ssh session (started by
# fr_launch.ps1 through WMI Win32_Process.Create), strictly one final and one MATLAB at a time at below-normal priority.
#
#   fr_driver.ps1 -Manifest E:\claudeWork\rerun1022\manifest.csv [-Set validation] [-Keys a,b] [-GapSec 45] [-HonorGates] ...
#
# Resumable: the state of every final is in <Root>\state\<key>.json (see fr_final.ps1 for the state machine and the resume rule).
# Controls (files in <Root>\control\): STOP (finish the current final, then exit), STOP_NOW (kill MATLAB now; the final is restored
# at the next start), PAUSE (hold before the next final), GATE_OPEN (opens the validation gate, see below).
# Heartbeat: <Root>\heartbeat.json.  Status table: <Root>\state\status.csv.  Failure list: <Root>\failures.csv.  Log: <Root>\logs\driver.log.
#
# THE VALIDATION GATE is persistent.  The manifest marks the last row of the validation set (gateAfter = 1).  While <Root>\control\GATE_OPEN
# does not exist, no row AFTER that row (by manifest order) is started - not in this process, not after a restart, not after a reboot of
# the lab desktop: the gate is read from the files at every start and before every row.  It is armed by the first start with -HonorGates
# (which writes <Root>\gate.json; every later start of the same root honours it whatever its arguments) and, for the REAL universe,
# also whenever the manifest has a gate row, unless -NoGate.  Whoever has read compare\summary.csv creates GATE_OPEN
# (home: fr_start.ps1 -Continue); the file stays, so the gate does not close again.  A -Scratch driver ignores the gate unless -HonorGates.
[CmdletBinding()]
param(
    [string]$Manifest = 'E:\claudeWork\rerun1022\manifest.csv',
    [string]$Root = 'E:\claudeWork\rerun1022',
    [string]$RepoRoot = 'E:\GitHub\zlp-main',
    [string]$BackupRoot = 'E:\reprocBackup_261022',
    [string]$Set = '',                 # run only this manifest set (validation | sniff | breath | test ...)
    [string]$Keys = '',                # or only these keys (comma separated)
    [int]$Threads = 4,
    [int]$GapSec = 45,                 # lock-free pause between finals (other jobs can take the sheet lock)
    [int]$MaxConsecutiveFailures = 4,  # circuit breaker (failed finals)
    [int]$MaxConsecutiveDecisions = 8, # a separate, larger breaker for needsDecision finals in a row (a systematic cause)
    [int]$RWatchSec = 45,
    [string]$SheetLockScript = '',     # tests only: another copy of withSheetLock.ps1
    [string]$SheetLockFile = '',       # tests only: its lock file
    [string]$SecretDir = '',           # default <Root>\secret (a test with another Root points it at the real one)
    [string]$MatlabLockFile = 'E:\claudeWork\rerun1022\matlab.lock',   # the machine-wide MATLAB lock (shared by the real and the scratch universe)
    [int]$MatlabLockWaitMin = 720,     # how long a final waits for the machine MATLAB lock (another driver / a foreground row)
    [double]$MinFreeE_GB = 40,
    [double]$MinFreeR_GB = 60,
    [double]$MinFreeMem_GB = 16,
    [switch]$HonorGates,               # arm the validation gate (persistent: gate.json); no row after the gate row starts until control\GATE_OPEN exists
    [switch]$NoGate,                   # ignore the gate (tests, or a deliberate full start)
    [switch]$RetryFailed,              # put failed and needsDecision finals back to pending
    [switch]$AllowCodeChange,          # do not pause when the repo HEAD changes / is dirty; start even when git cannot be run
    [switch]$KeepCredential,           # do not delete the credential blob when the batch finishes
    [switch]$NoPrune,                  # never delete a verified-redundant E: backup to make room (default: prune only when space is short)
    [switch]$PlanOnly,                 # print the plan and exit
    [switch]$Scratch,                  # run the loop in a SCRATCH universe (copies on E:, staging sheet, no lock) - see fr_scratch.ps1
    [string]$ScratchRoot = 'E:\claudeWork\rerun1022\scratch',
    [switch]$Console                   # echo the log to the console (foreground tests)
)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'fr_lib.ps1')
. (Join-Path $PSScriptRoot 'fr_final.ps1')
. (Join-Path $PSScriptRoot 'fr_scratch.ps1')
if ($Scratch) {
    if (-not $SecretDir) { $SecretDir = Join-Path $Root 'secret' }      # the real credential; the scratch root has none
    $Root = $ScratchRoot; $BackupRoot = Join-Path $ScratchRoot 'backup'
}
$FR = Initialize-Fr -Root $Root -RepoRoot $RepoRoot -BackupRoot $BackupRoot -Threads $Threads -MinFreeE_GB $MinFreeE_GB -MinFreeR_GB $MinFreeR_GB -MinFreeMem_GB $MinFreeMem_GB -RWatchSec $RWatchSec -SecretDir $SecretDir -SheetLockScript $SheetLockScript -SheetLockFile $SheetLockFile -MatlabLockFile $MatlabLockFile -MatlabLockWaitMin $MatlabLockWaitMin
$script:FrConsole = [bool]$Console
$U = if ($Scratch) { New-FrUniverse 'scratch' -ScratchRoot $ScratchRoot } else { New-FrUniverse 'real' }

# ------------------------------------------------------------------ the plan
$rows = @(Import-Csv -LiteralPath $Manifest | Sort-Object { [double]$_.order })
$sel = $rows
if ($Set) { $sel = @($sel | Where-Object { $_.set -eq $Set }) }
if ($Keys) { $kl = $Keys.Split(',') | ForEach-Object { $_.Trim() }; $sel = @($sel | Where-Object { $kl -contains $_.key }) }
if ($PlanOnly) {
    $sel | Format-Table order, set, key, enabled, timeoutMin, gateAfter -AutoSize | Out-String -Width 200
    Write-Output ("{0} rows ({1} enabled)" -f $sel.Count, @($sel | Where-Object { $_.enabled -ne '0' }).Count)
    return
}

# ------------------------------------------------------------------ one driver at a time (an OS-held exclusive file handle)
$lockPath = Join-Path $FR.Root 'driver.lock'
try { $script:FrLockHandle = [IO.File]::Open($lockPath, 'OpenOrCreate', 'ReadWrite', 'None') }
catch { Write-Output 'ANOTHER DRIVER IS ALREADY RUNNING (driver.lock is held) - exiting'; exit 3 }
$pidInfo = [ordered]@{ pid = $PID; start = (Get-Process -Id $PID).StartTime.ToString('s'); startTicks = (Get-Process -Id $PID).StartTime.ToUniversalTime().Ticks; manifest = $Manifest; set = $Set; keys = $Keys; universe = $U.Name }
Save-FrJson -Obj $pidInfo -Path (Join-Path $FR.Root 'driver.pid.json')
Remove-Item -LiteralPath (Join-Path $FR.Control 'FINISHED') -Force -ErrorAction SilentlyContinue

function Exit-Driver {
    param([string]$StateName, [string]$Msg, [int]$Code = 0)
    Write-FrLog 'INFO' ("driver exit: {0} - {1}" -f $StateName, $Msg)
    Set-FrCtx -State $StateName -Key '' -Step '' -Extra $Msg
    try { [void](Update-FrStatus $rows $U) } catch { }
    Update-FrHeartbeat -Force
    Exit-FrMatlabLock
    if ($script:FrLockHandle) { $script:FrLockHandle.Dispose(); $script:FrLockHandle = $null }
    exit $Code
}

try {
    Write-FrLog 'INFO' ("=== driver start pid={0} universe={1} manifest={2} set='{3}' keys='{4}' gap={5}s threads={6} ===" -f $PID, $U.Name, $Manifest, $Set, $Keys, $GapSec, $Threads)
    Set-FrCtx -State 'starting'
    # ---- the code-freeze guard: git must work (a guard that cannot see the repo is no guard), and the repo must be clean
    $head = Get-FrRepoHead
    if (-not $head.Ok -and -not $AllowCodeChange) { Exit-Driver 'refused' ("git cannot be run for $($FR.RepoRoot): $($head.Error) - the code-freeze guard would be blind; fix git (PATH of the launching process) or start with -AllowCodeChange") 4 }
    $script:FrCtx.Head = $head.Head
    if ($head.Ok -and $head.Dirty -and -not $AllowCodeChange) { Exit-Driver 'refused' ("the repo $($FR.RepoRoot) has uncommitted changes to tracked files - commit them or start with -AllowCodeChange") 4 }
    Write-FrLog 'INFO' ("code: {0} head {1}{2}" -f $FR.RepoRoot, $(if ($head.Ok) { $head.Head } else { '(git unavailable, -AllowCodeChange)' }), $(if ($head.Ok -and $head.Dirty) { ' DIRTY (-AllowCodeChange)' } else { '' }))
    # ---- the sheet-lock script (real universe): the lab's withSheetLock.ps1, or the snapshot kept from an earlier start
    if ($U.UseLock) {
        $ls = Initialize-FrSheetLockScript
        if ($ls -eq 'missing') { Exit-Driver 'refused' ("the sheet-lock script $($FR.SheetLockScript) does not exist and there is no snapshot ($($FR.SheetLockSnap)): the master sheet cannot be written safely") 4 }
        Write-FrLog 'INFO' ("sheet-lock script: {0}" -f $ls)
    }
    Clear-FrStaleSheetLock
    Stop-FrOrphanMatlab
    $mls = Get-FrMatlabLockState
    if ($mls.Held) { Write-FrLog 'INFO' ("machine MATLAB lock is held by {0} (pid {1}): finals will wait for it" -f $mls.Info.who, $mls.Info.pid) }

    # R: first (every final needs it)
    if (-not (Wait-FrR)) { Exit-Driver 'stopped' 'stopped while waiting for R:' 0 }

    # ---- the validation gate: its state is read from the files (persistent across restarts and reboots)
    $gateFile = Join-Path $FR.Root 'gate.json'
    $gateOpenFile = Join-Path $FR.Control 'GATE_OPEN'
    $gateRow = $rows | Where-Object { $_.gateAfter -eq '1' } | Select-Object -First 1
    $gateOrder = $(if ($gateRow) { [double]$gateRow.order } else { [double]::NaN })
    $gateActive = $false
    if ($gateRow -and -not $NoGate) {
        if ($HonorGates -or (Test-Path -LiteralPath $gateFile)) { $gateActive = $true }
        elseif (-not $Scratch) { $gateActive = $true }            # the real universe: the gate is the default
    }
    if ($gateActive) {
        $gj = Read-FrJson $gateFile
        if (-not $gj) { Save-FrJson -Obj ([ordered]@{ created = (Get-Date -Format s); gateKey = $gateRow.key; gateOrder = $gateOrder; manifest = $Manifest; openedAt = '' }) -Path $gateFile }
        Write-FrLog 'INFO' ("validation gate: ARMED at manifest row {0} ({1}); control\GATE_OPEN {2}" -f $gateRow.order, $gateRow.key, $(if (Test-Path -LiteralPath $gateOpenFile) { 'EXISTS - the gate is open' } else { 'absent - rows after the gate row will not start' }))
    } elseif ($gateRow) { Write-FrLog 'INFO' ("validation gate: not armed ({0})" -f $(if ($NoGate) { '-NoGate' } else { 'scratch universe without -HonorGates' })) }
    else { Write-FrLog 'INFO' 'validation gate: the manifest has no gate row' }

    # the work list: finals left mid-way first (they are restored and redone), then the rest in manifest order
    $work = @($sel | Where-Object { $_.enabled -ne '0' })
    $midway = New-Object Collections.Generic.List[object]; $rest = New-Object Collections.Generic.List[object]
    foreach ($r in $work) {
        $s = Read-FrJson (Join-Path $U.State ($r.key + '.json'))
        $stn = if ($s) { [string]$s.state } else { 'pending' }
        if ($RetryFailed -and ($stn -eq 'failed' -or $stn -eq 'needsDecision')) {
            $o = Get-FrState (Join-Path $U.State ($r.key + '.json')) $r
            $o['attempts'] = 0; $o['interruptions'] = 0; $o['attemptOpen'] = $false
            Set-FrStateName $o (Join-Path $U.State ($r.key + '.json')) 'backedUp' ("$stn final put back by -RetryFailed (original is in place)")
            $stn = 'backedUp'
        }
        if (@('moved', 'running', 'restoring') -contains $stn) { $midway.Add($r) } else { $rest.Add($r) }
    }
    $queue = New-Object Collections.Generic.List[object]
    foreach ($r in $midway) { $queue.Add($r) }
    foreach ($r in $rest) { $queue.Add($r) }
    $counts = Update-FrStatus $rows $U
    Write-FrLog 'INFO' ("plan: {0} rows in this run ({1} mid-way); counts: {2}" -f $queue.Count, $midway.Count, (($counts.GetEnumerator() | ForEach-Object { "$($_.Key)=$($_.Value)" }) -join ' '))

    $consecFail = 0; $consecDecision = 0; $stuck = 0; $crash = @{}
    $i = 0
    while ($i -lt $queue.Count) {
        $row = $queue[$i]
        # ---- controls
        $c = Get-FrControl
        if ($c -eq 'now' -or $c -eq 'stop') { Exit-Driver 'stopped' "control file $c" 0 }
        if ($c -eq 'pause') {
            Set-FrCtx -State 'paused' -Key '' -Step '' -Extra 'control\PAUSE present'
            while ((Get-FrControl) -eq 'pause') { Update-FrHeartbeat; Start-Sleep -Seconds 5 }
            continue
        }
        $sp = Join-Path $U.State ($row.key + '.json')
        $s = Read-FrJson $sp
        $stn = if ($s) { [string]$s.state } else { 'pending' }
        if ($stn -eq 'done' -or $stn -eq 'failed' -or $stn -eq 'needsDecision') { $i++; continue }

        # ---- the validation gate: nothing after the gate row starts until control\GATE_OPEN exists (read from the file every time)
        if ($gateActive -and [double]$row.order -gt $gateOrder -and -not (Test-Path -LiteralPath $gateOpenFile)) {
            $nf = 0; $fl = Join-Path $FR.Root 'failures.csv'
            if (Test-Path -LiteralPath $fl) { try { $nf = @(Import-Csv -LiteralPath $fl).Count } catch { } }
            Set-Content -LiteralPath (Join-Path $FR.Control 'GATE_WAIT') -Value (Get-Date -Format s)
            Write-FrLog 'INFO' ("validation gate: next row {0} (order {1}) is behind the gate; waiting for control\GATE_OPEN ({2} failure(s) so far)" -f $row.key, $row.order, $nf)
            Set-FrCtx -State 'gate' -Key '' -Step '' -Extra ("validation gate closed ({0} failure(s) so far): check compare\summary.csv, then fr_start.ps1 -Continue (creates control\GATE_OPEN)" -f $nf)
            while (-not (Test-Path -LiteralPath $gateOpenFile)) { if (Start-FrSleep 10) { break } }
            if (Test-Path -LiteralPath $gateOpenFile) {
                Remove-Item -LiteralPath (Join-Path $FR.Control 'GATE_WAIT') -Force -ErrorAction SilentlyContinue
                Write-FrLog 'INFO' 'validation gate: control\GATE_OPEN found - the gate is open'
                $gj = Read-FrJson $gateFile
                if ($gj) { $o = [ordered]@{}; foreach ($pp in $gj.PSObject.Properties) { $o[$pp.Name] = $pp.Value }; $o['openedAt'] = (Get-Date -Format s); try { Save-FrJson -Obj $o -Path $gateFile } catch { } }
            }
            continue          # re-read the controls (a STOP while waiting ends the driver at the top of the loop)
        }

        # ---- code must not change under a running batch (and git must keep working)
        if (-not $AllowCodeChange) {
            $h = Get-FrRepoHead
            if (-not $h.Ok -or $h.Head -ne $script:FrCtx.Head -or $h.Dirty) {
                $why = if (-not $h.Ok) { "git cannot be run: $($h.Error)" } else { "repo changed (HEAD {0} dirty={1}); waiting for it to return to {2}" -f $h.Head.Substring(0, 8), $h.Dirty, ([string]$script:FrCtx.Head).Substring(0, 8) }
                Set-FrCtx -State 'pausedCode' -Key '' -Step '' -Extra $why
                Write-FrLog 'WARN' $why
                if (Start-FrSleep 120) { continue }
                continue
            }
        }
        # ---- machine headroom
        $mem = Get-FrFreeMemGB
        if ($mem -lt $FR.MinFreeMem_GB) {
            Set-FrCtx -State 'waitMem' -Key '' -Step '' -Extra ("free memory {0:N0} GB < {1:N0}" -f $mem, $FR.MinFreeMem_GB)
            if (Start-FrSleep 60) { continue }
            continue
        }
        if (-not (Wait-FrR)) { Exit-Driver 'stopped' 'stopped while waiting for R:' 0 }

        # ---- room for the next backup (verified-redundant backups of done finals are pruned only when space is short)
        if (-not $NoPrune) { try { [void](Invoke-FrPrune $U ([double]$row.finalBytes / 1GB * 1.1 + $FR.MinFreeE_GB + 10)) } catch { Write-FrLog 'WARN' ("prune: " + $_.Exception.Message) } }

        # ---- the final
        Set-FrCtx -State 'working' -Key $row.key -Step 'start' -Extra ''
        $out = $null
        try {
            if ($Scratch) { Initialize-FrScratchRow -Row $row -U $U }
            $out = Invoke-FrFinal -Row $row -U $U
        }
        catch {
            $crash[$row.key] = 1 + [int]$crash[$row.key]
            Write-FrLog 'ERROR' ("{0}: driver exception ({1}x): {2}" -f $row.key, $crash[$row.key], $_.Exception.Message)
            Write-FrLog 'ERROR' ($_.ScriptStackTrace -replace '[\r\n]+', ' | ')
            if ($crash[$row.key] -ge 3) { Exit-Driver 'halted' ("repeated driver exception on $($row.key): $($_.Exception.Message)") 5 }
            Start-FrSleep 30 | Out-Null
            continue
        }
        [void](Update-FrStatus $rows $U)
        switch ($out.Outcome) {
            'done' {
                $consecFail = 0; $consecDecision = 0; $stuck = 0; $i++
                Write-FrLog 'INFO' ("{0}: DONE" -f $row.key)
            }
            'failed' {
                $consecFail++; $i++
                Write-FrLog 'ERROR' ("{0}: FAILED (original restored): {1}" -f $row.key, $out.Msg)
                if ($consecFail -ge $MaxConsecutiveFailures) { Exit-Driver 'halted' ("circuit breaker: $consecFail finals failed in a row (last: $($row.key)) - look at failures.csv, then restart") 6 }
            }
            'needsDecision' {
                # a deterministic refusal (the respiration carry): the original is back, a retry cannot change it - move on, a person decides later
                $consecDecision++; $i++
                Write-FrLog 'ERROR' ("{0}: NEEDS A DECISION (original restored, not retried): {1}" -f $row.key, $out.Msg)
                if ($consecDecision -ge $MaxConsecutiveDecisions) { Exit-Driver 'halted' ("$consecDecision finals in a row need a decision (last: $($row.key)) - a systematic cause? look at failures.csv (class needsDecision), then restart") 6 }
            }
            'infra' {
                Write-FrLog 'WARN' ("{0}: interrupted ({1}) - waiting for R:, then redoing" -f $row.key, $out.Msg)
                if (-not (Wait-FrR)) { Exit-Driver 'stopped' 'stopped while waiting for R:' 0 }
                [void](Start-FrSleep 60)    # a transient file-system error must not be retried in a tight loop
            }
            'stop' { Exit-Driver 'stopped' ("stop during $($row.key): $($out.Msg)") 0 }
            'halt' { Exit-Driver 'halted' ("$($row.key): $($out.Msg)") 8 }
            'disk' {
                Write-FrLog 'WARN' ("{0}: {1}" -f $row.key, $out.Msg)
                Set-FrCtx -State 'pausedDisk' -Key $row.key -Step 'backup' -Extra $out.Msg
                if (Start-FrSleep 300) { continue }
            }
            'stuck' {
                $stuck++
                Write-FrLog 'ERROR' ("{0}: restore did not complete ({1}/5): {2}" -f $row.key, $stuck, $out.Msg)
                if ($stuck -ge 5) { Exit-Driver 'halted' ("restore of $($row.key) keeps failing - the original is in superseded_261022 and E:\reprocBackup_261022: $($out.Msg)") 7 }
                if (-not (Wait-FrR)) { Exit-Driver 'stopped' 'stopped while waiting for R:' 0 }
            }
        }
        # ---- lock-free gap before the next final
        $c = Get-FrControl
        if ($c -ne 'now' -and $c -ne 'stop' -and $i -lt $queue.Count -and $out.Outcome -ne 'infra') {
            Set-FrCtx -State 'gap' -Key '' -Step '' -Extra ''
            [void](Start-FrSleep $GapSec)
        }
    }
    # ------------------------------------------------------------------ the batch is finished
    $counts = Update-FrStatus $rows $U
    $left = 0; foreach ($k in @('pending', 'backedUp', 'moved', 'running', 'verified', 'restoring')) { if ($counts.Contains($k)) { $left += [int]$counts[$k] } }
    if ($left -eq 0 -and -not $Set -and -not $Keys) {
        New-Item -ItemType File -Force -Path (Join-Path $FR.Control 'FINISHED') | Out-Null
        if ($KeepCredential) { Write-FrLog 'INFO' 'credential blob kept (-KeepCredential)' }
        elseif ($FR.Secret -ne (Join-Path $FR.Root 'secret')) { Write-FrLog 'INFO' "credential blob kept: -SecretDir ($($FR.Secret)) is not this root's own secret folder" }
        else {
            Get-ChildItem -LiteralPath $FR.Secret -Filter 'netid*' -ErrorAction SilentlyContinue | Remove-Item -Force -ErrorAction SilentlyContinue
            Write-FrLog 'INFO' 'credential blob deleted (batch finished)'
        }
        Exit-Driver 'finished' ("batch finished: " + (($counts.GetEnumerator() | ForEach-Object { "$($_.Key)=$($_.Value)" }) -join ' ')) 0
    }
    Exit-Driver 'idle' ("this run is finished (rows left in the manifest: $left): " + (($counts.GetEnumerator() | ForEach-Object { "$($_.Key)=$($_.Value)" }) -join ' ')) 0
} catch {
    Write-FrLog 'ERROR' ("driver crashed: " + $_.Exception.Message)
    Write-FrLog 'ERROR' ($_.ScriptStackTrace -replace '[\r\n]+', ' | ')
    Set-FrCtx -State 'crashed' -Extra $_.Exception.Message
    Exit-FrMatlabLock
    if ($script:FrLockHandle) { $script:FrLockHandle.Dispose() }
    exit 9
}

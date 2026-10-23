# fr_final.ps1 - the per-final state machine of the full-EEG-rerun driver (dot-source after fr_lib.ps1).
#
#   pending -> backedUp -> moved -> running -> verified -> done            (the normal path)
#                  ^         |          |            |
#                  |         +----------+------------+--> restoring --> backedUp (retry / interrupted)
#                  |                                           |
#                  |                                           +--> failed          (two failed attempts)
#                  |                                           +--> needsDecision   (a deterministic error: no retry)
#
#   pending   nothing done.
#   backedUp  the final is copied to <Backup>\<task>\<sessID>\ and SHA-256 verified (source hashed while it is read,
#             the copy hashed again); the original is still in place.
#   moved     the original was MOVED (renamed, never deleted) to <preProc>\superseded_261022\ ; the live path is empty.
#   running   makeOutDat + main (one MATLAB, below normal priority, sheet lock held) have been started / have run; then
#             the verification MATLAB (fr_verify.m) runs and compares the new final with the superseded one.
#   verified  every check passed; the old-vs-new comparison is saved under compare\.
#   done      recorded.   failed: two attempts failed - the previous final is back in place and listed in failures.csv.
#   needsDecision  the run failed in a way that a second try cannot change (the respiration carry refuses the previous final: a
#             channel / polarity / sample-count / section mismatch, a "not the same recording" test, a missing previous final; a
#             precondition of the driver itself): the previous final is back in place, the row is listed in failures.csv with
#             class needsDecision and the driver MOVES ON.  Needs a person (a sheet fix, a decision); fr_start -RetryFailed
#             puts it back.  Not counted by the circuit breaker (a separate, larger limit stops a systematic cause).
#   restoring transitional: the live path is being put back to the original (failure, retry, interrupted driver).
#
# One MATLAB at a time on the whole machine: a final takes the machine-wide MATLAB lock (fr_lib.ps1, Enter-FrMatlabLock) BEFORE the
# sheet lock and the move and holds it for the run and the verification - the real and the scratch universe share it.
#
# RESUME RULE (decision): a final found in 'moved' or 'running' or 'restoring' at (re)start was interrupted (driver or MATLAB
# killed, VPN/R: drop, reboot).  It is RESTORED to the original (the newer partial file, if any, is moved aside to
# superseded_261022\failed_<time>_<name>, never deleted; the original is hash-checked against the backup) and the state goes
# back to 'backedUp'; the final is then redone from the move step.  An interruption does not count as a failed attempt: the state
# file carries attemptOpen (set when the attempt is counted at the move, cleared when its outcome is known), and the resume gives
# the attempt back (attempts - 1) when it finds it open; at most 6 interruptions per final.  'verified' resumes by recording 'done'.
#
# A "universe" ($U) says where everything lives: the real one (R: finals, the master sheet under the lab lock) or a scratch
# one (copies on E:, a staging sheet, no lock) - the state machine is identical.

$script:FrEnvClear = @('ZLP_ADMIN_XLSX', 'ZLP_ADMED_XLSX', 'ZLP_SEP_ECHEM', 'ZLP_CARRY_FROM', 'ZLP_CARRY_SHA256',
    'ZLP_ALLOW_GUESS_RUN', 'ZLP_ALLOW_GUESS_RUN_ALL', 'ZLP_MAIN_ONLY', 'ZLP_MAKEOUTDAT_ONLY', 'FR_CFGDIR')

# A failure whose first message line matches this is DETERMINISTIC (the respiration carry refuses the previous final: the same
# inputs refuse again, a retry only repeats the tens of minutes of the shared core): the row becomes needsDecision.  The mains print
# "fail for <id>: <message>" (no error identifier), so the carry messages are recognised by their wording (shared/carry*.m).
$script:FrDeterministicRx = '(?i)carry(Resp|Open|Finish)\w*|ZLP_CARRY|P\.carryFrom|previous final|not the same recording|exactly one struct variable|targTrace rows|rsp rows.{0,200}carried|no usable correlation'

function New-FrUniverse {
    param([string]$Name = 'real', [string]$ScratchRoot = '')
    $FR = $script:FR
    if ($Name -eq 'real') {
        return @{ Name = 'real'; Scratch = $false; State = $FR.State; Backup = $FR.BackupRoot; Compare = $FR.Compare; Logs = $FR.Logs
            LabCommon = $null; CfgDir = ''; UseLock = $true; Root = $FR.Root }
    }
    $sr = $ScratchRoot
    foreach ($d in 'state', 'backup', 'compare', 'logs', 'cfg', 'lc') { New-Item -ItemType Directory -Force -Path (Join-Path $sr $d) | Out-Null }
    return @{ Name = 'scratch'; Scratch = $true; State = (Join-Path $sr 'state'); Backup = (Join-Path $sr 'backup'); Compare = (Join-Path $sr 'compare')
        Logs = (Join-Path $sr 'logs'); LabCommon = ((Join-Path $sr 'lc') + '\'); CfgDir = (Join-Path $sr 'cfg'); UseLock = $false; Root = $sr }
}

function Get-FrPaths {
    param($Row, $U)
    $live = Resolve-FrScratchPath $Row.finalPath $U
    $pre = Split-Path -Parent $live
    $name = Split-Path -Leaf $live
    $sup = Join-Path $pre $script:FR.Superseded
    $bd = Join-Path (Join-Path $U.Backup $Row.task) $Row.sessID
    return @{ Live = $live; PreProc = $pre; Name = $name; SupDir = $sup; SupPath = (Join-Path $sup $name); BackupDir = $bd; BackupPath = (Join-Path $bd $name) }
}

# ----------------------------------------------------------------------------------------------- state files
function Get-FrState {
    param([string]$Path, $Row)
    $o = Read-FrJson $Path
    $h = [ordered]@{}
    if ($o) { foreach ($p in $o.PSObject.Properties) { $h[$p.Name] = $p.Value } }
    else {
        $h['key'] = $Row.key; $h['task'] = $Row.task; $h['sessID'] = $Row.sessID; $h['order'] = $Row.order; $h['set'] = $Row.set
        $h['state'] = 'pending'; $h['attempts'] = 0; $h['interruptions'] = 0; $h['restores'] = 0
        $h['finalPath'] = $Row.finalPath; $h['created'] = (Get-Date -Format s); $h['history'] = @()
    }
    return $h
}
function Save-FrState {
    param($St, [string]$Path)
    $St['updated'] = (Get-Date -Format s)
    Save-FrJson -Obj $St -Path $Path -Depth 6
}
function Set-FrStateName {
    param($St, [string]$Path, [string]$Name, [string]$Note = '')
    $St['state'] = $Name
    $St['history'] = @($St['history']) + ('{0}|{1}|{2}' -f (Get-Date -Format s), $Name, $Note)
    Save-FrState $St $Path
    Write-FrLog 'INFO' ("{0}: -> {1} {2}" -f $St['key'], $Name, $Note)
}

# ----------------------------------------------------------------------------------------------- status.csv
function Update-FrStatus {
    # merges the manifest with the state files: <State>\status.csv, and the counts for the heartbeat
    param($Rows, $U)
    $out = New-Object Collections.Generic.List[object]
    $counts = [ordered]@{ pending = 0; backedUp = 0; moved = 0; running = 0; verified = 0; done = 0; failed = 0; needsDecision = 0; restoring = 0; disabled = 0 }
    foreach ($r in $Rows) {
        $p = Join-Path $U.State ($r.key + '.json')
        $s = Read-FrJson $p
        $enabled = ($r.enabled -ne '0')
        $name = if ($s) { [string]$s.state } else { 'pending' }
        if (-not $enabled -and $name -eq 'pending') { $name = 'disabled' }
        if ($counts.Contains($name)) { $counts[$name]++ } else { $counts[$name] = 1 }
        $out.Add([pscustomobject][ordered]@{
                order = $r.order; set = $r.set; key = $r.key; task = $r.task; sessID = $r.sessID; enabled = $r.enabled; state = $name
                attempts = $(if ($s) { $s.attempts } else { 0 }); interruptions = $(if ($s) { $s.interruptions } else { 0 })
                started = $(if ($s) { $s.runStart } else { '' }); ended = $(if ($s) { $s.doneAt } else { '' }); secs = $(if ($s) { $s.runSecs } else { '' })
                oldMB = $(if ($s -and $s.backupBytes) { [math]::Round([double]$s.backupBytes / 1MB, 1) } else { '' })
                newMB = $(if ($s -and $s.newBytes) { [math]::Round([double]$s.newBytes / 1MB, 1) } else { '' })
                verify = $(if ($s) { $s.verifyOk } else { '' }); warnings = $(if ($s) { $s.verifyWarnings } else { '' }); reason = $(if ($s) { $s.lastError } else { '' })
            })
    }
    try { $out | Export-Csv -LiteralPath (Join-Path $U.State 'status.csv') -NoTypeInformation -Encoding UTF8 } catch { }
    $script:FrCtx.Counts = $counts
    return $counts
}
function Add-FrFailure {
    # one line per failed / needsDecision final.  The columns are fixed: a failures.csv written by an older version of this file
    # (other columns) is renamed aside instead of being appended to with misaligned columns.
    param($U, $Row, $St, [string]$Reason, [string]$Log, [string]$Class = 'failed')
    $f = Join-Path $U.Root 'failures.csv'
    $cols = 'time,key,task,sessID,attempts,class,reason,log'
    if (Test-Path -LiteralPath $f) {
        $h = ''; try { $h = ((Get-Content -LiteralPath $f -TotalCount 1) -replace '"', '') } catch { }
        if ($h -ne $cols) { Move-Item -LiteralPath $f -Destination (Join-Path $U.Root ('failures_{0}.csv' -f (Get-Date -Format 'yyyyMMdd_HHmmss'))) -Force }
    }
    $line = [pscustomobject][ordered]@{ time = (Get-Date -Format s); key = $Row.key; task = $Row.task; sessID = $Row.sessID; attempts = $St['attempts']; class = $Class; reason = ($Reason -replace '[\r\n]+', ' ' -replace '"', "'"); log = $Log }
    $line | Export-Csv -LiteralPath $f -NoTypeInformation -Append -Encoding UTF8
}

# ----------------------------------------------------------------------------------------------- backup
function Step-FrBackup {
    param($Row, $U, $St, $Paths)
    Set-FrCtx -Step 'backup'
    $info = Get-FrFileInfo $Paths.Live
    if (-not $info.Exists) { throw "FRPRE: the final does not exist: $($Paths.Live)" }
    $gb = [double]$info.Length / 1GB
    New-Item -ItemType Directory -Force -Path $Paths.BackupDir | Out-Null
    $eFree = Get-FrFreeGB $Paths.BackupDir
    if ($eFree -lt ($gb * 1.1 + $script:FR.MinFreeE_GB)) { throw ("FRDISK: backup volume has {0:N0} GB free, needs {1:N0}" -f $eFree, ($gb * 1.1 + $script:FR.MinFreeE_GB)) }
    if (-not $U.Scratch) {
        $rFree = Get-FrFreeGB $Paths.PreProc
        if ($rFree -lt ($gb * 2 + $script:FR.MinFreeR_GB)) { throw ("FRDISK: R: has {0:N0} GB free, needs {1:N0}" -f $rFree, ($gb * 2 + $script:FR.MinFreeR_GB)) }
    }
    # resume: a verified backup of this very file is already there
    if ($St['backupSha'] -and (Test-Path -LiteralPath $Paths.BackupPath)) {
        $b = Get-Item -LiteralPath $Paths.BackupPath
        if ($b.Length -eq [long]$St['backupBytes'] -and $info.Length -eq $b.Length) {
            $h = Get-FrHash $Paths.Live
            if ($h -eq $St['backupSha']) { Write-FrLog 'INFO' "$($Row.key): existing backup re-confirmed"; return }
        }
    }
    $t0 = Get-Date
    $sha = Copy-FrHash $Paths.Live $Paths.BackupPath -Overwrite       # the backup lives on the local volume
    $dstSha = Get-FrHash $Paths.BackupPath
    if ($sha -ne $dstSha) { throw "FRBACKUP: SHA-256 of the copy differs from what was read ($sha vs $dstSha)" }
    $info2 = Get-FrFileInfo $Paths.Live
    if ($info2.Length -ne $info.Length -or $info2.MTimeUtc -ne $info.MTimeUtc) { throw 'FRBACKUP: the final changed while it was being copied' }
    $St['backupSha'] = $sha; $St['backupBytes'] = $info.Length; $St['backupMTimeUtc'] = $info.MTimeUtc.ToString('o'); $St['backupPath'] = $Paths.BackupPath
    $meta = [ordered]@{ source = $Paths.Live; backup = $Paths.BackupPath; sha256 = $sha; bytes = $info.Length; sourceMTimeUtc = $info.MTimeUtc.ToString('o'); backedUpAt = (Get-Date -Format s); key = $Row.key }
    Save-FrJson -Obj $meta -Path ($Paths.BackupPath + '.backup.json')
    Write-FrLog 'INFO' ("{0}: backup {1:N0} MB, sha256 {2}..., {3} s" -f $Row.key, ($info.Length / 1MB), $sha.Substring(0, 12), [int]((Get-Date) - $t0).TotalSeconds)
}

# ----------------------------------------------------------------------------------------------- move
function Step-FrMove {
    param($Row, $U, $St, $Paths)
    Set-FrCtx -Step 'move'
    $info = Get-FrFileInfo $Paths.Live
    if (-not $info.Exists) {
        # a move completed by an earlier call that was interrupted before the state was saved
        $s2 = Get-FrFileInfo $Paths.SupPath
        if ($s2.Exists -and $s2.Length -eq [long]$St['backupBytes']) { $St['supPath'] = $Paths.SupPath; return }
        throw "FRPRE: the final to move is missing: $($Paths.Live)"
    }
    if ($info.Length -ne [long]$St['backupBytes']) { throw 'FRPRE-CHANGED: the final changed after its backup' }
    # the size can stay the same when another job rewrites the final between the backup and the move (the wait for the sheet lock can
    # take hours): compare the modification time with the one measured at the backup too
    if ($St['backupMTimeUtc']) {
        $bm = [DateTime]::Parse([string]$St['backupMTimeUtc']).ToUniversalTime()
        if ([Math]::Abs(($info.MTimeUtc - $bm).TotalSeconds) -gt 2) { throw 'FRPRE-CHANGED: the final was modified after its backup' }
    }
    New-FrDir $Paths.SupDir
    if (Test-FrPath $Paths.SupPath) {
        Move-FrFile $Paths.SupPath (Join-Path $Paths.SupDir ('old_{0}_{1}' -f (Get-Date -Format 'yyyyMMddHHmmss'), $Paths.Name))
    }
    Move-FrFile $Paths.Live $Paths.SupPath
    if (Test-FrPath $Paths.Live) { throw 'FRPRE: the live path is still occupied after the move' }
    $i2 = Get-FrFileInfo $Paths.SupPath
    if (-not $i2.Exists -or $i2.Length -ne [long]$St['backupBytes']) { throw 'FRPRE: the superseded copy is missing or has the wrong size' }
    $St['supPath'] = $Paths.SupPath
}

# ----------------------------------------------------------------------------------------------- restore
function Step-FrRestore {
    # puts the original back at the live path (the newer file, if any, is moved aside - never deleted)
    param($Row, $U, $St, $Paths, [string]$Why)
    Set-FrCtx -Step 'restore'
    Write-FrLog 'WARN' ("{0}: restore ({1})" -f $Row.key, $Why)
    if (-not (Wait-FrR)) { throw 'FRRESTORE: R: is not available (stop requested or credential refused)' }
    $ts = Get-Date -Format 'yyyyMMddHHmmss'
    $live = Get-FrFileInfo $Paths.Live
    $sup = Get-FrFileInfo $Paths.SupPath
    $want = [long]$St['backupBytes']
    $liveIsOriginal = $false
    if ($live.Exists -and -not $sup.Exists -and $live.Length -eq $want) {
        # never moved (or already restored): is the live file the backed-up one?
        if ((Get-FrHash $Paths.Live) -eq $St['backupSha']) { $liveIsOriginal = $true }
    }
    if (-not $liveIsOriginal) {
        if ($live.Exists) {
            New-FrDir $Paths.SupDir
            Move-FrFile $Paths.Live (Join-Path $Paths.SupDir ('failed_{0}_{1}' -f $ts, $Paths.Name))
        }
        if ($sup.Exists) { Move-FrFile $Paths.SupPath $Paths.Live }
        else {
            Write-FrLog 'ERROR' ("{0}: no superseded copy - restoring from the E: backup" -f $Row.key)
            [void](Copy-FrHash $Paths.BackupPath $Paths.Live)
        }
    }
    $now = Get-FrFileInfo $Paths.Live
    $ok = $now.Exists -and $now.Length -eq $want -and ((Get-FrHash $Paths.Live) -eq $St['backupSha'])
    if (-not $ok) {
        Write-FrLog 'ERROR' ("{0}: restored file does not match the backup - copying the backup over it" -f $Row.key)
        if ($now.Exists) { Move-FrFile $Paths.Live (Join-Path $Paths.SupDir ('badrestore_{0}_{1}' -f $ts, $Paths.Name)) }
        [void](Copy-FrHash $Paths.BackupPath $Paths.Live)
        $now = Get-FrFileInfo $Paths.Live
        if (-not ($now.Exists -and $now.Length -eq $want -and ((Get-FrHash $Paths.Live) -eq $St['backupSha']))) { throw 'FRRESTORE-CRITICAL: the live final does not match its backup after the restore' }
    }
    $St['restores'] = [int]$St['restores'] + 1
    $St['lastRestore'] = (Get-Date -Format s)
}

# ----------------------------------------------------------------------------------------------- MATLAB command files
function New-FrRunCmd {
    param($Row, $U, [string]$Path)
    $FR = $script:FR; $repo = $FR.RepoRoot
    $q = { param($s) ([string]$s).Replace("'", "''") }
    $mk = ''; if ($Row.makeOutDat) { $mk = Join-Path $repo ($Row.makeOutDat -replace '/', '\') }
    $mn = Join-Path $repo ($Row.main -replace '/', '\')
    $L = New-Object Collections.Generic.List[string]
    $L.Add("% fr_run_cmd.m - generated by fr_final.ps1 for $($Row.key) at $(Get-Date -Format s); do not edit")
    $L.Add("cd('$(& $q $repo)');")
    $L.Add("addpath(genpath('$(& $q $repo)'));")
    if ($U.CfgDir) { $L.Add("addpath('$(& $q $U.CfgDir)');   % scratch universe: labPaths_local.m first on the path") }
    $L.Add("set(0,'DefaultFigureVisible','off');")
    $L.Add("try, maxNumCompThreads($($FR.Threads)); catch, end")
    $L.Add("fprintf('FR_BEGIN %s\n', datestr(now,31));")
    $L.Add("fprintf('FR_LABPATHS %s\n', which('labPaths'));")
    $L.Add("frL = labPaths(); fprintf('FR_LABCOMMON %s\nFR_ADMINXLSX %s\nFR_REPO %s\n', frL.labCommon, frL.adminXlsx, frL.repo);")
    $L.Add("try")
    if ($mk) {
        if ($mk -match 'breathingTask_makeOutDat') { $L.Add("    try, parpool('local',1); catch, end   % breathingTask_makeOutDat has a parfor: one worker") }
        $L.Add("    run('$(& $q $mk)');")
        $L.Add("    fprintf('FR_PHASE_DONE makeOutDat\n');")
    }
    $L.Add("    run('$(& $q $mn)');")
    $L.Add("    fprintf('FR_PHASE_DONE main\n');")
    $L.Add("catch frME")
    $L.Add("    fprintf('FR_ERROR_ID %s\n', frME.identifier);")
    $L.Add("    fprintf('FR_ERROR %s\n', getReport(frME,'extended','hyperlinks','off'));")
    $L.Add("    exit(2);")
    $L.Add("end")
    $L.Add("fprintf('FR_END\n');")
    [IO.File]::WriteAllText($Path, ($L -join "`r`n") + "`r`n", (New-Object Text.UTF8Encoding($false)))
}
function New-FrVerifyCmd {
    param($ArgsJson, $U, [string]$Path)
    $FR = $script:FR; $repo = $FR.RepoRoot
    $q = { param($s) ([string]$s).Replace("'", "''") }
    $L = New-Object Collections.Generic.List[string]
    $L.Add("% fr_verify_cmd.m - generated by fr_final.ps1 at $(Get-Date -Format s); do not edit")
    $L.Add("cd('$(& $q $repo)');")
    $L.Add("addpath(genpath('$(& $q $repo)'));")
    if ($U.CfgDir) { $L.Add("addpath('$(& $q $U.CfgDir)');") }
    $L.Add("set(0,'DefaultFigureVisible','off');")
    $L.Add("try, maxNumCompThreads($($FR.Threads)); catch, end")
    $L.Add("try")
    $L.Add("    fr_verify('$(& $q $ArgsJson)');")
    $L.Add("catch frME")
    $L.Add("    fprintf('FR_VERIFY_ERROR %s\n', getReport(frME,'extended','hyperlinks','off'));")
    $L.Add("    exit(2);")
    $L.Add("end")
    [IO.File]::WriteAllText($Path, ($L -join "`r`n") + "`r`n", (New-Object Text.UTF8Encoding($false)))
}
function Get-FrLogVerdict {
    # @{ Ok; Reason; PhaseMk; PhaseMain; Det }  Det = the failure is deterministic (a carry refusal, see $script:FrDeterministicRx)
    param([string]$LogFile, [bool]$NeedMk)
    $v = @{ Ok = $false; Reason = ''; PhaseMk = $false; PhaseMain = $false; Det = $false }
    if (-not (Test-Path -LiteralPath $LogFile)) { $v.Reason = 'no MATLAB log was written'; return $v }
    $txt = Get-Content -LiteralPath $LogFile -Raw
    if (-not $txt) { $txt = '' }
    $v.PhaseMk = ($txt -match 'FR_PHASE_DONE makeOutDat'); $v.PhaseMain = ($txt -match 'FR_PHASE_DONE main')
    $m = [regex]::Match($txt, '(?im)^(fail for [^\r\n]*|FR_ERROR[^\r\n]*|SKIP \(guess[^\r\n]*|Error using [^\r\n]*|finished file detected[^\r\n]*|Done with [^\r\n]*)')
    if ($m.Success) {
        $tail = $txt.Substring($m.Index, [Math]::Min(600, $txt.Length - $m.Index)) -replace '[\r\n]+', ' | '
        $v.Reason = $tail
        # deterministic: the first message line names the carry (the mains print only the message), or an uncaught error carries a carry identifier
        if ($m.Value -match $script:FrDeterministicRx) { $v.Det = $true }
        $id = [regex]::Match($txt, '(?m)^FR_ERROR_ID (\S+)')
        if ($id.Success -and $id.Groups[1].Value -match '^carry(Resp|Open|Finish)\w*:') { $v.Det = $true }
        return $v
    }
    if ($NeedMk -and -not $v.PhaseMk) { $v.Reason = 'makeOutDat did not finish (no FR_PHASE_DONE makeOutDat)'; return $v }
    if (-not $v.PhaseMain) { $v.Reason = 'the main did not finish (no FR_PHASE_DONE main)'; return $v }
    $v.Ok = $true
    return $v
}

# ----------------------------------------------------------------------------------------------- master-sheet snapshot + backup
function Test-FrXlsxIntact {
    # an .xlsx is a zip with xl/workbook.xml: a MATLAB killed in the middle of a sheet write can leave anything else
    param([string]$Path)
    try {
        Add-Type -AssemblyName System.IO.Compression.FileSystem -ErrorAction SilentlyContinue
        $z = [IO.Compression.ZipFile]::OpenRead($Path)
        try { return [bool]($z.Entries | Where-Object { $_.FullName -eq 'xl/workbook.xml' }) } finally { $z.Dispose() }
    } catch { return $false }
}
function Step-FrSheetBefore {
    # Called with the sheet lock held, right before the final is moved (so a failure here needs no restore):
    #  - the snapshot of the master sheet that fr_verify compares with the "after" snapshot (<sheettmp>\<key>.before.xlsx);
    #  - real universe: the lab-convention backup of the master in Admin\Data\sheetBackups\ (one per final, taken under the lock
    #    immediately before this final's MATLAB run - the run is the only thing that writes the sheet):
    #        dataTracking_backup_<yyMMdd_HHmmss>_rerun1022.xlsx
    # Real universe: any failure throws (FRFS / FRSTALL = infra, retried later) - MATLAB never runs without a backup of the sheet it
    # may write.  Scratch universe: the snapshot is best effort (the staging sheet is a throw-away copy).
    param($Row, $U, $St)
    $FR = $script:FR
    $sheet = Resolve-FrScratchPath $FR.RProbe $U
    $before = Join-Path $FR.SheetTmp ($Row.key + '.before.xlsx'); $after = Join-Path $FR.SheetTmp ($Row.key + '.after.xlsx')
    Remove-Item -LiteralPath $before, $after -Force -ErrorAction SilentlyContinue
    $St['sheetBefore'] = ''; $St['sheetAfter'] = ''
    if ($U.Scratch) {
        try { Wait-FrJob ([FrJob]::Copy($sheet, $before)) 90 'sheet snapshot (before)' | Out-Null; $St['sheetBefore'] = $before }
        catch { Write-FrLog 'WARN' "sheet snapshot before: $($_.Exception.Message)" }
        return
    }
    Wait-FrJob ([FrJob]::Copy($sheet, $before)) 90 'sheet snapshot (before)' | Out-Null
    if (-not (Test-FrXlsxIntact $before)) { throw 'FRFS: the master sheet snapshot taken before the run is not a readable xlsx - nothing is run' }
    $name = 'dataTracking_backup_{0}_rerun1022.xlsx' -f (Get-Date -Format 'yyMMdd_HHmmss')
    $dst = Join-Path $FR.SheetBackupDir $name
    New-FrDir $FR.SheetBackupDir
    $sha = Copy-FrHash $before $dst
    $i = Get-FrFileInfo $dst
    if (-not $i.Exists -or $i.Length -ne (Get-Item -LiteralPath $before).Length) { throw "FRFS: the master-sheet backup $dst is missing or has the wrong size" }
    $St['sheetBefore'] = $before; $St['sheetBackup'] = $dst; $St['sheetBackupSha'] = $sha
    Write-FrLog 'INFO' ("{0}: master sheet backed up -> {1}" -f $Row.key, $name)
}

# ----------------------------------------------------------------------------------------------- run + verify
function Step-FrRun {
    # returns @{ Kind = 'ok'|'fail'|'infra'|'stop'; Msg; Det }   Det = a deterministic failure (needsDecision, no retry)
    param($Row, $U, $St, $Paths, $Holder = $null)
    $FR = $script:FR
    Set-FrCtx -Step 'run'
    if ($Row.task -like '__noop*') { return (Invoke-FrNoopRun $Row $U $St $Paths $Holder) }
    # MATLAB writes the master sheet (writeParams / writePreProcX): never without the lab's sheet lock
    if (-not $U.Scratch -and -not $Holder) { return @{ Kind = 'infra'; Msg = 'FRLOCK: refusing to run MATLAB in the real universe without the sheet lock'; Det = $false } }
    $att = [int]$St['attempts']
    $log = Join-Path $U.Logs ('{0}.a{1}.run.log' -f $Row.key, $att)
    $cmd = Join-Path $FR.Cmd 'fr_run_cmd.m'
    New-FrRunCmd $Row $U $cmd
    $envv = @{}
    foreach ($k in $script:FrEnvClear) { $envv[$k] = '' }
    $envv['FR_THREADS'] = [string]$FR.Threads
    $envv['ZLP_MAKEOUTDAT_ONLY'] = $Row.sessID; $envv['ZLP_MAIN_ONLY'] = $Row.sessID
    if ($U.CfgDir) { $envv['FR_CFGDIR'] = $U.CfgDir }
    foreach ($kv in ([string]$Row.envFlags -split ';')) { if ($kv -match '^\s*([A-Za-z0-9_]+)=(.*)$') { $envv[$Matches[1]] = $Matches[2].Trim() } }
    if ($Row.carry -ne '0') { $envv['ZLP_CARRY_FROM'] = $Paths.SupPath; $envv['ZLP_CARRY_SHA256'] = [string]$St['backupSha'] }
    $timeout = [int]([double]$Row.timeoutMin * 60)
    if ($timeout -lt 600) { $timeout = 600 }

    # the caller holds the sheet lock (real universe) for the whole move + run; the "before" snapshot / backup was taken by
    # Step-FrSheetBefore inside it
    $sheet = Resolve-FrScratchPath $FR.RProbe $U
    $before = [string]$St['sheetBefore']
    $after = Join-Path $FR.SheetTmp ($Row.key + '.after.xlsx')
    Remove-Item -LiteralPath $after -Force -ErrorAction SilentlyContinue
    $St['runStart'] = (Get-Date -Format s); $St['runStartUtc'] = [DateTime]::UtcNow.ToString('o'); Save-FrState $St (Join-Path $U.State ($Row.key + '.json'))
    $res = Invoke-FrMatlab -CmdFile $cmd -LogFile $log -TimeoutSec $timeout -EnvVars $envv -WatchR:(-not $U.Scratch) -LockHolder $Holder
    try { Wait-FrJob ([FrJob]::Copy($sheet, $after)) 90 'sheet snapshot (after)' | Out-Null } catch { Write-FrLog 'WARN' "sheet snapshot after: $($_.Exception.Message)"; $after = '' }
    $St['runEnd'] = (Get-Date -Format s); $St['runSecs'] = $res.Secs; $St['matlabExit'] = $res.Exit; $St['runLog'] = $log
    $St['sheetAfter'] = $after
    # a MATLAB that was killed (timeout, STOP_NOW, R: loss, lost lock) may have been in the middle of a sheet write: the master must still
    # be a readable xlsx; if not it is put back from the snapshot taken under the lock before the run (or the lab-convention backup)
    if (-not $U.Scratch -and $after) {
        if (-not (Test-FrXlsxIntact $after)) {
            Write-FrLog 'ERROR' "$($Row.key): the master sheet is not a readable xlsx after the run - restoring it from the snapshot taken before the run"
            $okRestore = $false
            foreach ($src in @($before, [string]$St['sheetBackup'])) {
                if ($src -and (Test-Path -LiteralPath $src) -and (Test-FrXlsxIntact $src)) {
                    Wait-FrJob ([FrJob]::Copy($src, $sheet)) 90 'sheet restore' | Out-Null
                    $okRestore = $true; $St['sheetRestored'] = (Get-Date -Format s) + ' from ' + $src; break
                }
            }
            if (-not $okRestore) { throw 'FRSHEET-CRITICAL: the master sheet is damaged and no intact backup could be restored - look at Admin\Data\sheetBackups' }
        }
    }
    if ($res.LockBusy) { return @{ Kind = 'infra'; Msg = 'another MATLAB of this family holds the machine lock (nothing was started)'; Det = $false } }
    if ($res.Stopped) { return @{ Kind = 'stop'; Msg = 'STOP_NOW while MATLAB ran'; Det = $false } }
    if ($res.RLost) { return @{ Kind = 'infra'; Msg = 'R: was lost while MATLAB ran (killed; will redo)'; Det = $false } }
    if ($res.LockLost) { return @{ Kind = 'infra'; Msg = 'the sheet lock was lost while MATLAB ran (killed; will redo)'; Det = $false } }
    if ($res.TimedOut) {
        if (-not (Test-FrR 30)) { return @{ Kind = 'infra'; Msg = 'timeout with R: unavailable (killed; will redo)'; Det = $false } }
        return @{ Kind = 'fail'; Msg = ("MATLAB timed out after {0} min" -f [int]($timeout / 60)); Det = $false }
    }
    $v = Get-FrLogVerdict $log ([bool]$Row.makeOutDat)
    if (-not $v.Ok) { return @{ Kind = 'fail'; Msg = $v.Reason; Det = [bool]$v.Det } }
    # the pipeline must have run on the paths this universe means (a stray labPaths_local.m / ZLP_ADMIN_XLSX would silently redirect it)
    $lt = Get-Content -LiteralPath $log -Raw
    $wantLC = if ($U.Scratch) { $U.LabCommon } else { $FR.CanonLC }
    $mLC = [regex]::Match($lt, '(?m)^FR_LABCOMMON (.*?)\s*$'); $mXL = [regex]::Match($lt, '(?m)^FR_ADMINXLSX (.*?)\s*$'); $mRP = [regex]::Match($lt, '(?m)^FR_REPO (.*?)\s*$')
    if (-not $mLC.Success -or $mLC.Groups[1].Value -ne $wantLC) { return @{ Kind = 'fail'; Msg = ("labPaths().labCommon was '{0}', expected '{1}'" -f $mLC.Groups[1].Value, $wantLC); Det = $false } }
    if (-not $mXL.Success -or $mXL.Groups[1].Value -ne $sheet) { return @{ Kind = 'fail'; Msg = ("labPaths().adminXlsx was '{0}', expected '{1}'" -f $mXL.Groups[1].Value, $sheet); Det = $false } }
    if (-not $mRP.Success -or $mRP.Groups[1].Value.TrimEnd([char]92) -ne $FR.RepoRoot.TrimEnd([char]92)) { return @{ Kind = 'fail'; Msg = ("the pipeline ran from '{0}', expected '{1}'" -f $mRP.Groups[1].Value, $FR.RepoRoot); Det = $false } }
    if ($res.Exit -ne 0) { return @{ Kind = 'fail'; Msg = ("MATLAB exit code {0}" -f $res.Exit); Det = $false } }
    $info = Get-FrFileInfo $Paths.Live
    if (-not $info.Exists) { return @{ Kind = 'fail'; Msg = 'the pipeline finished but wrote no final at the expected path (the id filter matched nothing, or the main wrote another file name)'; Det = $false } }
    # written by THIS run: newer than the original (the file server's clock is the reference for both) and not older than the run
    # start by more than the possible clock offset between the server and this machine
    $started = [DateTime]::Parse([string]$St['runStartUtc']).ToUniversalTime()
    $origM = [DateTime]::Parse([string]$St['backupMTimeUtc']).ToUniversalTime()
    if ($info.MTimeUtc -le $origM -or $info.MTimeUtc -lt $started.AddMinutes(-10)) { return @{ Kind = 'fail'; Msg = 'the file at the expected path was not written by this run (its time is not newer than the original)'; Det = $false } }
    $St['newBytes'] = $info.Length
    return @{ Kind = 'ok'; Msg = ''; Det = $false }
}
function Step-FrVerify {
    param($Row, $U, $St, $Paths)
    $FR = $script:FR
    Set-FrCtx -Step 'verify'
    if ($Row.task -like '__noop*') { return (Invoke-FrNoopVerify $Row $U $St $Paths) }
    $att = [int]$St['attempts']
    $res = Join-Path $U.Compare ($Row.key + '.verify.json')
    Remove-Item -LiteralPath $res -Force -ErrorAction SilentlyContinue
    $a = [ordered]@{
        key = $Row.key; task = $Row.task; sessID = $Row.sessID; newFinal = $Paths.Live; oldFinal = $Paths.SupPath
        hasEEG = ([string]$Row.hasEEG -ne '0'); carry = ($Row.carry -ne '0'); paramSource = $Row.paramSource
        resultJson = $res; compareDir = $U.Compare; sheetBefore = [string]$St['sheetBefore']; sheetAfter = [string]$St['sheetAfter']
        runStartUtc = [string]$St['runStartUtc']; scratch = [bool]$U.Scratch; backupSha = [string]$St['backupSha']
        sepEchem = ([string]$Row.envFlags -match 'ZLP_SEP_ECHEM=1')
    }
    $aj = Join-Path $FR.Cmd 'fr_verify_args.json'
    Save-FrJson -Obj $a -Path $aj
    $cmd = Join-Path $FR.Cmd 'fr_verify_cmd.m'
    New-FrVerifyCmd $aj $U $cmd
    $log = Join-Path $U.Logs ('{0}.a{1}.verify.log' -f $Row.key, $att)
    $r = Invoke-FrMatlab -CmdFile $cmd -LogFile $log -TimeoutSec 3600 -WatchR:(-not $U.Scratch)
    if ($r.LockBusy) { return @{ Kind = 'infra'; Msg = 'another MATLAB of this family holds the machine lock (nothing was started)'; Det = $false } }
    if ($r.Stopped) { return @{ Kind = 'stop'; Msg = 'STOP_NOW during the verification'; Det = $false } }
    if ($r.RLost) { return @{ Kind = 'infra'; Msg = 'R: was lost during the verification'; Det = $false } }
    $j = Read-FrJson $res
    if (-not $j) {
        if ($r.TimedOut -and -not (Test-FrR 30)) { return @{ Kind = 'infra'; Msg = 'verification timed out with R: unavailable'; Det = $false } }
        $why = if ($r.TimedOut) { 'verification timed out' } else { "verification produced no result (MATLAB exit $($r.Exit))" }
        return @{ Kind = 'fail'; Msg = $why; Det = $false }
    }
    $St['verifyOk'] = [bool]$j.ok
    $St['verifyWarnings'] = (@($j.warnings) -join ' ; ')
    $St['compareFile'] = [string]$j.compareFile
    $St['prunable'] = [bool]($j.ok -and $j.carryShaMatch)   # the E: backup is redundant: the carry hashed the superseded copy on R: and it matched
    $St['verifyLog'] = $log
    # a deterministic verdict (the carried respiration does not match the previous final / the carry gate refuses it): a rerun of the same
    # inputs gives the same verdict, so the row is not retried (needsDecision)
    $St['verifyDeterministic'] = [bool]$j.deterministic
    if (-not $j.ok) { return @{ Kind = 'fail'; Msg = ('verification failed: ' + (@($j.failures) -join ' ; ')); Det = [bool]$j.deterministic } }
    return @{ Kind = 'ok'; Msg = ''; Det = $false }
}

# ----------------------------------------------------------------------------------------------- no-op rows (driver / state machine tests)
# Row.task '__noop' ; Row.main = 'noop:<mode>:<sec>' with mode
#   ok | fail | detfail (a deterministic failure: needsDecision, no retry) | dropR | matlabdrop (R: deleted behind a running MATLAB) |
#   matlablock (the sheet-lock holder is killed behind a running MATLAB) | matlab (a plain MATLAB pause) | hang | killdriver (the
#   driver process itself is killed once, mid-run: the next start must give the attempt back)
function Invoke-FrNoopRun {
    param($Row, $U, $St, $Paths, $Holder = $null)
    $parts = ([string]$Row.main).Split(':'); $mode = $parts[1]; $sec = [int]$parts[2]
    $St['runStart'] = (Get-Date -Format s); $St['runStartUtc'] = [DateTime]::UtcNow.ToString('o')
    Write-FrLog 'INFO' ("{0}: no-op run mode={1} {2}s" -f $Row.key, $mode, $sec)
    $t0 = Get-Date
    function Write-NoopFinal { Copy-Item -LiteralPath $Paths.SupPath -Destination ($Paths.Live + '.part') -Force; Add-Content -LiteralPath ($Paths.Live + '.part') -Value ('new-final ' + (Get-Date -Format s)); Move-Item -LiteralPath ($Paths.Live + '.part') -Destination $Paths.Live -Force }
    if ($mode -eq 'hang') {
        $h0 = Get-Date
        while (((Get-Date) - $h0).TotalSeconds -lt $sec) { if (Start-FrSleep 15) { return @{ Kind = 'stop'; Msg = 'stop during no-op hang' } } }
        return @{ Kind = 'fail'; Msg = 'no-op hang finished' }
    }
    if ($mode -eq 'killdriver' -and [int]$St['interruptions'] -eq 0 -and -not $St['killedOnce']) {
        # the state file says 'running' with the attempt open; the driver dies right here (tests the attempt give-back at the restart)
        $St['killedOnce'] = $true; Save-FrState $St (Join-Path $U.State ($Row.key + '.json'))
        Write-FrLog 'WARN' "$($Row.key): no-op test kills the driver process now"
        Stop-Process -Id $PID -Force
        Start-Sleep -Seconds 30
    }
    if ($mode -eq 'matlabdrop' -or $mode -eq 'matlab' -or $mode -eq 'matlablock') {
        # a real MATLAB (pause) with R: deleted behind its back after 12 s: the R: watchdog must notice, kill it and report infra
        # (matlablock: the sheet-lock holder is killed instead: the lock watchdog must notice, kill MATLAB and report infra)
        $cmd = Join-Path $script:FR.Cmd 'fr_noop_cmd.m'
        [IO.File]::WriteAllText($cmd, "fprintf('noop matlab start\n'); pause($sec); fprintf('noop matlab end\n');`r`n")
        if ($mode -eq 'matlabdrop' -and [int]$St['interruptions'] -eq 0) {   # only the first time: the redo after the interruption must run clean
            $dropper = Start-Process -FilePath 'cmd.exe' -ArgumentList '/c', 'ping -n 13 127.0.0.1 >nul & net use R: /delete /y >nul' -PassThru -WindowStyle Hidden
        }
        if ($mode -eq 'matlablock' -and $Holder -and [int]$St['interruptions'] -eq 0) {
            $dropper = Start-Process -FilePath 'cmd.exe' -ArgumentList '/c', ('ping -n 13 127.0.0.1 >nul & taskkill /PID {0} /F >nul' -f $Holder.Proc.Id) -PassThru -WindowStyle Hidden
        }
        $log = Join-Path $U.Logs ($Row.key + '.noop.log')
        $r = Invoke-FrMatlab -CmdFile $cmd -LogFile $log -TimeoutSec ($sec + 120) -WatchR -LockHolder $Holder
        if ($r.LockBusy) { return @{ Kind = 'infra'; Msg = 'another MATLAB of this family holds the machine lock (no-op test)' } }
        if ($r.RLost) { return @{ Kind = 'infra'; Msg = 'R: was lost while MATLAB ran (no-op test)' } }
        if ($r.LockLost) { return @{ Kind = 'infra'; Msg = 'the sheet lock was lost while MATLAB ran (no-op test)' } }
        if ($r.Stopped) { return @{ Kind = 'stop'; Msg = 'stop' } }
    }
    elseif ($mode -eq 'dropR') {
        [void][FrNet]::Cancel('R:')
        Write-FrLog 'WARN' "$($Row.key): no-op test dropped R:"
        if (-not (Wait-FrR)) { return @{ Kind = 'stop'; Msg = 'stop while R: was down' } }
        if (Start-FrSleep $sec) { return @{ Kind = 'stop'; Msg = 'stop' } }
    }
    else { if (Start-FrSleep $sec) { return @{ Kind = 'stop'; Msg = 'stop' } } }
    $St['runEnd'] = (Get-Date -Format s); $St['runSecs'] = [int]((Get-Date) - $t0).TotalSeconds; $St['runLog'] = ''
    $St['sheetBefore'] = ''; $St['sheetAfter'] = ''
    if ($mode -eq 'fail') { return @{ Kind = 'fail'; Msg = 'no-op failure requested' } }
    if ($mode -eq 'detfail') { return @{ Kind = 'fail'; Msg = 'no-op deterministic failure requested (carry refusal stand-in)'; Det = $true } }
    Write-NoopFinal
    $St['newBytes'] = (Get-Item -LiteralPath $Paths.Live).Length
    return @{ Kind = 'ok'; Msg = '' }
}
function Invoke-FrNoopVerify {
    param($Row, $U, $St, $Paths)
    $new = Get-Item -LiteralPath $Paths.Live
    if ($new.Length -le [long]$St['backupBytes']) { return @{ Kind = 'fail'; Msg = 'no-op verify: the new final is not larger than the old one' } }
    $St['verifyOk'] = $true; $St['verifyWarnings'] = ''; $St['compareFile'] = ''
    return @{ Kind = 'ok'; Msg = '' }
}

# ----------------------------------------------------------------------------------------------- backup pruning
function Invoke-FrPrune {
    # Frees E: space when the next backup would not fit: deletes the E: backup copy of finals that are DONE and whose superseded
    # copy on R: was hash-verified by the carry (state 'prunable': outDat.carry.sha256 = the SHA-256 of the backup).  Oldest first.
    # The backup.json record stays; every deletion is logged.  Returns the number of files removed.
    param($U, [double]$NeedFreeGB)
    $free = Get-FrFreeGB $U.Backup
    if ($free -ge $NeedFreeGB) { return 0 }
    $n = 0
    $cands = @(Get-ChildItem -LiteralPath $U.State -Filter '*.json' -ErrorAction SilentlyContinue | ForEach-Object { Read-FrJson $_.FullName } |
            Where-Object { $_ -and $_.state -eq 'done' -and $_.prunable -eq $true -and $_.backupPath -and -not $_.backupPruned } | Sort-Object doneAt)
    foreach ($c in $cands) {
        if ($free -ge $NeedFreeGB) { break }
        if (Test-Path -LiteralPath $c.backupPath) {
            $mb = (Get-Item -LiteralPath $c.backupPath).Length / 1MB
            Remove-Item -LiteralPath $c.backupPath -Force -ErrorAction SilentlyContinue
            Write-FrLog 'WARN' ("E: space short ({0:N0} GB free, need {1:N0}): pruned the verified-redundant backup of {2} ({3:N0} MB)" -f $free, $NeedFreeGB, $c.key, $mb)
            $n++
        }
        $sp = Join-Path $U.State ($c.key + '.json')
        $o = Get-FrState $sp ([pscustomobject]@{ key = $c.key })
        $o['backupPruned'] = (Get-Date -Format s); Save-FrState $o $sp
        $free = Get-FrFreeGB $U.Backup
    }
    return $n
}

# ----------------------------------------------------------------------------------------------- the state machine
function Invoke-FrFinal {
    # Runs (or resumes) one manifest row.
    # Returns @{ Outcome = 'done'|'failed'|'needsDecision'|'infra'|'stop'|'disk'|'stuck'|'halt'; Msg }
    #   needsDecision: a deterministic failure (the carry refuses the previous final): original back in place, no retry, the driver moves on
    #   halt: the driver cannot go on safely (no sheet-lock script, a damaged master sheet): it stops and says why
    param($Row, $U, [int]$MaxAttempts = 2, [int]$MaxInterruptions = 6)
    $FR = $script:FR
    $sp = Join-Path $U.State ($Row.key + '.json')
    $St = Get-FrState $sp $Row
    $paths = Get-FrPaths $Row $U
    if ($St['state'] -eq 'done') { return @{ Outcome = 'done'; Msg = 'already done' } }
    if ($St['state'] -eq 'failed') { return @{ Outcome = 'failed'; Msg = [string]$St['lastError'] } }
    if ($St['state'] -eq 'needsDecision') { return @{ Outcome = 'needsDecision'; Msg = [string]$St['lastError'] } }
    Set-FrCtx -Key $Row.key -State 'final' -Step 'start'
    $St['commit'] = $script:FrCtx.Head
    $St['universe'] = $U.Name
    Save-FrState $St $sp

    try {
        # --- resume rule: anything between 'moved' and 'verified' was interrupted: restore and redo ---
        if (@('moved', 'running', 'restoring') -contains [string]$St['state']) {
            # was the attempt still open (counted at the move, outcome not yet known)?  Then it was interrupted, not failed: give it back.
            # A state file without the marker (older version): moved / running = open, restoring = a failure being undone.
            $wasOpen = if ($St.Contains('attemptOpen')) { [bool]$St['attemptOpen'] } else { [string]$St['state'] -ne 'restoring' }
            Set-FrStateName $St $sp 'restoring' 'found mid-way at start: restoring the original'
            Step-FrRestore $Row $U $St $paths 'found mid-way at (re)start'
            $St['interruptions'] = [int]$St['interruptions'] + 1
            if ($wasOpen) { $St['attempts'] = [Math]::Max(0, [int]$St['attempts'] - 1) }
            $St['attemptOpen'] = $false
            Set-FrStateName $St $sp 'backedUp' ("restored after an interruption (attempts now {0})" -f $St['attempts'])
        }
        if ([string]$St['state'] -eq 'backedUp' -and -not (Get-FrFileInfo $paths.Live).Exists) {
            # the original is not in place although only the backup step is recorded (a move interrupted before its state was saved)
            Set-FrStateName $St $sp 'restoring' 'backedUp but the live final is missing: restoring'
            Step-FrRestore $Row $U $St $paths 'live final missing in state backedUp'
            Set-FrStateName $St $sp 'backedUp' 'restored'
        }
        if ([string]$St['state'] -eq 'verified') {
            $St['doneAt'] = (Get-Date -Format s)
            Set-FrStateName $St $sp 'done' 'resumed from verified'
            return @{ Outcome = 'done'; Msg = '' }
        }
        while ($true) {
            if ([int]$St['interruptions'] -gt $MaxInterruptions) {
                $St['lastError'] = 'too many interruptions'
                Set-FrStateName $St $sp 'failed' 'too many interruptions'
                Add-FrFailure $U $Row $St 'too many interruptions' ''
                return @{ Outcome = 'failed'; Msg = 'too many interruptions' }
            }
            $kind = ''; $msg = ''; $det = $false; $bumped = $false
            try {
                if ([string]$St['state'] -eq 'pending') {
                    Step-FrBackup $Row $U $St $paths
                    Set-FrStateName $St $sp 'backedUp' 'backup verified'
                }
                if ([string]$St['state'] -eq 'backedUp') {
                    $c = Get-FrControl; if ($c -eq 'now' -or $c -eq 'stop') { return @{ Outcome = 'stop'; Msg = 'stop requested before the move' } }
                    # ONE MATLAB at a time on the machine, whatever the universe: the machine lock comes first (before the sheet lock and the
                    # move), is held for the run and the verification, and a wait for it never leaves a final moved or the sheet locked
                    Set-FrCtx -Step 'matlabLock'
                    $mlk = Enter-FrMatlabLock -Who ("{0}:{1}" -f $U.Name, $Row.key)
                    if ($null -eq $mlk) { return @{ Outcome = 'stop'; Msg = 'stop requested while waiting for the machine MATLAB lock' } }
                    if ($mlk -ne $true) { return @{ Outcome = 'infra'; Msg = 'another MATLAB job holds the machine-wide MATLAB lock (one MATLAB at a time); will retry' } }
                    try {
                        # the sheet lock is taken BEFORE the final is moved away: a long wait for another job's lock must never leave a final missing
                        $holder = $null
                        # (no-op test rows never touch the lab's real lock; with a test lock file they take that one)
                        if ($U.UseLock -and -not ($Row.task -like '__noop*' -and $FR.SheetLockFile -eq $FR.RealSheetLockFile)) {
                            Set-FrCtx -Step 'sheetLock'
                            # the hold limit must cover the longest run Invoke-FrMatlab allows (4 x the stall limit, the limit being >= 10 min) + the move
                            $maxHold = [int](4 * [Math]::Max(10, [double]$Row.timeoutMin) + 45)
                            $holder = Enter-FrSheetLock -MaxHoldMin $maxHold
                            if (-not $holder) {
                                $c = Get-FrControl
                                if ($c -eq 'now' -or $c -eq 'stop') { return @{ Outcome = 'stop'; Msg = 'stop requested while waiting for the sheet lock' } }
                                return @{ Outcome = 'infra'; Msg = 'the sheet lock could not be taken (wait timed out or the holder failed); will retry' }
                            }
                            Write-FrLog 'INFO' ("{0}: sheet lock held (hold limit {1} min; the holder and the lock file are watched while MATLAB runs)" -f $Row.key, $maxHold)
                        }
                        try {
                            # under the lock, before anything is moved: the snapshot + the master-sheet backup (real universe: a failure = no run)
                            if (-not ($Row.task -like '__noop*')) { Step-FrSheetBefore $Row $U $St }
                            $St['attempts'] = [int]$St['attempts'] + 1; $bumped = $true
                            $St['attemptOpen'] = $true
                            Step-FrMove $Row $U $St $paths
                            Set-FrStateName $St $sp 'moved' ("attempt $($St['attempts'])")
                            Set-FrStateName $St $sp 'running' 'makeOutDat + main'
                            $r = Step-FrRun $Row $U $St $paths $holder
                        } finally { if ($holder) { Exit-FrSheetLock $holder } }
                        Save-FrState $St $sp
                        $kind = $r.Kind; $msg = $r.Msg; $det = [bool]$r.Det
                        if ($kind -eq 'ok') {
                            $r = Step-FrVerify $Row $U $St $paths
                            Save-FrState $St $sp
                            $kind = $r.Kind; $msg = $r.Msg; $det = [bool]$r.Det
                        }
                    } finally { Exit-FrMatlabLock }
                    $St['attemptOpen'] = $false          # the outcome of this attempt is known
                    if ($kind -eq 'ok') {
                        $St['doneAt'] = (Get-Date -Format s); $St['lastError'] = ''
                        Set-FrStateName $St $sp 'verified' ("ok; warnings: $($St['verifyWarnings'])")
                        $St['restores'] = [int]$St['restores']
                        Set-FrStateName $St $sp 'done' ("{0} s" -f $St['runSecs'])
                        foreach ($tmpf in @([string]$St['sheetBefore'], [string]$St['sheetAfter'])) { if ($tmpf) { Remove-Item -LiteralPath $tmpf -Force -ErrorAction SilentlyContinue } }
                        return @{ Outcome = 'done'; Msg = '' }
                    }
                }
            } catch {
                $em = $_.Exception.Message
                $St['attemptOpen'] = $false              # an exception ends the attempt (the failure handling below decides what it means)
                if ($em -like 'FRDISK:*') { if ($bumped) { $St['attempts'] = [Math]::Max(0, [int]$St['attempts'] - 1) }; return @{ Outcome = 'disk'; Msg = $em } }
                if ($em -like 'FRSTALL:*' -or $em -like 'FRFS:*') { $kind = 'infra'; $msg = $em }
                elseif ($em -like 'FRRESTORE*' -or $em -like 'FRLOCKSCRIPT:*' -or $em -like 'FRSHEET-CRITICAL*') { throw }
                else {
                    $kind = 'fail'; $msg = $em
                    # a precondition of the driver itself that cannot change by itself (the final to back up / move is not there)
                    if ($em -like 'FRPRE:*') { $det = $true }
                }
            }
            # --- the attempt did not succeed: put the original back, then retry / give up ---
            $St['attemptOpen'] = $false
            $St['lastError'] = $msg
            if ([string]$St['state'] -eq 'pending' -and $kind -eq 'fail') { $St['attempts'] = [int]$St['attempts'] + 1 }   # a failing backup must not loop for ever
            if ($msg -like 'FRPRE-CHANGED*') { if ($bumped) { $St['attempts'] = [Math]::Max(0, [int]$St['attempts'] - 1) }; $St['backupSha'] = ''; Set-FrStateName $St $sp 'pending' 'the final changed after its backup: backing it up again'; continue }
            Write-FrLog 'WARN' ("{0}: attempt {1} -> {2}{3}: {4}" -f $Row.key, $St['attempts'], $kind, $(if ($det) { ' (deterministic)' } else { '' }), $msg)
            if (@('moved', 'running') -contains [string]$St['state']) {
                Set-FrStateName $St $sp 'restoring' ("$kind - $msg")
                Step-FrRestore $Row $U $St $paths $msg
            }
            if ($kind -eq 'stop') {
                if ($bumped) { $St['attempts'] = [Math]::Max(0, [int]$St['attempts'] - 1) }      # a stop is not a failed attempt
                Set-FrStateName $St $sp 'backedUp' 'stopped'; return @{ Outcome = 'stop'; Msg = $msg }
            }
            if ($kind -eq 'infra') {
                $St['interruptions'] = [int]$St['interruptions'] + 1
                if ($bumped) { $St['attempts'] = [Math]::Max(0, [int]$St['attempts'] - 1) }      # an interruption is not a failed attempt
                if ([string]$St['state'] -ne 'pending') { Set-FrStateName $St $sp 'backedUp' 'infrastructure interruption' }
                return @{ Outcome = 'infra'; Msg = $msg }
            }
            if ($kind -eq 'fail' -and $det) {
                # the same inputs refuse again: no retry (a retry would repeat the shared core for nothing).  The original is back in
                # place; a person decides (fr_start -RetryFailed puts the row back after the cause is fixed).
                Set-FrStateName $St $sp 'needsDecision' $msg
                Add-FrFailure $U $Row $St $msg ([string]$St['runLog']) 'needsDecision'
                return @{ Outcome = 'needsDecision'; Msg = $msg }
            }
            if ([int]$St['attempts'] -ge $MaxAttempts) {
                Set-FrStateName $St $sp 'failed' $msg
                Add-FrFailure $U $Row $St $msg ([string]$St['runLog']) 'failed'
                return @{ Outcome = 'failed'; Msg = $msg }
            }
            if ([string]$St['state'] -ne 'pending') { Set-FrStateName $St $sp 'backedUp' 'retry after a failed attempt' }
        }
    } catch {
        $em = $_.Exception.Message
        $St['lastError'] = $em
        Save-FrState $St $sp
        if ($em -like 'FRRESTORE*') { Write-FrLog 'ERROR' ("{0}: {1}" -f $Row.key, $em); return @{ Outcome = 'stuck'; Msg = $em } }
        if ($em -like 'FRLOCKSCRIPT:*' -or $em -like 'FRSHEET-CRITICAL*') { Write-FrLog 'ERROR' ("{0}: {1}" -f $Row.key, $em); return @{ Outcome = 'halt'; Msg = $em } }
        if ($em -like 'FRSTALL:*' -or $em -like 'FRFS:*') { return @{ Outcome = 'infra'; Msg = $em } }
        throw
    }
}

function fr_verify(argsJson)
%FR_VERIFY  Verification + old-vs-new comparison of ONE rerun final (the full-EEG-rerun driver, batch/fullRerun).
%
%   fr_verify(argsJson)   argsJson = a JSON file written by fr_final.ps1 with
%       key, task, sessID, newFinal (the live path, just written), oldFinal (the superseded copy), hasEEG, carry,
%       paramSource, resultJson (where to write the result), compareDir, sheetBefore / sheetAfter (snapshots of the master
%       sheet taken under the lock around the run, '' = none), runStartUtc, scratch, sepEchem
%
%   Checks (FAIL = the driver restores the previous final and retries / lists the failure):
%     - the new final loads; fs 500; moreThan1; data/labels consistent; behDat (table) with manOnset (+ finalOnset for the sniff
%       tasks); breath tasks: bmObj, bmFeatures (+ baseEmotion, heartBeats for breathingTask), breathMerge, holds for airPuff
%     - same session, same sample count, same section table (sep) as the previous final
%     - EEG (hasEEG): EEGCleaningInfo.mode 'fixed' (sep: every section), blink IC rule 'frontal' whenever an IC was removed,
%       dataLap sane (common-mode share of its variance < 0.5, dataLapGeometry present) or legitimately empty
%     - carried rows (rsp*, targTrace, rspSelected) sample-identical to the previous final's, outDat.carry.rowsVerified
%     - the carry gate (carryGate below; codeReview M2): the same-recording evidence that the carry recorded
%       (outDat.carry.checks) is ACTED ON, not just stored - the selected respiration channel needs a FINITE correlation
%       (a NaN = flat row / < 100 usable samples fails, it does not pass), >= 0.90 always, >= 0.98 for a previous final saved
%       before the line-noise notch was removed (2026-07-07 22:38, the commit of the notch-free core; the July reprocessing finals start 22:52), and for a previous final saved after it (same processing, so
%       the carried row must EQUAL the rerun's own row) at most 0.1 % of the samples may differ (nDiff).  Weaker evidence
%       (r < 0.995, maxAbsDiff > 5 % of the row's range, an auxiliary row below 0.90, no rspIDX / rspFlip recorded in the
%       previous final) is a WARNING and goes to summary.csv.
%     - the master sheet snapshots: no paramSource cell changed
%   Everything else that differs is recorded as a WARNING and in the comparison, never silently dropped.
%   A failure of the carry class (carried rows changed, carry record missing / unverified / wrong hash, carry gate) is DETERMINISTIC:
%   result.deterministic = true, and the driver does not retry it (the row becomes needsDecision).
%
%   Output: resultJson (ok, deterministic, failures, warnings, summary, compareFile) ; compareDir\<key>.json (the full comparison) ;
%   compareDir\summary.csv (one line per final).  Prints FR_VERIFY_OK / FR_VERIFY_FAIL.
A = jsondecode(fileread(argsJson));
R = struct('ok', false, 'deterministic', false, 'key', A.key, 'failures', {{}}, 'warnings', {{}}, 'compareFile', '', 'time', datestr(now, 31), 'carryShaMatch', false);
fail = {}; warn = {};
detFail = false;       % a failure of the carry class: the same inputs give it again, no retry
C = struct();          % the comparison record
t0 = tic;

% ---- load both finals -------------------------------------------------------------------------------------
try
    [N, vN] = loadFinal(A.newFinal);
catch ME
    R.failures = {['the new final does not load: ' ME.message]};
    finish(A, R, C); return
end
O = []; vO = '';
loadedOld = true;
try
    [O, vO] = loadFinal(A.oldFinal);
catch ME
    loadedOld = false;
    warn{end+1} = ['the previous final does not load, no old-vs-new comparison: ' ME.message]; %#ok<AGROW>
end
C.key = A.key; C.task = A.task; C.sessID = A.sessID; C.newFinal = A.newFinal; C.oldFinal = A.oldFinal;
C.varNew = vN; C.varOld = vO; C.loadSeconds = toc(t0);
fi = dir(A.newFinal); C.newBytes = fi.bytes;
fo = dir(A.oldFinal); if ~isempty(fo), C.oldBytes = fo.bytes; else, C.oldBytes = NaN; end

breathKinds = {'breathingTask', 'EmotionalMovieTask', 'alternating6Blocks', 'pacedBreathing', 'breathingTasks_separate', ...
    'breathingTasks_separate_echem', 'respiratorySweep', 'airPuff'};
sniffKinds = {'cueTask', 'cueTask3', 'threshTask', 'O15', 'detectNoOdor'};
isBreath = any(strcmp(A.task, breathKinds));
isSniff = any(strcmp(A.task, sniffKinds));
isSep = startsWith(A.task, 'breathingTasks_separate');

% ---- structure of the new final (CLAUDE.md sec. 8 + sec. 6) ----------------------------------------------------
req = @(f) isfield(N, f);
try
if ~req('data') || ~isnumeric(N.data) || ~req('labels'), fail{end+1} = 'data / labels missing'; finish(A, packR(R, fail, warn), C); return, end
labN = cellfun(@(x) char(string(x)), N.labels(:)', 'UniformOutput', false);
if size(N.data, 1) ~= numel(labN), fail{end+1} = sprintf('data has %d rows, labels %d', size(N.data, 1), numel(labN)); end
if ~(req('fs') && N.fs == 500), fail{end+1} = 'fs is not 500'; end
if ~req('moreThan1'), fail{end+1} = 'moreThan1 missing (the done-sentinel)'; end
if ~req('behDat') || ~istable(N.behDat)
    fail{end+1} = 'behDat missing or not a table';
else
    vn = N.behDat.Properties.VariableNames;
    if ~ismember('manOnset', vn)
        if isSniff || strcmp(A.task, 'breathingTask'), fail{end+1} = 'behDat.manOnset missing'; else, warn{end+1} = 'behDat.manOnset missing'; end
    end
    if isSniff && ~ismember('finalOnset', vn), fail{end+1} = 'behDat.finalOnset missing'; end
end
if isBreath
    for f = {'bmObj', 'bmFeatures'}
        if ~req(f{1}), fail{end+1} = ['breath-type final without ' f{1}]; end
    end
    if strcmp(A.task, 'breathingTask')
        for f = {'baseEmotion', 'heartBeats'}
            if ~req(f{1}), fail{end+1} = ['breathingTask final without ' f{1}]; end
        end
    end
    if strcmp(A.task, 'airPuff') && ~req('holds'), fail{end+1} = 'airPuff final without holds'; end
    if ~req('breathMerge')
        respSkip = req('respSkipped') && all(N.respSkipped(:) == 2);
        if ~respSkip, fail{end+1} = 'breath-type final without breathMerge (the merge stage did not run)'; end
    end
end
if isSep
    if ~req('sections') || ~istable(N.sections), fail{end+1} = 'sep final without the sections table'; end
    if ~req('eegQCPerSection'), if A.hasEEG, fail{end+1} = 'sep final without eegQCPerSection'; end, end
end
if isfield(N, 'sessID') && ~strcmp(char(N.sessID), A.sessID)
    if loadedOld && isfield(O, 'sessID') && strcmp(char(N.sessID), char(O.sessID))
        % the id the previous final carries (e.g. the TB_1 / TPB_1 remap) - same as before, fine
    else
        warn{end+1} = sprintf('outDat.sessID %s differs from the manifest id %s', char(N.sessID), A.sessID);
    end
end
catch ME
    fail{end+1} = ['verifier error in the structure checks: ' ME.message];
end

% ---- the comparison with the previous final -----------------------------------------------------------------
carriedNames = {};
if loadedOld
    labO = cellfun(@(x) char(string(x)), O.labels(:)', 'UniformOutput', false);
    C.nChanOld = numel(labO); C.nChanNew = numel(labN);
    C.nSampOld = size(O.data, 2); C.nSampNew = size(N.data, 2);
    if C.nSampOld ~= C.nSampNew, fail{end+1} = sprintf('sample count changed %d -> %d', C.nSampOld, C.nSampNew); end
    if isfield(O, 'sessID') && isfield(N, 'sessID') && ~strcmp(char(O.sessID), char(N.sessID)), fail{end+1} = 'sessID differs from the previous final'; end
    lost = setdiff(labO, labN); gained = setdiff(labN, labO);
    allowedLost = {'blinkIndicator'};   % blink removal switched off (DL_1) / not run
    badLost = setdiff(lost, allowedLost);
    if ~isempty(badLost), fail{end+1} = ['rows of the previous final are missing: ' strjoin(badLost, ' ')]; end
    if ~isempty(lost) && isempty(badLost), warn{end+1} = ['rows no longer present: ' strjoin(lost, ' ')]; end
    if ~isempty(gained), warn{end+1} = ['new rows: ' strjoin(gained, ' ')]; end
    C.rowsLost = lost; C.rowsGained = gained;
    % row-by-row equality of the common rows
    try
    common = intersect(labN, labO, 'stable');
    same = {}; diffRows = {}; carriedBad = {};
    % EEG rows = rows 1-32 when the final has an EEG block (CLAUDE.md 6.2); labN is the normalised label list
    % (a final may store its labels as strings or a char matrix; ismember needs char cells)
    eegSet = {};
    if numel(labN) >= 32 && strcmp(labN{1}, 'Fp1'), eegSet = labN(1:32); end
    isEEGlab = @(l) ismember(l, eegSet);
    expectDiff = @(l) isEEGlab(l) || startsWith(l, 'macBP') || ismember(l, {'spikeCleanVec', 'badTS', 'interpChan', 'blinkIndicator'});
    isCarried = @(l) contains(l, 'rsp') || strcmp(l, 'targTrace');
    if C.nSampOld == C.nSampNew
        for k = 1:numel(common)
            l = common{k};
            a = N.data(strcmp(labN, l), :); b = O.data(strcmp(labO, l), :);
            a = a(1, :); b = b(1, :);
            if isequaln(a, b), same{end+1} = l; %#ok<AGROW>
            else
                diffRows{end+1} = l; %#ok<AGROW>
                if A.carry && isCarried(l), carriedBad{end+1} = l; end %#ok<AGROW>
                if ~expectDiff(l) && ~isCarried(l), warn{end+1} = ['row differs from the previous final: ' l]; end %#ok<AGROW>
            end
        end
    end
    C.rowsIdentical = numel(same); C.rowsDifferent = diffRows;
    if ~isempty(carriedBad), fail{end+1} = ['carried row(s) changed vs the previous final: ' strjoin(carriedBad, ' ')]; detFail = true; end
    catch ME
        fail{end+1} = ['verifier error comparing the rows: ' ME.message];
    end
    % the carry record
    stageNames = {};
    try
    if A.carry
        if ~isfield(N, 'carry') || ~isstruct(N.carry), fail{end+1} = 'carry requested but outDat.carry is missing'; detFail = true;
        else
            C.carry = safeCarry(N.carry);
            if ~(isfield(N.carry, 'rowsVerified') && allTrue(N.carry.rowsVerified)), fail{end+1} = 'outDat.carry.rowsVerified is not true'; detFail = true; end
            if isfield(N.carry, 'postHocFields'), carriedNames = cellstr(string(N.carry.postHocFields)); end
            % fields of the previous final that are stage outputs of the previous run (blinkICA, EEGCleaningInfo, heartBeats, ...): not carried by design
            if isfield(N.carry, 'stageFieldsNotCarried'), stageNames = cellstr(string(N.carry.stageFieldsNotCarried)); C.stageFieldsNotCarried = stageNames; end
            % the file the carry read on R: is the file that was backed up (so the E: backup is redundant once this passes)
            if isfield(N.carry, 'sha256') && ~isempty(A.backupSha)
                R.carryShaMatch = strcmpi(char(string(N.carry.sha256)), A.backupSha);
                C.carryShaMatchesBackup = R.carryShaMatch;
                if ~R.carryShaMatch, fail{end+1} = 'outDat.carry.sha256 differs from the SHA-256 of the backup'; detFail = true; end
            end
            % the carry gate: the same-recording evidence the carry recorded is acted on (NaN fails, nDiff / maxAbsDiff are judged)
            oldDatenum = NaN; if ~isempty(fo), oldDatenum = fo(1).datenum; end
            [gf, gw, gi] = carryGate(N.carry, N, oldDatenum, isSep);
            C.carryGate = gi;
            if ~isempty(gf), fail = [fail gf]; detFail = true; end %#ok<AGROW>
            warn = [warn gw]; %#ok<AGROW>
        end
    end
    catch ME
        fail{end+1} = ['verifier error checking the carry record: ' ME.message];
    end
    try
    % fields: gained / lost
    fN = fieldnames(N); fO = fieldnames(O);
    C.fieldsGained = setdiff(fN, fO)'; C.fieldsLost = setdiff(fO, fN)';
    lostF = setdiff(C.fieldsLost, [carriedNames(:)' stageNames(:)' {'carriedFromPrevFinal'}]);
    if ~isempty(lostF), warn{end+1} = ['fields of the previous final not in the new one (and not carried): ' strjoin(lostF, ' ')]; end
    % behavior table
    C = compareBeh(C, N, O, isSniff, isBreath);
    if isBreath && C.behRowsOld > 0 && C.behRowsNew == 0 && ~(isfield(N, 'respSkipped') && all(N.respSkipped(:) == 2))
        fail{end+1} = 'behDat has no rows although the previous final had some';
    end
    if isSniff && C.behRowsOld ~= C.behRowsNew, warn{end+1} = sprintf('behDat rows %d -> %d', C.behRowsOld, C.behRowsNew); end
    if isSniff && isfield(C, 'finalOnsetDiffN') && C.finalOnsetDiffN > 0
        warn{end+1} = sprintf('%d of %d finalOnset values differ from the previous final (max %.1f samples)', C.finalOnsetDiffN, C.behRowsNew, C.finalOnsetMaxDiff);
    end
    if isfield(N, 'TTL') && isfield(O, 'TTL')
        C.ttlEqual = isequaln(N.TTL, O.TTL);
        if ~C.ttlEqual && isSniff, warn{end+1} = 'TTL differs from the previous final'; end
    end
    % breath counts
    if isfield(N, 'bmObj') && isfield(O, 'bmObj')
        C.breathsOld = size(O.bmObj, 1); C.breathsNew = size(N.bmObj, 1);
    end
    if isfield(N, 'breathMerge') && isstruct(N.breathMerge)
        bm = N.breathMerge;
        for f = {'nBefore', 'nAfter', 'nMerged'}
            if isfield(bm, f{1}), C.(['merge_' f{1}]) = sum(bm.(f{1})(:)); end
        end
    end
    catch ME
        warn{end+1} = ['[verifier] behavior / field comparison failed: ' ME.message];
    end
end

% ---- EEG stage -----------------------------------------------------------------------------------------------
if A.hasEEG
    try
    UN = eegUnits(N, isSep); C.eegNew = UN;
    if loadedOld, UO = eegUnits(O, isSep); C.eegOld = UO; end
    if isempty(UN)
        fail{end+1} = 'hasEEG but the new final has no EEG stage record';
    else
        for u = 1:numel(UN)
            tag = UN(u).label;
            if ~strcmp(UN(u).ciMode, 'fixed'), fail{end+1} = sprintf('EEGCleaningInfo.mode is "%s", not fixed (%s)', UN(u).ciMode, tag); end
            if isempty(UN(u).ciVersion), warn{end+1} = ['EEGCleaningInfo.version missing (' tag ')']; end
            if UN(u).blinkRemoval == 1 && ~strcmp(UN(u).blinkMode, 'frontal')
                fail{end+1} = sprintf('blink IC removed with rule "%s", not frontal (%s)', UN(u).blinkMode, tag);
            end
            if UN(u).ciUnjudgeable == 1, warn{end+1} = ['EEG unjudgeable: every channel bad (' tag ')']; end
        end
        if loadedOld && numel(UO) == numel(UN)
            for u = 1:numel(UN)
                C.badChansAdded{u} = strjoin(setdiff(UN(u).badChans, UO(u).badChans), ' ');
                C.badChansRemoved{u} = strjoin(setdiff(UO(u).badChans, UN(u).badChans), ' ');
            end
        elseif loadedOld && isSep
            fail{end+1} = sprintf('number of sections changed %d -> %d', numel(UO), numel(UN));
        end
        if isSep && loadedOld && isfield(O, 'sections') && isfield(N, 'sections')
            if ~isequal(cellstr(string(O.sections.label)), cellstr(string(N.sections.label))), fail{end+1} = 'section labels differ from the previous final'; end
            if ~isequal(O.sections.startSample, N.sections.startSample) || ~isequal(O.sections.endSample, N.sections.endSample), fail{end+1} = 'section bounds differ from the previous final'; end
        end
    end
    catch ME
        fail{end+1} = ['verifier error in the EEG checks: ' ME.message];
    end
    % dataLap
    C.dataLap = struct('present', false, 'commonModeShare', NaN, 'geometry', false);
    try
    if isfield(N, 'dataLap') && ~isempty(N.dataLap)
        C.dataLap.present = true;
        C.dataLap.geometry = isfield(N, 'dataLapGeometry');
        [cm, nfin] = lapCommonMode(N);
        C.dataLap.commonModeShare = cm; C.dataLap.finite = nfin;
        if size(N.dataLap, 2) ~= size(N.data, 2) || size(N.dataLap, 1) ~= 32, fail{end+1} = 'dataLap has the wrong size'; end
        if ~nfin, fail{end+1} = 'dataLap has non-finite values'; end
        if cm >= 0.5, fail{end+1} = sprintf('dataLap is a common-mode artefact (share %.2f)', cm); elseif cm >= 0.2, warn{end+1} = sprintf('dataLap common-mode share %.2f', cm); end
        if ~C.dataLap.geometry, fail{end+1} = 'dataLap present without dataLapGeometry (the pre-fix Laplacian code ran)'; end
    else
        warn{end+1} = 'dataLap is empty (<= 10 good channels or the blink-stage gate)';
    end
    catch ME
        warn{end+1} = ['[verifier] dataLap check failed: ' ME.message];
    end
end

% ---- master sheet: nothing but the intended cells may change ------------------------------------------------
C.sheet = struct('compared', false, 'nChanged', 0, 'changed', {{}});
if ~isempty(A.sheetBefore) && ~isempty(A.sheetAfter) && isfile(A.sheetBefore) && isfile(A.sheetAfter)
    try
        c1 = readcell(A.sheetBefore, 'Sheet', 'Sheet1'); c2 = readcell(A.sheetAfter, 'Sheet', 'Sheet1');
        C.sheet.compared = true;
        if ~isequal(size(c1), size(c2))
            warn{end+1} = sprintf('master sheet size changed %s -> %s during the run', mat2str(size(c1)), mat2str(size(c2)));
            C.sheet.sizeChanged = true;
        else
            neq = ~cellfun(@(a, b) isequaln(a, b) || (all(ismissing(string(a))) && all(ismissing(string(b)))), c1, c2);
            [ri, ci] = find(neq);
            C.sheet.nChanged = numel(ri);
            hdr = cellfun(@(x) strtrim(cstr(x)), c1(2, :), 'UniformOutput', false);
            ch = cell(1, min(numel(ri), 30));
            for k = 1:numel(ch)
                nm = hdr{ci(k)};
                ch{k} = sprintf('r%d %s: %s -> %s', ri(k), nm, short(c1{ri(k), ci(k)}), short(c2{ri(k), ci(k)}));
                if strcmpi(nm, 'paramSource'), fail{end+1} = ['the run changed a paramSource cell: ' ch{k}]; end %#ok<AGROW>
            end
            C.sheet.changed = ch;
            if numel(ri) > 0, warn{end+1} = sprintf('%d master-sheet cell(s) changed during the run (concurrent writers included): %s', numel(ri), strjoin(ch(1:min(3, end)), ' ; ')); end
        end
    catch ME
        warn{end+1} = ['sheet snapshot comparison failed: ' ME.message];
    end
end

C.seconds = toc(t0);
R.failures = fail; R.warnings = warn; R.ok = isempty(fail); R.deterministic = (~R.ok && detFail);
finish(A, R, C);
end

% =====================================================================================================
function [f, w, g] = carryGate(carry, N, oldDatenum, isSep)
%CARRYGATE  Acts on the same-recording evidence that the respiration carry recorded in outDat.carry.checks (codeReview M2).
%   f = failures, w = warnings, g = the facts (era, worst selected r, largest differing share / relative deviation, rspMatch).
%   The carry itself (shared/carryRespFromFinal.m) errors only for a FINITE r below 0.90 on the selected channel; a NaN r (a flat row, or
%   fewer than 100 usable samples) passed silently, nDiff / maxAbsDiff were stored and ignored, and an unrecorded rspIDX / rspFlip passed.
%   This gate closes those holes from the outside, on the final the carry produced:
%     selected channel   r must be finite; r >= RFAIL (0.90); >= RFAIL_NOTCH (0.98) when the previous final was saved before the
%                        line-noise notch was removed from the shared core (2026-07-07 22:38: the notch cannot change the < 5 Hz band,
%                        so a lower r is a shifted or different recording); r < RWARN (0.995) warns;
%     same processing    a previous final saved on/after 2026-07-07 22:38 went through exactly the processing the rerun applies, so the
%                        carried row must EQUAL the rerun's own row: more than FRAC_FAIL (0.1 %) of the samples differing (nDiff,
%                        beyond 1e-6 of the row's range, outside reconstructed blocks) fails; the largest deviation above REL_WARN
%                        (5 %) of the row's range warns;
%     auxiliary rows     (not the selected channel) NaN or r < RFAIL warn, like the carry's own auxRow warning;
%     rspMatch false     (the previous final records no rspIDX / rspFlip, so the channel choice was not compared) warns.
RFAIL = 0.90; RFAIL_NOTCH = 0.98; RWARN = 0.995; FRAC_FAIL = 1e-3; REL_WARN = 0.05;
f = {}; w = {};
notchEra = isfinite(oldDatenum) && oldDatenum < datenum(2026, 7, 7, 22, 38, 0);
g = struct('era', 'unknown', 'rSelMin', NaN, 'fracDiffMax', NaN, 'relDevMax', NaN, 'rspMatch', true, 'nRecords', 0);
if isfinite(oldDatenum), if notchEra, g.era = 'notch'; else, g.era = 'post-notch'; end, end
if isfield(carry, 'perSection') && iscell(carry.perSection), recs = carry.perSection; else, recs = {carry}; end
g.nRecords = numel(recs);
labN = cellfun(@(x) char(string(x)), N.labels(:)', 'UniformOutput', false);
need = {'r', 'selected', 'nDiff', 'maxAbsDiff', 'nSamp'};
for k = 1:numel(recs)
    rec = recs{k};
    tag = ''; if numel(recs) > 1, tag = sprintf(' (section %d)', k); end
    if ~isstruct(rec) || ~isfield(rec, 'checks') || ~isstruct(rec.checks) || ~all(isfield(rec.checks, need)) || ~isfield(rec, 'rowsCarried')
        f{end+1} = ['carry record' tag ' has no per-row checks (r / selected / nDiff / maxAbsDiff): the same-recording evidence is missing']; %#ok<AGROW>
        continue
    end
    ck = rec.checks;
    rows = cellstr(string(rec.rowsCarried(:)));
    nR = numel(rows);
    r = double(ck.r(:)); sel = logical(ck.selected(:)); nd = double(ck.nDiff(:)); mx = double(ck.maxAbsDiff(:));
    if any([numel(r) numel(sel) numel(nd) numel(mx)] ~= nR)
        f{end+1} = ['carry record' tag ' is malformed: the per-row checks do not match the carried rows']; %#ok<AGROW>
        continue
    end
    if isfield(ck, 'rspMatch') && ~isempty(ck.rspMatch) && ~logical(ck.rspMatch(1))
        w{end+1} = ['the previous final' tag ' records no rspIDX / rspFlip: the channel choice could not be compared with the sheet']; %#ok<AGROW>
        g.rspMatch = false;
    end
    nUse = max(1, double(ck.nSamp) - double(getf(ck, 'nExcluded', 0)));
    % the range of each carried row (in this section of the new final)
    i0 = 1; i1 = size(N.data, 2);
    if isSep && isfield(N, 'sections') && istable(N.sections) && k <= height(N.sections)
        i0 = double(N.sections.startSample(k)); i1 = double(N.sections.endSample(k));
    end
    for j = 1:nR
        lab = rows{j};
        ii = find(strcmp(labN, lab), 1);
        rowRange = NaN;
        if ~isempty(ii)
            x = double(N.data(ii, i0:i1)); x = x(isfinite(x));
            if ~isempty(x), rowRange = max(x) - min(x); end
        end
        rel = NaN; if isfinite(mx(j)) && isfinite(rowRange) && rowRange > 0, rel = mx(j) / rowRange; end
        frac = NaN; if isfinite(nd(j)), frac = nd(j) / nUse; end
        if sel(j)
            if ~isfinite(r(j))
                f{end+1} = sprintf(['the selected respiration channel %s%s has no finite same-recording correlation (r is NaN: a flat row or fewer than ' ...
                    '100 usable samples) - the carry cannot show that it is the same recording'], lab, tag); %#ok<AGROW>
            elseif r(j) < RFAIL
                f{end+1} = sprintf('the selected respiration channel %s%s correlates r = %.3f (< 5 Hz) with the rerun''s own row (need >= %.2f)', lab, tag, r(j), RFAIL); %#ok<AGROW>
            elseif notchEra && r(j) < RFAIL_NOTCH
                f{end+1} = sprintf(['the selected respiration channel %s%s correlates r = %.3f (< 5 Hz) with the rerun''s own row; the previous final predates ' ...
                    'the notch removal, which cannot change that band (need >= %.2f) - a shifted or different recording'], lab, tag, r(j), RFAIL_NOTCH); %#ok<AGROW>
            elseif r(j) < RWARN
                w{end+1} = sprintf('carry: selected %s%s correlates r = %.4f with the rerun''s own row (< %.3f)', lab, tag, r(j), RWARN); %#ok<AGROW>
            end
            if isfinite(r(j)), g.rSelMin = min([g.rSelMin r(j)], [], 'omitnan'); end
            if isfinite(frac), g.fracDiffMax = max([g.fracDiffMax frac], [], 'omitnan'); end
            if isfinite(rel), g.relDevMax = max([g.relDevMax rel], [], 'omitnan'); end
            if ~notchEra && isfinite(oldDatenum) && isfinite(frac) && frac > FRAC_FAIL
                f{end+1} = sprintf(['the carried %s%s differs from the rerun''s own row in %.2f %% of the samples (largest deviation %.3g, %.1f %% of the row''s range) ' ...
                    'although the previous final was saved after the notch was removed (the same processing must give the same row) - a shifted or re-extracted recording'], ...
                    lab, tag, 100 * frac, mx(j), 100 * rel); %#ok<AGROW>
            elseif isfinite(rel) && rel > REL_WARN
                w{end+1} = sprintf('carry: the carried %s%s deviates from the rerun''s own row by up to %.1f %% of its range in %.1f %% of the samples', lab, tag, 100 * rel, 100 * frac); %#ok<AGROW>
            end
        else
            if ~isfinite(r(j)) || r(j) < RFAIL
                w{end+1} = sprintf('carry: auxiliary %s%s correlates r = %s with the rerun''s own row (carried as it is; the selected channel is judged separately)', lab, tag, numstr(r(j))); %#ok<AGROW>
            end
        end
    end
end
end

function s = numstr(x)
if isfinite(x), s = sprintf('%.3f', x); else, s = 'NaN'; end
end

% =====================================================================================================
function t = allTrue(x)
% a logical / numeric array, or a struct of them (a sep session record keeps one entry per section)
if isstruct(x)
    f = fieldnames(x); t = true;
    for i = 1:numel(f), t = t && allTrue(x.(f{i})); end
elseif iscell(x)
    t = true; for i = 1:numel(x), t = t && allTrue(x{i}); end
elseif isempty(x), t = false;
else, t = all(logical(x(:)));
end
end

function c = safeCarry(cr)
% the parts of outDat.carry that go into the json (scalars / strings / small arrays only)
c = struct();
for f = {'source', 'sha256', 'bytes', 'modified', 'sourceVar', 'rowsVerified', 'postHocFields', 'postHocNote', 'targTraceCarried', 'reconstructedCarried', 'rspIDX', 'rspFlip', 'note'}
    if isfield(cr, f{1})
        x = cr.(f{1});
        if ischar(x) || isstring(x) || (isnumeric(x) && numel(x) < 50) || islogical(x) || iscellstr(x), c.(f{1}) = x; end %#ok<ISCLSTR>
    end
end
if isfield(cr, 'rowsCarried'), try, c.rowsCarried = cellstr(string(cr.rowsCarried)); catch, end, end
end

function R = packR(R, fail, warn)
R.failures = fail; R.warnings = warn; R.ok = isempty(fail);
end

function finish(A, R, C)
% writes the result json, the comparison record and the summary line; prints the verdict
R.ok = isempty(R.failures);
cdir = A.compareDir;
if ~exist(cdir, 'dir'), mkdir(cdir); end
cf = fullfile(cdir, [A.key '.json']);
try
    C.verdict = struct('ok', R.ok, 'failures', {R.failures}, 'warnings', {R.warnings});
    fid = fopen(cf, 'w'); fwrite(fid, jsonencode(C, 'PrettyPrint', true), 'char'); fclose(fid);
    R.compareFile = cf;
catch ME
    R.warnings{end+1} = ['comparison record not written: ' ME.message];
end
try, summaryLine(cdir, A, R, C); catch ME, R.warnings{end+1} = ['summary line not written: ' ME.message]; end
fid = fopen(A.resultJson, 'w'); fwrite(fid, jsonencode(R), 'char'); fclose(fid);
if R.ok, fprintf('FR_VERIFY_OK %s (%d warning(s))\n', A.key, numel(R.warnings));
else, fprintf('FR_VERIFY_FAIL %s: %s\n', A.key, strjoin(R.failures, ' ; ')); end
for k = 1:numel(R.warnings), fprintf('FR_VERIFY_WARN %s\n', R.warnings{k}); end
end

function summaryLine(cdir, A, R, C)
f = fullfile(cdir, 'summary.csv');
cols = {'time', 'key', 'task', 'sessID', 'ok', 'nFail', 'nWarn', 'oldMB', 'newMB', 'nSamp', 'rowsIdentical', 'rowsDifferent', ...
    'badOld', 'badNew', 'badAdded', 'badRemoved', 'badTSold', 'badTSnew', 'blinkOld', 'blinkNew', 'ciModeNew', 'blinkMode', ...
    'dataLapShare', 'behRowsOld', 'behRowsNew', 'onsetDiffN', 'breathsOld', 'breathsNew', 'mergeJoined', 'carryVerified', 'sheetChanged', ...
    'deterministic', 'carryEra', 'carryRselMin', 'carryFracDiffMax', 'carryRelDevMax', 'carryRspMatch'};
v = struct();
v.time = datestr(now, 31); v.key = A.key; v.task = A.task; v.sessID = A.sessID; v.ok = double(R.ok);
v.nFail = numel(R.failures); v.nWarn = numel(R.warnings);
v.oldMB = fld(C, 'oldBytes') / 1e6; v.newMB = fld(C, 'newBytes') / 1e6; v.nSamp = fld(C, 'nSampNew');
v.rowsIdentical = fld(C, 'rowsIdentical'); v.rowsDifferent = numel(getf(C, 'rowsDifferent', {}));
eo = getf(C, 'eegOld', []); en = getf(C, 'eegNew', []);
v.badOld = joinNum(eo, 'nBad'); v.badNew = joinNum(en, 'nBad');
v.badAdded = strjoin(getf(C, 'badChansAdded', {}), '|'); v.badRemoved = strjoin(getf(C, 'badChansRemoved', {}), '|');
v.badTSold = joinNum(eo, 'badTSfrac'); v.badTSnew = joinNum(en, 'badTSfrac');
v.blinkOld = joinNum(eo, 'blinkRemoval'); v.blinkNew = joinNum(en, 'blinkRemoval');
v.ciModeNew = strjoin(arrayfun(@(u) u.ciMode, en, 'UniformOutput', false), '|');
v.blinkMode = strjoin(arrayfun(@(u) u.blinkMode, en, 'UniformOutput', false), '|');
dl = getf(C, 'dataLap', struct('commonModeShare', NaN)); v.dataLapShare = dl.commonModeShare;
v.behRowsOld = fld(C, 'behRowsOld'); v.behRowsNew = fld(C, 'behRowsNew'); v.onsetDiffN = fld(C, 'finalOnsetDiffN');
v.breathsOld = fld(C, 'breathsOld'); v.breathsNew = fld(C, 'breathsNew'); v.mergeJoined = fld(C, 'merge_nMerged');
cr = getf(C, 'carry', []); v.carryVerified = NaN;
if isstruct(cr) && isfield(cr, 'rowsVerified'), v.carryVerified = double(all(logical(cr.rowsVerified(:)))); end
v.sheetChanged = getf(getf(C, 'sheet', struct('nChanged', NaN)), 'nChanged', NaN);
v.deterministic = double(getf(R, 'deterministic', false));
cg = getf(C, 'carryGate', struct());
v.carryEra = getf(cg, 'era', ''); v.carryRselMin = getf(cg, 'rSelMin', NaN); v.carryFracDiffMax = getf(cg, 'fracDiffMax', NaN);
v.carryRelDevMax = getf(cg, 'relDevMax', NaN); v.carryRspMatch = double(getf(cg, 'rspMatch', true));
% a summary.csv written with other columns (an older version of this file) is renamed aside: its rows would misalign with the new header
hdr = strjoin(cols, ',');
if isfile(f)
    fid0 = fopen(f, 'r'); h0 = fgetl(fid0); fclose(fid0);
    if ~ischar(h0) || ~strcmp(strtrim(h0), hdr)
        movefile(f, fullfile(cdir, ['summary_' datestr(now, 'yyyymmdd_HHMMSS') '.csv']));
    end
end
newFile = ~isfile(f);
fid = fopen(f, 'a');
if newFile, fprintf(fid, '%s\n', hdr); end
parts = cell(1, numel(cols));
for k = 1:numel(cols)
    x = v.(cols{k});
    if isnumeric(x) || islogical(x)
        if isempty(x) || ~isscalar(x) || isnan(x), parts{k} = ''; else, parts{k} = sprintf('%.6g', x); end
    else, parts{k} = ['"' strrep(char(string(x)), '"', '''') '"']; end
end
fprintf(fid, '%s\n', strjoin(parts, ','));
fclose(fid);
end

function v = fld(S, f)
v = NaN; if isfield(S, f) && ~isempty(S.(f)), v = double(S.(f)(1)); end
end
function v = getf(S, f, d)
v = d; if isstruct(S) && isfield(S, f), v = S.(f); end
end
function s = joinNum(U, f)
s = '';
if isempty(U), return, end
c = arrayfun(@(u) sprintf('%.4g', double(u.(f))), U, 'UniformOutput', false);
s = strjoin(c, '|');
end
function s = cstr(x)
% char of a sheet cell; a missing / empty cell becomes ''
s = '';
try
    if isempty(x), return, end
    if isscalar(x) && ismissing(x), return, end
    s = char(string(x));
catch
    s = '<?>';
end
end
function s = short(x)
s = cstr(x); if numel(s) > 40, s = [s(1:37) '...']; end
if isempty(s), s = '<empty>'; end
end

function [S, vname] = loadFinal(f)
s = load(f); fn = fieldnames(s);
if numel(fn) ~= 1, error('fr_verify:var', '%s holds %d variables', f, numel(fn)); end
vname = fn{1}; S = s.(vname);
if ~isstruct(S), error('fr_verify:struct', '%s: variable %s is not a struct', f, vname); end
end

function U = eegUnits(S, isSep)
% one record per EEG unit: the whole final, or each section of a sep final
U = struct('label', {}, 'ciMode', {}, 'ciVersion', {}, 'ciUnjudgeable', {}, 'blinkRemoval', {}, 'blinkMode', {}, 'badChans', {}, 'nBad', {}, 'badTSfrac', {});
if isSep
    if ~isfield(S, 'eegQCPerSection'), return, end
    for c = 1:numel(S.eegQCPerSection)
        q = S.eegQCPerSection{c};
        lab = sprintf('section %d', c);
        if isfield(S, 'sections') && c <= height(S.sections), lab = sprintf('section %d %s', c, char(string(S.sections.label(c)))); end
        U(end+1) = unitOf(q, lab, S, S.sections.startSample(c), S.sections.endSample(c)); %#ok<AGROW>
    end
else
    if ~isfield(S, 'EEGCleaning') && ~isfield(S, 'badChans'), return, end
    U = unitOf(S, 'all', S, 1, size(S.data, 2));
end
end
function u = unitOf(q, lab, S, i0, i1)
u = struct('label', lab, 'ciMode', '', 'ciVersion', '', 'ciUnjudgeable', NaN, 'blinkRemoval', NaN, 'blinkMode', '', 'badChans', {{}}, 'nBad', NaN, 'badTSfrac', NaN);
if isfield(q, 'EEGCleaningInfo') && isstruct(q.EEGCleaningInfo)
    ci = q.EEGCleaningInfo;
    if isfield(ci, 'mode'), u.ciMode = char(string(ci.mode)); end
    if isfield(ci, 'version'), u.ciVersion = char(string(ci.version)); end
    if isfield(ci, 'unjudgeable') && ~isempty(ci.unjudgeable), u.ciUnjudgeable = double(ci.unjudgeable(1)); end
end
if isfield(q, 'blinkRemoval') && ~isempty(q.blinkRemoval), u.blinkRemoval = double(q.blinkRemoval(1)); end
if isfield(q, 'blinkICA') && isstruct(q.blinkICA) && isfield(q.blinkICA, 'mode'), u.blinkMode = char(string(q.blinkICA.mode)); end
if isfield(q, 'badChans')
    b = q.badChans; if isempty(b), b = {}; end
    b = cellstr(string(b(:)'));  b = b(~cellfun(@isempty, b));
    u.badChans = b; u.nBad = numel(b);
end
lab0 = cellfun(@(x) char(string(x)), S.labels(:)', 'UniformOutput', false);
ib = find(strcmp(lab0, 'badTS'), 1);
if ~isempty(ib), u.badTSfrac = mean(S.data(ib, i0:i1) ~= 0); end
end

function [share, allFinite] = lapCommonMode(S)
% share of the variance of dataLap that sits in the channel mean (stored pre-fix finals: 0.96-0.99; fixed: 0.01-0.03)
L = S.dataLap; fs = S.fs; n = size(L, 2);
lab = cellfun(@(x) char(string(x)), S.labels(:)', 'UniformOutput', false);
ib = find(strcmp(lab, 'badTS'), 1);
w = 60 * fs; i0 = 1; i1 = n;
if n > w
    bad = double(S.data(ib, :) ~= 0);
    nWin = floor(n / w); best = inf;
    for k = 1:nWin
        s = mean(bad((k-1)*w+1:k*w)); if s < best, best = s; i0 = (k-1)*w+1; i1 = k*w; end
    end
end
x = double(L(:, i0:i1));
allFinite = all(isfinite(L(:, i0:i1)), 'all');
x = x - mean(x, 2);
m = mean(x, 1);
share = size(x, 1) * var(m) / sum(var(x, 0, 2));
end

function C = compareBeh(C, N, O, isSniff, isBreath)
C.behRowsOld = NaN; C.behRowsNew = NaN;
if isfield(N, 'behDat') && istable(N.behDat), C.behRowsNew = height(N.behDat); C.behColsNew = N.behDat.Properties.VariableNames; end
if isfield(O, 'behDat') && istable(O.behDat), C.behRowsOld = height(O.behDat); C.behColsOld = O.behDat.Properties.VariableNames; end
if isfield(C, 'behColsNew') && isfield(C, 'behColsOld')
    C.behColsAdded = setdiff(C.behColsNew, C.behColsOld); C.behColsRemoved = setdiff(C.behColsOld, C.behColsNew);
end
if isSniff && C.behRowsOld == C.behRowsNew && C.behRowsNew > 0 && ismember('finalOnset', N.behDat.Properties.VariableNames) && ismember('finalOnset', O.behDat.Properties.VariableNames)
    a = double(N.behDat.finalOnset); b = double(O.behDat.finalOnset);
    d = abs(a - b); d(isnan(a) & isnan(b)) = 0;
    C.finalOnsetDiffN = sum(d > 0 | xor(isnan(a), isnan(b))); C.finalOnsetMaxDiff = max([0; d(~isnan(d))]);
end
end

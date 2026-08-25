% task789_verifyFinals — verify the finals produced by the Task 7/8/9 runs and
% reconcile the sheet flags (movie/alt6 via writePreProcX/clearPreProcX; sep
% via writeSheetSep). Same hard/soft philosophy as task3_verifyFinals:
% structural problems clear the flag, soft metrics are review-flags only.

report = {};

% ---------------- EmotionalMovieTask (7 EEG sessions) ----------------
IDS = {'260806_EEG_NWU_JH', '260806_EEG_NWU_MM', '260807_EEG_NWU_GP', ...
       '260810_EEG_NWU_IS', '260810_EEG_NWU_AL', '260811_EEG_NWU_MS', '260811_EEG_NWU_HK'};
L = labPaths();
for k = 1:numel(IDS)
    id = IDS{k};
    f = fullfile(L.rootEEG, id, 'preProc', [id '_EmotionalMovieTaskpreproc.mat']);
    r = verifyOne(f, id, 'EmotionalMovieTask', {'moreThan1', 'bmObj', 'bmFeatures', 'behDat', 'TTL'});
    if r.hardOK
        chkClips = height(r.od.TTL);
        nBr = height(r.od.behDat);
        bpm = bpmOf(r.od);
        soft = {};
        % the movie's design is 180 clips (~60/valence; confirmed on TI_1);
        % mild photodiode over-detection is a review flag
        if chkClips < 150 || chkClips > 210, soft{end+1} = sprintf('%d clips', chkClips); end
        if nBr < 100, soft{end+1} = sprintf('only %d in-clip breaths', nBr); end
        if isfinite(bpm) && (bpm < 45 || bpm > 110), soft{end+1} = sprintf('%.0f bpm', bpm); end
        missing = setdiff({'clipIndex', 'clipValence', 'clipOnset', 'manOnset', 'goodBreath'}, ...
                          r.od.behDat.Properties.VariableNames);
        if ~isempty(missing), r.hardOK = false; soft{end+1} = ['missing cols: ' strjoin(missing, ',')]; end
        report{end+1} = sprintf('%-22s movie: %s clips=%d breaths=%d bpm=%.0f %s', id, ...
            okStr(r.hardOK), chkClips, nBr, bpm, strjoin(soft, '; ')); %#ok<AGROW>
    else
        report{end+1} = sprintf('%-22s movie: FAIL %s', id, r.msg); %#ok<AGROW>
    end
    reconcile(r.hardOK, 'EmotionalMovieTask', id);
    clear r
end

% ---------------- alternating6Blocks (8 EEG sessions) ----------------
IDS = [{'260805_EEG_NWU_CA'}, IDS];
for k = 1:numel(IDS)
    id = IDS{k};
    f = fullfile(L.rootEEG, id, 'preProc', [id '_alternating6Blockspreproc.mat']);
    r = verifyOne(f, id, 'alternating6Blocks', {'moreThan1', 'bmObj', 'bmFeatures', 'behDat', 'blocks', 'baseEmotion'});
    if r.hardOK
        B = r.od.blocks;
        durMin = (B.endSample - B.startSample) / 500 / 60;
        nBr = height(r.od.behDat);
        bpm = bpmOf(r.od);
        soft = {};
        if height(B) ~= 7, r.hardOK = false; soft{end+1} = sprintf('%d blocks', height(B)); end
        if any(durMin < 4 | durMin > 12), soft{end+1} = ['block mins ' mat2str(round(durMin', 1))]; end
        if isfinite(bpm) && (bpm < 45 || bpm > 110), soft{end+1} = sprintf('%.0f bpm', bpm); end
        if ~any(contains(r.od.behDat.Properties.VariableNames, '_affective'))
            soft{end+1} = 'no rating columns';
        end
        report{end+1} = sprintf('%-22s alt6:  %s blocks=%d breaths=%d bpm=%.0f %s', id, ...
            okStr(r.hardOK), height(B), nBr, bpm, strjoin(soft, '; ')); %#ok<AGROW>
    else
        report{end+1} = sprintf('%-22s alt6:  FAIL %s', id, r.msg); %#ok<AGROW>
    end
    reconcile(r.hardOK, 'alternating6Blocks', id);
    clear r
end

% ---------------- breathingTasks_separate (8 sessions) ----------------
SEP = {'260625_OBE_NWU_HM_2', 4; '260702_OBE_NWU_SP_2', 3; '260622_OBE_NWU_RC_1', 4; ...
       '260720_OBE_NWU_KA_2', 1; '250929_Dupi_NMH_GH_1', 1; '251027_Dupi_NMH_DL_1', 1; ...
       '251006_OBE_NWU_RY_1', 1; '260105_OBE_NWU_ZF_1', 1};
cfgS = applyParams('breathingTasks_separate', 'main');
for k = 1:size(SEP, 1)
    id = SEP{k, 1};
    ri = find(strcmpi(cfgS.sessionIDs, id), 1);
    if isempty(ri)
        report{end+1} = sprintf('%-22s sep:   not in session list!', id); %#ok<AGROW>
        continue;
    end
    f = fullfile(cfgS.root{ri}, id, 'preProc', [id '_breathingTasks_separatepreproc.mat']);
    r = verifyOne(f, id, 'breathingTasks_separate', {'moreThan1', 'bmObj', 'bmFeatures', 'behDat', 'sections'});
    if r.hardOK
        nSec = height(r.od.sections);
        nBr = height(r.od.behDat);
        bpm = bpmOf(r.od);
        soft = {};
        if nSec ~= SEP{k, 2}, r.hardOK = false; soft{end+1} = sprintf('%d sections (expected %d)', nSec, SEP{k, 2}); end
        if isfinite(bpm) && (bpm < 45 || bpm > 110), soft{end+1} = sprintf('%.0f bpm', bpm); end
        report{end+1} = sprintf('%-22s sep:   %s sections=%d breaths=%d bpm=%.0f %s', id, ...
            okStr(r.hardOK), nSec, nBr, bpm, strjoin(soft, '; ')); %#ok<AGROW>
    else
        report{end+1} = sprintf('%-22s sep:   FAIL %s', id, r.msg); %#ok<AGROW>
    end
    try
        P = struct('task', 'breathingTasks_separate');
        if r.hardOK, writeSheetSep(P, id, 'X'); else, writeSheetSep(P, id, 'clearX'); end
    catch ME
        fprintf('  (writeSheetSep failed for %s: %s)\n', id, ME.message);
    end
    clear r
end

fprintf('\n===== task789_verifyFinals =====\n');
fprintf('%s\n', report{:});

% ============================ helpers ============================

function r = verifyOne(f, id, ~, fields)
    r = struct('hardOK', false, 'msg', '', 'od', []);
    if ~exist(f, 'file')
        r.msg = 'final missing';
        return;
    end
    try
        S = load(f); fn = fieldnames(S); r.od = S.(fn{1});
        for k = 1:numel(fields)
            if ~isfield(r.od, fields{k})
                r.msg = ['no ' fields{k}];
                return;
            end
        end
        if r.od.fs ~= 500, r.msg = sprintf('fs=%g', r.od.fs); return; end
        r.hardOK = true;
    catch ME
        r.msg = ['load failed: ' ME.message];
    end
end

function b = bpmOf(od)
    b = NaN;
    if isfield(od, 'heartBeats') && isfield(od, 'data') && ~isempty(od.heartBeats)
        b = numel(od.heartBeats) / (size(od.data, 2) / od.fs / 60);
    end
end

function s = okStr(ok)
    if ok, s = 'OK  '; else, s = 'BAD '; end
end

function reconcile(ok, task, id)
    try
        if ok
            writePreProcX(struct('task', task), id);
        else
            clearPreProcX(struct('task', task), id);
        end
    catch ME
        fprintf('  (sheet reconcile failed for %s/%s: %s)\n', task, id, ME.message);
    end
end

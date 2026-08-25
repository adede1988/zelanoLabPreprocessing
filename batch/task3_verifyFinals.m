% task3_verifyFinals — verify every breathing final after the Task 3 rerun
% (Tasks_260824.md Task 3 step 8) and reconcile the sheet flag.
%
% For every applyParams-eligible breathingTask session:
%   - final loads (h5 fields via task1-style structural read, then a real load
%     of behDat-scale fields), has manOnset, bmObj, bmFeatures, baseEmotion
%   - breath count vs the July backup (E:\reprocBackup_260824\breathing\)
%     within +/-10% where a backup exists
%   - heart rate from heartBeats plausible (45-110 bpm)
%   - behDat carries the old columns plus bm_* columns
% Sheet reconciliation follows D2 (the flag mirrors the DISK):
%   - STRUCTURAL failures (final missing / unloadable / missing required
%     fields) -> clearPreProcX
%   - structurally valid finals -> writePreProcX (idempotent), even when a
%     SOFT metric (breath-count drift, odd heart rate) is flagged; soft
%     failures are report-only and listed for human review.

BACKUP = 'E:\reprocBackup_260824\breathing';
cfg = applyParams('breathingTask', 'main');

OLD_COLS = {'sniffOnset', 'finalOnset', 'manOnset', 'condition', 'Yonset', ...
            'inhaleMax', 'inMaxTim', 'Yend', 'endTim', 'length', 'amp', ...
            'exhaleMin', 'exMinTim', 'index', 'task', 'noseMouth', ...
            'shadowFile', 'warp', 'goodBreath', 'maxRR', 'minRR', 'RR_max_min'};

nOK = 0; nSoft = 0; nBad = 0; nMissing = 0;
for s = 1:numel(cfg.sessionIDs)
    id = cfg.sessionIDs{s};
    fpath = fullfile(cfg.root{s}, id, 'preProc', [id '_breathingPreproc.mat']);
    if ~exist(fpath, 'file')
        fprintf('MISSING %-26s (no final) -> clearing sheet flag\n', id);
        nMissing = nMissing + 1;
        tryClear(id);
        continue;
    end
    try
        S = load(fpath); fn = fieldnames(S); od = S.(fn{1}); clear S
        hard = {}; soft = {};
        for f = {'moreThan1', 'bmObj', 'bmFeatures', 'baseEmotion', 'behDat', 'heartBeats'}
            if ~isfield(od, f{1}), hard{end+1} = ['no ' f{1}]; end %#ok<SAGROW>
        end
        if isfield(od, 'fs') && od.fs ~= 500, hard{end+1} = sprintf('fs=%g', od.fs); end %#ok<SAGROW>
        if isfield(od, 'behDat') && istable(od.behDat)
            missingCols = setdiff(OLD_COLS, od.behDat.Properties.VariableNames);
            if ~isempty(missingCols)
                hard{end+1} = ['missing cols: ' strjoin(missingCols, ',')]; %#ok<SAGROW>
            end
            if ~any(startsWith(od.behDat.Properties.VariableNames, 'bm_'))
                hard{end+1} = 'no bm_* columns'; %#ok<SAGROW>
            end
            nBr = height(od.behDat);
        else
            nBr = NaN;
        end
        % heart rate (soft)
        if isfield(od, 'heartBeats') && isfield(od, 'data')
            durMin = size(od.data, 2) / od.fs / 60;
            bpm = numel(od.heartBeats) / durMin;
            if bpm < 45 || bpm > 110
                soft{end+1} = sprintf('heart rate %.0f bpm', bpm); %#ok<SAGROW>
            end
        else
            bpm = NaN;
        end
        % breath count vs backup (soft); bmObj is [n x 14] with n >> 14, so
        % max(Dataspace.Size) is the breath count
        bkTxt = '';
        bk = dir(fullfile(BACKUP, [id '_breathingPreproc.mat']));
        if ~isempty(bk)
            try
                info = h5info(fullfile(bk(1).folder, bk(1).name));
                top = info.Groups(find(~startsWith({info.Groups.Name}, '/#'), 1)).Name;
                gi = h5info(fullfile(bk(1).folder, bk(1).name), [top '/bmObj']);
                oldN = max(gi.Dataspace.Size);
                if isfinite(nBr) && oldN > 14
                    dPct = 100 * (nBr - oldN) / oldN;
                    bkTxt = sprintf(' | breaths %d vs July %d (%+.1f%%)', nBr, oldN, dPct);
                    if abs(dPct) > 10
                        soft{end+1} = sprintf('breath count %+.1f%% vs July', dPct); %#ok<SAGROW>
                    end
                end
            catch
                bkTxt = ' | (backup unreadable)';
            end
        end
        if isempty(hard)
            % structurally valid -> the sheet flag must be SET (D2), soft
            % issues are reported for human review
            try
                writePreProcX(struct('task', 'breathingTask'), id);
            catch ME
                fprintf('        (writePreProcX failed: %s)\n', ME.message);
            end
            if isempty(soft)
                fprintf('OK      %-26s breaths=%d bpm=%.0f%s\n', id, nBr, bpm, bkTxt);
                nOK = nOK + 1;
            else
                fprintf('SOFT    %-26s %s%s (final kept, X kept - review)\n', ...
                    id, strjoin(soft, '; '), bkTxt);
                nSoft = nSoft + 1;
            end
        else
            fprintf('BAD     %-26s %s%s -> clearing sheet flag\n', id, strjoin(hard, '; '), bkTxt);
            nBad = nBad + 1;
            tryClear(id);
        end
        clear od
    catch ME
        fprintf('BAD     %-26s load failed: %s -> clearing sheet flag\n', id, ME.message);
        nBad = nBad + 1;
        tryClear(id);
    end
end
fprintf('task3_verifyFinals: DONE  ok=%d soft=%d bad=%d missing=%d of %d\n', ...
    nOK, nSoft, nBad, nMissing, numel(cfg.sessionIDs));

function tryClear(id)
    try
        clearPreProcX(struct('task', 'breathingTask'), id);
    catch ME
        fprintf('        (clearPreProcX failed: %s)\n', ME.message);
    end
end

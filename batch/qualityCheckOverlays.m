% qualityCheckOverlays — breath-segmentation overlay figures for EVERY final
% whose breaths were detected by breathMetrics (breathingTask, movie,
% alternating6Blocks, breathingTasks_separate). Six 1-minute panels per
% session: the 3 lowest-amplitude minutes + 3 seeded-random minutes, inhale
% onsets (bmObj col 2) marked on the trace exactly as the engine saw it
% (rspIDX selected, rspFlip applied). The title states the session ID, task,
% and whether detection used the windowed amplitude adjustment (with its
% floor) or the pre-windowed global amplitude criterion - read from the
% final's own bmFeatures.conditioning record, never assumed.
%
% Output: E:\reprocBackup_260824\breathingQualityCheck\qc_<task>_<id>.jpg
% (copied into the repo's breathingQualityCheck\ folder for review).

TASKS = { ...
 'breathingTask',          '_breathing*.mat'; ...
 'emotionalMovieTask',     '_EmotionalMovieTask*.mat'; ...
 'alternating6Blocks',     '_alternating6Blocks*.mat'; ...
 'breathingTasks_separate','_breathingTasks_separate*.mat'};

outDir = 'E:\reprocBackup_260824\breathingQualityCheck';
if ~exist(outDir, 'dir'), mkdir(outDir); end

nFig = 0; nSkip = 0; ctr = 0;
for tt = 1:size(TASKS, 1)
    [tkey, glb] = TASKS{tt, :};
    cfg = applyParams(tkey, 'main');
    for si = 1:numel(cfg.sessionIDs)
        id = cfg.sessionIDs{si};
        ctr = ctr + 1;
        hits = dir(fullfile(cfg.root{si}, id, 'preProc', [id glb]));
        if isempty(hits), continue; end
        try
            s = load(fullfile(hits(1).folder, hits(1).name));
            fn = fieldnames(s); od = s.(fn{1}); clear s
        catch
            fprintf('SKIP %s %s: final unreadable\n', tkey, id);
            nSkip = nSkip + 1;
            continue;
        end
        if ~isfield(od, 'bmObj') || ~isfield(od, 'bmFeatures')
            fprintf('SKIP %s %s: not a breathMetrics final\n', tkey, id);
            nSkip = nSkip + 1;
            clear od
            continue;
        end

        % engine-mode label from the final's own conditioning record
        mode = 'engine conditioning UNKNOWN';
        c = [];
        if isfield(od.bmFeatures, 'conditioning')
            c = od.bmFeatures.conditioning;
        elseif isfield(od.bmFeatures, 'conditioningPerSection') ...
                && ~isempty(od.bmFeatures.conditioningPerSection)
            c = od.bmFeatures.conditioningPerSection{1};
        end
        if ~isempty(c) && isstruct(c)
            if isfield(c, 'windowedAmpNorm')
                if isfield(c, 'ampNormFloorFrac'), ffTxt = sprintf('%.2f', c.ampNormFloorFrac);
                else, ffTxt = '0.10'; end
                mode = ['WINDOWED amp adjustment (floor ' ffTxt ')'];
            else
                mode = 'GLOBAL amplitude (no windowed adjustment)';
            end
        end

        isRsp = cellfun(@(x) contains(x, 'rsp'), od.labels);
        rsp = od.data(isRsp, :);
        rsp = rsp(od.rspIDX, :) .* od.rspFlip;
        fs = od.fs;
        onsets = round(od.bmObj(:, 2) * fs);
        onsets = onsets(onsets >= 1 & onsets <= numel(rsp));

        % task windows: alt6 keeps only in-block breaths and movie only
        % in-clip breaths, so time OUTSIDE the windows is intentionally
        % unmarked - shade it to prevent reading it as detection dropout
        win = [];   % [start end] rows in samples
        try
            if istable(od.TTL) && ismember('clipOnset', od.TTL.Properties.VariableNames)
                win = [od.TTL.clipOnset, od.TTL.clipEnd];
            elseif strcmp(tkey, 'alternating6Blocks') && isfield(od, 'blocks') && istable(od.blocks)
                bv = od.blocks.Properties.VariableNames;
                sc = bv(contains(lower(bv), 'start')); ec = bv(contains(lower(bv), 'end'));
                if ~isempty(sc) && ~isempty(ec)
                    win = [od.blocks.(sc{1}), od.blocks.(ec{1})];
                end
            end
        catch
            win = [];
        end
        if ~isempty(win)
            win = win(all(isfinite(win), 2) & win(:, 2) > win(:, 1), :);
        end

        N = numel(rsp);
        W = round(60 * fs);
        sLoc = movstd(double(rsp), W);
        nBins = floor(N / (60 * fs));
        if nBins < 1, fprintf('SKIP %s %s: <1 min\n', tkey, id); nSkip = nSkip + 1; continue; end
        binAmp = zeros(1, nBins);
        for w = 1:nBins, binAmp(w) = median(sLoc((w-1)*60*fs+1 : w*60*fs)); end
        [~, ampOrd] = sort(binAmp);
        rng(3000 + ctr, 'twister');
        nLow = min(3, nBins);
        pool = setdiff(1:nBins, ampOrd(1:nLow));
        bins = sort([ampOrd(1:nLow), pool(randperm(numel(pool), min(3, numel(pool))))]);

        fig = figure('Visible', 'off', 'Position', [10 10 1500 1350]);
        for b = 1:numel(bins)
            i0 = (bins(b) - 1) * 60 * fs + 1; i1 = bins(b) * 60 * fs;
            t = (i0:i1) / fs;
            subplot(numel(bins), 1, b); hold on
            if ~isempty(win)
                % shade the parts of this minute OUTSIDE every task window
                outMask = true(1, i1 - i0 + 1);
                for wr = 1:size(win, 1)
                    a = max(i0, win(wr, 1)); z = min(i1, win(wr, 2));
                    if z >= a, outMask(a - i0 + 1 : z - i0 + 1) = false; end
                end
                d = diff([0 outMask 0]);
                sIdx = find(d == 1); eIdx = find(d == -1) - 1;
                yl = [min(rsp(i0:i1)) max(rsp(i0:i1))];
                for sg = 1:numel(sIdx)
                    patch(([sIdx(sg) eIdx(sg) eIdx(sg) sIdx(sg)] + i0 - 1) / fs, ...
                        yl([1 1 2 2]), [0.85 0.85 0.85], 'EdgeColor', 'none');
                end
            end
            plot(t, rsp(i0:i1), 'k', 'LineWidth', 0.75);
            oi = onsets(onsets >= i0 & onsets <= i1);
            plot(oi / fs, rsp(oi), 'rv', 'MarkerFaceColor', 'r', 'MarkerSize', 6);
            xlim([t(1) t(end)]); ylabel(sprintf('min %d', bins(b)));
            if b == 1
                shadeTxt = '';
                if ~isempty(win)
                    shadeTxt = '  (gray = outside task windows: breaths intentionally excluded)';
                end
                title({sprintf('%s  —  %s%s', strrep(id, '_', '\_'), tkey, shadeTxt), ...
                       sprintf('breathMetrics, %s  —  n=%d breaths, rspFlip %+d', ...
                           mode, size(od.bmObj, 1), od.rspFlip)});
            end
            if b == numel(bins), xlabel('time (s)'); end
        end
        saveas(fig, fullfile(outDir, sprintf('qc_%s_%s.jpg', tkey, id)));
        close(fig);
        nFig = nFig + 1;
        fprintf('FIG %s %s: n=%d, %s\n', tkey, id, size(od.bmObj, 1), mode);
        clear od rsp
    end
end
fprintf('qualityCheckOverlays: DONE (%d figures, %d skipped)\n', nFig, nSkip);

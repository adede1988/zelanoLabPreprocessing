% qc3_triColorFigs — QC round 3 step 3: for EVERY breathMetrics final (post
% trace reconstruction), run the three candidate onset detectors on the v3b
% detection trace (150-ms smooth, 30-s movstd norm; MS leak blanked) over the
% shared alternating-extrema backbone, and plot 6 one-minute panels with the
% three algorithms in three colors:
%   RED   = slopeGate (sustained slope-threshold crossing in the mid-band)
%   BLUE  = kneeBacktrack (foot of the fast rise from max slope)
%   GREEN = changepoint (two-line fit breakpoint)
% Backbone peaks/troughs shown as small black dots. Panels: 3 lowest-amplitude
% + 3 seeded-random minutes. -> E:\reprocBackup_260824\qc3triColor\

TASKS = { ...
 'breathingTask',          '_breathing*.mat'; ...
 'emotionalMovieTask',     '_EmotionalMovieTask*.mat'; ...
 'alternating6Blocks',     '_alternating6Blocks*.mat'; ...
 'breathingTasks_separate','_breathingTasks_separate*.mat'};
outDir = 'E:\reprocBackup_260824\qc3triColor';
if ~exist(outDir, 'dir'), mkdir(outDir); end
METHODS = {'slopeGate', 'kneeBacktrack', 'changepoint'};
COLS = {[0.85 0.1 0.1], [0.1 0.3 0.9], [0.05 0.6 0.2]};
ctr = 0; nFig = 0;
for tt = 1:size(TASKS, 1)
    [tkey, glb] = TASKS{tt, :};
    cfg = applyParams(tkey, 'main');
    for si = 1:numel(cfg.sessionIDs)
        id = cfg.sessionIDs{si}; ctr = ctr + 1;
        hits = dir(fullfile(cfg.root{si}, id, 'preProc', [id glb]));
        if isempty(hits), continue; end
        try
            s = load(fullfile(hits(1).folder, hits(1).name));
            fn = fieldnames(s); od = s.(fn{1}); clear s
            if ~isfield(od, 'bmFeatures'), continue; end
            isRsp = cellfun(@(x) contains(x, 'rsp'), od.labels);
            rsp = od.data(isRsp, :); rsp = double(rsp(od.rspIDX, :)) .* od.rspFlip;
            fs = od.fs;
            rsp = fillmissing(rsp, 'linear', 'EndValues', 'nearest');
            xs = movmean(rsp, round(0.15 * fs));
            sc = movstd(xs, round(30 * fs));
            det = xs ./ max(sc, 0.05 * median(sc));
            if strcmp(id, '260811_EEG_NWU_MS') && ~strcmp(tkey, 'breathingTask')
                det(sc < 0.10 * median(sc)) = 0;
            end
            [pk, tr] = findAlternatingExtrema(det, fs);
            ons = cell(1, 3);
            for mm = 1:3, ons{mm} = findInhaleOnsets_zlp(det, fs, pk, tr, METHODS{mm}); end

            N = numel(rsp); nBins = floor(N / (60 * fs));
            if nBins < 1, continue; end
            binAmp = zeros(1, nBins);
            for w = 1:nBins, binAmp(w) = median(sc((w-1)*60*fs+1 : w*60*fs)); end
            [~, aOrd] = sort(binAmp);
            rng(4000 + ctr, 'twister');
            nLow = min(3, nBins); pool = setdiff(1:nBins, aOrd(1:nLow));
            bins = sort([aOrd(1:nLow), pool(randperm(numel(pool), min(3, numel(pool))))]);
            fig = figure('Visible', 'off', 'Position', [10 10 1500 230 * numel(bins)]);
            for b = 1:numel(bins)
                i0 = (bins(b)-1)*60*fs + 1; i1 = min(bins(b)*60*fs, N); t = (i0:i1)/fs;
                subplot(numel(bins), 1, b); hold on
                plot(t, rsp(i0:i1), 'k', 'LineWidth', 0.7);
                ex = [pk(pk>=i0 & pk<=i1), tr(tr>=i0 & tr<=i1)];
                plot(ex/fs, rsp(ex), 'k.', 'MarkerSize', 8);
                for mm = 1:3
                    oi = ons{mm}(ons{mm}>=i0 & ons{mm}<=i1);
                    plot(oi/fs, rsp(oi), 'v', 'Color', COLS{mm}, 'MarkerFaceColor', COLS{mm}, 'MarkerSize', 6);
                end
                xlim([t(1) t(end)]); ylabel(sprintf('min %d', bins(b)));
                if b == 1
                    title({sprintf('%s — %s — RED slopeGate | BLUE kneeBacktrack | GREEN changepoint', ...
                        strrep(id, '_', '\_'), tkey), ...
                        sprintf('n = %d / %d / %d onsets; black dots = backbone peaks/troughs', ...
                        numel(ons{1}), numel(ons{2}), numel(ons{3}))});
                end
                if b == numel(bins), xlabel('time (s)'); end
            end
            saveas(fig, fullfile(outDir, sprintf('qc3_%s_%s.jpg', tkey, id)));
            close(fig); nFig = nFig + 1;
            fprintf('QC3 %s %s: %d/%d/%d onsets, %d peaks\n', tkey, id, numel(ons{1}), numel(ons{2}), numel(ons{3}), numel(pk));
            clear od rsp det
        catch ME
            fprintf('QC3 FAIL %s %s: %s\n', tkey, id, ME.message);
        end
    end
end
fprintf('qc3_triColorFigs: DONE (%d figures)\n', nFig);

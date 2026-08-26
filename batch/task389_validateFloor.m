% task389_validateFloor — pick the amplitude-normalization floor. MS's
% leak-attenuated section (cannula tube partially unplugged; pressure not
% fully contained but the sensor still on the nose) carries real breaths at
% ~1/30 of plugged amplitude: test floorFrac 0.05 and 0.02 on MS (recovery)
% and 0.05 on VW (false-positive control in its genuinely quiet stretches).
% Offline only - nothing saved to preProc.

outDir = 'E:\reprocBackup_260824\segQC2';
if ~exist(outDir, 'dir'), mkdir(outDir); end

CASES = { ...  % id, taskKey, glob, flip override (NaN = stored), floorFrac
 '260811_EEG_NWU_MS', 'alternating6Blocks', '_alternating6Blocks*.mat', +1, 0.05; ...
 '260811_EEG_NWU_MS', 'alternating6Blocks', '_alternating6Blocks*.mat', +1, 0.02; ...
 '251111_EEG_NWU_VW', 'breathingTask', '_breathing*.mat', NaN, 0.05};

for k = 1:size(CASES, 1)
    [id, tkey, glb, flipOv, ff] = CASES{k, :};
    cfg = applyParams(tkey, 'main');
    si = find(strcmp(cfg.sessionIDs, id), 1);
    hits = dir(fullfile(cfg.root{si}, id, 'preProc', [id glb]));
    s = load(fullfile(hits(1).folder, hits(1).name));
    fn = fieldnames(s); od = s.(fn{1}); clear s

    isRsp = cellfun(@(x) contains(x, 'rsp'), od.labels);
    rsp = od.data(isRsp, :);
    if isnan(flipOv), flip = od.rspFlip; else, flip = flipOv; end
    rsp = rsp(od.rspIDX, :) .* flip;
    fs = od.fs;

    bmNew = segmentBreaths_breathMetrics(rsp, fs, ff);
    onsets = round(bmNew(:, 2) * fs);
    fprintf('%s floor %.2f: %d breaths\n', id, ff, size(bmNew, 1));

    N = numel(rsp);
    W = round(60 * fs);
    sLoc = movstd(double(rsp), W);
    nBins = floor(N / (60 * fs));
    binAmp = zeros(1, nBins);
    for w = 1:nBins, binAmp(w) = median(sLoc((w-1)*60*fs+1 : w*60*fs)); end
    [~, ampOrd] = sort(binAmp);
    rng(1000 + k, 'twister');
    pool = setdiff(1:nBins, ampOrd(1:3));
    bins = sort([ampOrd(1:min(3, nBins)), pool(randperm(numel(pool), min(3, numel(pool))))]);

    fig = figure('Visible', 'off', 'Position', [10 10 1500 1350]);
    for b = 1:numel(bins)
        i0 = (bins(b) - 1) * 60 * fs + 1; i1 = bins(b) * 60 * fs;
        t = (i0:i1) / fs;
        subplot(6, 1, b); hold on
        plot(t, rsp(i0:i1), 'k', 'LineWidth', 0.75);
        oi = onsets(onsets >= i0 & onsets <= i1);
        plot(oi / fs, rsp(oi), 'rv', 'MarkerFaceColor', 'r', 'MarkerSize', 6);
        xlim([t(1) t(end)]); ylabel(sprintf('min %d', bins(b)));
        if b == 1
            title(sprintf('%s (flip %+d, floor %.2f): n=%d', ...
                strrep(id, '_', '\_'), flip, ff, size(bmNew, 1)));
        end
        if b == numel(bins), xlabel('time (s)'); end
    end
    saveas(fig, fullfile(outDir, sprintf('floor%03d_%s.jpg', round(ff * 100), id)));
    close(fig);
    clear od rsp
end
fprintf('task389_validateFloor: DONE\n');

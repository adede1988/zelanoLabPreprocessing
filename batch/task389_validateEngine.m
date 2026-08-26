% task389_validateEngine — offline validation of (a) the windowed amplitude
% normalization in segmentBreaths_breathMetrics and (b) the corrected
% August-cohort polarity (no flip), BEFORE any final is rebuilt. Nothing is
% saved to preProc; figures go to E:\reprocBackup_260824\segQC2\.
%
% Cases:
%   VW  breathing (-65.7% under-detected)  -> expect recovery toward ~800
%   DB_1 breathing (well-segmented +51.2%) -> expect little change (no regression)
%   MS  alt6 at rspFlip=+1 (user: no flip; cannula partially unplugged for a
%       stretch) -> onsets at inhale start; weak section NOT amplified
%   JH  alt6 at rspFlip=+1                 -> clean August sanity check

outDir = 'E:\reprocBackup_260824\segQC2';
if ~exist(outDir, 'dir'), mkdir(outDir); end

CASES = { ...  % id, task cfg key, final glob, flip override (NaN = use stored)
 '251111_EEG_NWU_VW',  'breathingTask', '_breathing*.mat', NaN,  275; ...
 '251030_Dupi_NMH_DB_1','breathingTask', '_breathing*.mat', NaN,  183; ...
 '260811_EEG_NWU_MS',  'alternating6Blocks', '_alternating6Blocks*.mat', +1, 272; ...
 '260806_EEG_NWU_JH',  'alternating6Blocks', '_alternating6Blocks*.mat', +1, 723};

for k = 1:size(CASES, 1)
    [id, tkey, glb, flipOv, nOld] = CASES{k, :};
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

    bmNew = segmentBreaths_breathMetrics(rsp, fs);
    onsets = round(bmNew(:, 2) * fs);
    fprintf('%s (%s, flip %+d): %d breaths NEW vs %d stored (July-era ref in title)\n', ...
        id, tkey, flip, size(bmNew, 1), nOld);

    % floor-limiting report: how much of the trace the amplitude floor holds
    % back from full normalization (relevant for MS's leak-attenuated stretch:
    % attenuated-but-real breaths want amplification; a high floor blocks it)
    W = round(60 * fs);
    sLoc = movstd(double(rsp), W);
    fprintf('   %.1f%% of samples below the 0.1x-median amplitude floor\n', ...
        100 * mean(sLoc < 0.1 * median(sLoc)));

    % segments: 3 seeded-random bins + the 3 LOWEST-amplitude bins, so the
    % weak stretches (VW quiet epochs, MS leak section) are always inspected
    N = numel(rsp);
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
            title(sprintf('%s VALIDATE (flip %+d) — windowed-norm engine: n=%d (was %d)', ...
                strrep(id, '_', '\_'), flip, size(bmNew, 1), nOld));
        end
        if b == numel(bins), xlabel('time (s)'); end
    end
    saveas(fig, fullfile(outDir, sprintf('validate_%s.jpg', id)));
    close(fig);
    clear od rsp
end
fprintf('task389_validateEngine: DONE\n');

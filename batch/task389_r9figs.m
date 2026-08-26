% task389_r9figs — post-round-9 segmentation overlays for the rebuilt finals:
% the 5 re-detected breathing sessions and all 8 alternating6Blocks sessions
% (polarity verification: onsets must sit at inhale start on the unflipped
% trace). 3 lowest-amplitude minutes + 3 seeded-random minutes per session.

outDir = 'E:\reprocBackup_260824\segQC_r9';
if ~exist(outDir, 'dir'), mkdir(outDir); end

CASES = [ ...
 cellfun(@(id) {id, 'breathingTask', '_breathing*.mat'}, ...
   {'251111_EEG_NWU_VW', '251002_Dupi_NMH_AB_2', '251008_EEG_NWU_JC', ...
    '251110_EEG_NWU_GA', '251113_EEG_NWU_GH'}, 'UniformOutput', false), ...
 cellfun(@(id) {id, 'alternating6Blocks', '_alternating6Blocks*.mat'}, ...
   {'260805_EEG_NWU_CA', '260806_EEG_NWU_JH', '260806_EEG_NWU_MM', ...
    '260807_EEG_NWU_GP', '260810_EEG_NWU_IS', '260810_EEG_NWU_AL', ...
    '260811_EEG_NWU_MS', '260811_EEG_NWU_HK'}, 'UniformOutput', false)];

for k = 1:numel(CASES)
    [id, tkey, glb] = CASES{k}{:};
    cfg = applyParams(tkey, 'main');
    si = find(strcmp(cfg.sessionIDs, id), 1);
    hits = dir(fullfile(cfg.root{si}, id, 'preProc', [id glb]));
    if isempty(hits), fprintf('%s: NO FINAL - skipped\n', id); continue; end
    s = load(fullfile(hits(1).folder, hits(1).name));
    fn = fieldnames(s); od = s.(fn{1}); clear s

    isRsp = cellfun(@(x) contains(x, 'rsp'), od.labels);
    rsp = od.data(isRsp, :);
    rsp = rsp(od.rspIDX, :) .* od.rspFlip;
    fs = od.fs;
    onsets = round(od.bmObj(:, 2) * fs);

    N = numel(rsp);
    W = round(60 * fs);
    sLoc = movstd(double(rsp), W);
    nBins = floor(N / (60 * fs));
    binAmp = zeros(1, nBins);
    for w = 1:nBins, binAmp(w) = median(sLoc((w-1)*60*fs+1 : w*60*fs)); end
    [~, ampOrd] = sort(binAmp);
    rng(2000 + k, 'twister');
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
            title(sprintf('%s (%s, flip %+d) — rebuilt: n=%d breaths', ...
                strrep(id, '_', '\_'), tkey, od.rspFlip, size(od.bmObj, 1)));
        end
        if b == numel(bins), xlabel('time (s)'); end
    end
    saveas(fig, fullfile(outDir, sprintf('r9_%s_%s.jpg', tkey, id)));
    close(fig);
    fprintf('%s (%s): n=%d flip %+d -> fig\n', id, tkey, size(od.bmObj, 1), od.rspFlip);
    clear od rsp
end
fprintf('task389_r9figs: DONE\n');

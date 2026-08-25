% task8_probeCA2 — second look at CA's ECG. The first probe z-scored globally;
% if noise bursts swamp the variance, real R-peaks fall below 3.5 sigma and
% detection collapses to a symmetric noise floor (~10 bpm) even with a clear
% underlying rhythm. Here: robust (median/MAD) normalization + a 10-s window
% noise mask, beat rates counted inside clean time only, and QC figures.

id = '260805_EEG_NWU_CA';
L = labPaths();
fpath = fullfile(L.rootEEG, id, 'preProc', [id '_alternating6Blockspreproc.mat']);
s = load(fpath); fn = fieldnames(s); od = s.(fn{1}); clear s

figDir = 'E:\reprocBackup_260824\CA_ecg';
if ~exist(figDir, 'dir'), mkdir(figDir); end

isECG = cellfun(@(x) contains(x, 'ECG'), od.labels);
ecg = od.data(isECG, :);
fs = od.fs;
N = size(ecg, 2);
minSep = round(fs / 20);
wLen = 10 * fs;                                   % 10-s noise windows
nW = floor(N / wLen);

for ch = 1:size(ecg, 1)
    xf = bandpass(ecg(ch, :), [5 40], fs);
    zg = (xf - mean(xf)) / std(xf);               % global z (current pipeline)
    zr = (xf - median(xf)) / (1.4826 * mad(xf, 1));  % robust z

    % window noise mask on the robust trace
    wstd = zeros(1, nW);
    for w = 1:nW
        wstd(w) = std(zr((w-1)*wLen+1 : w*wLen));
    end
    noisy = wstd > 3 * median(wstd);
    cleanMask = true(1, N);
    for w = find(noisy)
        cleanMask((w-1)*wLen+1 : w*wLen) = false;
    end
    cleanMin = sum(cleanMask) / fs / 60;
    fprintf('%s ch%d: %.1f%% of windows noisy (median wstd %.2f); clean time %.1f min\n', ...
        id, ch, 100 * mean(noisy), median(wstd), cleanMin);

    pm = '+-';
    for sgn = [1 -1]
        for mode = 1:2
            if mode == 1, z = zg; lab = 'globalZ'; else, z = zr; lab = 'robustZ'; end
            idx = find(sgn * z > 3.5 & cleanMask);
            if isempty(idx), nb = 0; else, nb = 1 + sum(diff(idx) > minSep); end
            fprintf('   ch%d %c3.5 %s (clean-only): %5d beats = %6.1f bpm\n', ...
                ch, pm((3 - sgn) / 2), lab, nb, nb / cleanMin);
        end
    end

    % figures: overview with noise mask + a clean 20-s snippet with markers
    fig = figure('Visible', 'off', 'Position', [20 20 1600 800]);
    subplot(2, 1, 1); hold on
    t = (0:N-1) / fs / 60;
    ds = 1:10:N;                                   % plot-decimate
    plot(t(ds), zr(ds), 'k');
    yl = [-15 15];
    for w = find(noisy)
        patch(([w-1 w w w-1] * wLen) / fs / 60, yl([1 1 2 2]), [1 .8 .8], ...
            'EdgeColor', 'none', 'FaceAlpha', .5);
    end
    ylim(yl); xlabel('min'); ylabel('robust z');
    title(sprintf('%s ECG ch%d — robust z, noise windows shaded (%.0f%%)', ...
        strrep(id, '_', '\_'), ch, 100 * mean(noisy)));
    subplot(2, 1, 2); hold on
    cw = find(~noisy, 1);                          % first clean window
    seg = (cw-1)*wLen+1 : min((cw+1)*wLen, N);     % 20 s
    plot(seg / fs, zr(seg), 'k');
    for sgn = [1 -1]
        idx = find(sgn * zr(seg) > 3.5);
        if ~isempty(idx)
            keep = [true, diff(idx) > minSep];
            plot(seg(idx(keep)) / fs, zr(seg(idx(keep))), 'rv');
        end
    end
    xlabel('s'); ylabel('robust z'); title('first clean 20 s, \pm3.5 crossings marked');
    saveas(fig, fullfile(figDir, sprintf('CA_ecg_ch%d.jpg', ch)));
    close(fig);
end
fprintf('figures -> %s\n', figDir);
fprintf('task8_probeCA2: DONE\n');

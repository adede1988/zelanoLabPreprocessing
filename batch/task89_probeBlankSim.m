% task89_probeBlankSim — (a) simulate the noise-blank fix for CA's ECG: blank
% 10-s windows whose robust-z std exceeds 3x the median, then recompute the
% GLOBAL z-score (what buildECGz produces) and count threshold crossings both
% polarities — the expected pipeline behavior after the fix. (b) re-check RY_1
% with the robust probe: its "no cardiac signal" verdict came from the global
% z-score and may be the same variance-swamping artifact as CA.

L = labPaths();
minSepOf = @(fs) round(fs / 20);
pm = '+-';

% ---------- (a) CA blank simulation ----------
id = '260805_EEG_NWU_CA';
fpath = fullfile(L.rootEEG, id, 'preProc', [id '_alternating6Blockspreproc.mat']);
s = load(fpath); fn = fieldnames(s); od = s.(fn{1}); clear s
isECG = cellfun(@(x) contains(x, 'ECG'), od.labels);
ecg = od.data(isECG, :); fs = od.fs; N = size(ecg, 2);
wLen = 10 * fs; nW = floor(N / wLen); mins = N / fs / 60;
for ch = 1:size(ecg, 1)
    xf = bandpass(ecg(ch, :), [5 40], fs);
    zr = (xf - median(xf)) / (1.4826 * mad(xf, 1));
    wstd = zeros(1, nW);
    for w = 1:nW, wstd(w) = std(zr((w-1)*wLen+1 : w*wLen)); end
    noisy = wstd > 3 * median(wstd);
    xb = xf;
    for w = find(noisy), xb((w-1)*wLen+1 : w*wLen) = 0; end
    zb = (xb - mean(xb)) / std(xb);               % global z AFTER blanking
    for sgn = [1 -1]
        idx = find(sgn * zb > 3.5);
        if isempty(idx), nb = 0; else, nb = 1 + sum(diff(idx) > minSepOf(fs)); end
        fprintf('CA ch%d %c3.5 globalZ-after-blank: %5d beats = %6.1f bpm\n', ...
            ch, pm((3 - sgn) / 2), nb, nb / mins);
    end
end

% ---------- (b) RY_1 robust re-check ----------
id2 = '251006_OBE_NWU_RY_1';
cfg = applyParams('breathingTasks_separate', 'main');
si = find(strcmp(cfg.sessionIDs, id2), 1);
fpath2 = fullfile(cfg.root{si}, id2, 'preProc', [id2 '_breathingTasks_separatepreproc.mat']);
s = load(fpath2); fn = fieldnames(s); od = s.(fn{1}); clear s
isECG = cellfun(@(x) contains(x, 'ECG'), od.labels);
ecg = od.data(isECG, :); fs = od.fs; N = size(ecg, 2);
wLen = 10 * fs; nW = floor(N / wLen);
for ch = 1:size(ecg, 1)
    xf = bandpass(ecg(ch, :), [5 40], fs);
    zr = (xf - median(xf)) / (1.4826 * mad(xf, 1));
    wstd = zeros(1, nW);
    for w = 1:nW, wstd(w) = std(zr((w-1)*wLen+1 : w*wLen)); end
    noisy = wstd > 3 * median(wstd);
    cleanMask = true(1, N);
    for w = find(noisy), cleanMask((w-1)*wLen+1 : w*wLen) = false; end
    cleanMin = sum(cleanMask) / fs / 60;
    fprintf('RY_1 ch%d: %.1f%% windows noisy; clean %.1f min\n', ch, 100*mean(noisy), cleanMin);
    for sgn = [1 -1]
        idx = find(sgn * zr > 3.5 & cleanMask);
        if isempty(idx), nb = 0; else, nb = 1 + sum(diff(idx) > minSepOf(fs)); end
        fprintf('   ch%d %c3.5 robustZ (clean-only): %5d beats = %6.1f bpm\n', ...
            ch, pm((3 - sgn) / 2), nb, nb / cleanMin);
    end
end
fprintf('task89_probeBlankSim: DONE\n');

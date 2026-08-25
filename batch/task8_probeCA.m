% task8_probeCA — CA's alternating6Blocks HRV came out 9.9 bpm on the measured
% Aug-2026 spec (1,0,lt,-3.5): measure beat rate per ECG channel x polarity on
% the saved final (same method as batch/task9_probeECGpolarity.m) to decide
% between a respec and a no-cardiac-signal NaN-HRV outcome.

id = '260805_EEG_NWU_CA';
L = labPaths();
fpath = fullfile(L.rootEEG, id, 'preProc', [id '_alternating6Blockspreproc.mat']);
s = load(fpath); fn = fieldnames(s); od = s.(fn{1}); clear s

isECG = cellfun(@(x) contains(x, 'ECG'), od.labels);
ecg = od.data(isECG, :);
fs = od.fs;
mins = size(ecg, 2) / fs / 60;
fprintf('%s: %d ECG chans, %.1f min\n', id, size(ecg, 1), mins);
minSep = round(fs / 20);
for ch = 1:size(ecg, 1)
    x = bandpass(ecg(ch, :), [5 40], fs);
    x = (x - mean(x)) / std(x);
    for sgn = [1 -1]
        idx = find(sgn * x > 3.5);
        if isempty(idx)
            nb = 0;
        else
            nb = 1 + sum(diff(idx) > minSep);
        end
        pm = '+-';
        fprintf('   ch%d %c3.5: %5d beats = %6.1f bpm\n', ch, ...
            pm((3 - sgn) / 2), nb, nb / mins);
    end
end
fprintf('task8_probeCA: DONE\n');

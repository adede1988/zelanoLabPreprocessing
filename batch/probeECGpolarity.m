% task9_probeECGpolarity — measure ECG beat rate per channel x polarity on the
% saved breathingTasks_separate finals whose HRV came out implausible or was
% dropped by the viability probe (Tasks_260824.md Task 9 follow-up).
%
% For each session: load the final, z-score each 5-40 Hz band-passed ECG
% channel (buildECGz's conditioning), count threshold crossings at +/-3.5
% sigma with the detectBeats minimum separation (fs/20), report bpm for every
% channel x side. A plausible resting rate (40-110 bpm) on exactly one side
% identifies the right beatSpec; ambiguous sessions stay NaN-HRV for manual
% curation.

IDS = {'260625_OBE_NWU_HM_2', '260702_OBE_NWU_SP_2', '260622_OBE_NWU_RC_1', ...
       '260720_OBE_NWU_KA_2', '251006_OBE_NWU_RY_1'};

cfg = applyParams('breathingTasks_separate', 'main');
for k = 1:numel(IDS)
    id = IDS{k};
    si = find(strcmp(cfg.sessionIDs, id), 1);
    if isempty(si), fprintf('%s: not in session list\n', id); continue; end
    fpath = fullfile(cfg.root{si}, id, 'preProc', [id '_breathingTasks_separatepreproc.mat']);
    if ~exist(fpath, 'file'), fprintf('%s: no final\n', id); continue; end
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
    clear od ecg
end
fprintf('task9_probeECGpolarity: DONE\n');

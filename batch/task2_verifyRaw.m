% task2_verifyRaw — verify every extracted raw .mat from Task 2 (step 5) and
% produce the D7 split figures for the JH/MM combined recordings.
%
% Checks per file: loads curDat, verifies label set/order vs the template,
% fsample = 2000, channel count 37, duration in the expected range, NaN
% fraction, and that the rsp/event rows carry signal (std > 0).
% Split figures: full-recording z-scored CSC269 with the split marked, saved to
% the session figure folder (labPaths figPath) and E:\reprocBackup_260824\task2_probe\.

ROOT = 'R:\Neurology\Zelano_Lab\Lab_Common\AllStudyData\EEGbreathing';
OUTD = 'E:\reprocBackup_260824\task2_probe';
L = labPaths();
if isfolder(L.fieldtrip), addpath(L.fieldtrip); else, addpath('E:\GitHub\fieldtrip-20230118'); end
ft_defaults

EXPECTED_LABS = {'Fp1', 'Fz', 'F3', 'F7', 'FT9', 'FC5', 'FC1', ...
                 'C3', 'T7', 'TP9', 'CP5', 'CP1', 'Pz', 'P3', ...
                 'P7', 'O1', 'Oz', 'O2', 'P4', 'P8', 'TP10', ...
                 'CP6', 'CP2', 'Cz', 'C4', 'T8', 'FT10', 'FC6', ...
                 'FC2', 'F4', 'F8', 'Fp2', 'ECG1', 'ECG2', 'ECG3', 'rsp1', 'event'};

% id, task, expected duration range (min)
CHECKS = { ...
 '260227_EEG_NWU_HW', 'waveBreathing',      [50 62]; ...
 '260805_EEG_NWU_CA', 'alternating6Blocks', [55 75]; ...
 '260806_EEG_NWU_JH', 'alternating6Blocks', [50 60]; ...
 '260806_EEG_NWU_JH', 'EmotionalMovieTask', [30 40]; ...
 '260806_EEG_NWU_MM', 'alternating6Blocks', [52 62]; ...
 '260806_EEG_NWU_MM', 'EmotionalMovieTask', [30 40]; ...
 '260807_EEG_NWU_GP', 'alternating6Blocks', [48 60]; ...
 '260807_EEG_NWU_GP', 'EmotionalMovieTask', [28 38]; ...
 '260810_EEG_NWU_IS', 'alternating6Blocks', [50 62]; ...
 '260810_EEG_NWU_IS', 'EmotionalMovieTask', [28 38]; ...
 '260810_EEG_NWU_AL', 'alternating6Blocks', [50 62]; ...
 '260810_EEG_NWU_AL', 'EmotionalMovieTask', [28 38]; ...
 '260811_EEG_NWU_MS', 'alternating6Blocks', [48 60]; ...
 '260811_EEG_NWU_MS', 'EmotionalMovieTask', [28 38]; ...
 '260811_EEG_NWU_HK', 'alternating6Blocks', [52 64]; ...
 '260811_EEG_NWU_HK', 'EmotionalMovieTask', [28 38]};

nPass = 0; nFail = 0;
for k = 1:size(CHECKS, 1)
    [id, task, durRange] = CHECKS{k, :};
    fpath = fullfile(ROOT, id, 'raw', ['raw_' task], ['raw_' task '.mat']);
    fprintf('\n--- %s / %s ---\n', id, task);
    if ~exist(fpath, 'file')
        fprintf('  FAIL: missing %s\n', fpath); nFail = nFail + 1; continue;
    end
    S = load(fpath);
    ok = true;
    cd0 = S.curDat;
    labs = cd0.outLabs;
    if numel(labs) ~= 37 || ~isequal(labs(:)', EXPECTED_LABS)
        fprintf('  FAIL: label mismatch (%d labels)\n', numel(labs)); ok = false;
    end
    fs = cd0.rawData.fsample;
    if fs ~= 2000
        fprintf('  FAIL: fsample = %g (expected 2000)\n', fs); ok = false;
    end
    X = cd0.rawData.trial{1};
    if size(X, 1) ~= 37
        fprintf('  FAIL: %d data rows (expected 37)\n', size(X, 1)); ok = false;
    end
    durMin = size(X, 2) / fs / 60;
    if durMin < durRange(1) || durMin > durRange(2)
        fprintf('  FAIL: duration %.1f min outside [%d %d]\n', durMin, durRange); ok = false;
    end
    nanFrac = mean(isnan(X(:)));
    iRsp = find(strcmp(labs, 'rsp1'), 1);
    iEvt = find(strcmp(labs, 'event'), 1);
    sRsp = std(X(iRsp, ~isnan(X(iRsp, :))));
    sEvt = std(X(iEvt, ~isnan(X(iEvt, :))));
    if ~(sRsp > 0 && sEvt > 0)
        fprintf('  FAIL: flat rsp/event channel (std %g / %g)\n', sRsp, sEvt); ok = false;
    end
    fprintf('  dur %.1f min | fs %d | nanFrac %.4f | rsp std %.3g | event std %.3g -> %s\n', ...
        durMin, fs, nanFrac, sRsp, sEvt, tern(ok, 'PASS', 'FAIL'));
    nPass = nPass + ok; nFail = nFail + ~ok;
    clear S X cd0
end

% ---------------- D7 split figures for JH / MM ----------------
SPLITS = {'260806_EEG_NWU_JH', '2026-08-06_09-23-06', 6810000, 3525.0; ...
          '260806_EEG_NWU_MM', '2026-08-06_13-22-23', 7130600, 3685.3};
if ~isfolder(OUTD), mkdir(OUTD); end
for k = 1:size(SPLITS, 1)
    [id, ts, splitS, pulseSec] = SPLITS{k, :};
    cfg = []; cfg.dataset = fullfile(ROOT, id, 'AtlasData', ts, 'CSC269.ncs');
    dat = ft_preprocessing(cfg);
    x = dat.trial{1}; fs = dat.fsample;
    x(isnan(x)) = 0;
    z = (x - mean(x)) / std(x);
    fig = figure('Visible', 'off', 'Position', [40 40 1500 500]);
    dec = 1:20:numel(z);
    plot(dec / fs / 60, z(dec), 'k'); hold on
    xline(splitS / fs / 60, 'r', 'LineWidth', 2);
    xline(pulseSec / 60, 'b--', 'LineWidth', 1);
    title(sprintf('%s CSC269 z-scored - split at %.1f min (red); first movie pulse %.1f min (blue)', ...
        strrep(id, '_', '\_'), splitS / fs / 60, pulseSec / 60));
    xlabel('minutes'); ylabel('z');
    figDir = fullfile(L.figPath, id);
    if ~isfolder(figDir), mkdir(figDir); end
    saveas(fig, fullfile(figDir, [id '_task2_split.png']));
    saveas(fig, fullfile(OUTD, [id '_task2_split.png']));
    close(fig);
    fprintf('split figure saved for %s (fig folder + %s)\n', id, OUTD);
    clear dat x z
end

fprintf('\ntask2_verifyRaw: DONE  pass=%d fail=%d\n', nPass, nFail);

function out = tern(c, a, b)
    if c, out = a; else, out = b; end
end

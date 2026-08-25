
clear
% ---- machine paths (everything machine-specific comes from labPaths) ----
zlpHere=fileparts(mfilename('fullpath')); zlpRoot=zlpHere; while exist(fullfile(zlpRoot,'config','labPaths.m'),'file')~=2, zlpP=fileparts(zlpRoot); if strcmp(zlpP,zlpRoot), error('zelanoLabPreprocessing root not found'); end; zlpRoot=zlpP; end; addpath(genpath(zlpRoot));
L            = labPaths();
addpath(genpath(L.repo))
addpath(genpath(L.slowBreathing))
addpath(genpath(L.eeglab))

figPath      = L.figPath;
EEGLOC       = readtable(L.eegLocCsv);
set(0, 'defaultfigurewindowstyle', 'normal')

% =====================================================================
%  EmotionalMovieTask preprocessing -- main pipeline (Tasks_260824.md Task 7)
%  TASK-SHARED sections are identical to the other *PreProc_main scripts; do
%  NOT edit them. TASK-SPECIFIC pieces:
%    - assembleRaw_emotionalMovieTask.m        (intermediate load + clip TTL)
%    - emotionalMovieTask_makeOutDat.m         (photodiode -> clip table)
%    - build_behavior_table_emotionalMovieTask.m  (D10 per-breath + clip cols)
%  Breath segmentation: shared segmentBreaths_breathMetrics (no cyclic-sigh
%  merging in this task). ECG runs the breathing path (processECG) when ECG
%  channels exist; otherwise it is skipped and recorded.
% =====================================================================

cfg        = applyParams('emotionalMovieTask','main');
sessionIDs = cfg.sessionIDs;

% Tasks_260824.md D4 batch override (see breathingTaskPreProc_main)
allowGuessRunEnv = strcmp(getenv('ZLP_ALLOW_GUESS_RUN'), '1');

success = ones(length(sessionIDs),1);
for s = 1:numel(sessionIDs)
    try
    disp(['working on ', sessionIDs{s}])
    S = struct;
    S.id   = sessionIDs{s};
    S.root = cfg.root{s};
    S.fig  = fullfile(figPath, S.id);

    % --- Params (before any load so not-run guess sessions cost nothing) ---
    P = applyParams('emotionalMovieTask', S.id);
    isGuess = ~strcmpi(strtrim(P.paramSource), 'curated');
    P.allowGuessRun = allowGuessRunEnv && strcmp(P.type, 'EEG');   % D4
    P.figDir = S.fig;
    if isGuess && allowGuessRunEnv && ~P.allowGuessRun
        disp(['SKIP (guess, not run per D4): ' S.id])
        continue
    end

    % --- done-check: a NEW-format final has moreThan1 AND bmFeatures ---
    preDir = fullfile(S.root, S.id, 'preProc');
    fpath  = fullfile(preDir, [S.id '_EmotionalMovieTaskpreproc.mat']);
    if exist(fpath, 'file')
        chk = load(fpath); fn = fieldnames(chk); chk = chk.(fn{1});
        if isfield(chk, 'moreThan1') && isfield(chk, 'bmFeatures')
            disp(['Done with ' S.id ' ; ' num2str(s)])
            clear chk
            continue
        end
        clear chk
    end

    % --- Assemble: TASK-SPECIFIC loader + shared assembler ---
    raw    = assembleRaw_emotionalMovieTask(S);   % <-- TASK-SPECIFIC
    outDat = assembleOutDat(raw, S, P);           % shared

    if isGuess, [outDat, P] = paramCheck(outDat, P); end

    outDat = downsample_data(outDat, P.fs_target);
    if P.hasEEG, outDat = preprocess_eeg(outDat, EEGLOC, P); end
    if P.hasMacros, outDat = preprocess_macros(outDat, P); end
    disp(['........................spike and blink ', sessionIDs{s}])

    % ===== TASK-SPECIFIC (movie): per-breath segmentation + clip windows =====
    isRsp  = cellfun(@(x) contains(x, 'rsp'), outDat.labels);
    rspDat = outDat.data(isRsp, :);
    rspDat = rspDat(P.rspIDX, :) .* P.rspFlip;
    [outDat.bmObj, outDat.bmFeatures] = segmentBreaths_breathMetrics(rspDat, outDat.fs);
    outDat.moreThan1 = 1;
    outDat.rspIDX  = P.rspIDX;
    outDat.rspFlip = P.rspFlip;

    outDat = build_behavior_table_emotionalMovieTask(outDat);

    % ECG / HRV via the breathing path; skip (and record) when absent, and
    % fall back to NaN HRV when detection fails (bad lead / wrong beatSpec)
    % rather than losing the breath data - flagged for review
    hasECG = sum(cellfun(@(x) contains(x, 'ECG'), outDat.labels)) > 0;
    ecgDone = false;
    if hasECG
        try
            if isGuess, P = paramCheckECG(outDat, P); end
            outDat = processECG(outDat, P);
            outDat = flagBadBreaths(outDat);
            outDat.ecgSkipped = 0;
            ecgDone = true;
        catch MEecg
            warning('%s: ECG processing failed (%s) - HRV set to NaN, REVIEW', ...
                S.id, MEecg.message);
            outDat.ecgSkipped = 2;   % 2 = present but detection failed
        end
    else
        disp(['NO ECG channels for ' S.id ' - HRV columns set to NaN'])
        outDat.ecgSkipped = 1;
    end
    if ~ecgDone
        n = height(outDat.behDat);
        outDat.behDat.goodBreath = nan(n, 1);
        outDat.behDat.maxRR      = nan(n, 1);
        outDat.behDat.minRR      = nan(n, 1);
        outDat.behDat.RR_max_min = nan(n, 1);
    end
    disp(['........................breath behave heart ', sessionIDs{s}])

    % onset-QC figures (shared helpers)
    R = preprocess_respiration_wholetrace(outDat);
    plot_sniff_epochs(outDat, R);
    % ===== end TASK-SPECIFIC =====

    % --- Guess gate (D4 pattern; never promotes paramSource) ---
    if isGuess
        if ~P.allowGuessRun
            error(['EmotionalMovieTask guess params: inspect the saved figures ' ...
                   '(rsp / macros / ECG / clips / onsets), then set paramSource=curated ' ...
                   'in dataTracking.xlsx and re-run.']);
        end
        disp(['RUN-ON-GUESS (D4): saving outputs for ' S.id '; paramSource stays guess'])
    else
        P.paramSource = 'curated';
        writeParams(P, S.id);
    end

    if ~exist(L.procBehavior, 'dir'), mkdir(L.procBehavior); end
    writetable(outDat.behDat, fullfile(L.procBehavior, ...
        [outDat.sessID '_EmotionalMovieTask_processedBreathing.csv']));

    if ~exist(preDir, 'dir'), mkdir(preDir); end
    save(fpath, 'outDat', '-v7.3');
    writePreProcX(P, S.id);

    catch ME
        success(s) = 0;
        disp(['fail for ', sessionIDs{s}, ': ', ME.message]); disp(getReport(ME, 'extended', 'hyperlinks', 'off'))
    end
    close all
end

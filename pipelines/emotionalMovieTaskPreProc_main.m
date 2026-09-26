
clear
% ---- machine paths (everything machine-specific comes from labPaths) ----
zlpHere=fileparts(mfilename('fullpath')); zlpRoot=zlpHere; while exist(fullfile(zlpRoot,'config','labPaths.m'),'file')~=2, zlpP=fileparts(zlpRoot); if strcmp(zlpP,zlpRoot), error('zelanoLabPreprocessing root not found'); end; zlpRoot=zlpP; end; addpath(genpath(zlpRoot));
L            = labPaths();
addpath(genpath(L.repo))
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
%  Breath segmentation: shared segmentBreaths_zlp (no cyclic-sigh
%  merging in this task). ECG runs the breathing path (processECG) when ECG
%  channels exist; otherwise it is skipped and recorded.
% =====================================================================

cfg        = applyParams('emotionalMovieTask','main');
sessionIDs = cfg.sessionIDs;

% Tasks_260824.md D4 batch override (see breathingTaskPreProc_main)
allowGuessRunEnv = strcmp(getenv('ZLP_ALLOW_GUESS_RUN'), '1');

% targeted-run filter (2026-09-01): comma-separated ids in ZLP_MAIN_ONLY
% restrict the sweep (blank = all sessions) - mirrors breathingTaskPreProc_main
mainOnlyEnv = getenv('ZLP_MAIN_ONLY');
mainOnlyList = {};
if ~isempty(mainOnlyEnv), mainOnlyList = strtrim(strsplit(mainOnlyEnv, ',')); end

for s = 1:numel(sessionIDs)
    try
    S = struct;
    S.id   = sessionIDs{s};
    if ~isempty(mainOnlyList) && ~any(strcmp(mainOnlyList, S.id)), continue; end
    disp(['working on ', sessionIDs{s}])
    S.root = cfg.root{s};
    S.fig  = fullfile(figPath, S.id);

    % --- Params (before any load so not-run guess sessions cost nothing) ---
    P = applyParams('emotionalMovieTask', S.id);
    isGuess = ~strcmpi(strtrim(P.paramSource), 'curated');
    % _ALL extension (2026-09-01): TI_1/CP_1 are OBE-type guess sessions the
    % reportResponse directs to run - same override semantics as breathing
    P.allowGuessRun = allowGuessRunEnv && (strcmp(P.type, 'EEG') || ...
        strcmp(getenv('ZLP_ALLOW_GUESS_RUN_ALL'), '1'));   % D4
    % task subfolder (= assembleOutDat's outDat.figs) so the paramCheck PNGs of the
    % session's different breath-type tasks cannot overwrite each other (C12)
    P.figDir = fullfile(S.fig, P.task);
    if isGuess && allowGuessRunEnv && ~P.allowGuessRun
        disp(['SKIP (guess, not run per D4): ' S.id])
        continue
    end

    % --- done-check: a NEW-format final has moreThan1 AND bmFeatures ---
    preDir = fullfile(S.root, S.id, 'preProc');
    fpath  = fullfile(preDir, [S.id '_EmotionalMovieTaskpreproc.mat']);
    if isSessionDone(fpath, {'moreThan1', 'bmFeatures'})
        disp(['Done with ' S.id ' ; ' num2str(s)])
        continue
    end

    % --- Assemble: TASK-SPECIFIC loader + shared assembler ---
    raw    = assembleRaw_emotionalMovieTask(S);   % <-- TASK-SPECIFIC
    outDat = assembleOutDat(raw, S, P);           % shared

    if isGuess, [outDat, P] = paramCheck(outDat, P); end

    outDat = runSharedCore(outDat, P, EEGLOC);   % shared: downsample, EEG, macros
    disp(['........................spike and blink ', sessionIDs{s}])

    % ===== TASK-SPECIFIC (movie): per-breath segmentation + clip windows =====
    isRsp  = cellfun(@(x) contains(x, 'rsp'), outDat.labels);
    rspDat = outDat.data(isRsp, :);
    rspDat = rspDat(P.rspIDX, :) .* P.rspFlip;
    % 260811_EEG_NWU_MS: leak-attenuated stretch (partially unplugged cannula
    % tube) - QC review decision (2026-08-26): exclude it, don't amplify it
    blank = [];
    if strcmp(S.id, '260811_EEG_NWU_MS'), blank = 0.10; end
    [outDat.bmObj, outDat.bmFeatures] = segmentBreaths_zlp(rspDat, outDat.fs, [], blank, []);
    outDat.moreThan1 = 1;
    outDat.rspIDX  = P.rspIDX;
    outDat.rspFlip = P.rspFlip;

    outDat = build_behavior_table_emotionalMovieTask(outDat);

    % ECG / HRV via the breathing path; skip (and record) when absent, and
    % fall back to NaN HRV when detection fails (bad lead / wrong beatSpec)
    % rather than losing the breath data - flagged for review (shared stage)
    [outDat, P] = runECGStage(outDat, P, isGuess, S.id);
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
        disp(['fail for ', sessionIDs{s}, ': ', ME.message]); disp(getReport(ME, 'extended', 'hyperlinks', 'off'))
    end
    close all
end

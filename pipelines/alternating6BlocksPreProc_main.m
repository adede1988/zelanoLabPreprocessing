
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
%  alternating6Blocks preprocessing -- main pipeline (Tasks_260824.md Task 8)
%  TASK-SPECIFIC pieces:
%    - alternating6Blocks_makeOutDat.m   (raw + gdrive logs -> intermediate
%      with blocks / ratings / log alignment)
%    - assembleRaw_alternating6Blocks.m  (intermediate load + blocks/TTL)
%    - build_behavior_table_alternating6Blocks.m  (D11d per-breath + ratings)
%  Breath segmentation: shared segmentBreaths_zlp. ECG via the
%  breathing path (these EEG_breathing sessions all carry ECG1-3).
% =====================================================================

cfg        = applyParams('alternating6Blocks','main');
sessionIDs = cfg.sessionIDs;

% Tasks_260824.md D4 batch override (see breathingTaskPreProc_main)
allowGuessRunEnv = strcmp(getenv('ZLP_ALLOW_GUESS_RUN'), '1');

for s = 1:numel(sessionIDs)
    try
    disp(['working on ', sessionIDs{s}])
    S = struct;
    S.id   = sessionIDs{s};
    S.root = cfg.root{s};
    S.fig  = fullfile(figPath, S.id);

    P = applyParams('alternating6Blocks', S.id);
    isGuess = ~strcmpi(strtrim(P.paramSource), 'curated');
    P.allowGuessRun = allowGuessRunEnv && strcmp(P.type, 'EEG');   % D4
    % task subfolder (= assembleOutDat's outDat.figs) so the paramCheck PNGs of the
    % session's different breath-type tasks cannot overwrite each other (C12)
    P.figDir = fullfile(S.fig, P.task);
    if isGuess && allowGuessRunEnv && ~P.allowGuessRun
        disp(['SKIP (guess, not run per D4): ' S.id])
        continue
    end

    % --- done-check ---
    preDir = fullfile(S.root, S.id, 'preProc');
    fpath  = fullfile(preDir, [S.id '_alternating6Blockspreproc.mat']);
    if isSessionDone(fpath, {'moreThan1', 'bmFeatures'})
        disp(['Done with ' S.id ' ; ' num2str(s)])
        continue
    end

    % --- Assemble: TASK-SPECIFIC loader + shared assembler ---
    raw    = assembleRaw_alternating6Blocks(S);   % <-- TASK-SPECIFIC
    outDat = assembleOutDat(raw, S, P);           % shared
    outDat.blocks   = raw.blocks;
    outDat.logAlign = raw.logAlign;

    % the makeOutDat's log alignment empirically determined the respiration
    % polarity; a sheet value that contradicts it would invert every breath
    if isfield(raw.logAlign, 'rspFlip') && raw.logAlign.rspFlip ~= P.rspFlip
        error(['%s: sheet rspFlip (%+d) contradicts the log-alignment ' ...
               'polarity (%+d) - fix the sheet guess before running'], ...
               S.id, P.rspFlip, raw.logAlign.rspFlip);
    end

    if isGuess, [outDat, P] = paramCheck(outDat, P); end

    outDat = runSharedCore(outDat, P, EEGLOC);   % shared: downsample, EEG, macros
    disp(['........................spike and blink ', sessionIDs{s}])

    % ===== TASK-SPECIFIC (alternating6Blocks) =====
    isRsp  = cellfun(@(x) contains(x, 'rsp'), outDat.labels);
    rspDat = outDat.data(isRsp, :);
    rspDat = rspDat(P.rspIDX, :) .* P.rspFlip;
    % 260811_EEG_NWU_MS: cannula tube partially unplugged for ~23% of the
    % recording - QC review decision (2026-08-26): EXCLUDE the leak-attenuated
    % stretch (blank it in the detection copy) rather than amplify it
    blank = [];
    if strcmp(S.id, '260811_EEG_NWU_MS'), blank = 0.10; end
    [outDat.bmObj, outDat.bmFeatures] = segmentBreaths_zlp(rspDat, outDat.fs, [], blank, []);
    outDat.moreThan1 = 1;
    outDat.rspIDX  = P.rspIDX;
    outDat.rspFlip = P.rspFlip;

    outDat = build_behavior_table_alternating6Blocks(outDat);

    % ECG with NaN-HRV fallback on detection failure (flagged for review)
    [outDat, P] = runECGStage(outDat, P, isGuess, S.id);
    disp(['........................breath behave heart ', sessionIDs{s}])

    R = preprocess_respiration_wholetrace(outDat);
    plot_sniff_epochs(outDat, R);
    % ===== end TASK-SPECIFIC =====

    % --- Guess gate (D4 pattern; never promotes paramSource) ---
    if isGuess
        if ~P.allowGuessRun
            error(['alternating6Blocks guess params: inspect the saved figures, ' ...
                   'then set paramSource=curated in dataTracking.xlsx and re-run.']);
        end
        disp(['RUN-ON-GUESS (D4): saving outputs for ' S.id '; paramSource stays guess'])
    else
        P.paramSource = 'curated';
        writeParams(P, S.id);
    end

    if ~exist(L.procBehavior, 'dir'), mkdir(L.procBehavior); end
    writetable(outDat.behDat, fullfile(L.procBehavior, ...
        [outDat.sessID '_alternating6Blocks_processedBreathing.csv']));

    if ~exist(preDir, 'dir'), mkdir(preDir); end
    save(fpath, 'outDat', '-v7.3');
    writePreProcX(P, S.id);

    catch ME
        disp(['fail for ', sessionIDs{s}, ': ', ME.message]); disp(getReport(ME, 'extended', 'hyperlinks', 'off'))
    end
    close all
end

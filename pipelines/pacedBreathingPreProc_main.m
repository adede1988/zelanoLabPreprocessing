
clear
% ---- machine paths (everything machine-specific comes from labPaths) ----
zlpHere=fileparts(mfilename('fullpath')); zlpRoot=zlpHere; while exist(fullfile(zlpRoot,'config','labPaths.m'),'file')~=2, zlpP=fileparts(zlpRoot); if strcmp(zlpP,zlpRoot), error('zelanoLabPreprocessing root not found'); end, zlpRoot=zlpP; end, addpath(genpath(zlpRoot));
L            = labPaths();
addpath(genpath(L.repo))
addpath(genpath(L.slowBreathing))
addpath(genpath(L.eeglab))

figPath      = L.figPath;
EEGLOC       = readtable(L.eegLocCsv);
set(0, 'defaultfigurewindowstyle', 'normal')

% =====================================================================
%  pacedBreathing preprocessing -- main pipeline (added 2026-09-15)
%  A single continuous EEG_breathing recording with NO event marks and no
%  behavioral file: ~7 min audiobook/survey, ~90 min of paced breathing at
%  a sweep of paces and depths (brief breaks between blocks), ~10 min of
%  focused breathing at the end. Block boundaries are INFERRED from the
%  segmented breaths (inferBlocks_pacedBreathing) - labels are positional.
%  TASK-SPECIFIC pieces:
%    - assembleRaw_pacedBreathing.m        (raw_pacedBreathing.mat, no makeOutDat)
%    - inferBlocks_pacedBreathing.m        (blocks table + breathing-style TTL)
%    - build_behavior_table_pacedBreathing.m (per-breath + regularity extras)
%  Breath segmentation: shared segmentBreaths_zlp. ECG via the breathing
%  path (EEG_breathing sessions carry ECG1-3).
% =====================================================================

cfg        = applyParams('pacedBreathing','main');
sessionIDs = cfg.sessionIDs;

% Tasks_260824.md D4 batch override (see breathingTaskPreProc_main)
allowGuessRunEnv = strcmp(getenv('ZLP_ALLOW_GUESS_RUN'), '1');
mainOnlyEnv = strtrim(getenv('ZLP_MAIN_ONLY'));            % optional session filter
onlyIDs = {};
if ~isempty(mainOnlyEnv)
    onlyIDs = strtrim(strsplit(mainOnlyEnv, ',')); onlyIDs = onlyIDs(~cellfun(@isempty, onlyIDs));
end

success = ones(length(sessionIDs),1);
for s = 1:numel(sessionIDs)
    try
    if ~isempty(onlyIDs) && ~any(strcmpi(onlyIDs, sessionIDs{s}))
        continue
    end
    disp(['working on ', sessionIDs{s}])
    S = struct;
    S.id   = sessionIDs{s};
    S.root = cfg.root{s};
    S.fig  = fullfile(figPath, S.id);

    P = applyParams('pacedBreathing', S.id);
    isGuess = ~strcmpi(strtrim(P.paramSource), 'curated');
    P.allowGuessRun = allowGuessRunEnv && strcmp(P.type, 'EEG');   % D4
    P.figDir = S.fig;
    if isGuess && allowGuessRunEnv && ~P.allowGuessRun
        disp(['SKIP (guess, not run per D4): ' S.id])
        continue
    end

    % --- done-check ---
    preDir = fullfile(S.root, S.id, 'preProc');
    fpath  = fullfile(preDir, [S.id '_pacedBreathingpreproc.mat']);
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
    raw    = assembleRaw_pacedBreathing(S);       % <-- TASK-SPECIFIC (no makeOutDat)
    outDat = assembleOutDat(raw, S, P);           % shared
    outDat.CSClist       = raw.CSClist;           % provenance (O15-style extras)
    outDat.OGdataDir     = raw.OGdataDir;
    outDat.loadFile      = raw.loadFile;
    outDat.preProcScript = 'pacedBreathingPreProc_main.m';
    clear raw

    if isGuess, [outDat, P] = paramCheck(outDat, P); end

    outDat = downsample_data(outDat, P.fs_target);
    if P.hasEEG, outDat = preprocess_eeg(outDat, EEGLOC, P); end
    if P.hasMacros, outDat = preprocess_macros(outDat, P); end
    disp(['........................spike and blink ', sessionIDs{s}])

    % ===== TASK-SPECIFIC (pacedBreathing) =====
    isRsp  = cellfun(@(x) contains(x, 'rsp'), outDat.labels);
    rspDat = outDat.data(isRsp, :);
    rspDat = rspDat(P.rspIDX, :) .* P.rspFlip;
    [outDat.bmObj, outDat.bmFeatures] = segmentBreaths_zlp(rspDat, outDat.fs);
    outDat.moreThan1 = 1;
    outDat.rspIDX  = P.rspIDX;
    outDat.rspFlip = P.rspFlip;

    % blocks are inferred from the breaths (no markers); labels positional
    [outDat.blocks, outDat.TTL, outDat.blockInference] = ...
        inferBlocks_pacedBreathing(outDat.bmObj, outDat.fs, size(outDat.data, 2), P.pacedOpts);
    outDat.bmObj(:, 12) = outDat.blockInference.blkOfBreath;   % condition = block index
    plotBlocks_pacedBreathing(outDat, rspDat);                  % QC figure -> outDat.figs

    outDat = build_behavior_table_pacedBreathing(outDat);

    % ECG with NaN-HRV fallback on detection failure (flagged for review)
    ecgDone = false;
    try
        % viability probe (as in breathingTasks_separate): an implausible beat
        % rate means no usable cardiac signal - NaN HRV, not garbage RRint
        [ECGzP, sepP] = buildECGz(outDat);
        bpmP = numel(P.getBeats(ECGzP, sepP)) / (size(outDat.data, 2) / outDat.fs / 60);
        clear ECGzP
        assert(bpmP >= 20, '%s: beat detection implausible (%.1f bpm)', S.id, bpmP);
        if isGuess, P = paramCheckECG(outDat, P); end
        outDat = processECG(outDat, P);
        outDat = flagBadBreaths(outDat);
        outDat.ecgSkipped = 0;
        ecgDone = true;
    catch MEecg
        warning('%s: ECG processing failed (%s) - HRV set to NaN, REVIEW', ...
            S.id, MEecg.message);
        outDat.ecgSkipped = 2;
    end
    if ~ecgDone
        n = height(outDat.behDat);
        outDat.behDat.goodBreath = nan(n, 1);
        outDat.behDat.maxRR      = nan(n, 1);
        outDat.behDat.minRR      = nan(n, 1);
        outDat.behDat.RR_max_min = nan(n, 1);
    end
    disp(['........................breath behave heart ', sessionIDs{s}])

    R = preprocess_respiration_wholetrace(outDat);
    plot_sniff_epochs(outDat, R);
    % ===== end TASK-SPECIFIC =====

    % --- Guess gate (D4 pattern; never promotes paramSource) ---
    if isGuess
        if ~P.allowGuessRun
            error(['pacedBreathing guess params: inspect the saved figures, ' ...
                   'then set paramSource=curated in dataTracking.xlsx and re-run.']);
        end
        disp(['RUN-ON-GUESS (D4): saving outputs for ' S.id '; paramSource stays guess'])
    else
        P.paramSource = 'curated';
        writeParams(P, S.id);
    end

    if ~exist(L.procBehavior, 'dir'), mkdir(L.procBehavior); end
    writetable(outDat.behDat, fullfile(L.procBehavior, ...
        [outDat.sessID '_pacedBreathing_processedBreathing.csv']));
    writetable(outDat.blocks, fullfile(L.procBehavior, ...
        [outDat.sessID '_pacedBreathing_blocks.csv']));

    if ~exist(preDir, 'dir'), mkdir(preDir); end
    save(fpath, 'outDat', '-v7.3');
    writePreProcX(P, S.id);

    catch ME
        success(s) = 0;
        disp(['fail for ', sessionIDs{s}, ': ', ME.message]); disp(getReport(ME, 'extended', 'hyperlinks', 'off'))
    end
    close all
end

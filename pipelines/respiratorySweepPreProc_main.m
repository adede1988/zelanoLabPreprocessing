clear
% ---- machine paths (everything machine-specific comes from labPaths) ----
zlpHere=fileparts(mfilename('fullpath')); zlpRoot=zlpHere; while exist(fullfile(zlpRoot,'config','labPaths.m'),'file')~=2, zlpP=fileparts(zlpRoot); if strcmp(zlpP,zlpRoot), error('zelanoLabPreprocessing root not found'); end, zlpRoot=zlpP; end, addpath(genpath(zlpRoot));
L            = labPaths();
addpath(genpath(L.repo))
addpath(genpath(L.eeglab))
if batchStartupOptionUsed, set(groot, 'DefaultFigureVisible', 'off'); end   % no figure pop-ups in -batch runs

figPath      = L.figPath;
EEGLOC       = readtable(L.eegLocCsv);
set(0, 'defaultfigurewindowstyle', 'normal')

% =====================================================================
%  respiratorySweep preprocessing -- main pipeline (added 2026-10-08)
%  One continuous EEG_breathing recording per session (first sessions
%  261006_EEG_NWU_RC / _IS): baseline ratings, a 6-min audiobook (natural
%  breathing), then 18 paced blocks of 150 s - 3 passes (depth 1.00, 0.85,
%  1.15 x the participant's calibrated breath size) through the paces 15, 13,
%  10, 8, 6, 4 breaths/min, tracing a target trace on screen - post-sweep
%  ratings, and (first sessions) 2 x 6 min focused breathing + 2 x 6 min
%  audiobook run off-script with a stopwatch.
%  The Atlas recording carries NO event marks: each session's LoadData script
%  aligns the SniffLogic log(s) to the raw respiration (shared/alignLogToRaw)
%  and hard-codes the stopwatch blocks from the session notes, writing the
%  event table into the raw file (curDat.TTL; buildSweepTTL). No makeOutDat.
%  TASK-SPECIFIC pieces:
%    - assembleRaw_respiratorySweep.m         (raw + event table + ratings)
%    - build_behavior_table_respiratorySweep.m (per-breath, all breaths)
%    - plotBlocks_respiratorySweep.m          (QC figures)
%  Breath segmentation: shared segmentBreaths_zlp. ECG via runECGStage.
%  Final: <id>_respiratorySweeppreproc.mat with outDat.blocks (fs 500),
%  TTL = block starts, TTLinfo (alignment record), a targTrace channel (the
%  target the participant traced, log units, 0 outside sweep blocks), ratings
%  / baseEmotion / postSweepEmotion.
% =====================================================================

cfg        = applyParams('respiratorySweep','main');
sessionIDs = cfg.sessionIDs;

% Tasks_260824.md D4 batch override (see breathingTaskPreProc_main)
allowGuessRunEnv = strcmp(getenv('ZLP_ALLOW_GUESS_RUN'), '1');
mainOnlyEnv = strtrim(getenv('ZLP_MAIN_ONLY'));            % optional session filter
onlyIDs = {};
if ~isempty(mainOnlyEnv)
    onlyIDs = strtrim(strsplit(mainOnlyEnv, ',')); onlyIDs = onlyIDs(~cellfun(@isempty, onlyIDs));
end

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

    P = applyParams('respiratorySweep', S.id);
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
    fpath  = fullfile(preDir, [S.id '_respiratorySweeppreproc.mat']);
    if isSessionDone(fpath, {'moreThan1', 'bmFeatures'})
        disp(['Done with ' S.id ' ; ' num2str(s)])
        continue
    end

    % --- Assemble: TASK-SPECIFIC loader + shared assembler ---
    raw    = assembleRaw_respiratorySweep(S);     % <-- TASK-SPECIFIC (no makeOutDat)
    outDat = assembleOutDat(raw, S, P);           % shared
    outDat.CSClist       = raw.CSClist;           % provenance (O15-style extras)
    outDat.OGdataDir     = raw.OGdataDir;
    outDat.loadFile      = raw.loadFile;
    outDat.preProcScript = 'respiratorySweepPreProc_main.m';
    outDat.TTLinfo       = raw.TTLinfo;
    blocksRaw = raw.blocksRaw;
    logTrace  = raw.logTrace;
    clear raw

    % the log alignment measured the polarity of the aligned channel (rsp1);
    % a sheet value that contradicts it would invert every breath
    if P.rspIDX == 1 && outDat.TTLinfo.rspFlip ~= P.rspFlip
        error(['%s: sheet rspFlip (%+d) contradicts the log-alignment polarity ' ...
               '(%+d) - fix the sheet before running'], S.id, P.rspFlip, outDat.TTLinfo.rspFlip);
    elseif P.rspIDX ~= 1
        fprintf(['%s: rspIDX %d is not the log-aligned channel (rsp1) - the log polarity check is ' ...
                 'skipped; verify rspFlip on the paramCheck figure\n'], S.id, P.rspIDX);
    end

    if isGuess, [outDat, P] = paramCheck(outDat, P); end

    outDat = runSharedCore(outDat, P, EEGLOC);   % shared: downsample, EEG, macros
    disp(['........................spike and blink ', sessionIDs{s}])

    % ===== TASK-SPECIFIC (respiratorySweep) =====
    % event table: raw samples -> final samples (time-exact: raw sample k is at
    % (k-1)/origFS s, final sample j at (j-1)/fs s); the start rounds to the
    % nearest final sample, the inclusive end to the last final sample at or
    % before the raw end sample's time; TTL = block starts
    nS = size(outDat.data, 2);
    blocks = blocksRaw;
    blocks.startSample = round((blocksRaw.startSample - 1) * outDat.fs / outDat.origFS) + 1;
    blocks.endSample   = min(nS, floor((blocksRaw.endSample - 1) * outDat.fs / outDat.origFS) + 1);
    assert(all(blocks.startSample >= 1 & blocks.endSample > blocks.startSample), 'block conversion failed');
    outDat.blocks = blocks;
    outDat.TTL = blocks.startSample';              % breathing-style vector (block starts)

    % target trace the participant traced (SniffLogic target_pa, log units),
    % 0 outside the sweep blocks (breathingTask targTrace convention)
    tg = (0:numel(logTrace.target) - 1) / logTrace.fs;
    targ = interp1(tg, double(logTrace.target), (0:nS - 1) / outDat.fs, 'linear');
    targ(~isfinite(targ)) = 0;
    outDat.data(end + 1, :) = targ;
    outDat.labels{end + 1} = 'targTrace';
    clear tg targ logTrace

    isRsp  = cellfun(@(x) contains(x, 'rsp'), outDat.labels);
    rspDat = outDat.data(isRsp, :);
    rspDat = rspDat(P.rspIDX, :) .* P.rspFlip;
    [outDat.bmObj, outDat.bmFeatures] = segmentBreaths_zlp(rspDat, outDat.fs);
    outDat.moreThan1 = 1;
    outDat.rspIDX  = P.rspIDX;
    outDat.rspFlip = P.rspFlip;

    outDat = build_behavior_table_respiratorySweep(outDat);   % sets bmObj col 12 = block order

    % ECG with NaN-HRV fallback on detection failure (flagged for review)
    [outDat, P] = runECGStage(outDat, P, isGuess, S.id);
    disp(['........................breath behave heart ', sessionIDs{s}])

    plotBlocks_respiratorySweep(outDat, rspDat);              % QC figures -> outDat.figs
    R = preprocess_respiration_wholetrace(outDat);
    plot_sniff_epochs(outDat, R);
    clear R rspDat
    % ===== end TASK-SPECIFIC =====

    % --- Guess gate (D4 pattern; never promotes paramSource) ---
    if isGuess
        if ~P.allowGuessRun
            error(['respiratorySweep guess params: inspect the saved figures, ' ...
                   'then set paramSource=curated in dataTracking.xlsx and re-run.']);
        end
        disp(['RUN-ON-GUESS (D4): saving outputs for ' S.id '; paramSource stays guess'])
    else
        P.paramSource = 'curated';
        writeParams(P, S.id);
    end

    if ~exist(L.procBehavior, 'dir'), mkdir(L.procBehavior); end
    writetable(outDat.behDat, fullfile(L.procBehavior, ...
        [outDat.sessID '_respiratorySweep_processedBreathing.csv']));
    writetable(outDat.blocks, fullfile(L.procBehavior, ...
        [outDat.sessID '_respiratorySweep_blocks.csv']));

    if ~exist(preDir, 'dir'), mkdir(preDir); end
    save(fpath, 'outDat', '-v7.3');
    writePreProcX(P, S.id);

    catch ME
        disp(['fail for ', sessionIDs{s}, ': ', ME.message]); disp(getReport(ME, 'extended', 'hyperlinks', 'off'))
    end
    close all
end

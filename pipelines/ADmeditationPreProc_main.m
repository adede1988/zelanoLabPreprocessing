
clear
% ---- machine paths (everything machine-specific comes from labPaths) ----
zlpHere=fileparts(mfilename('fullpath')); zlpRoot=zlpHere; while exist(fullfile(zlpRoot,'config','labPaths.m'),'file')~=2, zlpP=fileparts(zlpRoot); if strcmp(zlpP,zlpRoot), error('zelanoLabPreprocessing root not found'); end, zlpRoot=zlpP; end, addpath(genpath(zlpRoot));
L            = labPaths();
addpath(genpath(L.repo))
addpath(genpath(L.eeglab))

figPath      = L.figPath;
EEGLOC       = readtable(L.eegLocCsv);
set(0, 'defaultfigurewindowstyle', 'normal')
if batchStartupOptionUsed   % matlab -batch: no figure windows (shared helpers call figure; visibly); files are still saved
    set(groot, 'DefaultFigureVisible', 'off');
end

% =====================================================================
%  ADmeditation preprocessing -- main pipeline (added 2026-10-08)
%  Adam's repeated ~60-min seated meditation recordings
%  (R:\...\AllStudyData\AD_repeatRecordings\<yyyy-mm-dd_hh-mm-ss>\), one
%  continuous Atlas recording per session on the EEG_breathing rig (32-ch EEG,
%  ECG1-3, rsp1-2, event). Tracked in their OWN sheet,
%  Admin\Data\dataTracking_AD_meditation.xlsx (labPaths().adMedXlsx) - not in
%  dataTracking.xlsx; applyParams / writeParams / writePreProcX switch to it
%  for this task. Raw: <root>\raw\<id>_raw.mat (LoadData_ADmeditation_claude.m
%  in the study folder extracts every not-yet-imported recording); final:
%  <root>\preProc\<id>_ADmeditationpreproc.mat.
%  The only marker is a button on the event channel pressed at a "good"
%  meditative state: detected on the whole raw event trace, carried into the
%  final as outDat.buttonPresses (table) and outDat.TTL (press-onset samples
%  in the analysis window, fs = 500), plus per-breath press columns in behDat.
%  Every recording is TRIMMED before processing: first 3 min and last 1 min
%  dropped (P.adMedOpts; outDat.trim maps final samples back to the raw file).
%  Eyes are closed throughout -> no blink removal (P.blinkRemoval = false, as
%  vipassana).
%  TASK-SPECIFIC pieces (tasks/ADmeditation/):
%    - assembleRaw_ADmeditation.m          (raw load, presses, trim; no makeOutDat)
%    - detectButtonPresses_ADmeditation.m  (press / release steps on the event channel)
%    - build_behavior_table_ADmeditation.m (per-breath + regularity + press columns)
%    - plotQC_ADmeditation.m               (one-page QC figure)
%  Shared: runSharedCore, segmentBreaths_zlp, runECGStage, checkRspPolarityRSA
%  (tasks/vipassana; inhale-locked RR sanity check on rspFlip).
% =====================================================================

cfg        = applyParams('ADmeditation','main');
sessionIDs = cfg.sessionIDs;

% Tasks_260824.md D4 batch override (see pacedBreathingPreProc_main)
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

    P = applyParams('ADmeditation', S.id);
    isGuess = ~strcmpi(strtrim(P.paramSource), 'curated');
    P.allowGuessRun = allowGuessRunEnv && strcmp(P.type, 'EEG');   % D4
    P.figDir = fullfile(S.fig, P.task);
    if isGuess && allowGuessRunEnv && ~P.allowGuessRun
        disp(['SKIP (guess, not run per D4): ' S.id])
        continue
    end

    % --- done-check ---
    preDir = fullfile(S.root, 'preProc');
    fpath  = fullfile(preDir, [S.id '_ADmeditationpreproc.mat']);
    if isSessionDone(fpath, {'moreThan1', 'bmFeatures'})
        disp(['Done with ' S.id ' ; ' num2str(s)])
        continue
    end

    % --- Assemble: TASK-SPECIFIC loader + shared assembler ---
    raw    = assembleRaw_ADmeditation(S, P);      % <-- TASK-SPECIFIC (no makeOutDat; presses + trim)
    outDat = assembleOutDat(raw, S, P);           % shared
    outDat.CSClist       = raw.CSClist;           % provenance (O15/pacedBreathing-style extras)
    outDat.OGdataDir     = raw.OGdataDir;
    outDat.loadFile      = raw.loadFile;
    outDat.atlasFolder   = raw.atlasFolder;
    outDat.preProcScript = 'ADmeditationPreProc_main.m';
    outDat.trim          = raw.trim;
    pressesRaw           = raw.presses;
    outDat.pressInfo     = raw.pressInfo;
    if isfield(raw, 'segments'), outDat.segmentsRaw = raw.segments; end
    clear raw

    if isGuess, [outDat, P] = paramCheck(outDat, P); end

    outDat = runSharedCore(outDat, P, EEGLOC);   % shared: downsample, EEG (no blink removal), macros
    disp(['........................shared core ', sessionIDs{s}])

    % ===== TASK-SPECIFIC (ADmeditation) =====
    % button presses -> the final rate (trimmed timeline); TTL = onsets of the
    % presses in the analysis window
    pr = pressesRaw;
    pr.sample        = toTargetSamples(pr.onsetTrim, outDat.origFS, outDat.fs);
    pr.releaseSample = toTargetSamples(pr.releaseTrim, outDat.origFS, outDat.fs);
    pr.sample(pr.sample < 1) = 1;
    pr.timeSec = (pr.sample - 1) / outDat.fs;           % from the start of the analysed data
    outDat.buttonPresses = pr;
    outDat.TTL = pr.sample(pr.inAnalysisWindow);
    clear pressesRaw

    % recording segments (multi-file acquisitions) -> final rate, as pacedBreathing
    outDat.segments = table();
    if isfield(outDat, 'segmentsRaw')
        sg = outDat.segmentsRaw;
        sg.startSample = round((sg.startSample - 1) * outDat.fs / outDat.origFS) + 1;
        sg.nSamples    = [diff(sg.startSample); size(outDat.data, 2) - sg.startSample(end) + 1];
        outDat.segments = sg;
        outDat = rmfield(outDat, 'segmentsRaw');
    end

    isRsp  = cellfun(@(x) contains(x, 'rsp'), outDat.labels);
    rspDat = outDat.data(isRsp, :);
    rspDat = rspDat(P.rspIDX, :) .* P.rspFlip;
    [outDat.bmObj, outDat.bmFeatures] = segmentBreaths_zlp(rspDat, outDat.fs);
    outDat.bmObj(:, 12) = 1;                       % one continuous meditation = condition 1
    outDat.moreThan1 = 1;
    outDat.rspIDX   = P.rspIDX;
    outDat.rspFlip  = P.rspFlip;
    outDat.beatSpec = P.beatSpec;

    outDat = build_behavior_table_ADmeditation(outDat);

    % ECG with NaN-HRV fallback on detection failure (flagged for review)
    [outDat, P] = runECGStage(outDat, P, isGuess, S.id);
    outDat.beatSpec = P.beatSpec;                  % paramCheckECG may have changed it
    disp(['........................breath behave heart ', sessionIDs{s}])

    % inhale-locked RR sanity check on rspFlip (every breath is a still,
    % seated meditation breath -> the check's 'still' selector is all true)
    if outDat.ecgSkipped == 0
        chk = outDat; chk.behDat.still = true(height(chk.behDat), 1);
        outDat.rspPolarityRSA = checkRspPolarityRSA(chk);
        clear chk
    else
        outDat.rspPolarityRSA = struct('deltaRRms', NaN, 'nBreaths', 0, 'consistent', false);
    end
    R = preprocess_respiration_wholetrace(outDat);
    plot_sniff_epochs(outDat, R);
    plotQC_ADmeditation(outDat, rspDat);
    clear R rspDat
    % ===== end TASK-SPECIFIC =====

    % --- Guess gate (D4 pattern; never promotes paramSource) ---
    if isGuess
        if ~P.allowGuessRun
            error(['ADmeditation guess params: inspect the saved figures, then set ' ...
                   'paramSource=curated in dataTracking_AD_meditation.xlsx and re-run.']);
        end
        disp(['RUN-ON-GUESS (D4): saving outputs for ' S.id '; paramSource stays guess'])
    else
        P.paramSource = 'curated';
        writeParams(P, S.id);
    end

    if ~exist(L.procBehavior, 'dir'), mkdir(L.procBehavior); end
    writetable(outDat.behDat, fullfile(L.procBehavior, ...
        [outDat.sessID '_ADmeditation_processedBreathing.csv']));
    writetable(outDat.buttonPresses, fullfile(L.procBehavior, ...
        [outDat.sessID '_ADmeditation_buttonPresses.csv']));

    if ~exist(preDir, 'dir'), mkdir(preDir); end
    save(fpath, 'outDat', '-v7.3');
    writePreProcX(P, S.id);
    hrBpm = NaN;
    if outDat.ecgSkipped == 0, hrBpm = round(numel(outDat.heartBeats) / (size(outDat.data, 2) / outDat.fs / 60), 1); end
    writeSheetADmed(S.id, {'Analyzed Duration (min)', round(size(outDat.data, 2) / outDat.fs / 60, 2), ...
        'nButtonPresses', sum(outDat.buttonPresses.inAnalysisWindow), ...
        'nPressesTrimmed', sum(~outDat.buttonPresses.inAnalysisWindow), ...
        'nBreaths', height(outDat.behDat), 'meanHR (bpm)', hrBpm});

    catch ME
        disp(['fail for ', sessionIDs{s}, ': ', ME.message]); disp(getReport(ME, 'extended', 'hyperlinks', 'off'))
    end
    close all
end

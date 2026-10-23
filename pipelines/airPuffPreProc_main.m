
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
%  airPuff preprocessing -- main pipeline (added 2026-10-15 with
%  261008_INR_NWU_SS_1)
%  The participant holds their breath and air is puffed up the nose through a
%  tube. On the DAQ event channel: a lead marker (protocol: 3 pulses; SS_1: 1),
%  then one pulse per puff delivered with a "Puff" auditory cue ('cued' run),
%  a 3-pulse separator, then one pulse per puff with no cue (the participant
%  blind to the timing; 'blind' run). Puffs come in breath holds (groups of
%  close pulses). No behavioral file; no makeOutDat (raw loaded directly).
%  Final: <root>\<id>\preProc\<id>_airPuffpreproc.mat with
%    TTL     puff onsets (fs = 500 samples)
%    pulses  every DAQ pulse with its role (lead / puff / separator) + puffInfo
%    holds   one row per breath hold (respiration-defined onset / offset, puffs,
%            condition, breath context, RR before / during / after)
%    behDat  one row per puff (timing within the hold, respiration and RR
%            around the puff, manOnset placeholder)
%    breaths per-breath table of the whole recording (segmentBreaths_zlp +
%            HRV via runECGStage; condition = hold index, 0 = no hold) + bmObj
%  TASK-SPECIFIC pieces (tasks/airPuff/):
%    - assembleRaw_airPuff.m           (raw load + event parse at the raw rate)
%    - parsePuffEvents_airPuff.m       (rail-referenced pulses -> lead / puffs / separator / holds)
%    - detectHolds_airPuff.m           (hold onset / offset from the respiration)
%    - build_behavior_table_airPuff.m  (per-puff behDat + hold RR)
%    - plotQC_airPuff.m                (overview / per-hold / locked-epoch figures)
%  Shared: runSharedCore, segmentBreaths_zlp, behDatFromBreaths,
%  appendBmFeatureCols, runECGStage (NaN-HRV fallback), paramCheck,
%  isSessionDone, writePreProcX / writeParams.
% =====================================================================

cfg        = applyParams('airPuff','main');
sessionIDs = cfg.sessionIDs;

% Run-on-guess batch override + targeted-run filter (Tasks_260824.md D4; the
% O15 mechanics): guess sessions run headlessly only when allowed - OBE ones
% also need ZLP_ALLOW_GUESS_RUN_ALL=1 - QC figures are saved, paramSource is
% NEVER promoted.
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

    P = applyParams('airPuff', S.id);
    isGuess = ~strcmpi(strtrim(P.paramSource), 'curated');
    P.allowGuessRun = allowGuessRunEnv && (strcmp(P.type, 'EEG') || ...
        strcmp(getenv('ZLP_ALLOW_GUESS_RUN_ALL'), '1'));
    P.figDir = fullfile(S.fig, P.task);
    if isGuess && allowGuessRunEnv && ~P.allowGuessRun
        disp(['SKIP (guess, not run per D4): ' S.id])
        continue
    end

    % --- done-check ---
    preDir = fullfile(S.root, S.id, 'preProc');
    fpath  = fullfile(preDir, [S.id '_airPuffpreproc.mat']);
    if isSessionDone(fpath, {'moreThan1', 'holds'})
        disp(['Done with ' S.id ' ; ' num2str(s)])
        continue
    end

    % --- Assemble: TASK-SPECIFIC loader (+ event parse) + shared assembler ---
    raw    = assembleRaw_airPuff(S, P);           % <-- TASK-SPECIFIC (no makeOutDat)
    outDat = assembleOutDat(raw, S, P);           % shared
    outDat.CSClist       = raw.CSClist;           % provenance (O15/pacedBreathing-style extras)
    outDat.OGdataDir     = raw.OGdataDir;
    outDat.loadFile      = raw.loadFile;
    outDat.preProcScript = 'airPuffPreProc_main.m';
    if isfield(raw, 'atlasSegments'), outDat.atlasSegments = raw.atlasSegments; end
    pulsesRaw            = raw.pulses;
    outDat.puffInfo      = raw.puffInfo;
    outDat.puffOpts      = P.puffOpts;            % the task options used (parse / hold / measure)
    clear raw

    if isGuess, [outDat, P] = paramCheck(outDat, P); end

    outDat = runSharedCore(outDat, P, EEGLOC);   % shared: downsample, EEG, macros
    % respiration carry (full EEG rerun, 2026-10-22): with ZLP_CARRY_FROM set (the previous final) its rsp rows
    % replace the pipeline's own before the breaths are segmented; without it this line does nothing
    [outDat, CS] = carryRespFromFinal(outDat, P);
    disp(['........................shared core ', sessionIDs{s}])

    % ===== TASK-SPECIFIC (airPuff) =====
    % DAQ pulses -> the final rate; TTL = puff onsets
    pu = pulsesRaw;
    pu.sample       = toTargetSamples(pu.onsetRaw, outDat.origFS, outDat.fs);
    pu.offsetSample = toTargetSamples(pu.offsetRaw, outDat.origFS, outDat.fs);
    pu.sample(pu.sample < 1) = 1;
    outDat.pulses = pu;
    isPuff = pu.role == "puff";
    outDat.TTL = pu.sample(isPuff);
    clear pulsesRaw

    % breaths over the whole recording (context: inhale onsets, the hold breaths)
    isRsp  = cellfun(@(x) contains(x, 'rsp'), outDat.labels);
    rspDat = outDat.data(isRsp, :);
    rspDat = rspDat(P.rspIDX, :) .* P.rspFlip;
    [outDat.bmObj, outDat.bmFeatures] = segmentBreaths_zlp(rspDat, outDat.fs);
    % (2026-10-22, user) the incomplete-exhale merge rule, after the engine: an inhale joins the previous breath
    % when the exhale since it is < 20 % of it (shared/mergeIncompleteExhales; outDat.breathMerge)
    outDat = applyBreathMerge(outDat, rspDat, P);

    % breath holds from the respiration around each puff group
    [outDat.holds, quietAtPuff, qc] = detectHolds_airPuff(rspDat, outDat.fs, pu(isPuff, :), ...
        outDat.bmObj, P.puffOpts.hold);
    outDat.holdInfo = struct('quietThreshUV', qc.thr, 'medianBreathAmpUV', qc.ampRef, 'opts', qc.opts);
    outDat.bmObj(:, 12) = 0;                        % condition = hold index of the breath spanning a hold
    hb = outDat.holds.holdBreath; okb = ~isnan(hb);
    outDat.bmObj(hb(okb), 12) = outDat.holds.hold(okb);
    outDat.moreThan1 = 0;                           % done-sentinel: one puff per behDat row
    outDat.rspIDX   = P.rspIDX;
    outDat.rspFlip  = P.rspFlip;
    outDat.beatSpec = P.beatSpec;

    % per-breath context table + ECG / HRV (runECGStage's flagBadBreaths works
    % on a per-breath behDat); then the per-puff behDat replaces it
    outDat.behDat = behDatFromBreaths(outDat.bmObj, size(outDat.data, 2), outDat.fs);
    outDat.behDat.task = repmat("breath", height(outDat.behDat), 1);   % flagBadBreaths reads task
    outDat.behDat.task(outDat.behDat.condition > 0) = "hold";
    outDat = appendBreathMergeCols(outDat);
    outDat = appendBmFeatureCols(outDat, 'airPuffPreProc_main');
    [outDat, P] = runECGStage(outDat, P, isGuess, S.id);
    outDat.beatSpec = P.beatSpec;                  % paramCheckECG may have changed it
    outDat.breaths  = outDat.behDat;
    outDat = build_behavior_table_airPuff(outDat, quietAtPuff, P.puffOpts.measure);
    disp(['........................puffs holds breaths heart ', sessionIDs{s}])

    figFiles = plotQC_airPuff(outDat, qc);
    clear qc rspDat
    H = outDat.holds;
    fprintf('%s: %d puffs (%d cued / %d blind) in %d holds; hold durations %s s; %d/%d puffs quiet; ecgSkipped %d\n', ...
        S.id, height(outDat.behDat), sum(outDat.behDat.cued), sum(~outDat.behDat.cued), height(H), ...
        mat2str(round(H.durSec', 1)), sum(outDat.behDat.quietAtPuff), height(outDat.behDat), outDat.ecgSkipped);
    % ===== end TASK-SPECIFIC =====

    % carry: the carried rows must have survived to here; the previous final's post-hoc fields are kept
    outDat = carryFinishFromFinal(outDat, CS);

    % --- Guess gate (D4 pattern; never promotes paramSource) ---
    if isGuess
        if ~P.allowGuessRun
            error(['airPuff guess params: inspect the saved figures (%s), then set ' ...
                   'paramSource=curated in dataTracking.xlsx and re-run.'], strjoin(figFiles, ', '));
        end
        disp(['RUN-ON-GUESS (D4): saving outputs for ' S.id '; paramSource stays guess'])
    else
        P.paramSource = 'curated';
        writeParams(P, S.id);
    end

    if ~exist(L.procBehavior, 'dir'), mkdir(L.procBehavior); end
    writetable(outDat.behDat, fullfile(L.procBehavior, [outDat.sessID '_airPuff_puffs.csv']));
    writetable(outDat.holds, fullfile(L.procBehavior, [outDat.sessID '_airPuff_holds.csv']));
    writetable(outDat.breaths, fullfile(L.procBehavior, [outDat.sessID '_airPuff_processedBreathing.csv']));

    if ~exist(preDir, 'dir'), mkdir(preDir); end
    save(fpath, 'outDat', '-v7.3');
    writePreProcX(P, S.id);

    catch ME
        disp(['fail for ', sessionIDs{s}, ': ', ME.message]); disp(getReport(ME, 'extended', 'hyperlinks', 'off'))
    end
    close all
end

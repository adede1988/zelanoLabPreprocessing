
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
%  vipassana preprocessing -- main pipeline (added 2026-09-26)
%  Three single-session BrainVision (actiCHamp) EEG_vipassana recordings, one
%  per participant: audiobook1 / anapana / questionnaire1 / vipassana /
%  questionnaire2 / metta / questionnaire3 / audiobook2 (+ optional pre/post),
%  with only shaky, incomplete hand-pressed markers at the period
%  transitions. Block boundaries are INFERRED from the raw scalp EEG activity
%  evidence (inferBlocks_vipassana) - the markers are hints, never
%  constraints. Respiration may be unusable in a given session
%  (probeRespViability_vipassana); when it is, the respiration-derived stages
%  are skipped and outDat.respSkipped records why.
%  Line noise (2026-09-27): the actiCHamp dry electrodes carry heavy 60-Hz
%  pickup that made the shared core's bad-channel detector
%  (removeNoiseChansVolt, amplitude rules on unfiltered data) flag channels
%  for line noise rather than bad contact (22 of DD's 32 channels, nearly all
%  of its first audiobook in badTS). The shared core keeps no notch by design
%  (Atlas rigs), so assembleRaw_vipassana notches the 32 scalp rows at
%  60/120/180 Hz at ingestion; outDat.notchHz / notchNote record it. The
%  block-inference evidence (outDat.artifactIndex) is computed by the loader
%  on the UN-notched rows first, so the segmentation is unchanged.
%  Blinks (2026-09-27): eyes were closed throughout, so there are no blinks
%  to remove - applyParams sets P.blinkRemoval = false for this task and
%  preprocess_eeg skips blinkRemoveWrapper (outDat.blinkRemoval = 0, no
%  blinkIndicator row); bad channels, badTS / interpChan and the Laplacian
%  are unchanged.
%  PROTOCOL v2 (2026-10-20; every session after the three above - P.vipOpts.
%  protocol, set by applyParams): audiobook1 / paced1 / audiobook2 / anapana /
%  vipassana / metta / paced2 (paced2 not run in some sessions). The blocks
%  are MARKED: the photodiode sees a white square during every block, and
%  the SniffLogic log (behavioralDat, when present) names every block and is
%  aligned to the recording through the respiration trace both systems
%  record (alignLog_vipassana); blocksFromMarks_vipassana combines the two
%  (photodiode edges, log identities). No notch; rsp1 low-passed at
%  ingestion (60-Hz pickup); the aligned log pressure is an extra rsp row
%  ('rspSniffLogic') and the paced-breathing target a 'targTrace' row; the
%  shared EEG detector runs in its default 'fixed' mode, which flags every
%  channel of the noisy v2 EEG (see applyParams).
%  TASK-SPECIFIC pieces:
%    - assembleRaw_vipassana.m           (raw_vipassana.mat, no makeOutDat;
%                                         activity evidence, then v1: the
%                                         60/120/180-Hz notch of rows 1-32 /
%                                         v2: photodiode + log + rsp filter)
%    - artifactIndex_vipassana.m         (1-s movement/EMG activity evidence,
%                                         called by the loader)
%    - inferBlocks_vipassana.m           (v1: protocol-constrained DP segmentation)
%    - parsePhotodiode_vipassana.m, parseLog_vipassana.m, alignLog_vipassana.m,
%      blocksFromMarks_vipassana.m       (v2: marked blocks)
%    - probeRespViability_vipassana.m    (is the resp channel usable?)
%    - build_behavior_table_vipassana.m  (per-breath + regularity extras;
%                                         v2: paced-breathing target columns)
%    - checkRspPolarityRSA.m             (RSA sanity check on rspFlip)
%    - plotBlocks_vipassana.m            (v1 QC figure)
%    - plotMarkedBlocks_vipassana.m      (v2 QC figures)
%  Breath segmentation: shared segmentBreaths_zlp. ECG via the shared
%  runECGStage (EEG_vipassana sessions carry ECG1).
% =====================================================================

cfg        = applyParams('vipassana','main');
sessionIDs = cfg.sessionIDs;

% Tasks_260824.md D4 batch override (see breathingTaskPreProc_main /
% pacedBreathingPreProc_main)
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

    P = applyParams('vipassana', S.id);
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
    fpath  = fullfile(preDir, [S.id '_vipassanapreproc.mat']);
    if isSessionDone(fpath, {'moreThan1', 'bmFeatures'})
        disp(['Done with ' S.id ' ; ' num2str(s)])
        continue
    end

    % --- Assemble: TASK-SPECIFIC loader + shared assembler ---
    raw    = assembleRaw_vipassana(S, P);         % <-- TASK-SPECIFIC (no makeOutDat)
    isV2   = strcmp(raw.protocol, 'v2');
    outDat = assembleOutDat(raw, S, P);           % shared
    outDat.CSClist       = raw.CSClist;           % provenance (O15/pacedBreathing-style extras)
    outDat.OGdataDir     = raw.OGdataDir;
    outDat.loadFile      = raw.loadFile;
    outDat.preProcScript = 'vipassanaPreProc_main.m';
    outDat.refChan       = raw.refChan;           % 'Cz', the RECORDING reference (zero row in the raw file)
    outDat.header        = raw.header;            % parsed .vhdr struct (incl. recStart)
    outDat.notchHz       = raw.notchHz;           % v1 [60 120 180]: scalp rows notched at ingestion;
    outDat.notchNote     = raw.notchNote;         %   v2 [] (assembleRaw_vipassana; see the header above)
    outDat.protocol      = raw.protocol;
    outDat.ecgNotchHz    = raw.ecgNotchHz;        % v2 [60 120 180]: ECG1 notched at ingestion; v1 []
    outDat.ecgNotchNote  = raw.ecgNotchNote;
    outDat.avgRef        = raw.avgRef;            % ingestion re-reference of rows 1-32 (shared/robustAvgRef)
    if outDat.avgRef.applied                      % the reference the stored rows 1-32 are in
        outDat.dataRef = 'robust common average (outDat.avgRef)';
    else
        outDat.dataRef = raw.refChan;
    end
    % acquisition segments from the LoadData script (.eeg file samples, kept +
    % dropped) - deliberately not outDat.segments, which other tasks use for
    % seams inside the final data (a v2 recording keeps ONE segment)
    if isfield(raw, 'acqSegments'), outDat.acqSegments = raw.acqSegments; end
    fsRaw = outDat.fs;                            % = raw.fs_raw (500 Hz for this task); kept for the
                                                   % marker sample-rate conversion below
    if isV2
        outDat.photodiode    = raw.photodiode;
        outDat.sniffLogic    = raw.sniffLogic;    % [] when behavioralDat has no SniffLogic log
        outDat.behFiles      = raw.behFiles;
        outDat.psychopyFiles = raw.psychopyFiles;
        outDat.rspFilterHz   = raw.rspFilterHz;
        outDat.rspFilterNote = raw.rspFilterNote;
        % the log is inhale-POSITIVE and the alignment measured the polarity of
        % the recording's own respiration channel against it (asserted against
        % the respiration choice after paramCheck, below)
        impliedFlip = [];
        if ~isempty(raw.sniffLogic)
            impliedFlip = [raw.sniffLogic.align.sign, 1];      % rsp1, rspSniffLogic
        end
        % blocks from the marks now (strict; before the expensive shared core).
        % The raw fs is the final 500 Hz and the core does not resample, so the
        % raw-sample boundaries are final samples - asserted, since a recording
        % at another rate would leave the boundaries in raw samples
        assert(raw.fs_raw == P.fs_target, 'vipassanaPreProc_main:fs', ...
            '%s: v2 marks are raw samples; raw fs %g ~= the %g-Hz target', S.id, raw.fs_raw, P.fs_target);
        [outDat.blocks, outDat.TTL, outDat.blockInference] = blocksFromMarks_vipassana( ...
            raw.photodiode, raw.sniffLogic, size(outDat.data, 2), outDat.fs, P.vipOpts);
        targTrace = raw.targTrace;
    end

    % ===== TASK-SPECIFIC (vipassana) =====
    % Activity evidence on the RAW scalp EEG, BEFORE the shared core touches
    % it (re-referencing / cleaning would blur the movement contrast the
    % segmentation depends on) - and before the ingestion notch: the loader
    % computes it on the un-notched rows (artifactIndex_vipassana) and then
    % notches them (see assembleRaw_vipassana's header for why; notched
    % evidence moved DD's audiobook1 by minutes). fs is unchanged by the core
    % at this site (raw fs already = fs_target = 500 Hz), so the window
    % timebase stays valid after runSharedCore runs.
    outDat.artifactIndex = raw.artifactIndex;

    % markers -> 500 Hz, Stimulus presses only (drop the 'New Segment' row;
    % its recStart datetime is already kept on outDat.header)
    mk = raw.markers;
    isStim = false(height(mk), 1);
    if ismember('type', mk.Properties.VariableNames)
        isStim = strcmpi(strtrim(string(mk.type)), 'Stimulus');
    end
    mkS = mk(isStim, :);
    outDat.markers = table();
    outDat.markers.description = string(mkS.description);
    outDat.markers.sampleRaw   = double(mkS.sample);
    outDat.markers.sample      = toTargetSamples(outDat.markers.sampleRaw, fsRaw, 500);
    outDat.markers.minutes     = double(mkS.minutes);
    clear raw mk mkS

    if isGuess, [outDat, P] = paramCheck(outDat, P); end
    outDat.rspIDX  = P.rspIDX;                    % paramCheck may change the respiration choice
    outDat.rspFlip = P.rspFlip;
    if isV2 && ~isempty(impliedFlip)
        % a respiration polarity that contradicts the SniffLogic log would put
        % every onset on the exhale (strict)
        assert(P.rspIDX <= 2 && P.rspFlip == impliedFlip(P.rspIDX), 'vipassanaPreProc_main:rspFlip', ...
            ['%s: rspIDX %d / rspFlip %d contradicts the SniffLogic log (rsp1 correlates %+d with the ' ...
             'inhale-positive log pressure -> rspFlip %d; rspSniffLogic -> 1)'], S.id, P.rspIDX, P.rspFlip, ...
             impliedFlip(1), impliedFlip(1));
    end

    outDat = runSharedCore(outDat, P, EEGLOC);   % shared: downsample, EEG, macros
    disp(['........................spike and blink ', sessionIDs{s}])

    % Cz is the recording reference, inserted by the loader as an all-zero
    % row. Average-referenced (outDat.avgRef.applied, the default since
    % 2026-10-21) it is a real channel and the shared EEG stage judges it
    % like any other. Left in the recording reference, the shared stage
    % cannot know the row is the reference: removeNoiseChansVolt flags the
    % flat row bad and overwrites it, trial by trial, with a spherical-
    % spline interpolation of its neighbours (exact 0 wherever too many
    % other channels were bad at once), so the reference invariant is
    % restored in the broadband data ('Cz' stays in outDat.badChans, and
    % dataLap / interpChan keep their interpolated-copy contract).
    outDat.czRezeroed = ~outDat.avgRef.applied;
    if outDat.czRezeroed
        czRow = find(strcmpi(cellstr(string(outDat.labels(1:32))), 'Cz'));
        assert(isscalar(czRow), 'vipassanaPreProc_main: exactly one Cz row expected in rows 1-32');
        outDat.data(czRow, :) = 0;
    end

    if ~isV2
        % v1 blocks: protocol-constrained DP segmentation on the activity
        % evidence, with the (converted) markers as hints only
        markersSec = (outDat.markers.sample - 1) / outDat.fs;
        [outDat.blocks, outDat.TTL, outDat.blockInference] = inferBlocks_vipassana( ...
            outDat.artifactIndex.evid, outDat.artifactIndex.tSec, markersSec, ...
            outDat.fs, size(outDat.data, 2), P.vipOpts);
    elseif ~isempty(targTrace)
        % v2 with a log: the paced-breathing target the participant followed
        % (Pa, the log's units, inhale-positive; 0 outside the sweeps) as a
        % channel, appended AFTER the shared core like breathingTask's
        % targTrace so the core's filters never touch it
        assert(numel(targTrace) == size(outDat.data, 2), 'vipassanaPreProc_main: targTrace length mismatch');
        outDat.data(end + 1, :) = targTrace;
        outDat.labels{end + 1} = 'targTrace';
    end
    clear targTrace

    isRsp  = cellfun(@(x) contains(x, 'rsp'), outDat.labels);
    rspDat = outDat.data(isRsp, :);
    rspDat = rspDat(P.rspIDX, :) .* P.rspFlip;

    % respiration viability probe (some sessions carry no usable respiration
    % - CC as of 2026-09-26; see vipassana_design.md section 1)
    % (v2: P.vipOpts.respProbe drops the autocorrelation rule - see applyParams)
    probeOpts = struct();
    if isfield(P.vipOpts, 'respProbe'), probeOpts = P.vipOpts.respProbe; end
    probe = probeRespViability_vipassana(rspDat, outDat.fs, outDat.blocks, probeOpts);
    outDat.respProbe = probe;

    if probe.viable
        [outDat.bmObj, outDat.bmFeatures] = segmentBreaths_zlp(rspDat, outDat.fs);
        onsetSamp = round(outDat.bmObj(:, 2) * outDat.fs);
        blkOfBreath = zeros(size(outDat.bmObj, 1), 1);
        Bk = outDat.blocks;
        for b = 1:height(Bk)
            blkOfBreath(onsetSamp >= Bk.startSample(b) & onsetSamp <= Bk.endSample(b)) = b;
        end
        assert(all(blkOfBreath > 0), ...
            'vipassanaPreProc_main: every breath must fall inside a block (the blocks tile the recording)');
        outDat.bmObj(:, 12) = blkOfBreath;    % condition = block index
        outDat.respSkipped = 0;
    else
        warning('vipassanaPreProc_main:respNotViable', ...
            '%s: respiration not viable (%s) - respiration-derived stages skipped', S.id, probe.reason);
        outDat.bmObj = zeros(0, 14);
        outDat.bmFeatures = struct('engine', 'none', 'skipped', true, 'reason', probe.reason);
        outDat.respSkipped = 2;
    end

    outDat = build_behavior_table_vipassana(outDat);   % must handle zero breaths (empty bmObj)

    % ECG with NaN-HRV fallback on detection failure (flagged for review);
    % flagBadBreaths / fillNaNHRV both tolerate an empty (0-row) behDat
    [outDat, P] = runECGStage(outDat, P, isGuess, S.id);
    disp(['........................breath behave heart ', sessionIDs{s}])

    if probe.viable && outDat.ecgSkipped == 0
        outDat.rspPolarityRSA = checkRspPolarityRSA(outDat);
        R = preprocess_respiration_wholetrace(outDat);
        plot_sniff_epochs(outDat, R);
    else
        % not checked (no respiration or no RRint); same shape as the check's
        % own no-breaths result
        outDat.rspPolarityRSA = struct('deltaRRms', NaN, 'nBreaths', 0, 'consistent', false);
    end
    % the respiration panel depends only on respiration viability, not on ECG
    if ~probe.viable, rspDat = []; end
    if isV2
        plotMarkedBlocks_vipassana(outDat, rspDat);
    else
        plotBlocks_vipassana(outDat, rspDat);
    end
    % ===== end TASK-SPECIFIC =====

    outDat.moreThan1 = 1;
    outDat.rspIDX  = P.rspIDX;
    outDat.rspFlip = P.rspFlip;

    % --- Guess gate (D4 pattern; never promotes paramSource) ---
    if isGuess
        if ~P.allowGuessRun
            error(['vipassana guess params: inspect the saved figures, ' ...
                   'then set paramSource=curated in dataTracking.xlsx and re-run.']);
        end
        disp(['RUN-ON-GUESS (D4): saving outputs for ' S.id '; paramSource stays guess'])
    else
        P.paramSource = 'curated';
        writeParams(P, S.id);
    end

    if ~exist(L.procBehavior, 'dir'), mkdir(L.procBehavior); end
    writetable(outDat.behDat, fullfile(L.procBehavior, ...
        [outDat.sessID '_vipassana_processedBreathing.csv']));
    writetable(outDat.blocks, fullfile(L.procBehavior, ...
        [outDat.sessID '_vipassana_blocks.csv']));

    if ~exist(preDir, 'dir'), mkdir(preDir); end
    save(fpath, 'outDat', '-v7.3');
    writePreProcX(P, S.id);

    catch ME
        disp(['fail for ', sessionIDs{s}, ': ', ME.message]); disp(getReport(ME, 'extended', 'hyperlinks', 'off'))
    end
    close all
end

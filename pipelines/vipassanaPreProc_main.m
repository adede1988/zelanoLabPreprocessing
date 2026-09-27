
clear
% ---- machine paths (everything machine-specific comes from labPaths) ----
zlpHere=fileparts(mfilename('fullpath')); zlpRoot=zlpHere; while exist(fullfile(zlpRoot,'config','labPaths.m'),'file')~=2, zlpP=fileparts(zlpRoot); if strcmp(zlpP,zlpRoot), error('zelanoLabPreprocessing root not found'); end, zlpRoot=zlpP; end, addpath(genpath(zlpRoot));
L            = labPaths();
addpath(genpath(L.repo))
addpath(genpath(L.eeglab))

figPath      = L.figPath;
EEGLOC       = readtable(L.eegLocCsv);
set(0, 'defaultfigurewindowstyle', 'normal')

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
%  TASK-SPECIFIC pieces:
%    - assembleRaw_vipassana.m           (raw_vipassana.mat, no makeOutDat)
%    - artifactIndex_vipassana.m         (1-s movement/EMG activity evidence)
%    - inferBlocks_vipassana.m           (protocol-constrained DP segmentation)
%    - probeRespViability_vipassana.m    (is the resp channel usable?)
%    - build_behavior_table_vipassana.m  (per-breath + regularity extras)
%    - checkRspPolarityRSA.m             (RSA sanity check on rspFlip)
%    - plotBlocks_vipassana.m            (QC figure)
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
    raw    = assembleRaw_vipassana(S);            % <-- TASK-SPECIFIC (no makeOutDat)
    outDat = assembleOutDat(raw, S, P);           % shared
    outDat.CSClist       = raw.CSClist;           % provenance (O15/pacedBreathing-style extras)
    outDat.OGdataDir     = raw.OGdataDir;
    outDat.loadFile      = raw.loadFile;
    outDat.preProcScript = 'vipassanaPreProc_main.m';
    outDat.refChan       = raw.refChan;           % 'Cz' (the inserted zero-row reference)
    outDat.header        = raw.header;            % parsed .vhdr struct (incl. recStart)
    fsRaw = outDat.fs;                            % = raw.fs_raw (500 Hz for this task); kept for the
                                                   % marker sample-rate conversion below

    % ===== TASK-SPECIFIC (vipassana) =====
    % Activity evidence on the RAW scalp EEG, BEFORE the shared core touches
    % it (re-referencing / cleaning would blur the movement contrast the
    % segmentation depends on). fs is unchanged by the core at this site
    % (raw fs already = fs_target = 500 Hz), so the window timebase stays
    % valid after runSharedCore runs.
    outDat.artifactIndex = artifactIndex_vipassana(outDat.data(1:32, :), outDat.fs);

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

    outDat = runSharedCore(outDat, P, EEGLOC);   % shared: downsample, EEG, macros
    disp(['........................spike and blink ', sessionIDs{s}])

    % Cz is the recording reference, inserted by the loader as an all-zero
    % row. The shared EEG stage cannot know that: removeNoiseChansVolt flags
    % the flat row bad and overwrites it, trial by trial, with a spherical-
    % spline interpolation of its neighbours (exact 0 wherever too many other
    % channels were bad at once). Restore the reference invariant in the
    % broadband data. 'Cz' stays in outDat.badChans, and dataLap / interpChan
    % keep their interpolated-copy contract (dataLapFromInterp).
    czRow = find(strcmpi(cellstr(string(outDat.labels(1:32))), 'Cz'));
    assert(isscalar(czRow), 'vipassanaPreProc_main: exactly one Cz row expected in rows 1-32');
    outDat.data(czRow, :) = 0;
    outDat.czRezeroed = true;

    % blocks: protocol-constrained DP segmentation on the activity evidence,
    % with the (converted) markers as hints only
    markersSec = (outDat.markers.sample - 1) / outDat.fs;
    [outDat.blocks, outDat.TTL, outDat.blockInference] = inferBlocks_vipassana( ...
        outDat.artifactIndex.evid, outDat.artifactIndex.tSec, markersSec, ...
        outDat.fs, size(outDat.data, 2), P.vipOpts);

    isRsp  = cellfun(@(x) contains(x, 'rsp'), outDat.labels);
    rspDat = outDat.data(isRsp, :);
    rspDat = rspDat(P.rspIDX, :) .* P.rspFlip;

    % respiration viability probe (some sessions carry no usable respiration
    % - CC as of 2026-09-26; see vipassana_design.md section 1)
    probe = probeRespViability_vipassana(rspDat, outDat.fs, outDat.blocks);
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
    if probe.viable
        plotBlocks_vipassana(outDat, rspDat);
    else
        plotBlocks_vipassana(outDat, []);
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

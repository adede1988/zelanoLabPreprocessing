
clear
% ---- machine paths (everything machine-specific comes from labPaths) ----
zlpHere=fileparts(mfilename('fullpath')); zlpRoot=zlpHere; while exist(fullfile(zlpRoot,'config','labPaths.m'),'file')~=2, zlpP=fileparts(zlpRoot); if strcmp(zlpP,zlpRoot), error('zelanoLabPreprocessing root not found'); end; zlpRoot=zlpP; end; addpath(genpath(zlpRoot));
L       = labPaths();
addpath(genpath(L.repo))
addpath(genpath(L.eeglab))

figPath = L.figPath;
EEGLOC  = readtable(L.eegLocCsv);

set(0, 'defaultfigurewindowstyle', 'normal')

% =====================================================================
%  detectNoOdor preprocessing -- main pipeline (added 2026-10-15)
%  Cued sniffs, the participant tries to detect an odor that is never there
%  (Main_detectiontask_f: air line only); one SNIFF cue + one Yes/No answer per
%  trial. A per-sniff task on the cue/thresh template.
%  TASK-SHARED sections call the shared functions every *PreProc_main uses
%  (runSharedCore + the shared stage helpers); do NOT edit or copy them.
%  TASK-SPECIFIC pieces for detectNoOdor:
%    - detectNoOdor_makeOutDat.m        (event parse + result file -> _detectNoOdorPreProc.mat)
%    - tasks/detectNoOdor/assembleRaw_detectNoOdor.m
%    - tasks/detectNoOdor/countInhales_detectNoOdor.m (inhales cue -> answer)
%    - tasks/detectNoOdor/build_behavior_table_detectNoOdor.m
%    - tasks/detectNoOdor/plotQC_detectNoOdor.m (all-trials montage)
%  Everything else is SHARED: applyParams, assembleOutDat, runSharedCore
%  (downsample_data -> preprocess_eeg -> preprocess_macros),
%  preprocess_respiration_wholetrace, detect_sniffs_from_TTLs,
%  refine_onsets_with_phase, paramCheck, writeParams, writePreProcX,
%  plot_sniff_epochs.
%  Intermediate <id>_detectNoOdorPreProc.mat and final
%  <id>_detectNoOdorpreproc.mat are the same file on Windows (CLAUDE.md §2).
% =====================================================================

cfg        = applyParams('detectNoOdor','main');
sessionIDs = cfg.sessionIDs;

% Run-on-guess batch override + targeted-run filter: identical mechanics to
% cueTaskPreProc_main (Tasks_260824.md D4). Guess sessions run headlessly when
% allowed, QC figures are saved, paramSource is NEVER promoted.
allowGuessRunEnv = strcmp(getenv('ZLP_ALLOW_GUESS_RUN'), '1');
mainOnlyEnv = getenv('ZLP_MAIN_ONLY');
mainOnlyList = {};
if ~isempty(mainOnlyEnv), mainOnlyList = strtrim(strsplit(mainOnlyEnv, ',')); end

for s = 1:numel(sessionIDs)
    try
    % --- Session descriptor ---
    S = struct;
    S.id   = sessionIDs{s};
    if ~isempty(mainOnlyList) && ~any(strcmp(mainOnlyList, S.id)), continue; end
    S.root = cfg.root{s};
    S.fig  = fullfile(figPath, S.id);
    disp(['working on ', sessionIDs{s}])
    preDir = fullfile(S.root, S.id, 'preProc');
    outDat = load(fullfile(preDir, [S.id '_detectNoOdorPreProc.mat']));
    fn = fieldnames(outDat); outDat = outDat.(fn{1});

    if isfield(outDat, 'moreThan1')
        disp(['Done with ' S.id ' ; ' num2str(s)])
        continue
    end
    % --- Params ---
    P = applyParams('detectNoOdor', S.id);
    % anything not explicitly curated is treated as a guess
    isGuess = ~strcmpi(strtrim(P.paramSource), 'curated');
    P.allowGuessRun = allowGuessRunEnv && (strcmp(P.type, 'EEG') || ...
        strcmp(getenv('ZLP_ALLOW_GUESS_RUN_ALL'), '1'));
    % task subfolder (matches assembleOutDat's outDat.figs)
    P.figDir = fullfile(S.fig, 'detectNoOdor');
    if isGuess && allowGuessRunEnv && ~P.allowGuessRun
        disp(['SKIP (guess, not run per D4): ' S.id])
        continue
    end

    % --- Assemble: TASK-SPECIFIC loader + shared assembler ---
    raw    = assembleRaw_detectNoOdor(S);   % <-- TASK-SPECIFIC
    outDat = assembleOutDat(raw, S, P);     % shared
    % TASK-SPECIFIC: event-parse + behavior provenance travel to the final
    outDat.ttlInfo   = raw.ttlInfo;
    outDat.behSource = raw.behSource;

    % Guessed params: verify rsp channel + macro/spike choices
    if isGuess, [outDat, P] = paramCheck(outDat, P); end
    outDat.rspIDX = P.rspIDX;
    outDat.rspFlip = P.rspFlip;
    disp(['........................Loaded ', sessionIDs{s}])

    outDat = runSharedCore(outDat, P, EEGLOC);   % shared: downsample, EEG, macros
    % respiration carry (full EEG rerun, 2026-10-22): with ZLP_CARRY_FROM set (the previous final) its rsp rows
    % replace the pipeline's own before the sniff detection reads them; without it this line does nothing
    [outDat, CS] = carryRespFromFinal(outDat, P);

    disp(['........................EEG / macros done ', sessionIDs{s}])
    R = preprocess_respiration_wholetrace(outDat); % fields: rspDat, smoothR, testSig, rspPhase

    % TTL columns trialStart, response, sniff: the shared detector takes the
    % sniff target from column 3 (one cued sniff per trial, label 'cued')
    sniffs = detect_sniffs_from_TTLs(R, P, outDat);

    % ----- TASK-SPECIFIC (detectNoOdor): inhales cue -> answer, behavior table -----
    inh = countInhales_detectNoOdor(R, outDat.TTL, outDat.fs, P.inhaleOpts);
    outDat.inhaleCount = inh;
    outDat.behDat = build_behavior_table_detectNoOdor(sniffs, raw.beh, inh, outDat.TTL, outDat.fs);
    % ----- end TASK-SPECIFIC -----

    outDat = refine_onsets_with_phase(outDat, R, P); % uses precomputed phase

    plot_sniff_epochs(outDat, R);
    plotQC_detectNoOdor(outDat, R, inh);   % TASK-SPECIFIC all-trials montage
    % one cued sniff per trial (done-sentinel, like cue / thresh)
    outDat.moreThan1 = 0;

    % carry: the carried rows must have survived to here; the previous final's post-hoc fields are kept
    outDat = carryFinishFromFinal(outDat, CS);

    % --- Guess gate: stop before writing back / saving so the user can verify
    %     onset detection in the saved figures first. Under the run-on-guess
    %     override the save proceeds but paramSource stays guess. ---
    if isGuess
        if ~P.allowGuessRun
            error(['detectNoOdor guess params: inspect the saved figures, then set ' ...
                   'paramSource=curated in dataTracking.xlsx (or call ' ...
                   'writeParams(P, S.id)) and re-run.']);
        end
        disp(['RUN-ON-GUESS (D4): saving outputs for ' S.id '; paramSource stays guess'])
    else
        P.paramSource = 'curated';
        writeParams(P, S.id);
    end

    disp(sprintf('%s: %d of %d trials with a cued sniff; nInhales %s', S.id, ...
        numel(unique(outDat.behDat.n)), height(outDat.TTL), mat2str(inh.nInhales')));

    % --- Save ---
    if ~exist(preDir,'dir'), mkdir(preDir); end
    save(fullfile(preDir, [S.id '_detectNoOdorpreproc.mat']), 'outDat','-v7.3');

    writePreProcX(P, S.id);   % mark Data Preprocessed = X in dataTracking.xlsx

    catch ME
        disp(['fail for ', sessionIDs{s}, ': ', ME.message])
        disp(getReport(ME, 'extended', 'hyperlinks', 'off'))
    end
    close all   % unattended batches must not accumulate figures
end


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
%  cueTask3 preprocessing -- main pipeline (added 2026-10-16 with
%  261008_INR_NWU_SS_1)
%  The lab's odor-matching cue task with THREE sniffs per trial: three SNIFF
%  cues 1.1 s apart, the odor line open across them, then the Yes/No answer.
%  Built on the cue task (cueTaskPreProc_main is the template).
%  TASK-SHARED sections call the shared functions every *PreProc_main uses
%  (runSharedCore + the shared stage helpers); do NOT edit or copy them.
%  TASK-SPECIFIC pieces for cueTask3:
%    - cueTask3_makeOutDat.m           (event parse + run result files -> _cueTask3PreProc.mat)
%    - tasks/cue/assembleRaw_cueTask.m (the cue loader, stem 'cueTask3')
%    - tasks/cueTask3/build_behavior_table_cueTask3.m (the cue builder + run,
%      noOdorDelivered, inhale bounds)
%    - tasks/cueTask3/plotSniffTrains_cueTask3.m (QC figures by sniff index)
%  Everything else is SHARED: applyParams, assembleOutDat, runSharedCore
%  (downsample_data -> preprocess_eeg -> preprocess_macros),
%  preprocess_respiration_wholetrace, detect_sniffs_from_TTLs and
%  refine_onsets_with_phase in their train mode (P.sniffTrain), paramCheck,
%  writeParams, writePreProcX, plot_sniff_epochs.
%  Intermediate <id>_cueTask3PreProc.mat and final <id>_cueTask3preproc.mat
%  are the same file on Windows (CLAUDE.md section 2).
% =====================================================================

cfg        = applyParams('cueTask3','main');
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
    outDat = load(fullfile(preDir, [S.id '_cueTask3PreProc.mat']));
    fn = fieldnames(outDat); outDat = outDat.(fn{1});

    if isfield(outDat, 'moreThan1')
        disp(['Done with ' S.id ' ; ' num2str(s)])
        continue
    end
    % --- Params ---
    P = applyParams('cueTask3', S.id);
    % anything not explicitly curated is treated as a guess
    isGuess = ~strcmpi(strtrim(P.paramSource), 'curated');
    P.allowGuessRun = allowGuessRunEnv && (strcmp(P.type, 'EEG') || ...
        strcmp(getenv('ZLP_ALLOW_GUESS_RUN_ALL'), '1'));
    % task subfolder (matches assembleOutDat's outDat.figs)
    P.figDir = fullfile(S.fig, 'cueTask3');
    if isGuess && allowGuessRunEnv && ~P.allowGuessRun
        disp(['SKIP (guess, not run per D4): ' S.id])
        continue
    end

    if isGuess
        [outDat, P] = paramCheck(outDat, P);
    end

    % --- Assemble: TASK-SPECIFIC loader + shared assembler ---
    raw    = assembleRaw_cueTask(S, 'cueTask3');   % <-- TASK-SPECIFIC (the cue loader)
    outDat = assembleOutDat(raw, S, P);            % shared
    outDat.ttlInfo = raw.ttlInfo;                  % the event-parse record travels to the final
    disp(['........................Loaded ', sessionIDs{s}])

    outDat = runSharedCore(outDat, P, EEGLOC);   % shared: downsample, EEG, macros
    % respiration carry (full EEG rerun, 2026-10-22): with ZLP_CARRY_FROM set (the previous final) its rsp rows
    % replace the pipeline's own before the sniff detection reads them; without it this line does nothing
    [outDat, CS] = carryRespFromFinal(outDat, P);

    disp(['........................EEG / macros done ', sessionIDs{s}])
    R = preprocess_respiration_wholetrace(outDat); % fields: rspDat, smoothR, testSig, rspPhase

    % TTL columns trialStart, response, sniff1, sniff2, sniff3: the shared
    % detector takes its sniff targets from columns 3:end; P.sniffTrain
    % (applyParams) selects its train mode, which finds each SNIFF cue's own
    % inhale (trough -> peak) on the smoothed trace
    sniffs = detect_sniffs_from_TTLs(R, P, outDat);
    outDat.sniffTrain = P.sniffTrain;   % the train-detector options used

    % three sniffs per trial (done-sentinel)
    outDat.moreThan1 = 1;

    % ----- TASK-SPECIFIC (cueTask3): behavior table from sniffs + raw behavior -----
    [outDat.behDat, noOdor] = build_behavior_table_cueTask3(sniffs, raw.beh, P);
    if ~isempty(noOdor)
        % trials without odor delivery (P.noOdorTrials): rows kept, flagged
        % behDat.noOdorDelivered; the record goes to outDat.noOdorTrials
        outDat.noOdorTrials = noOdor;
        disp(['no odor delivered in trial(s) ' mat2str(noOdor.trial') ': ' char(noOdor.reason(1))])
    end
    % ----- end TASK-SPECIFIC -----

    outDat = refine_onsets_with_phase(outDat, R, P); % train mode: steepest rise trough -> peak

    % carry: the carried rows must have survived to here; the previous final's post-hoc fields are kept
    outDat = carryFinishFromFinal(outDat, CS);

    % --- Guess gate: stop before promoting/saving so the user can verify the
    %     onset figures first. Under the run-on-guess override the save
    %     proceeds but paramSource stays guess (never promoted). ---
    if isGuess
        if ~P.allowGuessRun
            error('check that onsets have been well-detected')
        end
        disp(['RUN-ON-GUESS (D4): saving outputs for ' S.id '; paramSource stays guess'])
    else
        P.paramSource = 'curated';
        writeParams(P, S.id);
    end

    plot_sniff_epochs(outDat, R);
    plotSniffTrains_cueTask3(outDat, R);   % TASK-SPECIFIC QC by sniff index

    nPer = accumarray(outDat.behDat.wiTriali, 1, [3 1])';
    fprintf('%s: %d sniffs in %d of %d trials (per sniff index %s); finalOnset - SNIFF cue median %s s\n', ...
        S.id, height(outDat.behDat), numel(unique(outDat.behDat.n)), height(outDat.TTL), mat2str(nPer), ...
        mat2str(arrayfun(@(k) median(outDat.behDat.finalOnset(outDat.behDat.wiTriali == k) - ...
            outDat.TTL{outDat.behDat.n(outDat.behDat.wiTriali == k), 2 + k}) / outDat.fs, 1:3), 3));

    % --- Save ---
    if ~exist(preDir,'dir'), mkdir(preDir); end
    save(fullfile(preDir, [S.id '_cueTask3preproc.mat']), 'outDat','-v7.3');

    writePreProcX(P, S.id);   % mark Data Preprocessed = X in dataTracking.xlsx

    catch ME
        disp(['fail for ', sessionIDs{s}, ': ', ME.message])
        disp(getReport(ME, 'extended', 'hyperlinks', 'off'))
    end
    close all   % unattended batches must not accumulate figures
end

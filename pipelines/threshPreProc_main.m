
clear
% ---- machine paths (everything machine-specific comes from labPaths) ----
zlpHere=fileparts(mfilename('fullpath')); zlpRoot=zlpHere; while exist(fullfile(zlpRoot,'config','labPaths.m'),'file')~=2, zlpP=fileparts(zlpRoot); if strcmp(zlpP,zlpRoot), error('zelanoLabPreprocessing root not found'); end; zlpRoot=zlpP; end; addpath(genpath(zlpRoot));
L       = labPaths();
codePre = L.codePre;
addpath(genpath(L.repo))
addpath(genpath(L.eeglab))

figPath = L.figPath;
EEGLOC  = readtable(L.eegLocCsv);

set(0, 'defaultfigurewindowstyle', 'normal')

% =====================================================================
%  threshTask preprocessing -- main pipeline
%  TASK-SHARED sections are identical across all four pipelines; do NOT edit
%  them when adding a new task. TASK-SPECIFIC sections must be rewritten.
%  TASK-SPECIFIC pieces for threshTask (rewrite these for a new task):
%    - assembleRaw_threshTask.m    (raw load -> raw struct)
%    - threshPreProc_makeOutDat.m  (PEA photodiode/behavior ingestion)
%    - the per-trial sniff-TTL table rebuild in the loop below
%    - build_behavior_table_threshTask.m
%  Everything else is SHARED: applyParams, assembleOutDat, downsample_data,
%  preprocess_eeg, preprocess_macros, preprocess_respiration_wholetrace,
%  detect_sniffs_from_TTLs, refine_onsets_with_phase, paramCheck, writeParams,
%  writePreProcX, plot_sniff_epochs.
% =====================================================================

cfg        = applyParams('threshTask','main');
sessionIDs = cfg.sessionIDs;

% Run-on-guess batch override + targeted-run filter (2026-09-01): identical
% mechanics to breathingTaskPreProc_main (Tasks_260824.md D4). Guess sessions
% run headlessly when allowed, QC figures are saved, paramSource is NEVER
% promoted - the outputs get checked by hand later.
allowGuessRunEnv = strcmp(getenv('ZLP_ALLOW_GUESS_RUN'), '1');
mainOnlyEnv = getenv('ZLP_MAIN_ONLY');
mainOnlyList = {};
if ~isempty(mainOnlyEnv), mainOnlyList = strtrim(strsplit(mainOnlyEnv, ',')); end

for s = 1:numel(sessionIDs)
    try
    % --- Session descriptor (adjust to your system) ---
    S = struct;
    S.id   = sessionIDs{s};
    if ~isempty(mainOnlyList) && ~any(strcmp(mainOnlyList, S.id)), continue; end
    S.root = cfg.root{s};
    S.fig  = fullfile(figPath, S.id);
    disp(['working on ', sessionIDs{s}])
    preDir = fullfile(S.root, S.id, 'preProc');
    outDat = load(fullfile(preDir, [S.id '_PEA_threshold_preproc.mat']));

    if isfield(outDat, 'out')
        outDat = outDat.out;
    elseif isfield(outDat, 'outDat')
        outDat = outDat.outDat;
    else
        error('unexpected missing field in outDat')
    end

    if isfield(outDat, 'moreThan1')
        disp(['Done with ' S.id ' ; ' num2str(s)])
        continue
    end
    % --- Params + raw load ---
    P = applyParams('threshTask', S.id);
    % anything not explicitly curated is treated as a guess
    isGuess = ~strcmpi(strtrim(P.paramSource), 'curated');
    P.allowGuessRun = allowGuessRunEnv && (strcmp(P.type, 'EEG') || ...
        strcmp(getenv('ZLP_ALLOW_GUESS_RUN_ALL'), '1'));
    % task subfolder (matches assembleOutDat's outDat.figs) so paramCheck
    % PNGs from different tasks of one session cannot overwrite each other
    P.figDir = fullfile(S.fig, 'threshTask');
    if isGuess && allowGuessRunEnv && ~P.allowGuessRun
        disp(['SKIP (guess, not run per D4): ' S.id])
        continue
    end

    % --- Assemble: TASK-SPECIFIC loader + shared assembler ---
    raw    = assembleRaw_threshTask(S);   % <-- TASK-SPECIFIC: edit/replace for a new task
    outDat = assembleOutDat(raw, S, P);    % shared

    % Guessed params: verify rsp channel + macro/spike choices interactively
    if isGuess, [outDat, P] = paramCheck(outDat, P); end
    outDat.rspIDX = P.rspIDX;
    outDat.rspFlip = P.rspFlip;
     disp(['........................Loaded ', sessionIDs{s}])
  % trialStarts, buttonPresses, sniffMarks    
    outDat = downsample_data(outDat, P.fs_target);
    if P.hasEEG, outDat = preprocess_eeg(outDat, EEGLOC, P); end
    outDat = preprocess_macros(outDat, P);
    
  disp(['........................spike and blink ', sessionIDs{s}])
    R = preprocess_respiration_wholetrace(outDat); % fields: rsp, rsp_smooth, phase, onset_metric

    % ----- TASK-SPECIFIC (threshTask): rebuild a 45-trial sniff-TTL table
    %       (start = sniff-1000 samples) before the shared sniff detector -----
    trial = 1:45;
    sniff = outDat.TTL.sniff;
    x = table(sniff(:)-1000, trial(:), sniff(:), ...
        'variablenames', {'start', 'trial', 'sniff'});
    outDat.TTL = x;
    % ----- end TASK-SPECIFIC -----
    sniffs = detect_sniffs_from_TTLs(R, P, outDat);  % returns table or matrix

   

    


    % ----- TASK-SPECIFIC (threshTask): behavior table from sniffs + raw behavior -----
    outDat.behDat = build_behavior_table_threshTask(sniffs, raw.beh);
    % ----- end TASK-SPECIFIC -----

    outDat = refine_onsets_with_phase(outDat, R, P); % uses precomputed phase


    plot_sniff_epochs(outDat, R);
   outDat.moreThan1 = 0;
  disp(['........................breath behave ', sessionIDs{s}])

    % --- Guess gate: stop before writing back / saving so the user can verify
    %     onset detection in the saved figures first. Under the run-on-guess
    %     override the save proceeds but paramSource stays guess. ---
    if isGuess
        if ~P.allowGuessRun
            error(['threshTask guess params: inspect the saved figures, then set ' ...
                   'paramSource=curated in dataTracking.xlsx (or call ' ...
                   'writeParams(P, S.id)) and re-run.']);
        end
        disp(['RUN-ON-GUESS (D4): saving outputs for ' S.id '; paramSource stays guess'])
    else
        P.paramSource = 'curated';
        writeParams(P, S.id);
    end

    % --- Save ---
    preDir = fullfile(S.root, S.id, 'preProc');
    if ~exist(preDir,'dir'), mkdir(preDir); end
    save(fullfile(preDir, [S.id '_PEA_threshold_preproc.mat']), 'outDat','-v7.3');

    writePreProcX(P, S.id);   % mark Data Preprocessed = X in dataTracking.xlsx

    catch ME
        disp(['fail for ', sessionIDs{s}, ': ', ME.message])
        disp(getReport(ME, 'extended', 'hyperlinks', 'off'))
    end
    close all   % unattended batches must not accumulate figures
end


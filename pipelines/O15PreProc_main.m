
clear
% ---- machine paths (everything machine-specific comes from labPaths) ----
zlpHere=fileparts(mfilename('fullpath')); zlpRoot=zlpHere; while exist(fullfile(zlpRoot,'config','labPaths.m'),'file')~=2, zlpP=fileparts(zlpRoot); if strcmp(zlpP,zlpRoot), error('zelanoLabPreprocessing root not found'); end; zlpRoot=zlpP; end; addpath(genpath(zlpRoot));
L       = labPaths();
codePre = L.codePre;
addpath(genpath(L.repo))
addpath(genpath(L.eeglab))

figPath = L.figPath;
EEGLOC  = readtable(L.eegLocCsv);   % load once, reuse

% =====================================================================
%  O15 preprocessing -- main pipeline
%  Sections marked TASK-SHARED are identical across all four pipelines
%  (breathing / cue / thresh / O15); do NOT edit them when adding a new task.
%  Sections marked TASK-SPECIFIC must be rewritten per task.
%  TASK-SPECIFIC pieces for O15 (rewrite these for a new task):
%    - assembleRaw_O15.m      (raw_O15 load + detect_ttls_O15 -> raw, TTL)
%    - detect_ttls_O15.m      (photodiode -> TTL table)
%    - assembleOutDat_O15extras.m  (O15-only outDat fields: CSClist, loadFile, ...)
%    - build_behavior_table_O15.m
%  Everything else is SHARED: applyParams, downsample_data, preprocess_eeg,
%  preprocess_macros, preprocess_respiration_wholetrace, detect_sniffs_from_TTLs,
%  refine_onsets_with_phase, paramCheck, writeParams, writePreProcX, plot_sniff_epochs.
% =====================================================================

cfg        = applyParams('O15','main');
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

  S = struct;
  S.id   = sessionIDs{s};
  if ~isempty(mainOnlyList) && ~any(strcmp(mainOnlyList, S.id)), continue; end
  disp(['working on ', sessionIDs{s}])
  S.root = cfg.root{s};
   matPath = fullfile(S.root, S.id);
  % done-check (2026-09-01: the old check pointed at a non-existent folder so
  % every sweep re-ran everything and the loop start was hand-edited instead)
  if ~exist(fullfile(matPath, 'preProc', [S.id '_O15preproc.mat']), 'file')
  S.figPath = figPath;
  if ~isfolder(fullfile(S.figPath, S.id))
      mkdir(fullfile(S.figPath, S.id))
  end
  P             = applyParams('O15', S.id);
  % anything not explicitly curated is treated as a guess
  isGuess = ~strcmpi(strtrim(P.paramSource), 'curated');
  P.allowGuessRun = allowGuessRunEnv && (strcmp(P.type, 'EEG') || ...
      strcmp(getenv('ZLP_ALLOW_GUESS_RUN_ALL'), '1'));
  % task subfolder (matches assembleOutDat's outDat.figs) so paramCheck
  % PNGs from different tasks of one session cannot overwrite each other
  P.figDir = fullfile(figPath, S.id, 'O15');
  if isGuess && allowGuessRunEnv && ~P.allowGuessRun
      disp(['SKIP (guess, not run per D4): ' S.id])
      continue
  end


  % trialStarts, buttonPresses, sniffMarks
  % --- Assemble: TASK-SPECIFIC loader (+ TTL detect) + shared assembler ---
  [raw, TTL] = assembleRaw_O15(S, P);                    % <-- TASK-SPECIFIC: edit/replace for a new task
  outDat     = assembleOutDat(raw, S, P);                % shared
  outDat     = assembleOutDat_O15extras(outDat, S, raw); % <-- TASK-SPECIFIC: O15-only outDat fields
  disp(['........................Loaded ', sessionIDs{s}])

  if isGuess
        [outDat, P] = paramCheck(outDat, P);
  end
  outDat.rspIDX = P.rspIDX;
  outDat.rspFlip = P.rspFlip;
  outDat.TTL = TTL;

  
  outDat = downsample_data(outDat, P.fs_target);

  if P.hasEEG, outDat = preprocess_eeg(outDat, EEGLOC, P); end


  outDat = preprocess_macros(outDat, P);
  disp(['........................spike and blink ', sessionIDs{s}])
    
  %there's more than one sniff per trial
  outDat.moreThan1 = 1; 

  % Precompute whole-trace respiration features ONCE
  R = preprocess_respiration_wholetrace(outDat); % fields: rsp, rsp_smooth, phase, onset_metric

  sniffs = detect_sniffs_from_TTLs(R, P, outDat);  % returns table or matrix

    % --- Guess gate: under the run-on-guess override the save proceeds but
    %     paramSource stays guess (never promoted). ---
    if isGuess
        if ~P.allowGuessRun
            error('check that onsets have been well-detected')
        end
        disp(['RUN-ON-GUESS (D4): saving outputs for ' S.id '; paramSource stays guess'])
    else
        P.paramSource = 'curated';
        writeParams(P, S.id);
    end


  % ----- TASK-SPECIFIC (O15): behavior table from sniffs + raw behavior -----
  outDat.behDat = build_behavior_table_O15(sniffs, raw.beh);
  % ----- end TASK-SPECIFIC -----

  outDat = refine_onsets_with_phase(outDat, R, P); % uses precomputed phase
  
  plot_sniff_epochs(outDat, R);
  disp(['........................breath behave ', sessionIDs{s}])
  if ~isfolder(fullfile(outDat.OGdataDir,  'preProc'))
      mkdir(fullfile(outDat.OGdataDir,  'preProc'))
  end
  save(fullfile(outDat.OGdataDir,  'preProc', ...
                [outDat.sessID '_O15preproc.mat']), ...
                'outDat', "-v7.3")

  writePreProcX(P, S.id)   % mark Data Preprocessed = X in dataTracking.xlsx
  else
       disp(['finished file detected for: ', sessionIDs{s}])
  end

  catch ME
      disp(['fail for ', sessionIDs{s}, ': ', ME.message])
      disp(getReport(ME, 'extended', 'hyperlinks', 'off'))
  end
  close all   % unattended batches must not accumulate figures
end


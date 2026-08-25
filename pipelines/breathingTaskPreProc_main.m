
clear
% ---- machine paths (everything machine-specific comes from labPaths) ----
zlpHere=fileparts(mfilename('fullpath')); zlpRoot=zlpHere; while exist(fullfile(zlpRoot,'config','labPaths.m'),'file')~=2, zlpP=fileparts(zlpRoot); if strcmp(zlpP,zlpRoot), error('zelanoLabPreprocessing root not found'); end; zlpRoot=zlpP; end; addpath(genpath(zlpRoot));
L            = labPaths();
codePre      = L.codePre;
addpath(genpath(L.repo))
addpath(genpath(L.slowBreathing))
addpath(genpath(L.eeglab))
% NB: breathMetrics (vendored in external/breathMetrics) is the per-breath
% segmentation engine via shared/segmentBreaths_breathMetrics — on the path
% through the repo genpath above

targTraceDir = L.targTraceDir;
figPath      = L.figPath;

EEGLOC       = readtable(L.eegLocCsv);
set(0, 'defaultfigurewindowstyle', 'normal')

% =====================================================================
%  breathingTask preprocessing -- main pipeline
%  TASK-SHARED sections are identical across all four pipelines; do NOT edit
%  them when adding a new task. TASK-SPECIFIC sections must be rewritten.
%  Breathing is the richest task: it alone has ECG/HRV and target-trace alignment.
%  TASK-SPECIFIC pieces for breathingTask (rewrite these for a new task):
%    - assembleRaw_breathingTask.m           (raw load -> raw struct)
%    - breathingTask_makeOutDat.m            (per-session photodiode ingestion)
%    - process_respiration_breathing.m       (per-breath metrics, bmObj)
%    - alignTargetBreathingTraceSimplify.m   (paced/shadow target-trace alignment)
%    - build_behavior_table_breathingTask.m
%    - processECG.m / buildECGz.m / paramCheckECG.m   (ECG beat detection + HRV)
%    - flagBadBreaths.m, plotBreathLengths.m
%  Everything else is SHARED: applyParams, assembleOutDat, downsample_data,
%  preprocess_eeg, preprocess_macros, preprocess_respiration_wholetrace,
%  paramCheck, writeParams, writePreProcX, plot_sniff_epochs.
% =====================================================================

cfg        = applyParams('breathingTask','main');
sessionIDs = cfg.sessionIDs;

% Tasks_260824.md D4 batch override: when the env var is set, guess-param
% sessions of Type EEG are run anyway (QC figures saved, paramSource left as
% guess). Every other guess session still halts at the gate.
allowGuessRunEnv = strcmp(getenv('ZLP_ALLOW_GUESS_RUN'), '1');

success = ones(length(sessionIDs),1);
for s = 1:numel(sessionIDs)
    try
    disp(['working on ', sessionIDs{s}])
    % --- Session descriptor (adjust to your system) ---
    S = struct;
    S.id   = sessionIDs{s};
    S.root = cfg.root{s};
    S.fig  = fullfile(figPath, S.id);
    
    % --- Check if the session is already done --- %
    preDir = fullfile(S.root, S.id, 'preProc');

    outDat = load(fullfile(preDir, [S.id '_breathingPreproc.mat']));
    try
        outDat = outDat.out; 
    catch
        outDat = outDat.chanDat; 
    end
    if isfield(outDat, 'baseEmotion')
        disp(['Done with ' S.id ' ; ' num2str(s)])
        continue
    end

    % --- Params + raw load ---
    P = applyParams('breathingTask', S.id);
    isGuess = strcmp(P.paramSource, 'guess');
    P.allowGuessRun = allowGuessRunEnv && strcmp(P.type, 'EEG');   % D4
    P.figDir = S.fig;

    disp(['........................Loaded ', sessionIDs{s}])
    % --- Assemble: TASK-SPECIFIC loader + shared assembler ---
    raw    = assembleRaw_breathingTask(S);   % <-- TASK-SPECIFIC: edit/replace for a new task
    outDat = assembleOutDat(raw, S, P);      % shared

    % Guessed params: verify rsp channel + macro/spike choices interactively
    if isGuess, [outDat, P] = paramCheck(outDat, P); end

    outDat = downsample_data(outDat, P.fs_target);

    if P.hasEEG, outDat = preprocess_eeg(outDat, EEGLOC, P); end

    if P.hasMacros, outDat = preprocess_macros(outDat, P); end
    
    
    disp(['........................spike and blink ', sessionIDs{s}])

    % ===== TASK-SPECIFIC (breathing): per-breath metrics + target trace +
    %       behavior table + ECG/HRV + breath QC. (preprocess_respiration_wholetrace
    %       and plot_sniff_epochs below are shared helpers reused for plotting.) =====
    outDat = process_respiration_breathing(outDat, P);
    if isfield(outDat, 'TTL')
        TaskBreaks = [outDat.TTL/outDat.fs size(outDat.data,2)/outDat.fs];
    else
        TaskBreaks = 0:300:max(outDat.behDat.order)*300-10; 
    end
    for cndi = 1:length(TaskBreaks)
       
        outDat.bmObj(outDat.bmObj(:,2)>TaskBreaks(cndi),12) = cndi; 
    
    end
    outDat.moreThan1 = 1; 
    outDat.rspIDX = P.rspIDX;
    outDat.rspFlip = P.rspFlip; 

    if strcmp(S.id, '250811_Dupi_NMH_TPB_1')
        disp(['TPB 1 had target trace problems'])
    else
        % This doesn't work for the wave breathing task really at all: 
        [outDat, targTraces] = alignTargetBreathingTraceSimplify(outDat, targTraceDir);
    end
    outDat = build_behavior_table_breathingTask(outDat, outDat.bmObj);

    % Guessed params: verify ECG beat-detection spec (breathing-only) before it
    % drives processECG / HRV
    if isGuess, P = paramCheckECG(outDat, P); end

    outDat = processECG(outDat, P);
    
    disp(['........................breath behave heart ', sessionIDs{s}])
 
    outDat = flagBadBreaths(outDat); 

    %processing respiration just for plotting
    R = preprocess_respiration_wholetrace(outDat);
    plot_sniff_epochs(outDat, R);

    plotBreathLengths(outDat, R)
    % ===== end TASK-SPECIFIC (breathing) =====

    % --- Guess gate: stop before writing back / exporting / saving so the user
    %     can verify the rsp, macro, ECG and breath figures first. Under the D4
    %     run-on-guess override the save proceeds but paramSource stays guess
    %     (never promoted) so the outputs get checked by hand later. ---
    if isGuess
        if ~P.allowGuessRun
            error(['breathingTask guess params: inspect the saved figures (rsp / ' ...
                   'macros / ECG / breaths), then set paramSource=curated in ' ...
                   'dataTracking.xlsx (or call writeParams(P, S.id)) and re-run.']);
        end
        disp(['RUN-ON-GUESS (D4): saving outputs for ' S.id '; paramSource stays guess'])
    else
        P.paramSource = 'curated';
        writeParams(P, S.id);
    end

    if ~exist(L.procBehavior,'dir'), mkdir(L.procBehavior); end
    writetable(outDat.behDat, fullfile(L.procBehavior, [outDat.sessID '_processedBreathing.csv']));

    % --- Save ---
    preDir = fullfile(S.root, S.id, 'preProc');
    if ~exist(preDir,'dir'), mkdir(preDir); end
    parSave(fullfile(preDir, [S.id '_breathingPreproc.mat']), outDat);

    writePreProcX(P, S.id);   % mark Data Preprocessed = X in dataTracking.xlsx

    catch ME
        success(s) = 0; 
        disp(['fail for ', sessionIDs{s}, ': ', ME.message])
    end
    
    
end

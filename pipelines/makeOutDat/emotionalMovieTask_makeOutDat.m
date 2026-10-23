% TASK-SPECIFIC ingestion for EmotionalMovieTask (Tasks_260824.md Task 7):
% raw_EmotionalMovieTask.mat -> <id>_EmotionalMovieTaskPreProc.mat with the
% photodiode parsed into a clip table (clipOnset, clipEnd, nPulses, valence).
% Modelled on cueTask_makeOutDat; the clip grammar (1/2/3 pulses at clip onset
% = neutral/happy/sad, end = next onset - 1.6 s) comes from the old
% ZelanoLabScripts pipeline (detect_ttls_EmotionalMovie).

clear
% ---- machine paths (everything machine-specific comes from labPaths) ----
zlpHere=fileparts(mfilename('fullpath'));
zlpRoot=zlpHere;
while exist(fullfile(zlpRoot,'config','labPaths.m'),'file')~=2
    zlpP=fileparts(zlpRoot);
    if strcmp(zlpP,zlpRoot)
        error('zelanoLabPreprocessing root not found');
    end
    zlpRoot=zlpP;
end
addpath(genpath(zlpRoot));
L = labPaths();
figPath = L.figPath;

cfg        = applyParams('emotionalMovieTask', 'makeOutDat');
sessionIDs = cfg.sessionIDs;
datPre     = cfg.datPre;
datPrei    = cfg.datPrei;

% ZLP_MAKEOUTDAT_ONLY restrict the sweep (blank = all sessions)
onlyEnv = strtrim(getenv('ZLP_MAKEOUTDAT_ONLY'));
onlyList = {};
if ~isempty(onlyEnv), onlyList = strtrim(strsplit(onlyEnv, ',')); onlyList = onlyList(~cellfun(@isempty, onlyList)); end

for sessi = 1:length(sessionIDs)
    if ~isempty(onlyList) && ~any(strcmpi(onlyList, sessionIDs{sessi}))
        continue
    end
    disp(['Working on: ' sessionIDs{sessi}])
    try

    outFile = [datPre{datPrei(sessi)} sessionIDs{sessi} '\preProc\' ...
               sessionIDs{sessi} '_EmotionalMovieTaskPreProc.mat'];
    if exist(outFile, 'file')
        disp('   intermediate/final already present - skipping')
        continue
    end

    rawFile = [datPre{datPrei(sessi)} sessionIDs{sessi} ...
               '\raw\raw_EmotionalMovieTask\raw_EmotionalMovieTask.mat'];
    dat = load(rawFile);
    dat = dat.curDat;

    outDat = struct;
    outDat.labels  = dat.outLabs;
    outDat.CSClist = dat.ncslabels;
    outDat.fs      = dat.rawData.fsample;
    outDat.sessID  = sessionIDs{sessi};
    outDat.data    = dat.rawData.trial{1};
    % LoadData provenance (shared lookup; never fatal - the intermediate's
    % loadFile is not carried into the final)
    outDat.OGdataDir = [datPre{datPrei(sessi)} sessionIDs{sessi}];
    outDat.loadFile  = findLoadDataScript(outDat.OGdataDir, 'EmotionalMovieTask', dat);
    clear dat

    % old-pipeline NaN handling: drop trailing/detached NaN columns flagged on
    % the last channel (the photodiode), interpolate any interior gaps
    nanCols = isnan(outDat.data(end, :));
    if any(nanCols)
        if mean(nanCols) > 0.5
            error('more than half the recording is NaN - inspect %s', sessionIDs{sessi});
        end
        outDat.data(:, nanCols) = [];
    end
    if any(isnan(outDat.data(:)))
        outDat.data = fillmissing(outDat.data, 'linear', 2, 'EndValues', 'nearest');
    end

    outDat.behDat = table();      % per-breath table built by the main; the PsychoPy clip log (below) feeds TTL
    if datPrei(sessi) == 1
        outDat.type = 'Dupi';
    elseif datPrei(sessi) == 2
        outDat.type = 'OBE';
    else
        outDat.type = 'EEG';
    end
    outDat.preProcScript = 'emotionalMovieTask_makeOutDat.m';

    % ---- photodiode -> clip table (fs_target sample space) ----
    P = applyParams('emotionalMovieTask', sessionIDs{sessi});
    outDat.TTL = detect_ttls_emotionalMovieTask(outDat, P, fullfile(figPath, sessionIDs{sessi}));
    % PsychoPy cross-check (2026-10-08): when the session's PsychoPy clip log is
    % in <id>\behavioralData\ (or, for the 2025 OBE layout, <id>\BehaviorResults\
    % emotionClips\), keep only photodiode clips that match a played clip
    % (valence from the log, threshold chosen by agreement) - see
    % matchClipsToPsychoPy. Sessions without the log keep the photodiode table.
    csvPath = findPsychoPyClipLog_emotionalMovie(fullfile(datPre{datPrei(sessi)}, sessionIDs{sessi}), sessionIDs{sessi});
    if ~isempty(csvPath)
        [outDat.TTL, outDat.clipCheck] = matchClipsToPsychoPy(outDat, P, ...
            csvPath, fullfile(figPath, sessionIDs{sessi}));
        % the movieClipTTLs figure shows the last threshold tried: redraw it at the chosen one
        Pc = P; Pc.pd.zthresh = outDat.clipCheck.zthresh;
        detect_ttls_emotionalMovieTask(outDat, Pc, fullfile(figPath, sessionIDs{sessi}));
    else
        disp('   no PsychoPy clip log (behavioralData, BehaviorResults\emotionClips) - photodiode clip table not cross-checked, no clip identity / norms')
    end
    fprintf('   %d clips: %d neutral / %d happy / %d sad\n', height(outDat.TTL), ...
        sum(outDat.TTL.valence == "neutral"), sum(outDat.TTL.valence == "happy"), ...
        sum(outDat.TTL.valence == "sad"));

    if ~isfolder([datPre{datPrei(sessi)} sessionIDs{sessi} '\preProc\'])
        mkdir([datPre{datPrei(sessi)} sessionIDs{sessi} '\preProc\']);
    end
    save(outFile, 'outDat', '-v7.3')
    disp('   intermediate saved')

    catch ME
        disp(['FAIL for ' sessionIDs{sessi} ': ' ME.message])
    end
    clearvars outDat
end

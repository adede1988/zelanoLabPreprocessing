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

for sessi = 1:length(sessionIDs)
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

    outDat.behDat = table();      % this task has no behavioral file
    if datPrei(sessi) == 1
        outDat.type = 'Dupi';
    elseif datPrei(sessi) == 2
        outDat.type = 'OBE';
    else
        outDat.type = 'EEG';
    end
    outDat.OGdataDir = [datPre{datPrei(sessi)} sessionIDs{sessi}];
    tmp = dir([datPre{datPrei(sessi)} sessionIDs{sessi}]);
    tmp = tmp(cellfun(@(x) contains(x, 'LoadData') & endsWith(x, '.m'), {tmp.name}));
    if size(tmp, 1) == 1
        outDat.loadFile = tmp.name;
    else
        tmp2 = tmp(cellfun(@(x) contains(x, 'EmotionalMovieTask'), {tmp.name}));
        if size(tmp2, 1) == 1
            outDat.loadFile = tmp2.name;
        else
            error('load file not identified uniquely')
        end
    end
    outDat.preProcScript = 'emotionalMovieTask_makeOutDat.m';

    % ---- photodiode -> clip table (fs_target sample space) ----
    P = applyParams('emotionalMovieTask', sessionIDs{sessi});
    outDat.TTL = detect_ttls_emotionalMovieTask(outDat, P, fullfile(figPath, sessionIDs{sessi}));
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

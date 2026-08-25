% TASK-SPECIFIC ingestion for alternating6Blocks (Tasks_260824.md Task 8):
% raw_alternating6Blocks.mat + the Google-Drive behavioral files ->
% <id>_alternating6BlocksPreProc.mat with:
%   .TTL      block-start samples at fs_target (breathing-style vector)
%   .blocks   table label / order / startSample / endSample (fs_target)
%   .behDat   ratings table (set, order, Q_short, type, question, rsp, t)
%   .logAlign lag / |r| / drift / inferred rspFlip from alignLogToRaw
%
% File matching (D11a): mindfulBreathing carries the participant ID in its
% name; the sniffLogicLog (no ID) is matched by date and nearest start time.
% The match must be unique within +/-3 h or the session errors.

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
behDir  = fullfile(L.gdrive, 'cZelano', 'breathingDataFiles');

cfg        = applyParams('alternating6Blocks', 'makeOutDat');
sessionIDs = cfg.sessionIDs;
datPre     = cfg.datPre;
datPrei    = cfg.datPrei;

for sessi = 1:length(sessionIDs)
    disp(['Working on: ' sessionIDs{sessi}])
    try

    outFile = [datPre{datPrei(sessi)} sessionIDs{sessi} '\preProc\' ...
               sessionIDs{sessi} '_alternating6BlocksPreProc.mat'];
    if exist(outFile, 'file')
        disp('   intermediate/final already present - skipping')
        continue
    end

    rawFile = [datPre{datPrei(sessi)} sessionIDs{sessi} ...
               '\raw\raw_alternating6Blocks\raw_alternating6Blocks.mat'];
    dat = load(rawFile);
    dat = dat.curDat;

    outDat = struct;
    outDat.labels  = dat.outLabs;
    outDat.CSClist = dat.ncslabels;
    outDat.fs      = dat.rawData.fsample;
    outDat.sessID  = sessionIDs{sessi};
    outDat.data    = dat.rawData.trial{1};
    clear dat
    if any(isnan(outDat.data(:)))
        nBad = sum(isnan(outDat.data(1, :)));
        fprintf('   filling %d NaN samples\n', nBad);
        outDat.data = fillmissing(outDat.data, 'linear', 2, 'EndValues', 'nearest');
    end
    outDat.type = 'EEG';
    outDat.OGdataDir = [datPre{datPrei(sessi)} sessionIDs{sessi}];
    tmp = dir([datPre{datPrei(sessi)} sessionIDs{sessi}]);
    tmp = tmp(cellfun(@(x) contains(x, 'LoadData') & endsWith(x, '.m'), {tmp.name}));
    if size(tmp, 1) == 1
        outDat.loadFile = tmp.name;
    else
        tmp2 = tmp(cellfun(@(x) contains(x, 'alternating6Blocks'), {tmp.name}));
        assert(size(tmp2, 1) == 1, 'load file not identified uniquely');
        outDat.loadFile = tmp2.name;
    end
    outDat.preProcScript = 'alternating6Blocks_makeOutDat.m';

    % ---- behavioral files (D11a) ----
    mb = dir(fullfile(behDir, [sessionIDs{sessi} '_mindfulBreathing_*.csv']));
    assert(numel(mb) == 1, 'expected exactly 1 mindfulBreathing csv for %s, found %d', ...
        sessionIDs{sessi}, numel(mb));
    mbTime = datetime(regexp(mb(1).name, '\d{4}-\d{2}-\d{2}_\d{2}h\d{2}', 'match', 'once'), ...
                      'InputFormat', 'yyyy-MM-dd_HH''h''mm');
    sl = dir(fullfile(behDir, 'sniffLogicLog_*.csv'));
    slTimes = NaT(numel(sl), 1);
    for k = 1:numel(sl)
        tok = regexp(sl(k).name, 'sniffLogicLog_(\d{8})_(\d{6})_', 'tokens', 'once');
        slTimes(k) = datetime([tok{1} tok{2}], 'InputFormat', 'yyyyMMddHHmmss');
    end
    dt = abs(slTimes - mbTime);
    [dmin, ki] = min(dt);
    others = sort(dt);
    assert(dmin < hours(3), 'nearest sniffLogicLog is %.1f h away - no match', hours(dmin));
    assert(numel(others) < 2 || others(2) > hours(3), ...
        'ambiguous sniffLogicLog match for %s (two logs within 3 h) - stop and ask', sessionIDs{sessi});
    fprintf('   matched %s (dt = %.0f min)\n', sl(ki).name, minutes(dmin));

    % ---- parse + align ----
    [log, blocksLog] = parse_sniffLogicLog(fullfile(sl(ki).folder, sl(ki).name));
    ratings = parse_mindfulBreathing(fullfile(mb(1).folder, mb(1).name));

    isRsp = cellfun(@(x) contains(x, 'rsp'), outDat.labels);
    rsp = outDat.data(isRsp, :);
    rsp = rsp(1, :);                     % rsp1 = CSC31, unflipped
    A = alignLogToRaw(log, rsp, outDat.fs, sessionIDs{sessi}, ...
                      fullfile(figPath, sessionIDs{sessi}));
    outDat.logAlign = rmfield(A, 'logToRaw500');
    fprintf('   inferred rspFlip = %+d (|r| = %.2f)\n', A.rspFlip, A.r);

    % ---- block boundaries -> fs_target samples ----
    n500 = floor(size(outDat.data, 2) / (outDat.fs / 500));
    blocks = table();
    blocks.label = blocksLog.label;
    blocks.order = blocksLog.order;
    blocks.startSample = max(1, A.logToRaw500(blocksLog.tStart));
    blocks.endSample   = min(n500, A.logToRaw500(blocksLog.tEnd));
    assert(all(blocks.endSample > blocks.startSample), 'block boundaries collapsed');
    outDat.blocks = blocks;
    outDat.TTL = blocks.startSample';    % breathing-style vector
    outDat.behDat = ratings;

    if ~isfolder([datPre{datPrei(sessi)} sessionIDs{sessi} '\preProc\'])
        mkdir([datPre{datPrei(sessi)} sessionIDs{sessi} '\preProc\']);
    end
    save(outFile, 'outDat', '-v7.3')
    disp('   intermediate saved')

    catch ME
        disp(['FAIL for ' sessionIDs{sessi} ': ' ME.message])
    end
    clearvars outDat log ratings
end

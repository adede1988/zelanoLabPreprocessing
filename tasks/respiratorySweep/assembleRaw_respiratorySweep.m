function raw = assembleRaw_respiratorySweep(S)
%ASSEMBLERAW_RESPIRATORYSWEEP  TASK-SPECIFIC raw load for respiratorySweep.
%
%   raw = assembleRaw_respiratorySweep(S)   S.id, S.root (from the main loop)
%
%   The session's LoadData_<id>_claude.m writes
%       <root>\<id>\raw\raw_respiratorySweep\raw_respiratorySweep.mat  (curDat)
%   with the Atlas channels AND the protocol's event table: curDat.TTL (one row
%   per block, raw samples - built by buildSweepTTL from the SniffLogic logs plus
%   the stopwatch blocks of the session notes), curDat.TTLinfo (alignment
%   record) and curDat.logTrace (log pressure / target on the raw clock). So
%   there is no makeOutDat step: the raw file is loaded directly (like O15 /
%   pacedBreathing) and the block table travels with it.
%
%   The ratings (PsychoPy <id>_mindfulBreathing_*.csv in <root>\<id>\
%   behavioralData\) are parsed here (parse_sweepRatings) into raw.beh, which
%   assembleOutDat stores as the initial outDat.behDat; the behavior-table
%   builder moves them to outDat.ratings.
%
%   Returns the fields shared/assembleOutDat.m reads (data / labels / fs_raw /
%   beh) plus blocksRaw (curDat.TTL), TTLinfo, logTrace and the O15-style
%   provenance extras (CSClist, OGdataDir, loadFile). raw.TTL is NOT set: the
%   main converts blocksRaw to the final 500-Hz block table and the
%   breathing-style TTL vector after the shared core (it needs outDat.origFS).

    rawFile = fullfile(S.root, S.id, 'raw', 'raw_respiratorySweep', 'raw_respiratorySweep.mat');
    if ~exist(rawFile, 'file')
        error('assembleRaw_respiratorySweep:MissingRaw', ...
            'Expected extracted raw file at %s (run the session''s LoadData script first).', rawFile);
    end
    tmp = load(rawFile);
    assert(isfield(tmp, 'curDat'), 'assembleRaw_respiratorySweep: %s must contain curDat', rawFile);
    dat = tmp.curDat; clear tmp
    assert(isfield(dat, 'TTL') && istable(dat.TTL) && height(dat.TTL) > 0, ...
        'assembleRaw_respiratorySweep:noTTL', ...
        '%s has no curDat.TTL block table - re-run the session''s LoadData script', rawFile);

    data = dat.rawData.trial{1};
    if any(isnan(data(:)))
        nBad = sum(isnan(data(1, :)));
        fprintf('assembleRaw_respiratorySweep: filling %d NaN samples (discontinuous Neuralynx read)\n', nBad);
        data = fillmissing(data, 'linear', 2, 'EndValues', 'nearest');
    end

    raw = struct();
    raw.sessID    = S.id;
    raw.fs_raw    = dat.rawData.fsample;
    raw.data      = data;
    raw.labels    = dat.outLabs;
    raw.CSClist   = dat.ncslabels;
    raw.OGdataDir = fullfile(S.root, S.id);
    raw.blocksRaw = dat.TTL;
    raw.TTLinfo   = dat.TTLinfo;
    raw.logTrace  = dat.logTrace;
    assert(dat.TTLinfo.nSamples == size(data, 2), 'assembleRaw_respiratorySweep:TTLlength', ...
        'the TTL table was built for %d samples but the raw data have %d', dat.TTLinfo.nSamples, size(data, 2));

    % ratings (PsychoPy) from the session's behavioralData folder
    behDir = fullfile(S.root, S.id, 'behavioralData');
    mb = dir(fullfile(behDir, [S.id '_mindfulBreathing_*.csv']));
    if isempty(mb)
        warning('assembleRaw_respiratorySweep:noRatings', '%s: no mindfulBreathing csv in %s - no ratings', S.id, behDir);
        raw.beh = table();
    else
        raw.beh = parse_sweepRatings(fullfile({mb.folder}, {mb.name}));
    end

    % which LoadData script produced the raw file (provenance; never fatal)
    raw.loadFile = findLoadDataScript(raw.OGdataDir, 'respiratorySweep', dat);

    assert(size(raw.data, 1) == numel(raw.labels), ...
        'assembleRaw_respiratorySweep: %d data rows vs %d labels', size(raw.data, 1), numel(raw.labels));
    assert(any(cellfun(@(x) contains(x, 'rsp'), raw.labels)), ...
        'assembleRaw_respiratorySweep: no respiration (rsp) channel in the raw file');
end

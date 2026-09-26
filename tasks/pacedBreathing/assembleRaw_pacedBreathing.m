function raw = assembleRaw_pacedBreathing(S)
%ASSEMBLERAW_PACEDBREATHING  TASK-SPECIFIC raw load for pacedBreathing.
%
%   raw = assembleRaw_pacedBreathing(S)   S.id, S.root (from the main loop)
%
%   pacedBreathing recordings carry NO event marks and NO behavioral files,
%   so (like O15) there is no makeOutDat step: the extracted raw file written
%   by the session's LoadData script,
%       <root>\<id>\raw\raw_pacedBreathing\raw_pacedBreathing.mat  (curDat),
%   is loaded directly. Block structure is inferred later in the main from
%   the segmented breaths (inferBlocks_pacedBreathing), so no TTL is returned
%   here (assembleOutDat's TTL passthrough is data-driven on the field).
%
%   Returns the fields shared/assembleOutDat.m reads (data / labels / fs_raw /
%   beh) plus the O15-style provenance extras (CSClist, OGdataDir, loadFile)
%   that the main copies onto outDat.

    rawFile = fullfile(S.root, S.id, 'raw', 'raw_pacedBreathing', 'raw_pacedBreathing.mat');
    if ~exist(rawFile, 'file')
        error('assembleRaw_pacedBreathing:MissingRaw', ...
            'Expected extracted raw file at %s (run the session''s LoadData script first).', rawFile);
    end
    tmp = load(rawFile);
    assert(isfield(tmp, 'curDat'), 'assembleRaw_pacedBreathing: %s must contain curDat', rawFile);
    dat = tmp.curDat; clear tmp

    data = dat.rawData.trial{1};
    if any(isnan(data(:)))
        nBad = sum(isnan(data(1, :)));
        fprintf('assembleRaw_pacedBreathing: filling %d NaN samples (discontinuous Neuralynx read)\n', nBad);
        data = fillmissing(data, 'linear', 2, 'EndValues', 'nearest');
    end

    raw = struct();
    raw.sessID  = S.id;
    raw.fs_raw  = dat.rawData.fsample;
    raw.data    = data;
    raw.labels  = dat.outLabs;
    raw.beh     = table();            % no behavioral file for this task
    raw.CSClist = dat.ncslabels;
    raw.OGdataDir = fullfile(S.root, S.id);
    % recording segments (multi-file acquisitions stitched end to end by the
    % LoadData script; one row per segment with startSample at fs_raw, plus the
    % wall-clock gap before each) - optional, used to flag breaths at the seams
    if isfield(dat, 'segments'), raw.segments = dat.segments; end

    % which LoadData script produced the raw file (provenance, as in O15;
    % shared lookup - curDat.loadFile first, never fatal)
    raw.loadFile = findLoadDataScript(raw.OGdataDir, 'pacedBreathing', dat);

    assert(size(raw.data, 1) == numel(raw.labels), ...
        'assembleRaw_pacedBreathing: %d data rows vs %d labels', size(raw.data, 1), numel(raw.labels));
    assert(any(cellfun(@(x) contains(x, 'rsp'), raw.labels)), ...
        'assembleRaw_pacedBreathing: no respiration (rsp) channel in the raw file');
end

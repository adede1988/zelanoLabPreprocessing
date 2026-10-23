function raw = assembleRaw_airPuff(S, P)
%ASSEMBLERAW_AIRPUFF  TASK-SPECIFIC raw load for airPuff (no makeOutDat).
%
%   raw = assembleRaw_airPuff(S, P)   S.id, S.root (from the main loop), P from applyParams
%
%   airPuff (added 2026-10-15 with 261008_INR_NWU_SS_1): the participant holds
%   their breath and air is puffed up the nose through a tube; one DAQ pulse on
%   the event channel per puff. There is no behavioral file, so (like O15 /
%   pacedBreathing) the extracted raw file written by the session's LoadData
%   script,
%       <root>\<id>\raw\raw_airPuff\raw_airPuff.mat  (curDat),
%   is loaded directly. The event channel is parsed HERE, on the raw-rate trace
%   (parsePuffEvents_airPuff, options P.puffOpts), before the shared core's
%   resample + 0.03-Hz high-pass reshape it; the main converts the pulse
%   samples to the final rate.
%
%   Returns the fields shared/assembleOutDat.m reads (data / labels / fs_raw /
%   beh) plus the provenance extras (CSClist, OGdataDir, loadFile, atlasSegments)
%   and the parse (pulses = every DAQ pulse with its role at fs_raw, puffInfo).

    rawFile = fullfile(S.root, S.id, 'raw', 'raw_airPuff', 'raw_airPuff.mat');
    if ~exist(rawFile, 'file')
        error('assembleRaw_airPuff:MissingRaw', ...
            'Expected extracted raw file at %s (run the session''s LoadData script first).', rawFile);
    end
    tmp = load(rawFile);
    assert(isfield(tmp, 'curDat'), 'assembleRaw_airPuff: %s must contain curDat', rawFile);
    dat = tmp.curDat; clear tmp

    data = dat.rawData.trial{1};
    if any(isnan(data(:)))
        nBad = sum(isnan(data(1, :)));
        fprintf('assembleRaw_airPuff: filling %d NaN samples (partial Atlas records)\n', nBad);
        data = fillmissing(data, 'linear', 2, 'EndValues', 'nearest');
    end

    raw = struct();
    raw.sessID    = S.id;
    raw.fs_raw    = dat.rawData.fsample;
    raw.data      = data;
    raw.labels    = dat.outLabs;
    raw.beh       = table();          % no behavioral file for this task
    raw.CSClist   = dat.ncslabels;
    raw.OGdataDir = fullfile(S.root, S.id);
    if isfield(dat, 'atlasSegments'), raw.atlasSegments = dat.atlasSegments; end
    raw.loadFile  = findLoadDataScript(raw.OGdataDir, 'airPuff', dat);   % provenance (curDat.loadFile first)

    assert(size(raw.data, 1) == numel(raw.labels), ...
        'assembleRaw_airPuff: %d data rows vs %d labels', size(raw.data, 1), numel(raw.labels));
    assert(any(cellfun(@(x) contains(x, 'rsp'), raw.labels)), ...
        'assembleRaw_airPuff: no respiration (rsp) channel in the raw file');
    isEv = cellfun(@(x) contains(x, 'event'), raw.labels);
    assert(sum(isEv) == 1, 'assembleRaw_airPuff: expected exactly one event channel, found %d', sum(isEv));

    opts = struct();
    if isfield(P, 'puffOpts') && isfield(P.puffOpts, 'parse'), opts = P.puffOpts.parse; end
    [raw.pulses, raw.puffInfo] = parsePuffEvents_airPuff(raw.data(isEv, :), raw.fs_raw, opts);
    fprintf('assembleRaw_airPuff: %d lead + %d puffs (%d cued holds, %d blind holds) + separator at %.1f s\n', ...
        sum(raw.pulses.role == "lead"), raw.puffInfo.nPuffs, raw.puffInfo.nHoldsCued, ...
        raw.puffInfo.nHoldsBlind, raw.puffInfo.separatorSec);
end

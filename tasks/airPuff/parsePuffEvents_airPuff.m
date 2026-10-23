function [pulses, info] = parsePuffEvents_airPuff(ev, fs, opts)
%PARSEPUFFEVENTS_AIRPUFF  Parse the airPuff DAQ event channel into lead / puff / separator pulses.
%
%   [pulses, info] = parsePuffEvents_airPuff(ev, fs, opts)
%
%   ev   : the RAW event channel (1 x nSamp, NaNs already filled), fs : its rate.
%          Parse it before downsample_data: the shared 0.03-Hz high-pass would
%          reshape the AC-coupled, rail-clipped trace.
%   opts : optional struct (P.puffOpts from applyParams), fields (defaults):
%     threshFrac      0.5    pulse-on threshold = median + threshFrac*(low - median),
%                            low = the 0.5th percentile (the negative rail when clipped)
%                            - rail/median-referenced levels, never a z-score
%     mergeGapSec     0.005  re-join a pulse split by a gap shorter than this
%     minPulseSec     0.02   drop blips shorter than this
%     pulseSec        0.26   width of every DAQ pulse of this task (measured 0.257-0.261 s)
%     widthTolSec     0.04   |width - pulseSec| tolerance (strict: error outside it)
%     trainSpacingSec 0.52   onset-to-onset spacing of the pulses of a marker train
%     trainTolSec     0.08   (puffs are >= 1.5 s apart, so they never chain into a train)
%     nLead           3      pulses of the leading marker before the first puff (the
%                            protocol's "3 DAQ pulses prior to the first run"); per
%                            session in applyParams (261008_INR_NWU_SS_1: 1)
%     nSep            3      pulses of the separator train between the cued run
%                            (before it) and the blind run (after it)
%     holdGapSec      5      consecutive puffs closer than this belong to one breath hold
%     expectedHolds   []     [nCued nBlind] holds; [] = no check
%     puffsPerHold    []     puffs in every hold; [] = no check
%     strict          true   error on any departure from the structure; false keeps
%                            going and labels unexplained pulses 'extra' (surveys only)
%
%   Protocol (user, 2026-10-15): the participant holds their breath and air is
%   puffed up the nose through a tube. Lead marker, then one DAQ pulse per puff
%   delivered (run 1, each puff announced by a "Puff" auditory cue = 'cued'),
%   then the separator (3 pulses), then one pulse per puff with no cue (run 2,
%   the participant blind to the timing = 'blind'). Each pulse marks the puff
%   delivery time. The event input is AC-coupled and rail-clipped: a pulse
%   steps to the negative rail and its release throws the trace onto the
%   positive rail, decaying over seconds (later pulses start from there).
%
%   Outputs (raw-sample indices at fs; onset = first sample below the threshold,
%   i.e. the half-height crossing of the falling step; offset = last sample below):
%     pulses : table, one row per DAQ pulse: pulse, onsetRaw, offsetRaw, durSec,
%              tSec, role ("lead" / "puff" / "separator" / "extra"), train
%              (marker-train index), puff (puff index, NaN for markers), hold
%              (global hold index), holdInRun, puffNum (1.. within the hold),
%              run (1 cued, 2 blind; NaN for markers), condition ("cued" /
%              "blind" / "")
%     info   : levels, threshold, rail fractions, counts, the options used.

    if nargin < 3 || isempty(opts), opts = struct; end
    d = struct('threshFrac', 0.5, 'mergeGapSec', 0.005, 'minPulseSec', 0.02, ...
        'pulseSec', 0.26, 'widthTolSec', 0.04, 'trainSpacingSec', 0.52, 'trainTolSec', 0.08, ...
        'nLead', 3, 'nSep', 3, 'holdGapSec', 5, 'expectedHolds', [], 'puffsPerHold', [], ...
        'strict', true);
    fn = fieldnames(d);
    for i = 1:numel(fn)
        if ~isfield(opts, fn{i}), opts.(fn{i}) = d.(fn{i}); end
    end

    ev = double(ev(:))';
    if any(~isfinite(ev)), error('parsePuffEvents_airPuff:NaN', 'fill NaNs before parsing'); end

    % ---- levels and threshold (rail/median-referenced, no z-score) ----
    info = struct;
    info.opts = opts;
    info.min = min(ev); info.max = max(ev);
    info.median = median(ev);
    info.low = prctile(ev, 0.5);
    info.thresh = info.median + opts.threshFrac * (info.low - info.median);
    rng = info.max - info.min;
    info.fracBelowThresh = mean(ev < info.thresh);
    info.fracNegRail = mean(ev <= info.min + 0.002 * rng);
    info.fracPosRail = mean(ev >= info.max - 0.002 * rng);
    if info.median - info.low < 0.25 * rng
        error('parsePuffEvents_airPuff:noPulses', ...
            'no negative-going pulses (median %.1f, 0.5th pct %.1f, range %.1f)', ...
            info.median, info.low, rng);
    end

    % ---- pulses = runs below the threshold ----
    on = ev < info.thresh;
    dd = diff([false on false]);
    s = find(dd == 1); f = find(dd == -1) - 1;
    gapMin = round(opts.mergeGapSec * fs);
    k = 1;
    while k < numel(s)
        if s(k+1) - f(k) - 1 < gapMin
            f(k) = f(k+1); s(k+1) = []; f(k+1) = [];
        else
            k = k + 1;
        end
    end
    keep = (f - s + 1) >= round(opts.minPulseSec * fs);
    info.nBlips = sum(~keep);
    s = s(keep); f = f(keep);
    n = numel(s);
    if n == 0, error('parsePuffEvents_airPuff:noPulses', 'no pulse below the threshold'); end

    pulses = table;
    pulses.pulse    = (1:n)';
    pulses.onsetRaw = s(:);
    pulses.offsetRaw = f(:);
    pulses.durSec   = (f(:) - s(:) + 1) / fs;
    pulses.tSec     = (s(:) - 1) / fs;
    pulses.role     = repmat("unassigned", n, 1);
    pulses.train    = nan(n, 1);
    pulses.puff     = nan(n, 1);
    pulses.hold     = nan(n, 1);
    pulses.holdInRun = nan(n, 1);
    pulses.puffNum  = nan(n, 1);
    pulses.run      = nan(n, 1);
    pulses.condition = repmat("", n, 1);

    badW = abs(pulses.durSec - opts.pulseSec) >= opts.widthTolSec;
    info.nBadWidth = sum(badW);
    if any(badW) && opts.strict
        error('parsePuffEvents_airPuff:width', ...
            '%d pulse(s) not %.2f +- %.2f s wide (first at %.2f s: %.3f s)', ...
            sum(badW), opts.pulseSec, opts.widthTolSec, pulses.tSec(find(badW, 1)), pulses.durSec(find(badW, 1)));
    end

    % ---- marker trains: consecutive pulses at trainSpacingSec ----
    gap = diff(pulses.tSec);
    link = abs(gap - opts.trainSpacingSec) < opts.trainTolSec;     % pulse i chains to i+1
    trainOf = cumsum([1; ~link(:)]);                                % singletons are trains of 1
    tLen = accumarray(trainOf, 1);
    info.trainLengths = tLen(:)';

    % ---- lead marker: the first train must have exactly nLead pulses ----
    if tLen(1) ~= opts.nLead
        msg = sprintf(['the first DAQ train has %d pulse(s) (at %.2f s), the lead marker should have %d ' ...
            '(set P.puffOpts.nLead in applyParams for this session after checking the event channel)'], ...
            tLen(1), pulses.tSec(1), opts.nLead);
        if opts.strict, error('parsePuffEvents_airPuff:lead', '%s', msg); end
        warning('parsePuffEvents_airPuff:lead', '%s', msg);
    end
    isLead = trainOf == 1;
    pulses.role(isLead) = "lead";
    pulses.train(isLead) = 1;

    % ---- separator: the one later train of nSep pulses; every other later train must be a single puff ----
    later = 2:numel(tLen);
    sepTrains = later(tLen(later) == opts.nSep);
    oddTrains = later(tLen(later) ~= opts.nSep & tLen(later) ~= 1);
    if ~isempty(oddTrains)
        msg = sprintf('%d marker train(s) of unexpected length (first: %d pulses at %.2f s)', numel(oddTrains), ...
            tLen(oddTrains(1)), pulses.tSec(find(trainOf == oddTrains(1), 1)));
        if opts.strict, error('parsePuffEvents_airPuff:train', '%s', msg); end
        warning('parsePuffEvents_airPuff:train', '%s', msg);
        for tI = oddTrains
            pulses.role(trainOf == tI) = "extra"; pulses.train(trainOf == tI) = tI;
        end
    end
    if numel(sepTrains) ~= 1
        msg = sprintf('%d separator train(s) of %d pulses found, expected exactly 1', numel(sepTrains), opts.nSep);
        if opts.strict, error('parsePuffEvents_airPuff:separator', '%s', msg); end
        warning('parsePuffEvents_airPuff:separator', '%s', msg);
    end
    sepT = Inf;
    if ~isempty(sepTrains)
        isSep = trainOf == sepTrains(1);
        pulses.role(isSep) = "separator";
        pulses.train(isSep) = sepTrains(1);
        sepT = pulses.tSec(find(isSep, 1));
        for tI = sepTrains(2:end)          % only reached when strict = false
            pulses.role(trainOf == tI) = "extra"; pulses.train(trainOf == tI) = tI;
        end
    end
    info.separatorSec = sepT;

    % ---- puffs: the remaining single pulses; cued before the separator, blind after ----
    ip = find(pulses.role == "unassigned");
    pulses.role(ip) = "puff";
    pulses.puff(ip) = (1:numel(ip))';
    isCued = pulses.tSec(ip) < sepT;
    pulses.run(ip(isCued)) = 1;  pulses.condition(ip(isCued)) = "cued";
    pulses.run(ip(~isCued)) = 2; pulses.condition(ip(~isCued)) = "blind";

    % ---- breath holds: consecutive puffs closer than holdGapSec, never across the separator ----
    tp = pulses.tSec(ip);
    newHold = [true; diff(tp) >= opts.holdGapSec | diff(pulses.run(ip)) ~= 0];
    hOf = cumsum(newHold);
    pulses.hold(ip) = hOf;
    for h = 1:max([hOf; 0])
        m = ip(hOf == h);
        pulses.puffNum(m) = (1:numel(m))';
    end
    for r = 1:2
        hr = unique(pulses.hold(pulses.run == r));
        for j = 1:numel(hr)
            pulses.holdInRun(pulses.hold == hr(j)) = j;
        end
    end

    nHold = max([hOf; 0]);
    info.nLeadFound = tLen(1);
    info.nPuffs = numel(ip);
    info.nHolds = nHold;
    info.nHoldsCued = numel(unique(pulses.hold(pulses.run == 1)));
    info.nHoldsBlind = numel(unique(pulses.hold(pulses.run == 2)));
    info.puffsPerHoldFound = accumarray(hOf, 1)';
    wIn = diff(tp); wIn = wIn(~newHold(2:end));            % onset-to-onset spacing within holds
    info.withinHoldSpacingSec = [min([wIn; NaN]), median(wIn), max([wIn; NaN])];

    % ---- expected structure (per session in applyParams) ----
    if ~isempty(opts.expectedHolds) && ~isequal([info.nHoldsCued info.nHoldsBlind], opts.expectedHolds(:)')
        msg = sprintf('found %d cued + %d blind holds, expected %d + %d', info.nHoldsCued, info.nHoldsBlind, ...
            opts.expectedHolds(1), opts.expectedHolds(2));
        if opts.strict, error('parsePuffEvents_airPuff:holdCount', '%s', msg); end
        warning('parsePuffEvents_airPuff:holdCount', '%s', msg);
    end
    if ~isempty(opts.puffsPerHold) && any(info.puffsPerHoldFound ~= opts.puffsPerHold)
        msg = sprintf('puffs per hold %s, expected %d each', mat2str(info.puffsPerHoldFound), opts.puffsPerHold);
        if opts.strict, error('parsePuffEvents_airPuff:puffCount', '%s', msg); end
        warning('parsePuffEvents_airPuff:puffCount', '%s', msg);
    end
end

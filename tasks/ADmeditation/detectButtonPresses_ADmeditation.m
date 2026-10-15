function [presses, info] = detectButtonPresses_ADmeditation(ev, fs, opts)
%DETECTBUTTONPRESSES_ADMEDITATION  Button presses on the ADmeditation event channel.
%
%   [presses, info] = detectButtonPresses_ADmeditation(ev, fs, opts)
%
%   ev    raw event-channel trace (the 'event' row of the extracted raw file,
%         CSC269, uV) of the WHOLE recording, before any trimming
%   fs    its sample rate (2000 Hz on this rig)
%   opts  struct, any field overrides the default below (P.adMedOpts.press)
%
%   The button marks a "good" meditative state. On this rig it reaches the
%   event input as a ~5-s pulse through an AC coupling: the press is a sharp
%   step (~750 uV; ~1100 uV in 2026-06-25) that decays back to baseline with a
%   ~0.6-s time constant, and the release ~5 s later is the mirror step of the
%   opposite sign. Which sign comes first depends on the reader: CSC269 is
%   recorded with InputInverted = True, which the lab's ReadNCS (the LoadData
%   reader) does NOT apply, so in the extracted raw file the press is a
%   NEGATIVE step and the release a positive one (a header-aware reader sees
%   the reverse). The detector therefore takes the press polarity from the
%   data - the press is the FIRST step of each press -> release pair - and
%   never assumes it (opts.polarity 'auto'; a session with no pairs falls back
%   to opts.defaultPolarity = -1, this rig's extracted raw). The channel also
%   carries heavy 60-Hz pickup (rms up to ~1.5 mV, more than the steps), so the
%   trace is low-passed before detection; after that the noise floor is ~2 uV
%   (probe 2026-10-08, E:\claudeWork\adMed1008\probe2, all 14 recordings).
%
%   Method
%     1. low-pass (Butterworth, order 4, opts.lpHz, zero-phase), subtract a
%        running median (opts.baselineSec) -> y
%     2. step candidates = positive peaks of y above thr and negative peaks
%        below -thr, thr = max(opts.minAmpUV, opts.minSD x robust SD of y);
%        peaks at least opts.minSepSec apart; peaks within opts.ignoreEdgeSec of
%        either end of the recording are dropped (filter start-up / end
%        transients)
%     3. edge time = walking back from the peak to the last sample where |y|
%        was below opts.edgeFrac x the peak (at most 0.5 s back). With the
%        default 0.5 this is the step's half-height crossing, which a
%        zero-phase low-pass leaves at the true step time (a 10% level lands
%        ~23 ms early at 10 Hz; synthetic test 2026-10-08: |error| < 5 ms)
%     4. polarity: for each sign, count the steps that are followed by an
%        opposite-sign step within opts.maxPressSec before the next same-sign
%        step; the sign with more such pairs is the press, a tie goes to the
%        sign whose pairs have the shorter median gap, and no evidence at all
%        (e.g. no steps) to opts.defaultPolarity. maxPressSec defaults to 15 s:
%        the pulse is 4.8-5.4 s in every probed recording, so a release ->
%        next-press gap only counts when presses come < ~20 s apart. info
%        records both counts.
%     5. each press is paired with the first release that follows it within
%        opts.maxPressSec and before the next press; an unpaired press keeps
%        NaN release, an unpaired release (a press that began before the
%        recording) is counted in info.orphanReleaseRaw but is not a press.
%
%   presses  table, one row per press, in time order:
%     press        1..n
%     onsetRaw     onset sample in the raw (untrimmed) recording
%     releaseRaw   release sample (NaN if none was found)
%     durationSec  (releaseRaw - onsetRaw) / fs
%     ampOnUV      size of the press step (baseline-corrected, uV, positive)
%     ampOffUV     size of the release step (uV, positive)
%     tRecSec      onset time from the start of the raw recording (s)
%   info     struct: thrUV, robustSD, polarity (sign of the press step in ev),
%            nPairsIfPos / nPairsIfNeg (the evidence), orphanReleaseRaw, opts

    def = struct('lpHz', 10, 'baselineSec', 10, 'minAmpUV', 200, 'minSD', 20, ...
                 'minSepSec', 1, 'ignoreEdgeSec', 2, 'edgeFrac', 0.5, 'maxPressSec', 15, ...
                 'polarity', 'auto', 'defaultPolarity', -1);
    if nargin < 3 || isempty(opts), opts = struct(); end
    fn = fieldnames(opts);
    for i = 1:numel(fn)
        assert(isfield(def, fn{i}), 'detectButtonPresses_ADmeditation: unknown option "%s"', fn{i});
        def.(fn{i}) = opts.(fn{i});
    end
    opts = def;

    x = double(ev(:));
    assert(all(isfinite(x)), 'detectButtonPresses_ADmeditation: event trace has non-finite samples');
    x = x - median(x);
    [z, p, k] = butter(4, opts.lpHz / (fs / 2), 'low');
    [sos, g] = zp2sos(z, p, k);
    lp = filtfilt(sos, g, x);

    % running-median baseline on a 100-Hz copy (the trace is low-passed at
    % opts.lpHz << 50 Hz, so the decimation does not alias)
    step = max(1, round(fs / 100));
    iD = (1:step:numel(lp))';
    baseD = movmedian(lp(iD), max(3, round(opts.baselineSec * fs / step)));
    base = interp1(iD, baseD, (1:numel(lp))', 'linear', 'extrap');
    y = lp - base;

    robustSD = 1.4826 * median(abs(y - median(y)));
    thr = max(opts.minAmpUV, opts.minSD * robustSD);
    minSep = max(1, round(opts.minSepSec * fs));
    edge = round(opts.ignoreEdgeSec * fs);
    n = numel(y);

    [pkUp, locUp] = findpeaksSafe(y, thr, minSep);
    [pkDn, locDn] = findpeaksSafe(-y, thr, minSep);
    keepUp = locUp > edge & locUp <= n - edge; pkUp = pkUp(keepUp); locUp = locUp(keepUp);
    keepDn = locDn > edge & locDn <= n - edge; pkDn = pkDn(keepDn); locDn = locDn(keepDn);
    edgeUp = arrayfun(@(l, h) walkBack(y, l, opts.edgeFrac * h, round(0.5 * fs)), locUp, pkUp);
    edgeDn = arrayfun(@(l, h) walkBack(-y, l, opts.edgeFrac * h, round(0.5 * fs)), locDn, pkDn);

    % ---- press polarity from the data: the press is the first step of a pair ----
    maxPair = round(opts.maxPressSec * fs);
    [nIfPos, gPos] = countPairs(edgeUp, edgeDn, maxPair);
    [nIfNeg, gNeg] = countPairs(edgeDn, edgeUp, maxPair);
    if ischar(opts.polarity) || isstring(opts.polarity)
        assert(strcmpi(opts.polarity, 'auto'), 'detectButtonPresses_ADmeditation: polarity must be ''auto'', 1 or -1');
        if nIfPos > nIfNeg
            pol = 1;
        elseif nIfNeg > nIfPos
            pol = -1;
        elseif nIfPos > 0 && median(gPos) ~= median(gNeg)
            pol = 2 * (median(gPos) < median(gNeg)) - 1;   % tie: the shorter gaps are the press -> release pairs
        else
            pol = opts.defaultPolarity;
        end
    else
        pol = sign(opts.polarity);
        assert(abs(pol) == 1, 'detectButtonPresses_ADmeditation: polarity must be ''auto'', 1 or -1');
    end
    if pol == 1
        onset = edgeUp; pkOn = pkUp; release = edgeDn; pkOff = pkDn;
    else
        onset = edgeDn; pkOn = pkDn; release = edgeUp; pkOff = pkUp;
    end

    nP = numel(onset);
    releaseRaw = nan(nP, 1); ampOff = nan(nP, 1);
    used = false(numel(release), 1);
    for i = 1:nP
        lim = onset(i) + round(opts.maxPressSec * fs);
        if i < nP, lim = min(lim, onset(i + 1)); end
        j = find(~used & release > onset(i) & release < lim, 1);
        if ~isempty(j)
            releaseRaw(i) = release(j); ampOff(i) = pkOff(j); used(j) = true;
        end
    end

    presses = table();
    presses.press       = (1:nP)';
    presses.onsetRaw    = onset(:);
    presses.releaseRaw  = releaseRaw;
    presses.durationSec = (releaseRaw - onset(:)) / fs;
    presses.ampOnUV     = pkOn(:);
    presses.ampOffUV    = ampOff;
    presses.tRecSec     = (onset(:) - 1) / fs;

    info = struct('thrUV', thr, 'robustSD', robustSD, 'polarity', pol, ...
                  'nPairsIfPos', nIfPos, 'nPairsIfNeg', nIfNeg, ...
                  'orphanReleaseRaw', release(~used), 'opts', opts);
end

function [pk, loc] = findpeaksSafe(y, thr, minSep)
% findpeaks without the "no data above MinPeakHeight" warning on press-free recordings
    if max(y) <= thr
        pk = zeros(0, 1); loc = zeros(0, 1); return;
    end
    w = warning('off', 'signal:findpeaks:largeMinPeakHeight');   % only edge samples above thr
    [pk, loc] = findpeaks(y, 'MinPeakHeight', thr, 'MinPeakDistance', minSep);
    warning(w);
    pk = pk(:); loc = loc(:);
end

function [k, gaps] = countPairs(a, b, maxGap)
% number of a-steps followed by a b-step within maxGap samples and before the
% next a-step, and those gaps (samples)
    k = 0; gaps = zeros(0, 1);
    for i = 1:numel(a)
        lim = a(i) + maxGap;
        if i < numel(a), lim = min(lim, a(i + 1)); end
        j = find(b > a(i) & b < lim, 1);
        if ~isempty(j), k = k + 1; gaps(end + 1, 1) = b(j) - a(i); end %#ok<AGROW>
    end
end

function s = walkBack(y, loc, level, maxBack)
% last sample at or before loc where y was below level (edge start), at most maxBack back
    i0 = max(1, loc - maxBack);
    k = find(y(i0:loc) < level, 1, 'last');
    if isempty(k), s = i0; else, s = i0 + k - 1; end
end

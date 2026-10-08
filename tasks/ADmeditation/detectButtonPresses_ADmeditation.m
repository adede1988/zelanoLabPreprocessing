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
%   POSITIVE step (~+750 uV; ~+1100 uV in 2026-06-25) that decays back to
%   baseline with a ~0.6-s time constant, and the release ~5 s later is the
%   mirror NEGATIVE step. The channel also carries heavy 60-Hz pickup (rms up
%   to ~1.5 mV, more than the steps), so the trace is low-passed before
%   detection; after that the noise floor is ~2 uV (probe 2026-10-08,
%   E:\claudeWork\adMed1008\probe2, all 14 recordings).
%
%   Method
%     1. low-pass (Butterworth, order 4, opts.lpHz, zero-phase), subtract a
%        running median (opts.baselineSec) -> y
%     2. press candidates = positive peaks of y above thr, release candidates
%        = negative peaks below -thr, thr = max(opts.minAmpUV, opts.minSD x
%        robust SD of y); peaks at least opts.minSepSec apart; peaks within
%        opts.ignoreEdgeSec of either end of the recording are dropped (filter
%        start-up / end transients)
%     3. edge time = walking back from the peak to the last sample where |y|
%        was below opts.edgeFrac x the peak (at most 0.5 s back). With the
%        default 0.5 this is the step's half-height crossing, which a
%        zero-phase low-pass leaves at the true step time (a 10% level lands
%        ~23 ms early at 10 Hz; synthetic test 2026-10-08: |error| < 5 ms)
%     4. each press is paired with the first release that follows it within
%        opts.maxPressSec and before the next press; an unpaired press keeps
%        NaN release, an unpaired release (a press that began before the
%        recording) is counted in info.orphanReleaseRaw but is not a press.
%
%   presses  table, one row per press, in time order:
%     press        1..n
%     onsetRaw     onset sample in the raw (untrimmed) recording
%     releaseRaw   release sample (NaN if none was found)
%     durationSec  (releaseRaw - onsetRaw) / fs
%     ampOnUV      height of the press step (baseline-corrected, uV)
%     ampOffUV     depth of the release step (uV, positive number)
%     tRecSec      onset time from the start of the raw recording (s)
%   info     struct: thrUV, robustSD, orphanReleaseRaw, opts

    def = struct('lpHz', 10, 'baselineSec', 10, 'minAmpUV', 200, 'minSD', 20, ...
                 'minSepSec', 1, 'ignoreEdgeSec', 2, 'edgeFrac', 0.5, 'maxPressSec', 30);
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

    [pkOn, locOn] = findpeaksSafe(y, thr, minSep);
    [pkOff, locOff] = findpeaksSafe(-y, thr, minSep);
    keepOn = locOn > edge & locOn <= n - edge;   pkOn = pkOn(keepOn);   locOn = locOn(keepOn);
    keepOff = locOff > edge & locOff <= n - edge; pkOff = pkOff(keepOff); locOff = locOff(keepOff);

    onset = arrayfun(@(l, h) walkBack(y, l, opts.edgeFrac * h, round(0.5 * fs)), locOn, pkOn);
    release = arrayfun(@(l, h) walkBack(-y, l, opts.edgeFrac * h, round(0.5 * fs)), locOff, pkOff);

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

    info = struct('thrUV', thr, 'robustSD', robustSD, ...
                  'orphanReleaseRaw', release(~used), 'opts', opts);
end

function [pk, loc] = findpeaksSafe(y, thr, minSep)
% findpeaks without the "no data above MinPeakHeight" warning on press-free recordings
    if max(y) <= thr
        pk = zeros(0, 1); loc = zeros(0, 1); return;
    end
    [pk, loc] = findpeaks(y, 'MinPeakHeight', thr, 'MinPeakDistance', minSep);
    pk = pk(:); loc = loc(:);
end

function s = walkBack(y, loc, level, maxBack)
% last sample at or before loc where y was below level (edge start), at most maxBack back
    i0 = max(1, loc - maxBack);
    k = find(y(i0:loc) < level, 1, 'last');
    if isempty(k), s = i0; else, s = i0 + k - 1; end
end

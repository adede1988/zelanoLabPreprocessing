function probe = probeRespViability_vipassana(rsp, fs, blocks, opts)
%PROBERESPVIABILITY_VIPASSANA  Does the respiration channel carry breathing?
%
%   probe = probeRespViability_vipassana(rsp, fs, blocks)
%   probe = probeRespViability_vipassana(rsp, fs, blocks, opts)
%
%   The vipassana belt channel is unusable in some sessions (CC: the 'resp'
%   input carries only 60-Hz pickup and irregular slow noise). Running the
%   locked breath engine on such a trace produces confident-looking garbage,
%   so the main asks this probe first and skips the respiration stage when
%   the trace does not look like breathing.
%
%   Method
%     1. demean, resample to opts.fsProbe (50 Hz; polyphase resample),
%        band-pass opts.band (0.02-1 Hz, Butterworth order 2 in second-order
%        sections, zero-phase filtfilt) over the WHOLE trace (so block edges
%        add no filter edges);
%     2. evaluation spans = the still blocks (blocks.still == 1, spans
%        startSample..endSample at fs) - the task periods, where the
%        participant sits still and breathing dominates; with no blocks
%        (empty / no still rows / missing columns) the whole recording is one
%        span;
%     3. periodicity:
%          acPeak / acLagSec : each span is cut into non-overlapping
%                              opts.acWinSec (120 s) windows (a span shorter
%                              than that but >= opts.acMinWinSec gives one
%                              window of its own length); per window the
%                              largest INTERIOR local maximum of the
%                              normalised autocorrelation ('coeff') at lags
%                              opts.acLagSec (2-20 s = 3-30 breaths/min) and
%                              its lag (a window whose AC has no interior
%                              maximum - monotone decay, i.e. drift or
%                              smoothness, not periodicity - scores 0);
%                              acPeak = MEDIAN over windows, acLagSec =
%                              median lag of the windows with a peak;
%          acPeakConcat      : the same maximum over the concatenated spans
%                              (diagnostic only, see the deviation note);
%          bandFrac          : Welch PSD of the concatenated spans (90-s Hann
%                              windows, 50% overlap): power in opts.breathBand
%                              (0.05-0.7 Hz) as a fraction of the power in
%                              opts.band (0.02-1 Hz);
%          peakHz / bpm      : frequency of the PSD maximum inside opts.band,
%                              and 60*peakHz;
%     4. viable = acPeak >= opts.acMin (0.40) && bandFrac >= opts.fracMin (0.85)
%                 && peakHz in opts.peakRange ([0.05 0.6] Hz)
%        and at least opts.minSec (120 s) of trace was evaluated.
%     DEVIATIONS from the 2026-09-26 design spec
%     - AC over the concatenated still blocks: tested on the real sessions,
%       the concatenated AC of the clean AS belt was only 0.32 (whole
%       recording 0.21) because the breathing rate differs between blocks
%       (the AC peak smears across lags) and a few high-amplitude movement
%       stretches dominate the normalisation; the 13-min-window reference
%       values of the spec (AS 0.69, DD 0.67, CC 0.21) are reproduced by the
%       windowed median instead (AS/DD pass, CC fails on both acPeak and
%       bandFrac).
%     - Bands lowered after review (spec: band 0.05-1, breathBand 0.1-0.7,
%       peakRange 0.1-0.6 Hz, AC lags 2-12 s, 60-s Welch): the spec bands
%       rejected clean synthetic belt signals at 4-6 breaths/min (plausible
%       in meditation; bandFrac 0.16-0.31, PSD peak below 0.1 Hz), and the
%       respiration of the whole session would then be dropped
%       (respSkipped = 2). The new defaults pass clean synthetic breathing at
%       4-24 /min, still reject white / red noise, a random walk and a flat
%       trace, and leave the real decisions unchanged (AS AC 0.71 / frac
%       0.98 and DD 0.66 / 0.95 viable; CC 0.18 / 0.75 not viable). The
%       interior-maximum rule replaces a plain max over the lag window,
%       whose value could be the lag-edge of a smooth trace. Pass the spec
%       values in opts to restore the old bands.
%
%   Inputs
%     rsp    : 1 x N respiration trace at fs (polarity irrelevant here)
%     fs     : sampling rate (Hz)
%     blocks : inferBlocks_vipassana table (label, still, startSample,
%              endSample, ...) or [] / empty table -> whole recording
%     opts   : optional struct; missing / empty fields take the defaults
%              fsProbe 50, band [0.02 1], breathBand [0.05 0.7], acLagSec [2 20],
%              acWinSec 120, acMinWinSec 60, acMin 0.40, fracMin 0.85,
%              peakRange [0.05 0.6], minSec 120, welchSec 90
%
%   Output
%     probe : struct
%       viable (logical), acPeak, acLagSec, bandFrac, peakHz, bpm (= 60*peakHz),
%       acBPM (= 60/acLagSec), acPeakConcat, acPeakWin (per-window peaks),
%       nWindows, nSecEvaluated, source ('stillBlocks' | 'wholeRecording'),
%       reason (why not viable; '' if viable), thresholds (struct acMin /
%       fracMin / peakRange / minSec), method (text)
%
%   Caveats
%     - The probe measures periodicity, not polarity (rspFlip is set on the
%       sheet and checked physiologically by checkRspPolarityRSA).
%     - Band-limited noise gives spurious AC maxima of ~0.1-0.3 in 1-2 min
%       windows (max over 2-20 s lags); the 0.40 threshold sits above that,
%       and bandFrac is an independent second test.
%     - Breathing slower than ~4 /min (period > 15 s) fails bandFrac / the
%       PSD-peak range (3 /min synthetic: frac 0.35) - widen the bands in
%       opts for such a session.
%     - A strongly periodic artifact at breathing rates (e.g. a rocking
%       movement) would pass; it is not expected in seated meditation.

    if nargin < 4 || isempty(opts), opts = struct(); end
    dflt = struct('fsProbe', 50, 'band', [0.02 1], 'breathBand', [0.05 0.7], 'acLagSec', [2 20], ...
                  'acWinSec', 120, 'acMinWinSec', 60, 'acMin', 0.40, 'fracMin', 0.85, ...
                  'peakRange', [0.05 0.6], 'minSec', 120, 'welchSec', 90);
    fn = fieldnames(dflt);
    for k = 1:numel(fn)
        if ~isfield(opts, fn{k}) || isempty(opts.(fn{k})), opts.(fn{k}) = dflt.(fn{k}); end
    end

    probe = struct('viable', false, 'acPeak', NaN, 'acLagSec', NaN, 'bandFrac', NaN, 'peakHz', NaN, ...
                   'bpm', NaN, 'acBPM', NaN, 'acPeakConcat', NaN, 'acPeakWin', zeros(1, 0), 'nWindows', 0, ...
                   'nSecEvaluated', 0, 'source', '', 'reason', '', ...
                   'thresholds', struct('acMin', opts.acMin, 'fracMin', opts.fracMin, ...
                                        'peakRange', opts.peakRange, 'minSec', opts.minSec), ...
                   'method', sprintf(['probeRespViability_vipassana: %g Hz, band-pass %g-%g Hz (Butterworth 2, filtfilt); ' ...
                                      'over the still blocks: median %g-s-window AC peak at %g-%g s lag >= %.2f, ' ...
                                      '%g-%g Hz power fraction >= %.2f, PSD peak in %g-%g Hz'], opts.fsProbe, opts.band, ...
                                      opts.acWinSec, opts.acLagSec, opts.acMin, opts.breathBand, opts.fracMin, opts.peakRange));

    x = double(rsp(:));
    assert(~isempty(x) && isscalar(fs) && fs > 0, 'probeRespViability_vipassana: empty trace or bad fs');
    N = numel(x);
    if ~all(isfinite(x)) || std(x) == 0
        probe.source = 'wholeRecording';
        probe.reason = 'trace is flat or non-finite';
        return
    end

    % ---- 1. resample + band-pass the whole trace ----
    [pp, qq] = rat(opts.fsProbe / fs, 1e-9);
    xd = resample(x - mean(x), pp, qq);
    fsd = fs * pp / qq;
    [zb, pb, kb] = butter(2, opts.band / (fsd / 2), 'bandpass');   % SOS: the low edge is ~1e-3 of Nyquist
    [sosB, gB] = zp2sos(zb, pb, kb);
    y = filtfilt(sosB, gB, xd);
    nY = numel(y);

    % ---- 2. evaluation spans (50-Hz indices) ----
    spans = [1 nY];
    probe.source = 'wholeRecording';
    if ~isempty(blocks) && istable(blocks) && height(blocks) > 0 && ...
            all(ismember({'still', 'startSample', 'endSample'}, blocks.Properties.VariableNames))
        st = blocks(blocks.still == 1, :);
        if height(st) > 0
            spans = zeros(height(st), 2);
            for b = 1:height(st)
                spans(b, 1) = max(1, floor((st.startSample(b) - 1) * fsd / fs) + 1);
                spans(b, 2) = min(nY, floor((min(st.endSample(b), N) - 1) * fsd / fs) + 1);
            end
            spans = spans(spans(:, 2) >= spans(:, 1), :);
            probe.source = 'stillBlocks';
        end
    end
    keep = false(nY, 1);
    for b = 1:size(spans, 1), keep(spans(b, 1):spans(b, 2)) = true; end
    yc = y(keep);
    probe.nSecEvaluated = numel(yc) / fsd;
    if probe.nSecEvaluated < opts.minSec
        probe.reason = sprintf('only %.0f s evaluated (< %g s)', probe.nSecEvaluated, opts.minSec);
        return
    end

    % ---- 3a. windowed autocorrelation peak ----
    lagLo = round(opts.acLagSec(1) * fsd); maxLag = round(opts.acLagSec(2) * fsd);
    wLen = round(opts.acWinSec * fsd); wMin = max(round(opts.acMinWinSec * fsd), 2 * maxLag);
    pk = []; lg = [];
    for b = 1:size(spans, 1)
        len = spans(b, 2) - spans(b, 1) + 1;
        if len >= wLen
            starts = spans(b, 1) + (0:floor(len / wLen) - 1) * wLen; L = wLen;
        elseif len >= wMin
            starts = spans(b, 1); L = len;
        else
            continue
        end
        for w0 = starts
            [p1, l1] = acPeakOf(y(w0:w0 + L - 1), lagLo, maxLag);
            pk(end + 1) = p1; lg(end + 1) = l1; %#ok<AGROW>
        end
    end
    okW = isfinite(pk); pk = pk(okW); lg = lg(okW);   % flat windows carry no AC
    probe.acPeakWin = pk;
    probe.nWindows = numel(pk);
    [probe.acPeakConcat, ~] = acPeakOf(yc, lagLo, maxLag);
    if isempty(pk)
        probe.reason = 'no evaluation window long enough';
        return
    end
    probe.acPeak = median(pk);
    probe.acLagSec = median(lg, 'omitnan') / fsd;      % NaN lag = window without an interior AC peak
    probe.acBPM = 60 / probe.acLagSec;

    % ---- 3b. spectrum of the concatenated spans ----
    yc = yc - mean(yc);
    nw = min(numel(yc), round(opts.welchSec * fsd));
    [P, f] = pwelch(yc, hann(nw), floor(nw / 2), max(nw, 2 ^ nextpow2(nw)), fsd);
    inBand = f >= opts.band(1) & f <= opts.band(2);
    inBr   = f >= opts.breathBand(1) & f <= opts.breathBand(2);
    probe.bandFrac = trapz(f(inBr), P(inBr)) / max(trapz(f(inBand), P(inBand)), eps);
    fB = f(inBand); [~, j] = max(P(inBand));
    probe.peakHz = fB(j);
    probe.bpm = 60 * probe.peakHz;

    % ---- 4. decision ----
    why = {};
    if ~(probe.acPeak >= opts.acMin), why{end+1} = sprintf('AC peak %.2f < %.2f', probe.acPeak, opts.acMin); end
    if ~(probe.bandFrac >= opts.fracMin), why{end+1} = sprintf('band fraction %.2f < %.2f', probe.bandFrac, opts.fracMin); end
    if ~(probe.peakHz >= opts.peakRange(1) && probe.peakHz <= opts.peakRange(2))
        why{end+1} = sprintf('PSD peak %.3f Hz outside [%g %g]', probe.peakHz, opts.peakRange);
    end
    probe.viable = isempty(why);
    probe.reason = strjoin(why, '; ');
    if probe.viable, verdict = 'VIABLE'; else, verdict = ['NOT viable: ' probe.reason]; end
    fprintf(['probeRespViability_vipassana (%s, %.0f s, %d windows): AC %.2f at %.1f s (concatenated %.2f), ' ...
             'band fraction %.2f, peak %.3f Hz (%.1f /min) -> %s\n'], probe.source, probe.nSecEvaluated, probe.nWindows, ...
        probe.acPeak, probe.acLagSec, probe.acPeakConcat, probe.bandFrac, probe.peakHz, probe.bpm, verdict);
end

% ============================ helpers ============================

function [pk, lagSamp] = acPeakOf(z, lagLo, maxLag)
% Largest INTERIOR local maximum of the normalised autocorrelation at lags
% lagLo..maxLag (samples). A maximum on the edge of the lag window is the
% monotone decay of a smooth / drifting trace, not periodicity, so it does
% not count. pk = NaN for a flat or too short window (dropped by the
% caller); pk = 0 with lagSamp = NaN when r has no interior local maximum
% (kept: a non-periodic window votes against viability).
    z = z(:) - mean(z);
    if numel(z) <= maxLag || ~(std(z) > 0), pk = NaN; lagSamp = NaN; return; end
    [r, lags] = xcorr(z, maxLag, 'coeff');
    sel = lags >= lagLo;
    r = r(sel); lags = lags(sel);
    isPk = [false; r(2:end - 1) > r(1:end - 2) & r(2:end - 1) >= r(3:end); false];
    if ~any(isPk), pk = 0; lagSamp = NaN; return; end
    r(~isPk) = -Inf;
    [pk, i] = max(r);
    lagSamp = lags(i);
end

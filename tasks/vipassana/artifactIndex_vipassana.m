function T = artifactIndex_vipassana(eeg, fs, opts)
%ARTIFACTINDEX_VIPASSANA  1-s movement / EMG artifact index from the raw scalp EEG.
%
%   T = artifactIndex_vipassana(eeg, fs)
%   T = artifactIndex_vipassana(eeg, fs, opts)
%
%   The vipassana recordings carry only hand-pressed, incomplete markers, so
%   the task periods are inferred from the DATA (inferBlocks_vipassana): the
%   audiobook and meditation periods are long stretches of still, artifact-
%   free EEG, the questionnaires (participant moving, writing) are stretches
%   of movement / muscle artifact. This helper turns the raw scalp EEG into a
%   per-second "activity evidence" series for that segmentation:
%
%     1. drop rows whose standard deviation is 0 (the all-zero inserted Cz
%        reference row, flat / dead channels) or that contain non-finite
%        values; error if fewer than opts.minChans rows survive;
%     2. per channel (one at a time - a raw session is ~0.5 GB per copy):
%        remove the channel median (the data are DC-coupled), then
%          hf  = 30-100 Hz band (Butterworth, order opts.filtOrder, zero-phase
%                filtfilt in second-order sections) -> mean power per window
%                (muscle / EMG);
%          p2p = 1-100 Hz band (same filter design) -> max - min per window
%                (movement transients, electrode pops);
%        over non-overlapping 1-s windows (round(fs) samples; a trailing
%        partial window is dropped); and the channel's whole-recording LINE
%        FRACTION = Welch power in opts.lineHz +/- 2 Hz over the power in the
%        p2p band (1-100 Hz) - the same measure as batch/probeMontageBV's
%        lineFrac (4-s Welch windows);
%     2b. rows whose line fraction exceeds opts.lineFracMax (0.5) are left
%        out of the channel median (if fewer than opts.minChans rows remain,
%        the opts.minChans least line-dominated rows are used, with a
%        warning). DEVIATION from the 2026-09-26 design spec (median over
%        every std > 0 row), added after review: in a high-impedance session
%        the line pickup sits inside both bands and sets the channel median.
%        260918_EEG_NWU_DD has 23/31 rows with line fraction > 0.5; there the
%        all-row median put questionnaire1/2 LOWER in hfLog than the
%        neighbouring meditations (mean questionnaire evid 0.28-0.47; without
%        markers questionnaire1|vipassana landed 68 s from its press), while
%        its 8 low-line rows give questionnaire evid 0.78-1.11 and marker-free
%        questionnaire boundaries within 1-8 s of the presses. AS and CC have
%        no row above 0.5 (evidence identical). opts.lineFracMax = Inf
%        restores the spec behaviour;
%     3. log10 of each feature, then the MEDIAN ACROSS CHANNELS per window
%        (robust to a few bad channels) -> hfLog, p2pLog;
%     4. robust z over the whole recording, z = (x - median) / (1.4826*MAD)
%        (falls back to the std if the MAD is 0), and
%        art = mean of the two z's;
%     5. slow baseline: artBase = running median of art over opts.baseWin
%        windows (default 601 = 10 min; MATLAB movmedian, shrinking at the
%        ends), artDev = art - artBase. A 10-min median follows slow changes
%        of the overall level (electrode drying, drowsiness, EMG tone) but
%        not a ~2-min questionnaire, which therefore stands out in artDev
%        even when the whole recording is noisy;
%     6. evid = movmedian( min(max(artDev, opts.clipLo), opts.clipHi), opts.smoothWin )
%        - clipped so that a single huge artifact cannot dominate the
%        segmentation cost, then a 5-s running median removes isolated
%        blips (single movements inside a meditation).
%     With fs < 250 Hz the upper band edges (100 Hz) exceed 0.8*Nyquist and
%     are lowered to 0.8*(fs/2) with a warning.
%
%   Inputs
%     eeg  : [nChan x nSamp] RAW scalp EEG (before any cleaning / re-reference,
%            i.e. outDat.data(1:32,:) right after assembleOutDat), in uV.
%            Rows with std == 0 (the inserted Cz reference) are dropped.
%     fs   : sampling rate (Hz) of eeg; the window is round(fs) samples, so
%            any fs works (500 Hz for these recordings).
%     opts : optional struct; missing / empty fields take the defaults
%              winSec    1          window length (s)
%              hfBand    [30 100]   EMG band (Hz)
%              p2pBand   [1 100]    peak-to-peak band (Hz)
%              filtOrder 4          Butterworth design order (band-pass => 2x poles)
%              baseWin   601        running-median baseline length (windows)
%              clipLo    -1         lower clip of artDev
%              clipHi    4          upper clip of artDev
%              smoothWin 5          running-median length of evid (windows)
%              minChans  4          minimum number of usable channels (else error)
%              lineHz    60         mains frequency (Hz) for the line fraction
%              lineFracMax 0.5      rows above this line fraction leave the median
%                                   (Inf = keep every usable row)
%              lineWelchSec 4       Welch window of the line fraction (s)
%
%   Output
%     T : table, one row per window -
%           tSec    window centre (s from the first sample; 0.5, 1.5, ... at winSec = 1)
%           hfLog   channel-median log10 30-100 Hz power (uV^2)
%           p2pLog  channel-median log10 1-100 Hz peak-to-peak (uV)
%           art     mean robust z of hfLog and p2pLog (un-baselined)
%           artBase running-median baseline of art
%           artDev  art - artBase
%           evid    clipped + smoothed artDev: the activity evidence that
%                   inferBlocks_vipassana consumes (high = movement / EMG)
%         T.Properties.UserData = struct(opts, fs, winSamples, chansUsed
%         (row indices into eeg that entered the channel median), chansUsable
%         (std > 0 and finite), chansLineDropped (usable but line-dominated),
%         lineFrac (1 x nChanIn, NaN for unusable rows), nChanIn,
%         zCenter / zScale of hf and p2p).
%
%   Caveats
%     - The index is a RELATIVE measure within one recording (robust z); it
%       says which seconds are noisier than that recording's own typical
%       second, not whether the recording is clean in absolute terms.
%     - 60-Hz line noise sits inside the 30-100 Hz band. On a channel where it
%       is small it only raises the baseline (removed by the z-score /
%       artBase); channels where it dominates are left out of the median
%       (step 2b), because their line level drifts over the recording and
%       masks the EMG contrast. No notch is applied (a 60/120-Hz notch was
%       tested in review and lowered AS's late-boundary margins).
%     - The first / last ~2 s carry filter edge transients; the robust
%       statistics and the 5-s median make them harmless for segmentation.

    if nargin < 3 || isempty(opts), opts = struct(); end
    dflt = struct('winSec', 1, 'hfBand', [30 100], 'p2pBand', [1 100], 'filtOrder', 4, ...
                  'baseWin', 601, 'clipLo', -1, 'clipHi', 4, 'smoothWin', 5, 'minChans', 4, ...
                  'lineHz', 60, 'lineFracMax', 0.5, 'lineWelchSec', 4);
    fn = fieldnames(dflt);
    for k = 1:numel(fn)
        if ~isfield(opts, fn{k}) || isempty(opts.(fn{k})), opts.(fn{k}) = dflt.(fn{k}); end
    end

    assert(isnumeric(eeg) && ismatrix(eeg), 'artifactIndex_vipassana: eeg must be a numeric [nChan x nSamp] matrix');
    assert(isscalar(fs) && fs > 0, 'artifactIndex_vipassana: fs must be a positive scalar');
    [nChanIn, nSamp] = size(eeg);
    w = round(opts.winSec * fs);
    nWin = floor(nSamp / w);
    assert(nWin >= 10, 'artifactIndex_vipassana: recording too short (%d windows of %d samples)', nWin, w);

    % ---- 1. usable rows ----
    sd = zeros(nChanIn, 1);
    fin = true(nChanIn, 1);
    for c = 1:nChanIn
        x = double(eeg(c, :));
        fin(c) = all(isfinite(x));
        if fin(c), sd(c) = std(x); end
    end
    use = find(fin & sd > 0);
    assert(numel(use) >= opts.minChans, ...
        'artifactIndex_vipassana: only %d usable EEG rows (std > 0, finite); need >= %d', numel(use), opts.minChans);

    % ---- filters (SOS, zero phase) ----
    nyq = fs / 2;
    hfB = opts.hfBand; p2pB = opts.p2pBand;
    if hfB(2) > 0.8 * nyq || p2pB(2) > 0.8 * nyq
        warning('artifactIndex_vipassana:lowFs', ...
            'fs = %g Hz: upper band edges lowered from %g/%g Hz to %g Hz (0.8*Nyquist)', ...
            fs, hfB(2), p2pB(2), 0.8 * nyq);
        hfB(2)  = min(hfB(2),  0.8 * nyq);
        p2pB(2) = min(p2pB(2), 0.8 * nyq);
    end
    assert(hfB(1) < hfB(2) && p2pB(1) < p2pB(2), 'artifactIndex_vipassana: invalid bands for fs = %g Hz', fs);
    [z1, p1, k1] = butter(opts.filtOrder, hfB / nyq, 'bandpass');
    [sosH, gH] = zp2sos(z1, p1, k1);
    [z2, p2, k2] = butter(opts.filtOrder, p2pB / nyq, 'bandpass');
    [sosP, gP] = zp2sos(z2, p2, k2);
    % a single-section SOS (filtOrder 1) is ambiguous with (b, a) in filtfilt:
    % append an identity section so it is always read as SOS
    if size(sosH, 1) == 1, sosH = [sosH; 1 0 0 1 0 0]; end
    if size(sosP, 1) == 1, sosP = [sosP; 1 0 0 1 0 0]; end

    % ---- 2. per-channel, per-window features (+ whole-recording line fraction) ----
    nU = numel(use);
    hfPow = zeros(nU, nWin);
    p2p   = zeros(nU, nWin);
    lineFrac = nan(nU, 1);
    lineBand = opts.lineHz + [-2 2];
    doLine = isfinite(opts.lineFracMax) && lineBand(1) > p2pB(1) && lineBand(2) <= p2pB(2);
    idx = 1:nWin * w;
    for u = 1:nU
        x = double(eeg(use(u), :));
        if doLine          % same measure as batch/probeMontageBV's lineFrac (4-s Welch, mean removed)
            [Pw, fw] = pwelch(x - mean(x), round(opts.lineWelchSec * fs), [], [], fs);
            lineFrac(u) = bandPow(Pw, fw, lineBand) / max(bandPow(Pw, fw, p2pB), eps);
        end
        x = x - median(x);
        xh = filtfilt(sosH, gH, x(:));
        xh = reshape(xh(idx), w, nWin);
        hfPow(u, :) = mean(xh .^ 2, 1);
        xp = filtfilt(sosP, gP, x(:));
        xp = reshape(xp(idx), w, nWin);
        p2p(u, :) = max(xp, [], 1) - min(xp, [], 1);
    end
    clear xh xp x

    % ---- 2b. drop line-dominated rows from the channel median ----
    inMed = true(nU, 1);
    if doLine
        inMed = lineFrac <= opts.lineFracMax;
        if sum(inMed) < opts.minChans          % keep the minChans least line-dominated rows
            [~, o] = sort(lineFrac, 'ascend');
            inMed(:) = false; inMed(o(1:min(nU, opts.minChans))) = true;
            warning('artifactIndex_vipassana:lineDominated', ...
                '%d of %d usable rows have line fraction > %.2f; the %d least line-dominated rows are used', ...
                sum(lineFrac > opts.lineFracMax), nU, opts.lineFracMax, sum(inMed));
        end
    end

    % ---- 3. log10 + channel median ----
    hfLog  = median(log10(hfPow(inMed, :) + eps), 1)';
    p2pLog = median(log10(p2p(inMed, :) + eps), 1)';

    % ---- 4. robust z, combined ----
    [zH, cH, sH] = robustZ(hfLog);
    [zP, cP, sP] = robustZ(p2pLog);
    art = (zH + zP) / 2;

    % ---- 5. slow baseline ----
    artBase = movmedian(art, opts.baseWin);
    artDev  = art - artBase;

    % ---- 6. evidence ----
    evid = movmedian(min(max(artDev, opts.clipLo), opts.clipHi), opts.smoothWin);

    tSec = ((1:nWin)' - 0.5) * w / fs;
    T = table(tSec, hfLog, p2pLog, art, artBase, artDev, evid);
    T.Properties.Description = 'artifactIndex_vipassana: 1-s EEG activity evidence (30-100 Hz power + 1-100 Hz p2p, channel median, robust z, 10-min baseline)';
    lineFracAll = nan(1, nChanIn); lineFracAll(use) = lineFrac;
    T.Properties.UserData = struct('opts', opts, 'fs', fs, 'winSamples', w, 'chansUsed', use(inMed)', ...
        'chansUsable', use(:)', 'chansLineDropped', use(~inMed)', 'lineFrac', lineFracAll, ...
        'nChanIn', nChanIn, 'hfCenter', cH, 'hfScale', sH, 'p2pCenter', cP, 'p2pScale', sP);
    fprintf(['artifactIndex_vipassana: %d/%d channels in the median (%d usable, %d line-dominated dropped), ' ...
             '%d windows of %d samples; evid > 1 in %.1f%% of seconds\n'], ...
        sum(inMed), nChanIn, nU, sum(~inMed), nWin, w, 100 * mean(evid > 1));
end

% ============================ helpers ============================

function v = bandPow(P, f, band)
% integrated PSD over band (same as batch/probeMontageBV's bp)
    sel = f >= band(1) & f <= band(2);
    v = trapz(f(sel), P(sel));
end

function [z, c, s] = robustZ(x)
% (x - median) / (1.4826 * MAD); std fallback when the MAD is 0
    c = median(x);
    s = 1.4826 * median(abs(x - c));
    if ~(s > 0), s = std(x); end
    if ~(s > 0), s = 1; end
    z = (x - c) / s;
end

function [X, info] = robustAvgRef(X, labels, fs, opts)
%ROBUSTAVGREF  SHARED: robust common-average reference of the scalp EEG rows.
%
%   [X, info] = robustAvgRef(X, labels, fs, opts)
%
%   X       [nChan x nSamp] scalp EEG in ONE common recording reference, the
%           reference electrode included as its own row (e.g. the BrainVision
%           recording reference Cz, inserted by the LoadData script as an
%           all-zero row). Returned re-referenced to the mean of the reference
%           set below (flat stretches excepted, see 1).
%   labels  channel labels parallel to the rows
%   fs      sample rate (Hz)
%   opts    optional struct (defaults): refChan ('Cz', the recording
%           reference row - legitimately all zero, never judged flat), winSec
%           (2, the shared detector's trial length), flatUV (1), flatFrac
%           (0.01), hpHz (1), zMax (5), zMaxWin (20), badWinFrac (0.01),
%           minRef (16)
%
%   Changing from one common reference to another subtracts the same time
%   series from every row, so the recording reference's own row (0 as
%   recorded) comes back as a real channel: Cz_avg = 0 - mean(reference set).
%   Noise common to every row as recorded (e.g. carried by the reference
%   electrode) cancels; noise of one electrode stays in that row and reaches
%   the others at 1/nRef of its amplitude, which is why bad rows are kept out
%   of the mean.
%
%   Steps (after the robust reference of the PREP pipeline, Bigdely-Shamlo et
%   al. 2015, Front Neuroinform 9:16, with a flat-signal guard):
%     1. FLAT: in the recording reference, a row is flat in a winSec window
%        when its peak-to-peak there is below flatUV (a dead / disconnected /
%        railed input reads constant). Windows in which every row except
%        refChan is flat are recording gaps and are not counted. A row flat in
%        more than flatFrac of the other windows leaves the reference set, and
%        in every window where it is flat it is NOT re-referenced (left
%        constant), so the shared detector's flat rule still sees it.
%     2. each row minus its mean, 1-Hz high-passed (4th-order Butterworth,
%        filtfilt) - removes the DC offsets of DC-coupled amplifiers BEFORE
%        any cross-row statistic; provisional reference = the per-sample
%        MEDIAN of the high-passed non-flat rows;
%     3. DEVIATION: robust amplitude of each high-passed row minus the
%        provisional reference (0.7413 x IQR), robust z across rows (median,
%        1.4826 x MAD). A row leaves the reference set when its
%        whole-recording z > zMax (PREP's deviation criterion) or when its
%        z within a winSec window exceeds zMaxWin in more than badWinFrac of
%        its non-flat windows (a guard for EXTREME events only - rails, an
%        electrode that fails for part of the recording; with z > zMax per
%        window instead, eyes-closed alpha at O1 and eye movements at Fp1/Fp2
%        excluded 8-11 of 32 rows, probe 2026-10-21);
%     4. reference = the MEAN of the remaining rows (unfiltered, as recorded),
%        subtracted from every row outside its flat windows (excluded rows
%        too, so all rows share one reference and the shared bad-channel
%        detector judges them as usual).
%   Errors when fewer than minRef rows remain, or on NaN / Inf.
%
%   info: method, labels, refChans, excluded, excludedWhy (per excluded row:
%   'flat' / 'deviation'), flatFrac / badWinFrac (windows with z > zMaxWin)
%   / winZ5Frac (windows with z > zMax, diagnostic) / robustAmpUV / robustZ
%   (per row, parallel to labels), nWin, nGapWin, opts, note.

    if nargin < 4 || isempty(opts), opts = struct(); end
    def = struct('refChan', 'Cz', 'winSec', 2, 'flatUV', 1, 'flatFrac', 0.01, 'hpHz', 1, ...
        'zMax', 5, 'zMaxWin', 20, 'badWinFrac', 0.01, 'minRef', 16);
    fn = fieldnames(def);
    for k = 1:numel(fn)
        if ~isfield(opts, fn{k}), opts.(fn{k}) = def.(fn{k}); end
    end
    labels = cellstr(string(labels(:)'));
    [nC, nS] = size(X);
    assert(numel(labels) == nC, 'robustAvgRef: %d labels for %d rows', numel(labels), nC);
    assert(all(isfinite(X(:))), 'robustAvgRef:nonFinite', 'robustAvgRef: EEG contains NaN / Inf');
    isRef = strcmpi(labels, opts.refChan);

    % windows (the last partial window joins the one before it)
    wl = round(opts.winSec * fs);
    nW = max(1, floor(nS / wl));
    edges = [(0:nW - 1) * wl + 1, nS + 1];

    % 1. flat windows, in the recording reference
    flatW = false(nC, nW);
    for w = 1:nW
        seg = X(:, edges(w):edges(w + 1) - 1);
        flatW(:, w) = (max(seg, [], 2) - min(seg, [], 2)) < opts.flatUV;
    end
    flatW(isRef, :) = false;                       % the recording reference is zero by construction
    gapW = all(flatW(~isRef, :), 1);               % recording gaps: every channel flat
    nJ = max(1, nnz(~gapW));
    flatFrac = sum(flatW(:, ~gapW), 2) / nJ;
    isFlat = flatFrac > opts.flatFrac;

    % 2. high-passed rows (single, one row at a time), provisional median reference
    [b, a] = butter(4, opts.hpHz / (fs / 2), 'high');
    H = zeros(nC, nS, 'single');
    for c = 1:nC
        y = double(X(c, :));
        H(c, :) = single(filtfilt(b, a, y - mean(y)));
    end
    med = median(H(~isFlat, :), 1);

    % 3. deviation: whole recording and per window
    amp = zeros(nC, 1);
    ampW = nan(nC, nW);
    for c = 1:nC
        d = double(H(c, :) - med);
        s = sort(d); n = numel(s);
        amp(c) = 0.7413 * (s(max(1, round(0.75 * n))) - s(max(1, round(0.25 * n))));
        D = reshape(d(1:nW * wl), wl, nW);
        D = sort(D, 1);
        ampW(c, :) = 0.7413 * (D(max(1, round(0.75 * wl)), :) - D(max(1, round(0.25 * wl)), :));
    end
    clear H med d s D
    ok = ~isFlat;
    z = robZ(amp, ok);
    zW = nan(nC, nW);
    for w = 1:nW
        zW(:, w) = robZ(ampW(:, w), ok & ~flatW(:, w));
    end
    usable = ~flatW & ~gapW;
    nUse = max(1, sum(usable, 2));
    badWinFrac = sum(zW > opts.zMaxWin & usable, 2) ./ nUse;
    winZ5Frac = sum(zW > opts.zMax & usable, 2) ./ nUse;      % diagnostic only
    isDev = ok & (badWinFrac > opts.badWinFrac | z > opts.zMax);

    out = isFlat | isDev;
    refSet = find(~out);
    assert(numel(refSet) >= opts.minRef, 'robustAvgRef:fewChannels', ...
        'robustAvgRef: only %d of %d rows left for the reference (flat: %s; deviation: %s)', ...
        numel(refSet), nC, strjoin(labels(isFlat), ' '), strjoin(labels(isDev), ' '));

    % 4. mean of the reference set, subtracted from every row outside its flat windows
    ref = mean(double(X(refSet, :)), 1);
    for c = 1:nC
        x = double(X(c, :)) - ref;
        for w = find(flatW(c, :) & ~gapW)
            ix = edges(w):edges(w + 1) - 1;
            x(ix) = X(c, ix);                      % keep the flat stretch flat
        end
        X(c, :) = x;                               % assignment keeps X's class
    end

    why = repmat({''}, 1, nC);
    why(isFlat) = {'flat'}; why(isDev) = {'deviation'};
    info = struct();
    info.method = 'robust common average (PREP-style, windowed deviation, flat guard)';
    info.labels = labels;
    info.refChans = labels(refSet);
    info.excluded = labels(out);
    info.excludedWhy = why(out);
    info.flatFrac = flatFrac';
    info.badWinFrac = badWinFrac';
    info.winZ5Frac = winZ5Frac';
    info.robustAmpUV = amp';
    info.robustZ = z';
    info.nWin = nW;
    info.nGapWin = nnz(gapW);
    info.opts = opts;
    exclStr = 'none';
    if any(out), exclStr = strjoin(strcat(labels(out), ' (', why(out), ')'), ', '); end
    info.note = sprintf(['robustAvgRef: every row re-referenced to the mean of %d of %d rows (flat windows of a row ' ...
        'left as recorded); excluded %s'], numel(refSet), nC, exclStr);
end

function z = robZ(v, use)
% robust z-score of v against the rows in use (median, 1.4826 x MAD)
    z = nan(size(v));
    if nnz(use) < 3, return; end
    m = median(v(use));
    s = 1.4826 * median(abs(v(use) - m));
    z = (v - m) / max(s, eps);
end

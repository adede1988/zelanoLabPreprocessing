function A = alignLog_vipassana(L, rsp, fs, opts)
%ALIGNLOG_VIPASSANA  Map the SniffLogic log clock onto the BrainVision recording.
%
%   A = alignLog_vipassana(L, rsp, fs)
%   A = alignLog_vipassana(L, rsp, fs, opts)
%
%   L    : struct from parseLog_vipassana (.t, .p = log pressure, Pa)
%   rsp  : the recording's respiration channel (1 x N, at fs, AS RECORDED -
%          unflipped). In the vipassana v2 rig the BrainVision 'Resp' input
%          is the analog output of the same pressure sensor SniffLogic logs,
%          so the two traces are one signal up to gain, offset, polarity,
%          acquisition noise and the two clocks.
%   opts : optional struct (defaults below)
%
%   Method
%     0. both traces are low-passed at their native rates BEFORE any
%        resampling (4th-order Butterworth opts.lpHz = 4 Hz, zero-phase): the
%        recording's 60/120/180-Hz pickup would otherwise alias onto the
%        coarse 20-Hz grid as a slow wander (60 Hz is a multiple of 20 Hz);
%        the log is first put on a uniform grid at its median rate;
%     1. coarse: both traces further low-passed (< 1 Hz) on a 20-Hz grid,
%        full normalised cross-correlation -> lag0 (raw s = log s + lag0;
%        the log grid's origin, the first logged sample, is accounted for)
%        and the sign of the peak;
%     2. fine: opts.winSec (120 s) windows every opts.stepSec (60 s) along
%        the log; per window the 4-Hz log pressure on a 100-Hz grid is
%        correlated with the recording's 4-Hz trace at lags lag0 +-
%        opts.searchSec (1 s) in 10-ms steps, the peak refined by a parabola
%        (sub-10-ms). A window whose peak sits on the EDGE of the search
%        range is not a measurement (the true lag lies outside it) and is
%        excluded; more than opts.maxEdgeFrac (10 %) of such windows is an
%        error (the coarse lag is wrong);
%     3. map: a robust line through the windows whose |r| >= opts.rMinWin
%        (0.8): Theil-Sen start (median of pairwise slopes), then least
%        squares, dropping windows more than opts.outlierMs (20 ms) off the
%        line, iterated until the set no longer changes. raw seconds (0 =
%        first raw sample) of log time tLog = c0 + (1 + c1) tLog; c1 is the
%        clock-rate difference (~12 ppm in the first sessions, i.e. ~45 ms
%        over an hour).
%   Strict: errors when the coarse peak is ambiguous (a second peak >= 90 %
%   of the first, > 5 s away), when fewer than max(3, opts.minWinFrac (50 %)
%   x the windows) remain in the final fit, when they span less than
%   opts.minSpanFrac (50 %) of the windows' range, when their median |r| <
%   opts.rMinMedian (0.9), or when the fit residual rms > opts.maxResidMs
%   (10 ms).
%
%   Returns A with
%     .lag0Sec, .coarsePeak, .coarseRunnerUp   coarse stage
%     .sign        sign of the correlation (+1: the recording's channel has
%                  the log's polarity; the log is inhale-POSITIVE, so .sign is
%                  the rspFlip that makes the recording's channel inhale-up)
%     .intercept (c0, s), .slope (c1), .driftPPM (= 1e6 c1)
%     .win         table tLogMid, lagSec, r, edge, used (every window)
%     .nWin, .nEdge, .nUsed, .medianR, .residRmsMs, .residMaxMs
%     .gainPerPa   least-squares gain of the recording's low-passed channel
%                  per Pa of log pressure (sign included), over the used
%                  windows
%     .logStartRawSec, .logEndRawSec   the log's first / last sample on the
%                  raw timeline (s; the log may start before / end after the
%                  recording)
%     .opts

    if nargin < 4 || isempty(opts), opts = struct(); end
    opts = fillDefaults(opts, struct('coarseFs', 20, 'coarseLpHz', 1, 'fineFs', 100, 'lpHz', 4, ...
        'winSec', 120, 'stepSec', 60, 'searchSec', 1, 'rMinWin', 0.8, 'outlierMs', 20, 'maxEdgeFrac', 0.1, ...
        'minWinFrac', 0.5, 'minSpanFrac', 0.5, 'rMinMedian', 0.9, 'maxResidMs', 10));

    rsp = double(rsp(:));
    N = numel(rsp);
    tRaw = (0:N - 1)' / fs;
    tL = L.t(:); pL = L.p(:);

    % ---- 0. low-pass both at their native rates (anti-alias) ----
    [b, a] = butter(4, opts.lpHz / (fs / 2), 'low');
    rF = filtfilt(b, a, rsp - median(rsp));
    fsL = round(1 / median(diff(tL)));
    tLu = (tL(1):1 / fsL:tL(end))';
    pLu = interp1(tL, pL, tLu, 'linear');
    [b, a] = butter(4, opts.lpHz / (fsL / 2), 'low');
    pLF = filtfilt(b, a, pLu - mean(pLu));

    % ---- 1. coarse ----
    FS = opts.coarseFs;
    gL = (tLu(1):1 / FS:tLu(end))';
    xL = interp1(tLu, pLF, gL, 'linear');
    xL = lowpass(xL - mean(xL), opts.coarseLpHz, FS);
    gR = (0:1 / FS:tRaw(end))';
    xR = interp1(tRaw, rF, gR, 'linear');
    xR = lowpass(xR - mean(xR), opts.coarseLpHz, FS);
    n = max(numel(xR), numel(xL));
    [xc, lags] = xcorr([xR; zeros(n - numel(xR), 1)], [xL; zeros(n - numel(xL), 1)], 'normalized');
    [pk, ip] = max(abs(xc));
    A = struct();
    % xR(i + m) ~ xL(i): raw time (i + m - 1)/FS, log time gL(1) + (i - 1)/FS
    A.lag0Sec = lags(ip) / FS - gL(1);
    A.sign = sign(xc(ip));
    far = abs(lags - lags(ip)) > 5 * FS;
    A.coarsePeak = pk;
    A.coarseRunnerUp = max(abs(xc(far)));
    assert(A.coarseRunnerUp < 0.9 * A.coarsePeak, 'alignLog_vipassana:ambiguous', ...
        'coarse lag ambiguous: peak %.3f at %.1f s, runner-up %.3f', pk, A.lag0Sec, A.coarseRunnerUp);

    % ---- 2. fine ----
    FSf = opts.fineFs;
    nS = round(opts.searchSec * FSf);
    t0s = (tLu(1) + 1):opts.stepSec:(tLu(end) - opts.winSec - 1);
    W = nan(numel(t0s), 4);              % tLogMid, lag, r, edge
    for k = 1:numel(t0s)
        tg = (t0s(k):1 / FSf:t0s(k) + opts.winSec)';
        tr0 = tg(1) + A.lag0Sec - opts.searchSec;
        tr1 = tg(end) + A.lag0Sec + opts.searchSec;
        if tr0 < 0 || tr1 > tRaw(end), continue; end
        x = interp1(tLu, pLF, tg, 'linear'); x = x - mean(x);
        yG = interp1(tRaw, rF, (tr0:1 / FSf:tr1 + 0.5 / FSf)', 'linear');
        m = numel(x);
        r = nan(2 * nS + 1, 1);
        for j = 1:2 * nS + 1
            y = yG(j:j + m - 1); y = y - mean(y);
            r(j) = (x' * y) / sqrt((x' * x) * (y' * y));
        end
        [~, jb] = max(A.sign * r);
        edge = jb == 1 || jb == numel(r);
        d = 0;
        if ~edge
            y0 = A.sign * r(jb - 1); y1 = A.sign * r(jb); y2 = A.sign * r(jb + 1);
            den = y0 - 2 * y1 + y2;
            if den < 0, d = 0.5 * (y0 - y2) / den; end
        end
        W(k, :) = [t0s(k) + opts.winSec / 2, A.lag0Sec + (jb - 1 - nS + d) / FSf, A.sign * r(jb), edge];
    end
    W = W(isfinite(W(:, 1)) & isfinite(W(:, 3)), :);
    A.nWin = size(W, 1);
    edgeW = W(:, 4) == 1;
    A.nEdge = sum(edgeW);
    assert(A.nWin >= 3, 'alignLog_vipassana:fewWindows', 'only %d alignment windows inside the recording', A.nWin);
    assert(A.nEdge <= opts.maxEdgeFrac * A.nWin, 'alignLog_vipassana:edgePeaks', ...
        ['%d of %d windows peak at the edge of the +-%g-s search around the coarse lag %.2f s - the coarse ' ...
         'lag is wrong'], A.nEdge, A.nWin, opts.searchSec, A.lag0Sec);
    cand = W(:, 3) >= opts.rMinWin & ~edgeW;

    % ---- 3. robust clock map ----
    used = cand;
    pf = theilSen(W(used, 1), W(used, 2));
    for it = 1:20
        res = W(:, 2) - polyval(pf, W(:, 1));
        newUsed = cand & abs(res) <= opts.outlierMs / 1000;
        assert(sum(newUsed) >= 3, 'alignLog_vipassana:poorMatch', 'fewer than 3 windows on the clock line');
        pf = polyfit(W(newUsed, 1), W(newUsed, 2), 1);
        if isequal(newUsed, used), break; end
        used = newUsed;
    end
    res = W(used, 2) - polyval(pf, W(used, 1));
    A.slope = pf(1);
    A.intercept = pf(2);
    A.driftPPM = 1e6 * pf(1);
    A.win = table(W(:, 1), W(:, 2), W(:, 3), edgeW, used, 'VariableNames', {'tLogMid', 'lagSec', 'r', 'edge', 'used'});
    A.nUsed = sum(used);
    A.medianR = median(W(~edgeW, 3));
    A.residRmsMs = 1e3 * sqrt(mean(res .^ 2));
    A.residMaxMs = 1e3 * max(abs(res));
    span = (max(W(used, 1)) - min(W(used, 1))) / max(eps, max(W(:, 1)) - min(W(:, 1)));
    assert(A.nUsed >= max(3, opts.minWinFrac * A.nWin), 'alignLog_vipassana:poorMatch', ...
        'only %d of %d windows on the clock line (r >= %.2f, within %g ms)', A.nUsed, A.nWin, opts.rMinWin, opts.outlierMs);
    assert(span >= opts.minSpanFrac, 'alignLog_vipassana:span', ...
        'the windows on the clock line span only %.0f %% of the overlap', 100 * span);
    assert(A.medianR >= opts.rMinMedian, 'alignLog_vipassana:poorMatch', ...
        'median window r %.3f < %.2f', A.medianR, opts.rMinMedian);
    assert(A.residRmsMs <= opts.maxResidMs, 'alignLog_vipassana:residual', ...
        'linear clock map residual %.1f ms rms > %.1f ms', A.residRmsMs, opts.maxResidMs);

    % ---- gain (recording units per Pa) over the used windows ----
    rawSec = A.intercept + (1 + A.slope) * tLu;
    inUse = false(size(tLu));
    for k = find(used)'
        inUse = inUse | abs(tLu - W(k, 1)) <= opts.winSec / 2;
    end
    inUse = inUse & rawSec >= 0 & rawSec <= tRaw(end);
    yl = interp1(tRaw, rF, rawSec(inUse), 'linear');
    g = polyfit(pLF(inUse) - mean(pLF(inUse)), yl - mean(yl), 1);
    A.gainPerPa = g(1);
    A.logStartRawSec = A.intercept + (1 + A.slope) * tL(1);
    A.logEndRawSec = A.intercept + (1 + A.slope) * tL(end);
    A.opts = opts;

    fprintf(['alignLog_vipassana: raw s = %.3f + (1 %+.2e) log s (drift %.1f ppm); sign %+d; %d/%d windows used ' ...
        '(%d at the search edge), median r %.3f, residual %.2f ms rms (max %.2f); log covers raw %.1f..%.1f s\n'], ...
        A.intercept, A.slope, A.driftPPM, A.sign, A.nUsed, A.nWin, A.nEdge, A.medianR, A.residRmsMs, A.residMaxMs, ...
        A.logStartRawSec, A.logEndRawSec);
end

function p = theilSen(x, y)
%THEILSEN  [slope intercept] from the median pairwise slope and the median intercept.
    n = numel(x);
    assert(n >= 2, 'alignLog_vipassana:poorMatch', 'fewer than 2 usable alignment windows');
    [i, j] = find(triu(true(n), 1));
    s = (y(j) - y(i)) ./ (x(j) - x(i));
    sl = median(s(isfinite(s)));
    p = [sl, median(y - sl * x)];
end

function s = fillDefaults(s, d)
    f = fieldnames(d);
    for k = 1:numel(f)
        if ~isfield(s, f{k}) || isempty(s.(f{k})), s.(f{k}) = d.(f{k}); end
    end
end

function A = alignLogToRaw(log, rsp, fsRaw, sessID, figDir)
%ALIGNLOGTORAW  Align the SniffLogic log clock to the raw recording (Task 8 D11 step 4).
%
%   A = alignLogToRaw(log, rsp, fsRaw, sessID, figDir)
%
%   log   : struct from parse_sniffLogicLog (.t seconds, .p pressure_pa)
%   rsp   : raw respiration trace (1 x N) at fsRaw, UNFLIPPED (CSC31 as recorded)
%   fsRaw : raw sampling rate
%
%   Both signals are low-passed (<1 Hz) and resampled to a common 20 Hz grid;
%   normalized cross-correlation gives the coarse lag; a sliding-window lag
%   estimate checks clock drift (linear map applied when drift exceeds one
%   sample at 500 Hz over the recording). Polarity is decided by the sign of
%   the correlation peak: SniffLogic nasal pressure is NEGATIVE during
%   inhalation, so corr>0 means the raw channel is also inhale-negative
%   (rspFlip = -1 makes inhale positive) and corr<0 means inhale-positive
%   (rspFlip = +1).
%
%   Returns A with:
%     .lagSec      log time t maps to raw time t + lagSec (+ drift term)
%     .r           peak normalized correlation (|r|)
%     .corrSign    +1/-1 sign of the peak
%     .rspFlip     inferred flip so that inhale is positive
%     .driftPPM    linear drift (raw seconds per log second - 1) * 1e6
%     .useDrift    whether the linear term is applied
%     .logToRaw500 @(tLog) sample index at 500 Hz in the raw recording
%   Fails loudly when |r| < 0.6 or a second peak reaches 90% of the max
%   at least 5 s away (ambiguity).

    FS = 20;

    % uniform-grid, low-passed copies
    tGrid = (log.t(1):1/FS:log.t(end))';
    pL = interp1(log.t, fillmissing(log.p, 'linear'), tGrid, 'linear');
    pL = lowpass(pL - mean(pL), 1, FS);

    tRawGrid = (0:1/FS:(numel(rsp)-1)/fsRaw)';
    pR = interp1((0:numel(rsp)-1)'/fsRaw, double(rsp(:)), tRawGrid, 'linear');
    pR = fillmissing(pR, 'linear', 'EndValues', 'nearest');   % before the mean!
    pR = lowpass(pR - mean(pR), 1, FS);

    [xc, lags] = xcorr(pR, pL, 'normalized');
    [pk, pi] = max(abs(xc));
    lagSamp = lags(pi);
    corrSign = sign(xc(pi));

    % ambiguity: another comparable peak far from the main one
    far = abs(lags - lagSamp) > 5 * FS;
    pk2 = max(abs(xc(far)));
    fprintf('%s: peak |r| = %.3f (sign %+d) at lag %.2f s; runner-up %.3f\n', ...
        sessID, pk, corrSign, lagSamp / FS, pk2);
    assert(pk >= 0.6, 'alignLogToRaw:weakPeak', ...
        '%s: alignment peak |r|=%.3f < 0.6 - stop and inspect', sessID, pk);
    assert(pk2 < 0.9 * pk, 'alignLogToRaw:ambiguous', ...
        '%s: second correlation peak at %.0f%% of max - ambiguous alignment', ...
        sessID, 100 * pk2 / pk);

    lagSec = lagSamp / FS;
    t0Log = tGrid(1);

    % ---- refinement: re-correlate at 100 Hz within +/-3 s of the coarse lag ----
    FSr = 100;
    tGr = (log.t(1):1/FSr:log.t(end))';
    pLr = lowpass(interp1(log.t, log.p, tGr, 'linear') - mean(log.p), 2, FSr);
    tRr = (0:1/FSr:(numel(rsp)-1)/fsRaw)';
    pRr = interp1((0:numel(rsp)-1)'/fsRaw, double(rsp(:)), tRr, 'linear');
    pRr = fillmissing(pRr, 'linear', 'EndValues', 'nearest');
    pRr = lowpass(pRr - mean(pRr), 2, FSr);
    [xcr, lr] = xcorr(pRr, pLr, 'normalized');
    inWin = abs(lr / FSr - lagSec) <= 3;
    [~, ri] = max(abs(xcr(:)) .* inWin(:));
    lagSec = lr(ri) / FSr;
    fprintf('%s: refined lag %.3f s (100 Hz)\n', sessID, lagSec);

    % ---- drift: lag re-estimated in 120-s sliding windows ----
    winSec = 120; hopSec = 60;
    centers = []; wlags = [];
    for w0 = tGrid(1):hopSec:tGrid(end) - winSec
        wi = tGrid >= w0 & tGrid < w0 + winSec;
        seg = pL(wi);
        rawT0 = (w0 - t0Log) + lagSec;               % expected raw start (s)
        ri0 = round((rawT0 - 10) * FS); ri1 = round((rawT0 + winSec + 10) * FS);
        if ri0 < 1 || ri1 > numel(pR), continue; end
        [wxc, wl] = xcorr(pR(ri0:ri1), seg, 'normalized');
        [wpk, wpi] = max(abs(wxc));
        if wpk < 0.5, continue; end
        centers(end+1) = w0 + winSec/2;              %#ok<AGROW>
        wlags(end+1) = (ri0 - 1) / FS + wl(wpi) / FS - (w0 - t0Log); %#ok<AGROW>
    end
    driftPPM = 0; useDrift = false; cf = [0 lagSec];
    if numel(centers) >= 5
        cf = polyfit(centers - t0Log, wlags, 1);   % lag(tLog) = cf(2)+cf(1)*(tLog-t0Log)
        driftTotal = cf(1) * (tGrid(end) - tGrid(1));
        driftPPM = cf(1) * 1e6;
        useDrift = abs(driftTotal) > 1/500;
        fprintf('%s: drift %.1f ppm (%.3f s over recording) -> linear map %s\n', ...
            sessID, driftPPM, driftTotal, string(useDrift));
    end

    A = struct();
    A.lagSec = lagSec;
    A.r = pk;
    A.corrSign = corrSign;
    A.rspFlip = -corrSign;    % pressure inhale-negative convention (see header)
    A.driftPPM = driftPPM;
    A.useDrift = useDrift;
    c1 = centers; w1 = wlags; cf1 = cf; t0 = t0Log;
    if useDrift
        A.logToRaw500 = @(tLog) round((cf1(2) + (tLog - t0) + cf1(1) .* (tLog - t0)) * 500);
    else
        A.logToRaw500 = @(tLog) round((lagSec + (tLog - t0)) * 500);
    end

    % ---- alignment figure ----
    fig = figure('Visible', 'off', 'Position', [30 30 1500 900]);
    subplot(3, 1, 1);
    plot(lags / FS / 60, xc, 'k');
    xline(lagSamp / FS / 60, 'r');
    title(sprintf('%s log-raw xcorr: |r|=%.2f sign %+d lag %.2f s', ...
        strrep(sessID, '_', '\_'), pk, corrSign, lagSamp / FS));
    xlabel('lag (min)');
    subplot(3, 1, 2); hold on
    w = 1:min(numel(tGrid), 120 * FS);
    rawIdx = round((lagSec + (tGrid(w) - t0Log)) * FS);
    ok = rawIdx >= 1 & rawIdx <= numel(pR);
    plot(tGrid(w(ok)), zscore(pL(w(ok))), 'b');
    plot(tGrid(w(ok)), zscore(pR(rawIdx(ok))) * corrSign, 'r');
    title('first 2 min aligned (blue=log, red=raw, sign-matched)');
    subplot(3, 1, 3);
    if ~isempty(c1)
        plot(c1 / 60, w1 - lagSec, 'ko-');
        title(sprintf('per-window lag deviation (drift %.1f ppm, applied=%s)', driftPPM, string(useDrift)));
        xlabel('log time (min)'); ylabel('s');
    end
    if ~isfolder(figDir), mkdir(figDir); end
    saveas(fig, fullfile(figDir, [sessID '_logAlign.png']));
    close(fig);
end

function plotMarkedBlocks_vipassana(outDat, rspDat)
%PLOTMARKEDBLOCKS_VIPASSANA  QC figures for a vipassana v2 (marked) session.
%
%   plotMarkedBlocks_vipassana(outDat, rspDat)
%
%   Saves to outDat.figs:
%   blocks_marked.jpg - shared minute axis:
%     1. the photodiode (outDat.photodiode.trace, 10 Hz, unfiltered) with the
%        periods shaded and labelled (outDat.blocks; task blocks coloured by
%        kind, gaps orange) and, when the session has a SniffLogic log, the
%        log's blocks mapped onto the recording as red bars;
%     2. the respiration trace (rspIDX/rspFlip applied; omitted when rspDat
%        is empty) with the paced-breathing target (targTrace row, scaled to
%        the trace's range) in green;
%     3. breath rate per breath (60 / length) and the target rate
%        (behDat.targetCPM) when known;
%     4. the EEG activity evidence (outDat.artifactIndex.evid; QC only - the
%        v2 blocks do not use it).
%   sniffLogicAlign.jpg (sessions with a log) - the clock map (window lags
%     minus the fitted line, ms), the window correlations, the photodiode-
%     minus-log edge offsets per block, and a 30-s overlay of rsp1 (scaled by
%     the fitted gain) on the aligned log pressure (rspSniffLogic) in the
%     middle of the longest task block.
%
%   Inputs: outDat after blocks / breaths / behDat (fields blocks, fs, figs,
%   sessID, photodiode, sniffLogic, artifactIndex, bmObj, behDat, labels,
%   data); rspDat = 1 x N respiration (flip applied) or [].

    B  = outDat.blocks;
    fs = outDat.fs;
    N  = size(outDat.data, 2);
    durMin = N / fs / 60;
    x0 = (B.startSample - 1) / fs / 60; x1 = B.endSample / fs / 60;
    hasRsp = nargin >= 2 && ~isempty(rspDat);
    hasLog = isfield(outDat, 'sniffLogic') && ~isempty(outDat.sniffLogic);
    hasRate = isfield(outDat, 'bmObj') && size(outDat.bmObj, 1) > 0;
    if ~exist(outDat.figs, 'dir'), mkdir(outDat.figs); end

    nRow = 2 + hasRsp + hasRate;
    fig = figure('Visible', 'off', 'Position', [40 40 1900 280 * nRow + 120]);
    tl = tiledlayout(fig, nRow, 1, 'TileSpacing', 'compact', 'Padding', 'compact');
    ax = gobjects(nRow, 1);

    % ---- 1. photodiode + periods ----
    r = 1; ax(r) = nexttile(tl); hold(ax(r), 'on')
    PD = outDat.photodiode;
    tp = (0:numel(PD.trace) - 1) / PD.traceFs / 60;
    y = (PD.trace - PD.lo) / max(PD.hi - PD.lo, eps);
    shade(ax(r), B, x0, x1, [-0.2 1.75]);
    plot(ax(r), tp, y, 'k');
    for b = 1:height(B)
        if B.kind(b) == "task" || B.durationSec(b) > 60
            text(ax(r), (x0(b) + x1(b)) / 2, 1.72, sprintf('%s\n%.2f min', B.label(b), B.durationSec(b) / 60), ...
                'HorizontalAlignment', 'center', 'VerticalAlignment', 'top', 'FontSize', 7, 'Interpreter', 'none');
        end
    end
    if hasLog
        LB = outDat.sniffLogic.log.blocks;
        for k = 1:height(LB)
            e = LB.rawEndSec(k); if ~isfinite(e), e = LB.rawStartSec(k); end
            plot(ax(r), [LB.rawStartSec(k) e] / 60, [1.2 1.2], 'r-', 'LineWidth', 3);
        end
    end
    ylim(ax(r), [-0.2 1.75]); ylabel(ax(r), 'photodiode (0 = low, 1 = high)'); grid(ax(r), 'on')
    srcs = unique(B.source(B.kind == "task"))';
    title(ax(r), sprintf('%s  v2 blocks from %s%s', outDat.sessID, strjoin(srcs, ' / '), ...
        ternary(hasLog, '  (red = SniffLogic blocks mapped onto the recording)', '')), 'Interpreter', 'none');

    % ---- 2. respiration + target ----
    if hasRsp
        r = r + 1; ax(r) = nexttile(tl); hold(ax(r), 'on')
        dec = max(1, round(fs / 10));
        tt = (0:dec:numel(rspDat) - 1) / fs / 60;
        yR = rspDat(1:dec:end);
        yl = [prctile(yR, 0.5), prctile(yR, 99.5)]; if ~(yl(2) > yl(1)), yl = yl + [-1 1]; end
        shade(ax(r), B, x0, x1, yl);
        % the target goes UNDER the respiration (drawn first, light) so the
        % paced breaths stay visible
        tgRow = find(strcmp(cellstr(string(outDat.labels)), 'targTrace'), 1);
        if ~isempty(tgRow)
            tg = outDat.data(tgRow, 1:dec:end);
            on = tg ~= 0;
            if any(on)
                pr = prctile(yR(on), [5 95]); pt = prctile(tg(on), [5 95]);
                tgS = (tg - mean(pt)) / max(diff(pt), eps) * diff(pr) + mean(pr);
                tgS(~on) = NaN;
                plot(ax(r), tt, tgS, 'Color', [0.55 0.85 0.55], 'LineWidth', 2);
            end
        end
        plot(ax(r), tt, yR, 'k');
        ylim(ax(r), yl); ylabel(ax(r), 'respiration (rspFlip applied)'); grid(ax(r), 'on')
    end

    % ---- 3. breath rate ----
    if hasRate
        r = r + 1; ax(r) = nexttile(tl); hold(ax(r), 'on')
        bm = outDat.bmObj;
        shade(ax(r), B, x0, x1, [0 40]);
        plot(ax(r), bm(:, 2) / 60, 60 ./ bm(:, 7), '.', 'Color', [0.2 0.2 0.2], 'MarkerSize', 5);
        if ismember('targetCPM', outDat.behDat.Properties.VariableNames)
            plot(ax(r), (outDat.behDat.sniffOnset - 1) / fs / 60, outDat.behDat.targetCPM, '.', ...
                'Color', [0 0.6 0], 'MarkerSize', 6);
        end
        ylim(ax(r), [0 40]); ylabel(ax(r), 'breaths / min (green = target)'); grid(ax(r), 'on')
    end

    % ---- 4. activity evidence ----
    r = r + 1; ax(r) = nexttile(tl); hold(ax(r), 'on')
    A = outDat.artifactIndex;
    yl = [-1.2, min(4.6, max(1.5, max(A.evid) + 0.8))];
    shade(ax(r), B, x0, x1, yl);
    plot(ax(r), A.tSec / 60, A.evid, 'k');
    ylim(ax(r), yl); ylabel(ax(r), 'EEG activity evidence'); grid(ax(r), 'on')
    xlabel(ax(r), 'min');
    linkaxes(ax, 'x'); xlim(ax(1), [0 durMin]);
    saveas(fig, fullfile(outDat.figs, 'blocks_marked.jpg'));
    close(fig);

    if ~hasLog, return; end

    % ================= alignment figure =================
    G = outDat.sniffLogic.align;
    fig = figure('Visible', 'off', 'Position', [40 40 1800 1000]);
    tl = tiledlayout(fig, 3, 2, 'TileSpacing', 'compact', 'Padding', 'compact');
    W = G.win;
    ax1 = nexttile(tl); hold(ax1, 'on')
    fitLag = G.intercept + G.slope * W.tLogMid;
    plot(ax1, W.tLogMid / 60, 1e3 * (W.lagSec - fitLag), 'o', 'Color', [0.6 0.6 0.6]);
    plot(ax1, W.tLogMid(W.used) / 60, 1e3 * (W.lagSec(W.used) - fitLag(W.used)), 'ko', 'MarkerFaceColor', 'k');
    yline(ax1, 0, 'r');
    ylim(ax1, [-25 25]); grid(ax1, 'on'); xlabel(ax1, 'log time (min)'); ylabel(ax1, 'window lag - fit (ms)');
    title(ax1, sprintf('clock map: raw = %.3f s + (1 %+.1e) log; drift %.1f ppm; residual %.2f ms rms', ...
        G.intercept, G.slope, G.driftPPM, G.residRmsMs));
    ax2 = nexttile(tl); hold(ax2, 'on')
    plot(ax2, W.tLogMid / 60, W.r, 'k.-'); yline(ax2, G.opts.rMinWin, 'r--');
    ylim(ax2, [min(0, min(W.r)) 1.02]); grid(ax2, 'on'); xlabel(ax2, 'log time (min)'); ylabel(ax2, 'window r');
    title(ax2, sprintf('rsp1 vs log pressure: sign %+d, median r %.3f, %d/%d windows used', G.sign, G.medianR, G.nUsed, G.nWin));
    ax3 = nexttile(tl, [1 2]); hold(ax3, 'on')
    T = B(B.kind == "task", :);
    bar(ax3, categorical(T.label, T.label), 1e3 * [T.pdMinusLogStartSec, T.pdMinusLogEndSec]);
    legend(ax3, {'onset: photodiode - log', 'offset: photodiode - log'}, 'Location', 'northwest');
    ylabel(ax3, 'ms'); grid(ax3, 'on'); title(ax3, 'photodiode edges vs SniffLogic block events mapped onto the recording');
    ax4 = nexttile(tl, [1 2]); hold(ax4, 'on')
    [~, lb] = max(T.durationSec);
    mid = round((T.startSample(lb) + T.endSample(lb)) / 2);
    w = max(1, mid - 15 * fs):min(N, mid + 15 * fs);
    isR = find(contains(cellstr(string(outDat.labels)), 'rsp'));
    r1 = outDat.data(isR(1), w); r1 = r1 - mean(r1);
    rL = outDat.data(strcmp(cellstr(string(outDat.labels)), 'rspSniffLogic'), w); rL = rL - mean(rL);
    plot(ax4, (w - 1) / fs, r1 / G.gainPerPa, 'b', 'LineWidth', 1);
    plot(ax4, (w - 1) / fs, rL, 'r--', 'LineWidth', 1);
    legend(ax4, {'rsp1 (BrainVision Resp, 5-Hz low-pass) / fitted gain', 'rspSniffLogic (aligned log pressure, Pa)'});
    xlabel(ax4, 'recording time (s)'); ylabel(ax4, 'Pa (demeaned)'); grid(ax4, 'on');
    title(ax4, sprintf('30 s in the middle of %s', T.label(lb)), 'Interpreter', 'none');
    title(tl, [outDat.sessID ' SniffLogic log alignment'], 'Interpreter', 'none');
    saveas(fig, fullfile(outDat.figs, 'sniffLogicAlign.jpg'));
    close(fig);
end

function shade(ax, B, x0, x1, yl)
    for b = 1:height(B)
        lab = char(B.label(b));
        if B.kind(b) ~= "task", c = [0.95 0.60 0.20];
        elseif startsWith(lab, 'paced'), c = [0.30 0.75 0.35];
        elseif startsWith(lab, 'audiobook'), c = [0.60 0.60 0.80];
        else, c = [0.30 0.55 0.90];
        end
        patch(ax, [x0(b) x1(b) x1(b) x0(b)], [yl(1) yl(1) yl(2) yl(2)], c, 'FaceAlpha', 0.15, 'EdgeColor', 'none');
    end
end

function out = ternary(c, a, b)
    if c, out = a; else, out = b; end
end

function plotSweepTTL(rsp, fs, TTL, logTrace, info, sessID, figDir)
%PLOTSWEEPTTL  QC figure of a respiratorySweep event table (<sessID>_sweepTTL.png).
%
%   plotSweepTTL(rsp, fs, TTL, logTrace, info, sessID, figDir)
%
%   rsp       raw respiration (1 x N) at fs, polarity applied (rsp1 .* info.rspFlip)
%   TTL, logTrace, info   the outputs of buildSweepTTL (= curDat.TTL / .logTrace /
%             .TTLinfo of the raw file, so the figure can be redrawn from a raw file)
%
%   Top: the whole recording (robust z, 10 Hz) with the blocks shaded - blue
%   audiobook, orange sweep (darker = deeper), green focused breathing.
%   Middle: 60-s zooms on four block edges with the raw respiration (black), the
%   aligned SniffLogic pressure (red) and the target trace (blue dashed), all
%   z-scored: the red and black traces must lie on top of each other.
%   Bottom: alignment numbers, the note-time checks and the stopwatch blocks.

    if ~isfolder(figDir), mkdir(figDir); end
    rsp = double(rsp(:)');
    fig = figure('Visible', 'off', 'Position', [20 20 1900 1200], 'Color', 'w');

    % ---------------- whole recording ----------------
    dec = max(1, round(fs / 10));
    r10 = rsp(1:dec:end);
    r10 = (r10 - median(r10)) / (1.4826 * mad(r10, 1) + eps);
    t10 = (0:numel(r10) - 1) * dec / fs / 60;
    ax1 = axes(fig, 'Position', [0.05 0.62 0.92 0.30]); hold(ax1, 'on');
    yl = [-6 9];
    for b = 1:height(TTL)
        x0 = TTL.startSec(b) / 60; x1 = TTL.endSec(b) / 60;
        switch TTL.blockType(b)
            case "sweep"
                c = [0.95 0.55 0.15] * (1.15 - 0.6 * (TTL.depth(b) - 0.85) / 0.30);   % darker = deeper
                c = min(max(c, 0), 1);
                txt = {sprintf('b%02d', TTL.blockIdx(b)), sprintf('%g', TTL.cpm(b)), sprintf('%.2f', TTL.depth(b))};
            case "audiobook"
                c = [0.30 0.50 0.90];
                txt = {'AB', char(TTL.phase(b)), regexprep(char(TTL.label(b)), '^.*_(post|pre)', '')};
            otherwise
                c = [0.20 0.65 0.30];
                txt = {'FB', char(TTL.phase(b)), regexprep(char(TTL.label(b)), '^.*_(post|pre)', '')};
        end
        patch(ax1, [x0 x1 x1 x0], [yl(1) yl(1) yl(2) yl(2)], c, 'FaceAlpha', 0.25, 'EdgeColor', 'none');
        text(ax1, (x0 + x1) / 2, yl(2) - 0.2, txt, 'HorizontalAlignment', 'center', ...
             'VerticalAlignment', 'top', 'FontSize', 6.5, 'Interpreter', 'none');
    end
    plot(ax1, t10, r10, 'k', 'LineWidth', 0.3);
    ylim(ax1, yl); xlim(ax1, [0 t10(end)]); grid(ax1, 'on');
    xlabel(ax1, 'Atlas recording time (min)'); ylabel(ax1, 'rsp1, robust z');
    title(ax1, {sprintf('%s  respiratorySweep event table (raw-file curDat.TTL)', sessID), ...
        ['blue = audiobook (AB), orange = sweep block (pace /min, depth; darker = deeper), green = focused ' ...
         'breathing (FB); post-sweep blocks = stopwatch times from the session notes, 6 min each']}, ...
        'Interpreter', 'none', 'FontSize', 10);

    % ---------------- zooms ----------------
    zoomKeys = {'audiobook_pre', 'Sweep_b01', 'Sweep_b18', 'focusedBreathing'};
    zoomEdge = {'start', 'start', 'end', 'start'};
    tP = (0:numel(logTrace.pressure) - 1)' / logTrace.fs;
    for z = 1:4
        ax = axes(fig, 'Position', [0.05 + (z - 1) * 0.24, 0.30, 0.205, 0.22]); hold(ax, 'on');
        m = find(startsWith(TTL.label, zoomKeys{z}), 1);
        if isempty(m), axis(ax, 'off'); continue; end
        if strcmp(zoomEdge{z}, 'start'), tc = TTL.startSec(m); w = [tc - 20, tc + 40];
        else, tc = TTL.endSec(m); w = [tc - 40, tc + 20]; end
        ri = max(1, round(w(1) * fs) + 1):min(numel(rsp), round(w(2) * fs) + 1);
        ri = ri(1:max(1, round(fs / 50)):end);
        plot(ax, (ri - 1) / fs - tc, zs(rsp(ri)), 'k', 'LineWidth', 0.9);
        li = tP >= w(1) & tP <= w(2);
        if any(isfinite(logTrace.pressure(li)))
            plot(ax, tP(li) - tc, zs(logTrace.pressure(li)), 'r', 'LineWidth', 0.7);
        end
        if any(isfinite(logTrace.target(li)))
            plot(ax, tP(li) - tc, zs(logTrace.target(li)), 'b--', 'LineWidth', 0.8);
        end
        xline(ax, 0, 'm-', 'LineWidth', 1.2);
        xlim(ax, w - tc); grid(ax, 'on');
        title(ax, {char(TTL.label(m)), sprintf('%s (%s)', zoomEdge{z}, TTL.source(m))}, 'Interpreter', 'none', 'FontSize', 8);
        xlabel(ax, 's from block edge', 'FontSize', 8);
    end
    annotation(fig, 'textbox', [0.05 0.245 0.92 0.03], 'String', ...
        ['zooms (z-scored): black = raw rsp1 (CSC31), red = SniffLogic log pressure mapped onto the raw clock, ' ...
         'blue dashed = target trace; magenta = block edge'], 'EdgeColor', 'none', 'FontSize', 8, 'Interpreter', 'none');

    % ---------------- numbers ----------------
    L = {};
    for k = 1:numel(info.logAlign)
        a = info.logAlign(k);
        rl = NaN; if isfield(a, 'rLocal'), rl = a.rLocal; end
        L{end+1} = sprintf('log%d %s', k, a.file); %#ok<AGROW>
        L{end+1} = sprintf('     overlap |r| %.2f (global %.2f), lag %.3f s, drift %.1f ppm (applied %d), polarity %+d, covers raw %.1f-%.1f min, %d block starts, audiobook %d', ...
            rl, a.r, a.lagSec, a.driftPPM, a.useDrift, a.rspFlip, a.rawStartSec / 60, a.rawEndSec / 60, a.nBlocks, a.hasAudio); %#ok<AGROW>
    end
    for k = 1:height(info.aborted)
        L{end+1} = sprintf('aborted block start (no block_end; NOT in the table): %s at raw %.1f min (%s)', ...
            info.aborted.name(k), info.aborted.rawStartSec(k) / 60, info.aborted.logFile(k)); %#ok<AGROW>
    end
    nc = info.noteCheck;
    for k = 1:height(nc)
        ed = "start"; if ismember('edge', nc.Properties.VariableNames), ed = nc.edge(k); end
        L{end+1} = sprintf('note check %s %s: notes %s = %.0f s, logs %.0f s, note - log = %+.0f s', ...
            nc.key(k), ed, nc.noteTime(k), nc.noteSec(k), nc.logSec(k), nc.diffSec(k)); %#ok<AGROW>
    end
    sw = TTL(TTL.source == "notes_stopwatch", :);
    for k = 1:height(sw)
        L{end+1} = sprintf('stopwatch %-24s %s - %s (%.0f s, hard-coded from the session notes)', sw.label(k), ...
            hmsStr(sw.startSec(k)), hmsStr(sw.endSec(k)), sw.durationSec(k)); %#ok<AGROW>
    end
    axT = axes(fig, 'Position', [0.05 0.01 0.92 0.22]); axis(axT, 'off');
    text(axT, 0, 1, L, 'VerticalAlignment', 'top', 'FontSize', 8, 'Interpreter', 'none', 'FontName', 'FixedWidth');

    saveas(fig, fullfile(figDir, [sessID '_sweepTTL.png']));
    close(fig);
end

function y = zs(x)
    x = double(x(:));
    y = (x - median(x, 'omitnan')) / (std(x, 'omitnan') + eps);
end

function s = hmsStr(sec)
    s = sprintf('%d:%02d:%02d', floor(sec / 3600), floor(mod(sec, 3600) / 60), round(mod(sec, 60)));
end

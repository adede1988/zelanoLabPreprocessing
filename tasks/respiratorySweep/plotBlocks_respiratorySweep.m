function plotBlocks_respiratorySweep(outDat, rspDat)
%PLOTBLOCKS_RESPIRATORYSWEEP  QC figures for a respiratorySweep final.
%
%   plotBlocks_respiratorySweep(outDat, rspDat)
%
%   rspDat : the respiration trace the breaths were segmented on (rspIDX
%            selected, rspFlip applied), 500 Hz
%
%   Saves to outDat.figs:
%     blocks_TTL.jpg       per-breath rate (with each sweep block's target pace
%                          as a red bar) and amplitude over the whole recording,
%                          blocks shaded by type (blue audiobook, orange sweep,
%                          green focused breathing), and the respiration trace
%                          with the block edges
%     sweepBlocks_zoom.jpg one 40-s panel per block (from 30 s after its start):
%                          respiration (black) and, for sweep blocks, the
%                          target trace the participant traced (blue,
%                          targTrace channel), both z-scored in the window;
%                          the title gives the block's median breath rate
%                          against its target pace

    B = outDat.blocks;
    fs = outDat.fs;
    bh = outDat.behDat;
    tMin = bh.sniffOnset / fs / 60;
    if ~exist(outDat.figs, 'dir'), mkdir(outDat.figs); end

    % ---------------- overview ----------------
    fig = figure('Visible', 'off', 'Position', [30 30 1900 1050], 'Color', 'w');
    ax1 = subplot(3, 1, 1); hold(ax1, 'on');
    shade(ax1, B, fs, [0 30], true);
    plot(ax1, tMin(~bh.inBlock), bh.rateBPM(~bh.inBlock), '.', 'Color', [0.65 0.65 0.65], 'MarkerSize', 6);
    plot(ax1, tMin(bh.inBlock), bh.rateBPM(bh.inBlock), '.', 'Color', [0.1 0.1 0.1], 'MarkerSize', 7);
    sw = find(B.blockType == "sweep");
    for b = sw'
        plot(ax1, [B.startSample(b) B.endSample(b)] / fs / 60, [B.cpm(b) B.cpm(b)], 'r-', 'LineWidth', 2);
    end
    ylim(ax1, [0 30]); ylabel(ax1, 'breath rate (/min)'); grid(ax1, 'on');
    title(ax1, sprintf(['%s respiratorySweep: per-breath rate (black in a block, gray between) vs target ' ...
        'pace (red); %d breaths, %d in blocks'], outDat.sessID, height(bh), sum(bh.inBlock)), 'Interpreter', 'none');

    ax2 = subplot(3, 1, 2); hold(ax2, 'on');
    ya = [0, prctile(bh.amp, 99) * 1.15];
    shade(ax2, B, fs, ya, false);
    plot(ax2, tMin, bh.amp, '.', 'Color', [0.2 0.2 0.2], 'MarkerSize', 6);
    ylim(ax2, ya); ylabel(ax2, 'breath amplitude'); grid(ax2, 'on');

    ax3 = subplot(3, 1, 3); hold(ax3, 'on');
    dec = max(1, round(fs / 10));
    tt = (0:dec:numel(rspDat) - 1) / fs / 60;
    plot(ax3, tt, rspDat(1:dec:end), 'k', 'LineWidth', 0.3);
    yl3 = [prctile(rspDat, 0.5), prctile(rspDat, 99.5)];
    for b = 1:height(B)
        xline(ax3, B.startSample(b) / fs / 60, 'Color', [0 0.6 0]);
        xline(ax3, B.endSample(b) / fs / 60, 'Color', [0.85 0 0]);
    end
    ylim(ax3, yl3); ylabel(ax3, 'respiration (rspIDX/rspFlip applied)'); xlabel(ax3, 'min'); grid(ax3, 'on');
    title(ax3, 'block starts (green) / ends (red)');
    linkaxes([ax1 ax2 ax3], 'x'); xlim(ax1, [0 numel(rspDat) / fs / 60]);
    saveas(fig, fullfile(outDat.figs, 'blocks_TTL.jpg'));
    close(fig);

    % ---------------- per-block zooms ----------------
    hasT = any(strcmp(outDat.labels, 'targTrace'));
    if hasT, targ = outDat.data(strcmp(outDat.labels, 'targTrace'), :); end
    nB = height(B);
    nc = 6; nr = ceil(nB / nc);
    fig = figure('Visible', 'off', 'Position', [10 10 2000, 330 * nr], 'Color', 'w');
    for b = 1:nB
        ax = subplot(nr, nc, b); hold(ax, 'on');
        s0 = min(B.startSample(b) + round(30 * fs), B.endSample(b));
        s1 = min([s0 + round(40 * fs) - 1, B.endSample(b), numel(rspDat)]);
        if s1 - s0 < fs, axis(ax, 'off'); continue; end
        t = ((s0:s1) - B.startSample(b)) / fs;
        plot(ax, t, z(rspDat(s0:s1)), 'k', 'LineWidth', 0.8);
        if hasT && B.blockType(b) == "sweep"
            plot(ax, t, z(targ(s0:s1)), 'b', 'LineWidth', 0.8);
        end
        m = bh.condition == b;
        medR = median(bh.rateBPM(m), 'omitnan');
        if B.blockType(b) == "sweep"
            ttl = {sprintf('b%02d  target %g/min, depth %.2f', B.blockIdx(b), B.cpm(b), B.depth(b)), sprintf('median %.1f/min (n=%d)', medR, sum(m))};
        else
            ttl = {char(B.label(b)), sprintf('median %.1f/min (n=%d)', medR, sum(m))};
        end
        title(ax, ttl, 'Interpreter', 'none', 'FontSize', 7.5, 'FontWeight', 'normal');
        xlim(ax, [t(1) t(end)]); grid(ax, 'on');
        if mod(b - 1, nc) == 0, ylabel(ax, 'z'); end
    end
    sgtitle(fig, sprintf('%s: 40 s of each block, from 30 s after its start (black respiration, blue target trace, z)', ...
        outDat.sessID), 'Interpreter', 'none');
    saveas(fig, fullfile(outDat.figs, 'sweepBlocks_zoom.jpg'));
    close(fig);

    % ---------------- breath-segmentation overlay ----------------
    % 60 s from the middle of: the first audiobook, the first pass's sweep
    % blocks (one per pace) and the first post-sweep focused / audiobook blocks
    pick = find(B.blockType ~= "sweep" & B.phase == "pre", 1);
    sw1 = find(B.blockType == "sweep" & B.sweepNum == min(B.sweepNum(B.blockType == "sweep")));
    pick = [pick; sw1(:)];
    pick = [pick; find(B.blockType == "focusedBreathing", 1); find(B.blockType == "audiobook" & B.phase == "post", 1)];
    pick = pick(:)';
    bm = outDat.bmObj;
    nP = numel(pick); nc = 3; nr = ceil(nP / nc);
    fig = figure('Visible', 'off', 'Position', [10 10 1900, 300 * nr], 'Color', 'w');
    for k = 1:nP
        b = pick(k);
        ax = subplot(nr, nc, k); hold(ax, 'on');
        mid = round((B.startSample(b) + B.endSample(b)) / 2);
        s0 = max(1, mid - round(30 * fs)); s1 = min(numel(rspDat), mid + round(30 * fs));
        t = (s0:s1) / fs;
        plot(ax, t, rspDat(s0:s1), 'k', 'LineWidth', 0.7);
        in = bm(:, 2) >= t(1) & bm(:, 2) <= t(end);
        plot(ax, bm(in, 2), bm(in, 1), '^', 'Color', [0 0.6 0], 'MarkerFaceColor', [0 0.6 0], 'MarkerSize', 5);
        inP = bm(:, 4) >= t(1) & bm(:, 4) <= t(end);
        plot(ax, bm(inP, 4), bm(inP, 3), 'rv', 'MarkerSize', 4);
        inT = bm(:, 11) >= t(1) & bm(:, 11) <= t(end);
        plot(ax, bm(inT, 11), bm(inT, 10), 'bo', 'MarkerSize', 3);
        xlim(ax, [t(1) t(end)]); grid(ax, 'on');
        title(ax, {char(B.label(b)), sprintf('%d onsets in 60 s', sum(in))}, 'Interpreter', 'none', 'FontSize', 8, 'FontWeight', 'normal');
    end
    sgtitle(fig, sprintf('%s breath segmentation (green onset, red inhale peak, blue exhale trough; s)', ...
        outDat.sessID), 'Interpreter', 'none');
    saveas(fig, fullfile(outDat.figs, 'breathOverlay.jpg'));
    close(fig);
end

function shade(ax, B, fs, yl, withText)
    for b = 1:height(B)
        x0 = B.startSample(b) / fs / 60; x1 = B.endSample(b) / fs / 60;
        switch B.blockType(b)
            case "audiobook",        c = [0.30 0.50 0.90];
            case "focusedBreathing", c = [0.20 0.65 0.30];
            case "sweep",            c = [0.95 0.55 0.15];
            otherwise,               c = [0.60 0.60 0.60];
        end
        patch(ax, [x0 x1 x1 x0], [yl(1) yl(1) yl(2) yl(2)], c, 'FaceAlpha', 0.15, 'EdgeColor', 'none');
        if withText
            if B.blockType(b) == "sweep"
                txt = sprintf('b%02d', B.blockIdx(b));
            else
                txt = shortLabel(B.label(b));
            end
            text(ax, (x0 + x1) / 2, yl(2) - 0.5, txt, 'HorizontalAlignment', 'center', ...
                 'VerticalAlignment', 'top', 'FontSize', 7, 'Interpreter', 'none');
        end
    end
end

function y = z(x)
    x = double(x(:)');
    y = (x - mean(x)) / (std(x) + eps);
end

function s = shortLabel(lab)
% 'audiobook_pre' -> 'AB pre', 'focusedBreathing_post2' -> 'FB2', 'audiobook_post1' -> 'AB1'
    lab = char(lab);
    s = regexprep(lab, '^audiobook_pre$', 'AB pre');
    s = regexprep(s, '^audiobook_post(\d+)$', 'AB$1');
    s = regexprep(s, '^focusedBreathing_post(\d+)$', 'FB$1');
    s = strrep(s, '_', ' ');
end

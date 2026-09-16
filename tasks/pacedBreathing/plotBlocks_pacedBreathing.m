function plotBlocks_pacedBreathing(outDat, rspDat)
%PLOTBLOCKS_PACEDBREATHING  QC figure for the inferred pacedBreathing blocks.
%
%   plotBlocks_pacedBreathing(outDat, rspDat)
%
%   Saves <outDat.figs>\blocks_inferred.jpg: per-breath rate and amplitude
%   over the recording (from bmObj) with the inferred blocks shaded and
%   labelled (order / positional label / median rate), plus the whole
%   respiration trace with the block starts (TTL) marked. Review this figure
%   before trusting the block labels - they are inferred, not recorded.

    bmObj = outDat.bmObj;
    B = outDat.blocks;
    fs = outDat.fs;
    tMin = bmObj(:, 2) / 60;
    rate = 60 ./ bmObj(:, 7);
    amp  = bmObj(:, 8);
    cols = lines(max(7, height(B)));

    fig = figure('Visible', 'off', 'Position', [40 40 1800 1000]);
    ax1 = subplot(3, 1, 1); hold on
    for b = 1:height(B)
        x0 = B.startSample(b) / fs / 60; x1 = B.endSample(b) / fs / 60;
        patch([x0 x1 x1 x0], [0 0 40 40], cols(mod(b - 1, size(cols, 1)) + 1, :), ...
              'FaceAlpha', 0.12, 'EdgeColor', 'none');
        text((x0 + x1) / 2, 37, sprintf('%d %s\n%.1f/min', B.order(b), B.label(b), B.medRateBPM(b)), ...
             'HorizontalAlignment', 'center', 'VerticalAlignment', 'top', 'FontSize', 7, 'Interpreter', 'none');
    end
    plot(tMin, rate, '.', 'Color', [0.2 0.2 0.2], 'MarkerSize', 5);
    ylim([0 40]); ylabel('breath rate (breaths/min)'); grid on
    title(sprintf('%s inferred blocks (n=%d) - labels are positional', outDat.sessID, height(B)), 'Interpreter', 'none');

    ax2 = subplot(3, 1, 2); hold on
    yl = [0, prctile(amp, 99) * 1.2];
    for b = 1:height(B)
        x0 = B.startSample(b) / fs / 60; x1 = B.endSample(b) / fs / 60;
        patch([x0 x1 x1 x0], [yl(1) yl(1) yl(2) yl(2)], cols(mod(b - 1, size(cols, 1)) + 1, :), ...
              'FaceAlpha', 0.12, 'EdgeColor', 'none');
    end
    plot(tMin, amp, '.', 'Color', [0.2 0.2 0.2], 'MarkerSize', 5);
    ylim(yl); ylabel('breath amplitude'); grid on

    ax3 = subplot(3, 1, 3); hold on
    dec = max(1, round(fs / 10));
    tt = (1:dec:numel(rspDat)) / fs / 60;
    plot(tt, rspDat(1:dec:end), 'k');
    yl3 = [prctile(rspDat, 0.5), prctile(rspDat, 99.5)];
    for b = 1:height(B)
        xline(B.startSample(b) / fs / 60, 'r-');
    end
    ylim(yl3); ylabel('respiration (rspIDX/rspFlip applied)'); xlabel('min'); grid on
    linkaxes([ax1 ax2 ax3], 'x'); xlim([0 numel(rspDat) / fs / 60]);

    if ~exist(outDat.figs, 'dir'), mkdir(outDat.figs); end
    saveas(fig, fullfile(outDat.figs, 'blocks_inferred.jpg'));
    close(fig);
end

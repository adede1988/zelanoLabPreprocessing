function plotBlocks_vipassana(outDat, rspDat)
%PLOTBLOCKS_VIPASSANA  QC figure for the inferred vipassana periods.
%
%   plotBlocks_vipassana(outDat, rspDat)
%
%   Saves <outDat.figs>\blocks_inferred.jpg - review it before trusting the
%   period boundaries, which are INFERRED from the EEG activity evidence
%   (inferBlocks_vipassana) with the hand-pressed markers only as hints.
%   Panels (shared minute axis):
%     1. activity evidence (outDat.artifactIndex.evid; artDev in light grey)
%        with the blocks shaded (still = blue, active = orange) and labelled
%        (order, label, duration), the Stimulus markers as red lines, and
%        at every inferred boundary its margin (cost units; small = weakly
%        determined) plus a dashed grey line at the alternative position
%        (outDat.blockInference.margins.altSec) when available;
%     2. hfLog  - channel-median log10 30-100 Hz power (EMG);
%     3. p2pLog - channel-median log10 1-100 Hz peak-to-peak (movement);
%     4. the respiration trace (rspIDX/rspFlip applied) with the block
%        starts, if rspDat is non-empty;
%     5. breath rate per breath (60 / bmObj col 7 at onset time bmObj col 2),
%        if outDat.bmObj has rows.
%
%   Inputs
%     outDat : the session struct after inferBlocks_vipassana, with
%              .artifactIndex (table: tSec, hfLog, p2pLog, artDev, evid),
%              .blocks (table: label, order, still, startSample, endSample,
%              durationSec, boundaryMarginStart), .fs, .sessID, .figs, and
%              optionally .markers (table with .sample at outDat.fs,
%              .description, optionally .type), .blockInference (margins),
%              .bmObj
%     rspDat : 1 x N respiration trace at outDat.fs, or [] (respiration
%              skipped, e.g. CC)
%
%   Caveat: the markers are drawn where they were pressed; they are known to
%   be late / missing / doubled in some sessions (see the sheet notes).

    B  = outDat.blocks;
    fs = outDat.fs;
    A  = outDat.artifactIndex;
    tA = A.tSec / 60;
    durMin = B.endSample(end) / fs / 60;                % the blocks tile 1..nSamp

    % markers (Stimulus only when a type column exists)
    mkMin = [];
    if isfield(outDat, 'markers') && istable(outDat.markers) && height(outDat.markers) > 0 && ...
            ismember('sample', outDat.markers.Properties.VariableNames)
        mk = outDat.markers;
        if ismember('type', mk.Properties.VariableNames)
            mk = mk(strcmpi(strtrim(string(mk.type)), "Stimulus"), :);
        elseif ismember('description', mk.Properties.VariableNames)
            mk = mk(~strcmpi(strtrim(string(mk.description)), "New Segment"), :);
        end
        mkMin = (double(mk.sample(:)) - 1) / fs / 60;
    end
    altMin = [];
    if isfield(outDat, 'blockInference') && isstruct(outDat.blockInference) && ...
            isfield(outDat.blockInference, 'margins') && istable(outDat.blockInference.margins)
        altMin = outDat.blockInference.margins.altSec / 60;
    end

    hasRsp  = nargin >= 2 && ~isempty(rspDat);
    hasRate = isfield(outDat, 'bmObj') && ~isempty(outDat.bmObj) && size(outDat.bmObj, 1) > 0;
    nRow = 3 + hasRsp + hasRate;
    hts = [2.2, ones(1, nRow - 1)];
    fig = figure('Visible', 'off', 'Position', [40 40 1900 260 * nRow + 120]);
    tl = tiledlayout(fig, sum(round(hts * 5)), 1, 'TileSpacing', 'compact', 'Padding', 'compact');
    ax = gobjects(nRow, 1);
    cStill = [0.30 0.55 0.90]; cAct = [0.95 0.60 0.20];
    x0 = (B.startSample - 1) / fs / 60; x1 = B.endSample / fs / 60;

    % ---- 1. evidence ----
    ax(1) = nexttile(tl, [round(hts(1) * 5) 1]); hold(ax(1), 'on')
    yl = [-1.2, min(4.6, max(1.5, max(A.evid) + 0.8))];    % evid is clipped to [-1 4]; zoom in on quiet sessions
    for b = 1:height(B)
        c = cAct; if B.still(b) == 1, c = cStill; end
        patch(ax(1), [x0(b) x1(b) x1(b) x0(b)], [yl(1) yl(1) yl(2) yl(2)], c, 'FaceAlpha', 0.16, 'EdgeColor', 'none');
        text(ax(1), (x0(b) + x1(b)) / 2, yl(2) - 0.1, sprintf('%d %s\n%.1f min', B.order(b), B.label(b), B.durationSec(b) / 60), ...
            'HorizontalAlignment', 'center', 'VerticalAlignment', 'top', 'FontSize', 7, 'Interpreter', 'none');
    end
    if ismember('artDev', A.Properties.VariableNames)
        plot(ax(1), tA, min(max(A.artDev, yl(1)), yl(2)), 'Color', [0.75 0.75 0.75]);
    end
    plot(ax(1), tA, A.evid, 'k', 'LineWidth', 1);
    for k = 1:numel(altMin)
        if isfinite(altMin(k)), xline(ax(1), altMin(k), '--', 'Color', [0.5 0.5 0.5]); end
    end
    for k = 1:numel(mkMin), xline(ax(1), mkMin(k), 'r-', 'LineWidth', 1.2); end
    for b = 1:height(B)
        if ismember('boundaryMarginStart', B.Properties.VariableNames) && isfinite(B.boundaryMarginStart(b))
            xline(ax(1), x0(b), 'b-', 'LineWidth', 1.5);
            text(ax(1), x0(b), yl(1) + 0.15, sprintf(' m=%.0f', B.boundaryMarginStart(b)), ...
                'Color', 'b', 'FontSize', 8, 'VerticalAlignment', 'bottom', 'Interpreter', 'none');
        elseif ismember('boundaryMarginStart', B.Properties.VariableNames) && isinf(B.boundaryMarginStart(b))
            xline(ax(1), x0(b), 'b-', 'LineWidth', 1.5);
            text(ax(1), x0(b), yl(1) + 0.15, ' m=Inf', 'Color', 'b', 'FontSize', 8, 'VerticalAlignment', 'bottom');
        end
    end
    ylim(ax(1), yl); ylabel(ax(1), 'activity evidence'); grid(ax(1), 'on')
    title(ax(1), sprintf(['%s  inferred periods (blue = boundary + margin, red = markers, dashed = ' ...
        'alternative boundary; blue shade = still, orange = active)'], outDat.sessID), 'Interpreter', 'none');

    % ---- 2/3. components ----
    comp = {'hfLog', 'log10 30-100 Hz power'; 'p2pLog', 'log10 1-100 Hz p2p'};
    for r = 1:2
        ax(1 + r) = nexttile(tl, [5 1]); hold(ax(1 + r), 'on')
        v = A.(comp{r, 1});
        ylr = [prctile(v, 0.5), prctile(v, 99.5)]; if ~(ylr(2) > ylr(1)), ylr = ylr + [-1 1]; end
        shadeBlocks(ax(1 + r), B, x0, x1, ylr, cStill, cAct);
        plot(ax(1 + r), tA, v, 'Color', [0.2 0.2 0.2]);
        for k = 1:numel(mkMin), xline(ax(1 + r), mkMin(k), 'r-'); end
        ylim(ax(1 + r), ylr); ylabel(ax(1 + r), comp{r, 2}); grid(ax(1 + r), 'on')
    end
    row = 3;

    % ---- 4. respiration ----
    if hasRsp
        row = row + 1;
        ax(row) = nexttile(tl, [5 1]); hold(ax(row), 'on')
        dec = max(1, round(fs / 10));
        tt = (0:dec:numel(rspDat) - 1) / fs / 60;
        y = rspDat(1:dec:end);
        ylr = [prctile(y, 0.5), prctile(y, 99.5)]; if ~(ylr(2) > ylr(1)), ylr = ylr + [-1 1]; end
        plot(ax(row), tt, y, 'k');
        for b = 1:height(B), xline(ax(row), x0(b), 'b-'); end
        ylim(ax(row), ylr); ylabel(ax(row), 'respiration (rspFlip applied)'); grid(ax(row), 'on')
    end

    % ---- 5. breath rate ----
    if hasRate
        row = row + 1;
        ax(row) = nexttile(tl, [5 1]); hold(ax(row), 'on')
        bm = outDat.bmObj;
        rate = 60 ./ bm(:, 7);
        shadeBlocks(ax(row), B, x0, x1, [0 40], cStill, cAct);
        plot(ax(row), bm(:, 2) / 60, rate, '.', 'Color', [0.2 0.2 0.2], 'MarkerSize', 5);
        ylim(ax(row), [0 40]); ylabel(ax(row), 'breaths / min'); grid(ax(row), 'on')
    end
    xlabel(ax(row), 'min');
    linkaxes(ax, 'x'); xlim(ax(1), [0 durMin]);

    if ~exist(outDat.figs, 'dir'), mkdir(outDat.figs); end
    saveas(fig, fullfile(outDat.figs, 'blocks_inferred.jpg'));
    close(fig);
end

function shadeBlocks(ax, B, x0, x1, yl, cStill, cAct)
    for b = 1:height(B)
        c = cAct; if B.still(b) == 1, c = cStill; end
        patch(ax, [x0(b) x1(b) x1(b) x0(b)], [yl(1) yl(1) yl(2) yl(2)], c, 'FaceAlpha', 0.12, 'EdgeColor', 'none');
    end
end

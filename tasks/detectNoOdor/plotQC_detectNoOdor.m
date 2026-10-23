function figFile = plotQC_detectNoOdor(outDat, R, inh)
%PLOTQC_DETECTNOODOR  All-trials montage: respiration around each SNIFF cue.
%
%   figFile = plotQC_detectNoOdor(outDat, R, inh)
%
%   One panel per trial, -3 .. +8 s around the SNIFF cue: the respiration
%   (R.rspDat, inhale up, the inhale counter's smoothing), the cue (green), the
%   button response (red), the coarse sniffOnset (magenta) and finalOnset (blue
%   dashed) of the trial's behDat row, the inhale peaks that were counted (red
%   triangles) and the candidates below the threshold (open circles). Title:
%   trial, answer, nInhales. Saved invisibly as
%   <outDat.figs>\trials_detectNoOdor.png.

    fs = outDat.fs;
    TTL = outDat.TTL;
    B = outDat.behDat;
    nT = height(TTL);
    x = smoothdata(R.rspDat, 'gaussian', max(1, round(inh.opts.smoothSec * fs)));
    T = numel(x);
    pre = round(3 * fs); post = round(8 * fs);
    tt = (-pre:post) / fs;
    nCol = 5; nRow = ceil(nT / nCol);
    fig = figure('Visible', 'off', 'Position', [0 0 2400 max(400, 200 * nRow)]);
    tiledlayout(nRow, nCol, 'TileSpacing', 'compact', 'Padding', 'compact');
    for t = 1:nT
        nexttile; hold on
        c = TTL.sniff(t);
        idx = c + (-pre:post);
        ok = idx >= 1 & idx <= T;
        y = nan(size(idx)); y(ok) = x(idx(ok));
        plot(tt, y, 'k');
        xline(0, 'Color', [0 0.7 0], 'LineWidth', 1.2);
        if ~isnan(TTL.response(t))
            xline((TTL.response(t) - c) / fs, 'r', 'LineWidth', 1.2);
        end
        r = find(B.n == t, 1);
        ans_ = "no row";
        if ~isempty(r)
            plot((B.sniffOnset(r) - c) / fs, x(min(max(B.sniffOnset(r), 1), T)), 'm.', 'MarkerSize', 14);
            xline((B.finalOnset(r) - c) / fs, 'b--');
            ans_ = B.respString(r);
        end
        if isfield(inh, 'peaks') && ~isempty(inh.peaks)
            P = inh.peaks(inh.peaks.trial == t, :);
            pidx = c + round(P.tSec * fs);
            pk = x(min(max(pidx, 1), T));
            plot(P.tSec(P.counted), pk(P.counted), 'rv', 'MarkerFaceColor', 'r', 'MarkerSize', 5);
            plot(P.tSec(~P.counted), pk(~P.counted), 'o', 'Color', [0.3 0.3 1], 'MarkerSize', 4);
        end
        xlim([-3 8]);
        title(sprintf('trial %d  %s  n=%g', t, ans_, inh.nInhales(t)), 'FontSize', 8);
    end
    sgtitle({sprintf('%s detectNoOdor: respiration around the SNIFF cue', outDat.sessID), ...
        sprintf(['cue (green), response (red), sniffOnset (magenta), finalOnset (blue dashed), ' ...
        'counted inhales (red) / candidates (blue o), promFrac %g'], inh.opts.promFrac)}, ...
        'Interpreter', 'none', 'FontSize', 10);
    figFile = fullfile(outDat.figs, 'trials_detectNoOdor.png');
    saveas(fig, figFile);
    close(fig);
end

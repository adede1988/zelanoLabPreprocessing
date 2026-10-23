function files = plotQC_airPuff(outDat, qc)
%PLOTQC_AIRPUFF  QC figures for an airPuff final (saved to outDat.figs, never shown).
%
%   files = plotQC_airPuff(outDat, qc)    qc = detectHolds_airPuff's third output
%
%   airPuff_overview.jpg  whole session: event channel with the pulse roles
%                         (lead / puff / separator), respiration with the holds
%                         shaded (cued / blind) + puffs + inhale onsets, the hold
%                         detector's quiet measure with its threshold, RRint
%   airPuff_holds.jpg     one zoom per hold (hold onset - 15 s .. offset + 10 s)
%   airPuff_locked.jpg    puff-locked respiration and RRint epochs by condition,
%                         and hold-onset-locked RRint (breath-hold bradycardia)
%   Returns the saved file paths.

    fs = outDat.fs;
    N = size(outDat.data, 2);
    t = (0:N - 1) / fs;
    cCued = [0.85 0.33 0.10]; cBlind = [0 0.45 0.74];
    condCol = @(c) cCued * (c == "cued") + cBlind * (c ~= "cued");
    isRsp = cellfun(@(x) contains(x, 'rsp'), outDat.labels);
    rsp = outDat.data(isRsp, :); rsp = rsp(outDat.rspIDX, :) .* outDat.rspFlip;
    ev = outDat.data(cellfun(@(x) contains(x, 'event'), outDat.labels), :);
    hasRR = isfield(outDat, 'ecgSkipped') && outDat.ecgSkipped == 0;
    if hasRR, rr = outDat.data(cellfun(@(x) contains(x, 'RRint'), outDat.labels), :); end
    P = outDat.pulses; H = outDat.holds; B = outDat.behDat;
    ons = (qc.allOns - 1) / fs;
    yl = prctile(rsp, [0.5 99.5]); yl = yl + [-0.15 0.15] * diff(yl);
    files = {};

    % ---------------- 1. overview ----------------
    fig = figure('Visible', 'off', 'Position', [0 0 1900 1150], 'Color', 'w');
    tl = tiledlayout(fig, 4, 1, 'TileSpacing', 'compact');
    ax1 = nexttile(tl); hold(ax1, 'on');
    plot(ax1, t, ev, 'Color', [0.5 0.5 0.5]);
    roles = ["lead", "puff", "separator", "extra"]; rc = {[0 0 0], [0.85 0 0], [0 0.6 0], [0.6 0 0.6]};
    for r = 1:numel(roles)
        m = P.role == roles(r);
        if any(m), xline(ax1, (P.sample(m) - 1) / fs, 'Color', rc{r}, 'LineWidth', 1); end
    end
    title(ax1, sprintf(['%s airPuff: event channel (500 Hz) - lead %d (black), puffs %d (red), separator %d (green) ' ...
        '| %d cued + %d blind holds'], outDat.sessID, sum(P.role == "lead"), sum(P.role == "puff"), ...
        sum(P.role == "separator"), sum(H.run == 1), sum(H.run == 2)), 'Interpreter', 'none');
    ylabel(ax1, 'uV');
    ax2 = nexttile(tl); hold(ax2, 'on');
    shadeHolds(ax2, H, fs, yl, condCol);
    plot(ax2, t, rsp, 'k');
    for k = 1:height(B), xline(ax2, B.tSec(k), 'Color', condCol(B.condition(k)), 'LineWidth', 1); end
    plot(ax2, ons, repmat(yl(2) - 0.05 * diff(yl), size(ons)), 'v', 'Color', [0 0.5 0], 'MarkerSize', 4, 'MarkerFaceColor', [0 0.5 0]);
    ylim(ax2, yl); ylabel(ax2, 'rsp (uV)');
    title(ax2, sprintf('respiration (rsp %d x %+d, inhale up): holds shaded (orange cued, blue blind), puffs = lines, inhale onsets = green triangles', ...
        outDat.rspIDX, outDat.rspFlip));
    ax3 = nexttile(tl); hold(ax3, 'on');
    ylq = [max(min(qc.msd), 0.05) max(qc.msd) * 1.5];
    shadeHolds(ax3, H, fs, ylq, condCol);
    plot(ax3, t, qc.msd, 'k'); yline(ax3, qc.thr, 'r--', sprintf('quiet < %.1f uV (%.2f x median breath amp %.0f uV)', ...
        qc.thr, qc.opts.quietFrac, qc.ampRef));
    set(ax3, 'YScale', 'log'); ylim(ax3, ylq);
    for k = 1:height(B), xline(ax3, B.tSec(k), 'Color', condCol(B.condition(k))); end
    ylabel(ax3, 'uV'); title(ax3, sprintf('hold detector: %.1f-s moving SD of the <%g Hz respiration', qc.opts.quietWinSec, qc.opts.lpHz));
    ax4 = nexttile(tl); hold(ax4, 'on');
    if hasRR
        ylr = [min(rr) max(rr)] + [-0.05 0.05];
        shadeHolds(ax4, H, fs, ylr, condCol);
        plot(ax4, t, rr, 'k'); ylim(ax4, ylr);
        for k = 1:height(B), xline(ax4, B.tSec(k), 'Color', condCol(B.condition(k))); end
        title(ax4, sprintf('RRint (s), beatSpec %s', outDat.beatSpec), 'Interpreter', 'none');
    else
        title(ax4, sprintf('no RRint (ecgSkipped = %d)', outDat.ecgSkipped));
    end
    xlabel(ax4, 's'); linkaxes([ax1 ax2 ax3 ax4], 'x'); xlim(ax1, [0 t(end)]);
    files{end + 1} = saveFig(fig, fullfile(outDat.figs, 'airPuff_overview.jpg'));

    % ---------------- 2. per-hold zooms ----------------
    nH = height(H);
    fig = figure('Visible', 'off', 'Position', [0 0 1900 260 * ceil(nH / 2) + 80], 'Color', 'w');
    tl = tiledlayout(fig, ceil(nH / 2), 2, 'TileSpacing', 'compact');
    for k = 1:nH
        ax = nexttile(tl); hold(ax, 'on');
        a0 = H.onsetSec(k); a1 = H.offsetSec(k);
        if isnan(a0), a0 = H.firstPuffSec(k); a1 = H.lastPuffSec(k); end
        w0 = max(0, a0 - 15); w1 = min(t(end), a1 + 10);
        m = t >= w0 & t <= w1;
        y2 = prctile(rsp(m), [0 100]); y2 = y2 + [-0.1 0.1] * max(diff(y2), 1);
        shadeHolds(ax, H(k, :), fs, y2, condCol);
        plot(ax, t(m), rsp(m), 'k');
        bk = B(B.hold == H.hold(k), :);
        for j = 1:height(bk), xline(ax, bk.tSec(j), 'Color', condCol(bk.condition(j)), 'LineWidth', 1.2); end
        oi = ons(ons >= w0 & ons <= w1);
        plot(ax, oi, repmat(y2(2) - 0.06 * diff(y2), size(oi)), 'v', 'Color', [0 0.5 0], 'MarkerFaceColor', [0 0.5 0]);
        xlim(ax, [w0 w1]); ylim(ax, y2);
        tag = ''; if H.interrupted(k), tag = ' INTERRUPTED'; end
        title(ax, sprintf('hold %d (%s %d): %.1f s, %d/%d puffs quiet%s, next inhale %.2f s after the last puff', ...
            H.hold(k), H.condition(k), H.holdInRun(k), H.durSec(k), H.nPuffsQuiet(k), H.nPuffs(k), ...
            tag, H.lastPuffToInhaleSec(k)));
    end
    xlabel(tl, 's'); ylabel(tl, 'rsp (uV)');
    title(tl, sprintf('%s airPuff: breath holds (shaded = respiration-defined hold, lines = puffs, triangles = inhale onsets)', ...
        outDat.sessID), 'Interpreter', 'none');
    files{end + 1} = saveFig(fig, fullfile(outDat.figs, 'airPuff_holds.jpg'));

    % ---------------- 3. locked epochs ----------------
    fig = figure('Visible', 'off', 'Position', [0 0 1600 1150], 'Color', 'w');
    tl = tiledlayout(fig, 3, 2, 'TileSpacing', 'compact');
    conds = ["cued", "blind"];
    for c = 1:2
        m = B.condition == conds(c);
        ax = nexttile(tl, c); hold(ax, 'on');
        [E, tt] = epochs(rsp, B.onset(m), -3, 6, fs);
        E = E - mean(E(:, tt >= -1 & tt < 0), 2, 'omitnan');
        plot(ax, tt, E', 'Color', [condCol(conds(c)) 0.3]);
        plot(ax, tt, mean(E, 1, 'omitnan'), 'Color', condCol(conds(c)), 'LineWidth', 2.5);
        xline(ax, 0, 'k--'); ylim(ax, [-1 1] * max(60, prctile(abs(E(:)), 98)));
        title(ax, sprintf('%s puffs (n = %d): respiration, baseline [-1 0) s', conds(c), sum(m)));
        xlabel(ax, 's from puff'); ylabel(ax, 'uV');
        ax = nexttile(tl, 2 + c); hold(ax, 'on');
        if hasRR
            [E, tt] = epochs(rr, B.onset(m), -5, 10, fs);
            plot(ax, tt, E', 'Color', [condCol(conds(c)) 0.3]);
            plot(ax, tt, mean(E, 1, 'omitnan'), 'Color', condCol(conds(c)), 'LineWidth', 2.5);
            xline(ax, 0, 'k--');
        end
        title(ax, sprintf('%s puffs: RRint (s)', conds(c))); xlabel(ax, 's from puff');
        ax = nexttile(tl, 4 + c); hold(ax, 'on');
        hm = H.condition == conds(c) & ~isnan(H.onset);
        if hasRR && any(hm)
            [E, tt] = epochs(rr, H.onset(hm), -10, 25, fs);
            plot(ax, tt, E', 'Color', [condCol(conds(c)) 0.3]);
            plot(ax, tt, mean(E, 1, 'omitnan'), 'Color', condCol(conds(c)), 'LineWidth', 2.5);
            xline(ax, 0, 'k--');
            hs = H(hm, :);
            for j = 1:height(hs), xline(ax, hs.durSec(j), ':', 'Color', condCol(conds(c))); end
        end
        title(ax, sprintf('%s holds (n = %d): RRint (s) from hold onset (dotted = offsets)', conds(c), sum(hm)));
        xlabel(ax, 's from hold onset');
    end
    title(tl, sprintf('%s airPuff: puff- and hold-locked epochs', outDat.sessID), 'Interpreter', 'none');
    files{end + 1} = saveFig(fig, fullfile(outDat.figs, 'airPuff_locked.jpg'));
end

function shadeHolds(ax, H, fs, yl, condCol)
    for k = 1:height(H)
        if isnan(H.onset(k)), continue; end
        x0 = (H.onset(k) - 1) / fs; x1 = (H.offset(k) - 1) / fs;
        patch(ax, [x0 x1 x1 x0], [yl(1) yl(1) yl(2) yl(2)], condCol(H.condition(k)), ...
            'FaceAlpha', 0.15, 'EdgeColor', 'none');
    end
end

function [E, tt] = epochs(x, on, t0, t1, fs)
    off = round(t0 * fs):round(t1 * fs);
    tt = off / fs;
    E = nan(numel(on), numel(off));
    for k = 1:numel(on)
        idx = on(k) + off;
        ok = idx >= 1 & idx <= numel(x);
        E(k, ok) = x(idx(ok));
    end
end

function f = saveFig(fig, f)
    exportgraphics(fig, f, 'Resolution', 110);
    close(fig);
end

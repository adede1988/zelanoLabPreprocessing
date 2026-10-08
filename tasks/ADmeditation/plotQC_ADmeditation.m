function plotQC_ADmeditation(outDat, rspDat)
%PLOTQC_ADMEDITATION  One-page QC figure for an ADmeditation final.
%
%   plotQC_ADmeditation(outDat, rspDat)   rspDat = the chosen, flipped
%                                         respiration row (inhale up)
%
%   Saves <outDat.figs>\QC_ADmeditation.jpg:
%     - breath rate and amplitude per breath over the trimmed recording
%       (grey = goodBreath 0), heart rate from RRint, button presses as red lines
%     - three 40-s respiration windows (start / middle / end) with the inhale
%       onsets (green) and inhale peaks (red) the breath engine found
%     - a 10-s ECG window (the beatSpec lead, z-scored) with the detected beats
%     - the event channel (10-Hz low-passed) around every press in the
%       analysis window, aligned on the detected onset (0 s): the press step
%       should rise at 0 and the release fall ~5 s later
%   Review it before promoting the session's parameters to curated.

    fs = outDat.fs;
    beh = outDat.behDat;
    nS = size(outDat.data, 2);
    tMin = beh.finalOnset / fs / 60;
    good = beh.goodBreath == 1;
    pr = outDat.buttonPresses;
    pIn = pr(pr.inAnalysisWindow, :);
    pMin = pIn.sample / fs / 60;

    fig = figure('Visible', 'off', 'Position', [20 20 1800 1500]);
    nR = 7;

    % ---- rate / amplitude / HR over time ----
    ax = subplot(nR, 1, 1); hold(ax, 'on');
    plot(ax, tMin(~good), beh.rateBPM(~good), '.', 'Color', [0.7 0.7 0.7], 'MarkerSize', 6);
    plot(ax, tMin(good), beh.rateBPM(good), '.', 'Color', [0.1 0.1 0.1], 'MarkerSize', 6);
    yl = [0, max(30, prctile(beh.rateBPM, 99.5))]; ylim(ax, yl);
    pressLines(ax, pMin, yl); xlim(ax, [0 nS / fs / 60]); ylabel(ax, 'breaths/min'); grid(ax, 'on');
    rsa = '';
    if isfield(outDat, 'rspPolarityRSA') && isfinite(outDat.rspPolarityRSA.deltaRRms)
        rsa = sprintf(' | inhale-locked dRR %.1f ms', outDat.rspPolarityRSA.deltaRRms);
    end
    hr = NaN;
    if isfield(outDat, 'heartBeats') && ~isempty(outDat.heartBeats)
        hr = numel(outDat.heartBeats) / (nS / fs / 60);
    end
    title(ax, sprintf(['%s (%s) | analysed %.1f min (raw %.1f, trimmed %g s + %g s) | %d breaths, %.0f%% good | ' ...
        'HR %.1f bpm (beatSpec %s) | presses %d in window, %d trimmed%s | rspIDX %d rspFlip %+d'], ...
        outDat.sessID, outDat.atlasFolder, nS / fs / 60, outDat.trim.rawDurSec / 60, outDat.trim.trimStartSec, ...
        outDat.trim.trimEndSec, height(beh), 100 * mean(good), hr, outDat.beatSpec, height(pIn), ...
        height(pr) - height(pIn), rsa, outDat.rspIDX, outDat.rspFlip), 'Interpreter', 'none', 'FontSize', 9);

    ax = subplot(nR, 1, 2); hold(ax, 'on');
    plot(ax, tMin(~good), beh.amp(~good), '.', 'Color', [0.7 0.7 0.7], 'MarkerSize', 6);
    plot(ax, tMin(good), beh.amp(good), '.', 'Color', [0.1 0.1 0.1], 'MarkerSize', 6);
    yl = [0, max(eps, prctile(beh.amp, 99.5) * 1.1)]; ylim(ax, yl);
    pressLines(ax, pMin, yl); xlim(ax, [0 nS / fs / 60]); ylabel(ax, 'amplitude'); grid(ax, 'on');

    ax = subplot(nR, 1, 3); hold(ax, 'on');
    isRR = cellfun(@(x) contains(x, 'RRint'), outDat.labels);
    if any(isRR)
        rr = outDat.data(find(isRR, 1), :);
        dsI = 1:round(fs / 10):nS;
        plot(ax, dsI / fs / 60, 60 ./ rr(dsI), 'Color', [0.8 0.2 0.2]);
        v = 60 ./ rr(dsI); v = v(isfinite(v));
        yl = [prctile(v, 0.5) - 5, prctile(v, 99.5) + 5];
        if ~isempty(v) && all(isfinite(yl)) && yl(2) > yl(1), ylim(ax, yl); else, yl = ylim(ax); end
        pressLines(ax, pMin, yl);
    else
        text(ax, 0.5, 0.5, 'no RRint (ECG stage skipped)', 'Units', 'normalized', 'HorizontalAlignment', 'center');
    end
    xlim(ax, [0 nS / fs / 60]); ylabel(ax, 'HR (bpm)'); xlabel(ax, 'min (trimmed timeline; red = button press)'); grid(ax, 'on');

    % ---- respiration windows with onsets / peaks ----
    w = round(40 * fs);
    starts = round([60 * fs, nS / 2 - w / 2, nS - 60 * fs - w]);
    names = {'start', 'middle', 'end'};
    for k = 1:3
        ax = subplot(nR, 3, 9 + k); hold(ax, 'on');
        ii = max(1, starts(k)):min(nS, starts(k) + w);
        plot(ax, ii / fs, rspDat(ii), 'k');
        on = beh.finalOnset(beh.finalOnset >= ii(1) & beh.finalOnset <= ii(end));
        pk = beh.inMaxTim(beh.inMaxTim >= ii(1) & beh.inMaxTim <= ii(end));
        plot(ax, on / fs, rspDat(on), 'go', 'MarkerFaceColor', 'g', 'MarkerSize', 4);
        plot(ax, pk / fs, rspDat(pk), 'rv', 'MarkerFaceColor', 'r', 'MarkerSize', 4);
        axis(ax, 'tight'); title(ax, sprintf('respiration (inhale up), %s: onsets green, peaks red', names{k}), 'FontSize', 8);
        xlabel(ax, 's');
    end

    % ---- ECG window with beats ----
    ax = subplot(nR, 1, 5); hold(ax, 'on');
    if isfield(outDat, 'heartBeats') && ~isempty(outDat.heartBeats)
        [ECGz, ~] = buildECGz(outDat);
        lead = str2double(regexp(outDat.beatSpec, '^\s*(\d+)', 'tokens', 'once'));
        if ~isfinite(lead) || lead > size(ECGz, 1), lead = 1; end
        ii = round(nS / 2) + (0:round(10 * fs));
        plot(ax, ii / fs, ECGz(lead, ii), 'k');
        b = outDat.heartBeats(outDat.heartBeats >= ii(1) & outDat.heartBeats <= ii(end));
        xline(ax, b / fs, 'm--');
        axis(ax, 'tight'); title(ax, sprintf('ECG lead %d (z, 5-40 Hz), 10 s mid-recording; magenta = detected beats', lead), 'FontSize', 8);
    else
        text(ax, 0.5, 0.5, 'no heart beats (ECG stage skipped)', 'Units', 'normalized', 'HorizontalAlignment', 'center');
    end
    xlabel(ax, 's');

    % ---- event channel around each press ----
    ax = subplot(nR, 1, [6 7]); hold(ax, 'on');
    evRow = find(strcmp(outDat.labels, 'event'), 1);
    if ~isempty(evRow) && height(pIn) > 0
        [z, p, kk] = butter(4, 10 / (fs / 2), 'low'); [sos, g] = zp2sos(z, p, kk);
        ev = filtfilt(sos, g, double(outDat.data(evRow, :)));
        offs = round(-3 * fs):round(8 * fs);
        cols = lines(height(pIn));
        for k = 1:height(pIn)
            ii = pIn.sample(k) + offs; ok = ii >= 1 & ii <= nS;
            seg = nan(size(offs)); seg(ok) = ev(ii(ok));
            seg = seg - median(seg(offs < 0), 'omitnan');
            plot(ax, offs / fs, seg, 'Color', cols(k, :));
        end
        xline(ax, 0, 'k--'); grid(ax, 'on');
        title(ax, sprintf('event channel (10-Hz low-pass) around the %d presses in the analysis window, aligned on the detected onset (0 s)', ...
            height(pIn)), 'FontSize', 8);
    else
        text(ax, 0.5, 0.5, 'no button presses in the analysis window', 'Units', 'normalized', 'HorizontalAlignment', 'center');
    end
    xlabel(ax, 's from press onset'); ylabel(ax, 'uV');

    if ~exist(outDat.figs, 'dir'), mkdir(outDat.figs); end
    saveas(fig, fullfile(outDat.figs, 'QC_ADmeditation.jpg'));
    close(fig);
end

function pressLines(ax, pMin, yl)
    for k = 1:numel(pMin)
        plot(ax, [pMin(k) pMin(k)], yl, 'r-', 'LineWidth', 1);
    end
end

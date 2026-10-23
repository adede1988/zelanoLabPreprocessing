function T = probeMontageBV(vhdrPath, outDir, varargin)
%PROBEMONTAGEBV  Signal-based channel-role probe for one BrainVision (.vhdr/.vmrk/.eeg) recording.
%
%   T = probeMontageBV(vhdrPath, outDir)
%   T = probeMontageBV(..., 'tag', 'myLabel')
%
%   The BrainVision counterpart of probeMontage.m (which probes Neuralynx
%   .ncs files): reads the WHOLE recording via readBrainVision.m and scores
%   every channel with the same feature names probeMontage uses, plus a few
%   BrainVision/respiration-specific ones ported from the scratch scripts
%   that first characterised the vipassana recordings
%   (DataForClaude/vipassana/probe/probeBV_vipassana.m + respProbe.m):
%     rmsUV      channel RMS (DC-removed), uV
%     lineFrac   58-62 Hz / 1-100 Hz power                 (unconnected / noisy)
%     alphaFrac  8-12 Hz / 1-45 Hz power                    (posterior scalp EEG)
%     respFrac   0.1-0.7 Hz / 0.1-24 Hz power (50 Hz decimated) (respiration: high)
%     respAC     peak autocorr of the <1 Hz trace at 2-12 s lag, respBPM its rate
%     ecgKurt    kurtosis of the 5-40 Hz trace, ecgSkew its skew (ECG: high/spiky)
%     ecgAC      peak autocorr of the 5-40 Hz envelope at 0.4-1.5 s, ecgBPM its rate
%     stepRate   large sample-to-sample jumps per minute     (photodiode / DAQ / artifact)
%     respSkew        skewness of the channel's 0.05-1 Hz band (breathing-cycle asymmetry)
%     respPlateauPos  histogram-mode position of that band within its 5-95th pctile
%                     range, 0 = plateau at the bottom, 1 = plateau at the top
%     respRiseFall    median rise time (trough->peak) / median fall time (peak->trough)
%                     of that band's cycles - respPlateauPos/respRiseFall/respSkew
%                     together say which end of a breath sits flat (the inhale or the
%                     exhale plateau), i.e. how to set rspFlip for THIS channel if it
%                     is chosen as respiration.
%   All features are computed for every channel (not just the presumed resp/ECG ones)
%   as a diagnostic: a channel accidentally carrying resp- or ECG-like signal is a montage
%   red flag.
%
%   Writes <outDir>\probe_<tag>.csv plus two figures:
%     probe_<tag>_features.png  per-channel feature bars (all channels) + an artifact-index
%                                overview: 1-s artifact z-index (30-100 Hz power + 1-100 Hz
%                                peak-to-peak, EEG channels only, robust-z'd and averaged),
%                                a per-10-s EEG log10-rms heatmap, and decimated resp/ECG/photo
%                                traces - each with the .vmrk markers overlaid as red lines.
%     probe_<tag>_traces.png    30-s excerpts of resp / ECG / photo / best-alpha-EEG, plus the
%                                LF (0.05-1 Hz raw) vs ENV (60-Hz line-noise envelope, 0.05-1 Hz)
%                                respiration-derivation/polarity panel (which of the two channel
%                                views carries the breathing cycle, and its plateau/rise-fall
%                                polarity) over the quietest still stretch found by the artifact
%                                index.
%
%   Assumes the lab's 34-channel actiCHamp vipassana montage (31 scalp EEG rows 1-31, then
%   the aux inputs found BY NAME: photo/ECG/resp in the 2026-09-18 sessions, photoDiode/Resp/ECG
%   from 2026-09-27 on) for the artifact-index/EEG-heatmap panel and the excerpt
%   candidates, but the per-channel feature table itself works for any channel count.
%
%   Read-only: never writes anything under vhdrPath's folder.

    p = inputParser;
    p.addParameter('tag', '');
    p.parse(varargin{:});
    tag = p.Results.tag;
    if isempty(tag)
        [~, tag] = fileparts(vhdrPath);
    end
    if ~isfolder(outDir), mkdir(outDir); end

    [X, hdr, mrk] = readBrainVision(vhdrPath);
    fs = hdr.fs; nChan = hdr.nChan; N = size(X, 2);
    labels = hdr.chanNames(:);
    fprintf('probeMontageBV %s: %d ch, fs %g, N %d (%.2f min), %d markers\n', ...
        tag, nChan, fs, N, N / fs / 60, height(mrk));

    % ---------------- per-channel features ----------------
    F = table();
    F.label = labels;
    F.rmsUV = nan(nChan, 1);
    F.lineFrac = nan(nChan, 1); F.alphaFrac = F.lineFrac; F.respFrac = F.lineFrac;
    F.respAC = F.lineFrac; F.respBPM = F.lineFrac; F.ecgKurt = F.lineFrac; F.ecgAC = F.lineFrac;
    F.ecgBPM = F.lineFrac; F.ecgSkew = F.lineFrac; F.stepRate = F.lineFrac;
    F.respSkew = F.lineFrac; F.respPlateauPos = F.lineFrac; F.respRiseFall = F.lineFrac;

    nyq = fs / 2;
    [bE, aE] = butter(4, [5 40] / nyq, 'bandpass');
    [bR, aR] = butter(2, [0.05 1] / 25, 'bandpass');   % applied after 50 Hz decimation

    for c = 1:nChan
        x = X(c, :) - mean(X(c, :));
        if std(x) == 0, F.rmsUV(c) = 0; continue; end
        F.rmsUV(c) = rms(x);
        [Pw, fw] = pwelch(x, round(4 * fs), [], [], fs);
        F.lineFrac(c) = bp(Pw, fw, 58, 62) / max(bp(Pw, fw, 1, 100), eps);
        F.alphaFrac(c) = bp(Pw, fw, 8, 12) / max(bp(Pw, fw, 1, 45), eps);

        xd = resample(x, 50, round(fs));
        [Pd, fd] = pwelch(detrend(xd), min(30 * 50, numel(xd)), [], [], 50);
        F.respFrac(c) = bp(Pd, fd, 0.1, 0.7) / max(bp(Pd, fd, 0.1, 24), eps);
        [bL, aL] = butter(2, 1 / 25, 'low');
        r = filtfilt(bL, aL, detrend(xd));
        [F.respAC(c), lag] = acPeak(r, 50, 2, 12); F.respBPM(c) = 60 / lag;

        e = filtfilt(bE, aE, x);
        F.ecgKurt(c) = kurtosis(e); F.ecgSkew(c) = skewness(e);
        env = abs(hilbert(e)); envd = resample(env, 50, round(fs));
        [F.ecgAC(c), lag2] = acPeak(envd - mean(envd), 50, 0.4, 1.5); F.ecgBPM(c) = 60 / lag2;

        d = abs(diff(x)); F.stepRate(c) = sum(d > 10 * (1.4826 * mad(d, 1)) + median(d)) / (N / fs / 60);

        rr = filtfilt(bR, aR, detrend(xd));
        F.respSkew(c) = skewness(rr);
        F.respPlateauPos(c) = plateauPos(rr);
        F.respRiseFall(c) = riseFallRatio(rr, 50);
    end
    writetable(F, fullfile(outDir, ['probe_' tag '.csv']));
    T = F;

    % ---------------- artifact index (fixed EEG rows 1-31) ----------------
    eegIdx = 1:min(31, nChan);
    hasEeg = numel(eegIdx) >= 2 && any(std(X(eegIdx, :), 0, 2) > 0);
    art = []; artS = []; tSecArt = [];
    if hasEeg
        [bHF, aHF] = butter(4, [30 100] / nyq, 'bandpass');
        [bLF, aLF] = butter(2, 3 / nyq, 'low');
        hf = filtfilt(bHF, aHF, X(eegIdx, :)')';
        lf = filtfilt(bLF, aLF, X(eegIdx, :)')';
        nSec = floor(N / fs);
        hfPow = zeros(numel(eegIdx), nSec); p2p = zeros(numel(eegIdx), nSec); lfPow = zeros(numel(eegIdx), nSec);
        for k = 1:nSec
            seg = round((k - 1) * fs) + (1:round(fs));
            hfPow(:, k) = mean(hf(:, seg) .^ 2, 2);
            p2p(:, k) = max(X(eegIdx, seg), [], 2) - min(X(eegIdx, seg), [], 2);
            lfPow(:, k) = mean(lf(:, seg) .^ 2, 2);
        end
        hfLog = log10(hfPow + eps); p2pLog = log10(p2p + eps); lfLog = log10(lfPow + eps);
        hfMed = median(hfLog, 1); p2pMed = median(p2pLog, 1); lfMed = median(lfLog, 1);
        rz = @(v) (v - median(v)) / max(1.4826 * mad(v, 1), eps);
        art = (rz(hfMed) + rz(p2pMed) + rz(lfMed)) / 3;
        artS = movmedian(art, 11);
        tSecArt = (0.5:1:nSec - 0.5)';
    end

    % ---------------- figure 1: features + overview ----------------
    fig = figure('Visible', 'off', 'Position', [50 50 1800 1200]);
    feats = {'rmsUV', 'respFrac', 'ecgKurt', 'alphaFrac', 'stepRate', 'lineFrac'};
    nTop = numel(feats) + (hasEeg * 3);
    for i = 1:numel(feats)
        subplot(nTop, 1, i);
        v = F.(feats{i}); if strcmp(feats{i}, 'rmsUV'), v = log10(v + 1); end
        bar(1:nChan, v, 1, 'EdgeColor', 'none');
        xlim([0 nChan + 1]);
        set(gca, 'XTick', 1:nChan, 'XTickLabel', labels, 'FontSize', 6); xtickangle(90);
        ylabel(strrep(feats{i}, 'rmsUV', 'log10 rms'), 'FontSize', 7);
        if i == 1, title(sprintf('probeMontageBV %s  (%s)', tag, vhdrPath), 'Interpreter', 'none'); end
    end
    if hasEeg
        ax1 = subplot(nTop, 1, numel(feats) + 1);
        plot(tSecArt / 60, art, 'Color', [.7 .7 .7]); hold on; plot(tSecArt / 60, artS, 'k', 'LineWidth', 1.2);
        for k = 1:height(mrk), xline(mrk.minutes(k), 'r-'); end
        ylabel('artifact idx (z)'); xlim([0 N / fs / 60]); grid on; title('EEG artifact index (red = .vmrk markers)');
        n10 = floor(N / (10 * fs)); rms10 = zeros(numel(eegIdx), n10);
        for k = 1:n10
            seg = round((k - 1) * 10 * fs) + (1:round(10 * fs));
            rms10(:, k) = rms(X(eegIdx, seg) - mean(X(eegIdx, seg), 2), 2);
        end
        ax2 = subplot(nTop, 1, numel(feats) + 2);
        imagesc((0.5:n10 - 0.5) * 10 / 60, 1:numel(eegIdx), log10(rms10 + eps));
        set(gca, 'YTick', 1:numel(eegIdx), 'YTickLabel', labels(eegIdx), 'FontSize', 6);
        ylabel('EEG log10 rms/10s'); colorbar('east'); xlim([0 N / fs / 60]);
        ax3 = subplot(nTop, 1, numel(feats) + 3);
        respRow = find(strcmpi(labels, 'resp'), 1);
        if isempty(respRow), respRow = min(nChan, 34); end
        dec = max(1, round(fs / 50)); tt = (1:dec:N) / fs / 60;
        plot(tt, X(respRow, 1:dec:end), 'k'); ylabel('resp (raw uV)'); xlabel('min'); grid on;
        for k = 1:height(mrk), xline(mrk.minutes(k), 'r-'); end
        xlim([0 N / fs / 60]);
        linkaxes([ax1 ax2 ax3], 'x');
    end
    exportgraphics(fig, fullfile(outDir, ['probe_' tag '_features.png']), 'Resolution', 110);
    close(fig);

    % ---------------- figure 2: traces + resp derivation/polarity ----------------
    fig = figure('Visible', 'off', 'Position', [50 50 1800 1100]);
    respRow = find(strcmpi(labels, 'resp'), 1);
    ecgRow = find(strcmpi(labels, 'ECG'), 1);
    photoRow = find(startsWith(lower(labels), 'photo'), 1);   % 'photo' (v1) / 'photoDiode' (v2)
    [~, alphaOrd] = sort(F.alphaFrac(eegIdx), 'descend');
    alphaRow = eegIdx(alphaOrd(1));

    if hasEeg && ~isempty(artS)
        [~, qm] = min(movmean(artS, min(60, numel(artS))));
        q0Sec = tSecArt(qm);
    else
        q0Sec = N / fs / 2;
    end
    q0 = max(1, round(q0Sec * fs) - 15 * fs);
    winLen = min(30 * fs, N - q0);
    seg = q0 + (0:winLen - 1);
    tsec = (0:winLen - 1) / fs;

    rowsToPlot = {respRow, 'resp', 1; ecgRow, 'ECG (raw)', 2; photoRow, 'photo', 3; alphaRow, ['alpha-best: ' labels{alphaRow}], 4};
    for r = 1:size(rowsToPlot, 1)
        ch = rowsToPlot{r, 1};
        subplot(4, 2, (r - 1) * 2 + 1);
        if isempty(ch)
            title([rowsToPlot{r, 2} ': channel not found']);
        else
            plot(tsec, X(ch, seg), 'k'); title(sprintf('%s @ %.1f min, 30 s', rowsToPlot{r, 2}, q0 / fs / 60), 'FontSize', 8);
            grid on;
        end
        if r == size(rowsToPlot, 1), xlabel('s'); end
    end

    % resp derivation / polarity panel (LF raw band vs 60-Hz envelope band),
    % evaluated over the same quiet window found above (respProbe.m logic).
    if ~isempty(respRow)
        [bB, aB] = butter(2, [55 65] / nyq, 'bandpass');
        winSec = min(180, N / fs);
        w0 = max(1, round(q0Sec * fs) - round(winSec * fs / 2));
        wseg = w0 + (0:min(round(winSec * fs), N - w0) - 1);
        xr = X(respRow, wseg);
        envr = abs(hilbert(filtfilt(bB, aB, xr)));
        fsd2 = 50;
        xd = resample(xr - mean(xr), fsd2, round(fs)); ed = resample(envr - mean(envr), fsd2, round(fs));
        LF = filtfilt(bR, aR, xd); EN = filtfilt(bR, aR, ed);
        z = @(v) (v - mean(v)) / max(std(v), eps);
        tt2 = (0:numel(LF) - 1) / fsd2;
        subplot(4, 2, 2);
        plot(tt2, LF, 'k'); title(sprintf('resp LF 0.05-1Hz | plateauPos %.2f skew %.2f riseFall %.2f', ...
            F.respPlateauPos(respRow), F.respSkew(respRow), F.respRiseFall(respRow)), 'FontSize', 7); grid on;
        subplot(4, 2, 4);
        plot(tt2, EN, 'b'); title('60-Hz envelope, 0.05-1 Hz (ENV)', 'FontSize', 7); grid on;
        subplot(4, 2, 6);
        plot(tt2, z(LF), 'k'); hold on; plot(tt2, z(EN), 'b');
        title(sprintf('LF vs ENV overlay (z), corr %.2f', corr(LF(:), EN(:))), 'FontSize', 7); grid on; xlabel('s');
        subplot(4, 2, 8);
        text(0.02, 0.9, sprintf('respAC %.2f  respBPM %.1f  respFrac %.2f', F.respAC(respRow), F.respBPM(respRow), F.respFrac(respRow)), 'Units', 'normalized', 'FontSize', 8);
        text(0.02, 0.6, sprintf('plateauPos %.2f (>0.5 = plateau at TOP => inhale likely DOWNWARD)', F.respPlateauPos(respRow)), 'Units', 'normalized', 'FontSize', 8);
        text(0.02, 0.3, sprintf('riseFall %.2f, skew %.2f', F.respRiseFall(respRow), F.respSkew(respRow)), 'Units', 'normalized', 'FontSize', 8);
        axis off;
    end
    sgtitle(sprintf('probeMontageBV %s - traces + resp derivation/polarity', tag), 'Interpreter', 'none');
    exportgraphics(fig, fullfile(outDir, ['probe_' tag '_traces.png']), 'Resolution', 110);
    close(fig);

    fprintf('probeMontageBV %s: wrote CSV + 2 figures -> %s\n', tag, outDir);
end

% ================= local functions =================

function v = bp(P, f, lo, hi)
    v = trapz(f(f >= lo & f <= hi), P(f >= lo & f <= hi));
end

function [pk, lagSec] = acPeak(x, fs, loSec, hiSec)
    x = x(:) - mean(x);
    maxLag = round(hiSec * fs);
    c = xcorr(x, maxLag, 'coeff');
    c = c(maxLag + 1:end);
    lags = (0:maxLag)' / fs;
    w = lags >= loSec & lags <= hiSec;
    [pk, i] = max(c(w));
    lw = lags(w); lagSec = lw(i);
    if isempty(pk), pk = NaN; lagSec = NaN; end
end

function q = plateauPos(r)
    % histogram-mode position of r within its 5-95th pctile range: 0 = bottom, 1 = top.
    lo = prctile(r, 5); hi = prctile(r, 95);
    if ~(hi > lo), q = NaN; return; end
    edges = linspace(lo, hi, 21);
    cnt = histcounts(r, edges);
    [~, m] = max(cnt);
    q = (m - 0.5) / 20;
end

function q = riseFallRatio(r, fs)
    % median rise time (trough->peak) / median fall time (peak->trough) of the cycles.
    if std(r) == 0, q = NaN; return; end
    [~, pk] = findpeaks(r, 'MinPeakDistance', round(1.5 * fs), 'MinPeakProminence', 0.5 * std(r));
    [~, tr] = findpeaks(-r, 'MinPeakDistance', round(1.5 * fs), 'MinPeakProminence', 0.5 * std(r));
    rise = []; fall = [];
    for i = 1:numel(pk)
        tPrev = tr(find(tr < pk(i), 1, 'last')); tNext = tr(find(tr > pk(i), 1, 'first'));
        if ~isempty(tPrev), rise(end + 1) = pk(i) - tPrev; end %#ok<AGROW>
        if ~isempty(tNext), fall(end + 1) = tNext - pk(i); end %#ok<AGROW>
    end
    if isempty(rise) || isempty(fall), q = NaN; else, q = median(rise) / median(fall); end
end

function T = guessParamsFromRaw(rawMats, outDir, tag)
%GUESSPARAMSFROMRAW  Measured parameter guesses for a new session, from its extracted raw files.
%
%   T = guessParamsFromRaw(rawMats, outDir, tag)
%     rawMats  cellstr of raw_<task>.mat paths (curDat: rawData / outLabs), e.g.
%              every recording that one sep/cue/thresh run will use
%     outDir   folder for <tag>_params.csv / <tag>_params.txt / figures
%     tag      label for the outputs (e.g. the session id)
%
%   Per recording it measures (at the raw rate, no pipeline code involved):
%     respiration  every channel whose label contains 'rsp': respFrac (0.1-0.7 Hz
%                  share of 0.05-5 Hz power), breathing rate, and a polarity vote
%                  from the waveform asymmetry riseFall = median(trough->peak) /
%                  median(peak->trough). The lab's rsp channels (BiNAPS nasal
%                  pressure, nasal-mask spirometer) are airflow/pressure traces;
%                  CALIBRATED 2026-09-25 on verified sessions (RC_1 curated binaps1
%                  +1, KA_2 / HM_2 binaps1 +1, BW_2 spirometer +1): the lab's
%                  inhale-positive orientation has riseFall 1.8-3.8, the inverted
%                  one 0.3-0.5. So riseFall > 1.1 votes rspFlip = +1, < 0.9 votes
%                  -1, otherwise 0. (Not valid for a volume-like belt trace.)
%     ECG          every 'ECG' channel, 5-40 Hz z-scored, beats counted at 3.5 /
%                  2.5 sigma on each side with the detectBeats refractory (fs/20);
%                  the plausible (40-110/min) channel x side with the largest
%                  margin over the opposite side -> beatSpec '<ch>,0,<gt|lt>,<thr>'
%     macros       'macro' channels railing (>= 2 % of samples pinned at an
%                  extreme, or a pinned run >= 5 s) -> macroRemove candidates;
%                  |z| > 10 event rate per minute -> spikeClean when > 2/min
%     EEG          number of the 32 10-20 labels present in rows 1-32
%   and writes one row per (recording, channel role) to <tag>_params.csv, a
%   plain-text verdict to <tag>_params.txt and one QC figure per recording
%   (60-s respiration traces with the detected peaks/troughs, 10-s ECG with
%   the counted beats). The session-level verdict picks the respiration channel
%   whose WORST respFrac across the recordings is best (a channel that dies in
%   one recording must not be chosen for a concatenated session).
%
%   Heuristics only: the pipeline's own paramCheck / paramCheckECG figures and
%   the guess-QC report remain the review step (paramSource stays 'guess').

    if ischar(rawMats), rawMats = {rawMats}; end
    if ~isfolder(outDir), mkdir(outDir); end
    rows = {};
    rspSummary = struct('label', {}, 'respFrac', {}, 'vote', {});
    ecgBest = {};
    macroRail = {}; spikeRates = [];
    eegCount = [];
    for r = 1:numel(rawMats)
        s = load(rawMats{r}, 'curDat'); cd = s.curDat; clear s
        X = cd.rawData.trial{1};
        fs = cd.rawData.fsample;
        labs = cellfun(@char, cd.outLabs, 'uni', 0);
        [~, recName] = fileparts(rawMats{r});
        fig = figure('Visible', 'off', 'Position', [50 50 1500 1000]);
        tl = tiledlayout(fig, 'flow'); title(tl, sprintf('%s  %s', tag, recName), 'Interpreter', 'none');

        % ---- EEG ----
        eeg1020 = {'Fp1','Fz','F3','F7','FT9','FC5','FC1','C3','T7','TP9','CP5','CP1','Pz','P3', ...
                   'P7','O1','Oz','O2','P4','P8','TP10','CP6','CP2','Cz','C4','T8','FT10','FC6', ...
                   'FC2','F4','F8','Fp2'};
        nE = sum(strcmp(labs(1:min(32, numel(labs))), eeg1020(1:min(32, numel(labs)))));
        eegCount(end + 1) = nE; %#ok<AGROW>
        rows(end + 1, :) = {recName, 'EEG', sprintf('%d/32 10-20 labels in rows 1-32', nE), NaN, NaN, NaN, ''}; %#ok<AGROW>

        % ---- respiration ----
        rIdx = find(contains(labs, 'rsp'));
        for k = 1:numel(rIdx)
            x = fillmissing(double(X(rIdx(k), :)), 'linear', 'EndValues', 'nearest');
            y = resample(x - mean(x), 50, round(fs));         % 50 Hz
            [bL, aL] = butter(2, 1 / 25, 'low');
            y = filtfilt(bL, aL, detrend(y));
            [P, f] = pwelch(y, 50 * 60, [], [], 50);
            rf = sum(P(f >= 0.1 & f <= 0.7)) / max(sum(P(f >= 0.05 & f <= 5)), eps);
            z = (y - median(y)) / (1.4826 * mad(y, 1) + eps);
            [~, pk] = findpeaks(z, 'MinPeakDistance', 75, 'MinPeakProminence', 0.6);
            [~, tr] = findpeaks(-z, 'MinPeakDistance', 75, 'MinPeakProminence', 0.6);
            [rise, fall] = riseFall(pk, tr);
            rfr = median(rise) / median(fall);
            vote = 0; if rfr > 1.1, vote = 1; elseif rfr < 0.9, vote = -1; end
            rate = numel(pk) / (numel(y) / 50 / 60);
            rows(end + 1, :) = {recName, 'rsp', labs{rIdx(k)}, rf, rate, rfr, sprintf('vote %+d (rspIDX %d)', vote, k)}; %#ok<AGROW>
            rspSummary(end + 1) = struct('label', labs{rIdx(k)}, 'respFrac', rf, 'vote', vote); %#ok<AGROW>
            nexttile(tl);
            n0 = max(1, floor(numel(z) / 2) - 1500); n1 = min(numel(z), n0 + 3000);
            t = (n0:n1) / 50;
            plot(t, z(n0:n1), 'k'); hold on
            p = pk(pk >= n0 & pk <= n1); q = tr(tr >= n0 & tr <= n1);
            plot(p / 50, z(p), 'rv', q / 50, z(q), 'b^');
            title(sprintf('rspIDX %d %s: respFrac %.2f  %.1f/min  rise/fall %.2f -> vote %+d', ...
                k, labs{rIdx(k)}, rf, rate, rfr, vote), 'Interpreter', 'none', 'FontSize', 8);
        end

        % ---- ECG ----
        eIdx = find(contains(labs, 'ECG'));
        best = struct('bpm', NaN, 'spec', '', 'margin', 0, 'ch', NaN, 'sgn', 0, 'thr', NaN);
        for k = 1:numel(eIdx)
            x = fillmissing(double(X(eIdx(k), :)), 'linear', 'EndValues', 'nearest');
            x = resample(x - mean(x), 500, round(fs));
            x = bandpass(x, [5 40], 500);
            x = (x - mean(x)) / std(x);
            mins = numel(x) / 500 / 60;
            for thr = [3.5 2.5]
                for sgn = [1 -1]
                    nb = countBeats(sgn * x, thr, 25);
                    nbO = countBeats(-sgn * x, thr, 25);
                    bpm = nb / mins; margin = bpm / max(nbO / mins, 1);
                    rows(end + 1, :) = {recName, 'ECG', labs{eIdx(k)}, bpm, thr * sgn, margin, ''}; %#ok<AGROW>
                    if bpm >= 40 && bpm <= 110 && margin > best.margin
                        best = struct('bpm', bpm, 'spec', sprintf('%d,0,%s,%g', k, ternStr(sgn > 0, 'gt', 'lt'), sgn * thr), ...
                            'margin', margin, 'ch', k, 'sgn', sgn, 'thr', thr);
                    end
                end
            end
        end
        ecgBest{end + 1} = best; %#ok<AGROW>
        if ~isnan(best.ch)
            x = fillmissing(double(X(eIdx(best.ch), :)), 'linear', 'EndValues', 'nearest');
            x = resample(x - mean(x), 500, round(fs)); x = bandpass(x, [5 40], 500); x = (x - mean(x)) / std(x);
            n0 = max(1, floor(numel(x) / 2) - 2500); n1 = min(numel(x), n0 + 5000);
            nexttile(tl); plot((n0:n1) / 500, best.sgn * x(n0:n1), 'k'); hold on; yline(best.thr, 'r');
            title(sprintf('ECG best: %s  %.0f/min  margin %.1f', best.spec, best.bpm, best.margin), 'FontSize', 8);
        end

        % ---- macros ----
        mIdx = find(contains(labs, 'macro'));
        for k = 1:numel(mIdx)
            x = double(X(mIdx(k), :)); x = x(~isnan(x));
            hi = max(x); lo = min(x);
            pinned = abs(x - hi) < 1e-9 | abs(x - lo) < 1e-9;
            longest = maxRun(pinned) / fs;
            rail = mean(pinned) >= 0.02 || longest >= 5;
            z = (x - median(x)) / (1.4826 * mad(x, 1) + eps);
            sp = countBeats(abs(z), 10, round(fs / 10)) / (numel(x) / fs / 60);
            rows(end + 1, :) = {recName, 'macro', labs{mIdx(k)}, mean(pinned), longest, sp, ternStr(rail, 'RAILING', '')}; %#ok<AGROW>
            if rail, macroRail{end + 1} = labs{mIdx(k)}; end %#ok<AGROW>
            spikeRates(end + 1) = sp; %#ok<AGROW>
        end
        exportgraphics(fig, fullfile(outDir, sprintf('%s_%s_params.png', tag, recName)), 'Resolution', 90);
        close(fig);
        clear X cd
    end
    T = cell2table(rows, 'VariableNames', {'recording', 'role', 'channel', 'v1', 'v2', 'v3', 'note'});
    writetable(T, fullfile(outDir, [tag '_params.csv']));

    % ---- session verdict ----
    fid = fopen(fullfile(outDir, [tag '_params.txt']), 'w'); c = onCleanup(@() fclose(fid));
    out = @(varargin) fprintf(fid, [varargin{1} '\n'], varargin{2:end});
    labsR = unique({rspSummary.label}, 'stable');
    worst = zeros(size(labsR)); votes = zeros(size(labsR));
    for k = 1:numel(labsR)
        m = strcmp({rspSummary.label}, labsR{k});
        worst(k) = min([rspSummary(m).respFrac]);
        votes(k) = sum([rspSummary(m).vote]);
    end
    if ~isempty(labsR)
        [~, kb] = max(worst);
        flip = sign(votes(kb)); if flip == 0, flip = 1; end
        out('rspIDX %d (%s): worst respFrac %.2f; polarity votes %+d -> rspFlip %+d%s', kb, labsR{kb}, ...
            worst(kb), votes(kb), flip, ternStr(votes(kb) == 0, ' (NO CLEAR VOTE - default +1)', ''));
        for k = 1:numel(labsR), out('   %s: worst respFrac %.2f, vote sum %+d', labsR{k}, worst(k), votes(k)); end
    end
    specs = cellfun(@(b) b.spec, ecgBest, 'uni', 0);
    out('beatSpec per recording: %s', strjoin(specs, ' | '));
    u = unique(specs(~cellfun('isempty', specs)));
    if isscalar(u), out('beatSpec %s (consistent across recordings)', u{1});
    elseif isempty(u), out('beatSpec NONE plausible (40-110/min) - ECG unusable or absent');
    else, out('beatSpec INCONSISTENT across recordings: %s', strjoin(u, ', ')); end
    out('macroRemove candidates (railing): %s', strjoin(unique(macroRail), ','));
    out('spike rate max %.2f/min -> spikeClean %s', max([spikeRates 0]), ternStr(max([spikeRates 0]) > 2, 'true', 'false'));
    out('EEG 10-20 labels in rows 1-32: %s -> hasEEG %s', mat2str(eegCount), ternStr(all(eegCount == 32), 'true', 'false'));
end

function [rise, fall] = riseFall(pk, tr)
    rise = []; fall = [];
    for i = 1:numel(pk)
        t0 = tr(find(tr < pk(i), 1, 'last'));
        t1 = tr(find(tr > pk(i), 1, 'first'));
        if ~isempty(t0) && ~isempty(t1)
            rise(end + 1) = pk(i) - t0; %#ok<AGROW>
            fall(end + 1) = t1 - pk(i); %#ok<AGROW>
        end
    end
    if isempty(rise), rise = NaN; fall = NaN; end
end

function n = countBeats(x, thr, refr)
    idx = find(x > thr);
    if isempty(idx), n = 0; else, n = 1 + sum(diff(idx) > refr); end
end

function L = maxRun(b)
    d = diff([0 b(:)' 0]);
    s = find(d == 1); e = find(d == -1);
    if isempty(s), L = 0; else, L = max(e - s); end
end

function s = ternStr(c, a, b)
    if c, s = a; else, s = b; end
end

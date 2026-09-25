function T = probeMontage(atlasDir, suffix, outDir, varargin)
%PROBEMONTAGE  Signal-based channel-role probe for one Neuralynx/Atlas recording.
%
%   T = probeMontage(atlasDir, suffix, outDir)
%   T = probeMontage(..., 'winSec', 120, 'tag', 'myLabel')
%
%   Reads a window (default 120 s, centred) of EVERY CSC<n><suffix>.ncs file in
%   atlasDir that holds data, straight from the .ncs records (no FieldTrip),
%   and scores each channel for the roles a LoadData channel map assigns:
%     respFrac   0.1-0.7 Hz power / 0.1-45 Hz power       (respiration: high)
%     respAC     peak autocorr of the <1 Hz trace at 2-12 s lag, respBPM its rate
%     ecgKurt    kurtosis of the 5-40 Hz trace             (ECG: high, spiky)
%     ecgAC      peak autocorr of the 5-40 Hz envelope at 0.4-1.5 s, ecgBPM its rate
%     alphaFrac  8-12 Hz / 1-45 Hz power                   (posterior scalp EEG)
%     lineFrac   58-62 Hz / 1-100 Hz power                 (unconnected / noisy)
%     stepRate   large sample-to-sample jumps per minute   (photodiode / DAQ)
%     nbrCorr    max |r| (1-40 Hz) with CSC n-1 / n+1       (contiguous EEG / macro blocks)
%   suffix: '' for the first recording, '_0001', ... for later ones.
%
%   Writes <outDir>\probe_<tag>.csv plus two figures: probe_<tag>_features.png
%   (per-channel feature bars + the channel correlation matrix, which shows the
%   EEG / macro / micro blocks) and probe_<tag>_traces.png (30-s traces of the
%   best respiration, ECG, event and alpha candidates). Read-only on atlasDir.
%
%   Used to verify the channel map of a LoadData script against the data
%   (montages differ between OBE eras and sometimes between recordings).

    p = inputParser;
    p.addParameter('winSec', 120);
    p.addParameter('tag', '');
    p.parse(varargin{:});
    winSec = p.Results.winSec;
    tag = p.Results.tag;
    if isempty(tag)
        [~, ts] = fileparts(atlasDir);
        tag = [ts strrep(suffix, '_', '-')];
        if isempty(suffix), tag = [ts '-none']; end
    end
    if ~isfolder(outDir), mkdir(outDir); end

    d = dir(fullfile(atlasDir, 'CSC*.ncs'));
    names = {d.name};
    if isempty(suffix)
        keep = ~cellfun('isempty', regexp(names, '^CSC\d+\.ncs$', 'once'));
    else
        keep = ~cellfun('isempty', regexp(names, ['^CSC\d+' regexptranslate('escape', suffix) '\.ncs$'], 'once'));
    end
    d = d(keep);
    num = cellfun(@(s) str2double(regexp(s, '^CSC(\d+)', 'tokens', 'once')), {d.name});
    [num, ord] = sort(num);
    d = d(ord);
    assert(~isempty(d), 'probeMontage: no CSC*%s.ncs files in %s', suffix, atlasDir);

    fsDs = 250;
    nCh = numel(d);
    X = cell(nCh, 1);
    rec = struct('csc', num2cell(num(:)), 'file', {d.name}', 'bytes', num2cell([d.bytes]'), ...
                 'fs', NaN, 'durMin', NaN, 'rmsUV', NaN, 'respFrac', NaN, 'respAC', NaN, ...
                 'respBPM', NaN, 'ecgKurt', NaN, 'ecgAC', NaN, 'ecgBPM', NaN, 'alphaFrac', NaN, ...
                 'lineFrac', NaN, 'stepRate', NaN, 'nbrCorr', NaN);
    for k = 1:nCh
        if d(k).bytes < 16384 + 1044 * 50, continue; end
        [x, fs, durMin] = readNcsWindow(fullfile(atlasDir, d(k).name), winSec);
        rec(k).fs = fs; rec(k).durMin = durMin;
        if isempty(x) || std(x) == 0, rec(k).rmsUV = 0; continue; end
        x = x - mean(x);
        rec(k).rmsUV = rms(x);
        % line noise on the native-rate trace
        [P, f] = pwelch(x, round(2 * fs), [], [], fs);
        rec(k).lineFrac = bp(P, f, 58, 62) / max(bp(P, f, 1, 100), eps);
        xs = resample(x, fsDs, round(fs));
        X{k} = xs;
        [P, f] = pwelch(detrend(xs), 30 * fsDs, [], [], fsDs);
        rec(k).respFrac = bp(P, f, 0.1, 0.7) / max(bp(P, f, 0.1, 45), eps);
        rec(k).alphaFrac = bp(P, f, 8, 12) / max(bp(P, f, 1, 45), eps);
        % respiration periodicity
        [bL, aL] = butter(2, 1 / (fsDs / 2), 'low');
        r = filtfilt(bL, aL, detrend(xs));
        [rec(k).respAC, lag] = acPeak(r, fsDs, 2, 12);
        rec(k).respBPM = 60 / lag;
        % ECG
        [bB, aB] = butter(2, [5 40] / (fsDs / 2), 'bandpass');
        e = filtfilt(bB, aB, xs);
        rec(k).ecgKurt = kurtosis(e);
        env = abs(e); env = movmean(env, round(0.05 * fsDs));
        [rec(k).ecgAC, lagE] = acPeak(env - mean(env), fsDs, 0.4, 1.5);
        rec(k).ecgBPM = 60 / lagE;
        % photodiode / DAQ steps
        dx = abs(diff(x));
        rec(k).stepRate = sum(dx > 8 * median(dx + eps) & dx > 0.2 * (max(x) - min(x))) / (numel(x) / fs / 60);
    end
    % neighbour correlation (1-40 Hz) - contiguous blocks share signal
    [bN, aN] = butter(2, [1 40] / (fsDs / 2), 'bandpass');
    F = cell(nCh, 1);
    for k = 1:nCh
        if ~isempty(X{k}), F{k} = filtfilt(bN, aN, X{k}); end
    end
    for k = 1:nCh
        if isempty(F{k}), continue; end
        c = [];
        for j = [k - 1, k + 1]
            if j >= 1 && j <= nCh && ~isempty(F{j}) && num(j) == num(k) + (j - k) && numel(F{j}) == numel(F{k})
                c(end + 1) = abs(corr(F{k}(:), F{j}(:))); %#ok<AGROW>
            end
        end
        if ~isempty(c), rec(k).nbrCorr = max(c); end
    end
    T = struct2table(rec);
    writetable(T, fullfile(outDir, ['probe_' tag '.csv']));

    % ---------- figure 1: features + correlation matrix ----------
    has = ~cellfun('isempty', F);
    fig = figure('Visible', 'off', 'Position', [50 50 1800 1100]);
    feats = {'rmsUV', 'respFrac', 'ecgKurt', 'alphaFrac', 'nbrCorr', 'stepRate'};
    for i = 1:numel(feats)
        subplot(numel(feats) + 3, 1, i);
        v = T.(feats{i}); if strcmp(feats{i}, 'rmsUV'), v = log10(v + 1); end
        bar(T.csc, v, 1, 'EdgeColor', 'none'); xlim([0 max(T.csc) + 1]);
        ylabel(strrep(feats{i}, 'rmsUV', 'log10 rms'), 'FontSize', 7); set(gca, 'FontSize', 7);
        if i == 1, title(sprintf('probeMontage %s  (%s)', tag, atlasDir), 'Interpreter', 'none'); end
    end
    subplot(numel(feats) + 3, 1, numel(feats) + 1:numel(feats) + 3);
    idx = find(has);
    if numel(idx) > 1
        M = zeros(numel(idx));
        L = min(cellfun(@numel, F(idx)));
        A = cell2mat(cellfun(@(v) v(1:L), F(idx)', 'uni', 0));
        M = abs(corr(A));
        imagesc(M, [0 1]); colorbar; axis square;
        tk = 1:max(1, round(numel(idx) / 40)):numel(idx);
        set(gca, 'XTick', tk, 'XTickLabel', T.csc(idx(tk)), 'YTick', tk, 'YTickLabel', T.csc(idx(tk)), 'FontSize', 6);
        xtickangle(90); title('|r| 1-40 Hz between channels with data (axis = CSC number)');
    end
    exportgraphics(fig, fullfile(outDir, ['probe_' tag '_features.png']), 'Resolution', 110);
    close(fig);

    % ---------- figure 2: candidate traces ----------
    fig = figure('Visible', 'off', 'Position', [50 50 1600 1200]);
    groups = {'respFrac', 3, 'respiration candidates (highest respFrac x respAC)'; ...
              'ecgKurt', 3, 'ECG candidates (highest ecgKurt)'; ...
              'stepRate', 2, 'event / photodiode candidates (highest stepRate)'; ...
              'alphaFrac', 2, 'alpha candidates (highest alphaFrac)'};
    row = 0; nRows = sum(cell2mat(groups(:, 2)));
    t = (0:30 * fsDs - 1) / fsDs;
    for g = 1:size(groups, 1)
        score = T.(groups{g, 1});
        if strcmp(groups{g, 1}, 'respFrac'), score = score .* max(T.respAC, 0); end
        score(~has) = -Inf; score(isnan(score)) = -Inf;
        [~, o] = sort(score, 'descend');
        for j = 1:groups{g, 2}
            row = row + 1;
            subplot(nRows, 1, row);
            k = o(j);
            if isinf(score(k)), continue; end
            v = X{k}; mid = floor(numel(v) / 2);
            seg = v(max(1, mid - 15 * fsDs + 1):min(numel(v), mid + 15 * fsDs));
            plot(t(1:numel(seg)), seg, 'k');
            title(sprintf('%s | CSC%d  respFrac %.2f respBPM %.1f ecgKurt %.1f ecgBPM %.0f alpha %.2f steps/min %.1f', ...
                groups{g, 3}, T.csc(k), T.respFrac(k), T.respBPM(k), T.ecgKurt(k), T.ecgBPM(k), ...
                T.alphaFrac(k), T.stepRate(k)), 'FontSize', 7, 'Interpreter', 'none');
            set(gca, 'FontSize', 6);
        end
    end
    xlabel('s (30-s window from the middle of the probe window)');
    exportgraphics(fig, fullfile(outDir, ['probe_' tag '_traces.png']), 'Resolution', 100);
    close(fig);
    fprintf('probeMontage %s: %d files, %d with data -> %s\n', tag, nCh, sum(has), outDir);
end

function v = bp(P, f, lo, hi)
    v = sum(P(f >= lo & f <= hi));
end

function [pk, lagSec] = acPeak(x, fs, loSec, hiSec)
    x = x(:) - mean(x);
    maxLag = round(hiSec * fs);
    c = xcorr(x, maxLag, 'coeff');
    c = c(maxLag + 1:end);            % lags 0..maxLag
    lags = (0:maxLag)' / fs;
    w = lags >= loSec & lags <= hiSec;
    [pk, i] = max(c(w));
    lw = lags(w); lagSec = lw(i);
    if isempty(pk), pk = NaN; lagSec = NaN; end
end

function [x, fs, durMin] = readNcsWindow(fn, winSec)
    % Neuralynx .ncs: 16384-byte ASCII header, then records of
    % uint64 ts, uint32 chan, uint32 fs, uint32 nValid, int16[512]  (1044 bytes)
    fid = fopen(fn, 'r', 'ieee-le');
    c = onCleanup(@() fclose(fid));
    hdr = fread(fid, 16384, '*char')';
    fs = hval(hdr, 'SamplingFrequency');
    bv = hval(hdr, 'ADBitVolts');
    inv = regexp(hdr, '-InputInverted\s+(\w+)', 'tokens', 'once');
    fseek(fid, 0, 'eof'); nRec = floor((ftell(fid) - 16384) / 1044);
    durMin = nRec * 512 / fs / 60;
    need = min(nRec, ceil(winSec * fs / 512));
    first = max(0, floor((nRec - need) / 2));
    fseek(fid, 16384 + first * 1044 + 20, 'bof');
    raw = fread(fid, [512, need], '512*int16=>double', 1044 - 1024);
    x = raw(:) * bv * 1e6;                         % microvolts
    if ~isempty(inv) && strcmpi(inv{1}, 'True'), x = -x; end
end

function v = hval(hdr, key)
    tok = regexp(hdr, ['-' key '\s+([-+0-9.eE]+)'], 'tokens', 'once');
    if isempty(tok), v = NaN; else, v = str2double(tok{1}); end
end

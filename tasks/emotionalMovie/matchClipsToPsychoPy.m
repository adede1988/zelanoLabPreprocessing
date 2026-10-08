function [TTL, chk] = matchClipsToPsychoPy(od, P, csvPath, figDir)
%MATCHCLIPSTOPSYCHOPY  Photodiode clip table checked against the PsychoPy clip log.
%
%   [TTL, chk] = matchClipsToPsychoPy(od, P, csvPath, figDir)
%
%   od       the raw-rate outDat of emotionalMovieTask_makeOutDat (.data / .labels
%            with the 'event' photodiode row, .fs, .sessID)
%   P        applyParams('EmotionalMovieTask', id) (P.pd photodiode parameters)
%   csvPath  the session's PsychoPy <id>_emotionalMovieTask_<datetime>.csv (one row
%            per clip: fileName, group = neut / happy / sad, photoDiode1.started =
%            first photodiode flash on the PsychoPy clock)
%   figDir   QC figure folder
%
%   The photodiode pulse-count grammar (1 / 2 / 3 pulses = neutral / happy / sad,
%   detect_ttls_emotionalMovieTask) depends on a z threshold, and a noisy event
%   channel produces spurious single pulses ("neutral" clips) or merged groups
%   (wrong valence): with the default zthresh -2 the 2026-10-06 sessions gave 248 /
%   241 clips for 180 played. The PsychoPy log is the ground truth for WHICH clips
%   were played and in what order, so:
%     1. detection runs at P.pd.zthresh and at -2.5 / -3 / -3.5 / -4;
%     2. for each, the PsychoPy photoDiode1.started times are aligned to the
%        detected onsets (best offset over candidate pairs, then a linear fit
%        for clock drift) and every PsychoPy clip is matched to the nearest
%        detected onset within 0.3 s;
%     3. the threshold with the most matched clips whose pulse count agrees with
%        the PsychoPy valence (fewest unmatched detections on ties) is kept;
%     4. detections without a PsychoPy clip are dropped, valence comes from the
%        PsychoPy log (pulse-count disagreements are counted), clipEnd is
%        recomputed with the legacy rule (next onset - P.pd.clipEndGapSec; NaN
%        for the final clip).
%   Errors when fewer than 95% of the PsychoPy clips can be matched.
%
%   Returns TTL in the makeOutDat convention (fs_target samples: clipOnset,
%   clipEnd, nPulses, valence) plus psychopyIdx / fileName / nPulsesDetected, and chk (thresholds
%   tried, chosen one, counts, offset/drift, residuals) for outDat.clipCheck. Saves
%   <id>_movieClipMatch.png.

    T = readtable(csvPath, 'VariableNamingRule', 'preserve', 'Delimiter', ',');
    T = T(~cellfun(@isempty, T.fileName), :);
    g = lower(string(T.group));
    g(g == "neut") = "neutral";
    assert(all(ismember(g, ["neutral", "happy", "sad"])), 'matchClipsToPsychoPy:group', ...
        '%s: unexpected group values in %s', od.sessID, csvPath);
    c = toNum(T.('photoDiode1.started'));
    ok = isfinite(c);
    T = T(ok, :); g = g(ok); c = c(ok);
    nC = numel(c);

    fsT = P.fs_target;
    ths = unique([P.pd.zthresh, -2.5, -3, -3.5, -4], 'stable');
    tmpDir = fullfile(tempdir, 'movieClipMatch'); if ~isfolder(tmpDir), mkdir(tmpDir); end
    best = []; trRows = zeros(0, 5);
    for k = 1:numel(ths)
        Pk = P; Pk.pd.zthresh = ths(k);
        D = detect_ttls_emotionalMovieTask(od, Pk, tmpDir);
        d = D.clipOnset / fsT;                                   % detected onsets, s
        [mi, fit, res] = alignTimes(c, d);
        matched = ~isnan(mi);
        agree = matched;
        agree(matched) = D.valence(mi(matched)) == g(matched);
        nUn = numel(d) - sum(matched);
        trRows(end+1, :) = [ths(k), numel(d), sum(matched), sum(agree), nUn]; %#ok<AGROW>
        score = [sum(agree), -nUn];
        if isempty(best) || score(1) > best.score(1) || (score(1) == best.score(1) && score(2) > best.score(2))
            best = struct('score', score, 'th', ths(k), 'D', D, 'mi', mi, 'fit', fit, 'res', res, 'agree', agree);
        end
    end
    tried = array2table(trRows, 'VariableNames', {'zthresh', 'nDetected', 'nMatched', 'nAgree', 'nUnmatched'});
    fprintf('%s photodiode vs PsychoPy (%d clips):\n', od.sessID, nC); disp(tried)

    mi = best.mi; matched = ~isnan(mi);
    assert(sum(matched) >= 0.95 * nC, 'matchClipsToPsychoPy:incomplete', ...
        '%s: only %d of %d PsychoPy clips matched a photodiode onset (best zthresh %g) - inspect the event channel', ...
        od.sessID, sum(matched), nC, best.th);

    D = best.D;
    TTL = table();
    TTL.clipOnset = D.clipOnset(mi(matched));
    TTL.clipEnd   = [TTL.clipOnset(2:end) - round(P.pd.clipEndGapSec * fsT); NaN];
    TTL.valence   = g(matched);
    % nPulses is the valence code downstream (bmObj col 12: 1 neutral / 2 happy / 3 sad):
    % it follows the PsychoPy valence; the detected pulse count is kept alongside
    code = zeros(sum(matched), 1);
    code(TTL.valence == "neutral") = P.pd.numNeu;
    code(TTL.valence == "happy")   = P.pd.numPos;
    code(TTL.valence == "sad")     = P.pd.numNeg;
    TTL.nPulses   = code;
    TTL.nPulsesDetected = D.nPulses(mi(matched));
    TTL.psychopyIdx = find(matched);
    TTL.fileName  = string(T.fileName(matched));

    chk = struct();
    chk.csvFile = csvPath;
    chk.nPsychoPy = nC;
    chk.tried = tried;
    chk.zthresh = best.th;
    chk.nDetected = height(D);
    chk.nMatched = sum(matched);
    chk.nDroppedDetections = height(D) - sum(matched);
    chk.nValenceFromPsychoPy = sum(matched & ~best.agree);   % pulse count disagreed with the log
    chk.offsetSec = best.fit(1);
    chk.driftPPM = best.fit(2) * 1e6;
    chk.residualMs = 1000 * best.res(matched);
    chk.note = ['clips = PsychoPy clips matched to photodiode onsets within 0.3 s; valence from the PsychoPy log; ' ...
                'detections without a PsychoPy clip dropped (matchClipsToPsychoPy)'];
    fprintf('%s: kept %d clips (zthresh %g; %d detections dropped; %d valences taken from PsychoPy over the pulse count); residual median %.0f ms, max %.0f ms\n', ...
        od.sessID, chk.nMatched, chk.zthresh, chk.nDroppedDetections, chk.nValenceFromPsychoPy, ...
        median(abs(chk.residualMs)), max(abs(chk.residualMs)));

    % QC figure: matched / unmatched onsets and timing residuals
    fig = figure('Visible', 'off', 'Position', [0 0 1400 600], 'Color', 'w');
    ax1 = subplot(2, 1, 1); hold(ax1, 'on');
    d = D.clipOnset / fsT;
    un = true(numel(d), 1); un(mi(matched)) = false;
    cols = struct('neutral', [0.1 0.6 0.1], 'happy', [0.1 0.3 0.9], 'sad', [0.85 0.1 0.1]);
    for v = ["neutral", "happy", "sad"]
        m = TTL.valence == v;
        plot(ax1, TTL.clipOnset(m) / fsT / 60, ones(sum(m), 1), '|', 'Color', cols.(char(v)), 'MarkerSize', 22, 'LineWidth', 1.2);
    end
    plot(ax1, d(un) / 60, 0.5 * ones(sum(un), 1), 'kx', 'MarkerSize', 8, 'LineWidth', 1.2);
    ylim(ax1, [0 1.5]); yticks(ax1, [0.5 1]); yticklabels(ax1, {'dropped', 'kept'}); grid(ax1, 'on');
    title(ax1, sprintf(['%s: %d PsychoPy clips -> %d kept (green neutral / blue happy / red sad), %d photodiode ' ...
        'detections dropped (x); zthresh %g'], od.sessID, nC, chk.nMatched, chk.nDroppedDetections, chk.zthresh), 'Interpreter', 'none');
    ax2 = subplot(2, 1, 2);
    plot(ax2, TTL.clipOnset / fsT / 60, chk.residualMs, 'k.', 'MarkerSize', 10);
    grid(ax2, 'on'); xlabel(ax2, 'minutes'); ylabel(ax2, 'onset - aligned PsychoPy time (ms)');
    title(ax2, sprintf('PsychoPy clock -> recording: offset %.3f s, drift %.0f ppm; %d valences differ from the pulse count', ...
        chk.offsetSec, chk.driftPPM, chk.nValenceFromPsychoPy));
    if ~isfolder(figDir), mkdir(figDir); end
    saveas(fig, fullfile(figDir, [od.sessID '_movieClipMatch.png']));
    close(fig);
end

function [mi, fit, res] = alignTimes(c, d)
% match PsychoPy times c (s, its own clock) to detected onsets d (s, recording):
% best single offset over candidate pairs, then a linear fit d = a + (1 + b) * c
    tol = 0.3;
    mi = nan(numel(c), 1); fit = [NaN NaN]; res = nan(numel(c), 1);
    if isempty(d), return; end
    nI = min(numel(d), 40); nJ = min(numel(c), 40);
    bestN = -1; bestOff = 0;
    for i = 1:nI
        for j = 1:nJ
            off = d(i) - c(j);
            n = countMatches(c + off, d, tol);
            if n > bestN, bestN = n; bestOff = off; end
        end
    end
    a = bestOff; b = 0;
    for it = 1:2
        pred = a + (1 + b) * c;
        [mi, dist] = nearestWithin(pred, d, tol);
        m = ~isnan(mi);
        if sum(m) >= 3
            pf = polyfit(c(m), d(mi(m)) - c(m), 1);   % d - c = a + b*c
            b = pf(1); a = pf(2);
        end
    end
    pred = a + (1 + b) * c;
    [mi, dist] = nearestWithin(pred, d, tol);
    res = dist;
    fit = [a b];
end

function n = countMatches(p, d, tol)
    [mi] = nearestWithin(p, d, tol);
    n = sum(~isnan(mi));
end

function [mi, dist] = nearestWithin(p, d, tol)
% one-to-one nearest matches within tol (greedy by distance)
    mi = nan(numel(p), 1); dist = nan(numel(p), 1);
    idx = interp1(d, 1:numel(d), p, 'nearest', 'extrap');
    if numel(d) == 1, idx = ones(size(p)); end
    dd = d(idx) - p;
    cand = find(abs(dd) <= tol);
    [~, o] = sort(abs(dd(cand)));
    used = false(numel(d), 1);
    for k = cand(o)'
        if ~used(idx(k)), mi(k) = idx(k); dist(k) = dd(k); used(idx(k)) = true; end
    end
end

function x = toNum(v)
    if iscell(v) || isstring(v), x = str2double(string(v)); else, x = double(v); end
end

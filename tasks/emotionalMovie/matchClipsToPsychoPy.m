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
%            first photodiode flash on the PsychoPy clock, movie.started /
%            movie.stopped = the clip's first frame / the first screen flip after
%            its routine ended (= the next clip's movie.started, ~0.3 s after
%            playback ends), and the conditions-file columns vidLen / valence /
%            arousal / impact)
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
%        for clock drift - piecewise, because the mapping can step between two
%        clips; see alignTimes) and every PsychoPy clip is matched to the nearest
%        detected onset within 0.3 s of its own segment's prediction;
%     3. the threshold with the most matched clips whose pulse count agrees with
%        the PsychoPy valence (fewest unmatched detections on ties) is kept;
%     4. detections without a PsychoPy clip are dropped, valence comes from the
%        PsychoPy log (pulse-count disagreements are counted), clipEnd is
%        recomputed with the legacy rule (next onset - P.pd.clipEndGapSec, which
%        lands ~0.27 s after the clip's movieStop). Two exceptions end a clip at
%        its own movieStop instead (NaN when the log has no usable movie.stopped):
%        the last kept clip (no next onset), and a kept clip whose next PsychoPy
%        clip was not matched (the legacy window would run through that unmatched
%        clip and give its breaths this clip's identity and norms).
%   Each clip's own PsychoPy movie.started / movie.stopped times are placed on
%   the recording relative to that clip's own photodiode onset (movieStart /
%   movieStop, clamped to the recording), so a clock step cannot shift them. The task starts the movie with the trial routine
%   and the photodiode flash 2 s into it, so clipOnset (the flash) is ~1.6-1.9 s
%   after movieStart; the clip windows (clipOnset..clipEnd) keep the legacy
%   definition.
%   Errors when fewer than 95% of the PsychoPy clips can be matched.
%
%   The stimulus attributes of each kept clip are copied from the log: vidLenSec
%   (the clip's length in s, DEVO2 Lengthofmoviesec) and normValence /
%   normArousal / normImpact. The norm* columns are NOT the participant's
%   ratings (the task collects none): they are the DEVO2 per-clip mean ratings
%   (1-9 scales; valence 1 unhappy - 9 happy, arousal 1 calm - 9 excited,
%   impact 1 no impact - 9 intense impact; Davidson et al. 2025, Behav Res
%   Methods 57:161) that configFileCreation.R copied into the task's conditions
%   file (EmotionalMovieTask repo, configFile1.csv). The norm prefix avoids a
%   clash with TTL.valence, the neutral / happy / sad category.
%
%   Returns TTL in the makeOutDat convention (fs_target samples: clipOnset,
%   clipEnd, nPulses, valence) plus nPulsesDetected / psychopyIdx / fileName /
%   vidLenSec / normValence / normArousal / normImpact / movieStart / movieStop
%   (fs_target samples), and chk (thresholds tried,
%   chosen one, counts, offset/drift, residuals, final-clip end) for
%   outDat.clipCheck. Saves <id>_movieClipMatch.png.

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
    best = []; trRows = zeros(0, 6);
    for k = 1:numel(ths)
        Pk = P; Pk.pd.zthresh = ths(k);
        D = detect_ttls_emotionalMovieTask(od, Pk, tmpDir);
        d = D.clipOnset / fsT;                                   % detected onsets, s
        [mi, fit, res, segs, segOf, F] = alignTimes(c, d);
        matched = ~isnan(mi);
        agree = matched;
        agree(matched) = D.valence(mi(matched)) == g(matched);
        nUn = numel(d) - sum(matched);
        trRows(end+1, :) = [ths(k), numel(d), sum(matched), sum(agree), nUn, height(segs)]; %#ok<AGROW>
        score = [sum(agree), -nUn];
        if isempty(best) || score(1) > best.score(1) || (score(1) == best.score(1) && score(2) > best.score(2))
            best = struct('score', score, 'th', ths(k), 'D', D, 'mi', mi, 'fit', fit, 'res', res, 'agree', agree, ...
                'segs', segs, 'segOf', segOf, 'F', F);
        end
    end
    tried = array2table(trRows, 'VariableNames', {'zthresh', 'nDetected', 'nMatched', 'nAgree', 'nUnmatched', 'nClockSegments'});
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
    % stimulus attributes from the conditions file (DEVO2 norms, not the
    % participant's ratings - see the header)
    TTL.vidLenSec   = toNum(T.vidLen(matched));
    TTL.normValence = toNum(T.valence(matched));
    TTL.normArousal = toNum(T.arousal(matched));
    TTL.normImpact  = toNum(T.impact(matched));

    % each clip's own start / stop on the PsychoPy clock (movie.started /
    % movie.stopped), placed relative to the clip's OWN photodiode onset (so a
    % step in the PsychoPy -> recording mapping cannot shift them) and clamped to
    % the recording (NaN kept). The task starts the movie with the trial routine
    % but the photodiode flash (clipOnset) 2 s into it, so movieStart is ~1.6-1.9 s
    % before clipOnset; the legacy clipEnd (next flash - P.pd.clipEndGapSec)
    % lands ~0.1-0.3 s after movieStop.
    nSampT = floor(size(od.data, 2) / (od.fs / fsT));
    driftK = best.F(best.segOf(matched), 2);           % clock-rate term of each kept clip's segment
    TTL.movieStart = toRec(T, 'movie.started', TTL.psychopyIdx, c, TTL.clipOnset, driftK, fsT, nSampT);
    TTL.movieStop  = toRec(T, 'movie.stopped', TTL.psychopyIdx, c, TTL.clipOnset, driftK, fsT, nSampT);
    % a kept clip whose next PsychoPy clip went unmatched: the legacy window
    % (next KEPT onset - gap) would run through the unmatched clip - end it at
    % its own movieStop instead
    gapNext = [diff(TTL.psychopyIdx) > 1; false] & isfinite(TTL.movieStop);
    TTL.clipEnd(gapNext) = TTL.movieStop(gapNext);
    % the last kept clip has no next onset: end it at its movieStop
    lastEndSrc = "none";
    if isfinite(TTL.movieStop(end))
        TTL.clipEnd(end) = TTL.movieStop(end);
        lastEndSrc = "psychopy movie.stopped";
    end

    chk = struct();
    chk.csvFile = csvPath;
    chk.nPsychoPy = nC;
    chk.tried = tried;
    chk.zthresh = best.th;
    chk.nDetected = height(D);
    chk.nMatched = sum(matched);
    chk.nDroppedDetections = height(D) - sum(matched);
    chk.nValenceFromPsychoPy = sum(matched & ~best.agree);   % pulse count disagreed with the log
    chk.offsetSec = best.fit(1);                    % largest clock segment
    chk.driftPPM = best.fit(2) * 1e6;
    chk.clockSegments = best.segs;                  % PsychoPy -> recording mapping, piecewise (alignTimes)
    chk.residualMs = 1000 * best.res(matched);      % each clip vs its own segment's mapping
    chk.lastClipEndSource = lastEndSrc;
    chk.nEndAtMovieStopBeforeGap = sum(gapNext);   % kept clips followed by an unmatched clip
    if lastEndSrc == "none"
        lastNote = 'last clip end NaN (no usable PsychoPy movie.stopped); ';
    else
        lastNote = 'last clip ends at its movieStop; ';
    end
    chk.note = ['clips = PsychoPy clips matched to photodiode onsets within 0.3 s; valence from the PsychoPy log; ' ...
                'detections without a PsychoPy clip dropped; movieStart / movieStop = PsychoPy movie.started / ' ...
                'movie.stopped on the recording (clipOnset = photodiode flash, ~1.6-1.9 s after movieStart); ' ...
                lastNote sprintf('%d clips followed by an unmatched clip end at their movieStop; ', chk.nEndAtMovieStopBeforeGap) ...
                'vidLenSec = clip length (s); normValence / normArousal / normImpact = DEVO2 per-clip mean ratings ' ...
                'from the conditions file, not participant ratings (matchClipsToPsychoPy)'];
    fprintf('%s: kept %d clips (zthresh %g; %d detections dropped; %d valences taken from PsychoPy over the pulse count); residual median %.0f ms, max %.0f ms; %d clips end at movieStop before an unmatched clip; last clip end: %s\n', ...
        od.sessID, chk.nMatched, chk.zthresh, chk.nDroppedDetections, chk.nValenceFromPsychoPy, ...
        median(abs(chk.residualMs)), max(abs(chk.residualMs)), chk.nEndAtMovieStopBeforeGap, lastEndSrc);
    if height(chk.clockSegments) > 1
        fprintf('%s: the PsychoPy -> recording mapping steps between clips (%d clock segments):\n', od.sessID, height(chk.clockSegments));
        disp(chk.clockSegments)
    end

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
    segTxt = '';
    if height(chk.clockSegments) > 1
        segTxt = sprintf('; %d clock segments, steps after clips %s', height(chk.clockSegments), ...
            strjoin(string(chk.clockSegments.lastClip(1:end-1)'), ', '));
        xline(ax2, TTL.clipOnset(ismember(TTL.psychopyIdx, chk.clockSegments.firstClip(2:end))) / fsT / 60, 'r--');
    end
    title(ax2, sprintf('PsychoPy clock -> recording: offset %.3f s, drift %.0f ppm (largest segment)%s; %d valences differ from the pulse count', ...
        chk.offsetSec, chk.driftPPM, segTxt, chk.nValenceFromPsychoPy));
    if ~isfolder(figDir), mkdir(figDir); end
    saveas(fig, fullfile(figDir, [od.sessID '_movieClipMatch.png']));
    close(fig);
end

function [mi, fit, res, segs, segOf, F] = alignTimes(c, d)
% match PsychoPy times c (s, its own clock) to detected onsets d (s, recording).
% The PsychoPy -> recording mapping d = a + (1 + b) * c can STEP between two
% clips and stay constant on either side (2026-08 sessions: 260806_MM -0.85 s
% after clip 43, 260807_GP +0.35 s after clip 134; the recordings have no gaps),
% so it is fitted piecewise:
%   1. discovery: fit one mapping to the clips not yet explained (best offset
%      over candidate pairs, then two linear refits); the clips it puts within
%      0.1 s of a detection form a segment; repeat on the rest (at most 4
%      segments of >= 5 clips each);
%   2. assignment: a changepoint dynamic programme over the clip sequence gives
%      each clip one segment's mapping (cost 0 for a detection within 0.1 s,
%      0.5 within 0.3 s, 1 for none; 4 per change), so segments are contiguous;
%   3. each segment's mapping is refitted on its own matched clips and every
%      clip is matched one-to-one to the nearest detection within 0.3 s of its
%      segment's prediction.
% A session without a step gives one segment = the former single linear fit.
% Returns fit = the largest segment's [a b], segs (one row per segment), segOf
% (segment of each clip) and F (each segment's [a b]).
    tol = 0.3; tight = 0.1; minSeg = 5; maxSeg = 4; lambda = 4;
    nC = numel(c);
    mi = nan(nC, 1); res = nan(nC, 1); fit = [NaN NaN]; segOf = nan(nC, 1);
    segs = table(); F = zeros(0, 2);
    if isempty(d), return; end
    left = true(nC, 1);
    for s = 1:maxSeg
        idx = find(left);
        if numel(idx) < minSeg, break; end
        f = fitOnce(c(idx), d, tol);
        if any(isnan(f)), break; end
        [m1, r1] = nearestWithin(f(1) + (1 + f(2)) * c(idx), d, tol);
        good = ~isnan(m1) & abs(r1) <= tight;
        if sum(good) < minSeg, break; end
        F(end+1, :) = f; %#ok<AGROW>
        left(idx(good)) = false;
    end
    if isempty(F), return; end
    for pass = 1:2
        segOf = assignSegments(c, d, F, tol, tight, lambda);
        pred = F(segOf, 1) + (1 + F(segOf, 2)) .* c;
        [mi, res] = nearestWithin(pred, d, tol);
        for s = 1:size(F, 1)                        % refit each segment on its matches
            m = segOf == s & ~isnan(mi);
            if sum(m) >= 3
                pf = polyfit(c(m), d(mi(m)) - c(m), 1);
                F(s, :) = [pf(2) pf(1)];
            end
        end
    end
    segOf = assignSegments(c, d, F, tol, tight, lambda);
    pred = F(segOf, 1) + (1 + F(segOf, 2)) .* c;
    [mi, res] = nearestWithin(pred, d, tol);
    % segments in clip order (a mapping can be reused after another one)
    runStart = [1; find(diff(segOf) ~= 0) + 1];
    runEnd = [runStart(2:end) - 1; nC];
    segs = table(runStart, runEnd, runEnd - runStart + 1, zeros(numel(runStart), 1), F(segOf(runStart), 1), ...
        1e6 * F(segOf(runStart), 2), nan(numel(runStart), 1), segOf(runStart), ...
        'VariableNames', {'firstClip', 'lastClip', 'nClips', 'nMatched', 'offsetSec', 'driftPPM', 'medianAbsResidualMs', 'mapping'});
    for r = 1:height(segs)
        k = segs.firstClip(r):segs.lastClip(r);
        segs.nMatched(r) = sum(~isnan(mi(k)));
        segs.medianAbsResidualMs(r) = 1000 * median(abs(res(k)), 'omitnan');
    end
    [~, big] = max(accumarray(segOf, 1, [size(F, 1) 1]));
    fit = F(big, :);
end

function segOf = assignSegments(c, d, F, tol, tight, lambda)
% changepoint DP: one mapping per clip, few changes along the clip sequence
    nC = numel(c); nS = size(F, 1);
    cost = ones(nC, nS);
    for s = 1:nS
        e = nearestDist(F(s, 1) + (1 + F(s, 2)) * c, d);
        cost(e <= tol, s) = 0.5;
        cost(e <= tight, s) = 0;
    end
    acc = cost(1, :); bp = zeros(nC, nS);
    for k = 2:nC
        [mn, am] = min(acc);
        newAcc = zeros(1, nS);
        for s = 1:nS
            if acc(s) <= mn + lambda
                newAcc(s) = acc(s) + cost(k, s); bp(k, s) = s;
            else
                newAcc(s) = mn + lambda + cost(k, s); bp(k, s) = am;
            end
        end
        acc = newAcc;
    end
    segOf = zeros(nC, 1);
    [~, segOf(nC)] = min(acc);
    for k = nC:-1:2, segOf(k - 1) = bp(k, segOf(k)); end
end

function f = fitOnce(c, d, tol)
% one linear mapping for clips c: best single offset over candidate pairs (every
% detection x the first 40 clips), then two linear refits
    f = [NaN NaN];
    nJ = min(numel(c), 40);
    bestN = -1; bestOff = 0;
    for i = 1:numel(d)
        for j = 1:nJ
            off = d(i) - c(j);
            n = sum(nearestDist(c + off, d) <= tol);
            if n > bestN, bestN = n; bestOff = off; end
        end
    end
    a = bestOff; b = 0;
    for it = 1:2
        [m1] = nearestWithin(a + (1 + b) * c, d, tol);
        m = ~isnan(m1);
        if sum(m) >= 3
            pf = polyfit(c(m), d(m1(m)) - c(m), 1);   % d - c = a + b*c
            b = pf(1); a = pf(2);
        end
    end
    f = [a b];
end

function e = nearestDist(p, d)
% distance from each p to its nearest detection (not one-to-one)
    if numel(d) == 1, e = abs(d - p); return; end
    idx = interp1(d, 1:numel(d), p, 'nearest', 'extrap');
    e = abs(d(idx) - p);
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

function s = toRec(T, col, idx, c, onset, drift, fsT, nSampT)
% PsychoPy-clock times of column col (rows idx) -> recording samples at fsT,
% anchored on each clip's own photodiode onset (onset, samples; c = its
% photoDiode1.started) with its segment's clock-rate term; clamped to
% [1, nSampT], NaN when absent
    s = NaN(numel(idx), 1);
    if ~ismember(col, T.Properties.VariableNames), return; end
    v = toNum(T.(col));
    s = round(onset + (v(idx) - c(idx)) .* (1 + drift) * fsT);
    s(s < 1) = 1;
    s(s > nSampT) = nSampT;
end

function x = toNum(v)
    if iscell(v) || isstring(v), x = str2double(string(v)); else, x = double(v); end
end

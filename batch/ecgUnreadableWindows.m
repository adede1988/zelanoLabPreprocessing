function [win, info] = ecgUnreadableWindows(heartBeats, fs, nSamp, opts)
%ECGUNREADABLEWINDOWS  Measure the stretches where the ECG gives no readable rhythm.
%
%   [win, info] = ecgUnreadableWindows(heartBeats, fs, nSamp)
%   [win, info] = ecgUnreadableWindows(heartBeats, fs, nSamp, opts)
%
%   A measurement tool (not a pipeline step): its output, rounded outward to
%   0.1 s, is what gets typed into config/applyParams.m as P.ecgExcludeSec for a
%   session whose reviewer asked for the unreadable-ECG breaths to be left out of
%   HRV (tasks_261014 task 7, 251110_Dupi_NMH_PC_2). shared/processECG and
%   shared/flagBadBreaths then honour those windows. Run it on the beats the
%   pipeline detected BEFORE any exclusion (outDat.heartBeats of a final made
%   without P.ecgExcludeSec), so the result is reproducible from the data.
%
%   heartBeats  detected beat sample indices (outDat.heartBeats)
%   fs          sample rate of those indices (Hz)
%   nSamp       recording length (samples)
%   win         [N x 2] unreadable windows, seconds from the recording start
%   info        struct: opts, medianIBI, ibiRange, readable (the [start end] s of
%               every readable interval), bursts (the [first last] beat s of every
%               pseudo-beat run), windowsRaw (merged windows before rounding:
%               [start end startInclusive endInclusive], see 5.), islandsAbsorbed,
%               totalSec
%
%   CRITERION ("the ECG is unreadable here" = no usable beat-to-beat rhythm):
%     1. An RR interval is READABLE when (a) it lies within +-ibiTol of the
%        session's median interval (physiological range for a participant at
%        rest; default +-40 %), and (b) at least one neighbouring interval is
%        also in that range and differs from it by <= dMax s (default 0.3 s):
%        a regular beat PAIR, which a burst of EMG pseudo-beats and a lone
%        misdetection do not give.
%     2. A stretch with no readable interval for >= gapSec (default 4 s, i.e.
%        more than ~3 consecutive missing beats) is UNREADABLE. Shorter holes
%        (an isolated missed or doubled beat) are NOT flagged: processECG's
%        interval filtering and interpolation already handle those.
%     3. A BURST of pseudo-beats is UNREADABLE however short: burstN (default 4)
%        or more consecutive intervals shorter than the physiological floor
%        (the low end of the range in 1.) means the detector was firing on an
%        EMG / movement burst. Some of the junk intervals around such a burst
%        can still land in the physiological range (so they pass processECG's
%        interval filter and make a within-breath HRV of artifact), which the
%        4-s hole rule of 2. does not see when the burst is ~1-3 s long
%        (251110_Dupi_NMH_PC_2, 335 s: 6 consecutive junk intervals in 1.3 s,
%        the neighbouring junk intervals 0.85 s and 1.11 s). The burst window
%        spans the first to the last beat of the run. Fewer consecutive short
%        intervals (an isolated doubled beat or a 2-3 beat spike in otherwise
%        readable ECG, e.g. 186-188 s, 363.6-364 s, 398 s in that session) are
%        NOT flagged: the real beat is still visible there.
%     4. A readable island shorter than islandSec (default 20 s, ~4 breaths)
%        between two unreadable windows is not trusted and is absorbed into one
%        window (a regular pair turning up by chance inside heavy movement).
%     5. Window edges, on the 0.1-s grid. processECG's test is inclusive (a beat
%        ON a window edge is dropped, and so is every interval touching it), so
%        the rounding depends on what the edge is:
%          - a hole's edge is the neighbouring READABLE beat (the last one before
%            it, the first one after it). That beat is not part of the problem, so
%            the window is rounded INWARD, strictly past it, and the beat and the
%            readable interval next to the hole stay in the data
%            (251110_Dupi_NMH_PC_2, 300.854 s: with the outward rounding that
%            kept [209.2 300.9] the clean beat was dropped and a breath whose
%            whole span is clean ECG lost its HRV);
%          - a burst's edges are its own first and last beat (junk), rounded
%            OUTWARD so they are inside;
%          - the recording start / end are inclusive;
%          - where windows merge, the outermost edge decides, and an edge that is
%            both (a hole ending on the beat that also ends a burst run, 30.148 s
%            in that session) counts as the burst's: inside.
%   Only beat times enter the criterion, so it is independent of which ECG
%   channel / beatSpec produced them; blanking (buildECGz) simply shows up as
%   missing beats.

    if nargin < 4, opts = struct(); end
    o = struct('ibiTol', 0.4, 'dMax', 0.3, 'gapSec', 4, 'islandSec', 20, 'burstN', 4);   % burstN = Inf: no burst rule
    fn = fieldnames(opts);
    for k = 1:numel(fn)
        assert(isfield(o, fn{k}), 'ecgUnreadableWindows: unknown option %s', fn{k});
        o.(fn{k}) = opts.(fn{k});
    end

    T  = nSamp / fs;
    bt = heartBeats(:)' / fs;
    ibi = diff(bt);
    assert(numel(ibi) >= 10, 'ecgUnreadableWindows: too few beats (%d)', numel(bt));
    med = median(ibi);
    rng = med * [1 - o.ibiTol, 1 + o.ibiTol];

    inr = ibi >= rng(1) & ibi <= rng(2);
    pairOK = abs(diff(ibi)) <= o.dMax & inr(1:end-1) & inr(2:end);   % interval i and i+1 form a regular pair
    readable = inr & ([false pairOK] | [pairOK false]);

    cv = [bt([readable false]); bt([false readable])]';                % [start end] (s) of readable intervals

    % Windows are [start end startIn endIn]: the last two say whether the edge is
    % INCLUSIVE (junk beats up to the edge: round outward) or sits on a readable
    % beat that has to stay outside (round inward). See 5. above.

    % holes between readable intervals (and at the recording edges) >= gapSec
    win = zeros(0, 4); prev = 0;
    for k = 1:size(cv, 1)
        if cv(k, 1) - prev >= o.gapSec, win(end+1, :) = [prev cv(k, 1) (prev <= 0) 0]; end %#ok<AGROW>
        prev = max(prev, cv(k, 2));
    end
    if T - prev >= o.gapSec, win(end+1, :) = [prev T (prev <= 0) 1]; end

    % bursts of pseudo-beats: >= burstN consecutive intervals below the floor
    short = ibi < rng(1);
    burst = zeros(0, 2); k = 1; nI = numel(short);
    while k <= nI
        if short(k)
            k2 = k;
            while k2 < nI && short(k2 + 1), k2 = k2 + 1; end
            if k2 - k + 1 >= o.burstN, burst(end+1, :) = [bt(k) bt(k2 + 1)]; end %#ok<AGROW>
            k = k2 + 1;
        else
            k = k + 1;
        end
    end
    win = sortrows([win; burst, ones(size(burst, 1), 2)], [1 -3 2]);

    % merge overlapping windows; absorb short readable islands between two
    % unreadable windows (the outermost edge decides inclusive / exclusive; an
    % edge shared by both is inclusive)
    nAbs = 0; k = 1;
    while k < size(win, 1)
        if win(k+1, 1) - win(k, 2) < o.islandSec
            if win(k+1, 1) > win(k, 2), nAbs = nAbs + 1; end   % a real island, not an overlap
            if win(k+1, 2) > win(k, 2)
                win(k, 2) = win(k+1, 2); win(k, 4) = win(k+1, 4);
            elseif win(k+1, 2) == win(k, 2)
                win(k, 4) = max(win(k, 4), win(k+1, 4));
            end
            win(k+1, :) = [];
        else
            k = k + 1;
        end
    end
    winRaw = win;

    % round to the 0.1-s grid (outward at an inclusive edge, strictly inward past
    % a readable beat), clamped to the recording
    if ~isempty(win)
        e = 1e-6;                                            % beat times sit on a 1/fs grid: a beat ON a grid line must still count as on it
        s = win(:, 1) * 10; en = win(:, 2) * 10;
        sRnd  = win(:, 3) .* floor(s + e)      + (1 - win(:, 3)) .* (floor(s + e) + 1);
        enRnd = win(:, 4) .* ceil(en - e)      + (1 - win(:, 4)) .* (ceil(en - e) - 1);
        win = [max(0, sRnd / 10), min(T, enRnd / 10)];
    else
        win = zeros(0, 2);
    end

    info = struct('opts', o, 'medianIBI', med, 'ibiRange', rng, 'readable', cv, 'bursts', burst, ...
                  'windowsRaw', winRaw, 'islandsAbsorbed', nAbs, 'totalSec', sum(diff(win, 1, 2)));
end

function [onsets, peaks, troughs] = findInhaleOnsets_zlp(resp, fs, peaks, troughs, method, r2Factor, r3Factor)
% r2Factor (default 0.75): rule-2 rise target as a fraction of local amplitude
% r3Factor (default 3): rule-3 slope-contrast ratio (max/min in -0.25..+0.5s)
%FINDINHALEONSETS_ZLP  Inhale onsets per trough->peak pair (QC round 3).
%
%   onsets = findInhaleOnsets_zlp(resp, fs, peaks, troughs, method)
%
%   resp   : detection trace (windowed-normalized), row vector
%   peaks/troughs : strictly alternating extrema (findAlternatingExtrema) -
%            bm-style sample indices, so this slots directly into the
%            breathMetrics flow in place of findRespiratoryPausesAndOnsets
%   method : 'slopeGate' | 'kneeBacktrack' | 'changepoint'
%
%   Morphology (lab definition): a true inhale onset is a FAST UPWARD
%   deflection beginning near zero - a sharp positive increase in slope while
%   the value sits well above the trough and below the peak. Zero crossings
%   alone fail (pauses hover around zero; onsets can start below zero).
%   Exactly one onset is returned per trough->peak pair; pairs are >=1.5 s
%   apart by the backbone's refractory.
%
%   Methods:
%     slopeGate     first SUSTAINED crossing of a slope threshold (20% of the
%                   window's max slope) within the amplitude mid-band
%                   (trough+15% .. peak-25% of the range)
%     kneeBacktrack from the steepest point of the rise, walk backward until
%                   slope falls below 15% of that maximum: the foot/knee of
%                   the fast rise
%     changepoint   two-line least-squares fit (flat-ish left segment, rising
%                   right segment); onset = breakpoint minimizing total
%                   residual with rightSlope > leftSlope (the principled
%                   version of slowBreathing's findInflectionUpward)

    resp = double(resp(:))';
    % slope on a 120-ms smoothed derivative (light - over-smoothing drags
    % onsets early, the ZL lesson)
    d = movmean([0, diff(resp)] * fs, round(0.12 * fs));

    % HARD ELIGIBILITY RULE (2026-08-28 review): a sample sitting more than
    % THETA below where the trace was 0.33 s earlier is mid-descent or just
    % landed in a trough - never an inhale onset. Candidates must satisfy
    % x(t) - x(t - 0.33 s) > -THETA (normalized units).
    LAG = round(0.33 * fs);
    THETA = 0.20;
    d33 = resp - [repmat(resp(1), 1, LAG), resp(1:end-LAG)];
    elig = d33 > -THETA;
    % rule 2 (2026-08-28, final form per review): within 0.4 s after a true
    % onset the trace must AT SOME POINT rise 0.75 x the LOCAL amplitude
    % scale above the onset value - agnostic to exactly when in that window.
    % Flat/drifting stretches can never qualify. Local scale = 30-s moving
    % std of the (already windowed-normalized) trace, so the threshold
    % adapts to residual amplitude variation.
    % rule 2's time window is PAIR-SCALED (2026-08-28: a fixed 0.4-s window
    % demands ~1.9 units/s of rise, which no slow breath can meet - whole
    % pairs got pruned and rates collapsed to ~3/min). The rise target stays
    % 0.75 x local amplitude; the window is max(0.4 s, 25% of the pair's
    % trough->peak duration), evaluated per pair below.
    Aloc = movstd(resp, round(30 * fs));
    % rule 3 (2026-08-28): the rise must be ACCELERATING at the onset - the
    % slope 0.25 s later must exceed 1.25x the ABSOLUTE slope at the mark (a
    % negative onset slope must be followed by a real positive rise, not a
    % shallower fall). Late placements past max slope fail by construction.
    % (windowed form, 2026-08-28: a fixed +0.25s offset was brittle to where
    % in the rise the acceleration peaks - counts dropped semi-randomly.
    % Like rule 2, test the WINDOW: slope must reach the factor at some
    % point within 0.5 s after the mark.)
    if nargin < 6 || isempty(r2Factor), r2Factor = 0.75; end
    if nargin < 7 || isempty(r3Factor), r3Factor = 3; end
    % rule 3 (2026-08-28 final form): slope CONTRAST across a window
    % straddling the mark (-0.25s..+0.5s): max slope must exceed r3Factor x
    % the min slope (clamped at +0.1 units/s - the min is ~0/negative at true
    % onsets, which is the point: flat-behind, steep-ahead passes easily even
    % when the mark is slightly late; uniform mid-rise and flat traces fail).
    % (2026-08-28 restructure: rule 3 is NOT a global gate - smooth
    % trough-to-peak sweeps have no flat/steep contrast anywhere, so gating
    % on it wrongly invalidated whole windows. It now refines knee placement
    % only, AFTER a knee is found - see the kneeBacktrack two-pass flow.)
    LB = round(0.25 * fs); LF = round(0.5 * fs);
    dMaxW = movmax(d, [LB LF]);
    dMinW = movmin(d, [LB LF]);
    r3v = dMaxW > r3Factor * max(dMinW, 0.1);
    valid = elig;                       % rules 1 (+2 per pair) gate candidates
    % rule 2 ABSOLUTE (2026-08-28 review): somewhere in the pair-scaled
    % window the trace must sit 0.4 normalized units above the candidate
    % (was multiplicative in local amplitude; r2Factor now IS the absolute
    % threshold, default raised 0.25 -> 0.4)
    if r2Factor == 0.25, r2Factor = 0.4; end
    pairValid = @(w) valid(w) & ...
        (movmax(resp(w), [0 max(round(0.4 * fs), round(0.25 * numel(w)))]) ...
         - resp(w)) > r2Factor;

    % SPURIOUS-PAIR PRUNING: a trough->peak window with NO dual-valid sample
    % is a false split of one breath (extrema over-detection) - eliminate
    % that trough and peak so the region absorbs into the adjacent breath.
    pruned = true;
    while pruned
        pruned = false;
        for k = 1:numel(peaks)
            t0 = troughs(troughs < peaks(k));
            if isempty(t0), continue; end
            t0 = t0(end);
            if ~any(pairValid(t0:peaks(k)))
                troughs(troughs == t0) = [];
                peaks(k) = [];
                pruned = true;
                break;
            end
        end
    end

    % pair each peak with the last trough before it
    onsets = nan(1, numel(peaks));
    for k = 1:numel(peaks)
        pk = peaks(k);
        tr = troughs(troughs < pk);
        if isempty(tr), continue; end
        tr = tr(end);
        w = tr:pk;
        if numel(w) < round(0.2 * fs), continue; end
        seg  = resp(w);
        dseg = d(w);
        eSeg = pairValid(w);   % all three rules, rule 2 pair-scaled
        rng_ = resp(pk) - resp(tr);
        lo = resp(tr) + 0.15 * rng_;
        hi = resp(pk) - 0.25 * rng_;
        switch method
            case 'slopeGate'
                th = 0.20 * max(dseg);
                sustain = round(0.10 * fs);
                cand = find(dseg(1:end-sustain) > th & seg(1:end-sustain) >= lo & seg(1:end-sustain) <= hi & eSeg(1:end-sustain));
                o = NaN;
                for c = cand
                    if all(dseg(c:c+sustain) > th * 0.5), o = c; break; end
                end
                if isnan(o) && ~isempty(cand), o = cand(1); end

            case 'kneeBacktrack'
                % (2026-08-28 JH_1 drill fixes) Anchor at the LAST major slope
                % surge before the peak, computed WITHOUT the amplitude cap -
                % the mid-band cap had excluded the final rise of multi-stage
                % inhales, anchoring the walk on an early sub-rise.
                % anchor (2026-08-28 review): start at the peak and walk back
                % to the closest point with slope >= 70% of the window max -
                % no amplitude-band logic (the smoothed slope is not jittery)
                dmax = max(dseg);
                im = find(dseg >= 0.7 * dmax, 1, 'last');
                if isempty(im), [~, im] = max(dseg); end
                % Stop only on a SUSTAINED dip (slope < 0.15 dmax for >=0.15 s)
                % - knife-edge single-sample dips on drifting plateaus neither
                % halt the walk early nor let it slide through a real pause.
                susLen = max(1, round(0.15 * fs));
                susDip = movsum(double(dseg < 0.15 * dmax), [susLen - 1, 0]) >= susLen;
                % walk freely: eligibility applies to the LANDING (final
                % snap), not the path - per-step gating halted walks at the
                % anchor when rule 2's near-peak cutoff sat right behind it
                % (PP 449s drill). Descents stop the walk via susDip anyway.
                o = im;
                while o > 1 && ~susDip(o - 1)
                    o = o - 1;
                end
                % late-landing extension (2026-08-28 rev4): a landing above
                % trough+35% of the swing is midway up a TWO-PHASE inhale
                % (the slow first phase read as a dip). Keep walking with a
                % stricter flatness demand to reach the true base; an
                % overshoot is caught by the clean-sweep midpoint below.
                if seg(o) > resp(tr) + 0.35 * rng_
                    susDip2 = movsum(double(dseg < 0.05 * dmax), [susLen - 1, 0]) >= susLen;
                    o2 = o;
                    while o2 > 1 && ~susDip2(o2 - 1)
                        o2 = o2 - 1;
                    end
                    o = o2;
                end
                % no-inflection fallback (2026-08-28, ZL audit): on pause-free
                % breaths the slope stays high nearly to the trough and the
                % walk-back descends >80% of the peak-to-trough swing - there
                % is no knee to find. Fall back to the LAST upward crossing of
                % the trough/peak MIDPOINT: on a smooth rise that is the
                % steepest region, i.e. the morphological onset.
                if seg(o) < resp(tr) + 0.2 * rng_
                    % clean sweep: no knee exists - midpoint crossing
                    midLvl = resp(tr) + 0.5 * rng_;
                    cr = find(seg(1:end-1) < midLvl & seg(2:end) >= midLvl);
                    if ~isempty(cr), o = cr(end) + 1; end
                else
                    % knee FOUND: apply rule 3 (slope contrast) to narrow the
                    % space and re-run the walk (2026-08-28 two-pass flow) -
                    % the re-walk stops no later than pass 1 by construction
                    % rule 3 refines the LANDING: if the mark lacks slope
                    % contrast, move to the nearest contrasted sample in-window
                    r3seg = r3v(w);
                    if ~r3seg(min(o, numel(r3seg))) && any(r3seg)
                        cnd = find(r3seg);
                        [~, ci] = min(abs(cnd - o)); o = cnd(ci);
                    end
                end

            case 'changepoint'
                n = numel(seg);
                step = max(1, round(fs / 100));            % 10-ms grid
                cands = round(0.05 * n):step:round(0.95 * n);
                x = 1:n;
                best = Inf; o = NaN;
                for c = cands
                    xl = x(1:c);  yl = seg(1:c);
                    xr = x(c:end); yr = seg(c:end);
                    pl = polyfit(xl, yl, 1); pr = polyfit(xr, yr, 1);
                    if pr(1) <= pl(1) + 1e-9, continue; end
                    r = sum((yl - polyval(pl, xl)).^2) + sum((yr - polyval(pr, xr)).^2);
                    if r < best, best = r; o = c; end
                end

            otherwise
                error('unknown method %s', method);
        end
        % ineligible landing (e.g. changepoint at a descent) -> advance to the
        % first eligible sample in the window
        if isfinite(o) && ~eSeg(min(o, numel(eSeg)))
            cand = find(eSeg);   % nearest eligible in EITHER direction
            if isempty(cand), o = NaN; else, [~, ci] = min(abs(cand - o)); o = cand(ci); end
        end
        if isfinite(o), onsets(k) = tr + o - 1; end
    end
    onsets = onsets(isfinite(onsets));
end

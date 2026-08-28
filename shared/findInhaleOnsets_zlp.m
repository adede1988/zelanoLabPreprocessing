function onsets = findInhaleOnsets_zlp(resp, fs, peaks, troughs, method)
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
    THETA = 0.10;
    d33 = resp - [repmat(resp(1), 1, LAG), resp(1:end-LAG)];
    elig = d33 > -THETA;

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
        eSeg = elig(w);
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
                inBand = seg >= lo & seg <= hi;
                dm = dseg; dm(~inBand) = -Inf;
                [dmax, im] = max(dm);
                if ~isfinite(dmax), [dmax, im] = max(dseg); end
                o = im;
                while o > 1 && dseg(o - 1) > 0.15 * dmax && eSeg(o - 1)
                    o = o - 1;
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
            nxt = find(eSeg(o:end), 1);
            if isempty(nxt), o = NaN; else, o = o + nxt - 1; end
        end
        if isfinite(o), onsets(k) = tr + o - 1; end
    end
    onsets = onsets(isfinite(onsets));
end

function [det, peaks, troughs, info] = prepBreathTrace_zlp(rsp, fs, mode, blankBelowFrac)
%PREPBREATHTRACE_ZLP  Step-1 preparation + peak/trough detection (QC round 4).
%
%   [det, peaks, troughs, info] = prepBreathTrace_zlp(rsp, fs, mode, blankBelowFrac)
%
%   Three alternatives for preparing the trace and finding breath extrema,
%   addressing the 2026-08 review's two step-1 failures: (a) over-detection
%   of peaks/troughs carving breaths up, (b) uniform smoothing erasing the
%   sharp inhale uptick along with the noise. breathMetrics-style outputs
%   (sample-index peak/trough vectors, strictly alternating) so any of them
%   can replace findRespiratoryExtrema in the bm flow. Onset detection
%   (findInhaleOnsets_zlp) runs downstream on the returned det trace.
%
%   mode 'pwl'          piecewise-linear (Douglas-Peucker) reconstruction:
%                       breakpoints only where line-fit error > 15% of local
%                       amplitude - micro-bumps vanish, sharp slope changes
%                       are preserved exactly. Extrema = alternating polyline
%                       vertices. det = the polyline itself.
%   mode 'conservative' minimal smoothing (150 ms); over-detection attacked
%                       at the criteria: prominence >= 0.6 (normalized),
%                       trough->peak rise >= 40% of local breath amplitude,
%                       2.5-s min separation, strict alternation.
%   mode 'twoscale'     extrema on a 500-ms-smoothed skeleton (bumps cannot
%                       survive), each refined to the true extremum on the
%                       150-ms trace within +/-0.6 s; det = the 150-ms trace
%                       (sharp uptick intact for onset placement).
%
%   Common to all: linear NaN fill, 30-s moving-std windowed amplitude
%   normalization (floor 0.05 x median), optional blankBelowFrac exclusion.

    if nargin < 4, blankBelowFrac = []; end
    rsp = double(rsp(:))';
    rsp = fillmissing(rsp, 'linear', 'EndValues', 'nearest');

    base = movmean(rsp, round(0.15 * fs));            % light common smoothing
    sc = movstd(base, round(30 * fs));
    scFloor = 0.05 * median(sc);
    x = base ./ max(sc, scFloor);                     % normalized, light
    if ~isempty(blankBelowFrac)
        x(sc < blankBelowFrac * median(sc)) = 0;
    end
    N = numel(x);
    info = struct('mode', mode, 'nBreakpoints', NaN);

    switch mode
        case 'pwl'
            % Douglas-Peucker at 20 Hz, tolerance 0.15 normalized units
            ds = max(1, round(fs / 20));
            gi = 1:ds:N; g = x(gi); ng = numel(g);
            keepBP = false(1, ng); keepBP([1 ng]) = true;
            stack = [1 ng];
            while ~isempty(stack)
                a = stack(end, 1); b = stack(end, 2); stack(end, :) = [];
                if b - a < 2, continue; end
                seg = g(a:b);
                lin = linspace(seg(1), seg(end), b - a + 1);
                [emax, ei] = max(abs(seg - lin));
                if emax > 0.15
                    c = a + ei - 1;
                    keepBP(c) = true;
                    stack(end+1, :) = [a c]; %#ok<AGROW>
                    stack(end+1, :) = [c b]; %#ok<AGROW>
                end
            end
            bp = gi(keepBP);
            det = interp1(bp, x(bp), 1:N, 'linear', 'extrap');
            info.nBreakpoints = numel(bp);
            % extrema = interior polyline vertices that are local max/min
            v = x(bp); pk = []; tr = [];
            for k = 2:numel(bp)-1
                if v(k) > v(k-1) && v(k) > v(k+1), pk(end+1) = bp(k); end %#ok<AGROW>
                if v(k) < v(k-1) && v(k) < v(k+1), tr(end+1) = bp(k); end %#ok<AGROW>
            end
            [peaks, troughs] = enforceAlt(det, pk, tr, 0.5, round(1.5 * fs));

        case 'conservative'
            det = x;
            [~, pk] = findpeaks(det,  'MinPeakProminence', 0.6, 'MinPeakDistance', round(2.5 * fs));
            [~, tr] = findpeaks(-det, 'MinPeakProminence', 0.6, 'MinPeakDistance', round(2.5 * fs));
            [peaks, troughs] = enforceAlt(det, pk, tr, 0, 0);
            % rise-fraction filter: a trough->peak rise under 40% of the local
            % breath amplitude is a bump, not a breath
            locAmp = movmax(det, round(30 * fs)) - movmin(det, round(30 * fs));
            good = true(size(peaks));
            for k = 1:numel(peaks)
                t0 = troughs(troughs < peaks(k));
                if isempty(t0), continue; end
                if det(peaks(k)) - det(t0(end)) < 0.4 * 0.5 * locAmp(peaks(k)), good(k) = false; end
            end
            [peaks, troughs] = enforceAlt(det, peaks(good), troughs, 0, 0);

        case 'twoscale'
            det = x;
            skel = movmean(x, round(0.5 * fs));
            [~, pk] = findpeaks(skel,  'MinPeakProminence', 0.45, 'MinPeakDistance', round(2 * fs));
            [~, tr] = findpeaks(-skel, 'MinPeakProminence', 0.45, 'MinPeakDistance', round(2 * fs));
            w = round(0.6 * fs);
            for k = 1:numel(pk)
                a = max(1, pk(k)-w); b = min(N, pk(k)+w);
                [~, m] = max(det(a:b)); pk(k) = a + m - 1;
            end
            for k = 1:numel(tr)
                a = max(1, tr(k)-w); b = min(N, tr(k)+w);
                [~, m] = min(det(a:b)); tr(k) = a + m - 1;
            end
            [peaks, troughs] = enforceAlt(det, pk, tr, 0, 0);

        otherwise
            error('unknown prep mode %s', mode);
    end
end

function [peaks, troughs] = enforceAlt(det, pk, tr, minProm, minSep)
% strict trough->peak->trough alternation; of two same-type extrema in a row
% the more extreme wins. Optional extra prominence/separation pre-filter.
    if minProm > 0 || minSep > 0
        % (used by pwl where vertices carry no findpeaks guarantees)
        keep = true(size(pk));
        for k = 2:numel(pk)
            if pk(k) - pk(k-1) < minSep, keep(k) = false; end
        end
        pk = pk(keep);
    end
    ev = [pk(:), ones(numel(pk), 1); tr(:), -ones(numel(tr), 1)];
    ev = sortrows(ev, 1);
    keep = true(size(ev, 1), 1);
    i = 1;
    while i < size(ev, 1)
        j = i + 1;
        while j <= size(ev, 1) && ~keep(j), j = j + 1; end
        if j > size(ev, 1), break; end
        if ev(i, 2) == ev(j, 2)
            if ev(i, 2) == 1
                if det(ev(i, 1)) >= det(ev(j, 1)), keep(j) = false; else, keep(i) = false; i = j; end
            else
                if det(ev(i, 1)) <= det(ev(j, 1)), keep(j) = false; else, keep(i) = false; i = j; end
            end
        else
            i = j;
        end
    end
    ev = ev(keep, :);
    peaks   = ev(ev(:, 2) == 1, 1)';
    troughs = ev(ev(:, 2) == -1, 1)';
end

function [bmObj, bmFeatures, info] = mergeCyclicSighBreaths(bmObj, bmFeatures, rsp, fs, cyBlocks, refracFrac)
% mergeCyclicSighBreaths  one breath per cyclic-sigh CYCLE (task-level refractory).
%
%   [bmObj, bmFeatures, info] = mergeCyclicSighBreaths(bmObj, bmFeatures, rsp, fs, cyBlocks)
%
% A cyclic sigh is a double-peaked inhale. The locked engine's keep-first rule
% (segmentBreaths_zlp, cySpan) only blocks a FIXED 5 s after a peak, which
% misses a top-up peak that lands later than that (HW cyclicSigh3: sub-peaks
% 5-7 s after the primary). This helper, run AFTER the engine (the engine is
% LOCKED and untouched), applies a refractory proportional to the block's
% cycle period: a breath whose inhale peak falls within refracFrac x period of
% the last KEPT peak of the same block is merged into that kept breath (keep
% first, like the engine).
%
%   cyBlocks   [nBlock x 2] sample ranges [start end] (at fs) of each cyclicSigh block
%   refracFrac fraction of the cycle period blocked after a kept peak (default 0.65)
%
% Cycle period of a block = the autocorrelation peak of its respiration in
% 6-14 s when that peak is strong (r >= 0.4); a block without a clear
% rhythm (no clear cycle) takes the median
% period of the blocks that have one, else 10 s (the nominal paced cycle).
%
% Merged breath k (kept) absorbs the dropped rows: its end (cols 5-7) becomes the
% end of the last absorbed row, amplitude (col 8) is recomputed, and its exhale
% trough (cols 10-11) is the lower of the absorbed troughs. bmFeatures per-breath
% arrays are NOT rebuilt: bmObjBreathIdx is re-pointed to the kept breath's own
% feature index, so the bm_* columns of a merged breath describe its first
% (primary) inhale. info lists blocks, periods, refractory and merge counts.

    if nargin < 6 || isempty(refracFrac), refracFrac = 0.65; end
    nB = size(cyBlocks, 1);
    per = nan(nB, 1); rr = nan(nB, 1);
    for b = 1:nB
        [per(b), rr(b)] = acPeriod(rsp(max(1, cyBlocks(b,1)):min(numel(rsp), cyBlocks(b,2))), fs);
    end
    good = isfinite(per) & rr >= 0.4;
    perUsed = per;
    if any(good), fb = median(per(good)); else, fb = 10; end
    perUsed(~good) = fb;
    refrac = refracFrac * perUsed;

    n0 = size(bmObj, 1);
    keep = true(n0, 1);
    pkT = bmObj(:, 4);
    nMerged = zeros(nB, 1);
    nIn = zeros(nB, 1);
    for b = 1:nB
        inB = find(pkT * fs >= cyBlocks(b,1) & pkT * fs < cyBlocks(b,2));
        nIn(b) = numel(inB);
        kIdx = 0;
        for q = 1:numel(inB)
            r = inB(q);
            if kIdx > 0 && (pkT(r) - pkT(kIdx)) < refrac(b)
                keep(r) = false; nMerged(b) = nMerged(b) + 1;
                % merge into the kept breath kIdx
                bmObj(kIdx, 5) = bmObj(r, 5); bmObj(kIdx, 6) = bmObj(r, 6);
                bmObj(kIdx, 7) = bmObj(kIdx, 6) - bmObj(kIdx, 2);
                bmObj(kIdx, 8) = bmObj(kIdx, 3) - (bmObj(kIdx, 1) + bmObj(kIdx, 5)) / 2;
                if bmObj(r, 10) < bmObj(kIdx, 10)
                    bmObj(kIdx, 10) = bmObj(r, 10); bmObj(kIdx, 11) = bmObj(r, 11);
                end
            else
                kIdx = r;
            end
        end
    end
    bmObj = bmObj(keep, :);
    if isfield(bmFeatures, 'bmObjBreathIdx')
        bmFeatures.bmObjBreathIdx = bmFeatures.bmObjBreathIdx(keep);
        bmFeatures.nBreathsSegmented = size(bmObj, 1);
    end
    info = struct('cyBlocks', cyBlocks, 'periodMeasured', per, 'acCoeff', rr, ...
        'periodUsed', perUsed, 'refractorySec', refrac, 'refracFrac', refracFrac, ...
        'nBreathsInBlock', nIn, 'nMerged', nMerged, ...
        'note', ['task-level cyclicSigh refractory (mergeCyclicSighBreaths, 2026-10-12): ' ...
                 'breaths whose peak is within refracFrac x cycle period of the last kept peak merged into it']);
    if isfield(bmFeatures, 'conditioning')
        bmFeatures.conditioning.cyclicSighRefractory = info;
    end
end

function [p, r] = acPeriod(x, fs)
% autocorrelation cycle period (s) in 6-14 s and its coefficient
    p = NaN; r = NaN;
    x = double(x(:)'); x = fillmissing(x, 'linear', 'EndValues', 'nearest');
    d = max(1, round(fs / 10));
    y = x - movmean(x, round(30 * fs));
    y = y(1:d:end);
    if numel(y) < 400, return; end
    [ac, lg] = xcorr(y, 150, 'coeff');
    ac = ac(lg >= 0); lg = lg(lg >= 0) / (fs / d);
    m = lg >= 6 & lg <= 14;
    [pk, l] = findpeaks(ac(m));
    if isempty(pk), return; end
    lgm = lg(m); [r, i] = max(pk); p = lgm(l(i));
end

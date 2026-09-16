function [blocks, TTL, info] = inferBlocks_pacedBreathing(bmObj, fs, nSamp, opts)
%INFERBLOCKS_PACEDBREATHING  Data-driven block segmentation for pacedBreathing.
%
%   [blocks, TTL, info] = inferBlocks_pacedBreathing(bmObj, fs, nSamp, opts)
%
%   pacedBreathing sessions carry NO event marks: the paced blocks (each a
%   plateau of near-constant pace and depth) are separated by brief breaks
%   and by step changes in pace and/or depth. This helper infers block
%   boundaries from the per-breath series stored in bmObj (onset time col 2,
%   breath length col 7, amplitude col 8). Everything is done in BREATH-index
%   space (uniform noise model) and converted to samples at the end:
%
%     1. per-breath log(period) and log(amplitude), each smoothed by a
%        5-breath running median (plateau level), plus a REGULARITY series =
%        7-breath running mean of |log(period) - 7-breath running median|
%        (natural breathing is irregular, paced breathing is not);
%     2. DELIBERATE OVER-SEGMENTATION: findchangepts ('mean') on each
%        smoothed series separately, MinDistance = opts.minBlockBreaths,
%        MinThreshold = opts.penaltyBIC * sigma^2 * log(n) with sigma^2 the
%        robust spread of the smoothed series around a wide running median.
%        That penalty is far below a proper BIC for these autocorrelated
%        series (it keeps the ~1 breath/min plateau steps of a pace sweep,
%        which a BIC on 15-25 breaths would miss), so it yields many spurious
%        splits inside homogeneous stretches; the three sets are pooled and
%        the MERGE stage (step 4) is the real decision maker;
%     3. forced splits at breaks (inter-onset gap > opts.gapSec), protected
%        from the similarity merge;
%     4. iterated MERGE + REFINE until stable:
%        merge - segments shorter than opts.minBlockSec (or fewer than
%          opts.minBlockBreaths breaths) are absorbed into the more similar
%          neighbour, never across a forced gap split while the other side
%          is free; an adjacent pair is merged (most similar first) when
%          (a) its raw-median log-period, log-amplitude and regularity all
%              differ by less than opts.mergePeriodLog / mergeAmpLog /
%              mergeRegularity, or
%          (b) both segments are irregular (regularity > opts.naturalReg,
%              i.e. natural breathing, which has no plateaus to separate)
%              and their amplitude differs by less than 2*mergeAmpLog
%              (opts.natPooled = true tests the pooled median regularity
%              instead - it merges more but also swallows a paced plateau
%              next to a natural stretch, so it is off by default), or
%          (c) the level differences are statistically indistinguishable
%              (< opts.seMult standard errors from the within-segment MADs).
%              TRADE-OFF (2026-09-15 review + synthetic sweeps): the splits
%              sit where the contrast is maximal, so at seMult 2.5 a
%              homogeneous but variable block (period CV 0.10-0.15, e.g.
%              focused or ragged breathing) is left in 2-3 fragments in
%              20-40% of cases; at seMult 4 those fragments merge but the
%              ~1 breath/min plateau steps of a pace sweep (15-25 breaths
%              each) are merged too (30 -> 26 blocks, purity .90 -> .83 on
%              protocol-matched simulations). 2.5 is the default because
%              this protocol is a pace sweep; raise it per session for
%              recordings made of long homogeneous blocks;
%        refine - each boundary moves to the breath within +/-
%          opts.refineBreaths that minimises the two-segment squared error
%          of the UNSMOOTHED per-breath series that actually change there;
%     5. labels are POSITIONAL, not verified: 'pre' = first block (audiobook
%        / survey before pacing starts), 'final' = last block (focused
%        breathing), 'paced' = everything between.
%
%   Outputs
%     blocks : table tiling the recording in fs-sample space -
%              label, order, startSample, endSample, durationSec, nBreaths,
%              medRateBPM, medPeriodSec, medAmp, periodCV, ampCV,
%              regularity (median per-breath |log-period deviation|), gapSplit
%     TTL    : breathing-style row vector of block-start samples
%     info   : parameters, raw changepoints, merge history, per-breath block
%              index (audit trail)
%
%   The inference is a first pass for a task without markers; review the
%   blocks_inferred figure the main saves and adjust opts (P.pacedOpts) if
%   needed.

    if nargin < 4 || isempty(opts), opts = struct(); end
    dflt = struct('minBlockSec', 60, 'minBlockBreaths', 6, 'gapSec', 15, 'penaltyBIC', 4, ...
                  'mergePeriodLog', 0.06, 'mergeAmpLog', 0.15, 'mergeRegularity', 0.10, ...
                  'naturalReg', 0.13, 'seMult', 2.5, 'natPooled', false, 'refineBreaths', 5, 'maxIter', 8);
    fn = fieldnames(dflt);
    for k = 1:numel(fn)
        if ~isfield(opts, fn{k}) || isempty(opts.(fn{k})), opts.(fn{k}) = dflt.(fn{k}); end
    end

    assert(size(bmObj, 2) >= 14, 'inferBlocks_pacedBreathing: bmObj must be [nBreaths x 14]');
    t   = bmObj(:, 2);
    per = bmObj(:, 7);
    amp = bmObj(:, 8);
    n = numel(t);
    assert(n >= 10, 'inferBlocks_pacedBreathing: too few breaths (%d)', n);
    per(~isfinite(per) | per <= 0) = NaN;
    amp(~isfinite(amp) | amp <= 0) = NaN;
    durS = nSamp / fs;
    if durS < t(end) + max(per(end), 1)          % recording shorter than the last breath? (should not happen)
        durS = t(end) + max(per(end), 1);
    end

    % ---- 1. per-breath series ----
    lpB = fillmissing(log(per(:)), 'nearest')';
    laB = fillmissing(log(amp(:)), 'nearest')';
    lpS = movmedian(lpB, 5, 'omitnan');
    laS = movmedian(laB, 5, 'omitnan');
    rgB = movmean(abs(lpB - movmedian(lpB, 7, 'omitnan')), 7, 'omitnan');
    series = {lpS, laS, rgB};
    names  = {'period', 'amp', 'regularity'};

    % ---- 2. changepoints per series (breath index), BIC-like penalty ----
    minBr = max(3, round(opts.minBlockBreaths));
    cpAll = cell(1, 3); thrAll = zeros(1, 3);
    for r = 1:3
        x = series{r};
        sig2 = max((1.4826 * mad(x - movmedian(x, 15), 1))^2, 1e-8);
        thrAll(r) = opts.penaltyBIC * sig2 * log(n);
        c = findchangepts(x, 'Statistic', 'mean', 'MinDistance', minBr, 'MinThreshold', thrAll(r));
        cpAll{r} = c(:)';
    end
    cp = unique([cpAll{:}]);                     % breath indices that START a new segment

    % ---- 3. breaks: inter-onset gaps ----
    gapB = find(diff(t) > opts.gapSec) + 1;      % first breath after each gap
    gapB = gapB(:)';
    bounds = unique([1, cp, gapB, n + 1]);       % segment first-breath indices; last = n+1
    isGap  = ismember(bounds, gapB);

    % ---- 4. iterated merge + refine ----
    history = {};
    zf = @(x) (x - mean(x)) / max(std(x), eps);
    zpB = zf(lpB); zaB = zf(laB);
    for it = 1:opts.maxIter
        [bounds, isGap, hist1, nMerged] = mergePass(bounds, isGap, t, durS, lpB, laB, rgB, opts);
        history = [history, hist1]; %#ok<AGROW>
        [bounds, nShift] = refinePass(bounds, isGap, n, zpB, zaB, lpS, laS, opts);
        if nMerged == 0 && nShift == 0, break; end
    end
    [bounds, isGap, hist1] = mergePass(bounds, isGap, t, durS, lpB, laB, rgB, opts);
    history = [history, hist1];

    % ---- 5. table ----
    nB = numel(bounds) - 1;
    bStart = bounds(1:nB);
    startSec = t(bStart)'; startSec(1) = 0;
    % block b starts AT its first breath's onset sample (round(t*fs) is the
    % sample index behDat.finalOnset carries), so a sample-span test
    % (onset >= startSample & onset <= endSample) agrees with blkOfBreath
    startSample = max(1, round(startSec * fs)); startSample(1) = 1;
    endSample   = [startSample(2:nB) - 1, nSamp];
    blkOfBreath = zeros(n, 1);
    for b = 1:nB
        if b < nB, blkOfBreath(bStart(b):bStart(b + 1) - 1) = b; else, blkOfBreath(bStart(b):n) = b; end
    end
    blkOfBreath(blkOfBreath == 0) = 1;

    label = repmat("paced", nB, 1);
    label(1) = "pre";
    if nB >= 2, label(nB) = "final"; end

    blocks = table();
    blocks.label = label;
    blocks.order = (1:nB)';
    blocks.startSample = startSample(:);
    blocks.endSample   = endSample(:);
    blocks.durationSec = (blocks.endSample - blocks.startSample + 1) / fs;
    blocks.nBreaths    = arrayfun(@(b) sum(blkOfBreath == b), (1:nB)');
    blocks.medRateBPM  = arrayfun(@(b) 60 / median(per(blkOfBreath == b), 'omitnan'), (1:nB)');
    blocks.medPeriodSec= arrayfun(@(b) median(per(blkOfBreath == b), 'omitnan'), (1:nB)');
    blocks.medAmp      = arrayfun(@(b) median(amp(blkOfBreath == b), 'omitnan'), (1:nB)');
    blocks.periodCV    = arrayfun(@(b) cvOf(per(blkOfBreath == b)), (1:nB)');
    blocks.ampCV       = arrayfun(@(b) cvOf(amp(blkOfBreath == b)), (1:nB)');
    blocks.regularity  = arrayfun(@(b) median(rgB(blkOfBreath == b), 'omitnan'), (1:nB)');
    blocks.gapSplit    = isGap(1:nB)';
    blocks.gapSplit(1) = false;

    TTL = blocks.startSample';

    info = struct();
    info.method = ['inferBlocks_pacedBreathing: per-breath log-period/log-amp/regularity, ' ...
                   'findchangepts mean with BIC-like penalty (pooled), gap splits, ' ...
                   'iterated similarity merge + per-breath boundary refinement'];
    info.opts = opts;
    for r = 1:3
        info.(['cp_' names{r} '_breath']) = cpAll{r};
        info.(['cp_' names{r} '_sec'])    = t(cpAll{r})';
        info.(['thr_' names{r}])          = thrAll(r);
    end
    info.gapSplitBreath  = gapB;
    info.mergeHistory    = history;
    info.blkOfBreath     = blkOfBreath(:);
    info.labelsArePositional = true;
    fprintf('inferBlocks_pacedBreathing: %d raw changepoints (period %d, amp %d, regularity %d), %d gap splits -> %d blocks\n', ...
        numel(cp), numel(cpAll{1}), numel(cpAll{2}), numel(cpAll{3}), numel(gapB), nB);
end

% ============================ helpers ============================

function [bounds, isGap, history, nMerged] = mergePass(bounds, isGap, t, durS, lpB, laB, rgB, opts)
% Absorb sub-minimum segments, then merge similar adjacent pairs until none
% qualifies. Level statistics use the RAW per-breath series (medians) so the
% smoothing never biases a boundary decision; the smoothed series only feed
% the changepoint detection.
    history = {}; nMerged = 0;
    while true
        nS = numel(bounds) - 1;
        if nS <= 1, break; end
        nBr = diff(bounds);
        segStartSec = t(bounds(1:nS))'; segStartSec(1) = 0;
        segEndSec   = [segStartSec(2:end), durS];
        durSec = segEndSec - segStartSec;
        med = zeros(nS, 3); sd = zeros(nS, 2);
        for s = 1:nS
            idx = bounds(s):bounds(s+1) - 1;
            med(s, :) = [median(lpB(idx)), median(laB(idx)), median(rgB(idx))];
            sd(s, :)  = 1.4826 * [mad(lpB(idx), 1), mad(laB(idx), 1)];
        end
        dP = abs(diff(med(:, 1))); dA = abs(diff(med(:, 2))); dR = abs(diff(med(:, 3)));
        seP = sqrt(sd(1:end-1, 1).^2 ./ nBr(1:end-1)' + sd(2:end, 1).^2 ./ nBr(2:end)');
        seA = sqrt(sd(1:end-1, 2).^2 ./ nBr(1:end-1)' + sd(2:end, 2).^2 ./ nBr(2:end)');
        dist = dP / opts.mergePeriodLog + dA / opts.mergeAmpLog + dR / opts.mergeRegularity;

        % (i) absorb the smallest sub-minimum segment into its more similar neighbour
        short = find(durSec < opts.minBlockSec | nBr < opts.minBlockBreaths);
        if ~isempty(short)
            [~, j] = min(durSec(short)); s0 = short(j);
            % neighbour choice: a forced (gap) split is never deleted while the
            % other side of the short segment is a free boundary
            gapL = isGap(s0); gapR = isGap(s0 + 1);
            if s0 == 1
                b = 1;
            elseif s0 == nS
                b = nS - 1;
            elseif gapR && ~gapL
                b = s0 - 1;                  % keep the gap after it: merge left
            elseif gapL && ~gapR
                b = s0;                      % keep the gap before it: merge right
            else
                if dist(s0 - 1) <= dist(s0), b = s0 - 1; else, b = s0; end
            end
            history{end+1} = sprintf('absorb short segment %d (%.0f s, %d breaths) across boundary %d', ...
                                     s0, durSec(s0), nBr(s0), b); %#ok<AGROW>
            bounds(b + 1) = []; isGap(b + 1) = []; nMerged = nMerged + 1;
            continue
        end

        % (ii) merge the most similar adjacent pair that qualifies (gap boundaries protected)
        tolRule = dP < opts.mergePeriodLog & dA < opts.mergeAmpLog & dR < opts.mergeRegularity;
        if opts.natPooled
            pooledReg = zeros(nS - 1, 1);
            for s = 1:nS - 1, pooledReg(s) = median(rgB(bounds(s):bounds(s+2) - 1)); end
            natRule = pooledReg > opts.naturalReg & dA < 2 * opts.mergeAmpLog;
        else
            natRule = med(1:end-1, 3) > opts.naturalReg & med(2:end, 3) > opts.naturalReg & dA < 2 * opts.mergeAmpLog;
        end
        seRule  = dP < opts.seMult * seP & dA < opts.seMult * seA & dR < opts.mergeRegularity;
        cand = find((tolRule | natRule | seRule) & ~isGap(2:end-1)');
        if isempty(cand), break; end
        [~, j] = min(dist(cand));
        b = cand(j);
        rule = 'tol'; if ~tolRule(b), if natRule(b), rule = 'natural'; else, rule = 'se'; end, end
        history{end+1} = sprintf('merge segments %d+%d by %s rule (dP=%.3f dA=%.3f dR=%.3f)', ...
                                 b, b + 1, rule, dP(b), dA(b), dR(b)); %#ok<AGROW>
        bounds(b + 1) = []; isGap(b + 1) = []; nMerged = nMerged + 1;
    end
end

function [bounds, nShift] = refinePass(bounds, isGap, n, zpB, zaB, lpS, laS, opts)
% Move each non-gap boundary to the breath (within +/- refineBreaths) that
% minimises the two-segment squared error of the raw per-breath series that
% actually change across it.
    nB = numel(bounds) - 1; nShift = 0;
    for b = 2:nB
        if isGap(b), continue; end
        i0 = bounds(b - 1);
        i1 = bounds(b + 1) - 1; if b == nB, i1 = n; end
        cur = bounds(b);
        lo = max(i0 + 3, cur - opts.refineBreaths);
        hi = min(i1 - 2, cur + opts.refineBreaths);
        if hi < lo, continue; end
        wP = abs(median(lpS(i0:cur-1)) - median(lpS(cur:i1))) >= opts.mergePeriodLog;
        wA = abs(median(laS(i0:cur-1)) - median(laS(cur:i1))) >= opts.mergeAmpLog;
        if ~wP && ~wA, wP = true; wA = true; end
        best = inf; bj = cur;
        for j = lo:hi
            c = wP * (sse(zpB(i0:j-1)) + sse(zpB(j:i1))) + wA * (sse(zaB(i0:j-1)) + sse(zaB(j:i1)));
            if c < best - 1e-12, best = c; bj = j; end
        end
        if bj ~= cur, bounds(b) = bj; nShift = nShift + 1; end
    end
end

function v = cvOf(x)
    x = x(isfinite(x));
    if numel(x) < 3, v = NaN; else, v = std(x) / mean(x); end
end

function e = sse(x)
    if isempty(x), e = 0; else, e = sum((x - mean(x)).^2); end
end

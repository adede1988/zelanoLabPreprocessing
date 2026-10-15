function [bmObj, bmFeatures, info] = mergeIncompleteExhales(bmObj, bmFeatures, rsp, fs, exFrac, opts)
% mergeIncompleteExhales  an inhale is not a new breath unless there has been an exhale since the last one.
%
%   [bmObj, bmFeatures, info] = mergeIncompleteExhales(bmObj, bmFeatures, rsp, fs, exFrac, opts)
%
% Rule (user, 2026-10-15; respiratorySweep): "we shouldn't count a breath as a new inhale if there's
% been no exhale since the last one ... breaths get merged if a breath exists where there's not an
% exhale with at least 20% of the volume of the inhale since the last inhale." Runs AFTER the LOCKED
% engine (segmentBreaths_zlp, untouched), like mergeCyclicSighBreaths, in three steps:
%
%  1. Pause blips. An engine onset whose own window [onset(k), onset(k+1)) holds neither an inhale
%     nor an exhale - inhale area I_k AND exhale area E_k each below opts.minorFrac (0.10) x the median
%     of the engine rows within +-10 rows - is not a breath (typically the engine's onset where an
%     exhale returns to rest, the pause after it sitting a little above zero flow); it joins the
%     breath before it, as part of its pause. Here I_k / E_k count the trace beyond a noise band of
%     +-opts.deadFrac (0.05) x the local breath swing (median max - min of the engine windows within
%     +-10 rows) around zero flow, on the 1-s mean of the trace for windows >= 4 s (cardiac ripple on
%     a pause averages out; over a 7-s pause a few units add up) and on the 200-ms mean for shorter
%     ones (a 1-s mean would cancel a fast breath: 261006_EEG_NWU_RC at 30 /min).
%  2. Lead bumps. An inhale k with no exhale before the next inhale (E < exFrac x I over its window),
%     a peak under opts.leadFrac (0.5) x that next inhale's, and >= opts.restSec (3 s) near zero flow
%     (1-s mean within 2 noise bands) between its peak and the next onset is the overshoot of the
%     previous exhale's recovery followed by a pause, not the start of the next breath: it joins the
%     breath before, and the breath starts at the next inhale. Contiguous pulses (a double inhale) have
%     no rest between them and are left to step 3. (261007_EEG_NWU_AL 2529.6 s: the SniffLogic target
%     is still in its recovery there; the inhale starts at 2536.5 s with the target's.)
%  3. Merge. For every remaining inhale k (in order): over [onset(k-1), onset(k)) - since the LAST
%     inhale, merged or not, blips included - E = area below zero flow and I = area above it; when E <
%     exFrac (0.20) x I, inhale k is not a new breath and joins the breath of inhale k-1. Consecutive
%     joins form one breath (a double inhale, a chain of pulses); each inhale is judged on its own
%     window, so a later complete exhale always ends the breath.
%
% Areas are signal areas (sensor units x ms) of the nasal-pressure trace (200-ms moving mean) above /
% below zero flow, not litres: the 20 % is of signal area. Step 3 and the reported areas use no noise
% band: a slow exhale reads small on a pressure sensor (pressure ~ flow^2), and a band would erase it.
% Nasal pressure under-reads slow flow, so a very slow, shallow exhale after a fast inhale can fall
% under 20 % of the inhale's signal area and the next inhale then merges. They are not taken from
% breathmetrics, whose exhaleVolumes integrate |trace| over its own exhale window - a dip that never
% goes below zero flow (no exhale at all) still gets a sizeable "exhale volume" (261007_EEG_NWU_AL
% 2551 s: bm 39 % of the inhale, area below zero flow 0 %).
%
% Zero-flow level z(t) (zeroFlowLevel below): the HIGHER of (a) the level the trace dwells at between
% breaths - its most frequent level within +-10 s, accepted only when >= 15 % of the window sits
% within one bin of it and >= 10 % lies above and below it - and (b) the 60-s moving mean (the trace is
% high-passed at 0.03 Hz by downsample_data, so its long-run mean is near zero flow in continuous
% breathing). Why: at the slow paces the pauses are zero flow, but the high-pass filter lifts each
% pause 10-20 units above the 60-s mean after a strong exhale (261007_EEG_NWU_AL 4 cpm), and over a
% 7-s pause that offset adds up to a whole inhale's area; without pauses the trace dwells on the slow
% part of the exhale instead (261006_EEG_NWU_IS: -20 to -40), BELOW zero flow, where the 60-s mean
% is the better estimate. Not the engine's onset level (without a pause the engine places its onsets
% low on the exhale recovery limb) and not a flatness test (cardiac ripple on the pauses defeats it).
% Validation 2026-10-15: synthetic regressions (double inhales, chains, staircases, blips, continuous
% breathing 4-30 /min, square-law slow exhales) and, on the four sweep sessions, the share of
% SniffLogic target cycles holding exactly one breath onset (engine -> merged: AL 83.5 -> 87.5 %,
% ZL 96.9 -> 97.9 %, RC 83.2 -> 85.3 %, IS 91.7 -> 93.9 %).
%
% Merged breath (kept row = its first inhale, keep-first) absorbs the rows after it: end (cols 5-7) =
% the last absorbed row's end; inhale peak (cols 3, 4, 9) = the highest pulse; exhale trough (cols
% 10-11) = the lowest trough; amplitude (col 8) recomputed. bmFeatures per-breath arrays are NOT
% rebuilt (as mergeCyclicSighBreaths): bmObjBreathIdx keeps the first pulse's feature index, so the
% bm_* columns of a merged breath describe its FIRST pulse - including its exhale-side features,
% which then describe the dip between the pulses, not an exhale. Use info.inhaleArea / exhaleArea
% (whole breath) instead for merged breaths (nPulses > 1).
%
% opts (all optional; defaults in brackets): minorFrac (0.10), deadFrac (0.05), blipSmoothSec (1) -
% step 1; leadFrac (0.5), restSec (3) - step 2; zeroHalfWinSec (10), zeroBinFrac (0.04),
% zeroSideFrac (0.10), zeroMassFrac (0.15), zeroMaxMean (true) - zeroFlowLevel.
%
% info: rule, exFrac, deadFrac, minorFrac, zeroFlow, zeroFlowFracDwell (share of the recording where
% the dwell level was accepted), nBefore, nAfter, nMinor (engine rows joined to the breath before as
% blips or lead bumps), nLeadBumps (of them, step 2), nMerged (inhales merged into the breath before;
% nBefore - nAfter = nMinor + nMerged); per KEPT row nPulses (inhales in the breath, 1 = not merged),
% nRows (engine rows it holds, blips included), inhaleArea, exhaleArea (whole breath), exInRatio,
% origRows (cell of the engine rows); per ENGINE row isMinor, isLeadBump, pulseInhaleArea (step 1's
% I_k), pairExInRatio (E / I over [onset(k), next inhale onset) - the value step 3 tested for the
% inhale after it; NaN for a blip), engineOnsetSec, zeroFlowAtOnsets, deadBand.

    if nargin < 5 || isempty(exFrac), exFrac = 0.20; end
    if nargin < 6 || isempty(opts), opts = struct(); end
    deadFrac  = getOpt(opts, 'deadFrac', 0.05);
    minorFrac = getOpt(opts, 'minorFrac', 0.10);
    zHalf     = getOpt(opts, 'zeroHalfWinSec', 10);
    zBin      = getOpt(opts, 'zeroBinFrac', 0.04);
    zSide     = getOpt(opts, 'zeroSideFrac', 0.10);
    blipSm    = getOpt(opts, 'blipSmoothSec', 1);
    leadFrac  = getOpt(opts, 'leadFrac', 0.5);
    restSec   = getOpt(opts, 'restSec', 3);
    nbhd = 10;                                          % rows each side for the local references
    x = fillmissing(double(rsp(:)'), 'linear', 'EndValues', 'nearest');
    N = numel(x);
    n0 = size(bmObj, 1);
    on0Sec = bmObj(:, 2);
    on = min(max(round(bmObj(:, 2) * fs), 1), N);      % onset samples (the engine stores sample / fs)
    en = min(max(round(bmObj(:, 6) * fs), 1), N);      % breath end = next onset
    pk = min(max(round(bmObj(:, 4) * fs), 1), N);
    hiEnd = max(on, en - 1);                            % last sample of each engine window

    % ---- zero-flow level; inhale / exhale area densities (raw, and beyond the noise band) ----
    [z, zInfo] = zeroFlowLevel(x, fs, zHalf, zBin, zSide, getOpt(opts, 'zeroMaxMean', true), getOpt(opts, 'zeroMassFrac', 0.15));
    r = movmean(x, max(1, round(0.2 * fs))) - z;
    swing = nan(n0, 1);
    for k = 1:n0, w = r(on(k):hiEnd(k)); swing(k) = max(w) - min(w); end
    dRow = nan(n0, 1);
    for k = 1:n0, dRow(k) = deadFrac * median(swing(max(1, k - nbhd):min(n0, k + nbhd)), 'omitnan'); end
    dS = zeros(1, N);                                   % noise band per sample (that of its engine row)
    for k = 1:n0, dS(on(k):hiEnd(k)) = dRow(k); end
    if n0 >= 1, dS(1:on(1) - 1) = dRow(1); dS(hiEnd(n0) + 1:end) = dRow(n0); end
    cI = [0 cumsum(max(r, 0))];                         % window [a, b] sum = c(b + 1) - c(a)
    cE = [0 cumsum(max(-r, 0))];
    r1 = movmean(x, max(1, round(blipSm * fs))) - z;    % steps 1-2: 1-s mean (cardiac ripple on a pause averages out)
    cIb = [0 cumsum(max(r1 - dS, 0))];                  % beyond the noise band (step 1, windows >= 4 s)
    cIb02 = [0 cumsum(max(r - dS, 0))];                 % shorter windows: the 1-s mean would cancel a fast breath
    cEb = [0 cumsum(max(-r1 - dS, 0))]; cEb02 = [0 cumsum(max(-r - dS, 0))];
    areaI = @(a, b) cI(b + 1) - cI(a);
    areaE = @(a, b) cE(b + 1) - cE(a);

    % ---- step 1: pause blips (no inhale, no exhale) join the breath before ----
    Ik = nan(n0, 1); Ek = nan(n0, 1);
    for k = 1:n0
        a = on(k); b = hiEnd(k);
        if b - a >= 4 * fs, Ik(k) = cIb(b + 1) - cIb(a); Ek(k) = cEb(b + 1) - cEb(a);
        else, Ik(k) = cIb02(b + 1) - cIb02(a); Ek(k) = cEb02(b + 1) - cEb02(a); end
    end
    clear cIb02 cEb cEb02
    isMinor = false(n0, 1);
    for k = 2:n0
        nb = [max(1, k - nbhd):k - 1, k + 1:min(n0, k + nbhd)];
        ref = median(Ik(nb), 'omitnan'); refE = median(Ek(nb), 'omitnan');
        isMinor(k) = ref > 0 && Ik(k) < minorFrac * ref && Ek(k) < minorFrac * refE;   % no inhale and no exhale
    end
    % ---- step 2: a small pulse that only leads into a rest before the next inhale is a pause bump ----
    pk1 = nan(n0, 1);
    for k = 1:n0, pk1(k) = max(r(on(k):hiEnd(k))); end
    isLead = false(n0, 1);
    inh0 = find(~isMinor);
    for j = 2:numel(inh0) - 1
        k = inh0(j); kn = inh0(j + 1);
        a = on(k); b = max(a, on(kn) - 1);
        if areaE(a, b) >= exFrac * areaI(a, b) || pk1(k) >= leadFrac * pk1(kn), continue; end
        [~, ip] = max(r1(a:b)); p = a + ip - 1;
        if sum(abs(r1(p:b)) <= 2 * dS(p:b)) / fs >= restSec
            isLead(k) = true; isMinor(k) = true;
        end
    end
    clear r1
    inh = find(~isMinor);                               % inhale rows (row 1 always)

    % ---- step 3: exhale since the previous inhale vs that inhale ----
    pairR = nan(n0, 1);
    joinI = false(numel(inh), 1);
    for j = 2:numel(inh)
        a = on(inh(j - 1)); b = max(a, on(inh(j)) - 1);
        I = areaI(a, b); E = areaE(a, b);
        pairR(inh(j - 1)) = E / I;
        joinI(j) = E < exFrac * I;
    end
    if ~isempty(inh)
        a = on(inh(end)); b = hiEnd(n0);
        pairR(inh(end)) = areaE(a, b) / areaI(a, b);
    end
    grpI = cumsum(~joinI);                              % group of each inhale row
    grp = zeros(n0, 1); grp(inh) = grpI;
    for k = 2:n0, if isMinor(k), grp(k) = grp(k - 1); end, end

    % ---- build the merged rows ----
    nK = max([grp; 0]);
    keepRows = zeros(nK, 1); nP = zeros(nK, 1); nR = zeros(nK, 1); origRows = cell(nK, 1);
    inA = nan(nK, 1); exA = nan(nK, 1);
    for q = 1:nK
        mem = find(grp == q);
        kr = mem(1); last = mem(end);
        keepRows(q) = kr; nP(q) = sum(~isMinor(mem)); nR(q) = numel(mem); origRows{q} = mem';
        if numel(mem) > 1
            bmObj(kr, 5) = bmObj(last, 5); bmObj(kr, 6) = bmObj(last, 6);
            bmObj(kr, 7) = bmObj(kr, 6) - bmObj(kr, 2);
            [~, ip] = max(x(pk(mem)) - z(pk(mem)));
            bmObj(kr, [3 4 9]) = bmObj(mem(ip), [3 4 9]);
            [~, it] = min(bmObj(mem, 10));
            bmObj(kr, [10 11]) = bmObj(mem(it), [10 11]);
            bmObj(kr, 8) = bmObj(kr, 3) - (bmObj(kr, 1) + bmObj(kr, 5)) / 2;
        end
        a = on(kr); b = hiEnd(last);
        inA(q) = areaI(a, b) / fs * 1000; exA(q) = areaE(a, b) / fs * 1000;
    end
    bmObj = bmObj(keepRows, :);
    bmObj(:, 14) = 1:nK;
    if isfield(bmFeatures, 'bmObjBreathIdx')
        bmFeatures.bmObjBreathIdx = bmFeatures.bmObjBreathIdx(keepRows);
        bmFeatures.nBreathsSegmented = nK;
    end
    zA = nan(n0, 1); if n0 >= 1, zA = z(on)'; end
    nMinor = sum(isMinor);
    info = struct('rule', sprintf(['an inhale is not a new breath when the exhale since the previous inhale is < %g x ' ...
        'that inhale (signal areas below / above zero flow over [previous onset, onset)); engine onsets whose window ' ...
        'holds neither an inhale nor an exhale (< %g x the local median beyond a +-%g x swing noise band), and small ' ...
        'pulses that only lead into a >= %g-s rest before the next inhale, join the breath before'], ...
        exFrac, minorFrac, deadFrac, restSec), ...
        'exFrac', exFrac, 'deadFrac', deadFrac, 'minorFrac', minorFrac, ...
        'zeroFlow', zInfo.method, 'zeroFlowFracDwell', zInfo.fracFromFlat, ...
        'nBefore', n0, 'nAfter', nK, 'nMinor', nMinor, 'nLeadBumps', sum(isLead), 'nMerged', n0 - nK - nMinor, ...
        'nPulses', nP, 'nRows', nR, 'inhaleArea', inA, 'exhaleArea', exA, 'exInRatio', exA ./ inA, ...
        'origRows', {origRows}, 'isMinor', isMinor, 'isLeadBump', isLead, 'pulseInhaleArea', Ik / fs * 1000, 'pairExInRatio', pairR, ...
        'engineOnsetSec', on0Sec, 'zeroFlowAtOnsets', zA, 'deadBand', dRow);
    if isfield(bmFeatures, 'conditioning')
        bmFeatures.conditioning.incompleteExhaleMerge = struct('rule', info.rule, 'exFrac', exFrac, ...
            'deadFrac', deadFrac, 'minorFrac', minorFrac, 'zeroFlow', info.zeroFlow, ...
            'nBefore', n0, 'nAfter', nK, 'nMinor', nMinor, 'nMerged', info.nMerged);
    end
end

function v = getOpt(s, f, d)
    if isfield(s, f) && ~isempty(s.(f)), v = s.(f); else, v = d; end
end

function [z, zi] = zeroFlowLevel(x, fs, halfWinSec, binFrac, sideFrac, useMax, massFrac)
% Zero-flow level of a nasal-pressure trace = its DWELL level: between breaths the pressure stays at
% zero flow (end-expiratory pauses, holds) while inhales go above it and exhales below it, so within
% +-halfWinSec (10 s) zero flow is the most frequent level of the trace (histogram mode of the
% 200-ms mean at 25 Hz, bins binFrac (0.04) x the local 5-95 % range, smoothed over 3 bins). A mode
% is accepted only when the trace spends >= sideFrac (0.10) of the window both above and below it
% (beyond 2 bins): the rounded trough of a slow exhale (or plateau of a slow inhale) without a pause
% is also a dwell level but the trace sits on one side of it only (synthetic 4 cpm, no pause: would
% merge 22 -> 1 breath). Elsewhere z = the 60-s moving mean (continuous breathing; the data are
% high-passed at 0.03 Hz, so its long-run mean is near zero flow). The accepted modes are
% median-filtered over 5 s. Why a dwell level: the high-pass filter shifts the pause level after
% every breath (261007_EEG_NWU_AL 4 cpm: pauses at +10 to +20, cardiac ripple +-10 on them, so they
% never read as "flat"), and a pause's offset over 6-8 s adds up to a whole inhale's area.
    N = numel(x);
    xs = movmean(x, max(1, round(0.2 * fs)));
    dec = max(1, round(fs / 25));
    xd = xs(1:dec:end); fd = fs / dec; Nd = numel(xd);
    g = 1:fs:N;                                             % 1-s grid
    gd = min(Nd, round((g - 1) / dec) + 1);
    hw = round(halfWinSec * fd);
    zMean = movmean(x, round(60 * fs));
    zg = zMean(g); ok = false(size(g)); zm = nan(size(g));
    for i = 1:numel(g)
        w = xd(max(1, gd(i) - hw):min(Nd, gd(i) + hw));
        q = prctile(w, [5 95]); rg = q(2) - q(1);
        if ~(rg > 0), continue; end
        bw = binFrac * rg;
        edges = (min(w) - bw):bw:(max(w) + bw);
        if numel(edges) < 4, continue; end
        c = histcounts(w, edges);
        c = conv(c, [1 1 1] / 3, 'same');
        [~, im] = max(c);
        m = (edges(im) + edges(im + 1)) / 2;
        m = median(w(abs(w - m) <= bw));                    % refine within the peak (no bin-grid bias)
        up = mean(w > m + 2 * bw); dn = mean(w < m - 2 * bw); mass = mean(abs(w - m) <= bw);
        if up >= sideFrac && dn >= sideFrac && mass >= massFrac
            ok(i) = true; zm(i) = m;
        end
    end
    if any(ok)
        zf = zm; zf(ok) = movmedian(zm(ok), 5);               % over 5 accepted seconds
        if useMax, zg(ok) = max(zf(ok), zg(ok)); else, zg(ok) = zf(ok); end
    end
    z = interp1(g, zg, 1:N, 'linear', 'extrap');
    zi = struct('method', sprintf(['dwell level (histogram mode of the 200-ms mean within +-%g s, bins %g x the ' ...
        'local range, accepted when >= %g of the window lies above and below it), else the 60-s moving mean'], ...
        halfWinSec, binFrac, sideFrac), 'fracFromFlat', mean(ok));
end

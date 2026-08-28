function [bmObj, bmFeatures] = segmentBreaths_zlp(rsp, fs, floorFrac, blankBelowFrac, cySpan)
%SEGMENTBREATHS_ZLP  LOCKED per-breath segmentation engine (QC round 4, 2026-08-28).
%
%   [bmObj, bmFeatures] = segmentBreaths_zlp(rsp, fs, floorFrac, blankBelowFrac, cySpan)
%
%   Replaces segmentBreaths_breathMetrics as the shared engine for every
%   breath-based task. Segmentation (extrema + inhale onsets) is the
%   user-locked ZLP algorithm - conservative prep x kneeBacktrack rev12b,
%   iterated over ~20 live-review generations - while the per-breath FEATURE
%   set is still computed by the vendored breathMetrics toolbox, fed our
%   landmarks through its sanctioned manual-adjustment path
%   (manualAdjustPostProcess), so the bmObj/bmFeatures/behDat contracts are
%   unchanged.
%
%   Inputs
%     rsp            : 1 x N chosen respiration trace (rspIDX/rspFlip applied)
%     fs             : sampling rate (500 Hz in this pipeline)
%     floorFrac      : amplitude-normalization floor as a fraction of the
%                      median moving scale (default 0.05)
%     blankBelowFrac : zero the detection copy where the local scale falls
%                      below this fraction of the median (default none;
%                      0.10 for MS's unplugged-cannula stretch)
%     cySpan         : [startSample endSample] of the cyclicSigh block, if
%                      any - enables the keep-first-within-5s peak rule
%
%   Outputs: bmObj [nBreaths x 14] in the exact legacy layout (see
%   segmentBreaths_breathMetrics header) and bmFeatures as a plain struct
%   with the full breathMetrics per-breath feature set + conditioning record.
%
%   LOCKED ALGORITHM (rev12b; full step list in the 2026-08-28 review chat):
%   Stage 0 prep: NaN fill, 500 ms movmean, 30 s movstd normalization
%     (floor floorFrac x median), optional blanking.
%   Stage 1 extrema: prominence >= 0.6, min separation 1.0 s; peak validity
%     height >= 0.5 with a 0.5-in-1s soft-descent demand (waived >= 1.0);
%     strict alternation; 40%-of-local-half-range rise filter; cyclicSigh
%     keep-FIRST of peak pairs within 5 s.
%   Stage 2 rules: r1 not-descending (x(t)-x(t-0.33s) > -0.2), r2 rising-
%     ahead (+0.4 within max(0.4s, 25% pair) window); pairs with no dual-
%     valid sample pruned (region absorbs into neighbor).
%   Stage 3 kneeBacktrack: anchor = last valid70 point of the SECOND half
%     (fallback last eligible); free walk, stop slope < 0.50 dmax sustained
%     0.10 s; clean sweep (main walk to floor < trough+10%) -> last midpoint
%     crossing; late-landing extension (> trough+35%) slope < 0.05 dmax
%     sustained 0.15 s with revert-on-floor; rule-3 slope-contrast landing
%     refinement (1.25x); final bidirectional eligibility snap.

    if size(rsp, 1) > 1, rsp = rsp'; end
    assert(isvector(rsp) && isnumeric(rsp), 'rsp must be a numeric vector');
    if nargin < 3 || isempty(floorFrac), floorFrac = 0.05; end
    if nargin < 4, blankBelowFrac = []; end
    if nargin < 5, cySpan = []; end

    nNaN = sum(~isfinite(rsp));
    if nNaN > 0
        fprintf('segmentBreaths_zlp: %d non-finite samples (%.3f%%) filled by prep\n', ...
            nNaN, 100 * nNaN / numel(rsp));
    end
    rspFilled = fillmissing(double(rsp), 'linear', 'EndValues', 'nearest');

    % ---- locked detection ----
    [det, pk0, tr0] = prepBreathTrace_zlp(rspFilled, fs, 'conservative', blankBelowFrac, cySpan, floorFrac);
    [on, pkP, trP] = findInhaleOnsets_zlp(det, fs, pk0, tr0, 'kneeBacktrack', 0.4, 1.25, 0.50, 0.10);
    on = round(sort(on(:)'));
    assert(numel(on) >= 3, 'segmentBreaths_zlp:tooFewBreaths', ...
        'only %d inhale onsets detected - not a usable respiration trace', numel(on));

    % bm-convention per-inhale landmark arrays: inhalePeaks(k) = the pair
    % peak after onset k; exhaleTroughs(k) = the first trough after that
    % peak (strict alternation makes it the trough before the next pair's
    % peak, i.e. inside breath k). Trailing inhales with no following
    % trough are dropped (breathmetrics' simplify convention).
    n0 = numel(on);
    pkA = nan(1, n0); trA = nan(1, n0);
    for k = 1:n0
        p = pkP(pkP > on(k));
        if isempty(p), continue; end
        pkA(k) = p(1);
        t = trP(trP > pkA(k));
        if ~isempty(t), trA(k) = t(1); end
    end
    keep = isfinite(pkA);
    on = on(keep); pkA = pkA(keep); trA = trA(keep);
    while ~isempty(on) && ~isfinite(trA(end))
        on(end) = []; pkA(end) = []; trA(end) = [];
    end
    n = numel(on);
    assert(n >= 3, 'segmentBreaths_zlp:tooFewBreaths', ...
        'only %d complete breaths after landmark pairing', n);

    % ---- breathMetrics feature computation on OUR landmarks ----
    % Sanctioned manual-adjust path: set extrema, let bm derive its own
    % pause/exhale-onset estimates from them, replace the inhale onsets with
    % the locked ones, recompute the pauses from those onsets with bm's own
    % routine (same clamps as findOnsetsAndPauses), then
    % manualAdjustPostProcess recomputes offsets/durations/volumes/shape/
    % secondary features downstream of the adjusted landmarks.
    bmo = breathmetrics(det, fs, 'humanAirflow');
    bmo.correctRespirationToBaseline('sliding', 0, 0);
    respBC = bmo.baselineCorrectedRespiration(:)';
    bmo.inhalePeaks = round(pkA);
    bmo.exhaleTroughs = round(trA);
    bmo.peakInspiratoryFlows  = respBC(round(pkA));
    bmo.troughExpiratoryFlows = respBC(round(trA));
    bmo.findOnsetsAndPauses(0);
    bmo.inhaleOnsets = on;
    nBINS = floor(fs / 100); if nBINS <= 20, nBINS = 20; end
    [exP, inP] = findRespiratoryPausesNew(respBC, fs, on, round(trA), round(pkA), nBINS);
    inP = round(inP(:)'); exP = round(exP(:)');
    if numel(inP) < n, inP = [inP, nan(1, n - numel(inP))]; end
    inP = inP(1:n);
    if numel(exP) < n, exP = [exP, nan(1, n - numel(exP))]; end
    exP = exP(1:n);
    exhOn = bmo.exhaleOnsets;
    for bi = 1:n
        if ~isnan(inP(bi)) && bi <= numel(exhOn) && ~isnan(exhOn(bi)) ...
                && (inP(bi) <= pkA(bi) || inP(bi) >= exhOn(bi))
            inP(bi) = NaN;
        end
        if ~isnan(exP(bi)) && (exP(bi) <= trA(bi) || ...
                (bi + 1 <= n && exP(bi) >= on(bi + 1)))
            exP(bi) = NaN;
        end
    end
    bmo.inhalePauseOnsets = inP;
    bmo.exhalePauseOnsets = exP;
    bmo.inhaleTimeToPeak = (round(pkA) - on) / fs;
    bmo.manualAdjustPostProcess();

    % ---- bmObj in the legacy 14-column layout (raw-unit amplitudes) ----
    respRaw = rspFilled - movmean(rspFilled, round(60 * fs));
    nB = n - 1;                    % legacy: breath ends at next inhale onset
    pkI = round(pkA); trI = round(trA);
    bmObj = zeros(nB, 14);
    bmObj(:, 1)  = respRaw(on(1:nB));
    bmObj(:, 2)  = on(1:nB) / fs;
    bmObj(:, 3)  = respRaw(pkI(1:nB));
    bmObj(:, 4)  = pkI(1:nB) / fs;
    bmObj(:, 5)  = respRaw(on(2:nB+1));
    bmObj(:, 6)  = on(2:nB+1) / fs;
    bmObj(:, 7)  = bmObj(:, 6) - bmObj(:, 2);
    bmObj(:, 8)  = bmObj(:, 3) - (bmObj(:, 1) + bmObj(:, 5)) / 2;
    bmObj(:, 9)  = pkI(1:nB);
    bmObj(:, 10) = respRaw(trI(1:nB));
    bmObj(:, 11) = trI(1:nB) / fs;
    bmObj(:, 12) = 0;
    bmObj(:, 13) = 0;
    ok = all(isfinite(bmObj(:, 1:11)), 2);
    nDropped = sum(~ok);
    if nDropped > 0
        fprintf('segmentBreaths_zlp: dropped %d/%d breaths with non-finite landmarks\n', nDropped, nB);
    end
    breathIdx = find(ok);
    bmObj = bmObj(ok, :);
    bmObj(:, 14) = 1:size(bmObj, 1);

    % ---------------- plain-struct feature export ----------------
    bmFeatures = struct();
    bmFeatures.engine  = 'zlp-locked + breathmetrics features';
    bmFeatures.version = ['segmentation: ZLP rev12b (2026-08-28 QC round 4); features: ' ...
        'qhyang42/breathmetrics commit 9791153, vendored in external/breathMetrics'];
    bmFeatures.dataType = bmo.dataType;
    bmFeatures.srate    = bmo.srate;
    bmFeatures.conditioning = struct( ...
        'callerConditioning',  'none (raw chosen trace, rspIDX/rspFlip applied upstream)', ...
        'nanSamplesFilled',    nNaN, ...
        'engineVersion',       'zlp rev12b LOCKED 2026-08-28: conservative prep x kneeBacktrack (see segmentBreaths_zlp header for the full step list)', ...
        'prep',                '500 ms movmean; 30 s movstd normalization; prominence 0.6; min sep 1.0 s; peak height floor 0.5 + 0.5-in-1s descent (waived >= 1.0); 40% rise filter; cyclicSigh keep-first 5 s', ...
        'onsetMethod',         'kneeBacktrack r2=0.4 r3=1.25 dip=0.50dmax/0.10s (anchor valid70 2nd-half, sweep <10% -> midpoint, ext 0.05dmax/0.15s revert-on-floor, eligibility snap)', ...
        'windowedAmpNorm',     'detection trace = 500 ms movmean / max(movstd 30 s, floorFrac x median); raw data untouched', ...
        'ampNormWindowSec',    30, ...
        'ampNormFloorFrac',    floorFrac, ...
        'blankBelowFrac',      ternGuard(isempty(blankBelowFrac), NaN, blankBelowFrac), ...
        'cySpan',              ternGuard(isempty(cySpan), [NaN NaN], cySpan), ...
        'bmFeatureFlow',       'breathmetrics fed locked landmarks: findOnsetsAndPauses on our extrema, inhaleOnsets replaced, pauses recomputed from our onsets, manualAdjustPostProcess', ...
        'bmObjAmplitudeUnits', 'raw signal units (60 s moving-mean baseline removed at detected indices)', ...
        'featureFlowUnits',    'windowed-normalized units (locally comparable across epochs)');

    perBreath = {'inhaleOnsets', 'exhaleOnsets', 'inhaleOffsets', 'exhaleOffsets', ...
                 'inhalePeaks', 'exhaleTroughs', 'peakInspiratoryFlows', ...
                 'troughExpiratoryFlows', 'inhaleTimeToPeak', 'exhaleTimeToTrough', ...
                 'inhaleVolumes', 'exhaleVolumes', 'inhaleDurations', 'exhaleDurations', ...
                 'inhalePauseOnsets', 'exhalePauseOnsets', ...
                 'inhalePauseDurations', 'exhalePauseDurations'};
    for f = 1:numel(perBreath)
        bmFeatures.(perBreath{f}) = double(bmo.(perBreath{f})(:))';
    end
    bmFeatures.shapeFeatures = bmo.shapeFeatures;

    sec = struct();
    if ~isempty(bmo.secondaryFeatures)
        ks = bmo.secondaryFeatures.keys;
        for k = 1:numel(ks)
            sec.(matlab.lang.makeValidName(ks{k})) = bmo.secondaryFeatures(ks{k});
        end
    end
    bmFeatures.secondaryFeatures = sec;

    bmFeatures.nInhalesDetected  = n;
    bmFeatures.nBreathsSegmented = size(bmObj, 1);
    bmFeatures.nBreathsDroppedNonFinite = nDropped;
    bmFeatures.bmObjBreathIdx = breathIdx(:)';
end

function out = ternGuard(cond, a, b)
% inline conditional (MATLAB has no ternary operator)
    if cond, out = a; else, out = b; end
end

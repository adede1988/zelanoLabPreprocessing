function [bmObj, bmFeatures] = segmentBreaths_breathMetrics(rsp, fs, floorFrac, blankBelowFrac)
%SEGMENTBREATHS_BREATHMETRICS  Per-breath segmentation via the breathMetrics toolbox.
%
%   [bmObj, bmFeatures] = segmentBreaths_breathMetrics(rsp, fs, floorFrac, blankBelowFrac)
%
%   floorFrac (optional, default 0.05): the windowed amplitude normalization's
%   floor as a fraction of the median moving scale. Lower = more amplification
%   of weak stretches at the cost of amplifying dead noise.
%   blankBelowFrac (optional, default none): stretches whose local scale falls
%   below this fraction of the median scale are ZEROED in the detection copy -
%   no breaths are detected there (QC-review decision for hardware-attenuated
%   sections, e.g. MS's partially unplugged cannula tube: exclude, don't
%   amplify).
%
%   Shared breath-segmentation engine for every breath-based task
%   (Tasks_260824.md Task 3 / D8). Replaces the per-breath engine inside
%   process_respiration_breathing (breathTemplates4) while keeping the
%   downstream contract byte-compatible.
%
%   Inputs
%     rsp : 1 x N respiration trace, the CHOSEN channel with rspIDX/rspFlip
%           already applied (inhale positive), at fs (= 500 Hz in this
%           pipeline). No additional conditioning is applied by the caller.
%     fs  : sampling rate of rsp in Hz.
%
%   Outputs
%     bmObj : [nBreaths x 14] matrix in the EXACT legacy layout that
%             flagBadBreaths / build_behavior_table_breathingTask / the
%             condition-assignment loop in the *_main scripts consume:
%               col  1: onset Y value            (baseline-corrected units)
%               col  2: onset time               (SECONDS)
%               col  3: inhale-peak Y value
%               col  4: inhale-peak time         (SECONDS)
%               col  5: end Y value  (= next breath's onset Y)
%               col  6: end time     (= next inhale onset, SECONDS)
%               col  7: length (col6 - col2, SECONDS)
%               col  8: amplitude (col3 - mean(col1, col5))
%               col  9: inhale-peak SAMPLE INDEX at fs
%                       (legacy engine stored an internal 50-Hz index here;
%                        nothing downstream reads it - documented drift)
%               col 10: exhale-trough Y value
%               col 11: exhale-trough time       (SECONDS)
%               col 12: condition/block  (0 here; filled by the main script)
%               col 13: unused           (0)
%               col 14: breath index     (1..nBreaths, sequential)
%             Following the legacy engine, each breath spans inhale onset ->
%             next inhale onset, so the final detected inhale is dropped.
%             Rows with any non-finite landmark are dropped (count reported).
%
%     bmFeatures : PLAIN STRUCT (never the class object) with the complete
%             breathMetrics feature set plus a record of the signal
%             conditioning applied. Units:
%               *Onsets/*Offsets/*Peaks/*Troughs/*PauseOnsets:
%                   SAMPLE INDICES at fs (NaN where absent, e.g. no pause)
%               *Durations, *TimeToPeak/*TimeToTrough: SECONDS
%               *Volumes: sum(|amplitude|)/fs*1000 (signal-units x ms,
%                   breathmetrics' native convention)
%               peakInspiratoryFlows/troughExpiratoryFlows: baseline-corrected
%                   signal units
%               shapeFeatures: per-breath table (Sagar-et-al-style smoothness/
%                   curvature/slope features), breath_id is 0-based
%               secondaryFeatures: summary statistics struct (field names
%                   sanitised from the breathmetrics map keys)
%             Feature arrays run over ALL detected inhales (1..nInhales);
%             bmObj row k corresponds to feature index bmFeatures.bmObjBreathIdx(k).
%
%   Signal conditioning (recorded in bmFeatures.conditioning): DETECTION runs
%   on a windowed-amplitude-normalized copy of the trace (60-s moving std,
%   floored at 0.1x its median so dead stretches - e.g. an unplugged cannula -
%   are not amplified into fake breaths; added 2026-08-25 after overlay QC
%   showed the global amplitude criterion missing real breaths in quiet epochs
%   of amplitude-non-stationary recordings). breathmetrics('humanAirflow')
%   then applies its own 50-ms fftSmooth and 60-s sliding baseline correction
%   (zScore=0, simplify=1). The stored signal is NEVER modified: bmObj
%   amplitude columns (1,3,5,8,10) are re-sampled from the RAW trace (60-s
%   moving-mean baseline removed, amplitude untouched) at the detected
%   indices, so they stay in raw signal units. bmFeatures flow/volume arrays
%   are in NORMALIZED units (locally comparable across epochs by design).
%
%   Vendored toolbox: external/breathMetrics (fork qhyang42/breathmetrics,
%   commit 9791153, 2026-08-03).

    if size(rsp, 1) > 1, rsp = rsp'; end
    assert(isvector(rsp) && isnumeric(rsp), 'rsp must be a numeric vector');
    if nargin < 3 || isempty(floorFrac), floorFrac = 0.05; end
    if nargin < 4, blankBelowFrac = []; end

    % discontinuous Neuralynx recordings can carry NaN samples, which poison
    % breathmetrics' FFT smoothing; interpolate them (same policy as the cue
    % makeOutDat's fillmissing) and record how many were filled
    nNaN = sum(~isfinite(rsp));
    if nNaN > 0
        fprintf('segmentBreaths_breathMetrics: filling %d non-finite samples (%.3f%%)\n', ...
            nNaN, 100 * nNaN / numel(rsp));
        rsp = fillmissing(double(rsp), 'linear', 'EndValues', 'nearest');
    end

    ZSCORE   = 0;
    BASELINE = 'sliding';
    SIMPLIFY = 1;

    % ---- detection-copy conditioning (raw data untouched) ----
    % v3 after the 2026-08 QC review (breath_detection_qc_notes.md):
    %   1. 300-ms moving-average smoothing: merges double-peaked inhales and
    %      calms ragged stretches (over-detection / midpoint detections).
    %   2. Windowed amplitude normalization on a 30-s moving MAD scale (was
    %      60-s moving std): adapts faster at loud->quiet transitions and is
    %      not inflated by a few large neighboring breaths - fixes both the
    %      whole-minute dropouts of the un-windowed runs and the residual
    %      quiet-epoch misses of the 60-s version.
    Wn = round(30 * fs);
    sm = round(0.3 * fs);
    xs = movmean(double(rsp), sm);
    s  = 1.4826 * movmad(xs, Wn);
    sFloor = floorFrac * median(s);
    rspDet = xs ./ max(s, sFloor);
    nBlanked = 0;
    if ~isempty(blankBelowFrac)
        dead = s < blankBelowFrac * median(s);
        rspDet(dead) = 0;
        nBlanked = sum(dead);
        fprintf('segmentBreaths_breathMetrics: blanked %.1f%% of trace (local scale < %.2f x median)\n', ...
            100 * mean(dead), blankBelowFrac);
    end

    bm = breathmetrics(rspDet, fs, 'humanAirflow');
    bm.estimateAllFeatures(ZSCORE, BASELINE, SIMPLIFY, 0);

    % raw-unit trace for the bmObj amplitude columns: baseline removed on a
    % 60-s scale (matches breathmetrics' sliding correction), amplitude intact
    respRaw = double(rsp) - movmean(double(rsp), round(60 * fs));

    on   = double(bm.inhaleOnsets(:));
    pk   = double(bm.inhalePeaks(:));
    tr   = double(bm.exhaleTroughs(:));

    % ---- onset band correction (middle-50% rule, QC review item 3/4) ----
    % Onsets repeatedly landed on the exhale trough (1-3 s early) or on the
    % inhale peak (late). True onsets sit on the RISING edge in the middle of
    % the local amplitude distribution: any onset outside the local 25th-75th
    % percentile band of the detection trace is relocated to the nearest
    % upward crossing of the local 25th percentile, searching within +/-3 s
    % but never past the neighboring onsets. No crossing found = onset kept.
    engineOn = on;
    halfW = round(15 * fs);
    maxShift = round(3 * fs);
    nReloc = 0;
    N = numel(rspDet);
    for k = 1:numel(on)
        o = on(k);
        if ~isfinite(o) || o < 1 || o > N, continue; end
        segLo = max(1, o - halfW); segHi = min(N, o + halfW);
        seg = sort(rspDet(segLo:segHi));
        p25 = seg(max(1, round(0.25 * numel(seg))));
        p75 = seg(max(1, round(0.75 * numel(seg))));
        v = rspDet(o);
        if v >= p25 && v <= p75, continue; end
        lo = max([1, o - maxShift, ternGuard(k > 1, on(k-1) + 1, 1)]);
        hi = min([N - 1, o + maxShift, ternGuard(k < numel(on), on(k+1) - 1, N - 1)]);
        if hi <= lo, continue; end
        w = lo:hi;
        cross = w(rspDet(w) < p25 & rspDet(w + 1) >= p25);
        if isempty(cross), continue; end
        [~, ci] = min(abs(cross - o));
        on(k) = cross(ci) + 1;
        nReloc = nReloc + 1;
    end
    if nReloc > 0
        fprintf('segmentBreaths_breathMetrics: relocated %d/%d onsets into the middle-50%% band\n', ...
            nReloc, numel(on));
    end

    n  = numel(on);
    assert(n >= 3, 'segmentBreaths_breathMetrics:tooFewBreaths', ...
        'only %d inhale onsets detected - not a usable respiration trace', n);
    nB = n - 1;                     % legacy: breath ends at next inhale onset

    % NaN landmark indices cannot index respRaw; substitute 1 and restore NaN
    % (such rows are dropped by the non-finite filter below anyway)
    pkI = pk; pkBad = ~isfinite(pkI); pkI(pkBad) = 1;
    trI = tr; trBad = ~isfinite(trI); trI(trBad) = 1;

    bmObj = zeros(nB, 14);
    bmObj(:, 1)  = respRaw(on(1:nB));
    bmObj(:, 2)  = on(1:nB) / fs;
    bmObj(:, 3)  = respRaw(pkI(1:nB));  bmObj(pkBad(1:nB), 3) = NaN;
    bmObj(:, 4)  = pk(1:nB) / fs;
    bmObj(:, 5)  = respRaw(on(2:nB+1));
    bmObj(:, 6)  = on(2:nB+1) / fs;
    bmObj(:, 7)  = bmObj(:, 6) - bmObj(:, 2);
    bmObj(:, 8)  = bmObj(:, 3) - (bmObj(:, 1) + bmObj(:, 5)) / 2;
    bmObj(:, 9)  = pk(1:nB);
    bmObj(:, 10) = respRaw(trI(1:nB));  bmObj(trBad(1:nB), 10) = NaN;
    bmObj(:, 11) = tr(1:nB) / fs;
    bmObj(:, 12) = 0;
    bmObj(:, 13) = 0;

    % drop breaths with any non-finite landmark (downstream index conversion
    % cannot represent them); keep the mapping back to breathmetrics indices
    ok = all(isfinite(bmObj(:, 1:11)), 2);
    nDropped = sum(~ok);
    if nDropped > 0
        fprintf('segmentBreaths_breathMetrics: dropped %d/%d breaths with non-finite landmarks\n', ...
            nDropped, nB);
    end
    breathIdx = find(ok);
    bmObj = bmObj(ok, :);
    bmObj(:, 14) = 1:size(bmObj, 1);

    % ---------------- plain-struct feature export ----------------
    bmFeatures = struct();
    bmFeatures.engine  = 'breathmetrics';
    bmFeatures.version = 'qhyang42/breathmetrics commit 9791153 (2026-08-03), vendored in external/breathMetrics';
    bmFeatures.dataType = bm.dataType;
    bmFeatures.srate    = bm.srate;
    bmFeatures.conditioning = struct( ...
        'callerConditioning',   'none (raw chosen trace, rspIDX/rspFlip applied upstream)', ...
        'nanSamplesFilled',     nNaN, ...
        'engineVersion',        'v3 (2026-08-26 QC review: smoothing + 30 s movmad window + onset band correction)', ...
        'detectionSmoothing',   '300 ms moving mean before normalization', ...
        'windowedAmpNorm',      'detection trace = smoothed / max(1.4826 x movmad(smoothed, 30 s), floorFrac x median); raw data untouched', ...
        'ampNormWindowSec',     30, ...
        'ampNormFloorFrac',     floorFrac, ...
        'ampNormFloor',         sFloor, ...
        'blankBelowFrac',       ternGuard(isempty(blankBelowFrac), NaN, blankBelowFrac), ...
        'nSamplesBlanked',      nBlanked, ...
        'onsetBandCorrection',  'onsets outside the local 25-75th percentile band relocated to the nearest upward p25 crossing (+/-3 s, within neighboring onsets)', ...
        'nOnsetsRelocated',     nReloc, ...
        'bmObjAmplitudeUnits',  'raw signal units (60 s moving-mean baseline removed at detected indices)', ...
        'featureFlowUnits',     'windowed-normalized units (locally comparable across epochs)', ...
        'smoothing',            'breathmetrics fftSmooth, 50 ms window (humanAirflow default), after the 300 ms detection smoothing', ...
        'baselineCorrection',   [BASELINE ' (60 s sliding window)'], ...
        'zScore',               ZSCORE, ...
        'simplify',             SIMPLIFY);

    perBreath = {'inhaleOnsets', 'exhaleOnsets', 'inhaleOffsets', 'exhaleOffsets', ...
                 'inhalePeaks', 'exhaleTroughs', 'peakInspiratoryFlows', ...
                 'troughExpiratoryFlows', 'inhaleTimeToPeak', 'exhaleTimeToTrough', ...
                 'inhaleVolumes', 'exhaleVolumes', 'inhaleDurations', 'exhaleDurations', ...
                 'inhalePauseOnsets', 'exhalePauseOnsets', ...
                 'inhalePauseDurations', 'exhalePauseDurations'};
    for f = 1:numel(perBreath)
        bmFeatures.(perBreath{f}) = double(bm.(perBreath{f})(:))';
    end
    % band-corrected onsets replace the engine's; originals kept alongside
    bmFeatures.engineInhaleOnsets = double(engineOn(:))';
    bmFeatures.inhaleOnsets = double(on(:))';
    bmFeatures.shapeFeatures = bm.shapeFeatures;    % per-breath table

    % containers.Map -> struct with sanitised field names
    sec = struct();
    if ~isempty(bm.secondaryFeatures)
        ks = bm.secondaryFeatures.keys;
        for k = 1:numel(ks)
            sec.(matlab.lang.makeValidName(ks{k})) = bm.secondaryFeatures(ks{k});
        end
    end
    bmFeatures.secondaryFeatures = sec;

    bmFeatures.nInhalesDetected  = n;
    bmFeatures.nBreathsSegmented = size(bmObj, 1);
    bmFeatures.nBreathsDroppedNonFinite = nDropped;
    bmFeatures.bmObjBreathIdx = breathIdx(:)';   % bmObj row k <-> feature index
end

function out = ternGuard(cond, a, b)
% inline conditional (MATLAB has no ternary operator)
    if cond, out = a; else, out = b; end
end

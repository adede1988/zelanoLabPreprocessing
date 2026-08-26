function [bmObj, bmFeatures] = segmentBreaths_breathMetrics(rsp, fs)
%SEGMENTBREATHS_BREATHMETRICS  Per-breath segmentation via the breathMetrics toolbox.
%
%   [bmObj, bmFeatures] = segmentBreaths_breathMetrics(rsp, fs)
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

    % windowed amplitude normalization for DETECTION ONLY (raw data untouched)
    W = round(60 * fs);
    s = movstd(double(rsp), W);
    sFloor = 0.1 * median(s);
    rspDet = double(rsp) ./ max(s, sFloor);

    bm = breathmetrics(rspDet, fs, 'humanAirflow');
    bm.estimateAllFeatures(ZSCORE, BASELINE, SIMPLIFY, 0);

    % raw-unit trace for the bmObj amplitude columns: baseline removed on the
    % same 60-s scale as breathmetrics' sliding correction, amplitude intact
    respRaw = double(rsp) - movmean(double(rsp), W);

    on   = double(bm.inhaleOnsets(:));
    pk   = double(bm.inhalePeaks(:));
    tr   = double(bm.exhaleTroughs(:));

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
        'windowedAmpNorm',      'detection trace = raw / max(movstd(raw, 60 s), 0.1 x median movstd); raw data untouched', ...
        'ampNormWindowSec',     60, ...
        'ampNormFloor',         sFloor, ...
        'bmObjAmplitudeUnits',  'raw signal units (60 s moving-mean baseline removed at detected indices)', ...
        'featureFlowUnits',     'windowed-normalized units (locally comparable across epochs)', ...
        'smoothing',            'breathmetrics fftSmooth, 50 ms window (humanAirflow default)', ...
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

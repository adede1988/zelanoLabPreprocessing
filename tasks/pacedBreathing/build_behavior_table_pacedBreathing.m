function outDat = build_behavior_table_pacedBreathing(outDat)
%BUILD_BEHAVIOR_TABLE_PACEDBREATHING  Per-breath behDat for pacedBreathing.
%
%   Breathing-layout columns from bmObj (one row per detected breath, whole
%   recording - the inferred blocks tile the recording so every breath has
%   one); condition = inferred block index (bmObj col 12, set by the main
%   from outDat.blocks), task = the block's positional label ('pre' /
%   'paced' / 'final'); noseMouth/shadowFile/warp kept as NA/NaN for
%   downstream compatibility; no rating columns / baseEmotion (there is no
%   behavioral file). bm_* feature columns appended as in the other
%   breath-based tasks.
%
%   Extra per-breath columns for this task (the paced breathing is often
%   ragged / forced, so a per-breath regularity measure travels with each
%   breath):
%     rateBPM        60 / length
%     localPeriodCV  CV of breath length over the +/-3 surrounding breaths
%     localAmpCV     CV of amplitude over the same window
%     nSubPeaks      number of local maxima (prominence >= 15% of the breath
%                    amplitude, 100-ms smoothed trace) between this inhale
%                    onset and the next - 1 = a clean single-peaked breath,
%                    more = ragged / multi-effort breath
%     nearSeam       true when the breath comes within 5 s of a recording seam
%                    (outDat.segments, multi-file acquisitions) - exclude in analyses

    bmObj = outDat.bmObj;
    B = outDat.blocks;
    n = size(bmObj, 1);

    behDat = behDatFromBreaths(bmObj, size(outDat.data, 2), outDat.fs);   % shared 14 base columns
    idx = behDat.sniffOnset;                     % inhale-onset samples (used below)
    blk = bmObj(:, 12);
    assert(all(blk >= 1 & blk <= height(B)), 'build_behavior_table_pacedBreathing: block index out of range');
    behDat.task       = cellstr(B.label(blk));
    behDat.noseMouth  = repmat("NA", n, 1);
    behDat.shadowFile = repmat("NA", n, 1);
    behDat.warp       = nan(n, 1);

    % ---- task extras: rate + local regularity + sub-peak count ----
    behDat.rateBPM = 60 ./ behDat.length;
    per = behDat.length; amp = behDat.amp;
    behDat.localPeriodCV = nan(n, 1);
    behDat.localAmpCV    = nan(n, 1);
    for b = 1:n
        w = max(1, b - 3):min(n, b + 3);
        w = w(blk(w) == blk(b));                 % never straddle a block boundary
        if numel(w) >= 4
            behDat.localPeriodCV(b) = std(per(w)) / mean(per(w));
            behDat.localAmpCV(b)    = std(amp(w)) / mean(amp(w));
        end
    end

    isRsp = cellfun(@(x) contains(x, 'rsp'), outDat.labels);
    rsp = outDat.data(isRsp, :);
    rsp = rsp(outDat.rspIDX, :) .* outDat.rspFlip;
    rspS = smoothdata(rsp, 'gaussian', round(0.1 * outDat.fs));
    behDat.nSubPeaks = nan(n, 1);
    for b = 1:n
        s0 = idx(b);
        if b < n, s1 = idx(b + 1) - 1; else, s1 = min(numel(rspS), s0 + round(behDat.length(b) * outDat.fs)); end
        if s1 - s0 < round(0.3 * outDat.fs) || ~isfinite(amp(b)) || amp(b) <= 0, continue; end
        seg = rspS(s0:s1);
        [~, pk] = findpeaks(seg, 'MinPeakProminence', 0.15 * amp(b), ...
                            'MinPeakDistance', max(1, round(0.15 * outDat.fs)));
        behDat.nSubPeaks(b) = numel(pk);
    end

    % ---- breaths at a recording seam ----
    % multi-file acquisitions are stitched end to end (no gap samples), so a
    % breath whose window [onset, onset + length] comes within 5 s of a seam
    % spans a discontinuity in respiration, ECG and RRint: flagged here so
    % analyses can exclude it (goodBreath itself is the shared flagBadBreaths
    % result and is left alone)
    behDat.nearSeam = false(n, 1);
    if isfield(outDat, 'segments') && istable(outDat.segments) && height(outDat.segments) > 1
        seamPad = round(5 * outDat.fs);
        seams = outDat.segments.startSample(2:end);
        bEnd = idx + round(behDat.length * outDat.fs);
        for k = 1:numel(seams)
            behDat.nearSeam = behDat.nearSeam | (idx - seamPad <= seams(k) & bEnd + seamPad >= seams(k));
        end
    end

    outDat.behDat = behDat;

    % ---- bm_* columns (shared convention, D8e) ----
    outDat = appendBmFeatureCols(outDat, 'build_behavior_table_pacedBreathing');
end

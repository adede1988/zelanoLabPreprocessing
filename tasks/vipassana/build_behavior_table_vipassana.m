function outDat = build_behavior_table_vipassana(outDat)
%BUILD_BEHAVIOR_TABLE_VIPASSANA  Per-breath behDat for vipassana.
%
%   outDat = build_behavior_table_vipassana(outDat)
%
%   Breathing-layout columns from bmObj (one row per detected breath, whole
%   recording - the inferred protocol blocks (inferBlocks_vipassana) tile the
%   recording so every breath falls in exactly one, set by the main on
%   bmObj(:,12) before calling this); condition = that block index, task =
%   the block's FIXED protocol label (outDat.blocks.label; unlike
%   pacedBreathing these are not positional guesses), still = whether the
%   block is a task/meditation period (1) or a questionnaire/pre/post period
%   (0, outDat.blocks.still). noseMouth/shadowFile/warp kept as NA/NaN for
%   downstream compatibility with the other breath-based tasks; no rating
%   columns / baseEmotion (there is no behavioral file). bm_* feature columns
%   appended as in the other breath-based tasks.
%
%   Extra per-breath columns for this task (copied from
%   tasks/pacedBreathing/build_behavior_table_pacedBreathing.m - the
%   meditation styles differ enough in pace/depth that a per-breath
%   regularity measure is useful downstream):
%     rateBPM        60 / length
%     localPeriodCV  CV of breath length over the +/-3 surrounding breaths
%                     (never crosses a block boundary)
%     localAmpCV     CV of amplitude over the same window
%     nSubPeaks      number of local maxima (prominence >= 15% of the breath
%                    amplitude, 100-ms smoothed trace) between this inhale
%                    onset and the next - 1 = a clean single-peaked breath,
%                    more = ragged / multi-effort breath
%
%   MUST also work with zero breaths: when respiration is not viable
%   (probeRespViability_vipassana), the main passes bmObj = zeros(0,14) and
%   this builds an empty (0-row) behDat with every column present, so
%   downstream code that reads outDat.behDat.<col> never hits a missing
%   field.

    bmObj = outDat.bmObj;
    B = outDat.blocks;
    n = size(bmObj, 1);

    behDat = behDatFromBreaths(bmObj, size(outDat.data, 2), outDat.fs);   % shared 14 base columns
    idx = behDat.sniffOnset;                     % inhale-onset samples (used below)
    blk = bmObj(:, 12);
    assert(all(blk >= 1 & blk <= height(B)), 'build_behavior_table_vipassana: block index out of range');
    behDat.task       = cellstr(B.label(blk));
    behDat.still      = double(B.still(blk));
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

    outDat.behDat = behDat;

    % ---- bm_* columns (shared convention, D8e) ----
    outDat = appendBmFeatureCols(outDat, 'build_behavior_table_vipassana');
end

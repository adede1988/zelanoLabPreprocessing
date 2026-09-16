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

    bmObj = outDat.bmObj;
    B = outDat.blocks;
    n = size(bmObj, 1);

    behDat = table();
    tim = (1:size(outDat.data, 2)) / outDat.fs;
    idx = arrayfun(@(x) find(x <= tim, 1), bmObj(:, 2));
    behDat.sniffOnset = idx;
    behDat.finalOnset = idx;
    behDat.manOnset   = nan(size(idx));
    behDat.condition  = bmObj(:, 12);
    behDat.Yonset     = bmObj(:, 1);
    behDat.inhaleMax  = bmObj(:, 3);
    behDat.inMaxTim   = arrayfun(@(x) find(x <= tim, 1), bmObj(:, 4));
    behDat.Yend       = bmObj(:, 5);
    behDat.endTim     = arrayfun(@(x) find(x <= tim, 1), bmObj(:, 6));
    behDat.length     = bmObj(:, 7);
    behDat.amp        = bmObj(:, 8);
    behDat.exhaleMin  = bmObj(:, 10);
    behDat.exMinTim   = arrayfun(@(x) find(x <= tim, 1), bmObj(:, 11));
    behDat.index      = bmObj(:, 14);
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

    outDat.behDat = behDat;

    % ---- bm_* columns (shared convention, D8e) ----
    if isfield(outDat, 'bmFeatures') && isfield(outDat.bmFeatures, 'bmObjBreathIdx')
        F  = outDat.bmFeatures;
        bi = F.bmObjBreathIdx(:);
        if numel(bi) == n
            perBreath = {'inhaleOnsets', 'exhaleOnsets', 'inhaleOffsets', 'exhaleOffsets', ...
                         'inhalePeaks', 'exhaleTroughs', 'peakInspiratoryFlows', ...
                         'troughExpiratoryFlows', 'inhaleTimeToPeak', 'exhaleTimeToTrough', ...
                         'inhaleVolumes', 'exhaleVolumes', 'inhaleDurations', 'exhaleDurations', ...
                         'inhalePauseOnsets', 'exhalePauseOnsets', ...
                         'inhalePauseDurations', 'exhalePauseDurations', ...
                         'inhaleVolumesRaw', 'exhaleVolumesRaw'};
            for f = 1:numel(perBreath)
                fld = perBreath{f};
                if isfield(F, fld) && numel(F.(fld)) >= max(bi)
                    v = F.(fld)(:);
                    outDat.behDat.(['bm_' fld]) = v(bi);
                end
            end
            if isfield(F, 'shapeFeatures') && istable(F.shapeFeatures) ...
                    && height(F.shapeFeatures) >= max(bi)
                sv = F.shapeFeatures.Properties.VariableNames;
                for f = 1:numel(sv)
                    if strcmp(sv{f}, 'breath_id'), continue; end
                    v = F.shapeFeatures.(sv{f});
                    outDat.behDat.(['bm_' sv{f}]) = v(bi);
                end
            end
        else
            warning('build_behavior_table_pacedBreathing:bmMisaligned', ...
                '%s: feature map misaligned; bm_* columns skipped', outDat.sessID);
        end
    end
end

function outDat = build_behavior_table_alternating6Blocks(outDat)
%BUILD_BEHAVIOR_TABLE_ALTERNATING6BLOCKS  Per-breath behDat for Task 8 (D11d).
%
%   Breathing-layout columns; ONLY breaths whose inhale onset falls inside a
%   block are kept; task = block label, condition = block order; rating
%   columns <Q_short>_<type> broadcast to every breath of the block (the set
%   recorded AFTER that block); baseEmotion = the baseline (order 0) set.
%   bm_* feature columns appended as in the breathing task.
%
%   Consumes outDat.bmObj/bmFeatures, outDat.blocks (fs=500 samples) and the
%   ratings table stored in outDat.behDat by the makeOutDat.

    ratings = outDat.behDat;      % long-format ratings from parse_mindfulBreathing
    B = outDat.blocks;
    bmObj = outDat.bmObj;

    onsetSamp = round(bmObj(:, 2) * outDat.fs);
    blkIdx = zeros(size(onsetSamp));
    for b = 1:height(B)
        in = onsetSamp >= B.startSample(b) & onsetSamp <= B.endSample(b);
        blkIdx(in) = b;
    end
    keep = blkIdx > 0;
    fprintf('%s: %d/%d breaths inside the %d blocks (dropped %d between-block)\n', ...
        outDat.sessID, sum(keep), numel(keep), height(B), sum(~keep));

    bmObj(:, 12) = blkIdx;        % condition = block order
    bmObj = bmObj(keep, :);
    blkIdx = blkIdx(keep);
    bmObj(:, 14) = 1:size(bmObj, 1);
    if isfield(outDat, 'bmFeatures') && isfield(outDat.bmFeatures, 'bmObjBreathIdx')
        outDat.bmFeatures.bmObjBreathIdx = outDat.bmFeatures.bmObjBreathIdx(keep);
    end
    outDat.bmObj = bmObj;

    % ---- breathing-layout table ----
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
    behDat.task       = cellstr(B.label(blkIdx));   % block label (D11d)

    % breathing columns that don't apply here are kept as NA (same policy as
    % Task 9 / D12c so downstream code finds them)
    n = height(behDat);
    behDat.noseMouth  = repmat("NA", n, 1);
    behDat.shadowFile = repmat("NA", n, 1);
    behDat.warp       = nan(n, 1);

    % ---- rating columns: the set AFTER block k (order == k) ----
    % NaN-prefilled so an unrated block reads NaN, not an auto-created 0
    Qs = unique(ratings.Q_short, 'stable');
    for q = 1:numel(Qs)
        r0 = find(ratings.Q_short == Qs(q), 1);
        behDat.(char(Qs(q) + "_" + ratings.type(r0))) = nan(n, 1);
    end
    for q = 1:numel(Qs)
        for b = 1:height(B)
            m = ratings.order == B.order(b) & ratings.Q_short == Qs(q);
            if ~any(m), continue; end
            r1 = find(m, 1);
            varName = char(Qs(q) + "_" + ratings.type(r1));
            behDat.(varName)(blkIdx == b) = ratings.rsp(r1);
        end
    end

    outDat.behDat = behDat;

    % ---- baseEmotion: the baseline (order 0) set ----
    baseEmotion = table();
    baseEmotion.task = "baseline";
    baseEmotion.noseMouth = "NA";
    baseEmotion.shadowFile = "NA";
    baseEmotion.warp = NaN;
    m0 = ratings.order == 0;
    q0 = ratings(m0, :);
    for r = 1:height(q0)
        baseEmotion.(char(q0.Q_short(r) + "_" + q0.type(r))) = q0.rsp(r);
    end
    outDat.baseEmotion = baseEmotion;

    % ---- bm_* columns (shared convention, D8e) ----
    if isfield(outDat, 'bmFeatures') && isfield(outDat.bmFeatures, 'bmObjBreathIdx')
        F  = outDat.bmFeatures;
        bi = F.bmObjBreathIdx(:);
        if numel(bi) == height(outDat.behDat)
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
            warning('build_behavior_table_alternating6Blocks:bmMisaligned', ...
                '%s: feature map misaligned; bm_* columns skipped', outDat.sessID);
        end
    end
end

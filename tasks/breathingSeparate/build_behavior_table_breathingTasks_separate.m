function outDat = build_behavior_table_breathingTasks_separate(outDat)
%BUILD_BEHAVIOR_TABLE_BREATHINGTASKS_SEPARATE  Per-breath behDat (Task 9 / D12c).
%
%   Breathing-layout columns from the concatenated bmObj; task = the
%   section's canonical condition label, condition = section index;
%   shadowFile/warp/noseMouth kept and filled with NA/NaN; no rating columns
%   and no baseEmotion (dropped by design); bm_* feature columns appended.

    bmObj = outDat.bmObj;
    sec = outDat.sections;

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
    behDat.task       = cellstr(sec.label(bmObj(:, 12)));
    n = height(behDat);
    behDat.noseMouth  = repmat("NA", n, 1);
    behDat.shadowFile = repmat("NA", n, 1);
    behDat.warp       = nan(n, 1);

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
            warning('build_behavior_table_breathingTasks_separate:bmMisaligned', ...
                '%s: feature map misaligned; bm_* columns skipped', outDat.sessID);
        end
    end
end

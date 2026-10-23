function outDat = appendBmFeatureCols(outDat, callerTag)
%APPENDBMFEATURECOLS  SHARED: append the breathMetrics bm_* columns to outDat.behDat.
%
%   outDat = appendBmFeatureCols(outDat, callerTag)
%
%   Tasks_260824.md D8e: every breath-type behDat keeps its own columns and
%   gets the per-breath feature set of outDat.bmFeatures appended as bm_*
%   columns, aligned to the behDat rows through bmFeatures.bmObjBreathIdx:
%     - the per-breath vectors listed below (when present and long enough)
%     - every shapeFeatures table variable except breath_id
%   Nothing is added when outDat has no bmFeatures / bmObjBreathIdx. When the
%   index does not match the behDat rows the columns are skipped with the
%   warning <callerTag>:bmMisaligned (callerTag = the builder's name).

    if ~(isfield(outDat, 'bmFeatures') && isfield(outDat.bmFeatures, 'bmObjBreathIdx'))
        return;
    end
    F  = outDat.bmFeatures;
    bi = F.bmObjBreathIdx(:);
    nRows = height(outDat.behDat);
    if numel(bi) ~= nRows
        warning([callerTag ':bmMisaligned'], ...
            '%s: bmObjBreathIdx (%d) does not match behDat rows (%d); bm_* columns skipped', ...
            outDat.sessID, numel(bi), nRows);
        return;
    end

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
end

function outDat = build_behavior_table_emotionalMovieTask(outDat)
%BUILD_BEHAVIOR_TABLE_EMOTIONALMOVIETASK  Per-breath behDat for the movie task.
%
%   outDat = build_behavior_table_emotionalMovieTask(outDat)
%
%   D10 (Tasks_260824.md): breathing-layout per-breath table plus clip columns;
%   ONLY breaths whose inhale onset falls inside a clip window are kept —
%   between-clip and otherwise unassociated breaths are dropped. The final clip
%   has no defined end (the old pipeline's clip-end rule is "next onset -
%   1.6 s"; there is no next onset), so its breaths are among the dropped and
%   this is reported.
%
%   Consumes outDat.bmObj / outDat.bmFeatures (segmentBreaths_breathMetrics)
%   and outDat.TTL (clip table in fs=500 samples). bmObj col 12 gets the clip
%   valence code (1 neutral / 2 happy / 3 sad, matching the old pipeline).

    bmObj = outDat.bmObj;
    T = outDat.TTL;

    % assign each breath to a clip by inhale-onset sample
    onsetSamp = round(bmObj(:, 2) * outDat.fs);
    clipIdx = zeros(size(onsetSamp));
    for c = 1:height(T)
        if ~isfinite(T.clipEnd(c)), continue; end
        in = onsetSamp >= T.clipOnset(c) & onsetSamp <= T.clipEnd(c);
        clipIdx(in) = c;
    end
    keep = clipIdx > 0;
    fprintf('%s: %d/%d breaths fall inside the %d bounded clip windows (dropped %d incl. final-clip/between-clip)\n', ...
        outDat.sessID, sum(keep), numel(keep), sum(isfinite(T.clipEnd)), sum(~keep));
    assert(sum(keep) > 0, 'build_behavior_table_emotionalMovieTask:noBreaths', ...
        '%s: no breaths fall inside any clip window - inspect the clip TTLs', outDat.sessID);

    bmObj(:, 12) = 0;
    bmObj(keep, 12) = T.nPulses(clipIdx(keep));   % valence code, old convention

    % trim to in-clip breaths and renumber
    bmObj = bmObj(keep, :);
    clipIdx = clipIdx(keep);
    bmObj(:, 14) = 1:size(bmObj, 1);
    if isfield(outDat, 'bmFeatures') && isfield(outDat.bmFeatures, 'bmObjBreathIdx')
        outDat.bmFeatures.bmObjBreathIdx = outDat.bmFeatures.bmObjBreathIdx(keep);
    end
    outDat.bmObj = bmObj;

    % ---- breathing-layout table (build_behavior_table_breathingTask core) ----
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

    % clip columns (D10)
    behDat.clipIndex   = clipIdx;
    behDat.clipValence = T.valence(clipIdx);
    behDat.clipOnset   = T.clipOnset(clipIdx);
    % block-type column in the breathing convention (also keeps flagBadBreaths
    % happy, which reads behDat.task)
    behDat.task = cellstr(T.valence(clipIdx));

    outDat.behDat = behDat;

    % ---- breathMetrics per-breath features as bm_* columns (D8e) ----
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
            warning('build_behavior_table_emotionalMovieTask:bmMisaligned', ...
                '%s: feature map misaligned; bm_* columns skipped', outDat.sessID);
        end
    end
end

function outDat = concatSections(segs, S, P)
%CONCATSECTIONS  Concatenate per-condition processed segments (Task 9 / D12b).
%
%   outDat = concatSections(segs, S, P)
%
%   segs is a struct array; each element is a fully processed single-condition
%   outDat (downsampled, EEG/macros done, bmObj/bmFeatures from
%   segmentBreaths_breathMetrics, ECG done when present) plus .label /
%   .condition / .srcFile. Labels are required to match across segments.
%
%   Concatenates data (and every derived channel) along time, offsets bmObj
%   (col 2/4/6/11 seconds, col 9 samples; col 12 = section index; col 14
%   renumbered), bmFeatures per-breath arrays (sample-index fields offset,
%   bmObjBreathIdx re-based), heartBeats. Section bookkeeping goes to
%   outDat.sections and the breathing-style boundary vector
%   outDat.TTL = [start_1 end_1 start_2 end_2 ...] (samples, concatenated).

    nSeg = numel(segs);
    for c = 2:nSeg
        % assert() evaluates message args eagerly - keep the strjoins inside
        % the failure branch
        if ~isequal(segs(c).od.labels(:), segs(1).od.labels(:))
            error('%s: processed-segment labels differ (%s vs %s) - strict failure', ...
                S.id, strjoin(segs(1).od.labels, ','), strjoin(segs(c).od.labels, ','));
        end
        assert(segs(c).od.fs == segs(1).od.fs, 'fs differs across segments');
    end

    outDat = segs(1).od;                    % carries labels/fs/EEG metadata
    outDat.sessID = S.id;
    outDat.task   = P.task;

    sampIdxFields = {'inhaleOnsets', 'exhaleOnsets', 'inhaleOffsets', 'exhaleOffsets', ...
                     'inhalePeaks', 'exhaleTroughs', 'inhalePauseOnsets', 'exhalePauseOnsets'};
    otherPerBreath = {'peakInspiratoryFlows', 'troughExpiratoryFlows', ...
                      'inhaleTimeToPeak', 'exhaleTimeToTrough', 'inhaleVolumes', ...
                      'exhaleVolumes', 'inhaleDurations', 'exhaleDurations', ...
                      'inhalePauseDurations', 'exhalePauseDurations', ...
                      'inhaleVolumesRaw', 'exhaleVolumesRaw'};

    data = []; bmObj = []; hb = []; F = struct();
    secTab = table('Size', [nSeg 4], ...
        'VariableTypes', {'string', 'string', 'double', 'double'}, ...
        'VariableNames', {'label', 'sourceFile', 'startSample', 'endSample'});
    eegQC = cell(nSeg, 1);
    featOffset = 0; sampOffset = 0;
    dataLap = []; lapOK = true;
    for c = 1:nSeg
        od = segs(c).od;
        n  = size(od.data, 2);
        offSec = sampOffset / od.fs;

        b = od.bmObj;
        b(:, [2 4 6 11]) = b(:, [2 4 6 11]) + offSec;
        b(:, 9)  = b(:, 9) + sampOffset;
        b(:, 12) = c;
        bmObj = [bmObj; b]; %#ok<AGROW>

        f = od.bmFeatures;
        for k = 1:numel(sampIdxFields)
            if isfield(f, sampIdxFields{k})
                F = appendFeat(F, sampIdxFields{k}, f.(sampIdxFields{k}) + sampOffset);
            end
        end
        for k = 1:numel(otherPerBreath)
            if isfield(f, otherPerBreath{k})
                F = appendFeat(F, otherPerBreath{k}, f.(otherPerBreath{k}));
            end
        end
        if isfield(f, 'shapeFeatures') && istable(f.shapeFeatures)
            if ~isfield(F, 'shapeFeatures'), F.shapeFeatures = f.shapeFeatures;
            else, F.shapeFeatures = [F.shapeFeatures; f.shapeFeatures]; end
        end
        F = appendFeat(F, 'bmObjBreathIdx', f.bmObjBreathIdx + featOffset);
        F.secondaryFeaturesPerSection{c} = f.secondaryFeatures;
        F.conditioningPerSection{c} = f.conditioning;
        featOffset = featOffset + f.nInhalesDetected;

        if isfield(od, 'heartBeats')
            hb = [hb, od.heartBeats(:)' + sampOffset]; %#ok<AGROW>
        end
        if isfield(od, 'dataLap') && ~isempty(od.dataLap) && lapOK
            dataLap = [dataLap, od.dataLap]; %#ok<AGROW>
        else
            lapOK = false;
        end

        secTab(c, :) = {string(segs(c).label), string(segs(c).srcFile), ...
                        sampOffset + 1, sampOffset + n};
        % per-section EEG QC metadata (interpolation/cleaning are per segment)
        q = struct();
        for fq = {'badChans', 'EEGInterpolation', 'EEGCleaning', 'blinkRemoval', 'dataLapFromInterp'}
            if isfield(od, fq{1}), q.(fq{1}) = od.(fq{1}); end
        end
        eegQC{c} = q;
        data = [data, od.data]; %#ok<AGROW>
        sampOffset = sampOffset + n;
    end

    bmObj(:, 14) = 1:size(bmObj, 1);
    F.engine = segs(1).od.bmFeatures.engine;
    F.version = segs(1).od.bmFeatures.version;
    F.dataType = segs(1).od.bmFeatures.dataType;
    F.srate = segs(1).od.bmFeatures.srate;
    F.nBreathsSegmented = size(bmObj, 1);

    outDat.data = data;
    outDat.bmObj = bmObj;
    outDat.bmFeatures = F;
    if ~isempty(hb), outDat.heartBeats = hb; end
    if lapOK, outDat.dataLap = dataLap; else, outDat.dataLap = []; end
    outDat.sections = secTab;
    outDat.eegQCPerSection = eegQC;   % top-level fields still describe section 1
    outDat.TTL = reshape([secTab.startSample'; secTab.endSample'], 1, []);
end

function F = appendFeat(F, name, v)
    v = v(:)';
    if ~isfield(F, name), F.(name) = v; else, F.(name) = [F.(name), v]; end
end

function outDat = concatSections(segs, S, P)
%CONCATSECTIONS  Concatenate per-condition processed segments (Task 9 / D12b).
%
%   outDat = concatSections(segs, S, P)
%
%   segs is a struct array; each element is a fully processed single-condition
%   outDat (downsampled, EEG/macros done, bmObj/bmFeatures from
%   segmentBreaths_zlp, ECG done when present) plus .label /
%   .condition / .srcFile. Labels are required to match across segments.
%
%   Concatenates data (and every derived channel) along time, offsets bmObj
%   (col 2/4/6/11 seconds, col 9 samples; col 12 = section index; col 14
%   renumbered), bmFeatures per-breath arrays (sample-index fields offset,
%   bmObjBreathIdx re-based), heartBeats. Section bookkeeping goes to
%   outDat.sections and the breathing-style boundary vector
%   outDat.TTL = [start_1 end_1 start_2 end_2 ...] (samples, concatenated).
%
%   Breath merge (2026-10-22): each section's od.breathMerge (applyBreathMerge, run per
%   recording after the engine) is concatenated into outDat.breathMerge - the per-breath
%   arrays nPulses / nRows / inhaleArea / exhaleArea / exInRatio in bmObj order, the counts
%   summed, every section's full record in .perSection (empty = not segmented) - so
%   build_behavior_table_breathingTasks_separate can add nInhalePulses etc. Section 1's own
%   od.carry (respiration carry, carryRespFromFinal) is replaced by the session record the
%   main builds with carryFinishFromFinal.
%
%   Per-condition settings (tasks_261014; each only when its P field exists,
%   so sessions without them get exactly the previous outDat):
%     P.condTrimSec      -> sections.trimStartSec/trimEndSec/rawFirstSample/
%                           rawLastSample/rawSamples (+ outDat.trimNote): final
%                           sample s of section b <-> raw sample
%                           (s - startSample(b)) * origFS/fs + rawFirstSample(b)
%     P.condBeatSpec     -> sections.beatSpec, only when the specs differ
%     blink removal      -> a section whose EEG stage did not remove blinks
%                           (blinkRemoval 0) has no blinkIndicator row. When
%                           another section has one - or none does, a sleep-only
%                           session (G2d, 2026-10-22) - an all-zero row (the
%                           blink stage did not run there: no blink marks -
%                           the row marks frontal blink-reference peaks where
%                           it ran - and nothing removed) is inserted before
%                           its badTS row
%                           so the labels match - whatever the reason
%                           (2026-10-20, guessReview_261015 G2c): switched off
%                           by the condition default (config/sepConditionInfo:
%                           sleep / sleepWithOdor, G2b) or by P.condBlinkRemoval
%                           (sepSectionP), <= 10 good channels after the
%                           detector, the blink-stage gate
%                           (EEGCleaningInfo.blinkGate), both blink channels
%                           bad. Any other label difference still errors.
%                           Recorded (when a section was switched off, a row
%                           was inserted, or P.condBlinkRemoval exists) in
%                           sections.blinkRemoval (0/1) / blinkSkipped
%                           (switched off by a setting) / blinkSkipReason
%                           ("" = blink removal ran) / blinkFilled (zero row
%                           inserted) + outDat.blinkNote
%     P.condRespSkip     -> sections.respSkipped (0/2), outDat.respSkipped
%                           (0 none / 1 some / 2 all sections) + respNote;
%                           a skipped section contributes no breaths
%     P.condMinIBI       -> sections.minIBI (s; NaN = not set for that
%                           recording) - processECG's beat pruning / RR floor

    nSeg = numel(segs);
    % sections whose EEG stage removed no blinks (blinkRemoval 0, for any
    % reason - blinkSkipReason) lack the blinkIndicator row preprocess_eeg
    % adds when blink removal runs: insert an all-zero one where another
    % section has it (G2c, 2026-10-20), and, when NO section ran blink removal
    % (a sleep-only session), in every section (G2d, 2026-10-22: the row is
    % there in every final that has an EEG stage, all zero where nothing ran).
    % A section with blinkRemoval 1, or no EEG stage at all, is never filled:
    % the strict label check below still guards everything else.
    isLab = @(lab, nm) cellfun(@(x) strcmp(char(string(x)), nm), lab);   % labels mix char and string
    hasBI = arrayfun(@(sg) any(isLab(sg.od.labels, 'blinkIndicator')), segs);
    hasBI = hasBI(:);
    blinkFilled = false(nSeg, 1);
    blinkSkipped = false(nSeg, 1);
    if isfield(segs, 'blinkSkipped'), blinkSkipped = logical([segs.blinkSkipped]'); end
    blinkWhy = strings(nSeg, 1);
    for c = 1:nSeg
        blinkWhy(c) = blinkSkipReason(segs(c), P);
        if ~hasBI(c) && blinkWhy(c) ~= ""
            lb = segs(c).od.labels;
            iB = find(isLab(lb, 'badTS'), 1);
            assert(~isempty(iB), '%s section %d: no badTS row to place blinkIndicator before', S.id, c);
            segs(c).od.data = [segs(c).od.data(1:iB-1, :); ...
                zeros(1, size(segs(c).od.data, 2)); segs(c).od.data(iB:end, :)];
            lbNew = [reshape(lb(1:iB-1), 1, []), {"blinkIndicator"}, reshape(lb(iB:end), 1, [])];
            segs(c).od.labels = reshape(lbNew, [], 1);
            if isrow(lb), segs(c).od.labels = lbNew; end
            blinkFilled(c) = true;
            fprintf('   section %d: blink removal not run (%s) - all-zero blinkIndicator row inserted\n', ...
                c, blinkWhy(c));
        end
    end
    for c = 2:nSeg
        % assert() evaluates message args eagerly - keep the strjoins inside
        % the failure branch
        if ~isequal(segs(c).od.labels(:), segs(1).od.labels(:))
            % (labels mix char and string: char() them for strjoin)
            labTxt = @(lab) strjoin(cellfun(@(x) char(string(x)), lab, 'UniformOutput', false), ',');
            error('%s: processed-segment labels differ (%s vs %s) - strict failure', ...
                S.id, labTxt(segs(1).od.labels), labTxt(segs(c).od.labels));
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
    bmInfo = cell(nSeg, 1);               % per-section breath-merge records (applyBreathMerge)
    for c = 1:nSeg
        od = segs(c).od;
        n  = size(od.data, 2);
        offSec = sampOffset / od.fs;

        if isfield(od, 'breathMerge'), bmInfo{c} = od.breathMerge; end
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
        for fq = {'badChans', 'EEGInterpolation', 'EEGCleaning', 'blinkRemoval', 'dataLapFromInterp', 'blinkICA', 'EEGCleaningInfo', 'spikeCleanInfo'}
            if isfield(od, fq{1}), q.(fq{1}) = od.(fq{1}); end
        end
        eegQC{c} = q;
        data = [data, od.data]; %#ok<AGROW>
        sampOffset = sampOffset + n;
    end

    bmObj(:, 14) = 1:size(bmObj, 1);
    % ---- breath merge (applyBreathMerge, run per section): the per-breath arrays concatenated in
    % bmObj order, the counts summed, every section's full record in perSection (empty = section
    % not segmented). outDat started as section 1's, whose record describes that section only.
    if isfield(outDat, 'breathMerge'), outDat = rmfield(outDat, 'breathMerge'); end
    hasBM = ~cellfun(@isempty, bmInfo);
    if any(hasBM)
        Bm = bmInfo(hasBM);
        M = struct('rule', Bm{1}.rule, 'exFrac', Bm{1}.exFrac);
        for fc = {'nBefore', 'nAfter', 'nMinor', 'nLeadBumps', 'nMerged'}
            M.(fc{1}) = sum(cellfun(@(q) q.(fc{1}), Bm));
        end
        for fc = {'nPulses', 'nRows', 'inhaleArea', 'exhaleArea', 'exInRatio'}
            M.(fc{1}) = cell2mat(cellfun(@(q) q.(fc{1})(:), Bm(:), 'UniformOutput', false));
        end
        M.perSection = bmInfo;
        assert(numel(M.nPulses) == size(bmObj, 1), 'concatSections: %d merged breaths but %d bmObj rows', ...
            numel(M.nPulses), size(bmObj, 1));
        outDat.breathMerge = M;
    end
    % engine metadata from the first section that was segmented (= section 1
    % unless respiration was skipped there, P.condRespSkip)
    respSk = zeros(nSeg, 1);
    if isfield(segs, 'respSkipped'), respSk = [segs.respSkipped]'; end
    c1 = find(respSk == 0, 1); if isempty(c1), c1 = 1; end
    F.engine = segs(c1).od.bmFeatures.engine;
    F.version = segs(c1).od.bmFeatures.version;
    F.dataType = segs(c1).od.bmFeatures.dataType;
    F.srate = segs(c1).od.bmFeatures.srate;
    F.nBreathsSegmented = size(bmObj, 1);

    outDat.data = data;
    outDat.bmObj = bmObj;
    outDat.bmFeatures = F;
    if ~isempty(hb), outDat.heartBeats = hb; end
    if lapOK, outDat.dataLap = dataLap; else, outDat.dataLap = []; end
    outDat.sections = secTab;
    outDat.eegQCPerSection = eegQC;   % top-level fields still describe section 1
    % ... except EEGCleaningInfo (2026-10-15): section 1's full record at top
    % level would read as the session's; keep a session summary there instead
    % (mode / version as in the per-section records, which hold the details)
    hasCI = cellfun(@(q) isfield(q, 'EEGCleaningInfo'), eegQC);
    if any(hasCI)
        ci = cellfun(@(q) q.EEGCleaningInfo, eegQC(hasCI), 'UniformOutput', false);
        md = unique(cellfun(@(r) char(string(r.mode)), ci, 'UniformOutput', false));
        vr = unique(cellfun(@(r) char(string(r.version)), ci, 'UniformOutput', false));
        sumCI = struct();
        sumCI.mode       = strjoin(md, '/');
        sumCI.version    = strjoin(vr, '/');
        sumCI.perSection = true;
        sumCI.unjudgeable = any(cellfun(@(r) isfield(r, 'unjudgeable') && r.unjudgeable, ci));
        sumCI.nBadPerSection      = NaN(nSeg, 1);
        sumCI.fracBadTSPerSection = NaN(nSeg, 1);
        sumCI.nBadPerSection(hasCI)      = cellfun(@(r) r.nBad, ci);
        sumCI.fracBadTSPerSection(hasCI) = cellfun(@(r) r.fracBadTS, ci);
        sumCI.note = ['breathingTasks_separate: the EEG stage runs per section - section b''s full record is ' ...
            'outDat.eegQCPerSection{b}.EEGCleaningInfo (top-level badChans / blinkRemoval describe section 1)'];
        outDat.EEGCleaningInfo = sumCI;
    end
    outDat.TTL = reshape([secTab.startSample'; secTab.endSample'], 1, []);

    % ---- per-condition respiration channels (only when they differ) ----
    % Analysts select the respiration trace with the canonical idiom
    %   rsp = data(isRsp,:); rsp = rsp(outDat.rspIDX,:) .* outDat.rspFlip.
    % When the sections use different channels/polarities, append ONE row
    % 'rspSelected' (label contains 'rsp'; after the raw rsp rows, so their
    % indices do not shift) = each section's chosen channel x its flip, point
    % rspIDX at it with rspFlip = 1, and record each section's choice in
    % outDat.sections.rspIDX / rspFlip. Sessions with one channel are untouched.
    [~, ~, mixed] = sepSectionRsp(P);
    if mixed
        lab = outDat.labels;
        isRsp = cellfun(@(x) contains(x, 'rsp'), lab);
        rspRows = outDat.data(isRsp, :);
        sel = zeros(1, size(outDat.data, 2));
        sIdx = zeros(nSeg, 1); sFlip = zeros(nSeg, 1);
        for c = 1:nSeg
            [sIdx(c), sFlip(c)] = sepSectionRsp(P, segs(c).condition);
            r = secTab.startSample(c):secTab.endSample(c);
            sel(r) = rspRows(sIdx(c), r) .* sFlip(c);
        end
        outDat.data(end+1, :) = sel;
        outDat.labels{end+1} = 'rspSelected';
        outDat.rspIDX  = sum(isRsp) + 1;     % index among the rsp rows (new row is last)
        outDat.rspFlip = 1;
        secTab.rspIDX = sIdx; secTab.rspFlip = sFlip;
        outDat.sections = secTab;
        outDat.rspSelectedNote = ['row rspSelected = per-section chosen rsp channel x its flip (outDat.sections.rspIDX/rspFlip); ' ...
            'raw rsp rows are unchanged; rspIDX points at rspSelected, rspFlip = 1'];
    end

    % ---- per-condition settings (tasks_261014), each only when configured ----
    if isfield(P, 'condTrimSec') && isfield(segs, 'raw')
        rw = [segs.raw];
        secTab.trimStartSec   = arrayfun(@(x) x.trimSec(1), rw)';
        secTab.trimEndSec     = arrayfun(@(x) x.trimSec(2), rw)';
        secTab.rawFirstSample = [rw.rawFirstSample]';
        secTab.rawLastSample  = [rw.rawLastSample]';
        secTab.rawSamples     = [rw.rawSamples]';
        outDat.trimNote = ['per-condition trim (applyParams P.condTrimSec): section b keeps raw samples ' ...
            'rawFirstSample(b)..rawLastSample(b) of its raw file (rawSamples(b) long; trimStartSec/trimEndSec ' ...
            '= the setting, NaN = untrimmed end); final sample s <-> raw sample ' ...
            '(s - startSample(b)) * origFS/fs + rawFirstSample(b)'];
    end
    if isfield(P, 'condBeatSpec') && numel(unique(P.condBeatSpec)) > 1
        secTab.beatSpec = strings(nSeg, 1);
        for c = 1:nSeg
            Pc = sepSectionP(P, segs(c).condition);
            secTab.beatSpec(c) = string(Pc.beatSpec);
        end
    end
    % blink-removal record: only when a section was switched off by a
    % setting, a zero row was inserted, or the session sets P.condBlinkRemoval
    % (sessions with none of these get exactly the previous outDat)
    if isfield(P, 'condBlinkRemoval') || any(blinkSkipped) || any(blinkFilled)
        secTab.blinkRemoval    = cellfun(@(q) getOr(q, 'blinkRemoval', NaN), eegQC);
        secTab.blinkSkipped    = blinkSkipped;
        secTab.blinkSkipReason = blinkWhy;
        secTab.blinkFilled     = blinkFilled;
        outDat.blinkNote = ['blink removal per section: sections.blinkRemoval 1 = the blink ICA ran, 0 = the section ' ...
            'was not blink-cleaned, for the reason in sections.blinkSkipReason; sections.blinkSkipped = switched off ' ...
            'by a setting (the condition default of config/sepConditionInfo - no blink removal in sleep / ' ...
            'sleepWithOdor recordings, reviewer 2026-10-20 - or a per-session applyParams P.condBlinkRemoval); ' ...
            'sections.blinkFilled = that section''s blinkIndicator row is all zero (no blink stage there: no blink ' ...
            'marks, nothing removed), inserted ' ...
            'so the section labels match'];
        if ~any(blinkFilled)
            outDat.blinkNote = [outDat.blinkNote ' - none was needed here'];
        end
    end
    if isfield(P, 'condRespSkip')
        secTab.respSkipped = 2 * double(respSk > 0);
        if all(respSk > 0), outDat.respSkipped = 2;
        elseif any(respSk > 0), outDat.respSkipped = 1;
        else, outDat.respSkipped = 0;
        end
        outDat.respNote = ['respiration not recoverable per condition (applyParams P.condRespSkip): ' ...
            'sections.respSkipped == 2 were not segmented and contribute no breaths (no finalOnsets); ' ...
            'outDat.respSkipped 0 none / 1 some / 2 all sections'];
    end
    if isfield(P, 'condMinIBI')
        secTab.minIBI = NaN(nSeg, 1);
        for c = 1:nSeg
            Pc = sepSectionP(P, segs(c).condition);
            if isfield(Pc, 'minIBI') && ~isempty(Pc.minIBI), secTab.minIBI(c) = Pc.minIBI; end
        end
    end
    outDat.sections = secTab;
end

function v = getOr(s, f, d)
    if isstruct(s) && isfield(s, f), v = double(s.(f)); else, v = d; end
end

function r = blinkSkipReason(seg, P)
% Why a section's EEG stage removed no blinks, from what preprocess_eeg
% records ("" = blink removal ran, or the section had no EEG stage). Order:
% the setting (sepSectionP), then preprocess_eeg's own skip paths - <= 10 good
% channels after the detector, the blink-stage gate (fixed / band), and the
% one remaining path, both blink channels bad.
    r = "";
    od = seg.od;
    if ~isfield(od, 'blinkRemoval') || od.blinkRemoval ~= 0, return; end
    if isfield(seg, 'blinkSkipped') && seg.blinkSkipped
        [~, si] = sepSectionP(P, seg.condition);
        if strcmp(si.blinkReason, 'session')
            r = "switched off for this recording (applyParams P.condBlinkRemoval)";
        else
            r = "condition default: no blink removal in " + string(seg.label) + ...
                " recordings (config/sepConditionInfo)";
        end
        return;
    end
    ci = struct();
    if isfield(od, 'EEGCleaningInfo') && isstruct(od.EEGCleaningInfo), ci = od.EEGCleaningInfo; end
    if isfield(ci, 'nGoodForBlink') && ci.nGoodForBlink <= 10
        r = sprintf("%d good channels after the detector (blink removal needs > 10)", ci.nGoodForBlink);
    elseif isfield(ci, 'blinkGate') && ci.blinkGate
        nG = NaN;
        if isfield(ci, 'nGoodAfterBlinkStage'), nG = ci.nGoodAfterBlinkStage; end
        r = sprintf("blink-stage gate: %d good channels after the blink stage's channel tests (needs > 10)", nG);
    elseif isfield(ci, 'nGoodForBlink')
        r = "both blink channels (Fp1, Fp2) bad for the blink stage";
    else
        r = "blink removal not run (blinkRemoval 0; no EEGCleaningInfo)";
    end
end

function F = appendFeat(F, name, v)
    v = v(:)';
    if ~isfield(F, name), F.(name) = v; else, F.(name) = [F.(name), v]; end
end

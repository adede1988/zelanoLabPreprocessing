function outDat = carryFinishFromFinal(outDat, CS, secRecords)
%CARRYFINISHFROMFINAL  Close the respiration carry: verify, keep the previous final's post-hoc fields, record.
%
%   outDat = carryFinishFromFinal(outDat, CS)
%   outDat = carryFinishFromFinal(outDat, CS, secRecords)    % breathingTasks_separate
%
%   Call it just before the main saves, after every stage has run. CS = [] (no
%   carry requested) returns outDat untouched. Otherwise, strictly:
%     - every carried row (rsp*, targTrace) must still equal the previous
%       final's, sample for sample, in the finished outDat: a later stage that
%       altered a respiration row is a bug (carryFinishFromFinal:rowChanged).
%       For a breathingTasks_separate final built from carried sections the
%       whole-session rows are compared, and the rebuilt 'rspSelected' row (a
%       per-section choice, concatSections) must equal the previous final's
%       when it had one;
%     - fields the previous final carries that the new outDat lacks are sorted
%       in two by shared/carryPipelineFields (the list of every top-level field
%       the pipeline can produce, in any task or configuration):
%         * a field the pipeline CAN produce but did not in this run (blinkICA /
%           EEGCleaningInfo / blinkRemoval when blink removal or the EEG stage is
%           off, heartBeats when ECG was skipped, ...) is a stage output of the
%           previous run, not a post-hoc addition: it is NOT carried (carrying
%           it would present the previous run's results as this run's); only its
%           name goes to outDat.carry.stageFieldsNotCarried;
%         * every other field (post-hoc analysis fields such as bestMac,
%           ridgeInfo, powerPhaseContinuity; anything added by a tool run on the
%           final afterwards) is moved to outDat.carriedFromPrevFinal (a struct,
%           field name -> the previous final's value), never dropped and never
%           presented as current: it describes the PREVIOUS data and is not
%           recomputed.
%       A carriedFromPrevFinal / carry the previous final itself held (a
%       second rerun) is kept inside (carry -> outDat.carry.previous).
%   and completes outDat.carry (written by carryRespFromFinal): rowsVerified,
%   postHocFields (names) + postHocNote, stageFieldsNotCarried (names) +
%   stageFieldsNote, previous (an earlier carry record).
%
%   secRecords (breathingTasks_separate): cell array, the outDat.carry record
%   of each section in order. outDat.carry then becomes the session record -
%   the source / hash / made / note of section 1 plus perSection = the
%   records of all sections (their per-row checks and spans).

    if isempty(CS), return; end
    id = outDat.sessID;
    if nargin < 3, secRecords = []; end
    if ~isfield(outDat, 'carry') && isempty(secRecords)
        error('carryFinishFromFinal:noCarry', '%s: carry requested (%s) but carryRespFromFinal was never applied', id, CS.path);
    end
    if ~isempty(secRecords)
        rec = secRecords{1};
        rec.perSection = secRecords;
        if isfield(rec, 'section'), rec = rmfield(rec, 'section'); end
        rec.checks = struct('perSection', true, 'note', 'see perSection{b}.checks');
        rec.targTraceCarried = any(cellfun(@(r) r.targTraceCarried, secRecords));
        rec.reconstructedCarried = false;
        rec.rspIDX = cellfun(@(r) r.rspIDX, secRecords);
        rec.rspFlip = cellfun(@(r) r.rspFlip, secRecords);
    else
        rec = outDat.carry;
    end

    % ---- the carried rows survived the whole pipeline ----
    lab = cellfun(@(x) char(string(x)), outDat.labels(:)', 'UniformOutput', false);
    newRsp = find(cellfun(@(x) contains(x, 'rsp'), lab) & ~ismember(lab, [CS.ignore, {'rspSelected'}]));
    if ~isequal(lab(newRsp), CS.rspLabels)
        error('carryFinishFromFinal:labels', '%s: rsp rows %s at the end, %s carried', id, strjoin(lab(newRsp), ','), strjoin(CS.rspLabels, ','));
    end
    for j = 1:numel(newRsp)
        if size(outDat.data, 2) ~= size(CS.rspRows, 2) || ~isequaln(double(outDat.data(newRsp(j), :)), CS.rspRows(j, :))
            error('carryFinishFromFinal:rowChanged', '%s: %s differs from the previous final''s row at the end of the pipeline', id, CS.rspLabels{j});
        end
    end
    if ~isempty(CS.targRow)
        iT = find(strcmp(lab, 'targTrace'));
        if numel(iT) ~= 1 || ~isequaln(double(outDat.data(iT, :)), CS.targRow)
            error('carryFinishFromFinal:rowChanged', '%s: targTrace differs from the previous final''s row at the end of the pipeline', id);
        end
    end
    rec.rowsVerified = true;
    if ~isempty(CS.rspSelectedRow)
        iS = find(strcmp(lab, 'rspSelected'));
        if numel(iS) ~= 1 || ~isequaln(double(outDat.data(iS, :)), CS.rspSelectedRow)
            error('carryFinishFromFinal:rspSelected', ['%s: the rebuilt rspSelected row differs from the previous final''s - ' ...
                'the per-section respiration choice changed'], id);
        end
        rec.rspSelectedVerified = true;
    end

    % ---- fields of the previous final that the new outDat lacks: stage outputs (not carried) vs post-hoc fields (carried) ----
    mine = fieldnames(outDat);
    missing = setdiff(CS.prevFields(:), [mine(:); {'carry'; 'carriedFromPrevFinal'}], 'stable');
    isStage = ismember(missing, carryPipelineFields());      % the pipeline can produce it (any task / configuration)
    extra = missing(~isStage);                               % genuine post-hoc fields
    rec.stageFieldsNotCarried = missing(isStage)';
    if any(isStage)
        rec.stageFieldsNote = ['fields of the previous final that this pipeline can produce but did not produce in this run ' ...
            '(e.g. blinkICA when blink removal is off): stage outputs of the previous run, not carried; the previous final is ' ...
            'kept at outDat.carry.source'];
        fprintf('%s: %d stage field(s) of the previous final not produced by this run and NOT carried: %s\n', id, nnz(isStage), strjoin(missing(isStage)', ', '));
    end
    wantOld = ~isempty(extra) || ismember('carry', CS.prevFields) || ismember('carriedFromPrevFinal', CS.prevFields);
    carried = struct();
    if wantOld
        s = load(CS.path, CS.varName);
        old = s.(CS.varName);
        clear s
        if isfield(old, 'carriedFromPrevFinal') && isstruct(old.carriedFromPrevFinal)
            carried = old.carriedFromPrevFinal;
        end
        for k = 1:numel(extra)
            carried.(extra{k}) = old.(extra{k});
        end
        if isfield(old, 'carry'), rec.previous = old.carry; end
        clear old
    end
    rec.postHocFields = extra(:)';
    if ~isempty(fieldnames(carried))
        outDat.carriedFromPrevFinal = carried;
        rec.postHocNote = ['outDat.carriedFromPrevFinal holds fields of the previous final that this pipeline does not produce ' ...
            '(analyses or edits made on that final afterwards). They describe the PREVIOUS data and were not recomputed on this ' ...
            'rerun''s EEG / breaths; check them against the new final before use.'];
        if ~isempty(extra)
            fprintf('%s: kept %d post-hoc field(s) of the previous final in outDat.carriedFromPrevFinal: %s\n', id, numel(extra), strjoin(extra(:)', ', '));
        end
    end
    outDat.carry = rec;
end

function outDat = build_behavior_table_breathingTask(outDat, bmObj)
% constructBehDat
%   Rebuilds outDat.behDat from breath-mark matrix bmObj and the
%   original behavioral table in outDat.behDat, and also constructs
%   outDat.baseEmotion.
%
% Inputs
%   outDat : struct with fields
%              .fs      : sampling rate
%              .data    : [channels x time]
%              .behDat  : original behavior table (tmpBehDat)
%   bmObj  : [nBreaths x 14+] matrix of breath markers:
%            col  1: onset Y value
%            col  2: onset time (s)
%            col  3: peak Y value
%            col  4: peak time (s)
%            col  5: end Y value
%            col  6: end time (s)
%            col  7: length (end - onset)
%            col  8: amplitude
%            col  9: idx of peak in rspSig2
%            col 10: exhale peak Y
%            col 11: exhale peak time (s)
%            col 12: condition
%            col 14: index
%
% Output
%   outDat : same struct with updated
%              .behDat      : per-breath table
%              .baseEmotion : baseline emotion row

    % Preserve original behavior table for emotion info
    tmpBehDat = outDat.behDat;

    % New behDat table based on bmObj: the 14 shared per-breath columns
    % (sniffOnset/finalOnset/manOnset, condition, Yonset, inhaleMax, inMaxTim,
    % Yend, endTim, length, amp, exhaleMin, exMinTim, index)
    outDat.behDat = behDatFromBreaths(bmObj, size(outDat.data, 2), outDat.fs);

    % ---------------- integrate emotion data into respiration ----------------
    Qs = unique(tmpBehDat.Q_short);  % e.g., emotion questions

    for cndi = 1:max(outDat.behDat.condition)
        idx = find(outDat.behDat.condition == cndi);
        if isempty(idx)
            continue;
        end

        tmp = tmpBehDat(tmpBehDat.order == cndi, :);
        if isempty(tmp)
            continue;
        end

        outDat.behDat.task(idx)       = tmp.task(1);
        outDat.behDat.noseMouth(idx)  = tmp.noseMouth(1);
        outDat.behDat.shadowFile(idx) = tmp.shadowFile(1);
        outDat.behDat.warp(idx)       = tmp.warp(1);

        % Add one column per Q/type combination: e.g., "Happy_pre" etc.
        for q = 1:length(Qs)
            % (2026-09-01) 'SKIP' marks a rating that was never collected
            % (e.g. AD_1's audio block) - an all-SKIP set otherwise matches
            % 12 rows at once and breaks the scalar assignment below
            if strcmp(Qs{q}, 'SKIP'), continue; end
            ii = find(cellfun(@(x) strcmp(Qs{q}, x), tmp.Q_short));
            if isempty(ii)
                continue;
            end
            if numel(ii) > 1
                warning('build_behavior_table_breathingTask:dupQ', ...
                    '%s: Q_short "%s" appears %d times in condition %d - using the first', ...
                    outDat.sessID, Qs{q}, numel(ii), cndi);
                ii = ii(1);
            end
            varName = [Qs{q} '_' tmp.type{ii}];
            outDat.behDat.(varName)(idx) = tmp.rsp(ii);
        end
    end

    % ---------------- baseline emotion row (order == 0) ----------------
    cndi = 0;
    baseEmotion = table;
    tmp = tmpBehDat(tmpBehDat.order == cndi, :);

    if ~isempty(tmp)
        baseEmotion.task       = tmp.task(1);
        baseEmotion.noseMouth  = tmp.noseMouth(1);
        baseEmotion.shadowFile = tmp.shadowFile(1);
        baseEmotion.warp       = tmp.warp(1);

        for q = 1:length(Qs)
            if strcmp(Qs{q}, 'SKIP'), continue; end   % never-collected marker
            ii = find(cellfun(@(x) strcmp(Qs{q}, x), tmp.Q_short));
            if isempty(ii)
                continue;
            end
            ii = ii(1);
            varName = [Qs{q} '_' tmp.type{ii}];
            baseEmotion.(varName) = tmp.rsp(ii);
        end
    end

    outDat.baseEmotion = baseEmotion;

    % ---------------- breathMetrics per-breath features (Tasks_260824 D8e) ----------------
    % Every existing column above is kept; the breathMetrics feature set is
    % appended as bm_* columns, aligned to bmObj rows via bmObjBreathIdx.
    outDat = appendBmFeatureCols(outDat, 'build_behavior_table_breathingTask');

end

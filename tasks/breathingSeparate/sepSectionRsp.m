function [idx, flip, mixed] = sepSectionRsp(P, condition)
%SEPSECTIONRSP  Respiration channel (index among the rsp rows) and polarity of one
%   breathingTasks_separate condition recording.
%
%   [idx, flip, mixed] = sepSectionRsp(P, condition)
%
%   Each condition row of the sheet may carry its own rspIDX / rspFlip
%   (applyParams -> P.condRspIDX / P.condRspFlip, aligned with P.conditions;
%   e.g. 260921_OBE_NWU_BW_2: binaps in three recordings, the spirometer in the
%   mouth-breathing recording). Without those fields, or when condition is
%   not listed, the session-level P.rspIDX / P.rspFlip apply. mixed = true
%   only when the conditions differ in channel or polarity; the main then
%   builds the 'rspSelected' row (concatSections). With condition omitted only
%   the mixed flag is of interest.
    idx = P.rspIDX; flip = P.rspFlip; mixed = false;
    if ~isfield(P, 'condRspIDX') || ~isfield(P, 'condRspFlip') || ~isfield(P, 'conditions')
        return;
    end
    mixed = numel(unique(P.condRspIDX)) > 1 || numel(unique(P.condRspFlip)) > 1;
    if nargin < 2 || isempty(condition), return; end
    k = find(strcmpi(strtrim(P.conditions), strtrim(condition)), 1);
    if ~isempty(k)
        idx = P.condRspIDX(k); flip = P.condRspFlip(k);
    end
end

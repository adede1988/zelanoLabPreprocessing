function type = cueTrialType(beh)
%CUETRIALTYPE  Outcome of each odor-cue trial: hit / miss / cr / fa / skip / noCue.
%
%   type = cueTrialType(beh)
%
%   beh   per-trial behaviour table with cue, odor (after the odor-line
%         recode, so a match is cue == odor) and response_str ('Yes' / 'No',
%         empty = no answer)
%   type  string column: hit (match, Yes), miss (match, No), cr (non-match,
%         No), fa (non-match, Yes), skip (no answer), noCue (cue == 0)
%
%   The rule of cueTask_makeOutDat, moved here unchanged (2026-10-16) so the
%   cue task and cueTask3 (cueTask3_makeOutDat) share it.

    type = repmat("hit", size(beh,1),1);
    idx = find(beh.cue==beh.odor & ...
                       strcmp(beh.response_str,'No'));
    type(idx) = repmat("miss", length(idx),1);
    idx = find(beh.cue~=beh.odor & ...
                       strcmp(beh.response_str,'No'));
    type(idx) = repmat("cr", length(idx),1);
    idx = find(beh.cue~=beh.odor & ...
                       strcmp(beh.response_str,'Yes'));
    type(idx) = repmat("fa", length(idx),1);
    idx = find(cellfun(@(x) isempty(x), beh.response_str));
    type(idx) = repmat("skip", length(idx),1);
    % No-cue condition (Tasks_260824.md D9): the raw file codes cue==0 for
    % no-cue trials; hit/miss/cr/fa are undefined there, so they get their own
    % outcome value. The cue column keeps the 0. The photodiode structure is
    % unchanged on no-cue trials (trial-start/sniff/response pulses all
    % present - verified on SP_2/RC_1/KA_2, batch/task6_probeNoCueTTL.m
    % (script removed in cleanup; see git history)).
    idx = find(beh.cue == 0);
    type(idx) = repmat("noCue", length(idx),1);
end

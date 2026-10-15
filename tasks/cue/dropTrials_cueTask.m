function [behDat, droppedTrials] = dropTrials_cueTask(behDat, dropTrials, reason)
% Remove whole trials from the cueTask behavior table (P.dropTrials, set per
% session in config/applyParams.m).
%
%   [behDat, droppedTrials] = dropTrials_cueTask(behDat, dropTrials, reason)
%
% Every sniff row whose trial number (behDat.n) is in dropTrials is removed, so
% the trial is simply absent from behDat - the same state as a trial whose
% sniff was never detected. outDat.TTL is NOT touched: behDat.n still indexes
% its rows. droppedTrials is the audit record the main stores in
% outDat.droppedTrials: table(trial, reason), one row per dropped trial.
%
% Strict: a trial that is not in behDat (nonexistent, or no sniff detected)
% means the configured drop is stale, so it errors instead of passing quietly.
    dropTrials = dropTrials(:);
    if isempty(dropTrials), error('dropTrials_cueTask:empty', 'dropTrials is empty; call only when there is something to drop'); end
    if ~isnumeric(dropTrials) || any(dropTrials < 1) || any(dropTrials ~= round(dropTrials)) || numel(unique(dropTrials)) ~= numel(dropTrials)
        error('dropTrials_cueTask:badTrials', 'dropTrials must be unique positive integer trial numbers');
    end
    missing = setdiff(dropTrials, behDat.n);
    if ~isempty(missing)
        error('dropTrials_cueTask:notPresent', ...
            'trial(s) %s are not in behDat (no detected sniff?) - the configured drop is stale', mat2str(missing(:)'));
    end
    behDat(ismember(behDat.n, dropTrials), :) = [];
    droppedTrials = table(dropTrials, repmat(string(reason), numel(dropTrials), 1), ...
        'VariableNames', {'trial', 'reason'});
end

% task3_writeGuesses — create guess parameters for breathing rows that have
% none (Tasks_260824.md Task 3 Part B step 6 / D3).
%
% Rows with blank paramSource in the current sheet:
%   260227_EEG_NWU_HW  (waveBreathing, extracted in Task 2) -> EEG standard set
%       with rspFlip = the modal rspFlip of curated EEG-type breathing rows
%   260608_OBE_NWU_RX_1 (breathing raw missing on disk)     -> OBEControl
%       modal values (documented guess; the session cannot run until its raw
%       appears)
% All written with paramSource='guess' (inheritance never produces curated).
% Existing guess rows (KS_3, DB_3, PD_2, ...) already carry parameters and are
% left untouched.

L = labPaths();
C = readcell(L.adminXlsx, 'Sheet', 'Sheet1');
hdr = C(2, :);
col = @(nm) find(cellfun(@(v) (ischar(v) || isstring(v)) && strcmpi(strtrim(char(string(v))), nm), hdr), 1);
cSub = col('Subject ID'); cType = col('Type'); cTask = col('Task');
cPS = col('paramSource'); cFlip = col('rspFlip'); cIdx = col('rspIDX'); cBeat = col('beatSpec');

% ---- modal values among curated breathing rows, per Type bucket ----
normT = @(v) lower(strrep(char(string(v)), ' ', ''));
isBreathingTask = @(v) any(strcmp(normT(v), {'breathingtasks', 'breathingtask', 'wavebreathing'}));
flipEEG = []; flipOBE = []; beatOBE = {}; idxOBE = [];
for r = 3:size(C, 1)
    v = C{r, cSub};
    if ~(ischar(v) || isstring(v)) || isempty(strtrim(char(string(v)))), continue; end
    if ~isBreathingTask(C{r, cTask}), continue; end
    ps = C{r, cPS};
    if ~(ischar(ps) || isstring(ps)) || ~strcmpi(strtrim(char(string(ps))), 'curated'), continue; end
    ty = lower(char(string(C{r, cType})));
    fv = C{r, cFlip}; iv = C{r, cIdx}; bv = C{r, cBeat};
    if contains(ty, 'eeg')
        if isnumeric(fv) && isscalar(fv) && ~isnan(fv), flipEEG(end+1) = fv; end %#ok<SAGROW>
    elseif ~contains(ty, 'dupi')
        if isnumeric(fv) && isscalar(fv) && ~isnan(fv), flipOBE(end+1) = fv; end %#ok<SAGROW>
        if isnumeric(iv) && isscalar(iv) && ~isnan(iv), idxOBE(end+1) = iv; end %#ok<SAGROW>
        if (ischar(bv) || isstring(bv)) && strlength(strtrim(string(bv))) > 0
            beatOBE{end+1} = strtrim(char(string(bv))); %#ok<SAGROW>
        end
    end
end
fprintf('curated EEG rspFlip values: %s -> mode %d\n', mat2str(flipEEG), mode(flipEEG));
fprintf('curated OBE rspFlip values: n=%d mode %d | rspIDX mode %d\n', ...
    numel(flipOBE), mode(flipOBE), mode(idxOBE));
[ub, ~, ib] = unique(beatOBE);
bCounts = accumarray(ib(:), 1);
[~, bi] = max(bCounts);
fprintf('modal OBE beatSpec: "%s" (%d/%d)\n', ub{bi}, bCounts(bi), numel(beatOBE));

% ---- HW: EEG standard set (work order section 0, D3.3) ----
P = struct('task', 'breathingTask', 'rspIDX', 1, 'rspFlip', mode(flipEEG), ...
    'hasEEG', true, 'hasMacros', false, 'spikeClean', false, ...
    'spikeThresh', 20, 'spikeWin', 11, 'macroRemove', [], ...
    'beatSpec', '1,0,gt,3.5', 'isNewStd', true, 'paramSource', 'guess');
writeParams(P, '260227_EEG_NWU_HW');

% ---- RX_1: OBEControl modal values (raw missing; guess recorded anyway) ----
P = struct('task', 'breathingTask', 'rspIDX', mode(idxOBE), 'rspFlip', mode(flipOBE), ...
    'hasEEG', true, 'hasMacros', true, 'spikeClean', true, ...
    'spikeThresh', 20, 'spikeWin', 11, 'macroRemove', [], ...
    'beatSpec', ub{bi}, 'isNewStd', true, 'paramSource', 'guess');
writeParams(P, '260608_OBE_NWU_RX_1');

fprintf('task3_writeGuesses: DONE\n');

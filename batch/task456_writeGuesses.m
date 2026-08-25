% task456_writeGuesses — create guess parameters for the blank-paramSource
% O15 / threshold / odor-cue rows (Tasks_260824.md Tasks 4-6, D3).
%
% D3 priority: (1) inherit rspIDX/rspFlip/spike settings from a curated row of
% the SAME session (any task); (2) otherwise the modal values among curated
% rows of the same task+Type. Task-specific sniff windows take the modal
% curated values of that task. Everything is written with paramSource='guess'
% and the row is NOT run (D4: none of these are EEG_breathing).
%
% Existing guess rows (PD_2, JA_2) already carry parameters - untouched.

% id, caller task key
TARGETS = { ...
 '260608_OBE_NWU_RX_1', 'O15'; ...
 '260702_OBE_NWU_SP_2', 'O15'; ...
 '260608_OBE_NWU_RX_1', 'threshTask'; ...
 '260625_OBE_NWU_HM_2', 'threshTask'; ...
 '260702_OBE_NWU_SP_2', 'threshTask'; ...
 '260720_OBE_NWU_KA_2', 'threshTask'; ...
 '260702_OBE_NWU_SP_2', 'cueTask'; ...
 '260622_OBE_NWU_RC_1', 'cueTask'; ...
 '260720_OBE_NWU_KA_2', 'cueTask'};

L = labPaths();
C = readcell(L.adminXlsx, 'Sheet', 'Sheet1');
hdr = C(2, :);
col = @(nm) find(cellfun(@(v) (ischar(v) || isstring(v)) && strcmpi(strtrim(char(string(v))), nm), hdr), 1);
cSub = col('Subject ID'); cType = col('Type'); cTask = col('Task'); cPS = col('paramSource');
cIdx = col('rspIDX'); cFlip = col('rspFlip'); cSpkC = col('spikeClean');
cSpkT = col('spikeThresh'); cSpkW = col('spikeWin'); cMacR = col('macroRemove');
cRespT = col('respThresh'); cBack = col('cuedBackBuff'); cAdj = col('adjWin'); cNew = col('isNewStd');

normT = @(v) lower(strrep(char(string(v)), ' ', ''));
numOr = @(v, d) firstFinite(v, d);

for k = 1:size(TARGETS, 1)
    [id, caller] = TARGETS{k, :};
    switch caller
        case 'O15',        wantTask = 'o15';
        case 'threshTask', wantTask = 'threshold';
        case 'cueTask',    wantTask = 'odorcuetask';
    end
    fprintf('\n--- %s / %s ---\n', id, caller);

    % (1) donor: a curated row of the same session, any task
    donor = 0;
    for r = 3:size(C, 1)
        v = C{r, cSub};
        if ~(ischar(v) || isstring(v)) || ~strcmpi(strtrim(char(string(v))), id), continue; end
        ps = C{r, cPS};
        if (ischar(ps) || isstring(ps)) && strcmpi(strtrim(char(string(ps))), 'curated')
            donor = r; break;
        end
    end

    % (2) modal values among curated rows of this task (same Type bucket = OBE here)
    idxV = []; flipV = []; spkCV = []; respTV = []; backV = []; adjV = []; newV = [];
    for r = 3:size(C, 1)
        v = C{r, cSub};
        if ~(ischar(v) || isstring(v)), continue; end
        if ~strcmp(normT(C{r, cTask}), wantTask), continue; end
        ps = C{r, cPS};
        if ~((ischar(ps) || isstring(ps)) && strcmpi(strtrim(char(string(ps))), 'curated')), continue; end
        ty = lower(char(string(C{r, cType})));
        if contains(ty, 'dupi') || contains(ty, 'eeg'), continue; end   % OBE bucket
        idxV(end+1)  = numOr(C{r, cIdx}, 1); %#ok<SAGROW>
        flipV(end+1) = numOr(C{r, cFlip}, 1); %#ok<SAGROW>
        spkCV(end+1) = boolOr(C{r, cSpkC}, ~strcmp(caller, 'O15')); %#ok<SAGROW>
        respTV(end+1) = numOr(C{r, cRespT}, 500); %#ok<SAGROW>
        backV(end+1) = numOr(C{r, cBack}, 150); %#ok<SAGROW>
        adjV(end+1)  = numOr(C{r, cAdj}, 500); %#ok<SAGROW>
        newV(end+1)  = boolOr(C{r, cNew}, false); %#ok<SAGROW>
    end
    fprintf('  modal pool: %d curated OBE %s rows\n', numel(idxV), wantTask);

    P = struct('task', caller, 'paramSource', 'guess');
    if donor > 0
        P.rspIDX  = numOr(C{donor, cIdx}, 1);
        P.rspFlip = numOr(C{donor, cFlip}, 1);
        P.spikeClean = boolOr(C{donor, cSpkC}, ~strcmp(caller, 'O15'));
        P.spikeThresh = numOr(C{donor, cSpkT}, 20);
        P.spikeWin = numOr(C{donor, cSpkW}, 11);
        basis = sprintf('inherited from same-session curated row %d (%s)', donor, char(string(C{donor, cTask})));
    else
        P.rspIDX  = modeOr(idxV, 1);
        P.rspFlip = modeOr(flipV, 1);
        P.spikeClean = logical(modeOr(spkCV, ~strcmp(caller, 'O15')));
        P.spikeThresh = 20;
        P.spikeWin = 11;
        basis = 'Type default (modal curated OBEControl values)';
    end
    P.hasEEG = ~strcmp(caller, 'O15');
    P.macroRemove = [];
    P.respThresh   = modeOr(respTV, 500);
    P.cuedBackBuff = modeOr(backV, 150);
    P.adjWin       = modeOr(adjV, 500);
    P.isNewStd     = true;   % all 2606xx+ recordings use the new-standard ingestion
    fprintf('  basis: %s\n  rspIDX=%d rspFlip=%d spikeClean=%d respThresh=%d cuedBackBuff=%d adjWin=%d\n', ...
        basis, P.rspIDX, P.rspFlip, P.spikeClean, P.respThresh, P.cuedBackBuff, P.adjWin);

    writeParams(P, id, [], 'AllowUnextracted', true);
end
fprintf('\ntask456_writeGuesses: DONE\n');

% ============================ helpers ============================

function x = firstFinite(v, d)
    if isnumeric(v) && isscalar(v) && isfinite(v), x = double(v); return; end
    if ischar(v) || isstring(v)
        t = str2double(char(string(v)));
        if isfinite(t), x = t; return; end
    end
    x = d;
end

function tf = boolOr(v, d)
    if isa(v, 'missing'), tf = d; return; end
    if islogical(v), tf = v; return; end
    if isnumeric(v) && isscalar(v) && isfinite(v), tf = v ~= 0; return; end
    if ischar(v) || isstring(v)
        tf = ismember(lower(strtrim(char(string(v)))), {'true', '1', 'yes'});
        return;
    end
    tf = d;
end

function m = modeOr(v, d)
    if isempty(v), m = d; else, m = mode(v); end
end

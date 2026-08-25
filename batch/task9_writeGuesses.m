% task9_writeGuesses — guess parameters for the breathingTasks_separate
% sessions (Tasks_260824.md Task 9 step 5 / D12d), written identically onto
% every in-scope condition row via writeSheetSep.
%
% Inheritance (D3): sessions with curated rows (GH_1, DL_1 breathing; RY_1,
% ZF_1 O15) copy rsp/spike settings (and breathing beatSpec where the donor is
% a breathing row); the four OBEControl-only sessions (HM_2, SP_2, RC_1, KA_2)
% use the same values as their own cue/thresh guesses (rspIDX=1, rspFlip=1)
% for within-session consistency - DECISION logged: the OBE curated breathing
% modal rspIDX is 3, but these sessions' montages match their cue/thresh
% recordings, whose curated-modal rspIDX is 1; the run-on-guess QC figures are
% the arbiter. beatSpec defaults to '1,0,gt,3.5' where no breathing donor.

SESS = {'260625_OBE_NWU_HM_2', '260702_OBE_NWU_SP_2', '260622_OBE_NWU_RC_1', ...
        '260720_OBE_NWU_KA_2', '250929_Dupi_NMH_GH_1', '251027_Dupi_NMH_DL_1', ...
        '251006_OBE_NWU_RY_1', '260105_OBE_NWU_ZF_1'};

L = labPaths();
C = readcell(L.adminXlsx, 'Sheet', 'Sheet1');
hdr = C(2, :);
col = @(nm) find(cellfun(@(v) (ischar(v) || isstring(v)) && strcmpi(strtrim(char(string(v))), nm), hdr), 1);
cSub = col('Subject ID'); cTask = col('Task'); cPS = col('paramSource');
cIdx = col('rspIDX'); cFlip = col('rspFlip'); cSpkC = col('spikeClean');
cSpkT = col('spikeThresh'); cSpkW = col('spikeWin'); cBeat = col('beatSpec');

normT = @(v) lower(strrep(strtrim(char(string(v))), ' ', ''));
isBreathingRow = @(v) ismember(normT(v), {'breathingtasks', 'breathingtask', 'wavebreathing'});

for k = 1:numel(SESS)
    id = SESS{k};
    donor = 0; donorBreathing = 0;
    for r = 3:size(C, 1)
        v = C{r, cSub};
        if ~(ischar(v) || isstring(v)) || ~strcmpi(strtrim(char(string(v))), id), continue; end
        ps = C{r, cPS};
        if ~((ischar(ps) || isstring(ps)) && strcmpi(strtrim(char(string(ps))), 'curated')), continue; end
        if donor == 0, donor = r; end
        if isBreathingRow(C{r, cTask}) && donorBreathing == 0, donorBreathing = r; end
    end

    P = struct('task', 'breathingTasks_separate', 'paramSource', 'guess', ...
               'hasEEG', true, 'hasMacros', true, ...
               'spikeThresh', 20, 'spikeWin', 11, 'spikeClean', true, ...
               'beatSpec', '1,0,gt,3.5', 'isNewStd', true, ...
               'rspIDX', 1, 'rspFlip', 1);
    basis = 'session-consistent OBE default (rspIDX=1, matching cue/thresh guesses)';
    if donor > 0
        P.rspIDX  = numOr(C{donor, cIdx}, 1);
        P.rspFlip = numOr(C{donor, cFlip}, 1);
        P.spikeClean = numOr(C{donor, cSpkC}, 1) ~= 0;
        P.spikeThresh = numOr(C{donor, cSpkT}, 20);
        P.spikeWin = numOr(C{donor, cSpkW}, 11);
        basis = sprintf('inherited from curated row %d (%s)', donor, strtrim(char(string(C{donor, cTask}))));
    end
    if donorBreathing > 0
        bs = C{donorBreathing, cBeat};
        if (ischar(bs) || isstring(bs)) && strlength(strtrim(string(bs))) > 0
            P.beatSpec = strtrim(char(string(bs)));
            basis = [basis ' + breathing beatSpec']; %#ok<AGROW>
        end
    end
    fprintf('%s: %s -> rspIDX=%d rspFlip=%+d spikeClean=%d beatSpec=%s\n', ...
        id, basis, P.rspIDX, P.rspFlip, P.spikeClean, P.beatSpec);
    writeSheetSep(P, id, 'params');
end
fprintf('task9_writeGuesses: DONE\n');

function x = numOr(v, d)
    if isnumeric(v) && isscalar(v) && isfinite(v), x = double(v); return; end
    if ischar(v) || isstring(v)
        t = str2double(char(string(v)));
        if isfinite(t), x = t; return; end
    end
    x = d;
end

% respFix_sheet.m - apply the 2026-09-01 reportResponse.md dataTracking edits.
%
% Pass 1 (deterministic): curated promotions for every row the user called
% good, plus the directed hasEEG / rspIDX / rspFlip / macroRemove /
% spikeClean / rspThresh / cuedBackBuff corrections. Probe-dependent values
% (TB_3 breathing hasEEG, thresh PD_2 hasEEG, O15 RX_1/SP_2 hasEEG, refined
% beatSpecs) are applied by respFix_sheet2 once measured.
%
% Sep rows are written directly (multiple condition rows per session;
% writeParams only targets single rows). Run ALONE - single sheet writer.

% ---------------- single-row tasks via writeParams ----------------
% {task, id, {field, value; ...}}
E = { ...
 'breathingTask', '250623_Dupi_NMH_KS_3', {'paramSource', 'curated'}; ...
 'breathingTask', '260326_OBE_NWU_AD_1', {'paramSource', 'curated'}; ...
 'breathingTask', '260608_OBE_NWU_RX_1', {'paramSource', 'curated'}; ...
 'breathingTask', '250811_Dupi_NMH_TB_3', {'rspFlip', 1; 'macroRemove', []}; ...
 'breathingTask', '250929_Dupi_NMH_GH_3', {'hasEEG', true}; ...
 'breathingTask', '251002_Dupi_NMH_AB_3', {'hasEEG', true}; ...
 'breathingTask', '251013_Dupi_NMH_JN_3', {'hasEEG', true; 'macroRemove', []}; ...
 'breathingTask', '251110_Dupi_NMH_PC_2', {'hasEEG', true; 'rspIDX', 1; 'rspFlip', 1}; ...
 'breathingTask', '251120_Dupi_NMH_JL_2', {'hasEEG', true; 'rspFlip', 1; 'macroRemove', []}; ...
 'breathingTask', '260316_Dupi_NMH_PD_1', {'hasEEG', true; 'rspFlip', 1; 'macroRemove', []}; ...
 'breathingTask', '260316_Dupi_NMH_PD_2', {'hasEEG', true; 'macroRemove', []}; ...
 'breathingTask', '260326_OBE_NWU_AD_2', {'rspFlip', 1}; ...
 'breathingTask', '260406_Dupi_NMH_BS_1', {'hasEEG', true; 'rspFlip', 1; 'macroRemove', []; 'spikeClean', true}; ...
 'breathingTask', '260504_Dupi_NMH_JA_1', {'hasEEG', true; 'rspFlip', 1; 'macroRemove', []; 'spikeClean', true}; ...
 'breathingTask', '260504_Dupi_NMH_JA_2', {'hasEEG', true; 'rspFlip', 1; 'macroRemove', []; 'spikeClean', true}; ...
 'breathingTask', '260514_OBE_NWU_BW_1', {'rspFlip', 1}; ...
 'EmotionalMovieTask', '260806_EEG_NWU_JH', {'paramSource', 'curated'}; ...
 'EmotionalMovieTask', '260806_EEG_NWU_MM', {'paramSource', 'curated'}; ...
 'EmotionalMovieTask', '260807_EEG_NWU_GP', {'paramSource', 'curated'}; ...
 'EmotionalMovieTask', '260810_EEG_NWU_AL', {'paramSource', 'curated'}; ...
 'alternating6Blocks', '260806_EEG_NWU_MM', {'paramSource', 'curated'}; ...
 'alternating6Blocks', '260807_EEG_NWU_GP', {'paramSource', 'curated'}; ...
 'alternating6Blocks', '260810_EEG_NWU_AL', {'paramSource', 'curated'}; ...
 'alternating6Blocks', '260810_EEG_NWU_IS', {'paramSource', 'curated'}; ...
 'alternating6Blocks', '260811_EEG_NWU_MS', {'paramSource', 'curated'}; ...
 'cueTask', '260316_Dupi_NMH_PD_2', {'paramSource', 'curated'}; ...
 'cueTask', '260504_Dupi_NMH_JA_2', {'paramSource', 'curated'}; ...
 'cueTask', '260702_OBE_NWU_SP_2', {'paramSource', 'curated'}; ...
 'cueTask', '260622_OBE_NWU_RC_1', {'respThresh', 4000; 'cuedBackBuff', 500; 'paramSource', 'curated'}; ...
 'cueTask', '260720_OBE_NWU_KA_2', {'respThresh', 4000; 'cuedBackBuff', 500; 'paramSource', 'curated'}; ...
 'threshTask', '260625_OBE_NWU_HM_2', {'paramSource', 'curated'}; ...
 'threshTask', '260720_OBE_NWU_KA_2', {'paramSource', 'curated'}; ...
 'threshTask', '260504_Dupi_NMH_JA_2', {'rspIDX', 1; 'rspFlip', 1}};

nOK = 0; nFail = 0;
for k = 1:size(E, 1)
    [tk, id, fv] = E{k, :};
    ok = false;
    for att = 1:20
        try
            P = applyParams(tk, id);
            for f = 1:size(fv, 1)
                P.(fv{f, 1}) = fv{f, 2};
            end
            writeParams(P, id);
            ok = true; break;
        catch ME
            fprintf('RESPFIX retry %d %s %s: %s\n', att, tk, id, ME.message);
            pause(20);
        end
    end
    if ok, nOK = nOK + 1; else, nFail = nFail + 1; fprintf('RESPFIX FAILED %s %s\n', tk, id); end
end
fprintf('RESPFIX single-row: %d ok, %d failed\n', nOK, nFail);

% ---------------- sep rows: direct cell writes ----------------
sepPromote = {'250929_Dupi_NMH_GH_1', '251027_Dupi_NMH_DL_1', '260622_OBE_NWU_RC_1'};
sepSpike0  = {'260625_OBE_NWU_HM_2', '260702_OBE_NWU_SP_2', '260720_OBE_NWU_KA_2'};
sepConds = {'audiobook', 'distractedbreathing', 'focusedbreathing', 'sleep', 'sleepwithodor', 'restingbaseline'};

L = labPaths();
for att = 1:20
    try
        C = readcell(L.adminXlsx, 'Sheet', 'Sheet1');
        hdr = C(2, :);
        colIdx = @(n) find(cellfun(@(x) (ischar(x) || isstring(x)) && strcmpi(strtrim(char(string(x))), n), hdr), 1);
        cID = colIdx('Subject ID'); cTask = colIdx('Task'); cRaw = colIdx('Raw Data Extracted');
        cPS = colIdx('paramSource'); cSC = colIdx('spikeClean'); cDT = colIdx('dataType');
        assert(~isempty(cPS) && ~isempty(cSC), 'paramSource/spikeClean columns not found');
        nW = 0;
        for r = 3:size(C, 1)
            idv = C{r, cID};
            if ~(ischar(idv) || isstring(idv)), continue; end
            id = strtrim(char(string(idv)));
            tks = lower(char(string(cellVal(C{r, cTask})))); tks = tks(~isspace(tks));
            if ~ismember(tks, sepConds), continue; end
            rawv = cellVal(C{r, cRaw});
            if strlength(strtrim(string(rawv))) == 0, continue; end
            dt = ''; if ~isempty(cDT), dt = lower(strtrim(char(string(cellVal(C{r, cDT}))))); end
            if contains(dt, 'echem'), continue; end
            % coordinate-verified single-cell writes (writeParams pattern)
            if any(strcmpi(sepPromote, id))
                nW = nW + writeSepCell(L.adminXlsx, C, r, cID, id, cPS, 'curated');
            end
            if any(strcmpi(sepSpike0, id))
                nW = nW + writeSepCell(L.adminXlsx, C, r, cID, id, cSC, false);
            end
        end
        fprintf('RESPFIX sep rows: %d cells written\n', nW);
        break;
    catch ME
        fprintf('RESPFIX sep retry %d: %s\n', att, ME.message);
        pause(20);
        if att == 20, fprintf('RESPFIX SEP FAILED\n'); end
    end
end
disp('RESPFIX_SHEET DONE')

function n = writeSepCell(xlsx, C, r, cID, id, col, val)
    n = 0;
    cur = '';
    if col <= size(C, 2)
        cur = cellVal(C{r, col});
    end
    same = false;
    if islogical(val)
        same = strcmpi(strtrim(char(string(cur))), char(string(val))) || ...
               (isnumeric(cur) && ~isempty(cur) && isequal(logical(cur), val)) || ...
               (islogical(cur) && isequal(cur, val));
    else
        same = strcmpi(strtrim(char(string(cur))), strtrim(char(string(val))));
    end
    if same, return; end
    ref = sprintf('%s%d', colLetter(cID), r);
    chk = readcell(xlsx, 'Sheet', 'Sheet1', 'Range', ref);
    assert(strcmpi(strtrim(char(string(chk{1}))), id), 'coordinate misalignment at %s', ref);
    tgt = sprintf('%s%d', colLetter(col), r);
    writecell({val}, xlsx, 'Sheet', 'Sheet1', 'Range', tgt, 'AutoFitWidth', false);
    fprintf('RESPFIX sep %s row %d %s -> %s\n', id, r, tgt, char(string(val)));
    n = 1;
end

function v = cellVal(x)
    if ismissing(string(x)), v = ''; else, v = x; end
end

function s = colLetter(n)
    s = '';
    while n > 0
        rr = mod(n - 1, 26);
        s = [char('A' + rr) s]; %#ok<AGROW>
        n = floor((n - 1) / 26);
    end
end

% respFix_sheet2.m - probe-dependent dataTracking edits from the 2026-09-01
% reportResponse.md round (pass 2; deterministic edits are in respFix_sheet).
%
% Probe evidence (E:\reprocBackup_260824\probe_resp1/2/3.log):
%   - EEG channels confirmed present in the raw recordings of TB_3 breathing,
%     PD_2 thresh, RX_1 O15, SP_2 O15 (9/9 reference 10-20 labels)
%   - beatSpecs: PC_2 1,0,gt,4 (93% in-range once noise windows are blanked,
%     was 79%); JL_2 1,0,gt,3 (99%, lowest burst); CP_1 movie 1,0,gt,3
%     (69 bpm / 89% once blanked - was a complete failure); ZF_1 per the
%     dedicated blanked sweep (probe_resp3). TB_3 keeps 1,0,gt,3.5 - its
%     burst overdetection is fixed by the buildECGz blanking alone.

E = { ...
 'breathingTask', '250811_Dupi_NMH_TB_3', {'hasEEG', true}; ...
 'threshTask',    '260316_Dupi_NMH_PD_2', {'hasEEG', true}; ...
 'O15',           '260608_OBE_NWU_RX_1', {'hasEEG', true}; ...
 'O15',           '260702_OBE_NWU_SP_2', {'hasEEG', true}; ...
 'breathingTask', '251110_Dupi_NMH_PC_2', {'beatSpec', '1,0,gt,4'}; ...
 'breathingTask', '251120_Dupi_NMH_JL_2', {'beatSpec', '1,0,gt,3'}; ...
 'EmotionalMovieTask', '251009_OBE_NWU_CP_1', {'beatSpec', '1,0,gt,3'}};
% ZF_1 (sep rows carry beatSpec per condition row) is handled below.
% probe_resp3 blanked sweep: beat count is stable from threshold 2.5 to 5
% (a genuine uniform R-peak family, not threshold noise); 4.5 gives 99%
% in-range / cv 0.09 / lowest burst. NB the ~37 bpm rate is flagged for the
% user in the report.
ZF1_SPEC = '1,0,gt,4.5';

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
            fprintf('RESPFIX2 retry %d %s %s: %s\n', att, tk, id, ME.message);
            pause(20);
        end
    end
    if ok, nOK = nOK + 1; else, nFail = nFail + 1; fprintf('RESPFIX2 FAILED %s %s\n', tk, id); end
end
fprintf('RESPFIX2 single-row: %d ok, %d failed\n', nOK, nFail);

% ---------------- ZF_1 sep rows: beatSpec via direct cell writes ----------------
if ~isempty(ZF1_SPEC)
    sepConds = {'audiobook', 'distractedbreathing', 'focusedbreathing', 'sleep', 'sleepwithodor', 'restingbaseline'};
    L = labPaths();
    for att = 1:20
        try
            C = readcell(L.adminXlsx, 'Sheet', 'Sheet1');
            hdr = C(2, :);
            colIdx = @(n) find(cellfun(@(x) (ischar(x) || isstring(x)) && strcmpi(strtrim(char(string(x))), n), hdr), 1);
            cID = colIdx('Subject ID'); cTask = colIdx('Task');
            cBS = colIdx('beatSpec'); cDT = colIdx('dataType');
            nW = 0;
            for r = 3:size(C, 1)
                idv = C{r, cID};
                if ~(ischar(idv) || isstring(idv)), continue; end
                if ~strcmpi(strtrim(char(string(idv))), '260105_OBE_NWU_ZF_1'), continue; end
                tks = lower(char(string(C{r, cTask}))); tks = tks(~isspace(tks));
                if ~ismember(tks, sepConds), continue; end
                dt = ''; if ~isempty(cDT) && ~ismissing(string(C{r, cDT})), dt = lower(strtrim(char(string(C{r, cDT})))); end
                if contains(dt, 'echem'), continue; end
                ref = sprintf('%s%d', colLetter(cID), r);
                chk = readcell(L.adminXlsx, 'Sheet', 'Sheet1', 'Range', ref);
                assert(strcmpi(strtrim(char(string(chk{1}))), '260105_OBE_NWU_ZF_1'), 'misalignment at %s', ref);
                tgt = sprintf('%s%d', colLetter(cBS), r);
                writecell({ZF1_SPEC}, L.adminXlsx, 'Sheet', 'Sheet1', 'Range', tgt, 'AutoFitWidth', false);
                fprintf('RESPFIX2 ZF_1 row %d beatSpec -> %s\n', r, ZF1_SPEC);
                nW = nW + 1;
            end
            fprintf('RESPFIX2 ZF_1: %d cells written\n', nW);
            break;
        catch ME
            fprintf('RESPFIX2 ZF_1 retry %d: %s\n', att, ME.message);
            pause(20);
        end
    end
end
disp('RESPFIX_SHEET2 DONE')

function s = colLetter(n)
    s = '';
    while n > 0
        rr = mod(n - 1, 26);
        s = [char('A' + rr) s]; %#ok<AGROW>
        n = floor((n - 1) / 26);
    end
end

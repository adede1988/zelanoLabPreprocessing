% rebuildSheet_260825 — reconstruct the master dataTracking.xlsx after the
% 2026-08-25 workbook corruption (the file stopped opening as a workbook
% during task3_verifyFinals' write burst; corrupt copy preserved at
% E:\reprocBackup_260824\dataTracking_corrupt_copy.xlsx).
%
% Strategy: start from the pre-run backup (dataTracking_before.xlsx) and
% deterministically replay every logged sheet mutation of this work order on
% an E: work copy, verify it, then move it into place on R:. The breathing
% task's Data Preprocessed states are NOT replayed here - rerunning
% task3_verifyFinals afterwards rebuilds them from the disk, which is the
% ground truth (D2).
%
% Replayed here:
%   1. SP_2 Subject ID fix (11 cells, rows 280-290)
%   2. Task 1 Data Preprocessed sync (from the saved inventory_260824.mat)
%   3. Task 2 extraction marks (16 rows: Raw Data Extracted=X + datPre)
%   4. Tasks 4/5/6 guesses (9 rows, exact values from task456_guesses.log)
%   5. Task 3 guesses (HW, RX_1 breathing; values from task3_guesses.log)

SRC  = 'E:\reprocBackup_260824\dataTracking_before.xlsx';
WORK = 'E:\reprocBackup_260824\dataTracking_rebuild.xlsx';
DEST = 'R:\Neurology\Zelano_Lab\Lab_Common\Admin\dataTracking.xlsx';

copyfile(SRC, WORK);
fprintf('work copy created from pre-run backup\n');

% ---- 1. SP_2 ID fix ----
OLD_ID = '2607802_OBE_NWU_SP_2'; NEW_ID = '260702_OBE_NWU_SP_2';
C = readcell(WORK, 'Sheet', 'Sheet1');
cSub = findColH(C, 'Subject ID');
nFix = 0;
for r = 3:size(C, 1)
    v = C{r, cSub};
    if (ischar(v) || isstring(v)) && strcmp(strtrim(char(v)), OLD_ID)
        writecell({NEW_ID}, WORK, 'Sheet', 'Sheet1', ...
            'Range', sprintf('%s%d', colLetter(cSub), r), 'AutoFitWidth', false);
        nFix = nFix + 1;
    end
end
assert(nFix == 11, 'expected 11 SP_2 fixes, made %d', nFix);
fprintf('1. SP_2 fix: %d cells\n', nFix);

% ---- 2. Task 1 X sync (inventory-driven; breathing rows corrected later by
%         task3_verifyFinals, but replaying keeps the intermediate state exact) ----
S = load('E:\reprocBackup_260824\inventory_260824.mat'); T = S.T;
C = readcell(WORK, 'Sheet', 'Sheet1');
cSub = findColH(C, 'Subject ID'); cPre = findColH(C, 'Data Preprocessed');
nSet = 0;
for i = 1:height(T)
    if ~T.inScope(i) || ~T.finalKnown(i), continue; end
    r = T.excelRow(i);
    cur = C{r, cPre};
    curX = ~isBlankC(cur);
    if T.eligible(i)
        want = logical(T.finalValid(i));
    else
        if ~(curX && ~T.finalValid(i)), continue; end
        want = false;
    end
    if curX == want, continue; end
    if want, val = 'X'; else, val = ''; end
    writecell({val}, WORK, 'Sheet', 'Sheet1', ...
        'Range', sprintf('%s%d', colLetter(cPre), r), 'AutoFitWidth', false);
    nSet = nSet + 1;
end
fprintf('2. task1 sync: %d cells (expect 41)\n', nSet);

% ---- 3. Task 2 extraction marks ----
ROWS2 = { ...
 '260227_EEG_NWU_HW', 'breathingTask'; '260805_EEG_NWU_CA', 'alternating6Blocks'; ...
 '260806_EEG_NWU_JH', 'alternating6Blocks'; '260806_EEG_NWU_JH', 'EmotionalMovieTask'; ...
 '260806_EEG_NWU_MM', 'alternating6Blocks'; '260806_EEG_NWU_MM', 'EmotionalMovieTask'; ...
 '260807_EEG_NWU_GP', 'alternating6Blocks'; '260807_EEG_NWU_GP', 'EmotionalMovieTask'; ...
 '260810_EEG_NWU_IS', 'alternating6Blocks'; '260810_EEG_NWU_IS', 'EmotionalMovieTask'; ...
 '260810_EEG_NWU_AL', 'alternating6Blocks'; '260810_EEG_NWU_AL', 'EmotionalMovieTask'; ...
 '260811_EEG_NWU_MS', 'alternating6Blocks'; '260811_EEG_NWU_MS', 'EmotionalMovieTask'; ...
 '260811_EEG_NWU_HK', 'alternating6Blocks'; '260811_EEG_NWU_HK', 'EmotionalMovieTask'};
for k = 1:size(ROWS2, 1)
    P = struct('task', ROWS2{k, 2}, 'datPre', 'R:\Neurology\Zelano_Lab\Lab_Common\AllStudyData\EEGbreathing\');
    writeParams(P, ROWS2{k, 1}, WORK, 'AllowUnextracted', true, 'SetRawExtracted', true, 'Verbose', false);
end
fprintf('3. task2 marks: %d rows\n', size(ROWS2, 1));

% ---- 4. Tasks 4/5/6 guesses (logged values) ----
G = { ...
 '260608_OBE_NWU_RX_1', 'O15',        3000, 150, 500, false; ...
 '260702_OBE_NWU_SP_2', 'O15',        3000, 150, 500, false; ...
 '260608_OBE_NWU_RX_1', 'threshTask', 5000, 350, 500, true; ...
 '260625_OBE_NWU_HM_2', 'threshTask', 5000, 350, 500, true; ...
 '260702_OBE_NWU_SP_2', 'threshTask', 5000, 350, 500, true; ...
 '260720_OBE_NWU_KA_2', 'threshTask', 5000, 350, 500, true; ...
 '260702_OBE_NWU_SP_2', 'cueTask',    3000, 150, 500, true; ...
 '260622_OBE_NWU_RC_1', 'cueTask',    3000, 150, 500, true; ...
 '260720_OBE_NWU_KA_2', 'cueTask',    3000, 150, 500, true};
for k = 1:size(G, 1)
    P = struct('task', G{k, 2}, 'paramSource', 'guess', 'rspIDX', 1, 'rspFlip', 1, ...
        'hasEEG', G{k, 6}, 'spikeClean', true, 'spikeThresh', 20, 'spikeWin', 11, ...
        'macroRemove', [], 'respThresh', G{k, 3}, 'cuedBackBuff', G{k, 4}, ...
        'adjWin', G{k, 5}, 'isNewStd', true);
    writeParams(P, G{k, 1}, WORK, 'AllowUnextracted', true, 'Verbose', false);
end
fprintf('4. task456 guesses: %d rows\n', size(G, 1));

% ---- 5. Task 3 guesses ----
P = struct('task', 'breathingTask', 'rspIDX', 1, 'rspFlip', -1, 'hasEEG', true, ...
    'hasMacros', false, 'spikeClean', false, 'spikeThresh', 20, 'spikeWin', 11, ...
    'macroRemove', [], 'beatSpec', '1,0,gt,3.5', 'isNewStd', true, 'paramSource', 'guess');
writeParams(P, '260227_EEG_NWU_HW', WORK, 'Verbose', false);
P = struct('task', 'breathingTask', 'rspIDX', 3, 'rspFlip', 1, 'hasEEG', true, ...
    'hasMacros', true, 'spikeClean', true, 'spikeThresh', 20, 'spikeWin', 11, ...
    'macroRemove', [], 'beatSpec', '1,0,lt,-2 & 2,1,gt,3 & 3,2,lt,0', 'isNewStd', true, ...
    'paramSource', 'guess');
writeParams(P, '260608_OBE_NWU_RX_1', WORK, 'Verbose', false);
fprintf('5. task3 guesses: 2 rows\n');

% ---- verify the work copy, then move into place ----
C2 = readcell(WORK, 'Sheet', 'Sheet1');
assert(size(C2, 1) >= 330, 'rebuilt sheet lost rows (%d)', size(C2, 1));
nNew = 0;
for r = 3:size(C2, 1)
    v = C2{r, findColH(C2, 'Subject ID')};
    if (ischar(v) || isstring(v)) && strcmp(strtrim(char(v)), NEW_ID), nNew = nNew + 1; end
end
assert(nNew == 11, 'SP_2 verification failed (%d)', nNew);
fprintf('rebuilt sheet verified (rows=%d, SP_2=%d)\n', size(C2, 1), nNew);

copyfile(WORK, [DEST '.tmp']);
movefile([DEST '.tmp'], DEST, 'f');
C3 = readcell(DEST, 'Sheet', 'Sheet1');
assert(size(C3, 1) >= 330, 'post-move readback failed');
fprintf('rebuildSheet_260825: DONE - master sheet restored on R:\n');

% ============================ helpers ============================
function idx = findColH(C, name)
    hdr = C(2, :);
    idx = find(cellfun(@(v) (ischar(v) || isstring(v)) && ...
        strcmpi(strtrim(char(string(v))), name), hdr), 1);
    assert(~isempty(idx), 'column %s not found', name);
end

function tf = isBlankC(v)
    if isa(v, 'missing'), tf = true; return; end
    if isnumeric(v) && (isempty(v) || all(isnan(v(:)))), tf = true; return; end
    if (ischar(v) || isstring(v)) && strlength(strtrim(string(v))) == 0, tf = true; return; end
    tf = false;
end

function s = colLetter(n)
    s = '';
    while n > 0
        r = mod(n - 1, 26);
        s = [char('A' + r) s]; %#ok<AGROW>
        n = floor((n - 1) / 26);
    end
    if isempty(s), s = 'A'; end
end

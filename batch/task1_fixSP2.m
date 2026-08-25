% task1_fixSP2 — correct the Subject ID typo 2607802_OBE_NWU_SP_2 -> 260702_OBE_NWU_SP_2
%
% One of the two hand-edits authorised by Tasks_260824.md (Task 1 step 2 / D12e).
% The session folder on R: is named 260702_OBE_NWU_SP_2 (verified 2026-08-24), so
% only the sheet is wrong. Edits the Admin master in place, one verified cell at
% a time (same alignment-safety pattern as writeParams). Rerunnable: rows already
% carrying the corrected ID are counted, not re-edited, so a partially applied
% run can simply be run again.

OLD_ID = '2607802_OBE_NWU_SP_2';
NEW_ID = '260702_OBE_NWU_SP_2';
N_EXPECT = 11;    % typo rows in the 2026-08-24 sheet (Excel rows 280-290)

% the work order mandates a sheet backup before the first write
assert(exist('E:\reprocBackup_260824\dataTracking_before.xlsx', 'file') == 2, ...
    'sheet backup E:\\reprocBackup_260824\\dataTracking_before.xlsx missing - back up first');

L = labPaths();

% Task 1 step 2: the session folder on R: must carry the CORRECTED name;
% if it carried the typo name we would have to stop and ask before renaming
assert(isfolder(fullfile(L.rootOBE, NEW_ID)), ...
    'session folder %s not found under %s - stop and ask', NEW_ID, L.rootOBE);
assert(~isfolder(fullfile(L.rootOBE, OLD_ID)), ...
    'typo-named folder %s exists on R: - stop and ask before renaming anything', OLD_ID);
xlsxPath = L.adminXlsx;
fprintf('task1_fixSP2: sheet = %s\n', xlsxPath);

C   = readcell(xlsxPath, 'Sheet', 'Sheet1');
hdr = C(2, :);
cSub = 0;
for c = 1:numel(hdr)
    v = hdr{c};
    if (ischar(v) || isstring(v)) && strcmpi(strtrim(char(v)), 'Subject ID')
        cSub = c; break;
    end
end
assert(cSub > 0, 'Subject ID column not found');

oldRows = []; newRows = [];
for r = 3:size(C, 1)
    v = C{r, cSub};
    if ischar(v) || isstring(v)
        s = strtrim(char(v));
        if strcmp(s, OLD_ID), oldRows(end+1) = r; end %#ok<SAGROW>
        if strcmp(s, NEW_ID), newRows(end+1) = r; end %#ok<SAGROW>
    end
end
fprintf('rows with typo ID: %d %s | rows already corrected: %d %s\n', ...
    numel(oldRows), mat2str(oldRows), numel(newRows), mat2str(newRows));
assert(numel(oldRows) + numel(newRows) == N_EXPECT, ...
    'expected %d SP_2 rows total (typo+corrected), found %d - aborting', ...
    N_EXPECT, numel(oldRows) + numel(newRows));
if isempty(oldRows)
    fprintf('task1_fixSP2: nothing to do (all %d rows already corrected)\n', N_EXPECT);
    return;
end

for r = oldRows
    ref = sprintf('%s%d', colLetter(cSub), r);
    rng = [ref ':' ref];
    chk = readcell(xlsxPath, 'Sheet', 'Sheet1', 'Range', rng);
    assert(strcmp(strtrim(char(string(chk{1}))), OLD_ID), ...
        'alignment check failed at %s (read "%s") - aborting', ref, char(string(chk{1})));
    try
        writecell({NEW_ID}, xlsxPath, 'Sheet', 'Sheet1', 'Range', ref, 'AutoFitWidth', false);
    catch
        writecell({NEW_ID}, xlsxPath, 'Sheet', 'Sheet1', 'Range', ref);
    end
    chk2 = readcell(xlsxPath, 'Sheet', 'Sheet1', 'Range', rng);
    assert(strcmp(strtrim(char(string(chk2{1}))), NEW_ID), ...
        'post-write verification failed at %s (read "%s")', ref, char(string(chk2{1})));
    fprintf('  %s: %s -> %s (verified)\n', ref, OLD_ID, NEW_ID);
end

% final whole-sheet verification
C2 = readcell(xlsxPath, 'Sheet', 'Sheet1');
nOld = 0; nNew = 0;
for r = 3:size(C2, 1)
    v = C2{r, cSub};
    if (ischar(v) || isstring(v))
        s = strtrim(char(v));
        if strcmp(s, OLD_ID), nOld = nOld + 1; end
        if strcmp(s, NEW_ID), nNew = nNew + 1; end
    end
end
fprintf('after edit: %d rows with old ID, %d rows with new ID\n', nOld, nNew);
assert(nOld == 0 && nNew == N_EXPECT, 'post-edit verification failed');
fprintf('task1_fixSP2: DONE\n');

function s = colLetter(n)
    s = '';
    while n > 0
        r = mod(n - 1, 26);
        s = [char('A' + r) s]; %#ok<AGROW>
        n = floor((n - 1) / 26);
    end
    if isempty(s), s = 'A'; end
end

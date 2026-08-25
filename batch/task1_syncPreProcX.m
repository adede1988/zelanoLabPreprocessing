% task1_syncPreProcX — bring the sheet's "Data Preprocessed" column into line
% with the disk (Tasks_260824.md Task 1 step 6 / D2).
%
% Consumes E:\reprocBackup_260824\inventory_260824.mat (written by
% task1_inventory, which must have run against the already-SP_2-fixed sheet).
%
% Rules:
%   eligible rows (Raw Data Extracted non-blank, not INCOMPLETE):
%       desired = 'X' iff a valid final exists on disk, blank otherwise
%   ineligible rows (stubs/duplicates): never given an X; a wrong X is
%       cleared only when no valid final exists for that session x task
%   rows whose final file is present but unreadable (finalKnown=false) are
%       skipped entirely and must be resolved by hand.
%
% Every write is alignment-verified (Subject ID AND Task cell re-checked at
% the target row) and read back afterwards. From here on, only writePreProcX /
% clearPreProcX touch this column.

INV = 'E:\reprocBackup_260824\inventory_260824.mat';
S = load(INV); T = S.T;

L = labPaths();
xlsxPath = L.adminXlsx;
fprintf('task1_syncPreProcX: sheet = %s\n', xlsxPath);
C   = readcell(xlsxPath, 'Sheet', 'Sheet1');
hdr = C(2, :);
cSub  = findColX(hdr, 'Subject ID');
cTask = findColX(hdr, 'Task');
cPreX = findColX(hdr, 'Data Preprocessed');

nSet = 0; nClr = 0; nSame = 0; nSkip = 0;
for i = 1:height(T)
    if ~T.inScope(i), continue; end
    if ~T.finalKnown(i)
        fprintf('SKIP  row %-4d %-28s %-22s final unreadable - resolve by hand\n', ...
            T.excelRow(i), T.SubjectID{i}, T.Task{i});
        nSkip = nSkip + 1;
        continue;
    end
    r = T.excelRow(i);
    if r > size(C, 1)
        error('task1_syncPreProcX:shrunk', ...
            'inventory row %d beyond sheet end (%d rows) - sheet changed since inventory; rerun task1_inventory.', ...
            r, size(C, 1));
    end
    % alignment safety: Subject ID AND Task at this row must match the inventory
    sheetID   = cs(C{r, cSub});
    sheetTask = cs(C{r, cTask});
    if ~strcmpi(strtrim(sheetID), strtrim(T.SubjectID{i})) || ...
       ~strcmp(normStr(sheetTask), normStr(T.Task{i}))
        error('task1_syncPreProcX:misaligned', ...
            'row %d: sheet [%s|%s] != inventory [%s|%s] - sheet changed since inventory; rerun task1_inventory.', ...
            r, sheetID, sheetTask, T.SubjectID{i}, T.Task{i});
    end

    cur  = C{r, cPreX};
    curX = ~isBlankCell(cur);
    if T.eligible(i)
        want = logical(T.finalValid(i));
    else
        % stub rows: only correct a wrong X, never add one
        if ~(curX && ~T.finalValid(i))
            nSame = nSame + 1;
            continue;
        end
        want = false;
    end
    if curX == want
        nSame = nSame + 1;
        continue;
    end

    ref = sprintf('%s%d', colLetter(cPreX), r);
    if want, val = 'X'; else, val = ''; end
    try
        writecell({val}, xlsxPath, 'Sheet', 'Sheet1', 'Range', ref, 'AutoFitWidth', false);
    catch
        writecell({val}, xlsxPath, 'Sheet', 'Sheet1', 'Range', ref);
    end
    % read back and verify
    chk = readcell(xlsxPath, 'Sheet', 'Sheet1', 'Range', [ref ':' ref]);
    gotX = ~isBlankCell(chk{1});
    assert(gotX == want, 'post-write verification failed at %s (wanted %d, read %d)', ref, want, gotX);
    if want
        nSet = nSet + 1;
        fprintf('SET   %s  row %-4d %-28s %-22s (was "%s")\n', ref, r, T.SubjectID{i}, T.Task{i}, cs(cur));
    else
        nClr = nClr + 1;
        fprintf('CLEAR %s  row %-4d %-28s %-22s (was "%s")\n', ref, r, T.SubjectID{i}, T.Task{i}, cs(cur));
    end
end
fprintf('task1_syncPreProcX: DONE  set=%d cleared=%d unchanged=%d skipped-unreadable=%d\n', ...
    nSet, nClr, nSame, nSkip);

% ============================ helpers ============================

function idx = findColX(hdr, name)
    idx = 0;
    for c = 1:numel(hdr)
        v = hdr{c};
        if (ischar(v) || isstring(v)) && strcmpi(strtrim(char(v)), name)
            idx = c; return;
        end
    end
    error('column "%s" not found', name);
end

function tf = isBlankCell(v)
    if isa(v, 'missing'), tf = true; return; end
    if isnumeric(v) && (isempty(v) || all(isnan(v(:)))), tf = true; return; end
    if (ischar(v) || isstring(v)) && strlength(strtrim(string(v))) == 0, tf = true; return; end
    tf = false;
end

function s = cs(v)
    if isa(v, 'missing'), s = ''; return; end
    if ischar(v), s = v; return; end
    if isstring(v), s = char(v); return; end
    if isnumeric(v) || islogical(v)
        if isscalar(v), s = num2str(v); else, s = mat2str(v); end
        return;
    end
    s = char(string(v));
end

function s = normStr(v)
    s = lower(cs(v));
    s = s(~isspace(s));
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

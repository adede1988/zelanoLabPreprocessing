function writeSheetSep(P, sessID, action, xlsxPath)
%WRITESHEETSEP  Sheet writer for breathingTasks_separate (Task 9 / D12d).
%
%   writeSheetSep(P, sessID, 'params')   write P's parameter values identically
%                                        onto EVERY in-scope condition row
%   writeSheetSep(P, sessID, 'X')        set Data Preprocessed = X on every row
%   writeSheetSep(P, sessID, 'clearX')   blank it on every row
%
%   In-scope = the session's condition rows (audiobook/distractedBreathing/
%   focusedBreathing/sleep/sleepWithOdor/restingBaseline, spelling-insensitive)
%   with Raw Data Extracted non-blank/non-INCOMPLETE and dataType == ephys.
%   The task-9 writers deliberately do NOT use writePreProcX (first-match
%   semantics cannot cover multiple condition rows). Each write verifies the
%   Subject ID cell at the target row first.

    sheet = 'Sheet1';
    if nargin < 4 || isempty(xlsxPath)
        L = labPaths();
        xlsxPath = L.adminXlsx;
    end
    sessID = strtrim(char(string(sessID)));

    C = readcell(xlsxPath, 'Sheet', sheet);
    hdr = C(2, :);
    col = @(nm) find(cellfun(@(v) (ischar(v) || isstring(v)) && ...
        strcmpi(strtrim(char(string(v))), nm), hdr), 1);
    cSub = col('Subject ID'); cTask = col('Task'); cRaw = col('Raw Data Extracted');
    cDT = col('dataType'); cPre = col('Data Preprocessed');
    % a missing header must never silently redirect writes (colLetter([]) = 'A')
    assert(~isempty(cSub) && ~isempty(cTask) && ~isempty(cRaw) && ...
           ~isempty(cDT) && ~isempty(cPre), ...
           'writeSheetSep: required sheet columns not found - aborting');

    conds = {'audiobook', 'distractedbreathing', 'focusedbreathing', ...
             'sleep', 'sleepwithodor', 'restingbaseline'};
    rowsHit = [];
    for r = 3:size(C, 1)
        v = C{r, cSub};
        if ~(ischar(v) || isstring(v)) || ~strcmpi(strtrim(char(string(v))), sessID), continue; end
        tk = C{r, cTask};
        if ~(ischar(tk) || isstring(tk)), continue; end
        tn = lower(strrep(strtrim(char(string(tk))), ' ', ''));
        if ~ismember(tn, conds), continue; end
        rawv = C{r, cRaw};
        if isa(rawv, 'missing') || ((ischar(rawv) || isstring(rawv)) && strlength(strtrim(string(rawv))) == 0), continue; end
        if (ischar(rawv) || isstring(rawv)) && strcmpi(strtrim(char(string(rawv))), 'INCOMPLETE'), continue; end
        dt = C{r, cDT};
        if ~((ischar(dt) || isstring(dt)) && strcmpi(strtrim(char(string(dt))), 'ephys')), continue; end
        rowsHit(end+1) = r; %#ok<AGROW>
    end
    assert(~isempty(rowsHit), 'writeSheetSep: no in-scope condition rows for %s', sessID);

    switch action
        case 'params'
            % write the parameter columns via writeParams on each row is not
            % possible (first-match); write directly, verified per cell
            paramCols = {'rspIDX', 'num'; 'rspFlip', 'num'; 'hasEEG', 'bool'; ...
                         'spikeClean', 'bool'; 'spikeThresh', 'num'; 'spikeWin', 'num'; ...
                         'hasMacros', 'bool'; 'beatSpec', 'str'; 'isNewStd', 'bool'; ...
                         'paramSource', 'str'};
            for r = rowsHit
                verifyRow(xlsxPath, sheet, cSub, r, sessID);
                for pc = 1:size(paramCols, 1)
                    fld = paramCols{pc, 1};
                    if ~isfield(P, fld), continue; end
                    ci = col(fld);
                    if isempty(ci)
                        warning('writeSheetSep:noColumn', 'column "%s" not in sheet; skipped', fld);
                        continue;
                    end
                    val = P.(fld);
                    if strcmp(paramCols{pc, 2}, 'bool'), val = logical(val); end
                    if strcmp(paramCols{pc, 2}, 'str'), val = char(string(val)); end
                    writeCellChecked(xlsxPath, sheet, ci, r, val);
                end
                fprintf('writeSheetSep params: %s row %d\n', sessID, r);
            end
        case {'X', 'clearX'}
            if strcmp(action, 'X'), val = 'X'; else, val = ''; end
            for r = rowsHit
                verifyRow(xlsxPath, sheet, cSub, r, sessID);
                writeCellChecked(xlsxPath, sheet, cPre, r, val);
                fprintf('writeSheetSep %s: %s row %d\n', action, sessID, r);
            end
        otherwise
            error('writeSheetSep: unknown action "%s"', action);
    end
end

function verifyRow(xlsxPath, sheet, cSub, r, sessID)
    ref = sprintf('%s%d', colLetter(cSub), r);
    chk = readcell(xlsxPath, 'Sheet', sheet, 'Range', [ref ':' ref]);
    assert(strcmpi(strtrim(char(string(chk{1}))), sessID), ...
        'writeSheetSep: alignment check failed at %s', ref);
end

function writeCellChecked(xlsxPath, sheet, ci, r, val)
    ref = sprintf('%s%d', colLetter(ci), r);
    try
        writecell({val}, xlsxPath, 'Sheet', sheet, 'Range', ref, 'AutoFitWidth', false);
    catch
        writecell({val}, xlsxPath, 'Sheet', sheet, 'Range', ref);
    end
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

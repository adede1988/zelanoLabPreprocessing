function clearPreProcX(P, sessID, xlsxPath)
%CLEARPREPROCX  Blank a session's "Data Preprocessed" cell.
%
%   clearPreProcX(P, sessID)            % default dataTracking.xlsx
%   clearPreProcX(P, sessID, xlsxPath)  % explicit spreadsheet path
%
%   The clearing counterpart of writePreProcX (Tasks_260824.md D2): finds the
%   row matching sessID (Subject ID) and P.task and blanks that row's
%   "Data Preprocessed" column, so the sheet mirrors the disk when a final is
%   found to be missing or invalid. Keyed on Subject ID + Task like the
%   existing writers.

    sheet = 'Sheet1';

    if nargin < 3 || isempty(xlsxPath)
        xlsxPath = resolveDefaultXlsx();
    end
    if exist(xlsxPath, 'file') ~= 2
        error('clearPreProcX:noFile', 'Spreadsheet not found: %s', xlsxPath);
    end

    sessID = strtrim(char(string(sessID)));
    if isempty(sessID)
        error('clearPreProcX:badSession', 'sessID must be a non-empty string.');
    end
    if ~isfield(P, 'task') || isempty(P.task)
        error('clearPreProcX:noTask', 'P.task is required to identify the row.');
    end
    tkey = taskKey(P.task);
    if isempty(tkey)
        % an unknown task would "match" any sheet row whose Task is also
        % unmapped (canonTask '') and silently clear the wrong cell
        error('clearPreProcX:badTask', 'Unknown task "%s".', char(string(P.task)));
    end

    % --- read the sheet, locate the header row (the one with 'Subject ID') ---
    C    = readcell(xlsxPath, 'Sheet', sheet);
    hRow = findRow(C, 'Subject ID');
    if hRow == 0
        error('clearPreProcX:noHeader', 'No "Subject ID" header found in %s.', xlsxPath);
    end
    hdr = C(hRow, :);

    cSub  = findCol(hdr, 'Subject ID');
    cTask = findCol(hdr, 'Task');
    cPre  = findCol(hdr, 'Data Preprocessed');
    cRaw  = findCol(hdr, 'Raw Data Extracted');
    if cSub == 0 || cTask == 0 || cPre == 0
        error('clearPreProcX:missingCols', ...
            'Sheet needs "Subject ID", "Task", and "Data Preprocessed" columns.');
    end

    % --- find the matching data row (Subject ID + task), skipping stub rows
    %     (blank / INCOMPLETE Raw Data Extracted) so a duplicate stub above the
    %     real row cannot swallow the clear ---
    dRow = 0;
    for r = hRow+1 : size(C, 1)
        if isBlank(C{r, cSub}), continue; end
        sub = strtrim(char(string(C{r, cSub})));
        if ~strcmpi(sub, sessID), continue; end
        if ~strcmp(canonTask(C{r, cTask}), tkey), continue; end
        if cRaw > 0
            rawv = C{r, cRaw};
            if isBlank(rawv), continue; end
            if strcmpi(strtrim(char(string(rawv))), 'INCOMPLETE'), continue; end
        end
        dRow = r; break;
    end
    if dRow == 0
        error('clearPreProcX:noSession', ...
            'No row found for session "%s" / task "%s".', sessID, char(string(P.task)));
    end

    % --- blank the cell and save ---
    ref = sprintf('%s%d', colLetter(cPre), dRow);
    writecell({''}, xlsxPath, 'Sheet', sheet, 'Range', ref);
    fprintf('clearPreProcX: %s (%s) -> Data Preprocessed cleared at %s\n', ...
            sessID, char(string(P.task)), ref);
end

% ============================ helpers ============================

function xlsxPath = resolveDefaultXlsx()
    L = labPaths();
    if exist(L.adminXlsx, 'file') == 2
        xlsxPath = L.adminXlsx;
    else
        xlsxPath = fullfile(L.repo, 'dataTracking.xlsx');
    end
end

function r = findRow(C, name)
    r = 0;
    for i = 1:size(C, 1)
        if findCol(C(i, :), name) > 0, r = i; return; end
    end
end

function idx = findCol(hdr, name)
    idx = 0;
    for c = 1:numel(hdr)
        v = hdr{c};
        if (ischar(v) || isstring(v)) && strcmpi(strtrim(char(v)), name)
            idx = c; return;
        end
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

% --- task vocabulary: P.task and the sheet's Task column use different
%     names, so both map onto a common key before comparison. ---

function k = taskKey(task)   % P.task -> key
    s = lower(char(string(task)));
    s = s(~isspace(s));
    switch s
        case 'breathingtask',      k = 'breathing';
        case 'cuetask',            k = 'cue';
        case 'threshtask',         k = 'thresh';
        case 'o15',                k = 'O15';
        case 'emotionalmovietask', k = 'movie';
        case 'alternating6blocks', k = 'alt6';
        otherwise,                 k = '';
    end
end

function k = canonTask(t)    % sheet Task cell -> key
    if isBlank(t)
        k = ''; return;
    end
    s = lower(char(string(t)));
    s = s(~isspace(s));
    switch s
        case {'breathingtasks', 'wavebreathing', 'breathingtask'}
            k = 'breathing';
        case 'odorcuetask'
            k = 'cue';
        case 'o15'
            k = 'O15';
        case 'threshold'
            k = 'thresh';
        case 'emotionalmovietask'
            k = 'movie';
        case 'alternating6blocks'
            k = 'alt6';
        otherwise
            k = '';
    end
end

function tf = isBlank(v)
    if isa(v, 'missing'), tf = true; return; end
    if isnumeric(v) && (isempty(v) || all(isnan(v(:)))), tf = true; return; end
    if (ischar(v) || isstring(v)) && strlength(strtrim(string(v))) == 0, tf = true; return; end
    if iscell(v) && isempty(v), tf = true; return; end
    tf = false;
end

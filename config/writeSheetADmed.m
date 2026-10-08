function writeSheetADmed(sessID, cols, xlsxPath)
%WRITESHEETADMED  Write named summary cells into an ADmeditation session's row.
%
%   writeSheetADmed(sessID, {'nBreaths', 812, 'meanHR (bpm)', 56.2, ...})
%   writeSheetADmed(sessID, cols, xlsxPath)
%
%   The ADmeditation sessions are tracked in their own sheet,
%   labPaths().adMedXlsx (Admin\Data\dataTracking_AD_meditation.xlsx; header
%   row 2, data from row 3, one row per recording, keyed by Subject ID).
%   writeParams writes the parameter columns and writePreProcX the "Data
%   Preprocessed" X; this writes the per-session summary columns the main
%   fills after a final is saved (Analyzed Duration (min), nButtonPresses,
%   nPressesTrimmed, nBreaths, meanHR (bpm)). Only the named cells are
%   written; a name missing from the header is an error (strict: a typo must
%   not silently drop a value). The Subject ID cell is re-read at the
%   computed coordinate before anything is written.

    if nargin < 3 || isempty(xlsxPath)
        L = labPaths();
        xlsxPath = L.adMedXlsx;
    end
    assert(exist(xlsxPath, 'file') == 2, 'writeSheetADmed: sheet not found: %s', xlsxPath);
    assert(iscell(cols) && mod(numel(cols), 2) == 0, 'writeSheetADmed: cols must be {name, value, ...}');
    sessID = strtrim(char(string(sessID)));

    C = readcell(xlsxPath, 'Sheet', 'Sheet1');
    hdr = C(2, :);
    cSub = findCol(hdr, 'Subject ID');
    assert(cSub > 0, 'writeSheetADmed: no "Subject ID" column in row 2 of %s', xlsxPath);
    dRow = 0;
    for r = 3:size(C, 1)
        v = C{r, cSub};
        if (ischar(v) || isstring(v)) && strcmpi(strtrim(char(v)), sessID)
            dRow = r; break;
        end
    end
    assert(dRow > 0, 'writeSheetADmed: no row for session %s in %s', sessID, xlsxPath);
    chk = readcell(xlsxPath, 'Sheet', 'Sheet1', 'Range', sprintf('%s%d', colLetter(cSub), dRow));
    assert(strcmpi(strtrim(char(string(chk{1}))), sessID), ...
        'writeSheetADmed: coordinate check failed for %s (row %d)', sessID, dRow);

    for k = 1:2:numel(cols)
        c = findCol(hdr, cols{k});
        assert(c > 0, 'writeSheetADmed: column "%s" not in the header of %s', cols{k}, xlsxPath);
        val = cols{k + 1};
        if isstring(val), val = char(val); end
        if isnumeric(val) && ~isscalar(val), val = mat2str(val); end
        if isnumeric(val) && isnan(val), val = ''; end
        writecell({val}, xlsxPath, 'Sheet', 'Sheet1', 'Range', sprintf('%s%d', colLetter(c), dRow));
    end
    fprintf('writeSheetADmed: %s -> %d cell(s) in row %d\n', sessID, numel(cols) / 2, dRow);
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
end

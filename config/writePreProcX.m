function writePreProcX(P, sessID, xlsxPath)
%WRITEPREPROCX  Mark a session's "Data Preprocessed" cell with an X.
%
%   writePreProcX(P, sessID)            % default dataTracking.xlsx
%   writePreProcX(P, sessID, xlsxPath)  % explicit spreadsheet path
%
%   Finds the row matching sessID (Subject ID) and P.task, writes 'X' into
%   that row's "Data Preprocessed" column, and saves the workbook in place.
%   Subject IDs repeat across tasks in the sheet, so the task is needed to
%   pick the right row. Thin wrapper: the body is config/setPreProcX.m.

    if nargin < 3, xlsxPath = ''; end
    setPreProcX(P, sessID, 'X', xlsxPath);
end

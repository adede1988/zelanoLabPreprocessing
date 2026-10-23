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
%   existing writers. Thin wrapper: the body is config/setPreProcX.m.

    if nargin < 3, xlsxPath = ''; end
    setPreProcX(P, sessID, '', xlsxPath);
end

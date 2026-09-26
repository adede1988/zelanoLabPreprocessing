function figDir = guessFigDir(outDat, P)
%GUESSFIGDIR  SHARED: folder for the run-on-guess QC figures (paramCheck*).
%
%   figDir = guessFigDir(outDat, P)
%
%   P.figDir if set (every *PreProc_main sets it to the session's task
%   subfolder), else outDat.figs, else <labPaths().figPath>\guessQC\<sessID>
%   so the figures are never silently lost. The folder is created if needed.
%   Used by paramCheck and paramCheckECG (Tasks_260824.md D4 run-on-guess).

    if isfield(P, 'figDir') && ~isempty(P.figDir)
        figDir = P.figDir;
    elseif isfield(outDat, 'figs') && ~isempty(outDat.figs)
        figDir = outDat.figs;
    else
        L = labPaths();
        figDir = fullfile(L.figPath, 'guessQC', outDat.sessID);
    end
    if ~isfolder(figDir), mkdir(figDir); end
end

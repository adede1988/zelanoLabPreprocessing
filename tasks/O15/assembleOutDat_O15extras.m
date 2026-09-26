function outDat = assembleOutDat_O15extras(outDat, S, raw)
%ASSEMBLEOUTDAT_O15EXTRAS  TASK-SPECIFIC O15 outDat fields.
%   Adds the CSC list, the original-data directory, the session's LoadData
%   script (provenance via shared findLoadDataScript: raw.loadFile when the
%   raw file recorded it, else the folder's LoadData script - never fatal
%   when several exist) and the preproc-script name. O15 only.

    outDat.CSClist   = raw.ncslabels;
    outDat.OGdataDir = fullfile(S.root, S.id);
    outDat.loadFile  = findLoadDataScript(outDat.OGdataDir, 'O15', raw);
    outDat.preProcScript = 'O15PreProc_main.m';
end

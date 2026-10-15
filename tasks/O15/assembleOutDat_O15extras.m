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
    % held-button protocol only (detect_ttls_O15 with P.ttl.protocol =
    % 'heldButton', tasks_261014 task 10): the button-down periods (the free
    % events; heldButtonFreeSniffs_O15 reads them) and the event-channel parse
    if isfield(raw, 'buttonDown'), outDat.buttonDown = raw.buttonDown; end
    if isfield(raw, 'ttlInfo'),    outDat.ttlInfo    = raw.ttlInfo;    end
end

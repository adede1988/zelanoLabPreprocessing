function raw = assembleRaw_cueTask(S)
%ASSEMBLERAW_CUETASK  TASK-SPECIFIC raw load for cueTask.
%   Loads <id>_cueTaskPreProc.mat (shared loadIntermediateRaw) and passes through
%   its TTL table. Called by cueTaskPreProc_main.

    matPath = fullfile(S.root, S.id, 'preProc', [S.id '_cueTaskPreProc.mat']);
    [raw, od] = loadIntermediateRaw(matPath);
    if isfield(od, 'TTL'), raw.TTL = od.TTL; end
end

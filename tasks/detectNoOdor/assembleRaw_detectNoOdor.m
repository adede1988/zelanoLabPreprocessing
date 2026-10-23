function raw = assembleRaw_detectNoOdor(S)
%ASSEMBLERAW_DETECTNOODOR  TASK-SPECIFIC raw load for detectNoOdor.
%   Loads <id>_detectNoOdorPreProc.mat (shared loadIntermediateRaw) and passes
%   through its TTL table plus the task's parse / behavior provenance
%   (ttlInfo, behSource), which the main attaches to the final.
%   Called by detectNoOdorPreProc_main.

    matPath = fullfile(S.root, S.id, 'preProc', [S.id '_detectNoOdorPreProc.mat']);
    [raw, od] = loadIntermediateRaw(matPath);
    raw.TTL = od.TTL;
    raw.ttlInfo = od.ttlInfo;
    raw.behSource = od.behSource;
end

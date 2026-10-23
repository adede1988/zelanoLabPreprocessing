function raw = assembleRaw_threshTask(S)
%ASSEMBLERAW_THRESHTASK  TASK-SPECIFIC raw load for threshTask.
%   Loads <id>_PEA_threshold_preproc.mat (shared loadIntermediateRaw) and passes
%   through its TTL table, and - multi-run design only (2026-10-15,
%   loadBeh_multiRun_threshTask) - its threshDesign struct. Called by
%   threshPreProc_main.

    matPath = fullfile(S.root, S.id, 'preProc', [S.id '_PEA_threshold_preproc.mat']);
    [raw, od] = loadIntermediateRaw(matPath);
    if isfield(od, 'TTL'), raw.TTL = od.TTL; end
    if isfield(od, 'threshDesign'), raw.threshDesign = od.threshDesign; end
end

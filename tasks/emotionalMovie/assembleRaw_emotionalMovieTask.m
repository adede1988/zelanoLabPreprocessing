function raw = assembleRaw_emotionalMovieTask(S)
%ASSEMBLERAW_EMOTIONALMOVIETASK  TASK-SPECIFIC raw load for EmotionalMovieTask.
%   Loads <id>_EmotionalMovieTaskPreProc.mat (shared loadIntermediateRaw) and
%   passes through its clip TTL table (already in fs_target sample space).
%   Mirrors assembleRaw_cueTask.

    matPath = fullfile(S.root, S.id, 'preProc', [S.id '_EmotionalMovieTaskPreProc.mat']);
    [raw, od] = loadIntermediateRaw(matPath);
    if isfield(od, 'TTL'), raw.TTL = od.TTL; end
end

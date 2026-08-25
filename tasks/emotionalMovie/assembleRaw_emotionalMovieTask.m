function raw = assembleRaw_emotionalMovieTask(S)
%ASSEMBLERAW_EMOTIONALMOVIETASK  TASK-SPECIFIC raw load for EmotionalMovieTask.
%   Loads <id>_EmotionalMovieTaskPreProc.mat (shared loadIntermediateRaw) and
%   passes through its clip TTL table (already in fs_target sample space).
%   Mirrors assembleRaw_cueTask.

    matPath = fullfile(S.root, S.id, 'preProc', [S.id '_EmotionalMovieTaskPreProc.mat']);
    [raw, od] = loadIntermediateRaw(matPath);
    % an OLD-pipeline movie FINAL shares this filename (Windows case quirk);
    % it must never be re-ingested as raw input
    assert(~isfield(od, 'moreThan1'), ...
        'assembleRaw_emotionalMovieTask:isFinal', ...
        ['%s: the preProc file is a processed FINAL (has moreThan1), not a ' ...
         'makeOutDat intermediate. Back it up and delete it before rerunning.'], S.id);
    if isfield(od, 'TTL'), raw.TTL = od.TTL; end
end

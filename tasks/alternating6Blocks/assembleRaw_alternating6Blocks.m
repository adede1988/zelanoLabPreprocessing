function raw = assembleRaw_alternating6Blocks(S)
%ASSEMBLERAW_ALTERNATING6BLOCKS  TASK-SPECIFIC raw load for alternating6Blocks.
%   Loads <id>_alternating6BlocksPreProc.mat (shared loadIntermediateRaw) and
%   passes through the block table, breathing-style TTL vector, ratings table
%   (raw.beh via loadIntermediateRaw) and the log-alignment record.
%   The intermediate stores blocks/TTL in fs_target (500 Hz) sample space and
%   data at the raw rate; downstream indexing happens after downsample_data.

    matPath = fullfile(S.root, S.id, 'preProc', [S.id '_alternating6BlocksPreProc.mat']);
    [raw, od] = loadIntermediateRaw(matPath);
    raw.TTL      = od.TTL;
    raw.blocks   = od.blocks;
    raw.logAlign = od.logAlign;
end

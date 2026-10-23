function [blkMerged, info] = blocksOfMergedBreaths_pacedBreathing(breathMerge, blkEngine, nBlocks)
%BLOCKSOFMERGEDBREATHS_PACEDBREATHING  Block (condition) of each breath that survived the incomplete-exhale merge.
%
%   [blkMerged, info] = blocksOfMergedBreaths_pacedBreathing(breathMerge, blkEngine, nBlocks)
%
%   pacedBreathing infers its blocks from the ENGINE's breaths (inferBlocks_pacedBreathing on
%   segmentBreaths_zlp's bmObj, as before the 2026-10-22 merge rule; decision 2026-10-23: the merge
%   changes the per-breath table only, never the blocks, TTL or labels), and only then runs the
%   shared merge (applyBreathMerge). This function carries the engine breaths' block index over to the
%   merged table: a merged breath belongs to the block of its FIRST engine breath (the merge keeps the
%   first inhale's onset - keep-first - so the breath's onset sample, which behDat.finalOnset carries,
%   lies inside that block's [startSample, endSample] span).
%
%   breathMerge  outDat.breathMerge (mergeIncompleteExhales' record): nBefore, nAfter, origRows
%                (cell, per merged breath the engine rows it holds, in order)
%   blkEngine    blockInference.blkOfBreath: block index of every engine breath (nBefore x 1)
%   nBlocks      number of inferred blocks
%
%   blkMerged    [nAfter x 1] block index per merged breath = bmObj(:, 12) of the merged table
%   info         accounting for outDat.blockMergeInfo: nBreathsEngine / nBreathsMerged (per block),
%                nEngine, nMerged, nStraddling (merged breaths whose engine rows lie in more than one
%                block), nEmptyBlocks (blocks left without a breath; 0 expected), rule

    n0 = numel(blkEngine);
    if breathMerge.nBefore ~= n0
        error('blocksOfMergedBreaths_pacedBreathing:nBefore', ...
            'the merge record covers %d engine breaths, the block inference %d', breathMerge.nBefore, n0);
    end
    oR = breathMerge.origRows;
    if numel(oR) ~= breathMerge.nAfter
        error('blocksOfMergedBreaths_pacedBreathing:nAfter', ...
            'the merge record lists %d merged breaths, nAfter says %d', numel(oR), breathMerge.nAfter);
    end
    blkEngine = blkEngine(:);
    first = cellfun(@(r) r(1), oR(:));
    blkMerged = blkEngine(first);
    straddle = cellfun(@(r) numel(unique(blkEngine(r))) > 1, oR(:));
    info = struct();
    info.rule = ['blocks are inferred from the engine breaths (before applyBreathMerge); a merged breath belongs to the ' ...
        'block of its first engine breath (keep-first onset); outDat.blocks and TTL are the inference output, unchanged by the merge'];
    info.nBreathsEngine = accumarray(blkEngine, 1, [nBlocks 1])';
    info.nBreathsMerged = accumarray(blkMerged, 1, [nBlocks 1])';
    info.nEngine = n0;
    info.nMerged = numel(blkMerged);
    info.nStraddling = nnz(straddle);
    info.nEmptyBlocks = nnz(info.nBreathsMerged == 0);
    if info.nEmptyBlocks > 0
        warning('blocksOfMergedBreaths_pacedBreathing:emptyBlock', ...
            '%d block(s) have no breath left after the merge (blocks %s)', info.nEmptyBlocks, mat2str(find(info.nBreathsMerged == 0)));
    end
end

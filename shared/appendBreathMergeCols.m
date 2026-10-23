function outDat = appendBreathMergeCols(outDat, srcRows)
%APPENDBREATHMERGECOLS  SHARED: add the breath-merge columns to a per-breath outDat.behDat.
%
%   outDat = appendBreathMergeCols(outDat)
%   outDat = appendBreathMergeCols(outDat, srcRows)
%
%   Columns (appended at the end of behDat, before the bm_* block when called
%   before appendBmFeatureCols):
%     nInhalePulses      inhale pulses merged into this breath by
%                        mergeIncompleteExhales (1 = not merged)
%     breathInhaleArea   the whole breath's signal area above zero flow
%                        (sensor units x ms)
%     breathExhaleArea   ... below zero flow
%     exhaleInhaleRatio  breathExhaleArea / breathInhaleArea
%   For a merged breath (nInhalePulses > 1) the bm_* columns describe its
%   FIRST pulse only (mergeIncompleteExhales) - use the area columns for the
%   whole breath. When outDat has no breathMerge (a pipeline that did not run
%   the merge) the columns read 1 / NaN / NaN / NaN.
%
%   srcRows  the row of outDat.breathMerge (= the merged bmObj row, bmObj col
%            14 at the time of the merge) behind each behDat row. Omitted =
%            behDat row k <- merged breath k (builders that keep every
%            breath). Builders that keep a subset (EmotionalMovieTask,
%            alternating6Blocks) pass the indices of the kept breaths.
%            Used by every breath-type behavior-table builder.

    n = height(outDat.behDat);
    if nargin < 2 || isempty(srcRows), srcRows = (1:n)'; end
    srcRows = srcRows(:);
    assert(numel(srcRows) == n, 'appendBreathMergeCols: %d source rows for %d behDat rows', numel(srcRows), n);
    if isfield(outDat, 'breathMerge') && isstruct(outDat.breathMerge) && isfield(outDat.breathMerge, 'nPulses')
        M = outDat.breathMerge;
        assert(all(srcRows >= 1 & srcRows <= numel(M.nPulses)), ...
            'appendBreathMergeCols:rowRange', '%s: breath-merge rows out of range (%d merged breaths)', ...
            outDat.sessID, numel(M.nPulses));
        outDat.behDat.nInhalePulses    = M.nPulses(srcRows);
        outDat.behDat.breathInhaleArea = M.inhaleArea(srcRows);
        outDat.behDat.breathExhaleArea = M.exhaleArea(srcRows);
        outDat.behDat.exhaleInhaleRatio = M.exInRatio(srcRows);
    else
        outDat.behDat.nInhalePulses    = ones(n, 1);
        outDat.behDat.breathInhaleArea = nan(n, 1);
        outDat.behDat.breathExhaleArea = nan(n, 1);
        outDat.behDat.exhaleInhaleRatio = nan(n, 1);
    end
end

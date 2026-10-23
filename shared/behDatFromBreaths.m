function behDat = behDatFromBreaths(bmObj, nSamp, fs)
%BEHDATFROMBREATHS  SHARED: the 14 base per-breath columns of a breath-type behDat.
%
%   behDat = behDatFromBreaths(bmObj, nSamp, fs)
%
%   bmObj  [nBreaths x 14] breath matrix (CLAUDE.md 6.6; times in s)
%   nSamp  number of samples in outDat.data (size(outDat.data, 2))
%   fs     outDat.fs
%
%   Returns a table with, in this order:
%     sniffOnset, finalOnset  inhale-onset sample (bmObj col 2 -> samples)
%     manOnset                NaN placeholder for manual QC
%     condition               bmObj col 12
%     Yonset, inhaleMax       bmObj cols 1, 3
%     inMaxTim                bmObj col 4 -> samples
%     Yend                    bmObj col 5
%     endTim                  bmObj col 6 -> samples
%     length, amp             bmObj cols 7, 8
%     exhaleMin               bmObj col 10
%     exMinTim                bmObj col 11 -> samples
%     index                   bmObj col 14
%
%   Seconds -> samples is the first sample whose time (1:nSamp)/fs is >= the
%   breath time, exactly as every breath-table builder has always done it.
%   Shared by build_behavior_table_{breathingTask, emotionalMovieTask,
%   alternating6Blocks, pacedBreathing, breathingTasks_separate}; each adds
%   its task columns after these.

    tim = (1:nSamp) / fs;
    toSamp = @(t) arrayfun(@(x) find(x <= tim, 1), t);

    behDat = table();
    idx = toSamp(bmObj(:, 2));
    behDat.sniffOnset = idx;
    behDat.finalOnset = idx;
    behDat.manOnset   = nan(size(idx));
    behDat.condition  = bmObj(:, 12);
    behDat.Yonset     = bmObj(:, 1);
    behDat.inhaleMax  = bmObj(:, 3);
    behDat.inMaxTim   = toSamp(bmObj(:, 4));
    behDat.Yend       = bmObj(:, 5);
    behDat.endTim     = toSamp(bmObj(:, 6));
    behDat.length     = bmObj(:, 7);
    behDat.amp        = bmObj(:, 8);
    behDat.exhaleMin  = bmObj(:, 10);
    behDat.exMinTim   = toSamp(bmObj(:, 11));
    behDat.index      = bmObj(:, 14);
end

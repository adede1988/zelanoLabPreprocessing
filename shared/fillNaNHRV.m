function behDat = fillNaNHRV(behDat)
%FILLNANHRV  SHARED: the NaN stand-ins for the flagBadBreaths / HRV columns.
%
%   behDat = fillNaNHRV(behDat)
%
%   Sets goodBreath, maxRR, minRR and RR_max_min to NaN on every row, for a
%   breath-type session whose ECG stage was skipped or failed, so the
%   per-breath table keeps the same columns (downstream code finds them) and
%   no breath reads as a computed value. Used by runECGStage and by the
%   breathingTasks_separate main.

    n = height(behDat);
    behDat.goodBreath = nan(n, 1);
    behDat.maxRR      = nan(n, 1);
    behDat.minRR      = nan(n, 1);
    behDat.RR_max_min = nan(n, 1);
end

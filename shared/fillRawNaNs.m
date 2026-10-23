function [dat, nNan] = fillRawNaNs(dat, maxNaN)
%FILLRAWNANS  Fill the NaN samples ReadNCS puts at Neuralynx recording gaps.
%
%   [dat, nNan] = fillRawNaNs(dat, maxNaN)
%     dat     a raw_<task>.mat curDat (dat.rawData.trial{1} = channels x samples)
%     maxNaN  error when any channel holds more NaN samples than this
%             (the cue new-set branch uses 12000 = 6 s at 2 kHz)
%
%   Every channel is filled along time: linear interpolation inside, nearest
%   neighbour at the edges - the same treatment the cue new-set branch gives
%   its photodiode + data. Newer FieldTrip versions mark gaps as NaN, and a
%   single NaN makes a mean/std z-score of the photodiode all-NaN (no TTLs).
%   nNan = the largest per-channel NaN count found (0 = nothing changed).

    X = dat.rawData.trial{1};
    nNan = max(sum(isnan(X), 2));
    if nNan > maxNaN
        error('fillRawNaNs:tooMany', 'too many missing values (%d > %d samples on one channel)', nNan, maxNaN);
    end
    if nNan > 0
        X = fillmissing(X, 'linear', 2);
        X = fillmissing(X, 'nearest', 2);
        dat.rawData.trial{1} = X;
    end
end

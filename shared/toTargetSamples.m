function out = toTargetSamples(idx, fsRaw, fsTarget)
%TOTARGETSAMPLES  SHARED: convert raw-rate sample indices to the target rate.
%
%   out = toTargetSamples(idx, fsRaw, fsTarget)
%
%   out = round(idx ./ (fsRaw / fsTarget)), elementwise (NaN stays NaN).
%   Replaces the hard-coded round(x ./ 4) of the makeOutDat / assembleRaw
%   TTL code, which assumed fsRaw = 2000 and fsTarget = 500 - the result is
%   identical at those rates and correct at any other raw rate.

    out = round(idx ./ (fsRaw / fsTarget));
end

function [trialDowns, trialRun, info] = splitRuns_threshTask(downs, difVals, fs, nPerRun, sessID)
%SPLITRUNS_THRESHTASK  TASK-SPECIFIC: sniff TTLs of a multi-run PEA threshold
%   recording (several runs in ONE raw recording).
%
%   [trialDowns, trialRun, info] = splitRuns_threshTask(downs, difVals, fs, nPerRun, sessID)
%
%   Each run of threshold_task_new.m starts with a start code of 3 x 0.3-s DAQ
%   pulses (0.1 s apart) and then one 0.5-s pulse per trial at the SNIFF cue;
%   there is no end code. The legacy single-run parse
%   (threshPreProc_makeOutDat) keeps only the pulses after the LAST start code,
%   which with two runs in one recording would drop run 1. Here every start
%   code is found with the legacy train rule (3 pulses within 3500 samples =
%   1.75 s at the 2-kHz raw rate, scaled with fs), the pulses between start
%   codes are the trials of that run, and pulses before the first start code
%   are pre-start pulses (dropped, as legacy). Strict: the number of start
%   codes must equal numel(nPerRun) and each run must hold exactly nPerRun(r)
%   trial pulses (the run's behaviour rows), else error.
%
%   downs   : pulse onsets (raw samples) after the legacy width filter
%   difVals : pulse widths (raw samples), parallel to downs
%   fs      : raw sample rate (Hz)
%   nPerRun : trials per run from the behaviour files (e.g. [40 40])
%
%   trialDowns : trial pulse onsets (raw samples), recording order
%   trialRun   : run index of each trial pulse
%   info       : struct (start-code onsets / ends, widths, pre-start count)

    downs = downs(:); difVals = difVals(:);
    n = numel(downs);
    trainGap = round(1.75 * fs);          % = the legacy 3500 samples at 2 kHz
    inTrain = false(n, 1);
    for di = 3:n
        if downs(di) - downs(di-2) < trainGap
            inTrain(di-2:di) = true;
        end
    end
    % contiguous groups of train pulses = start codes
    d = diff([false; inTrain; false]);
    trStart = find(d == 1);
    trEnd   = find(d == -1) - 1;
    nRuns = numel(nPerRun);
    if numel(trStart) ~= nRuns
        error('PEA loader: %s has %d start codes (pulse trains) in the recording, expected %d runs.', ...
            sessID, numel(trStart), nRuns);
    end

    isTrial = ~inTrain;
    preStart = isTrial & ((1:n)' < trStart(1));
    isTrial(preStart) = false;
    runOf = zeros(n, 1);
    for r = 1:nRuns
        runOf((1:n)' > trEnd(r)) = r;
    end
    trialDowns = downs(isTrial);
    trialRun   = runOf(isTrial);

    for r = 1:nRuns
        k = sum(trialRun == r);
        if k ~= nPerRun(r)
            error('PEA loader: %s run %d has %d sniff TTLs, its behaviour file has %d trials.', ...
                sessID, r, k, nPerRun(r));
        end
    end

    info = struct;
    info.trainGapSamples  = trainGap;
    info.startCodeOnset   = downs(trStart);            % raw samples, first pulse of each start code
    info.startCodeEnd     = downs(trEnd);              % raw samples, last pulse of each start code
    info.startCodeNPulses = trEnd - trStart + 1;
    info.nPreStartDropped = sum(preStart);
    info.medWidthStartSec = median(difVals(inTrain)) / fs;
    info.medWidthTrialSec = median(difVals(isTrial)) / fs;
    info.trialsPerRun     = arrayfun(@(r) sum(trialRun == r), 1:nRuns);
end

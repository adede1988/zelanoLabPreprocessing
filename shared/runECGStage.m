function [outDat, P] = runECGStage(outDat, P, isGuess, id)
%RUNECGSTAGE  SHARED ECG / HRV stage with NaN-HRV fallback (breath-type tasks).
%
%   [outDat, P] = runECGStage(outDat, P, isGuess, id)
%
%   outDat   after the per-breath behDat is built
%   P        applyParams struct (P.getBeats / P.beatSpec)
%   isGuess  true for a guess-param session (runs paramCheckECG first)
%   id       session ID, for messages
%
%   When outDat has ECG channels (label contains 'ECG'):
%     1. viability probe: buildECGz + P.getBeats; below 20 beats/min there is
%        no usable cardiac signal and the stage fails (NaN HRV, not garbage
%        RRint)
%     2. paramCheckECG (guess sessions only; may update P.beatSpec/getBeats,
%        which is why P is returned)
%     3. processECG (appends RRint, outDat.heartBeats) + flagBadBreaths
%   Any error in 1-3 is caught: a warning asks for review and the HRV
%   columns are set to NaN (fillNaNHRV) rather than losing the breath data.
%
%   outDat.ecgSkipped records the outcome:
%     0 = ECG processed
%     1 = no ECG channel in the recording
%     2 = ECG channels present but detection / processing failed
%
%   Used by the EmotionalMovieTask, alternating6Blocks and pacedBreathing
%   mains. breathingTask deliberately keeps its strict path (a failure there
%   must stop the session - CLAUDE.md section 7); breathingTasks_separate
%   probes ECG once per session across its sections and only uses fillNaNHRV.
%
%   Edge case (behaviour change when this helper replaced the inline code):
%   the alternating6Blocks and pacedBreathing mains had no ECG-channel check,
%   so a recording WITHOUT ECG channels reached the try block, failed there
%   and was recorded as ecgSkipped = 2. It is now recorded as ecgSkipped = 1
%   (the EmotionalMovieTask semantics). The EEG_breathing recordings of those
%   two tasks all carry ECG1-3 (per their main headers), so existing finals
%   are not expected to be affected; HRV is NaN either way.

    hasECG = sum(cellfun(@(x) contains(x, 'ECG'), outDat.labels)) > 0;
    ecgDone = false;
    if hasECG
        try
            [ECGzP, sepP] = buildECGz(outDat);
            bpmP = numel(P.getBeats(ECGzP, sepP)) / (size(outDat.data, 2) / outDat.fs / 60);
            clear ECGzP
            assert(bpmP >= 20, '%s: beat detection implausible (%.1f bpm)', id, bpmP);
            if isGuess, P = paramCheckECG(outDat, P); end
            outDat = processECG(outDat, P);
            outDat = flagBadBreaths(outDat);
            outDat.ecgSkipped = 0;
            ecgDone = true;
        catch MEecg
            warning('%s: ECG processing failed (%s) - HRV set to NaN, REVIEW', ...
                id, MEecg.message);
            outDat.ecgSkipped = 2;   % 2 = present but detection failed
        end
    else
        disp(['NO ECG channels for ' id ' - HRV columns set to NaN'])
        outDat.ecgSkipped = 1;
    end
    if ~ecgDone
        outDat.behDat = fillNaNHRV(outDat.behDat);
    end
end

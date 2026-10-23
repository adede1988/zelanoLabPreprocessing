function outDat = refine_onsets_with_phase(outDat, R, P)
% REFINE_ONSETS_WITH_PHASE
% outDat = refine_onsets_with_phase(outDat, R, P)
% Uses precomputed respiration phase to refine sniff onsets.
%
% Inputs
%   outDat.behDat.sniffOnset : sample indices (downsampled Fs) of coarse onsets
%   R.rspDat    : 1xT respiration (already chosen channel & flipped)
%   R.smoothR   : 1xT smoothed respiration (same Fs as outDat.fs)
%   R.rspPhase  : 1xT phase = angle(R.analytic)
%   P.adjWin    : window length (samples) for onset backtrack
%
% Outputs
%   outDat.behDat.adjust     : signed offset (samples) relative to sniffOnset
%   outDat.behDat.finalOnset : refined onset (sample index)

    fs = outDat.fs;
    preSamp  = round(2*fs);  % -2 s
    postSamp = round(4*fs);  % +4 s

    nSniffs = size(outDat.behDat, 1);
    if ~isfield(outDat.behDat, 'adjust')
        outDat.behDat.adjust = zeros(nSniffs,1);
    end
    if ~isfield(outDat.behDat, 'finalOnset')
        outDat.behDat.finalOnset = zeros(nSniffs,1);
    end

    % Train mode (opt-in, P.sniffTrain; cueTask3 2026-10-16): each sniff of a
    % rapid train (detect_sniffs_from_TTLs train mode) gets the same
    % steepest-rise rule as below, but between its own inhale trough and peak
    % (behDat.inhaleTrough / inhalePeak, at most P.adjWin samples back from the
    % peak) instead of in the adjWin before the respiration-phase peak: that
    % 1-Hz phase follows the whole train, not the single sniffs, and its window
    % reaches back into the previous sniff's rise. Absent / empty P.sniffTrain
    % = the legacy rule, unchanged.
    trainMode = isfield(P, 'sniffTrain') && ~isempty(P.sniffTrain);
    if trainMode && ~all(ismember({'inhaleTrough', 'inhalePeak'}, outDat.behDat.Properties.VariableNames))
        error('refine_onsets_with_phase:noInhaleBounds', ...
            'P.sniffTrain is set but behDat has no inhaleTrough / inhalePeak columns.');
    end

    T = numel(R.rspPhase);
    for sniffi = 1:nSniffs
        s0 = outDat.behDat.sniffOnset(sniffi);
        if ~isfinite(s0) || s0<=0, continue; end

        if trainMode
            lo = outDat.behDat.inhaleTrough(sniffi);
            hi = outDat.behDat.inhalePeak(sniffi);
            a  = max(hi - P.adjWin, lo);
            if hi - a < 21          % too short for the 20-sample rise test
                outDat.behDat.adjust(sniffi)     = 0;
                outDat.behDat.finalOnset(sniffi) = s0;
                continue;
            end
            seg = R.smoothR(a:hi);
            difVals = seg(1:end-20) - seg(21:end);   % 20-sample drop (negative = rise)
            [~, minidx] = min(difVals);
            onset = a - 20 + minidx;                 % same offset as the legacy rule below
            outDat.behDat.adjust(sniffi)     = onset - s0;
            outDat.behDat.finalOnset(sniffi) = max(1, min(T, onset));
            continue;
        end

        % segment around the sniff (clip to bounds)
        segStart = max(1, s0 - preSamp);
        segEnd   = min(T, s0 + postSamp);
        if segEnd - segStart < max(100, P.adjWin+50), continue; end

        phaseSeg  = R.rspPhase(segStart:segEnd);
        smoothSeg = R.smoothR(segStart:segEnd);

        % index (within the segment) corresponding to time 0 (sniff onset)
        preEff = s0 - segStart;           % samples before 0 inside segment
        % upward zero-crossings of phase
        zc = find(phaseSeg(1:end-1) < 0 & phaseSeg(2:end) >= 0) + 1;

        % prefer first crossing AFTER t=0; fallback to first crossing at all
        zc = zc(zc > preEff);
        if isempty(zc)
            % if none after t=0, try any crossing
            zc = find(phaseSeg(1:end-1) < 0 & phaseSeg(2:end) >= 0) + 1;
            if isempty(zc)
                % give up gracefully
                outDat.behDat.adjust(sniffi)     = 0;
                outDat.behDat.finalOnset(sniffi) = s0;
                continue;
            end
        end
        peakIdx = zc(1) - 10;                  % small bias earlier (as in script)
        peakIdx = max(1, min(peakIdx, numel(smoothSeg)));

        % ensure we have enough room to look back
        if peakIdx < 21
            outDat.behDat.adjust(sniffi)     = 0;
            outDat.behDat.finalOnset(sniffi) = s0;
            continue;
        end
        adjWinEff = min(P.adjWin, peakIdx - 1);  % keep windows in-bounds

        % two adjacent windows ending at (peakIdx) with a 20-sample gap
        left  = smoothSeg(peakIdx - adjWinEff : peakIdx - 20);
        right = smoothSeg(peakIdx - (adjWinEff - 20) : peakIdx);
        % (vectors are same length: adjWinEff-20+1)
        difVals = left - right;

        [~, minidx] = min(difVals);

        % refined onset index within the segment
        onsetSeg = (peakIdx - (adjWinEff + 20)) + minidx;

        % convert to offset relative to sniffOnset (can be negative)
        delta = onsetSeg - preEff;

        % store
        outDat.behDat.adjust(sniffi)     = delta;
        outDat.behDat.finalOnset(sniffi) = max(1, min(T, s0 + delta));
    end

    % Manual-onset placeholder column: NaN here, filled in by hand during later QC.
    outDat.behDat.manOnset = nan(nSniffs, 1);
end

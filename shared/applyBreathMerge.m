function outDat = applyBreathMerge(outDat, rspDat, P)
%APPLYBREATHMERGE  SHARED stage: the incomplete-exhale breath merge, after the locked engine.
%
%   outDat = applyBreathMerge(outDat, rspDat, P)
%
%   Runs shared/mergeIncompleteExhales on outDat.bmObj / outDat.bmFeatures (as
%   segmentBreaths_zlp, and the task's own merges, left them) and stores the
%   record in outDat.breathMerge. User's rule (2026-10-22, every breath-type
%   pipeline): "an inhale joins the previous breath when the exhale since that
%   inhale is under 20 % of it. Volume is the area of the nasal-pressure trace
%   above and below zero flow." The rule itself, its steps and the meaning of
%   outDat.breathMerge are documented in mergeIncompleteExhales.
%
%   outDat   after segmentBreaths_zlp (and, for breathingTask, after the
%            cyclicSigh refractory merge: the design-driven, block-specific
%            merge first, the generic rule on its result)
%   rspDat   the respiration trace the engine segmented: the chosen rsp row
%            x rspFlip at outDat.fs (the caller already built it)
%   P        applyParams struct. Optional fields: P.mergeExhaleFrac (the 20 %,
%            default 0.20), P.sweepOpts.mergeExhaleFrac (respiratorySweep's
%            own copy of the same number; wins over the default), P.mergeOpts
%            (opts struct of mergeIncompleteExhales; default none)
%
%   Call it ONCE per segmentation, before anything numbers or filters the
%   breaths (condition column, block/clip selection, behavior table). The
%   behavior-table builders add nInhalePulses / breathInhaleArea /
%   breathExhaleArea / exhaleInhaleRatio from outDat.breathMerge
%   (appendBreathMergeCols). An empty bmObj passes through unchanged.

    exFrac = 0.20;
    if isstruct(P)
        if isfield(P, 'sweepOpts') && isstruct(P.sweepOpts) && isfield(P.sweepOpts, 'mergeExhaleFrac') ...
                && ~isempty(P.sweepOpts.mergeExhaleFrac)
            exFrac = P.sweepOpts.mergeExhaleFrac;
        end
        if isfield(P, 'mergeExhaleFrac') && ~isempty(P.mergeExhaleFrac), exFrac = P.mergeExhaleFrac; end
    end
    opts = struct();
    if isstruct(P) && isfield(P, 'mergeOpts') && isstruct(P.mergeOpts), opts = P.mergeOpts; end

    if size(outDat.bmObj, 1) == 0
        warning('applyBreathMerge:noBreaths', '%s: no breaths to merge', outDat.sessID);
        return
    end
    [outDat.bmObj, outDat.bmFeatures, outDat.breathMerge] = mergeIncompleteExhales(outDat.bmObj, ...
        outDat.bmFeatures, rspDat, outDat.fs, exFrac, opts);
    fprintf('%s: breath merge %d -> %d breaths (%d pause blips + %d inhales joined the breath before)\n', ...
        outDat.sessID, outDat.breathMerge.nBefore, outDat.breathMerge.nAfter, outDat.breathMerge.nMinor, ...
        outDat.breathMerge.nMerged);
end

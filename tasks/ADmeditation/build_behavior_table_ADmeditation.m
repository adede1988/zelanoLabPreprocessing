function outDat = build_behavior_table_ADmeditation(outDat)
%BUILD_BEHAVIOR_TABLE_ADMEDITATION  Per-breath behDat for ADmeditation.
%
%   Breathing-layout columns from bmObj (one row per detected breath over the
%   whole trimmed recording; shared behDatFromBreaths), condition = 1 (one
%   continuous meditation, bmObj col 12), task = 'meditation';
%   noseMouth/shadowFile/warp kept as NA/NaN for downstream compatibility; no
%   rating columns / baseEmotion (no behavioral file). bm_* feature columns
%   appended as in the other breath-based tasks.
%
%   Task columns
%     rateBPM          60 / length
%     localPeriodCV    CV of breath length over the +/-3 surrounding breaths
%     localAmpCV       CV of amplitude over the same window
%     nSubPeaks        local maxima (prominence >= 15% of the breath amplitude,
%                      100-ms smoothed trace) between this inhale onset and the
%                      next - 1 = a clean single-peaked breath (as pacedBreathing)
%     pressInBreath    number of button presses (outDat.buttonPresses, in the
%                      analysis window) whose onset falls in [this inhale onset,
%                      next inhale onset)
%     secSincePress    time from the most recent press onset to this inhale
%                      onset (s; NaN before the first press)
%     secToPress       time from this inhale onset to the next press onset
%                      (s; NaN after the last press)
%     nearSeam         breath within 5 s of a recording seam (multi-file
%                      acquisitions; outDat.segments) - exclude in analyses

    bmObj = outDat.bmObj;
    n = size(bmObj, 1);
    fs = outDat.fs;

    behDat = behDatFromBreaths(bmObj, size(outDat.data, 2), fs);   % shared 14 base columns
    idx = behDat.sniffOnset;
    behDat.task       = repmat({'meditation'}, n, 1);
    behDat.noseMouth  = repmat("NA", n, 1);
    behDat.shadowFile = repmat("NA", n, 1);
    behDat.warp       = nan(n, 1);

    % ---- rate + local regularity + sub-peak count (as pacedBreathing) ----
    behDat.rateBPM = 60 ./ behDat.length;
    per = behDat.length; amp = behDat.amp;
    behDat.localPeriodCV = nan(n, 1);
    behDat.localAmpCV    = nan(n, 1);
    for b = 1:n
        w = max(1, b - 3):min(n, b + 3);
        if numel(w) >= 4
            behDat.localPeriodCV(b) = std(per(w)) / mean(per(w));
            behDat.localAmpCV(b)    = std(amp(w)) / mean(amp(w));
        end
    end
    isRsp = cellfun(@(x) contains(x, 'rsp'), outDat.labels);
    rsp = outDat.data(isRsp, :);
    rsp = rsp(outDat.rspIDX, :) .* outDat.rspFlip;
    rspS = smoothdata(rsp, 'gaussian', round(0.1 * fs));
    behDat.nSubPeaks = nan(n, 1);
    for b = 1:n
        s0 = idx(b);
        if b < n, s1 = idx(b + 1) - 1; else, s1 = min(numel(rspS), s0 + round(behDat.length(b) * fs)); end
        if s1 - s0 < round(0.3 * fs) || ~isfinite(amp(b)) || amp(b) <= 0, continue; end
        [~, pk] = findpeaks(rspS(s0:s1), 'MinPeakProminence', 0.15 * amp(b), ...
                            'MinPeakDistance', max(1, round(0.15 * fs)));
        behDat.nSubPeaks(b) = numel(pk);
    end

    % ---- button presses relative to each breath ----
    pr = outDat.buttonPresses;
    pS = sort(pr.sample(pr.inAnalysisWindow & isfinite(pr.sample)));
    nextOn = [idx(2:end); size(outDat.data, 2) + 1];
    behDat.pressInBreath = zeros(n, 1);
    behDat.secSincePress = nan(n, 1);
    behDat.secToPress    = nan(n, 1);
    for b = 1:n
        behDat.pressInBreath(b) = sum(pS >= idx(b) & pS < nextOn(b));
        prev = pS(pS <= idx(b));
        if ~isempty(prev), behDat.secSincePress(b) = (idx(b) - prev(end)) / fs; end
        nxt = pS(pS > idx(b));
        if ~isempty(nxt), behDat.secToPress(b) = (nxt(1) - idx(b)) / fs; end
    end

    % ---- breaths at a recording seam (as pacedBreathing) ----
    behDat.nearSeam = false(n, 1);
    if isfield(outDat, 'segments') && istable(outDat.segments) && height(outDat.segments) > 1
        seamPad = round(5 * fs);
        seams = outDat.segments.startSample(2:end);
        bEnd = idx + round(behDat.length * fs);
        for k = 1:numel(seams)
            behDat.nearSeam = behDat.nearSeam | (idx - seamPad <= seams(k) & bEnd + seamPad >= seams(k));
        end
    end

    outDat.behDat = behDat;
    outDat = appendBmFeatureCols(outDat, 'build_behavior_table_ADmeditation');   % bm_* (D8e)
end

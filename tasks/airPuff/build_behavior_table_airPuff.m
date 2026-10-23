function outDat = build_behavior_table_airPuff(outDat, quietAtPuff, opts)
%BUILD_BEHAVIOR_TABLE_AIRPUFF  Per-puff behDat for airPuff (+ RR columns of outDat.holds).
%
%   outDat = build_behavior_table_airPuff(outDat, quietAtPuff, opts)
%
%   Needs outDat.pulses (puff rows with .sample at outDat.fs), outDat.holds
%   (detectHolds_airPuff), outDat.bmObj, and - when outDat.ecgSkipped == 0 - the
%   RRint channel (processECG via runECGStage). quietAtPuff: detectHolds_airPuff's
%   per-puff flag. opts = P.puffOpts.measure, fields (defaults):
%     preSec 1, postSec 1   respiration windows [-preSec, 0) / [0, postSec) s around the puff
%     lpHz 2                low-pass of the trace used for the slope / SD measures
%     rrPreSec 2, rrPostSec 2   RRint windows around the puff
%     rrHoldCtxSec 10       RRint windows before the hold onset / after its offset
%
%   behDat (one row per puff, in time order):
%     puff            puff index (1..nPuffs)
%     onset           puff onset sample at outDat.fs (= the DAQ pulse's half-height
%                     falling crossing; = outDat.TTL)
%     finalOnset      = onset: the column every task epochs on
%     manOnset        NaN placeholder for manual QC
%     tSec            (onset - 1) / fs
%     run, condition, cued   1 'cued' (before the separator; "Puff" auditory cue) /
%                     2 'blind' (after it; no cue, the participant blind to the timing)
%     hold, holdInRun, puffNum   global hold index, hold index within its run,
%                     puff index within its hold
%     quietAtPuff     the respiration was flat (breath held) at the puff (detectHolds_airPuff)
%     tSinceHoldOnset, tToHoldOffset   s from the hold onset / to the hold offset
%                     (respiration-defined; NaN when the hold was not detected)
%     tToNextInhale   s to the next inhale onset (segmentBreaths_zlp)
%     windowsInHold   both respiration windows lie inside the respiration-defined hold
%                     (false: a window reaches into the breathing before / after it -
%                     e.g. a puff 0.6 s after the hold onset or before the recovery inhale)
%     rspPre, rspPost mean respiration (rspIDX / rspFlip applied, inhale up; the
%                     nasal-pressure cannula reads ~airflow) in the pre / post windows
%     rspChange       rspPost - rspPre
%     slopePre, slopePost   linear-fit slope (uV/s) of the <lpHz trace in the windows
%                     (its derivative: + = toward inhale)
%     sdPre, sdPost   SD of the <lpHz trace in the windows (respiratory activity; the
%                     hold detector calls < ~12 uV "quiet")
%     rrPre, rrPost   mean RRint (s) in [-rrPreSec, 0) / [0, rrPostSec) s; NaN without ECG
%   Windows reaching past the recording edges give NaN. Puffs are >= 1.6 s apart,
%   so a puff's post window can overlap the next puff's pre window by <= 0.4 s.
%
%   outDat.holds gains rrPre (mean RRint over the rrHoldCtxSec before the hold
%   onset), rrHold (over the hold), rrRecovery (over the rrHoldCtxSec after the
%   offset) - NaN without ECG or without a detected hold.

    if nargin < 3 || isempty(opts), opts = struct; end
    d = struct('preSec', 1, 'postSec', 1, 'lpHz', 2, 'rrPreSec', 2, 'rrPostSec', 2, 'rrHoldCtxSec', 10);
    fn = fieldnames(d);
    for i = 1:numel(fn)
        if ~isfield(opts, fn{i}), opts.(fn{i}) = d.(fn{i}); end
    end

    fs = outDat.fs;
    N = size(outDat.data, 2);
    pp = outDat.pulses(outDat.pulses.role == "puff", :);
    sp = pp.sample(:);
    n = numel(sp);

    isRsp = cellfun(@(x) contains(x, 'rsp'), outDat.labels);
    rsp = outDat.data(isRsp, :);
    rsp = rsp(outDat.rspIDX, :) .* outDat.rspFlip;
    [b, a] = butter(2, opts.lpHz / (fs / 2), 'low');
    rl = filtfilt(b, a, rsp);
    rr = [];
    if isfield(outDat, 'ecgSkipped') && outDat.ecgSkipped == 0
        isRR = cellfun(@(x) contains(x, 'RRint'), outDat.labels);
        assert(sum(isRR) == 1, 'build_behavior_table_airPuff: expected one RRint row');
        rr = outDat.data(isRR, :);
    end

    H = outDat.holds;
    [~, hi] = ismember(pp.hold, H.hold);
    onsS = round(outDat.bmObj(:, 2) * fs);
    allOns = unique([onsS; round(outDat.bmObj(end, 6) * fs)]);

    behDat = table;
    behDat.puff       = pp.puff;
    behDat.onset      = sp;
    behDat.finalOnset = sp;
    behDat.manOnset   = nan(n, 1);
    behDat.tSec       = (sp - 1) / fs;
    behDat.run        = pp.run;
    behDat.condition  = pp.condition;
    behDat.cued       = pp.run == 1;
    behDat.hold       = pp.hold;
    behDat.holdInRun  = pp.holdInRun;
    behDat.puffNum    = pp.puffNum;
    behDat.quietAtPuff = logical(quietAtPuff(:));
    behDat.tSinceHoldOnset = (sp - H.onset(hi)) / fs;
    behDat.tToHoldOffset   = (H.offset(hi) - sp) / fs;
    behDat.tToNextInhale   = nan(n, 1);
    behDat.windowsInHold   = false(n, 1);
    cols = {'rspPre', 'rspPost', 'rspChange', 'slopePre', 'slopePost', 'sdPre', 'sdPost', 'rrPre', 'rrPost'};
    for c = 1:numel(cols), behDat.(cols{c}) = nan(n, 1); end

    preN = round(opts.preSec * fs); postN = round(opts.postSec * fs);
    rrPreN = round(opts.rrPreSec * fs); rrPostN = round(opts.rrPostSec * fs);
    for k = 1:n
        s = sp(k);
        ni = allOns(find(allOns > s, 1));
        if ~isempty(ni), behDat.tToNextInhale(k) = (ni - s) / fs; end
        behDat.windowsInHold(k) = ~isnan(H.onset(hi(k))) && s - preN >= H.onset(hi(k)) && ...
            s + postN - 1 <= H.offset(hi(k));
        if s - preN >= 1 && s + postN - 1 <= N
            wPre = s - preN:s - 1; wPost = s:s + postN - 1;
            behDat.rspPre(k)  = mean(rsp(wPre));
            behDat.rspPost(k) = mean(rsp(wPost));
            behDat.rspChange(k) = behDat.rspPost(k) - behDat.rspPre(k);
            behDat.slopePre(k)  = slopeOf(rl(wPre), fs);
            behDat.slopePost(k) = slopeOf(rl(wPost), fs);
            behDat.sdPre(k)  = std(rl(wPre));
            behDat.sdPost(k) = std(rl(wPost));
        end
        if ~isempty(rr) && s - rrPreN >= 1 && s + rrPostN - 1 <= N
            behDat.rrPre(k)  = mean(rr(s - rrPreN:s - 1), 'omitnan');
            behDat.rrPost(k) = mean(rr(s:s + rrPostN - 1), 'omitnan');
        end
    end
    outDat.behDat = behDat;

    % ---- RR around / during each hold ----
    ctxN = round(opts.rrHoldCtxSec * fs);
    H.rrPre = nan(height(H), 1); H.rrHold = nan(height(H), 1); H.rrRecovery = nan(height(H), 1);
    if ~isempty(rr)
        for k = 1:height(H)
            if isnan(H.onset(k)), continue; end
            o = H.onset(k); f = H.offset(k);
            if o - ctxN >= 1, H.rrPre(k) = mean(rr(o - ctxN:o - 1), 'omitnan'); end
            H.rrHold(k) = mean(rr(o:f), 'omitnan');
            if f + ctxN <= N, H.rrRecovery(k) = mean(rr(f + 1:f + ctxN), 'omitnan'); end
        end
    end
    outDat.holds = H;
end

function m = slopeOf(y, fs)
% least-squares slope of y (per second)
    t = (0:numel(y) - 1)' / fs;
    y = y(:);
    t = t - mean(t);
    m = sum(t .* (y - mean(y))) / sum(t .^ 2);
end

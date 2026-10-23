function [ev, pulses, info] = parse_detectNoOdor_events(pd, fs, opts)
%PARSE_DETECTNOODOR_EVENTS  Parse the detectNoOdor event channel into trials (strict).
%
%   [ev, pulses, info] = parse_detectNoOdor_events(pd, fs, opts)
%
%   pd   : the raw event channel (1 x nSamp, NaNs already filled), fs : its rate.
%   opts : optional struct, fields (defaults):
%     threshFrac    0.5    pulse-on threshold = median + threshFrac*(low - median),
%                          low = the 0.5th percentile (the negative rail when clipped)
%     mergeGapSec   0.005  re-join a pulse split by a gap shorter than this
%     minPulseSec   0.02   drop blips shorter than this
%     shortSec      0.307  pulse_dur 0.3 s (start / end code, button response)
%     sniffSec      0.505  pulse_dur_sniff 0.5 s (the SNIFF cue)
%     widthTolSec   0.03   |width - shortSec/sniffSec| tolerance
%     codeGapSec    0.415  onset-to-onset spacing inside the start / end code
%                          (pulse 0.3 s + inter_pulse_dur 0.1 s)
%     codeTolSec    0.05
%     nStartCode    4      start code = this many short pulses at codeGapSec
%     nEndCode      2      end code = this many short pulses at codeGapSec
%     respLatSec    [2.4 16]  sniff cue -> button pulse: the Yes/No screen opens
%                          2.5 s after the cue (0.5-s pulse + 2-s wait) and the
%                          response loop runs 13 s
%
%   Protocol (OBE_task_backup\tasks\odor_detection\src\Main_detectiontask_f.m,
%   the "fake" detection task: the olfactometer opens the air line only, never
%   an odor). DAQ pulses are low-going on the AC-coupled, rail-clipped event
%   input (CSC269), like O15 (parse_O15_events: median / rail-referenced levels,
%   no z-score):
%     start code   4 x 0.3 s, 0.1 s apart
%     per trial    countdown 3-2-1 (no pulse), SNIFF cue = one 0.5-s pulse,
%                  2 s later the Yes/No screen; the key press sends one 0.3-s
%                  pulse (none when the participant does not answer within 13 s)
%     end code     2 x 0.3 s, 0.1 s apart
%   Anything before the start code is preamble (recorded, not used; e.g. in
%   261008_INR_NWU_SS_1 a 10.5-s low level at file start and three 0.26-s pulses
%   at 15.5 s). Between the start and the end code only sniff and response
%   pulses are allowed (strict: anything else errors).
%
%   Outputs (raw-sample indices at fs; onset = last sample above the threshold,
%   the lab's 'downs' convention):
%     ev.sniff     [nTrial x 1]  SNIFF-cue pulse onsets
%     ev.response  [nTrial x 1]  button-response pulse onsets (NaN = no answer)
%     ev.startCode [1 x nStartCode], ev.endCode [1 x nEndCode] onsets
%     pulses : table of every pulse (onset, offset, durSec, tSec, role, trial),
%              role in {preamble, startCode, sniff, response, endCode}
%     info   : levels, threshold, counts, preamble summary

    if nargin < 3, opts = struct; end
    d = struct('threshFrac', 0.5, 'mergeGapSec', 0.005, 'minPulseSec', 0.02, ...
        'shortSec', 0.307, 'sniffSec', 0.505, 'widthTolSec', 0.03, ...
        'codeGapSec', 0.415, 'codeTolSec', 0.05, 'nStartCode', 4, 'nEndCode', 2, ...
        'respLatSec', [2.4 16]);
    fn = fieldnames(d);
    for i = 1:numel(fn)
        if ~isfield(opts, fn{i}), opts.(fn{i}) = d.(fn{i}); end
    end

    pd = double(pd(:))';
    if any(isnan(pd)), error('parse_detectNoOdor_events:NaN', 'fill NaNs before parsing'); end

    % ---- levels and threshold (no z-score) ----
    info = struct;
    info.opts = opts;
    info.min = min(pd); info.max = max(pd);
    info.median = median(pd);
    info.low = prctile(pd, 0.5);
    info.thresh = info.median + opts.threshFrac * (info.low - info.median);
    rng = info.max - info.min;
    if info.median - info.low < 0.25 * rng
        error('parse_detectNoOdor_events:noPulses', ...
            'no negative-going pulses (median %.1f, 0.5th pct %.1f, range %.1f)', ...
            info.median, info.low, rng);
    end

    % ---- pulses = runs below the threshold ----
    on = pd < info.thresh;
    dd = diff([false on false]);
    s = find(dd == 1); f = find(dd == -1) - 1;
    gapMin = round(opts.mergeGapSec * fs);
    k = 1;
    while k < numel(s)
        if s(k+1) - f(k) - 1 < gapMin
            f(k) = f(k+1); s(k+1) = []; f(k+1) = [];
        else
            k = k + 1;
        end
    end
    w = f - s + 1;
    keep = w >= round(opts.minPulseSec * fs);
    info.nBlips = sum(~keep);
    s = s(keep); f = f(keep);
    s = s - 1; s(s < 1) = 1;          % 'downs' convention (last sample above)
    n = numel(s);

    pulses = table;
    pulses.onset  = s(:);
    pulses.offset = f(:);
    pulses.durSec = (f(:) - s(:)) / fs;
    pulses.tSec   = (s(:) - 1) / fs;
    pulses.role   = repmat("unassigned", n, 1);
    pulses.trial  = nan(n, 1);

    isS = abs(pulses.durSec - opts.shortSec) < opts.widthTolSec;
    isM = abs(pulses.durSec - opts.sniffSec) < opts.widthTolSec;
    gapOK = @(i) abs((pulses.onset(i+1) - pulses.onset(i)) / fs - opts.codeGapSec) < opts.codeTolSec;

    % ---- start code: the first run of nStartCode short pulses at codeGapSec ----
    nS = opts.nStartCode;
    isCode = false(n, 1);
    for i = 1:n - nS + 1
        ok = all(isS(i:i+nS-1));
        for j = i:i+nS-2
            ok = ok && gapOK(j);
        end
        isCode(i) = ok;
    end
    i0 = find(isCode, 1);
    if isempty(i0)
        error('parse_detectNoOdor_events:noStartCode', ...
            'no start code (%d x %.2f-s pulses %.2f s apart) found', nS, opts.shortSec, opts.codeGapSec);
    end
    if any(isCode(i0+nS:end))
        error('parse_detectNoOdor_events:twoStartCodes', ...
            'a second start code at %.2f s (two runs in one recording?)', ...
            pulses.tSec(find(isCode(i0+nS:end), 1) + i0 + nS - 1));
    end
    pre = 1:i0-1;
    pulses.role(pre) = "preamble";
    pulses.role(i0:i0+nS-1) = "startCode";
    info.nPreamble = numel(pre);
    info.preamble = pulses(pre, {'tSec', 'durSec'});   % any width (a line already low at file start too)
    info.startCodeSec = pulses.tSec(i0);

    % ---- end code: the last nEndCode pulses, short, at codeGapSec ----
    nE = opts.nEndCode;
    iE = n - nE + 1;
    okEnd = iE > i0 + nS && all(isS(iE:n));
    for j = iE:n-1
        okEnd = okEnd && gapOK(j);
    end
    if ~okEnd
        error('parse_detectNoOdor_events:noEndCode', ...
            'the last %d pulses (from %.2f s) are not the end code (%d x %.2f s, %.2f s apart)', ...
            nE, pulses.tSec(max(iE, 1)), nE, opts.shortSec, opts.codeGapSec);
    end
    pulses.role(iE:n) = "endCode";

    % ---- body: sniff cue, then at most one response pulse ----
    body = (i0+nS):(iE-1);
    bad = body(~isS(body) & ~isM(body));
    if ~isempty(bad)
        error('parse_detectNoOdor_events:unknownPulse', ...
            '%d pulse(s) between start and end code are neither %.2f-s nor %.2f-s (first at %.2f s, %.3f s wide)', ...
            numel(bad), opts.sniffSec, opts.shortSec, pulses.tSec(bad(1)), pulses.durSec(bad(1)));
    end
    if isempty(body) || ~isM(body(1))
        error('parse_detectNoOdor_events:noFirstSniff', 'the first pulse after the start code is not a sniff cue');
    end
    iSn = body(isM(body));
    nT = numel(iSn);
    ev = struct;
    ev.sniff = pulses.onset(iSn);
    ev.response = nan(nT, 1);
    for t = 1:nT
        if t < nT, last = iSn(t+1) - 1; else, last = iE - 1; end
        pulses.role(iSn(t)) = "sniff";
        pulses.trial(iSn(t):last) = t;
        r = (iSn(t)+1):last;
        if numel(r) > 1
            error('parse_detectNoOdor_events:twoResponses', ...
                'trial %d (cue %.2f s): %d response pulses', t, pulses.tSec(iSn(t)), numel(r));
        end
        if isscalar(r)
            lat = (pulses.onset(r) - pulses.onset(iSn(t))) / fs;
            if lat < opts.respLatSec(1) || lat > opts.respLatSec(2)
                error('parse_detectNoOdor_events:respLatency', ...
                    'trial %d: response pulse %.2f s after the cue (allowed %.1f-%.1f s)', ...
                    t, lat, opts.respLatSec(1), opts.respLatSec(2));
            end
            pulses.role(r) = "response";
            ev.response(t) = pulses.onset(r);
        end
    end
    ev.startCode = pulses.onset(i0:i0+nS-1)';
    ev.endCode = pulses.onset(iE:n)';
    info.nTrials = nT;
    info.nResponses = sum(~isnan(ev.response));
    info.sniffWidthSec = [min(pulses.durSec(iSn)) max(pulses.durSec(iSn))];
    if info.nResponses > 0
        info.respWidthSec = [min(pulses.durSec(pulses.role == "response")) max(pulses.durSec(pulses.role == "response"))];
    else
        info.respWidthSec = [NaN NaN];
    end
end

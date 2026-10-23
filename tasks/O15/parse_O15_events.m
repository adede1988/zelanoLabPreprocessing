function [ev, pulses, info] = parse_O15_events(pd, fs, opts)
%PARSE_O15_EVENTS  Robust (no z-score) parse of the O15 event channel into trials.
%
%   [ev, pulses, info] = parse_O15_events(pd, fs, opts)
%
%   pd   : the raw event channel (1 x nSamp, NaNs already filled), fs : its rate.
%   opts : optional struct, fields (defaults):
%     threshFrac    0.5    pulse-on threshold = median + threshFrac*(low - median),
%                          low = the 0.5th percentile (the negative rail when clipped)
%     mergeGapSec   0.005  re-join a pulse split by a gap shorter than this
%     minPulseSec   0.02   drop blips shorter than this
%     shortSec      0.307  programmatic short pulse (trial start, press pair)
%     midSec        0.505  programmatic mid pulse (start cue, confirm pair; old free marks)
%     widthTolSec   0.04   |width - shortSec/midSec| tolerance
%     pairShortSec  0.415  onset-to-onset spacing of the press pair (SS)
%     pairMidSec    0.610  onset-to-onset spacing of the confirm pair (MM)
%     pairTolSec    0.05
%     cueDelaySec   [7 8.5] trial start -> start cue onset (measured 7.75-7.80 s)
%     expectedTrials 15    error unless exactly this many trials ([] = no check)
%     strict        true   error on any pulse the motif does not explain (anything
%                          but short sync pulses before trial 1, or pulses between
%                          a confirm pair and the next start); false labels them
%                          'preamble' / 'extra' instead (surveys only)
%
%   WHY (tasks_261014 task 10, 2026-10-14): the O15 DAQ event input is AC-coupled
%   and rail-clipped (+-5000): a pulse sits on the NEGATIVE rail and its release
%   throws the trace onto the positive rail, decaying back over seconds. Since
%   ~Oct 2025 the experimenter HOLDS the button while the odor bottle is under the
%   participant's nose (held-button protocol) instead of tapping once per observed
%   sniff; the long holds put ~25 % of the samples on the negative rail, the
%   z-scored low state no longer reaches the legacy -2 threshold (DB_3: z -1.39),
%   and detect_ttls_O15's maxPulseSamp drops every hold. This parser uses
%   rail/median-referenced levels and the fixed widths of the programmatic pulses.
%
%   Trial motif (both protocols; measured on 251030_Dupi_NMH_DB_3 and
%   251110_Dupi_NMH_PC_2):
%     [preamble: 5 short sync pulses ~0.41 s apart]
%     S  trial start (single short, ~0.31 s)
%     M  start cue   (single mid ~0.50 s, 7.75-7.80 s after the start; the
%        'start' sniff follows it)
%     .. free events (old protocol: one ~0.50 s pulse per sniff the experimenter
%        saw; held-button protocol: one pulse per button-down period, any width)
%     SS button press (two short pulses 0.41 s apart; when the experimenter is
%        still holding the button, pulse 1 disappears into the hold's tail:
%        it is then inferred pairShortSec before pulse 2, the hold is cut
%        there, and the trial is listed in info.mergedPress)
%     MM confirm      (two mid pulses 0.61 s apart; the 'confirm' sniff follows)
%
%   Outputs (raw-sample indices at fs; onset = last sample above the threshold,
%   the legacy 'downs' convention of detect_ttls_O15; offset = last sample below):
%     ev.trialStart, ev.cue, ev.press (2nd pulse of SS, as the legacy code
%     keeps it), ev.confirm (1st pulse of MM), ev.pressPair, ev.confirmPair
%     [nTrial x 2], ev.free{k} = [onset offset] of trial k's free-event pulses.
%     pulses : table of every pulse (onset, offset, durSec, tSec, role, trial).
%     info   : levels, threshold, fractions of time low / on each rail, counts.

    if nargin < 3, opts = struct; end
    d = struct('threshFrac', 0.5, 'mergeGapSec', 0.005, 'minPulseSec', 0.02, ...
        'shortSec', 0.307, 'midSec', 0.505, 'widthTolSec', 0.04, ...
        'pairShortSec', 0.415, 'pairMidSec', 0.610, 'pairTolSec', 0.05, ...
        'cueDelaySec', [7 8.5], 'expectedTrials', 15, 'strict', true);
    fn = fieldnames(d);
    for i = 1:numel(fn)
        if ~isfield(opts, fn{i}), opts.(fn{i}) = d.(fn{i}); end
    end

    pd = double(pd(:))';
    if any(isnan(pd)), error('parse_O15_events:NaN', 'fill NaNs before parsing'); end

    % ---- levels and threshold (no z-score) ----
    info = struct;
    info.min = min(pd); info.max = max(pd);
    info.median = median(pd);
    info.low = prctile(pd, 0.5);
    info.thresh = info.median + opts.threshFrac * (info.low - info.median);
    rng = info.max - info.min;
    info.fracBelowThresh = mean(pd < info.thresh);
    info.fracNegRail = mean(pd <= info.min + 0.002*rng);
    info.fracPosRail = mean(pd >= info.max - 0.002*rng);
    sd = std(pd);
    info.zOfLow = (info.low - mean(pd)) / sd;     % what the legacy z-score sees
    if info.median - info.low < 0.25 * rng
        error('parse_O15_events:noPulses', ...
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
    s = s - 1; s(s < 1) = 1;          % legacy 'downs' convention (last sample above)
    n = numel(s);

    pulses = table;
    pulses.onset  = s(:);
    pulses.offset = f(:);
    pulses.durSec = (f(:) - s(:)) / fs;
    pulses.tSec   = (s(:) - 1) / fs;
    pulses.role   = repmat("unassigned", n, 1);
    pulses.trial  = nan(n, 1);

    isS = abs(pulses.durSec - opts.shortSec) < opts.widthTolSec;
    isM = abs(pulses.durSec - opts.midSec)   < opts.widthTolSec;
    on1 = pulses.onset;
    pairS = false(n, 1); pairM = false(n, 1);  % pulse i starts an SS / MM pair
    for i = 1:n-1
        gap = (on1(i+1) - on1(i)) / fs;
        pairS(i) = isS(i) && isS(i+1) && abs(gap - opts.pairShortSec) < opts.pairTolSec;
        pairM(i) = isM(i) && isM(i+1) && abs(gap - opts.pairMidSec)   < opts.pairTolSec;
    end

    % ---- trial starts: a lone short pulse followed by the start cue ----
    isStart = false(n, 1);
    for i = 1:n-1
        if ~isS(i) || pairS(i) || (i > 1 && pairS(i-1)), continue; end
        dl = (on1(i+1) - on1(i)) / fs;
        isStart(i) = isM(i+1) && ~pairM(i+1) && dl >= opts.cueDelaySec(1) && dl <= opts.cueDelaySec(2);
    end
    st = find(isStart);
    if isempty(st), error('parse_O15_events:noTrials', 'no trial start (S + cue) found'); end

    % preamble before the first trial: must be short pulses only (sync burst)
    pre = 1:st(1)-1;
    if any(~isS(pre))
        if opts.strict
            error('parse_O15_events:preamble', ...
                'unexpected pulse(s) before the first trial start at %.2f s: %s', ...
                pulses.tSec(st(1)), mat2str(round(pulses.durSec(pre(~isS(pre)))', 3)));
        end
        pulses.role(pre) = "preamble";
    else
        pulses.role(pre) = "sync";
    end
    info.nPreamble = numel(pre);
    info.nExtra = 0;
    info.mergedPress = [];     % trials whose press pulse 1 was hidden in a hold

    % ---- state machine per trial ----
    nT = numel(st);
    ev = struct;
    ev.trialStart = nan(nT, 1); ev.cue = nan(nT, 1);
    ev.press = nan(nT, 1); ev.confirm = nan(nT, 1);
    ev.pressPair = nan(nT, 2); ev.confirmPair = nan(nT, 2);
    ev.free = cell(nT, 1);
    for t = 1:nT
        i0 = st(t);
        if t < nT, iEnd = st(t+1) - 1; else, iEnd = n; end
        ev.trialStart(t) = on1(i0);   pulses.role(i0) = "start";
        ev.cue(t) = on1(i0+1);        pulses.role(i0+1) = "cue";
        pulses.trial(i0:iEnd) = t;
        ip = find(pairS(i0+2:iEnd), 1) + i0 + 1;      % press pair (first SS)
        merged = false;
        if isempty(ip)
            % The press pair's FIRST pulse can be hidden in the tail of a button
            % hold (the line is low for either; 260917_OBE_NWU_RC_2 trial 12):
            % then a lone short pulse starts (pairShortSec - shortSec) after the
            % end of a longer pulse and is followed directly by the confirm pair.
            for i = (i0+3):(iEnd-2)
                gapPrev = (pulses.onset(i) - pulses.offset(i-1)) / fs;
                if isS(i) && ~pairS(i) && pairM(i+1) && ...
                        pulses.durSec(i-1) > opts.shortSec + opts.widthTolSec && ...
                        abs(gapPrev - (opts.pairShortSec - opts.shortSec)) < opts.pairTolSec
                    ip = i; merged = true; break
                end
            end
        end
        if isempty(ip)
            error('parse_O15_events:noPress', 'trial %d (start %.2f s): no press pair', t, pulses.tSec(i0));
        end
        if merged
            p1 = on1(ip) - round(opts.pairShortSec * fs);     % inferred hidden pulse 1
            if p1 - 1 <= pulses.onset(ip-1)
                error('parse_O15_events:merge', 'trial %d: hold too short to hide press pulse 1', t);
            end
            ev.pressPair(t, :) = [p1 on1(ip)];   ev.press(t) = on1(ip);
            pulses.role(ip) = "press2";
            pulses.offset(ip-1) = p1 - 1;                    % the hold ends where pulse 1 began
            pulses.durSec(ip-1) = (pulses.offset(ip-1) - pulses.onset(ip-1)) / fs;
            info.mergedPress(end+1) = t;
            ic = ip + 1;
        else
            ev.pressPair(t, :) = on1([ip ip+1]);    ev.press(t) = on1(ip+1);
            pulses.role([ip ip+1]) = ["press1"; "press2"];
            ic = ip + 2;
        end
        if ic + 1 > iEnd || ~pairM(ic)
            error('parse_O15_events:noConfirm', ...
                'trial %d (start %.2f s): press pair at %.2f s not followed by the confirm pair', ...
                t, pulses.tSec(i0), pulses.tSec(ip));
        end
        ev.confirmPair(t, :) = on1([ic ic+1]); ev.confirm(t) = on1(ic);
        pulses.role([ic ic+1]) = ["confirm1"; "confirm2"];
        fr = (i0+2):(ip-1);
        pulses.role(fr) = "free";
        ev.free{t} = [pulses.onset(fr) pulses.offset(fr)];
        ex = (ic+2):iEnd;
        if ~isempty(ex)
            if opts.strict
                error('parse_O15_events:extra', ...
                    'trial %d: %d unexplained pulse(s) after the confirm pair (first at %.2f s, %.3f s wide)', ...
                    t, numel(ex), pulses.tSec(ex(1)), pulses.durSec(ex(1)));
            end
            pulses.role(ex) = "extra";
            info.nExtra = info.nExtra + numel(ex);
        end
    end
    info.nTrials = nT;
    nFree = cellfun(@(x) size(x, 1), ev.free);
    info.nFreePulses = sum(nFree);
    allFree = pulses.durSec(pulses.role == "free");
    info.freeMedianSec = median(allFree);
    info.freeFracProgrammatic = mean(abs(allFree - opts.midSec) < opts.widthTolSec);
    info.freeTotalSec = sum(allFree);
    if ~isempty(opts.expectedTrials) && nT ~= opts.expectedTrials
        error('parse_O15_events:trialCount', 'found %d trials, expected %d', nT, opts.expectedTrials);
    end
end

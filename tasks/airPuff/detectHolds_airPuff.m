function [holds, quietAtPuff, qc] = detectHolds_airPuff(rsp, fs, puffs, bmObj, opts)
%DETECTHOLDS_AIRPUFF  Breath-hold onset / offset from the respiration around each puff group.
%
%   [holds, quietAtPuff, qc] = detectHolds_airPuff(rsp, fs, puffs, bmObj, opts)
%
%   rsp    1 x N respiration at the final rate (rspIDX / rspFlip applied, inhale up)
%   fs     its rate (500)
%   puffs  table, one row per puff: sample (final-rate onset), hold, run,
%          condition, holdInRun (the puff rows of outDat.pulses)
%   bmObj  segmentBreaths_zlp output for the whole recording (CLAUDE.md 6.6;
%          times in s = sample / fs)
%   opts   P.puffOpts.hold, fields (defaults):
%     lpHz        2     low-pass (Hz) of the trace the quiet test is computed on
%     quietWinSec 0.5   centred moving-SD window (s)
%     quietFrac   0.10  quiet = moving SD < quietFrac x the median breath amplitude
%                       (bmObj col 8) of the recording
%     nPreBreaths 3     breaths before the hold breath summarised in preAmp / preLenSec
%
%   DEFINITION. A breath hold is an apnoea: the nasal-pressure trace goes flat.
%   The trace is "quiet" where its centred moving SD (quietWinSec window, <lpHz)
%   is below quietFrac x the recording's median breath amplitude. The hold of a
%   puff group runs from the start of the quiet stretch that contains its first
%   quiet puff to the end of the quiet stretch that contains its last quiet puff
%   (the group itself - which puffs form one hold - comes from the DAQ spacing,
%   parsePuffEvents_airPuff). A hold whose puffs fall in more than one quiet
%   stretch (a breath taken in between) is flagged 'interrupted'; a puff
%   delivered while the trace is not quiet has quietAtPuff = false; a group
%   with no quiet puff has NaN onset / offset. The edges are where the centred
%   window crosses the threshold (within ~quietWinSec/2 of the visible change).
%   Measured on 261008_INR_NWU_SS_1 (2026-10-15): in-hold moving SD 0.3-3 uV,
%   breathing 10-100 uV, median breath amplitude 117 uV; all 7 holds and all 28
%   puffs quiet for quietFrac 0.08-0.10 (0.05 misses the first puff of hold 5,
%   delivered 0.6 s after that hold began).
%
%   Context from the breath segmentation (inhale onsets = bmObj col 2 plus the
%   end of the last breath): holdBreath = the breath whose span contains the
%   first puff (its inhale onset = lastInhaleSec, its exhale trough =
%   exhaleTroughSec - in SS_1 every hold is held after an exhale), nextInhaleSec
%   = the first inhale onset after the last puff (breathing resumes), the
%   recovery breath = the breath that starts there.
%
%   holds (one row per hold; samples at fs, seconds = (sample - 1) / fs):
%     hold, run, condition, holdInRun, nPuffs, nPuffsQuiet, nQuietRuns,
%     interrupted, onset, offset, onsetSec, offsetSec, durSec, firstPuffSec,
%     lastPuffSec, onsetToFirstPuffSec, lastPuffToOffsetSec, holdBreath,
%     lastInhaleSec, exhaleTroughSec, nextInhaleSec, lastPuffToInhaleSec,
%     preAmp, preLenSec (median of the nPreBreaths breaths before the hold
%     breath), recoveryAmp, recoveryLenSec (the breath starting at nextInhale)
%   quietAtPuff  logical, one per puff row
%   qc           struct for the QC figures (rl, msd, quiet, thr, ampRef) - not saved

    if nargin < 5 || isempty(opts), opts = struct; end
    d = struct('lpHz', 2, 'quietWinSec', 0.5, 'quietFrac', 0.10, 'nPreBreaths', 3);
    fn = fieldnames(d);
    for i = 1:numel(fn)
        if ~isfield(opts, fn{i}), opts.(fn{i}) = d.(fn{i}); end
    end
    assert(~isempty(bmObj), 'detectHolds_airPuff: no breaths segmented');

    rsp = double(rsp(:))';
    N = numel(rsp);
    [b, a] = butter(2, opts.lpHz / (fs / 2), 'low');
    rl = filtfilt(b, a, rsp);
    msd = movstd(rl, round(opts.quietWinSec * fs));
    ampRef = median(bmObj(:, 8));
    thr = opts.quietFrac * ampRef;
    quiet = msd < thr;
    dq = diff([false quiet false]);
    qs = find(dq == 1); qe = find(dq == -1) - 1;
    runOf = zeros(1, N);
    for r = 1:numel(qs), runOf(qs(r):qe(r)) = r; end

    sp = puffs.sample(:);
    quietAtPuff = quiet(sp)';

    onsS = round(bmObj(:, 2) * fs);                 % inhale onsets (samples)
    endS = round(bmObj(:, 6) * fs);
    trS  = round(bmObj(:, 11) * fs);
    allOns = unique([onsS; endS(end)]);             % + the final inhale (end of the last breath)

    hIds = unique(puffs.hold(:))';
    nH = numel(hIds);
    holds = table;
    holds.hold = hIds(:);
    holds.run = nan(nH, 1);
    holds.condition = repmat("", nH, 1);
    numCols = {'holdInRun', 'nPuffs', 'nPuffsQuiet', 'nQuietRuns'};
    for c = 1:numel(numCols), holds.(numCols{c}) = nan(nH, 1); end
    holds.interrupted = false(nH, 1);
    numCols = {'onset', 'offset', 'onsetSec', 'offsetSec', 'durSec', 'firstPuffSec', 'lastPuffSec', ...
        'onsetToFirstPuffSec', 'lastPuffToOffsetSec', 'holdBreath', 'lastInhaleSec', 'exhaleTroughSec', ...
        'nextInhaleSec', 'lastPuffToInhaleSec', 'preAmp', 'preLenSec', 'recoveryAmp', 'recoveryLenSec'};
    for c = 1:numel(numCols), holds.(numCols{c}) = nan(nH, 1); end
    toSec = @(s) (s - 1) / fs;

    for k = 1:nH
        m = puffs.hold == hIds(k);
        spk = sp(m);
        holds.run(k) = puffs.run(find(m, 1));
        holds.condition(k) = string(puffs.condition(find(m, 1)));
        holds.holdInRun(k) = puffs.holdInRun(find(m, 1));
        holds.nPuffs(k) = sum(m);
        qk = quietAtPuff(m);
        holds.nPuffsQuiet(k) = sum(qk);
        holds.firstPuffSec(k) = toSec(spk(1));
        holds.lastPuffSec(k) = toSec(spk(end));
        if any(qk)
            rr = unique(runOf(spk(qk)));
            holds.nQuietRuns(k) = numel(rr);
            holds.interrupted(k) = numel(rr) > 1;
            holds.onset(k) = qs(min(rr));
            holds.offset(k) = qe(max(rr));
            holds.onsetSec(k) = toSec(holds.onset(k));
            holds.offsetSec(k) = toSec(holds.offset(k));
            holds.durSec(k) = (holds.offset(k) - holds.onset(k) + 1) / fs;
            holds.onsetToFirstPuffSec(k) = (spk(1) - holds.onset(k)) / fs;
            holds.lastPuffToOffsetSec(k) = (holds.offset(k) - spk(end)) / fs;
        else
            holds.nQuietRuns(k) = 0;
        end
        % breath context
        hb = find(onsS <= spk(1), 1, 'last');
        if ~isempty(hb) && endS(hb) > spk(1)
            holds.holdBreath(k) = hb;
            holds.lastInhaleSec(k) = toSec(onsS(hb));
            holds.exhaleTroughSec(k) = toSec(trS(hb));
            pb = max(1, hb - opts.nPreBreaths):hb - 1;
            if ~isempty(pb)
                holds.preAmp(k) = median(bmObj(pb, 8));
                holds.preLenSec(k) = median(bmObj(pb, 7));
            end
        end
        ni = allOns(find(allOns > spk(end), 1));
        if ~isempty(ni)
            holds.nextInhaleSec(k) = toSec(ni);
            holds.lastPuffToInhaleSec(k) = (ni - spk(end)) / fs;
            rb = find(onsS == ni, 1);
            if ~isempty(rb)
                holds.recoveryAmp(k) = bmObj(rb, 8);
                holds.recoveryLenSec(k) = bmObj(rb, 7);
            end
        end
    end

    qc = struct('rl', rl, 'msd', msd, 'quiet', quiet, 'thr', thr, 'ampRef', ampRef, ...
        'allOns', allOns, 'opts', opts);
end

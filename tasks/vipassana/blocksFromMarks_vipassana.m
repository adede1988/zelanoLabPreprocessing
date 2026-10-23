function [blocks, TTL, info] = blocksFromMarks_vipassana(PD, LG, nSamp, fs, opts)
%BLOCKSFROMMARKS_VIPASSANA  vipassana v2 blocks from the photodiode and the SniffLogic log.
%
%   [blocks, TTL, info] = blocksFromMarks_vipassana(PD, LG, nSamp, fs)
%   [blocks, TTL, info] = blocksFromMarks_vipassana(PD, LG, nSamp, fs, opts)
%
%   PD    : parsePhotodiode_vipassana output (.usable, .runs on/off samples)
%   LG    : [] (no log) or struct with .log (parseLog_vipassana) and .align
%           (alignLog_vipassana: raw s = intercept + (1 + slope) log s)
%   nSamp : recording length (samples at fs; the raw fs = the final 500 Hz)
%   opts  : P.vipOpts (fields used: matchTolSec, durTolFrac, durTolMinSec,
%           durCheck, nTaskAllowed; defaults below)
%
%   The v2 protocol (sessions from 2026-09-27 on) runs seven blocks in a fixed
%   order - audiobook1 (5 min), paced1 (8-min paced-breathing sweep, SniffLogic
%   'sweep1'), audiobook2 (5), anapana (15), vipassana (15), metta (7.5),
%   paced2 (8, 'sweep2') - and some sessions stop before paced2. The SniffLogic
%   log names every block it ran (identities, on the log clock); the
%   photodiode marks every block on the recording's own clock (a white square
%   for the block's whole duration, parsePhotodiode_vipassana).
%     log + photodiode   every log block (audio_instruct excluded) must match
%                        exactly one photodiode run whose onset is within
%                        opts.matchTolSec (5 s) of the log start mapped onto
%                        the recording; the boundaries are the photodiode
%                        edges (the screen change itself; they trail the log
%                        events by ~37 ms) and the label is the log's. A log
%                        block without a run takes the mapped log times
%                        (source 'log'); a block run without a log block is
%                        an error.
%     photodiode only    the n block runs (n in opts.nTaskAllowed = [6 7])
%                        take the first n protocol labels in order.
%     log only           mapped log times (photodiode unusable).
%   Every task block's duration must be within max(opts.durTolFrac x nominal,
%   opts.durTolMinSec) of its nominal duration (opts.durCheck = false turns
%   the check off for a session whose blocks were deliberately shortened). A
%   block cut off by the recording's first or last sample (its photodiode run
%   is high there - PD.runs.atStart / atEnd - or its mapped log times fall
%   outside the recording) may only be SHORTER than nominal; a run cut off at
%   the start matches its log block by the offset instead of the onset.
%   info.clippedAtEdge lists such blocks.
%   The stretches between blocks become gap periods, so the table TILES the
%   recording (1..nSamp, like inferBlocks_vipassana):
%       pre | audiobook1 | instructPaced1 | paced1 | instructAudiobook2 |
%       audiobook2 | break | anapana | questionnaire1 | vipassana |
%       questionnaire2 | metta | instructPaced2 | paced2 | post
%   (gap names from the PsychoPy routines of the first sessions:
%   instructionsPlayback, audiobookInstruct2, Break + AnapanaInstruct,
%   Questionnaire1 + VipInstruct, Questionnaire2 + MettaInstruct; what runs
%   between metta and paced2 was not logged in a session with paced2 - the
%   name assumes the paced-breathing instructions). Zero-length gaps are
%   dropped; everything after the last block is 'post'.
%
%   Returns
%     blocks : table, one row per period in time order: label, order
%              (protocol index 0..14 as listed above), kind ('task'/'gap'),
%              still (1 task block, 0 gap), startSample, endSample,
%              durationSec, nominalSec (NaN for gaps), source
%              ('photodiode+log' / 'photodiode' / 'log' / 'gap'), logName,
%              logStartSample / logEndSample (the log's block times mapped
%              onto the recording, NaN without a log), pdMinusLogStartSec /
%              pdMinusLogEndSec (photodiode edge minus mapped log time, s)
%     TTL    : row vector of period starts (= blocks.startSample')
%     info   : struct - protocol, sources, nTask, missingTask (protocol
%              blocks the session did not run), durDevSec, unmatched log
%              blocks, flickers, opts

    if nargin < 5 || isempty(opts), opts = struct(); end
    opts = fillDefaults(opts, struct('matchTolSec', 5, 'durTolFrac', 0.05, 'durTolMinSec', 10, ...
        'durCheck', true, 'nTaskAllowed', [6 7]));
    [taskLab, logNames, nomSec, gapLab, orderTask, orderGap] = protocolV2();

    hasLog = ~isempty(LG);
    hasPD = isstruct(PD) && PD.usable && height(PD.runs) > 0;
    assert(hasLog || hasPD, 'blocksFromMarks_vipassana:noMarks', ...
        'neither a SniffLogic log nor a usable photodiode: the v2 blocks cannot be identified');

    % ---- log blocks on the recording ----
    if hasLog
        LB = LG.log.blocks;
        nm = lower(LB.name);
        keep = nm ~= "audio_instruct";
        unknown = LB.name(keep & ~ismember(nm, lower(logNames)));
        assert(isempty(unknown), 'blocksFromMarks_vipassana:unknownLogBlock', ...
            'SniffLogic block(s) not in the v2 protocol: %s', strjoin(unknown, ', '));
        LB = LB(keep, :);
        nL = height(LB);
        assert(nL >= 1 && isequal(lower(LB.name)', lower(logNames(1:nL))), 'blocksFromMarks_vipassana:logOrder', ...
            'SniffLogic blocks %s are not the protocol sequence %s', strjoin(LB.name, ' '), strjoin(logNames(1:nL), ' '));
        A = LG.align;
        toSamp = @(tLog) round((A.intercept + (1 + A.slope) * tLog) * fs) + 1;
        logS = toSamp(LB.tStart);
        logE = toSamp(LB.tEnd) - 1;          % NaN stays NaN (incomplete block)
    end

    % ---- assemble the task blocks ----
    if hasLog
        n = nL;
    else
        n = height(PD.runs);
        assert(ismember(n, opts.nTaskAllowed), 'blocksFromMarks_vipassana:nRuns', ...
            'photodiode shows %d block runs; the v2 protocol has %s', n, mat2str(opts.nTaskAllowed));
    end
    st = nan(n, 1); en = nan(n, 1); src = strings(n, 1); lname = strings(n, 1);
    lS = nan(n, 1); lE = nan(n, 1); dS = nan(n, 1); dE = nan(n, 1);
    usedRun = false(hasPD * height(PD.runs), 1);
    runCut = false(n, 1);                    % the block's run is cut off by the recording edge
    unmatched = strings(0, 1);
    for k = 1:n
        if hasLog
            lname(k) = LB.name(k); lS(k) = logS(k); lE(k) = logE(k);
            j = [];
            if hasPD
                R = PD.runs;
                % match on the onset; a run cut off at the recording START has no
                % true onset, so it matches on its offset (or, when the log block
                % has no end, by containing the log start)
                dd = abs(R.on - logS(k)) / fs;
                if isfinite(logE(k))
                    dd(R.atStart) = abs(R.off(R.atStart) - logE(k)) / fs;
                else
                    dd(R.atStart) = inf;
                    dd(R.atStart & logS(k) <= R.off) = 0;
                end
                j = find(dd <= opts.matchTolSec);
                assert(numel(j) <= 1, 'blocksFromMarks_vipassana:ambiguousRun', ...
                    '%d photodiode runs within %g s of log block %s', numel(j), opts.matchTolSec, LB.name(k));
            end
            if isscalar(j)
                st(k) = PD.runs.on(j); en(k) = PD.runs.off(j); usedRun(j) = true;
                runCut(k) = PD.runs.atStart(j) || PD.runs.atEnd(j);
                src(k) = "photodiode+log";
                if ~PD.runs.atStart(j), dS(k) = (PD.runs.on(j) - logS(k)) / fs; end
                if isfinite(logE(k)) && ~PD.runs.atEnd(j), dE(k) = (PD.runs.off(j) - logE(k)) / fs; end
            else
                assert(isfinite(logE(k)), 'blocksFromMarks_vipassana:noEnd', ...
                    'log block %s has no end event and no photodiode run', LB.name(k));
                st(k) = logS(k); en(k) = logE(k); src(k) = "log";
                unmatched(end + 1, 1) = LB.name(k); %#ok<AGROW>
            end
        else
            st(k) = PD.runs.on(k); en(k) = PD.runs.off(k); usedRun(k) = true; src(k) = "photodiode";
            runCut(k) = PD.runs.atStart(k) || PD.runs.atEnd(k);
        end
    end
    if hasPD
        assert(all(usedRun), 'blocksFromMarks_vipassana:extraRun', ...
            'photodiode block run(s) at %s s match no SniffLogic block', mat2str(round(PD.runs.onSec(~usedRun)', 1)));
    end
    if ~isempty(unmatched)
        warning('blocksFromMarks_vipassana:logOnly', 'no photodiode run for %s - mapped log times used', strjoin(unmatched, ', '));
    end
    clipped = runCut | st < 1 | en > nSamp;  % cut off by the recording edge
    st = max(1, min(nSamp, st)); en = max(1, min(nSamp, en));
    assert(all(en > st) && all(st(2:end) > en(1:end - 1)), 'blocksFromMarks_vipassana:overlap', ...
        'task blocks overlap or are empty after mapping');

    % ---- durations (a block cut off by the recording edge may only be shorter) ----
    durSec = (en - st + 1) / fs;
    dev = durSec - nomSec(1:n)';
    tol = max(opts.durTolFrac * nomSec(1:n)', opts.durTolMinSec);
    bad = (abs(dev) > tol & ~clipped) | (dev > tol & clipped);
    if opts.durCheck
        assert(~any(bad), 'blocksFromMarks_vipassana:duration', ...
            'block duration(s) off the protocol: %s', strjoin(compose('%s %.1f s (nominal %g)', ...
            string(taskLab(bad))', durSec(bad), nomSec(bad)'), '; '));
    elseif any(bad)
        warning('blocksFromMarks_vipassana:duration', 'durCheck off; off-nominal: %s', strjoin(string(taskLab(bad)), ', '));
    end

    % ---- tile ----
    R = {};
    addRow = @(lab, ord, kind, still, s0, s1, nom, sr, ln, ls, le, ds, de) ...
        {string(lab), ord, string(kind), still, s0, s1, (s1 - s0 + 1) / fs, nom, string(sr), string(ln), ls, le, ds, de};
    if st(1) > 1
        R(end + 1, :) = addRow(gapLab{1}, orderGap(1), 'gap', 0, 1, st(1) - 1, NaN, 'gap', '', NaN, NaN, NaN, NaN);
    end
    for k = 1:n
        R(end + 1, :) = addRow(taskLab{k}, orderTask(k), 'task', 1, st(k), en(k), nomSec(k), src(k), lname(k), ...
            lS(k), lE(k), dS(k), dE(k)); %#ok<AGROW>
        g0 = en(k) + 1;
        if k < n
            g1 = st(k + 1) - 1; gl = gapLab{k + 1}; go = orderGap(k + 1);
        else
            g1 = nSamp; gl = gapLab{end}; go = orderGap(end);
        end
        if g1 >= g0
            R(end + 1, :) = addRow(gl, go, 'gap', 0, g0, g1, NaN, 'gap', '', NaN, NaN, NaN, NaN); %#ok<AGROW>
        end
    end
    blocks = cell2table(R, 'VariableNames', {'label', 'order', 'kind', 'still', 'startSample', 'endSample', ...
        'durationSec', 'nominalSec', 'source', 'logName', 'logStartSample', 'logEndSample', ...
        'pdMinusLogStartSec', 'pdMinusLogEndSec'});
    assert(blocks.startSample(1) == 1 && blocks.endSample(end) == nSamp && ...
        all(blocks.startSample(2:end) == blocks.endSample(1:end - 1) + 1), ...
        'blocksFromMarks_vipassana: periods do not tile 1..nSamp');
    TTL = blocks.startSample';

    info = struct();
    info.protocol = 'v2';
    info.taskLabels = taskLab; info.logNames = logNames; info.nominalSec = nomSec; info.gapLabels = gapLab;
    info.hasLog = hasLog; info.hasPhotodiode = hasPD;
    info.nTask = n;
    info.missingTask = taskLab(n + 1:end);
    info.durDevSec = dev;
    info.clippedAtEdge = taskLab(clipped);
    info.unmatchedLogBlocks = unmatched;
    if hasPD, info.flickers = PD.flickers; else, info.flickers = table(); end
    info.opts = opts;

    fprintf('blocksFromMarks_vipassana: %d task blocks (%s)%s\n', n, ...
        strjoin(compose('%s', src), ', '), ternary(isempty(info.missingTask), '', ...
        [' - not run: ' strjoin(info.missingTask, ', ')]));
    for b = 1:height(blocks)
        fprintf('   %2d %-19s %-4s %8.2f - %8.2f min (%6.1f s)%s\n', blocks.order(b), blocks.label(b), ...
            blocks.kind(b), (blocks.startSample(b) - 1) / fs / 60, blocks.endSample(b) / fs / 60, ...
            blocks.durationSec(b), ternary(isfinite(blocks.pdMinusLogStartSec(b)), ...
            sprintf('  pd-log %+.3f / %+.3f s', blocks.pdMinusLogStartSec(b), blocks.pdMinusLogEndSec(b)), ''));
    end
end

function [taskLab, logNames, nomSec, gapLab, orderTask, orderGap] = protocolV2()
    taskLab  = {'audiobook1', 'paced1', 'audiobook2', 'anapana', 'vipassana', 'metta', 'paced2'};
    logNames = {'audiobook1', 'sweep1', 'audioBook2', 'anapana', 'vipassana', 'metta', 'sweep2'};
    nomSec   = [300 480 300 900 900 450 480];
    % gapLab{1} = before the first block, gapLab{k+1} = after task block k
    % (k = 1..6), gapLab{end} = after the last block
    gapLab   = {'pre', 'instructPaced1', 'instructAudiobook2', 'break', 'questionnaire1', ...
                'questionnaire2', 'instructPaced2', 'post'};
    orderTask = [1 3 5 7 9 11 13];
    orderGap  = [0 2 4 6 8 10 12 14];
end

function out = ternary(c, a, b)
    if c, out = a; else, out = b; end
end

function s = fillDefaults(s, d)
    f = fieldnames(d);
    for k = 1:numel(f)
        if ~isfield(s, f{k}) || isempty(s.(f{k})), s.(f{k}) = d.(f{k}); end
    end
end

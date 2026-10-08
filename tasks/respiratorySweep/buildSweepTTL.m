function [TTL, info, logTrace] = buildSweepTTL(rsp, fsRaw, sessID, logPaths, stopwatch, noteChecks, figDir, opts)
%BUILDSWEEPTTL  Event table of a respiratorySweep recording, built from its SniffLogic logs.
%
%   [TTL, info, logTrace] = buildSweepTTL(rsp, fsRaw, sessID, logPaths, stopwatch, noteChecks, figDir)
%   [...] = buildSweepTTL(..., opts)
%
%   The Atlas recording of this protocol carries NO event marks. The behavioral
%   computer's SniffLogic log(s) carry the protocol events (audiobook listen,
%   block_start / block_end of every pacing block) together with the
%   respiration pressure on the log's own clock, so each log is aligned to the
%   raw respiration by cross-correlation (shared/alignLogToRaw: lag, linear
%   drift, polarity) and its events are mapped onto raw samples. Blocks that
%   were run off-script with a stopwatch (the focused-breathing / audiobook
%   blocks at the end of the first 2026-10 sessions) are not in any log: their
%   start times (Atlas recording time from the session notes) are passed in
%   STOPWATCH and each lasts exactly opts.stopwatchSec. Called by each
%   session's LoadData_<id>_claude.m, which stores the outputs in the raw file
%   (curDat.TTL / .TTLinfo / .logTrace), so the raw file reads as if the
%   recording had been event-marked.
%
%   Inputs
%     rsp        raw respiration (1 x N) at fsRaw, UNFLIPPED, the channel the
%                log is aligned to (CSC31 = rsp1 on the 2026 EEG rig)
%     fsRaw      raw sampling rate (Hz); raw sample k is at (k-1)/fsRaw s
%     sessID     session ID (figure names / messages)
%     logPaths   cellstr of the session's SniffLogic logs, any order; logs with
%                no events (aborted starts) are aligned and reported, not used
%     stopwatch  n x 2 cell {label, 'h:mm:ss' Atlas recording time} ({} = none);
%                labels must start with 'focusedBreathing' or 'audiobook'
%     noteChecks m x 2 or m x 3 cell {key, 'h:mm:ss'[, 'start'|'end']}: approximate
%                event times written in the session notes, compared with the
%                log-derived block start (default) or end as a check that the
%                notes' clock is the raw clock (key = a TTL label or its prefix,
%                e.g. 'audiobook_pre', 'Sweep_b13'); {} = none
%     figDir     QC figure folder (created if missing)
%     opts       optional struct: .expectSweepBlocks (18), .stopwatchSec (360),
%                .noteTolSec (120: |note - log| above this is an error)
%
%   Outputs
%     TTL       table, one row per block in recording order:
%               order, label, blockType ('audiobook' | 'sweep' |
%               'focusedBreathing'), phase ('pre' | 'sweep' | 'post'),
%               sweepNum (1-3, NaN off-sweep), blockIdx (log block number),
%               cpm, depth, cndNum, targetP2T, startSample, endSample (raw
%               samples, 1-based, inclusive), startSec, endSec, durationSec
%               (raw time, 0 = first sample), source ('sniffLogicLog' |
%               'notes_stopwatch'), logFile
%     info      struct: per-log alignment (logAlign), aborted blocks, the
%               stopwatch spec, noteCheck table, rspFlip (log-derived polarity
%               of rsp: +1 = inhale up), fsRaw, nSamples, created
%     logTrace  struct: fs (50), pressure / target (single, NaN where no log /
%               no target), on the raw clock (sample 1 = raw time 0)

    if nargin < 8 || isempty(opts), opts = struct(); end
    if ~isfield(opts, 'expectSweepBlocks'), opts.expectSweepBlocks = 18; end
    if ~isfield(opts, 'stopwatchSec'),      opts.stopwatchSec = 360; end
    if ~isfield(opts, 'noteTolSec'),        opts.noteTolSec = 120; end
    if isempty(stopwatch),  stopwatch = cell(0, 2); end
    if isempty(noteChecks), noteChecks = cell(0, 2); end
    if ischar(logPaths) || isstring(logPaths), logPaths = cellstr(logPaths); end
    if ~isfolder(figDir), mkdir(figDir); end

    rsp = double(rsp(:)');
    if any(~isfinite(rsp))            % Neuralynx reads can carry NaN at gaps
        rsp = fillmissing(rsp, 'linear', 'EndValues', 'nearest');
    end
    N = numel(rsp);
    durRaw = (N - 1) / fsRaw;
    toSamp = @(sec) round(sec * fsRaw) + 1;

    % ---------------- parse + align every log ----------------
    nLog = numel(logPaths);
    logs = cell(nLog, 1);
    al = struct('file', {}, 'lagSec', {}, 'r', {}, 'rLocal', {}, 'reviewNeeded', {}, 'corrSign', {}, ...
                'rspFlip', {}, 'driftPPM', {}, 'useDrift', {}, 't0Log', {}, 'mapIntercept', {}, ...
                'mapSlope', {}, 'rawStartSec', {}, 'rawEndSec', {}, 'nBlocks', {}, 'hasAudio', {});
    for k = 1:nLog
        Lg = parse_sweepLog(logPaths{k});
        [~, fn, ext] = fileparts(logPaths{k});
        A = alignLogToRaw(struct('t', Lg.t, 'p', Lg.p), rsp, fsRaw, sprintf('%s_log%d', sessID, k), figDir);
        Lg.rawSec = @(tl) A.mapIntercept + (1 + A.mapSlope) .* (tl - A.t0Log);
        logs{k} = Lg;
        al(k).file = [fn ext];
        al(k).lagSec = A.lagSec; al(k).r = A.r; al(k).rLocal = A.rLocal; al(k).reviewNeeded = A.reviewNeeded;
        al(k).corrSign = A.corrSign; al(k).rspFlip = A.rspFlip;
        al(k).driftPPM = A.driftPPM; al(k).useDrift = A.useDrift;
        al(k).t0Log = A.t0Log; al(k).mapIntercept = A.mapIntercept; al(k).mapSlope = A.mapSlope;
        al(k).rawStartSec = Lg.rawSec(Lg.t(1)); al(k).rawEndSec = Lg.rawSec(Lg.t(end));
        al(k).nBlocks = height(Lg.blocks); al(k).hasAudio = ~isempty(Lg.audio);
        fprintf('%s log%d %s: overlap |r| %.2f, lag %.2f s, drift %.1f ppm (applied %d), covers raw %.1f-%.1f min\n', ...
            sessID, k, al(k).file, A.rLocal, A.lagSec, A.driftPPM, A.useDrift, al(k).rawStartSec / 60, al(k).rawEndSec / 60);
        assert(al(k).rawStartSec > -60 && al(k).rawEndSec < durRaw + 60, 'buildSweepTTL:outside', ...
            '%s: log %s maps to raw %.1f-%.1f s, outside the %.1f-s recording - alignment is wrong', ...
            sessID, al(k).file, al(k).rawStartSec, al(k).rawEndSec, durRaw);
    end
    flips = unique([al.rspFlip]);
    assert(isscalar(flips), 'buildSweepTTL:polarity', ...
        '%s: the logs disagree on the respiration polarity (%s) - inspect the alignment figures', sessID, mat2str([al.rspFlip]));

    % ---------------- rows from the logs ----------------
    R = emptyRows();
    nAudio = 0;
    aborted = table();
    for k = 1:nLog
        Lg = logs{k};
        if ~isempty(Lg.audio)
            nAudio = nAudio + 1;
            r = rowTemplate();
            r.label = "audiobook_pre"; r.blockType = "audiobook"; r.phase = "pre";
            r.startSec = Lg.rawSec(Lg.audio(1)); r.endSec = Lg.rawSec(Lg.audio(2));
            r.source = "sniffLogicLog"; r.logFile = string(al(k).file);
            R = [R; struct2table(r)]; %#ok<AGROW>
        end
        B = Lg.blocks;
        for b = 1:height(B)
            if ~B.complete(b)
                ab = B(b, {'name', 'blockIdx', 'tStart'});
                ab.rawStartSec = Lg.rawSec(B.tStart(b));
                ab.logFile = string(al(k).file);
                aborted = [aborted; ab]; %#ok<AGROW>
                continue
            end
            r = rowTemplate();
            r.label = B.name(b); r.blockType = "sweep"; r.phase = "sweep";
            r.blockIdx = B.blockIdx(b); r.cpm = B.cpm(b); r.depth = B.depth(b);
            r.cndNum = B.cndNum(b); r.targetP2T = B.targetP2T(b);
            r.startSec = Lg.rawSec(B.tStart(b)); r.endSec = Lg.rawSec(B.tEnd(b));
            r.source = "sniffLogicLog"; r.logFile = string(al(k).file);
            R = [R; struct2table(r)]; %#ok<AGROW>
        end
    end
    assert(nAudio <= 1, 'buildSweepTTL:audio', '%s: %d logs contain an audiobook - expected one', sessID, nAudio);
    if nAudio == 0
        warning('buildSweepTTL:noAudio', '%s: no audiobook events in any log', sessID);
    end
    isSw = R.blockType == "sweep";
    bi = sort(R.blockIdx(isSw));
    assert(numel(bi) == opts.expectSweepBlocks && isequal(bi(:)', 1:opts.expectSweepBlocks), ...
        'buildSweepTTL:sweepBlocks', '%s: expected complete sweep blocks 1..%d, got %s', ...
        sessID, opts.expectSweepBlocks, mat2str(bi(:)'));
    % sweep number = which pass through the pace list (6 paces per depth in the
    % 2026-10 protocol: blocks 1-6, 7-12, 13-18); derived from the depth changes
    % so a different pace count still numbers the passes correctly
    [~, ordSw] = sort(R.blockIdx(isSw));
    dep = R.depth(isSw); dep = dep(ordSw);
    passNum = cumsum([1; diff(dep) ~= 0]);
    swRows = find(isSw);
    R.sweepNum(swRows(ordSw)) = passNum;

    % ---------------- stopwatch rows (session notes) ----------------
    for s = 1:size(stopwatch, 1)
        lab = string(stopwatch{s, 1});
        r = rowTemplate();
        r.label = lab; r.phase = "post";
        if startsWith(lab, "focusedBreathing")
            r.blockType = "focusedBreathing";
        elseif startsWith(lab, "audiobook")
            r.blockType = "audiobook";
        else
            error('buildSweepTTL:stopwatchLabel', '%s: stopwatch label "%s" must start with focusedBreathing or audiobook', sessID, lab);
        end
        r.startSec = hms2sec(stopwatch{s, 2});
        r.endSec = r.startSec + opts.stopwatchSec;
        r.source = "notes_stopwatch"; r.logFile = "";
        R = [R; struct2table(r)]; %#ok<AGROW>
    end
    assert(numel(unique(R.label)) == height(R), 'buildSweepTTL:dupLabel', '%s: duplicate block labels', sessID);

    % ---------------- samples, order, checks ----------------
    R.startSample = toSamp(R.startSec);
    R.endSample   = toSamp(R.endSec) - 1;            % inclusive end: the sample before the end time
    R.durationSec = R.endSec - R.startSec;
    R = sortrows(R, 'startSample');
    R.order = (1:height(R))';
    assert(all(R.startSample >= 1 & R.endSample <= N), 'buildSweepTTL:range', ...
        '%s: block(s) %s fall outside the %d-sample recording', sessID, ...
        strjoin(R.label(R.startSample < 1 | R.endSample > N), ', '), N);
    ov = find(R.startSample(2:end) <= R.endSample(1:end-1));
    assert(isempty(ov), 'buildSweepTTL:overlap', '%s: overlapping blocks: %s', sessID, ...
        strjoin(R.label(ov) + " / " + R.label(ov + 1), '; '));
    swDur = R.durationSec(R.blockType == "sweep");
    if any(abs(swDur - median(swDur)) > 2)
        warning('buildSweepTTL:sweepDur', '%s: sweep block durations vary: %s s', sessID, mat2str(round(swDur', 1)));
    end
    if any(R.source == "notes_stopwatch") && any(R.blockType == "sweep")
        lastSweepEnd = max(R.endSec(R.blockType == "sweep"));
        if any(R.startSec(R.source == "notes_stopwatch") < lastSweepEnd)
            warning('buildSweepTTL:stopwatchOrder', '%s: a stopwatch block starts before the last sweep block ends', sessID);
        end
    end

    TTL = R(:, {'order', 'label', 'blockType', 'phase', 'sweepNum', 'blockIdx', 'cpm', 'depth', ...
                'cndNum', 'targetP2T', 'startSample', 'endSample', 'startSec', 'endSec', ...
                'durationSec', 'source', 'logFile'});

    % ---------------- note-time consistency ----------------
    noteCheck = table('Size', [0 6], 'VariableTypes', {'string', 'string', 'string', 'double', 'double', 'double'}, ...
        'VariableNames', {'key', 'edge', 'noteTime', 'noteSec', 'logSec', 'diffSec'});
    for c = 1:size(noteChecks, 1)
        key = string(noteChecks{c, 1});
        edge = "start";
        if size(noteChecks, 2) >= 3 && ~isempty(noteChecks{c, 3}), edge = string(noteChecks{c, 3}); end
        assert(ismember(edge, ["start", "end"]), 'buildSweepTTL:noteEdge', '%s: note check edge must be start or end', sessID);
        m = find(startsWith(TTL.label, key) & TTL.source == "sniffLogicLog", 1);
        assert(~isempty(m), 'buildSweepTTL:noteKey', '%s: note check key "%s" matches no log-derived block', sessID, key);
        ns = hms2sec(noteChecks{c, 2});
        if edge == "start", ls = TTL.startSec(m); else, ls = TTL.endSec(m); end
        noteCheck(end+1, :) = {key, edge, string(noteChecks{c, 2}), ns, ls, ns - ls}; %#ok<AGROW>
    end
    if height(noteCheck) > 0
        fprintf('%s note-time check (note - log-derived start, s):\n', sessID);
        disp(noteCheck)
        bad = abs(noteCheck.diffSec) > opts.noteTolSec;
        assert(~any(bad), 'buildSweepTTL:noteClock', ...
            ['%s: note times differ from the log-derived times by more than %d s (%s) - the notes'' ' ...
             'clock may not be the raw recording clock; stopwatch blocks would be misplaced'], ...
            sessID, opts.noteTolSec, strjoin(noteCheck.key(bad), ', '));
    end

    % ---------------- log trace on the raw clock (50 Hz) ----------------
    fsT = 50;
    tg = (0:1/fsT:durRaw)';
    pres = nan(size(tg)); targ = nan(size(tg));
    for k = 1:nLog
        Lg = logs{k};
        rs = Lg.rawSec(Lg.t);
        in = tg >= rs(1) & tg <= rs(end);
        v = interp1(rs, Lg.p, tg(in), 'linear');
        % no interpolation across log dropouts > 0.5 s
        gi = find(diff(rs) > 0.5);
        for g = gi'
            v(tg(in) > rs(g) & tg(in) < rs(g + 1)) = NaN;
        end
        pres(in) = v;
        if numel(Lg.tTarget) > 1
            rt = Lg.rawSec(Lg.tTarget);
            B = Lg.blocks(Lg.blocks.complete, :);
            for b = 1:height(B)
                tb = Lg.tTarget >= B.tStart(b) & Lg.tTarget <= B.tEnd(b);
                if sum(tb) < 2, continue; end
                inb = tg >= rt(find(tb, 1)) & tg <= rt(find(tb, 1, 'last'));
                targ(inb) = interp1(rt(tb), Lg.target(tb), tg(inb), 'linear');
            end
        end
    end
    logTrace = struct('fs', fsT, 'pressure', single(pres), 'target', single(targ), ...
        'note', 'SniffLogic pressure_pa / target_pa on the raw clock: sample i at raw time (i-1)/fs; NaN = no log / no target');

    info = struct();
    info.sessID = sessID;
    info.fsRaw = fsRaw;
    info.nSamples = N;
    info.logAlign = al;
    info.rspFlip = flips;
    info.aborted = aborted;
    info.stopwatch = cell2table(stopwatch, 'VariableNames', {'label', 'noteTime'});
    info.stopwatchSec = opts.stopwatchSec;
    info.noteCheck = noteCheck;
    info.created = char(datetime('now', 'Format', 'yyyy-MM-dd HH:mm:ss'));
    info.function = 'buildSweepTTL';

    fprintf('%s: %d blocks (%d audiobook / %d sweep / %d focusedBreathing), rspFlip %+d, %d aborted block start(s)\n', ...
        sessID, height(TTL), sum(TTL.blockType == "audiobook"), sum(TTL.blockType == "sweep"), ...
        sum(TTL.blockType == "focusedBreathing"), flips, height(aborted));

    writetable(TTL, fullfile(figDir, [sessID '_sweepTTL.csv']));
    plotSweepTTL(rsp .* flips, fsRaw, TTL, logTrace, info, sessID, figDir);
end

% =====================================================================

function R = emptyRows()
    R = struct2table(rowTemplate());
    R(1, :) = [];
end

function r = rowTemplate()
    r = struct('label', "", 'blockType', "", 'phase', "", 'sweepNum', NaN, 'blockIdx', NaN, ...
               'cpm', NaN, 'depth', NaN, 'cndNum', NaN, 'targetP2T', NaN, 'startSec', NaN, ...
               'endSec', NaN, 'source', "", 'logFile', "");
end

function s = hms2sec(str)
% 'h:mm:ss', 'mm:ss' or 'h:mm:ss.s' (Atlas recording time) -> seconds
    p = str2double(strsplit(strtrim(char(str)), ':'));
    assert(all(isfinite(p)) && numel(p) >= 2 && numel(p) <= 3, 'buildSweepTTL:time', 'bad time "%s"', str);
    s = sum(p .* 60 .^ (numel(p) - 1:-1:0));
end

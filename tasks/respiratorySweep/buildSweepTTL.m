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
%     logPaths   cellstr of the session's SniffLogic logs, any order. A log with
%                no events at all (an aborted start) is skipped - not aligned,
%                listed in info.skippedLogs
%     stopwatch  n x 2 cell {label, 'h:mm:ss' Atlas recording time} ({} = none);
%                labels must start with 'focusedBreathing' or 'audiobook'
%     noteChecks m x 2 or m x 3 cell {key, 'h:mm:ss'[, 'start'|'end']}: approximate
%                event times written in the session notes, compared with the
%                log-derived block start (default) or end as a check that the
%                notes' clock is the raw clock (key = a TTL label or its prefix,
%                e.g. 'audiobook_pre', 'Sweep_b13'); {} = none
%     figDir     QC figure folder (created if missing)
%     opts       optional struct: .expectSweepBlocks (18), .stopwatchSec (360),
%                .noteTolSec (120: any |note - log| above this is an error),
%                .noteMedianTolSec (30: with >= 2 checks, |median(note - log)|
%                above this is an error - a systematic clock offset)
%
%   Outputs
%     TTL       table, one row per block in recording order:
%               order, label, blockType ('audiobook' | 'sweep' |
%               'focusedBreathing' | 'other'), phase ('pre' / 'sweep' / 'mid' /
%               'post': before the first sweep block, a sweep block, between,
%               after the last), sweepNum (pass 1-3, NaN off-sweep), blockIdx
%               (log block number), cpm, depth, cndNum (as logged, not unique),
%               targetP2T, startSample, endSample (raw samples, 1-based,
%               inclusive), startSec, endSec, durationSec (raw time, 0 = first
%               sample), source ('sniffLogicLog' | 'notes_stopwatch'), logFile
%               Labels: the log's block names (Sweep_b<NN>_cpm<rate>_depth<scale>,
%               or any other logged name), 'audiobook_<phase>' for the logged
%               audiobook listen, the given labels for stopwatch blocks.
%     info      struct: per-log alignment (logAlign), skippedLogs, aborted
%               blocks, the stopwatch spec, noteCheck table, flags (every check
%               that needs a look - also printed, so they survive warning('off')),
%               rspFlip (log-derived polarity of rsp: +1 = inhale up), fsRaw,
%               nSamples, created
%     logTrace  struct: fs (50), pressure / target (single, NaN where no log /
%               no target), on the raw clock (sample 1 = raw time 0)

    if nargin < 8 || isempty(opts), opts = struct(); end
    if ~isfield(opts, 'expectSweepBlocks'), opts.expectSweepBlocks = 18; end
    if ~isfield(opts, 'stopwatchSec'),      opts.stopwatchSec = 360; end
    if ~isfield(opts, 'noteTolSec'),        opts.noteTolSec = 120; end
    if ~isfield(opts, 'noteMedianTolSec'),  opts.noteMedianTolSec = 30; end
    if isempty(stopwatch),  stopwatch = cell(0, 2); end
    if isempty(noteChecks), noteChecks = cell(0, 2); end
    if ischar(logPaths) || isstring(logPaths), logPaths = cellstr(logPaths); end
    if ~isfolder(figDir), mkdir(figDir); end
    flags = strings(0, 1);

    rsp = double(rsp(:)');
    if any(~isfinite(rsp))            % Neuralynx reads can carry NaN at gaps
        rsp = fillmissing(rsp, 'linear', 'EndValues', 'nearest');
    end
    N = numel(rsp);
    durRaw = (N - 1) / fsRaw;
    toSamp = @(sec) round(sec * fsRaw) + 1;

    % ---------------- parse + align every log with events ----------------
    logs = {};
    skipped = strings(0, 1);
    al = struct('file', {}, 'lagSec', {}, 'r', {}, 'rLocal', {}, 'reviewNeeded', {}, 'corrSign', {}, ...
                'rspFlip', {}, 'driftPPM', {}, 'useDrift', {}, 't0Log', {}, 'mapIntercept', {}, ...
                'mapSlope', {}, 'rawStartSec', {}, 'rawEndSec', {}, 'nBlocks', {}, 'hasAudio', {});
    for kk = 1:numel(logPaths)
        Lg = parse_sweepLog(logPaths{kk});
        [~, fn, ext] = fileparts(logPaths{kk});
        if isempty(Lg.audio) && height(Lg.blocks) == 0
            fprintf('%s: %s has no events (%.1f s of pressure) - skipped, not aligned\n', sessID, [fn ext], Lg.t(end) - Lg.t(1));
            skipped(end+1, 1) = string([fn ext]); %#ok<AGROW>
            continue
        end
        k = numel(logs) + 1;
        A = alignLogToRaw(struct('t', Lg.t, 'p', Lg.p), rsp, fsRaw, sprintf('%s_log%d', sessID, k), figDir);
        Lg.rawSec = @(tl) A.mapIntercept + (1 + A.mapSlope) .* (tl - A.t0Log);
        logs{k} = Lg; %#ok<AGROW>
        al(k).file = [fn ext];
        al(k).lagSec = A.lagSec; al(k).r = A.r; al(k).rLocal = A.rLocal; al(k).reviewNeeded = A.reviewNeeded;
        al(k).corrSign = A.corrSign; al(k).rspFlip = A.rspFlip;
        al(k).driftPPM = A.driftPPM; al(k).useDrift = A.useDrift;
        al(k).t0Log = A.t0Log; al(k).mapIntercept = A.mapIntercept; al(k).mapSlope = A.mapSlope;
        al(k).rawStartSec = Lg.rawSec(Lg.t(1)); al(k).rawEndSec = Lg.rawSec(Lg.t(end));
        al(k).nBlocks = height(Lg.blocks); al(k).hasAudio = ~isempty(Lg.audio);
        fprintf('%s log%d %s: overlap |r| %.2f, lag %.2f s, drift %.1f ppm (applied %d), covers raw %.1f-%.1f min\n', ...
            sessID, k, al(k).file, A.rLocal, A.lagSec, A.driftPPM, A.useDrift, al(k).rawStartSec / 60, al(k).rawEndSec / 60);
        if A.reviewNeeded
            flags(end+1, 1) = sprintf('log%d alignment overlap |r| %.2f < 0.60 (REVIEW)', k, A.rLocal); %#ok<AGROW>
        end
        % the log's EVENTS must land inside the recording; the log itself may run past
        % it (SniffLogic kept logging ~5 min after Atlas stopped in 261014_EEG_NWU_ZL)
        evT = [];
        if ~isempty(Lg.audio), evT = Lg.audio(:)'; end
        if height(Lg.blocks) > 0, evT = [evT, Lg.blocks.tStart(:)', Lg.blocks.tEnd(:)']; end %#ok<AGROW>
        evRaw = Lg.rawSec(evT(isfinite(evT)));
        assert(min(evRaw) > -5 && max(evRaw) < durRaw + 5, 'buildSweepTTL:outside', ...
            '%s: log %s events map to raw %.1f-%.1f s, outside the %.1f-s recording - alignment is wrong', ...
            sessID, al(k).file, min(evRaw), max(evRaw), durRaw);
        if al(k).rawStartSec < -60 || al(k).rawEndSec > durRaw + 60
            flags(end+1, 1) = sprintf(['log%d runs from %.0f s to %.0f s on the raw clock, beyond the %.0f-s ' ...
                'recording (its events are inside; the log outlasted the recording)'], k, al(k).rawStartSec, ...
                al(k).rawEndSec, durRaw); %#ok<AGROW>
        end
    end
    assert(~isempty(logs), 'buildSweepTTL:noLogs', '%s: no SniffLogic log with events', sessID);
    flips = unique([al.rspFlip]);
    assert(isscalar(flips), 'buildSweepTTL:polarity', ...
        '%s: the logs disagree on the respiration polarity (%s) - inspect the alignment figures', sessID, mat2str([al.rspFlip]));

    % ---------------- rows from the logs ----------------
    R = emptyRows();
    nAudio = 0;
    aborted = table();
    for k = 1:numel(logs)
        Lg = logs{k};
        if ~isempty(Lg.audio)
            nAudio = nAudio + 1;
            r = rowTemplate();
            r.label = "audiobook_log"; r.blockType = "audiobook";     % renamed by phase below
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
            r.label = B.name(b);
            if B.isSweep(b)
                r.blockType = "sweep";
            elseif contains(lower(B.name(b)), "focus")
                r.blockType = "focusedBreathing";
            elseif contains(lower(B.name(b)), "audio")
                r.blockType = "audiobook";
            else
                r.blockType = "other";
            end
            r.blockIdx = B.blockIdx(b); r.cpm = B.cpm(b); r.depth = B.depth(b);
            r.cndNum = B.cndNum(b); r.targetP2T = B.targetP2T(b);
            r.startSec = Lg.rawSec(B.tStart(b)); r.endSec = Lg.rawSec(B.tEnd(b));
            r.source = "sniffLogicLog"; r.logFile = string(al(k).file);
            R = [R; struct2table(r)]; %#ok<AGROW>
        end
    end
    if nAudio == 0
        flags(end+1, 1) = "no audiobook listen events in any log";
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
        r.label = lab;
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

    % ---------------- phases (by time relative to the sweep) ----------------
    swStart = min(R.startSec(isSw)); swEnd = max(R.endSec(R.blockType == "sweep"));
    for i = 1:height(R)
        if R.blockType(i) == "sweep"
            R.phase(i) = "sweep";
        elseif R.endSec(i) <= swStart
            R.phase(i) = "pre";
        elseif R.startSec(i) >= swEnd
            R.phase(i) = "post";
        else
            R.phase(i) = "mid";
        end
    end
    isLogAudio = R.label == "audiobook_log";
    R.label(isLogAudio) = "audiobook_" + R.phase(isLogAudio);
    assert(numel(unique(R.label)) == height(R), 'buildSweepTTL:dupLabel', '%s: duplicate block labels %s', sessID, ...
        strjoin(R.label, ', '));

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
        flags(end+1, 1) = "sweep block durations vary: " + mat2str(round(swDur', 1)) + " s";
    end
    if any(R.source == "notes_stopwatch" & R.phase ~= "post")
        flags(end+1, 1) = "a stopwatch block starts before the last sweep block ends";
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
        fprintf('%s note-time check (note - log-derived time, s):\n', sessID);
        disp(noteCheck)
        bad = abs(noteCheck.diffSec) > opts.noteTolSec;
        assert(~any(bad), 'buildSweepTTL:noteClock', ...
            ['%s: note times differ from the log-derived times by more than %d s (%s) - the notes'' ' ...
             'clock may not be the raw recording clock; stopwatch blocks would be misplaced'], ...
            sessID, opts.noteTolSec, strjoin(noteCheck.key(bad), ', '));
        if height(noteCheck) >= 2
            md = median(noteCheck.diffSec);
            assert(abs(md) <= opts.noteMedianTolSec, 'buildSweepTTL:noteOffset', ...
                ['%s: the note times are offset from the log-derived times by a median %+.0f s - a systematic ' ...
                 'clock difference would misplace the stopwatch blocks'], sessID, md);
        end
    end

    % ---------------- log trace on the raw clock (50 Hz) ----------------
    fsT = 50;
    tg = (0:1/fsT:durRaw)';
    pres = nan(size(tg)); targ = nan(size(tg));
    for k = 1:numel(logs)
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
    info.skippedLogs = skipped;
    info.rspFlip = flips;
    info.aborted = aborted;
    info.stopwatch = cell2table(stopwatch, 'VariableNames', {'label', 'noteTime'});
    info.stopwatchSec = opts.stopwatchSec;
    info.noteCheck = noteCheck;
    info.flags = flags;
    info.created = char(datetime('now', 'Format', 'yyyy-MM-dd HH:mm:ss'));
    info.function = 'buildSweepTTL';

    fprintf('%s: %d blocks (%d audiobook / %d sweep / %d focusedBreathing / %d other), rspFlip %+d, %d aborted block start(s), %d skipped log(s)\n', ...
        sessID, height(TTL), sum(TTL.blockType == "audiobook"), sum(TTL.blockType == "sweep"), ...
        sum(TTL.blockType == "focusedBreathing"), sum(TTL.blockType == "other"), flips, height(aborted), numel(skipped));
    for f = 1:numel(flags)
        fprintf('%s CHECK: %s\n', sessID, flags(f));   % printed, not warning(): loaders run with warnings off
    end

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

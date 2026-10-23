function L = parse_sweepLog(csvPath)
%PARSE_SWEEPLOG  Read one SniffLogic log of the respiratorySweep protocol.
%
%   L = parse_sweepLog(csvPath)
%
%   The behavioral computer's <id>_sniffLogicLog_<yyyyMMdd>_<HHmmss>_<n>.csv has
%   columns time_s, pressure_pa, target_pa, block, event at ~200 Hz on the
%   log's own clock (0 = log start). Event rows carry no pressure. The event
%   grammar of this protocol (first sessions 2026-10-06):
%     end_audio_instruct                 once, end of the spoken instructions
%     start_audio_listen                 repeated every frame while the
%                                        audiobook plays (first one = start)
%     end_audio_listen                   once, end of the audiobook
%     block_start <name> cndNum=<k> target_p2t=<Pa> center=<c> gain=<g>
%     block_end <name>                   one pair per pacing block, <name> =
%                                        Sweep_b<NN>_cpm<rate>_depth<scale>
%   target_pa is filled only while a pacing block runs (the target trace the
%   participant traced). A block_start without its block_end is an aborted
%   block (e.g. a restarted run) and is returned with complete = false.
%   Any other block name (e.g. the focused-breathing / audiobook blocks once the
%   protocol logs them) is kept with isSweep = false and NaN pace fields; the
%   block's 'block' column number is its blockIdx in that case.
%
%   Returns struct L with
%     .file         csvPath
%     .t, .p        pressure samples (s, Pa): event rows dropped, strictly
%                   increasing t (duplicate time stamps removed)
%     .tTarget, .target   rows that carry target_pa (s, Pa)
%     .audio        [tStart tEnd] of the audiobook, [] when the log has none
%     .blocks       table, one row per block_start in log order:
%                   name, isSweep, blockIdx, cpm, depth, cndNum (as logged; not
%                   unique - b06 and b07 both log 7), targetP2T, center, gain,
%                   tStart, tEnd (NaN if aborted), complete
%     .events       table t, block, event of every event row (provenance)

    % the event column is sparse text and target_pa / block are mostly empty:
    % force the types so readtable's detection cannot coerce them
    opts = detectImportOptions(csvPath, 'Delimiter', ',');
    need = {'time_s', 'pressure_pa', 'target_pa', 'block', 'event'};
    assert(all(ismember(need, opts.VariableNames)), 'parse_sweepLog:columns', ...
        '%s: expected columns %s, found %s', csvPath, strjoin(need, ','), strjoin(opts.VariableNames, ','));
    opts = setvartype(opts, 'event', 'char');
    opts = setvartype(opts, {'time_s', 'pressure_pa', 'target_pa', 'block'}, 'double');
    T = readtable(csvPath, opts);

    t  = T.time_s;
    ev = strtrim(string(T.event));
    ev(ismissing(ev)) = "";

    L = struct();
    L.file = csvPath;

    sig = isfinite(T.pressure_pa) & isfinite(t);
    [tS, iu] = unique(t(sig), 'sorted');
    pS = T.pressure_pa(sig);
    L.t = tS;
    L.p = pS(iu);
    assert(numel(L.t) > 1000, 'parse_sweepLog:short', '%s: only %d pressure samples', csvPath, numel(L.t));

    tg = isfinite(T.target_pa) & isfinite(t);
    [L.tTarget, it] = unique(t(tg), 'sorted');
    tv = T.target_pa(tg);
    L.target = tv(it);

    isEv = ev ~= "";
    L.events = table(t(isEv), T.block(isEv), ev(isEv), 'VariableNames', {'t', 'block', 'event'});

    % ---- audiobook: first start_audio_listen .. end_audio_listen ----
    L.audio = [];
    aS = t(ev == "start_audio_listen");
    aE = t(ev == "end_audio_listen");
    if ~isempty(aS) || ~isempty(aE)
        assert(~isempty(aS) && isscalar(aE), 'parse_sweepLog:audio', ...
            '%s: audiobook events incomplete (%d start_audio_listen, %d end_audio_listen)', ...
            csvPath, numel(aS), numel(aE));
        assert(aE > min(aS), 'parse_sweepLog:audio', '%s: end_audio_listen precedes the audiobook start', csvPath);
        L.audio = [min(aS), aE];
    end

    % ---- pacing blocks ----
    isStart = startsWith(ev, "block_start ");
    isEnd   = startsWith(ev, "block_end ");
    sIdx = find(isStart);
    n = numel(sIdx);
    name = strings(n, 1); blockIdx = nan(n, 1); cpm = nan(n, 1); depth = nan(n, 1); isSweep = false(n, 1);
    cndNum = nan(n, 1); targetP2T = nan(n, 1); center = nan(n, 1); gain = nan(n, 1);
    tStart = nan(n, 1); tEnd = nan(n, 1); complete = false(n, 1);
    endNames = extractAfter(ev(isEnd), "block_end ");
    endTimes = t(isEnd);
    usedEnd = false(numel(endTimes), 1);
    for k = 1:n
        s = ev(sIdx(k));
        tok = regexp(char(s), '^block_start\s+(\S+)(.*)$', 'tokens', 'once');
        name(k) = string(tok{1});
        kv = tok{2};
        nm = regexp(tok{1}, '_b(\d+)_cpm([\d.]+)_depth([\d.]+)$', 'tokens', 'once');
        if ~isempty(nm)
            isSweep(k)  = true;
            blockIdx(k) = str2double(nm{1});
            cpm(k)      = str2double(nm{2});
            depth(k)    = str2double(nm{3});
        else
            blockIdx(k) = T.block(sIdx(k));     % a non-pacing block: the logged block number
        end
        cndNum(k)    = kvNum(kv, 'cndNum');
        targetP2T(k) = kvNum(kv, 'target_p2t');
        center(k)    = kvNum(kv, 'center');
        gain(k)      = kvNum(kv, 'gain');
        tStart(k)    = t(sIdx(k));
        % matching end: the first unused block_end of the same name after the start
        m = find(endNames == name(k) & endTimes > tStart(k) & ~usedEnd, 1);
        if ~isempty(m)
            % a later block_start of the same name before this end means this
            % start was aborted and restarted
            nextSame = find(startsWith(ev, "block_start " + name(k) + " ") & t > tStart(k), 1);
            if isempty(nextSame) || t(nextSame) > endTimes(m)
                tEnd(k) = endTimes(m);
                complete(k) = true;
                usedEnd(m) = true;
            end
        end
    end
    assert(all(usedEnd), 'parse_sweepLog:orphanEnd', '%s: %d block_end without a block_start', ...
        csvPath, sum(~usedEnd));
    L.blocks = table(name, isSweep, blockIdx, cpm, depth, cndNum, targetP2T, center, gain, tStart, tEnd, complete);

    fprintf('parse_sweepLog: %s\n   %.1f min of pressure, audiobook %s, %d blocks (%d complete)\n', ...
        csvPath, (L.t(end) - L.t(1)) / 60, mat2str(round(L.audio, 1)), n, sum(complete));
end

function v = kvNum(s, key)
    tok = regexp(s, [key '=(\S+)'], 'tokens', 'once');
    if isempty(tok), v = NaN; else, v = str2double(tok{1}); end
end

function L = parseLog_vipassana(csvPath)
%PARSELOG_VIPASSANA  Read one SniffLogic log of the vipassana v2 protocol.
%
%   L = parseLog_vipassana(csvPath)
%
%   The behavioral computer's <id>_sniffLogicLog_<yyyyMMdd>_<HHmmss>_<n>.csv
%   (copied into <root>\<id>\behavioralDat\) has columns time_s, pressure_pa,
%   target_pa, block, event at ~200 Hz on the log's own clock (0 = log
%   start; the laptop's calendar date is wrong in the file names, the clock
%   itself is fine). Event rows carry no pressure. Event grammar (first
%   sessions 2026-09-27, 260927_EEG_NWU_BM / RM, 261016_EEG_NWU_NE):
%     start <name> [parameters]      one per block, <name> = the block column
%     end <name>                     one per completed block
%     breath <k> half <h> period <P> depth <D> amp <A> gain <G> center <C>
%                                    one per paced (sweep) target cycle, at
%                                    the cycle start
%   Blocks seen: audio_instruct, audiobook1, sweep1, audioBook2, anapana,
%   vipassana, metta (and sweep2 in sessions that ran the second paced
%   block). The log keeps recording after the last block. target_pa is
%   filled only while a sweep runs (the trace the participant followed).
%   The pressure column is POSITIVE during inhalation (lab-confirmed
%   2026-08-25, see shared alignLogToRaw / the alternating6Blocks task).
%
%   Returns struct L with
%     .file           csvPath
%     .t, .p          pressure samples (s, Pa): event rows dropped, strictly
%                     increasing t (duplicate stamps removed)
%     .fsMedian       median sampling rate of the pressure samples (Hz)
%     .tTarget, .target   rows that carry target_pa (s, Pa)
%     .blocks         table, one row per 'start' event in log order:
%                     name (as logged), params (the rest of the start
%                     string), tStart, tEnd (NaN when the block has no
%                     'end'), complete
%     .sweepBreaths   table of every 'breath ...' event: block (the sweep it
%                     belongs to), breath, half, periodSec, depth, amp, gain,
%                     center, t (s, log clock = the target cycle start)
%     .events         table t, block, event of every event row (provenance)
%   Errors (strict) on missing columns, an 'end' without its 'start', a
%   block started twice, or a breath event outside any sweep block.

    opts = detectImportOptions(csvPath, 'Delimiter', ',');
    need = {'time_s', 'pressure_pa', 'target_pa', 'block', 'event'};
    assert(all(ismember(need, opts.VariableNames)), 'parseLog_vipassana:columns', ...
        '%s: expected columns %s, found %s', csvPath, strjoin(need, ','), strjoin(opts.VariableNames, ','));
    % sparse text columns: force the types so detection cannot coerce them
    opts = setvartype(opts, {'block', 'event'}, 'char');
    opts = setvartype(opts, {'time_s', 'pressure_pa', 'target_pa'}, 'double');
    T = readtable(csvPath, opts);

    t  = T.time_s;
    ev = strtrim(string(T.event)); ev(ismissing(ev)) = "";
    bk = strtrim(string(T.block)); bk(ismissing(bk)) = "";

    L = struct();
    L.file = csvPath;

    sig = isfinite(T.pressure_pa) & isfinite(t);
    [L.t, iu] = unique(t(sig), 'sorted');
    pS = T.pressure_pa(sig);
    L.p = pS(iu);
    assert(numel(L.t) > 1000, 'parseLog_vipassana:short', '%s: only %d pressure samples', csvPath, numel(L.t));
    L.fsMedian = 1 / median(diff(L.t));

    tg = isfinite(T.target_pa) & isfinite(t);
    [L.tTarget, it] = unique(t(tg), 'sorted');
    tv = T.target_pa(tg);
    L.target = tv(it);

    isEv = ev ~= "";
    L.events = table(t(isEv), bk(isEv), ev(isEv), 'VariableNames', {'t', 'block', 'event'});
    E = L.events;

    % ---- blocks: start/end pairs ----
    isStart = startsWith(E.event, "start ");
    isEnd   = startsWith(E.event, "end ");
    rest  = extractAfter(E.event(isStart), "start ");
    name  = strings(numel(rest), 1); params = strings(numel(rest), 1);
    for k = 1:numel(rest)
        tok = regexp(char(rest(k)), '^(\S+)\s*(.*)$', 'tokens', 'once');
        name(k) = string(tok{1}); params(k) = string(tok{2});
    end
    assert(numel(unique(lower(name))) == numel(name), 'parseLog_vipassana:dupStart', ...
        '%s: a block was started twice (%s)', csvPath, strjoin(name, ', '));
    tStart = E.t(isStart);
    endName = strtrim(extractAfter(E.event(isEnd), "end "));
    endT = E.t(isEnd);
    tEnd = nan(numel(name), 1);
    used = false(numel(endName), 1);
    for k = 1:numel(name)
        m = find(endName == name(k) & endT >= tStart(k) & ~used, 1);
        if ~isempty(m), tEnd(k) = endT(m); used(m) = true; end
    end
    assert(all(used), 'parseLog_vipassana:orphanEnd', '%s: end event(s) without a start: %s', ...
        csvPath, strjoin(endName(~used), ', '));
    L.blocks = table(name, params, tStart, tEnd, isfinite(tEnd), ...
        'VariableNames', {'name', 'params', 'tStart', 'tEnd', 'complete'});
    L.blocks = sortrows(L.blocks, 'tStart');

    % ---- sweep target cycles ----
    isBr = startsWith(E.event, "breath ");
    S = E(isBr, :);
    n = height(S);
    breath = nan(n, 1); half = nan(n, 1); periodSec = nan(n, 1); depth = nan(n, 1);
    amp = nan(n, 1); gain = nan(n, 1); center = nan(n, 1); blockName = strings(n, 1);
    for k = 1:n
        s = char(S.event(k));
        breath(k)    = kvNum(s, 'breath');
        half(k)      = kvNum(s, 'half');
        periodSec(k) = kvNum(s, 'period');
        depth(k)     = kvNum(s, 'depth');
        amp(k)       = kvNum(s, 'amp');
        gain(k)      = kvNum(s, 'gain');
        center(k)    = kvNum(s, 'center');
        inB = find(L.blocks.tStart <= S.t(k) & (S.t(k) <= L.blocks.tEnd | ~L.blocks.complete), 1, 'last');
        assert(~isempty(inB) && startsWith(lower(L.blocks.name(inB)), "sweep"), ...
            'parseLog_vipassana:breathOutsideSweep', '%s: breath event at %.2f s outside a sweep block', csvPath, S.t(k));
        blockName(k) = L.blocks.name(inB);
    end
    L.sweepBreaths = table(blockName, breath, half, periodSec, depth, amp, gain, center, S.t, ...
        'VariableNames', {'block', 'breath', 'half', 'periodSec', 'depth', 'amp', 'gain', 'center', 't'});

    fprintf('parseLog_vipassana: %s\n   %.1f min of pressure (%.0f Hz), %d blocks, %d sweep target cycles\n', ...
        csvPath, (L.t(end) - L.t(1)) / 60, L.fsMedian, height(L.blocks), n);
    for b = 1:height(L.blocks)
        fprintf('   %-15s %8.1f - %8.1f s\n', L.blocks.name(b), L.blocks.tStart(b), L.blocks.tEnd(b));
    end
end

function v = kvNum(s, key)
    tok = regexp(s, ['(?:^|\s)' key '\s+(\S+)'], 'tokens', 'once');
    if isempty(tok), v = NaN; else, v = str2double(tok{1}); end
end

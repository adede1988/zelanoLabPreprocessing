function [log, blocks] = parse_sniffLogicLog(csvPath)
%PARSE_SNIFFLOGICLOG  Read a SniffLogic behavioral-computer log (Task 8 / D11b).
%
%   [log, blocks] = parse_sniffLogicLog(csvPath)
%
%   File format: columns time_s, pressure_pa, event; ~200 Hz; event rows carry
%   NaN signal. Event strings repeat throughout their block:
%     'active trial time 0.4' -> focused_entrainment
%     'active trial time 0.0' -> focused_noEntrain
%     'start_audio_listen' (audio events generally) -> audiobook
%   A block is the maximal contiguous run of ONE event string, allowing gaps up
%   to 3x that string's median inter-event interval (D11b).
%
%   Returns
%     log    : struct  .t (s, sorted)  .p (pressure_pa, NaN event rows removed)
%     blocks : table   label ("audiobook"/"focused_entrainment"/"focused_noEntrain"),
%              order (1..n by start time), tStart, tEnd (s, log clock)
%   Errors loudly if the block structure is not 1 audiobook + 3 entrain +
%   3 noEntrain (D11c).

    % the event column is sparse text: readtable's type detection can coerce
    % it to numeric (making every event NaN), so force the column types
    opts = detectImportOptions(csvPath, 'Delimiter', ',');
    opts = setvartype(opts, 'event', 'char');
    opts = setvartype(opts, {'time_s', 'pressure_pa'}, 'double');
    T = readtable(csvPath, opts);
    t = T.time_s;
    p = T.pressure_pa;
    ev = strtrim(string(T.event));
    ev(ismissing(ev)) = "";

    sig = isfinite(p);
    tS = t(sig); pS = p(sig);
    % interp1 downstream needs strictly increasing sample points
    [tS, iu] = unique(tS, 'sorted');
    log = struct('t', tS, 'p', pS(iu));

    kinds = { ...
        "active trial time 0.4", "focused_entrainment"; ...
        "active trial time 0.0", "focused_noEntrain"};
    % audio: any event mentioning audio counts toward the audiobook block
    isAudio = contains(ev, "audio");

    segs = table('Size', [0 4], 'VariableTypes', {'string', 'double', 'double', 'double'}, ...
                 'VariableNames', {'label', 'tStart', 'tEnd', 'nEvents'});
    for k = 1:size(kinds, 1) + 1
        if k <= size(kinds, 1)
            m = ev == kinds{k, 1};
            lab = kinds{k, 2};
        else
            m = isAudio;
            lab = "audiobook";
        end
        tt = sort(t(m));    % event rows are not strictly time-ordered in the log
        if isempty(tt), continue; end
        % fixed tolerance: intra-block events repeat every ~0.2 s (display
        % stalls of a few seconds occur), while between-block rating gaps are
        % >= ~80 s - 30 s separates cleanly where a 3x-median rule fragments
        gapTol = 30;
        brk = find(diff(tt) > gapTol);
        s0 = [1; brk + 1];
        s1 = [brk; numel(tt)];
        for b = 1:numel(s0)
            n = s1(b) - s0(b) + 1;
            if n < 10, continue; end     % ignore stray single events
            segs(end+1, :) = {lab, tt(s0(b)), tt(s1(b)), n}; %#ok<AGROW>
        end
    end
    segs = sortrows(segs, 'tStart');

    blocks = table();
    blocks.label  = segs.label;
    blocks.order  = (1:height(segs))';
    blocks.tStart = segs.tStart;
    blocks.tEnd   = segs.tEnd;

    nA = sum(blocks.label == "audiobook");
    nE = sum(blocks.label == "focused_entrainment");
    nN = sum(blocks.label == "focused_noEntrain");
    fprintf('parse_sniffLogicLog: %d blocks (%d audiobook / %d entrain / %d noEntrain)\n', ...
        height(blocks), nA, nE, nN);
    for b = 1:height(blocks)
        fprintf('  %d %-20s %7.1f - %7.1f s (%.1f min)\n', blocks.order(b), ...
            blocks.label(b), blocks.tStart(b), blocks.tEnd(b), ...
            (blocks.tEnd(b) - blocks.tStart(b)) / 60);
    end
    assert(nA == 1 && nE == 3 && nN == 3 && height(blocks) == 7, ...
        'parse_sniffLogicLog:badStructure', ...
        'expected 1 audiobook + 3 entrain + 3 noEntrain blocks, got %d/%d/%d (D11c)', nA, nE, nN);
end

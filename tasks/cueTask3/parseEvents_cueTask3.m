function [ttl, info] = parseEvents_cueTask3(pd, fsRaw, nPerRun, hasResp, trlStart)
%PARSEEVENTS_CUETASK3  Strict parse of the cueTask3 event (DAQ) channel.
%
%   [ttl, info] = parseEvents_cueTask3(pd, fsRaw, nPerRun, hasResp, trlStart)
%
%   pd        1 x N raw event channel (NaN-free; the DAQ pulses are low-going)
%   fsRaw     its sample rate (Hz)
%   nPerRun   trials per run, in recording order (one result file per run)
%   hasResp   nTrial x 1 logical: the result files list an answer (response
%             ~= 999, outMat_to_table's code for "no key press")
%   trlStart  nTrial x 1 task-laptop trial-start clock (GetSecs, s) from the
%             result files: its within-run intervals must match the pulses'
%
%   ttl   nTrial x 5 RAW samples (pulse onsets): trialStart (the cue-word
%         pulse), response (NaN = no key press), sniff1, sniff2, sniff3
%   info  struct: pulses (table onsetRaw, durSec, cls, role, run, trial),
%         nPulses, nIgnored (crossings outside the width window),
%         sniffGapSec [min median max], cueToSniff1Sec [min median max],
%         clockResidualMaxSec (|pulse - laptop| trial-start interval mismatch,
%         worst over both runs), rule (text)
%
%   Protocol (OBE_task_backup\tasks\olf_cuetask\src\olf_cuetask_3sniff.m):
%   per run a 6 x 0.3-s start code (0.1-s gaps); per trial one 0.3-s pulse at
%   the cue word, ~5 s later three 0.5-s SNIFF pulses 1.1 s apart (onset to
%   onset), and a 0.7-s pulse at the Yes/No key press (none when the 5-s
%   response window passes without one); per run a 2 x 0.3-s end code.
%   Pulse detection = cueTask_makeOutDat's: z-score, downward crossing of
%   -1.5 SD to the next upward crossing, widths outside 0.15-0.75 s ignored,
%   classes by width < 0.425 s code/cue (c), 0.425-0.625 s sniff (s),
%   > 0.625 s response (r) - the cue task's 300 / 850 / 1250 / 1500-sample cuts
%   at 2 kHz. The class sequence must be exactly
%       [ c^6 (c s s s r?){nPerRun(k)} c^2 ] for every run k
%   with r present exactly where the result files have an answer; anything
%   else errors (strict: a deviation is a data problem to look at).

    pd = pd(:)';
    z  = (pd - mean(pd)) / std(pd);
    downs = find(z(1:end-1) > -1.5 & z(2:end) < -1.5);
    ups   = find(z(1:end-1) < -1.5 & z(2:end) > -1.5);
    % pair every downward crossing with the next upward one
    on = []; off = [];
    for k = 1:numel(downs)
        u = ups(find(ups > downs(k), 1));
        if isempty(u), break; end
        if ~isempty(off) && downs(k) < off(end), continue; end
        on(end+1) = downs(k); off(end+1) = u; %#ok<AGROW>
    end
    w = (off - on) / fsRaw;
    keep = w >= 0.15 & w <= 0.75;
    nIgnored = sum(~keep);
    on = on(keep); w = w(keep);
    cls = repmat('c', 1, numel(w));
    cls(w >= 0.425 & w <= 0.625) = 's';
    cls(w > 0.625) = 'r';

    nTrial = sum(nPerRun);
    if numel(hasResp) ~= nTrial || numel(trlStart) ~= nTrial
        error('parseEvents_cueTask3:behSize', 'behaviour has %d / %d rows for %d trials', ...
            numel(hasResp), numel(trlStart), nTrial);
    end
    ttl  = nan(nTrial, 5);
    role = strings(numel(on), 1); runOf = nan(numel(on), 1); trialOf = nan(numel(on), 1);
    pos = 1; tr = 0;
    for k = 1:numel(nPerRun)
        expect('cccccc', sprintf('run %d start code', k));
        role(pos:pos+5) = "start"; runOf(pos:pos+5) = k; pos = pos + 6;
        for t = 1:nPerRun(k)
            tr = tr + 1;
            expect('csss', sprintf('trial %d (run %d trial %d)', tr, k, t));
            ttl(tr, [1 3 4 5]) = on(pos:pos+3);
            role(pos:pos+3) = ["cue" "sniff1" "sniff2" "sniff3"];
            runOf(pos:pos+3) = k; trialOf(pos:pos+3) = tr;
            pos = pos + 4;
            gotR = pos <= numel(cls) && cls(pos) == 'r';
            if gotR ~= logical(hasResp(tr))
                error('parseEvents_cueTask3:response', ...
                    'trial %d: response pulse %d but result file answer %d', tr, gotR, hasResp(tr));
            end
            if gotR
                ttl(tr, 2) = on(pos);
                role(pos) = "response"; runOf(pos) = k; trialOf(pos) = tr;
                pos = pos + 1;
            end
        end
        expect('cc', sprintf('run %d end code', k));
        role(pos:pos+1) = "end"; runOf(pos:pos+1) = k; pos = pos + 2;
    end
    if pos <= numel(cls)
        error('parseEvents_cueTask3:extraPulses', '%d pulses after the last end code (%s)', ...
            numel(cls) - pos + 1, cls(pos:end));
    end

    % --- timing checks against the protocol ---
    sg = diff(ttl(:, 3:5), 1, 2) / fsRaw;
    if any(sg(:) < 1.0 | sg(:) > 1.2)
        error('parseEvents_cueTask3:sniffGap', 'sniff-pulse spacing outside 1.0-1.2 s (%.3f-%.3f s)', ...
            min(sg(:)), max(sg(:)));
    end
    c2s = (ttl(:, 3) - ttl(:, 1)) / fsRaw;
    if any(c2s < 2 | c2s > 10)
        error('parseEvents_cueTask3:cueToSniff', 'cue -> first sniff pulse outside 2-10 s (%.2f-%.2f s)', ...
            min(c2s), max(c2s));
    end
    r2 = (ttl(:, 2) - ttl(:, 5)) / fsRaw;
    if any(r2 < 0 | r2 > 8)
        error('parseEvents_cueTask3:response', 'third sniff -> response pulse outside 0-8 s');
    end
    % trial-start intervals: event channel vs the task laptop's clock
    res = [];
    first = [0 cumsum(nPerRun(:)')];
    for k = 1:numel(nPerRun)
        ix = first(k)+1 : first(k+1);
        res = [res; diff(ttl(ix, 1)) / fsRaw - diff(trlStart(ix))]; %#ok<AGROW>
    end
    if any(abs(res) > 0.5)
        error('parseEvents_cueTask3:clock', ...
            'trial-start pulse intervals differ from the result files'' trl_start by up to %.3f s', max(abs(res)));
    end

    info = struct();
    info.pulses = table(on(:), w(:), cls(:), role, runOf, trialOf, ...
        'VariableNames', {'onsetRaw', 'durSec', 'cls', 'role', 'run', 'trial'});
    info.fsRaw = fsRaw;
    info.nPulses = numel(on);
    info.nIgnored = nIgnored;
    info.nPerRun = nPerRun(:)';
    info.sniffGapSec = [min(sg(:)) median(sg(:)) max(sg(:))];
    info.cueToSniff1Sec = [min(c2s) median(c2s) max(c2s)];
    info.clockResidualMaxSec = max(abs(res));
    info.rule = ['z-score, -1.5 SD downward crossing to the next upward one, widths 0.15-0.75 s; ' ...
                 'c < 0.425 s <= s <= 0.625 s < r; per run c^6 (c s s s r?)^n c^2'];

    function expect(pat, what)
        n = numel(pat);
        if pos + n - 1 > numel(cls) || ~strcmp(cls(pos:pos+n-1), pat)
            got = cls(pos:min(numel(cls), pos+n-1));
            error('parseEvents_cueTask3:sequence', '%s: expected "%s" at pulse %d, found "%s"', ...
                what, pat, pos, got);
        end
    end
end

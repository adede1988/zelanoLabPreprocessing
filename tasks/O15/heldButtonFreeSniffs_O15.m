function [sniffs, outDat] = heldButtonFreeSniffs_O15(sniffs, R, P, outDat)
%HELDBUTTONFREESNIFFS_O15  Free sniffs of the O15 held-button protocol.
%
%   [sniffs, outDat] = heldButtonFreeSniffs_O15(sniffs, R, P, outDat)
%
%   Called by O15PreProc_main after detect_sniffs_from_TTLs when outDat has a
%   buttonDown table (detect_ttls_O15 with P.ttl.protocol = 'heldButton';
%   tasks_261014 task 10). In that protocol the experimenter HOLDS the button
%   while the odor bottle is under the participant's nose, so a free event is
%   a button-down period, not one pulse per observed sniff: every inhale that
%   happens during a period is a free sniff. detect_sniffs_from_TTLs has
%   already found the 'start' (after the start cue, TTL free1) and 'confirm'
%   sniffs; this adds the 'free' ones.
%
%   Inhale candidates use the same detector as detect_sniffs_from_TTLs: an
%   upward crossing of R.testSig over P.respThresh (onset = first sample above
%   it). A candidate is a free sniff of button-down period w when its rising
%   phase overlaps the period: onset <= period offset AND its inhale peak
%   (max of R.smoothR within peakWinSec after the onset) >= period onset, with
%   the onset no more than lookbackSec before the period onset (the
%   experimenter often presses as the inhale starts: DB_3 has sniffs whose
%   testSig crossing precedes the press by ~0.5 s). Each candidate is used once
%   (first period wins) and never when it already is the trial's start or
%   confirm sniff. refine_onsets_with_phase later refines every onset as usual,
%   and resolveHeldButtonSniffs_O15 then keeps one free sniff per inhale where
%   two rows of a trial were refined to the same onset (2026-10-21).
%
%   Options P.ttl.heldSniff (all optional): lookbackSec (2), peakWinSec (1.5);
%   resolveHeldButtonSniffs_O15 reads mergeDropFrac / baseSec / peakMaxSec.
%
%   sniffs rows (detect_sniffs_from_TTLs layout): 1 onset, 2 trial, 3 index
%   within trial (renumbered here in time order), 4 offset from the marker
%   (free: onset - period onset, samples), 5 buttonDown row (free sniffs;
%   0 otherwise), 6 type (1 start, 2 free, 3 confirm), 7 unused.
%   outDat.buttonDown gains nFree; outDat.ttlInfo.heldSniff records the rule.
%   The per-trial QC figures sniffsTrial<k>.jpg (period shading) are drawn by
%   resolveHeldButtonSniffs_O15, after the refinement (2026-10-21).

    o = struct('lookbackSec', 2, 'peakWinSec', 1.5);
    if isfield(P, 'ttl') && isfield(P.ttl, 'heldSniff')
        fn = fieldnames(P.ttl.heldSniff);
        for i = 1:numel(fn), o.(fn{i}) = P.ttl.heldSniff.(fn{i}); end
    end
    fs = outDat.fs;
    BD = outDat.buttonDown;
    x = R.testSig(:)';
    up = find(x(1:end-1) < P.respThresh & x(2:end) > P.respThresh) + 1;
    pk = zeros(size(up));
    for i = 1:numel(up)
        [~, m] = max(R.smoothR(up(i):min(numel(R.smoothR), up(i) + round(o.peakWinSec*fs))));
        pk(i) = up(i) + m - 1;
    end

    sniffs = sniffs(sniffs(:,6) > 0, :);   % drop unfilled preallocated rows
    taken = false(size(up));
    newRows = zeros(0, 7);
    BD.nFree = zeros(height(BD), 1);
    for w = 1:height(BD)
        on = BD.onset(w); off = BD.offset(w); tr = BD.trial(w);
        used = sniffs(sniffs(:,2) == tr, 1);
        c = find(~taken & up <= off & up >= on - round(o.lookbackSec*fs) & pk >= on & ...
                 ~ismember(up, used));
        taken(c) = true;
        BD.nFree(w) = numel(c);
        for j = 1:numel(c)
            newRows(end+1, :) = [up(c(j)), tr, 0, up(c(j)) - on, w, 2, 0]; %#ok<AGROW>
        end
    end
    sniffs = sortrows([sniffs; newRows], [2 1]);
    for tr = unique(sniffs(:,2))'
        m = sniffs(:,2) == tr;
        sniffs(m, 3) = (1:sum(m))';
    end
    outDat.buttonDown = BD;
    if ~isfield(outDat, 'ttlInfo'), outDat.ttlInfo = struct; end
    o.respThresh = P.respThresh;
    o.rule = ['free sniff = testSig upward crossing of respThresh whose [onset, inhale peak] ' ...
              'overlaps a button-down period (onset >= period onset - lookbackSec)'];
    outDat.ttlInfo.heldSniff = o;
end

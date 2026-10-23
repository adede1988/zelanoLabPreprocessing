function outDat = resolveHeldButtonSniffs_O15(outDat, R, P)
%RESOLVEHELDBUTTONSNIFFS_O15  One free sniff per inhale after the onset refinement (O15 held-button protocol).
%
%   outDat = resolveHeldButtonSniffs_O15(outDat, R, P)
%
%   Called by O15PreProc_main right after refine_onsets_with_phase when outDat has a buttonDown table
%   (P.ttl.protocol = 'heldButton'; 2026-10-21, g3be2). heldButtonFreeSniffs_O15 makes every testSig crossing
%   whose rise overlaps a button-down period a free sniff; refine_onsets_with_phase then puts each sniff's
%   finalOnset at the steepest rise in the adjWin before the first upward zero crossing of the 1-Hz
%   respiration phase after its coarse onset. Two inhales 0.6-1 s apart within one button-down period, or an
%   end-exhale pause before the inhale, can leave the 1-Hz phase with ONE
%   cycle for two crossings, so both refine to the same onset (260917_OBE_NWU_RC_2, 2026-10-20: 9 pairs):
%     a) two crossings on ONE inhale (the slow return from the exhale, a pause, then the inhale proper);
%     b) two inhales separated by an exhale, where the later crossing's search window reaches back into the
%        earlier inhale's (steeper) rise.
%   Only rows that share a finalOnset are touched, so a session without such collisions is unchanged.
%
%   Rule, per group of sniff rows of one trial with an identical finalOnset f (at least one of them free):
%   the coarse onsets (seeds) are taken in time order and split into inhales - consecutive seeds c1 < c2 are
%   two inhales when R.smoothR falls between them by >= mergeDropFrac of the pair's excursion (the largest
%   drop below its running maximum on [c1, c2], over max(smoothR(c1:c2)) - min(smoothR(c1 - baseSec : c2)));
%   the separating trough is the sample of that largest drop.
%     - The inhale that holds f keeps it, with ONE row: its start / confirm row if it has one, else the free
%       seed nearest to f. Its other free seeds are dropped (one free sniff per inhale).
%     - Each other inhale keeps one free row whose finalOnset is re-refined inside its own inhale: from the
%       separating trough to its own peak (a later inhale: the first maximum after the trough before smoothR
%       falls by mergeDropFrac of its rise, searched up to peakMaxSec; an earlier inhale: the maximum between
%       its first seed and the trough), with the train-mode rule of the shared refine_onsets_with_phase
%       (steepest 20-sample rise, at most adjWin back from the peak). The kept row is the seed nearest to the
%       new onset; the inhale's other free seeds are dropped.
%   Start / confirm rows are never dropped or re-refined: a group in which one of them would need it is an
%   error, as is any identical finalOnset left in a trial afterwards.
%
%   Options P.ttl.heldSniff (all optional; heldButtonFreeSniffs_O15 reads the same struct): mergeDropFrac
%   (0.35), baseSec (1), peakMaxSec (1.5).
%
%   Output: behDat without the dropped rows (wiTriali renumbered in time order, adjust / finalOnset of the
%   re-refined rows replaced), buttonDown.nFree recounted, outDat.ttlInfo.heldResolve = the options, the rule
%   and actions (one row per row of a group: trial, sniffOnset, buttonWindow, label, group, inhale, dropFrac
%   (the split statistic before this seed; NaN for a group's first seed), action kept / dropped / rerefined,
%   finalBefore, finalAfter, inhaleTrough, inhalePeak (samples; NaN unless re-refined)). Per-trial QC figures
%   sniffsTrial<k>.jpg are drawn here (button-down shading, coarse and final onsets, dropped seeds).

    o = struct('mergeDropFrac', 0.35, 'baseSec', 1, 'peakMaxSec', 1.5);
    if isfield(P, 'ttl') && isfield(P.ttl, 'heldSniff')
        for f = intersect(fieldnames(o), fieldnames(P.ttl.heldSniff))'
            o.(f{1}) = P.ttl.heldSniff.(f{1});
        end
    end
    fs = outDat.fs;
    s  = R.smoothR(:)';
    T  = numel(s);
    B  = outDat.behDat;
    lb = string(B.sniffLabel);
    isFree = lb == "free";
    hasBW = ismember('buttonWindow', B.Properties.VariableNames);
    if ~hasBW, error('resolveHeldButtonSniffs_O15:noButtonWindow', 'behDat has no buttonWindow column'); end

    keep = true(height(B), 1);
    finalBefore = B.finalOnset;
    act = cell(0, 13);
    gNum = 0;
    for tr = unique(B.n)'
        idx = find(B.n == tr);
        [u, ~, g] = unique(B.finalOnset(idx));
        for q = find(accumarray(g, 1) > 1)'
            G = idx(g == q);
            if ~any(isFree(G))
                error('resolveHeldButtonSniffs_O15:cuedCollision', ...
                    'trial %d: start / confirm rows %s share finalOnset %d', tr, mat2str(G'), u(q));
            end
            gNum = gNum + 1;
            fShared = u(q);
            [~, ord] = sort(B.sniffOnset(G)); G = G(ord); c = B.sniffOnset(G);
            % split the seeds into inhales
            inh = ones(numel(G), 1); ddf = nan(numel(G), 1); bnd = [];
            for j = 1:numel(G) - 1
                seg = s(c(j):c(j + 1));
                ex  = max(seg) - min(s(max(1, c(j) - round(o.baseSec * fs)):c(j + 1)));
                [dd, m] = max(cummax(seg) - seg);    % largest drop below the running max, and where
                ddf(j + 1) = dd / max(ex, eps);
                if ddf(j + 1) >= o.mergeDropFrac
                    bnd(end + 1) = c(j) + m - 1; %#ok<AGROW>  the separating trough
                    inh(j + 1) = inh(j) + 1;
                else
                    inh(j + 1) = inh(j);
                end
            end
            kf = 1 + sum(fShared > bnd);   % the inhale that holds the shared onset
            action = repmat("dropped", numel(G), 1);
            fNew = nan(numel(G), 1); lo = nan(numel(G), 1); hi = nan(numel(G), 1);
            for k = 1:max(inh)
                m = find(inh == k);
                cued = m(~isFree(G(m)));
                if k == kf
                    if ~isempty(cued)
                        kk = cued(1);
                    else
                        [~, i] = min(abs(c(m) - fShared)); kk = m(i);
                    end
                    action(kk) = "kept"; fNew(kk) = fShared;
                    continue
                end
                if ~isempty(cued)
                    error('resolveHeldButtonSniffs_O15:cuedRerefine', ...
                        'trial %d: %s row %d would need re-refining (its inhale does not hold the shared onset)', ...
                        tr, lb(G(cued(1))), G(cued(1)));
                end
                if k > kf
                    a0 = bnd(k - 1);
                    if k < max(inh)
                        [~, i] = max(s(a0:bnd(k))); pk = a0 + i - 1;
                    else
                        pk = ownPeak(s, a0, min(T, a0 + round(o.peakMaxSec * fs)), o.mergeDropFrac);
                    end
                else
                    [~, i] = max(s(c(m(1)):bnd(k))); pk = c(m(1)) + i - 1;
                    [~, i] = min(s(max(1, pk - P.adjWin):pk)); a0 = max(1, pk - P.adjWin) + i - 1;
                end
                % the shared train-mode rule (steepest rise between trough and peak) for each seed of the inhale
                tmp = struct('fs', fs);
                tmp.behDat = table(c(m), repmat(a0, numel(m), 1), repmat(pk, numel(m), 1), ...
                    'VariableNames', {'sniffOnset', 'inhaleTrough', 'inhalePeak'});
                Pt = P; Pt.sniffTrain = struct();
                tmp = refine_onsets_with_phase(tmp, R, Pt);
                [~, i] = min(abs(tmp.behDat.adjust));
                kk = m(i);
                action(kk) = "rerefined"; fNew(kk) = tmp.behDat.finalOnset(i); lo(kk) = a0; hi(kk) = pk;
                B.finalOnset(G(kk)) = tmp.behDat.finalOnset(i);
                B.adjust(G(kk))     = tmp.behDat.adjust(i);
            end
            keep(G(action == "dropped")) = false;
            for j = 1:numel(G)
                act(end + 1, :) = {tr, c(j), B.buttonWindow(G(j)), lb(G(j)), gNum, inh(j), ddf(j), ...
                    action(j), finalBefore(G(j)), fNew(j), lo(j), hi(j), G(j)}; %#ok<AGROW>
            end
        end
    end

    vn = {'trial', 'sniffOnset', 'buttonWindow', 'label', 'group', 'inhale', 'dropFrac', 'action', ...
          'finalBefore', 'finalAfter', 'inhaleTrough', 'inhalePeak', 'rowBefore'};
    A = table('Size', [size(act, 1) numel(vn)], 'VariableNames', vn, 'VariableTypes', ...
        {'double', 'double', 'double', 'string', 'double', 'double', 'double', 'string', ...
         'double', 'double', 'double', 'double', 'double'});
    if ~isempty(act)
        for v = 1:numel(vn)
            if isstring(A.(vn{v})), A.(vn{v}) = string(act(:, v)); else, A.(vn{v}) = cell2mat(act(:, v)); end
        end
    end
    dropped = B(~keep, :);
    B = B(keep, :);
    for tr = unique(B.n)'
        m = B.n == tr;
        B.wiTriali(m) = (1:sum(m))';
        if numel(unique(B.finalOnset(m))) < sum(m)
            error('resolveHeldButtonSniffs_O15:collisionLeft', 'trial %d still has identical finalOnsets', tr);
        end
    end
    outDat.behDat = B;
    BD = outDat.buttonDown;
    fr = B.buttonWindow(string(B.sniffLabel) == "free");
    BD.nFree = accumarray(fr(:), 1, [height(BD) 1]);
    outDat.buttonDown = BD;
    if ~isfield(outDat, 'ttlInfo'), outDat.ttlInfo = struct; end
    h = o;
    h.rule = ['rows of a trial with an identical finalOnset: seeds split into inhales where smoothR drops by ' ...
              '>= mergeDropFrac of the excursion; one row per inhale; the inhale holding the shared onset keeps ' ...
              'it, every other inhale is re-refined between its trough and its peak (train-mode rule)'];
    h.nGroups = gNum;
    h.nDropped = sum(A.action == "dropped");
    h.nRerefined = sum(A.action == "rerefined");
    h.actions = A;
    outDat.ttlInfo.heldResolve = h;

    plotTrials(outDat, R, P, dropped);
end

function pk = ownPeak(s, a0, lim, frac)
% first maximum after a0 before smoothR falls by frac of its rise from a0 (searched up to lim)
    rm = s(a0); pk = a0;
    for k = a0 + 1:lim
        if s(k) > rm, rm = s(k); pk = k; end
        if s(k) < rm - frac * (rm - s(a0)), break; end
    end
end

function plotTrials(outDat, R, P, dropped)
% per-trial QC figures (replace detect_sniffs_from_TTLs' versions): button-down periods, coarse onsets
% (dashed) and finalOnsets (solid) per sniff type, dropped seeds (grey dotted)
    fs = outDat.fs; TTL = outDat.TTL; BD = outDat.buttonDown; B = outDat.behDat;
    x = R.testSig(:)'; T = numel(x);
    cols = {[0 0 1], [0 .6 0], [1 0 0]};
    for tr = 1:height(TTL)
        a = max(1, TTL.trialStart(tr) - 2*fs);
        b = min(T, TTL.confirmSniff(tr) + 4*fs);
        hF = figure('visible', 'off', 'position', [0 0 1600 500]);
        hold on
        yl = [min(R.smoothR(a:b)) max(R.smoothR(a:b))];
        if yl(2) <= yl(1), yl = yl + [-1 1]; end
        bw = find(BD.trial == tr);
        for i = bw'
            patch(([BD.onset(i) BD.offset(i) BD.offset(i) BD.onset(i)] - a) ./ fs, ...
                yl([1 1 2 2]), [1 .8 .5], 'EdgeColor', 'none');
        end
        plot(((a:b) - a) ./ fs, R.smoothR(a:b), 'k')
        mk = [TTL.trialStart(tr), TTL.free1(tr), TTL.buttonPress(tr), TTL.confirmSniff(tr)];
        xline((mk - a) ./ fs, '--', {'start', 'cue', 'press', 'confirm'})
        ss = B(B.n == tr, :);
        for k = 1:3
            r = ss.sniffType == k;
            if any(r)
                xline((ss.sniffOnset(r) - a) ./ fs, ':', 'color', cols{k}, 'linewidth', 1.5);
                xline((ss.finalOnset(r) - a) ./ fs, '-', 'color', cols{k}, 'linewidth', 2);
            end
        end
        dd = dropped(dropped.n == tr, :);
        if ~isempty(dd), xline((dd.sniffOnset - a) ./ fs, ':', 'color', [.5 .5 .5], 'linewidth', 1.5); end
        yyaxis right
        plot(((a:b) - a) ./ fs, x(a:b), 'color', [.5 .8 .5]); yline(P.respThresh, ':')
        xlabel('s from trial start - 2 s')
        title({sprintf('%s trial %d (held-button): %d periods (%.1f s), sniffs start %d / free %d / confirm %d, %d seeds dropped', ...
            outDat.sessID, tr, numel(bw), sum(BD.durSec(bw)), sum(ss.sniffType == 1), sum(ss.sniffType == 2), ...
            sum(ss.sniffType == 3), height(dd)), ['blue start, green free, red confirm: dotted = coarse onset, ' ...
            'solid = finalOnset; grey dotted = dropped seed (same inhale); orange = button down; right axis testSig + respThresh']}, ...
            'interpreter', 'none')
        saveas(hF, fullfile(outDat.figs, ['sniffsTrial' num2str(tr) '.jpg']));
        close(hF)
    end
end

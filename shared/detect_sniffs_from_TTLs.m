function [outSniffs] = detect_sniffs_from_TTLs(R, P, outDat)

    %outDat.TTL      table with col1: trialStart
    %                           col2: buttonpress
    %                           col3-20: sniffs

    outSniffs = zeros(30, 7);
    TTL = outDat.TTL;
    %col 1: sniff onset index into data
    %col 2: trial number
    %col 3: sniff within trial number
    %col 4: off from TTL by
    %col 6: sniff type 1 = start, 2 = free, 3 = confirm
    %col 7: adjustment for phase align
    oi = 1; %index variable for out sniffs

    % Train mode (opt-in, cueTask3 2026-10-16): P.sniffTrain (a struct set by
    % applyParams; struct() = the defaults in detectSniffTrain below) marks a
    % task whose sniff cues come as a rapid train within a trial (cueTask3:
    % 3 SNIFF cues 1.1 s apart). The legacy search below (an upward crossing
    % of the 1-s-smoothed deflection metric R.testSig past P.respThresh)
    % cannot separate sniffs that close together - the metric stays above
    % threshold between them - so each target is instead located on the
    % smoothed trace itself, with two more output columns (8 inhale trough,
    % 9 inhale peak) that refine_onsets_with_phase uses in the same mode.
    % Absent / empty P.sniffTrain = the legacy search, unchanged.
    trainMode = isfield(P, 'sniffTrain') && ~isempty(P.sniffTrain);

    if trainMode
        outSniffs = detectSniffTrain(R, P, TTL);
    else
        for triali = 1:size(TTL,1)
            targets = TTL(triali, 3:end);
            targets = table2array(targets);
            targets(isnan(targets)) = [];
            targets = sort(targets);
            sniffi = 1;
            for tt = 1:length(targets)
                if tt == 1 || tt == length(targets)
                    %first and last sniff! should be after TTL
                    startSearch = targets(tt) - 30 - P.cuedBackBuff;
                    endSearch = targets(tt)+2000 - 30; %search window of 4s
                    val = find(R.testSig(startSearch:endSearch-1)<...
                                                        P.respThresh  & ...
                        R.testSig(startSearch+1:endSearch) > P.respThresh, 1);
                    if tt == 1
                        type = 1;
                    else
                        type = 3;
                    end

                else
                    %free sniffs! should be before TTL
                    startSearch = targets(tt)- 30 - 1000; %search window of 2s
                    endSearch = targets(tt) -30 + 300;

                    val = find(R.testSig(startSearch:endSearch-1)<...
                                                        P.respThresh & ...
                        R.testSig(startSearch+1:endSearch) > P.respThresh);
                    % val(val<16) = 16;
                    % val(val>1285) = 1285;
                    if length(val)>1
                        testSpace = R.testSig(startSearch:endSearch-1);
                        L = length(testSpace);
                        stopAt = arrayfun(@(x) min([x+15, L]),...
                                            val);
                        startAt= arrayfun(@(x) max([x-15, 1]), val);
                        sizes = testSpace(stopAt) - testSpace(startAt);
                        [~, maxSniff] = max(sizes);
                        val = val(maxSniff);
                    end
                    type = 2;
                end


                    %was a sniff found? if yes then find overall idx
                    %val is how far from the start search the sniff happened
                if ~isempty(val)
                    targidx = val + startSearch;

                    %col 1: sniff onset index
                    outSniffs(oi,1) = targidx;
                    %col 2: trial number
                    outSniffs(oi,2) = triali;
                    %col 3: sniff within trial number
                    outSniffs(oi,3) = sniffi;
                    sniffi = sniffi + 1;
                    %col 4: off from TTL by
                    if type == 2
                        outSniffs(oi,4) = - 30 - 1000 +val;
                    else
                        outSniffs(oi,4) = val - 30 - P.cuedBackBuff;
                    end
                    %col 6: sniff type 1 = start, 2 = free, 3 = confirm
                    outSniffs(oi,6) = type;
                    oi = oi + 1;
                end
            end
        end
    end


    TTL = table2array(TTL);


    for triali  = 1:size(TTL,1)
        figure('visible', false)
        idx = TTL(triali, 1);
        endidx = TTL(triali,3)+P.fs_target*4;
        rspTrial = R.smoothR(idx:endidx);
        testHere = R.testSig(idx+30:endidx+30);

        plot(rspTrial )

        idx = TTL(triali,3:end) - TTL(triali, 1);
        idx(isnan(idx)) = [];
        xline(idx, 'linewidth', 2)
        title([outDat.sessID ...
            ' backBuff: ' num2str(P.cuedBackBuff) ...
            ' rspThresh:' num2str(P.respThresh) ...
            ' trial:' num2str(triali)], 'interpreter', 'none')
        curSniffs = outSniffs(outSniffs(:,2) == triali, 1);
        if ~isempty(curSniffs)
            xline(curSniffs - TTL(triali, 1), ...
                'color', 'green', 'linewidth', 2);
        end
        if trainMode && ~isempty(curSniffs)
            % train mode: each detected sniff's inhale trough (v) and peak (^)
            hold on
            bnd = outSniffs(outSniffs(:,2) == triali, 8:9);
            plot(bnd(:,1) - TTL(triali, 1) + 1, R.smoothR(bnd(:,1)), 'cv', 'MarkerFaceColor', 'c')
            plot(bnd(:,2) - TTL(triali, 1) + 1, R.smoothR(bnd(:,2)), 'm^', 'MarkerFaceColor', 'm')
        end
        yyaxis right
        plot(testHere)
        saveas(gcf,fullfile(outDat.figs, ...
                    ['sniffsTrial' num2str(triali) '.jpg']));
    end


end


function outSniffs = detectSniffTrain(R, P, TTL)
% Train mode of detect_sniffs_from_TTLs (cueTask3, 2026-10-16). For every
% sniff target T_j of a trial (TTL columns 3:end, which must increase along
% the row; NaN = no target) on the smoothed respiration R.smoothR:
%   peak   = its maximum in [T_j - peakPreSec, T_(j+1) - nextGuardSec]
%            ([T_j - peakPreSec, T_j + lastPostSec] for the trial's last
%            target); it must be a true local maximum (not on a window edge)
%   trough = its minimum between the previous target's peak (first target:
%            T_j - 30 - P.cuedBackBuff, the legacy cued search start) and
%            this peak
%   onset  = the first sample after the trough where R.smoothR has risen by
%            riseStartFrac of the trough-to-peak amplitude - the coarse onset;
%            refine_onsets_with_phase (train mode) puts the final onset at the
%            steepest rise between trough and peak.
% A target gets no sniff (no row, like an undetected legacy sniff) when its
% peak is on a window edge or its rise is below minRiseFrac x the median rise
% of all the session's train sniffs.
% P.respThresh is not used in this mode; P.cuedBackBuff bounds the first
% target's trough search; P.fs_target converts the seconds.
% Output (one row per detected sniff, in trial / target order):
%   1 coarse onset, 2 trial (TTL row), 3 the target's position in the train
%   (= its cue number, kept when another target of the trial is undetected),
%   4 onset - T_j, 6 sniff type 1 (cued), 8 inhale trough, 9 inhale peak
%   (columns 5 and 7 zero, as in the legacy output).

    o = struct('peakPreSec', 0.2, 'nextGuardSec', 0.1, 'lastPostSec', 1.2, ...
               'riseStartFrac', 0.1, 'minRiseFrac', 0.2);
    fn = fieldnames(P.sniffTrain);
    for k = 1:numel(fn)
        if ~isfield(o, fn{k})
            error('detect_sniffs_from_TTLs:badTrainOpt', 'unknown P.sniffTrain field "%s"', fn{k});
        end
        o.(fn{k}) = P.sniffTrain.(fn{k});
    end
    fs = P.fs_target;
    s  = R.smoothR;
    T  = numel(s);
    tg = table2array(TTL(:, 3:end));
    [nTr, nTg] = size(tg);

    pk = nan(nTr, nTg); tr = nan(nTr, nTg); okPk = false(nTr, nTg);
    for i = 1:nTr
        row = tg(i, :);
        have = find(~isnan(row));
        if any(diff(row(have)) <= 0)
            error('detect_sniffs_from_TTLs:trainOrder', ...
                'trial %d: sniff targets must increase along the TTL row', i);
        end
        prevPk = -Inf;
        for q = 1:numel(have)
            j  = have(q);
            lo = max(1, row(j) - round(o.peakPreSec * fs));
            if q < numel(have)
                hi = row(have(q + 1)) - round(o.nextGuardSec * fs);
            else
                hi = row(j) + round(o.lastPostSec * fs);
            end
            hi = min(T, hi);
            if hi - lo < 2, continue; end
            [~, m] = max(s(lo:hi));
            p   = lo + m - 1;
            tlo = max([row(j) - 30 - P.cuedBackBuff, prevPk, 1]);
            if tlo >= p, continue; end
            [~, m2] = min(s(tlo:p));
            pk(i, j)   = p;
            tr(i, j)   = tlo + m2 - 1;
            okPk(i, j) = m > 1 && p < hi;
            if okPk(i, j), prevPk = p; end
        end
    end

    amp = nan(nTr, nTg);
    amp(okPk) = s(pk(okPk)) - s(tr(okPk));
    ok = okPk & amp > 0;
    if any(ok(:))
        ok = ok & amp >= o.minRiseFrac * median(amp(ok));
    end

    outSniffs = zeros(nnz(ok), 9);
    oi = 1;
    for i = 1:nTr
        for j = find(ok(i, :))
            seg = s(tr(i, j):pk(i, j));
            on  = tr(i, j) - 1 + find(seg >= seg(1) + o.riseStartFrac * amp(i, j), 1);
            outSniffs(oi, 1) = on;              % coarse onset
            outSniffs(oi, 2) = i;               % trial number
            outSniffs(oi, 3) = j;               % position in the train (cue number)
            outSniffs(oi, 4) = on - tg(i, j);   % off from the TTL by
            outSniffs(oi, 6) = 1;               % cued
            outSniffs(oi, 8) = tr(i, j);        % inhale trough
            outSniffs(oi, 9) = pk(i, j);        % inhale peak
            oi = oi + 1;
        end
    end
end

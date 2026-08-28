% qc4_threePrepFigs — QC round 4: THREE step-1 preparation/extrema
% alternatives (prepBreathTrace_zlp: pwl / conservative / twoscale), each
% with the tri-color step-2 onset detectors (RED slopeGate, BLUE
% kneeBacktrack, GREEN changepoint) and the cyclicSigh 10-s-cycle rule.
% One figure per session per prep:
%   E:\reprocBackup_260824\qc4prep_<mode>\qc4_<mode>_<task>_<id>.jpg
% Each final loads once; all three preps run on it.

TASKS = { ...
 'breathingTask',          '_breathing*.mat'; ...
 'emotionalMovieTask',     '_EmotionalMovieTask*.mat'; ...
 'alternating6Blocks',     '_alternating6Blocks*.mat'; ...
 'breathingTasks_separate','_breathingTasks_separate*.mat'};
MODES = {'pwl', 'conservative', 'twoscale'};
METHODS = {'slopeGate', 'kneeBacktrack', 'changepoint'};
COLS = {[0.85 0.1 0.1], [0.1 0.3 0.9], [0.05 0.6 0.2]};
for mo = 1:3
    d = ['E:\reprocBackup_260824\qc4prep_' MODES{mo}];
    if ~exist(d, 'dir'), mkdir(d); end
end
ctr = 0; nFig = 0;
for tt = 1:size(TASKS, 1)
    [tkey, glb] = TASKS{tt, :};
    cfg = applyParams(tkey, 'main');
    for si = 1:numel(cfg.sessionIDs)
        id = cfg.sessionIDs{si}; ctr = ctr + 1;
        hits = dir(fullfile(cfg.root{si}, id, 'preProc', [id glb]));
        if isempty(hits), continue; end
        try
            s = load(fullfile(hits(1).folder, hits(1).name));
            fn = fieldnames(s); od = s.(fn{1}); clear s
            if ~isfield(od, 'bmFeatures'), continue; end
            isRsp = cellfun(@(x) contains(x, 'rsp'), od.labels);
            rsp = od.data(isRsp, :); rsp = double(rsp(od.rspIDX, :)) .* od.rspFlip;
            fs = od.fs; N = numel(rsp);
            blankF = [];
            if strcmp(id, '260811_EEG_NWU_MS') && ~strcmp(tkey, 'breathingTask'), blankF = 0.10; end

            % cyclicSigh span (breathing task only)
            cySpan = [];
            if isfield(od, 'behDat') && ismember('task', od.behDat.Properties.VariableNames)
                tkc = od.behDat.task;
                if iscell(tkc), tkc(cellfun(@(x) ~(ischar(x) && isrow(x)) && ~(isstring(x) && isscalar(x)), tkc)) = {'NA'}; end
                cm = strcmp(string(tkc), 'cyclicSigh');
                if any(cm) && ismember('finalOnset', od.behDat.Properties.VariableNames)
                    cySpan = [min(od.behDat.finalOnset(cm)) - 15*fs, max(od.behDat.finalOnset(cm)) + 15*fs];
                end
            end

            % panel bins from the common local-scale (prep-independent)
            scB = movstd(movmean(rsp, round(0.15*fs)), round(30*fs));
            nBins = floor(N / (60 * fs));
            if nBins < 1, continue; end
            binAmp = zeros(1, nBins);
            for w = 1:nBins, binAmp(w) = median(scB((w-1)*60*fs+1 : w*60*fs)); end
            [~, aOrd] = sort(binAmp);
            rng(5000 + ctr, 'twister');
            nLow = min(3, nBins); pool = setdiff(1:nBins, aOrd(1:nLow));
            bins = sort([aOrd(1:nLow), pool(randperm(numel(pool), min(3, numel(pool))))]);

            for mo = 1:3
                [det, pk, tr] = prepBreathTrace_zlp(rsp, fs, MODES{mo}, blankF);
                ons = cell(1, 3);
                for mm = 1:3, ons{mm} = findInhaleOnsets_zlp(det, fs, pk, tr, METHODS{mm}); end
                if ~isempty(cySpan)
                    for mm = 1:3
                        o = ons{mm}; keep = true(size(o)); lastKept = -Inf;
                        for k = 1:numel(o)
                            if o(k) >= cySpan(1) && o(k) <= cySpan(2) && (o(k) - lastKept) < 6 * fs
                                keep(k) = false;
                            else
                                lastKept = o(k);
                            end
                        end
                        ons{mm} = o(keep);
                    end
                end
                fig = figure('Visible', 'off', 'Position', [10 10 1500 230 * numel(bins)]);
                for b = 1:numel(bins)
                    i0 = (bins(b)-1)*60*fs + 1; i1 = min(bins(b)*60*fs, N); t = (i0:i1)/fs;
                    subplot(numel(bins), 1, b); hold on
                    plot(t, rsp(i0:i1), 'k', 'LineWidth', 0.7);
                    ex = [pk(pk>=i0 & pk<=i1), tr(tr>=i0 & tr<=i1)];
                    plot(ex/fs, rsp(ex), 'k.', 'MarkerSize', 9);
                    for mm = 1:3
                        oi = ons{mm}(ons{mm}>=i0 & ons{mm}<=i1);
                        plot(oi/fs, rsp(oi), 'v', 'Color', COLS{mm}, 'MarkerFaceColor', COLS{mm}, 'MarkerSize', 6);
                    end
                    xlim([t(1) t(end)]); ylabel(sprintf('min %d', bins(b)));
                    if b == 1
                        title({sprintf('%s — %s — PREP: %s — RED slopeGate | BLUE knee | GREEN changepoint', ...
                            strrep(id, '_', '\_'), tkey, MODES{mo}), ...
                            sprintf('n = %d/%d/%d onsets, %d peaks; black dots = extrema', ...
                            numel(ons{1}), numel(ons{2}), numel(ons{3}), numel(pk))});
                    end
                    if b == numel(bins), xlabel('time (s)'); end
                end
                saveas(fig, fullfile(['E:\reprocBackup_260824\qc4prep_' MODES{mo}], ...
                    sprintf('qc4_%s_%s_%s.jpg', MODES{mo}, tkey, id)));
                close(fig); nFig = nFig + 1;
                fprintf('QC4 %s %s %s: %d/%d/%d onsets, %d peaks\n', MODES{mo}, tkey, id, ...
                    numel(ons{1}), numel(ons{2}), numel(ons{3}), numel(pk));
            end
            clear od rsp
        catch ME
            fprintf('QC4 FAIL %s %s: %s\n', tkey, id, ME.message);
        end
    end
end
fprintf('qc4_threePrepFigs: DONE (%d figures)\n', nFig);

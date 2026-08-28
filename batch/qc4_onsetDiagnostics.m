% qc4_onsetDiagnostics — LOCKED-pipeline session review (2026-08-28):
% conservative prep x kneeBacktrack, r2 = 0.25, r3 = 1.25.
% Per session: one minute-long trace panel per CONDITION (onsets BLUE v,
% peaks RED ., troughs GREEN .; BLACK arrowheads above trough/late onsets)
% + a whole-session onset-locked overlay panel (-0.5..+2 s, y +-5, stats
% bottom-right). Summary CSV per session x locked params.
% Figures -> ZLP_DIAG_DIR (default E:\reprocBackup_260824\qc4diag).

R2L = 0.25; R3L = 1.25;
TASKS = { ...
 'breathingTask',          '_breathing*.mat'; ...
 'emotionalMovieTask',     '_EmotionalMovieTask*.mat'; ...
 'alternating6Blocks',     '_alternating6Blocks*.mat'; ...
 'breathingTasks_separate','_breathingTasks_separate*.mat'};
outDir = getenv('ZLP_DIAG_DIR');
if isempty(outDir), outDir = 'E:\reprocBackup_260824\qc4diag'; end
if ~exist(outDir, 'dir'), mkdir(outDir); end
SUM = {};
for tt = 1:size(TASKS, 1)
    [tkey, glb] = TASKS{tt, :};
    cfg = applyParams(tkey, 'main');
    for si = 1:numel(cfg.sessionIDs)
        id = cfg.sessionIDs{si};
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
            base = movmean(fillmissing(rsp, 'linear', 'EndValues', 'nearest'), round(0.15 * fs));
            scN = movstd(base, round(30 * fs));
            xN = base ./ max(scN, 0.05 * median(scN));

            [det, pk0, tr0] = prepBreathTrace_zlp(rsp, fs, 'conservative', blankF);
            [o, pk, tr] = findInhaleOnsets_zlp(det, fs, pk0, tr0, 'kneeBacktrack', R2L, R3L);

            % cyclicSigh 6-s keep-first + condition inventory from behDat
            condList = {}; condMid = [];
            cySpan = [];
            if isfield(od, 'behDat') && ismember('task', od.behDat.Properties.VariableNames) ...
                    && ismember('finalOnset', od.behDat.Properties.VariableNames)
                tkc = od.behDat.task;
                if iscell(tkc), tkc(cellfun(@(x) ~(ischar(x) && isrow(x)) && ~(isstring(x) && isscalar(x)), tkc)) = {'NA'}; end
                tkc = string(tkc);
                ub = unique(tkc, 'stable');
                for k = 1:numel(ub)
                    m = tkc == ub(k);
                    condList{end+1} = char(ub(k)); %#ok<SAGROW>
                    condMid(end+1) = round((min(od.behDat.finalOnset(m)) + max(od.behDat.finalOnset(m))) / 2); %#ok<SAGROW>
                end
                cm = tkc == "cyclicSigh";
                if any(cm)
                    cySpan = [min(od.behDat.finalOnset(cm)) - 15*fs, max(od.behDat.finalOnset(cm)) + 15*fs];
                end
            elseif isfield(od, 'sections') && istable(od.sections)
                for k = 1:height(od.sections)
                    condList{end+1} = char(string(od.sections.label(k))); %#ok<SAGROW>
                    condMid(end+1) = round((od.sections.startSample(k) + od.sections.endSample(k)) / 2); %#ok<SAGROW>
                end
            end
            if isempty(condList)
                nEven = 4;
                for k = 1:nEven
                    condList{end+1} = sprintf('t%d/4', k); %#ok<SAGROW>
                    condMid(end+1) = round(N * (2*k - 1) / (2 * nEven)); %#ok<SAGROW>
                end
            end
            if ~isempty(cySpan)
                keep = true(size(o)); lastKept = -Inf;
                for k = 1:numel(o)
                    if o(k) >= cySpan(1) && o(k) <= cySpan(2) && (o(k) - lastKept) < 6 * fs
                        keep(k) = false;
                    else, lastKept = o(k);
                    end
                end
                o = o(keep);
            end

            WB = round(0.5 * fs); WF = round(2.0 * fs);
            o = o(o >= WB + 1 & o + WF <= N);
            y0 = xN(o);
            isBad = (y0 < -0.5) | (y0 > 1.0);      % trough | late -> arrowhead

            nP = numel(condList) + 1;
            fig = figure('Visible', 'off', 'Position', [10 10 1500 190 * nP]);
            for c = 1:numel(condList)
                i0 = max(1, condMid(c) - 30 * fs); i1 = min(N, i0 + 60 * fs);
                t = (i0:i1) / fs;
                subplot(nP, 1, c); hold on
                plot(t, rsp(i0:i1), 'k', 'LineWidth', 0.7);
                pkl = pk(pk >= i0 & pk <= i1); trl = tr(tr >= i0 & tr <= i1);
                plot(pkl / fs, rsp(pkl), '.', 'Color', [0.85 0.1 0.1], 'MarkerSize', 11);
                plot(trl / fs, rsp(trl), '.', 'Color', [0.05 0.6 0.2], 'MarkerSize', 11);
                ol = o(o >= i0 & o <= i1);
                plot(ol / fs, rsp(ol), 'v', 'Color', [0.1 0.3 0.9], 'MarkerFaceColor', [0.1 0.3 0.9], 'MarkerSize', 6);
                bl = o(isBad & o >= i0 & o <= i1);
                if ~isempty(bl)
                    yr = max(rsp(i0:i1)) - min(rsp(i0:i1));
                    plot(bl / fs, rsp(bl) + 0.12 * yr, 'kv', 'MarkerFaceColor', 'k', 'MarkerSize', 7);
                end
                xlim([t(1) t(end)]); ylabel(strrep(condList{c}, '_', '\_'));
                if c == 1
                    title(sprintf('%s — %s — LOCKED conservative x kneeBacktrack, r2=%.2f r3=%.2f (blue=onset red=peak green=trough, black arrow=trough/late)', ...
                        strrep(id, '_', '\_'), tkey, R2L, R3L));
                end
            end
            % overlay panel
            subplot(nP, 1, nP); hold on
            nB = numel(o);
            st = struct('n', nB, 'bpm', nB / (N / fs / 60));
            if nB >= 5
                seg = zeros(nB, WB + WF + 1);
                for k = 1:nB, seg(k, :) = xN(o(k)-WB:o(k)+WF); end
                i0c = WB + 1;
                y5 = seg(:, i0c + round(0.5 * fs));
                slope0 = seg(:, i0c + round(0.25 * fs)) - seg(:, i0c);
                st.medY0 = median(seg(:, i0c)); st.iqrY0 = iqr(seg(:, i0c));
                st.pctTrough = 100 * mean(seg(:, i0c) < -0.5);
                st.pctLate   = 100 * mean(seg(:, i0c) > 1.0);
                st.pctFall   = 100 * mean(slope0 < 0);
                st.rise500   = median(y5 - seg(:, i0c));
                tv = (-WB:WF) / fs * 1000;
                show = 1:nB; if nB > 200, rng(7000 + si); show = sort(randperm(nB, 200)); end
                plot(tv, seg(show, :)', 'Color', [0 0 0 0.05]);
                mu = mean(seg, 1); sd = std(seg, 0, 1);
                fill([tv fliplr(tv)], [mu+sd fliplr(mu-sd)], [0.85 0.3 0.2], 'FaceAlpha', 0.25, 'EdgeColor', 'none');
                plot(tv, mu, 'Color', [0.75 0.1 0.1], 'LineWidth', 2);
                yline(0, ':'); xline(0, ':');
                txt = sprintf('n=%d %.1f/min | Y0 %.2f iqr %.2f | trough %.0f%% late %.0f%% fall %.0f%% | rise500 %.2f', ...
                    st.n, st.bpm, st.medY0, st.iqrY0, st.pctTrough, st.pctLate, st.pctFall, st.rise500);
                text(0.98, 0.02, txt, 'Units', 'normalized', 'HorizontalAlignment', 'right', 'VerticalAlignment', 'bottom', 'FontSize', 7, 'BackgroundColor', [1 1 1 0.7]);
                xlim([-500 2000]); ylim([-5 5]);
                ylabel('all onsets');
            else
                text(0.5, 0.5, sprintf('n=%d (too few)', nB), 'Units', 'normalized', 'HorizontalAlignment', 'center');
                st.medY0 = NaN; st.iqrY0 = NaN; st.pctTrough = NaN; st.pctLate = NaN; st.pctFall = NaN; st.rise500 = NaN;
            end
            xlabel('time (ms from onset)');
            saveas(fig, fullfile(outDir, sprintf('diag_%s_%s.jpg', tkey, id)));
            close(fig);
            SUM(end+1, :) = {id, tkey, st.n, st.bpm, st.medY0, st.iqrY0, st.pctTrough, st.pctLate, st.pctFall, st.rise500}; %#ok<AGROW>
            fprintf('DIAG %s %s: n=%d bpm=%.1f trough=%.0f%%\n', tkey, id, st.n, st.bpm, st.pctTrough);
            clear od rsp xN det
        catch ME
            fprintf('DIAG FAIL %s %s: %s\n', tkey, id, ME.message);
        end
    end
end
T = cell2table(SUM, 'VariableNames', {'session', 'task', 'n', 'bpm', 'medY0', 'iqrY0', 'pctTrough', 'pctLate', 'pctFall', 'rise500'});
writetable(T, fullfile(outDir, 'onsetDiagnostics_summary.csv'));
fprintf('qc4_onsetDiagnostics: DONE (%d rows)\n', height(T));

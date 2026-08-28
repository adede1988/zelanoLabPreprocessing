% qc4_onsetDiagnostics — LOCKED-pipeline session review (2026-08-28 rev2):
% conservative prep (2-s peak sep; 6-s inside cyclicSigh, at the extrema
% level) x kneeBacktrack; rule 2 absolute +0.4; anchor = last slope >= 70%
% of window max before the peak.
% Per session: one minute trace panel per CONDITION (rows; onsets BLUE v,
% peaks RED ., troughs GREEN ., BLACK arrowheads above trough/late onsets)
% + a bottom row of PER-CONDITION onset-locked overlays side by side
% (-0.5..+2 s, y +-5, mini stats). Summary CSV. -> ZLP_DIAG_DIR.

R2L = 0.4; R3L = 1.25;
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
            base = movmean(fillmissing(rsp, 'linear', 'EndValues', 'nearest'), round(0.50 * fs));
            scN = movstd(base, round(30 * fs));
            xN = base ./ max(scN, 0.05 * median(scN));

            % conditions: labels + spans (behDat.task -> sections -> quarters)
            condList = {}; condSpan = zeros(0, 2); cySpan = [];
            if isfield(od, 'behDat') && ismember('task', od.behDat.Properties.VariableNames) ...
                    && ismember('finalOnset', od.behDat.Properties.VariableNames)
                tkc = od.behDat.task;
                if iscell(tkc), tkc(cellfun(@(x) ~(ischar(x) && isrow(x)) && ~(isstring(x) && isscalar(x)), tkc)) = {'NA'}; end
                tkc = string(tkc);
                ub = unique(tkc, 'stable');
                for k = 1:numel(ub)
                    m = tkc == ub(k);
                    condList{end+1} = char(ub(k)); %#ok<SAGROW>
                    condSpan(end+1, :) = [max(1, min(od.behDat.finalOnset(m)) - 15*fs), ...
                                          min(N, max(od.behDat.finalOnset(m)) + 15*fs)]; %#ok<SAGROW>
                end
                cm = tkc == "cyclicSigh";
                if any(cm), cySpan = condSpan(find(ub == "cyclicSigh", 1), :); end
            elseif isfield(od, 'sections') && istable(od.sections)
                for k = 1:height(od.sections)
                    condList{end+1} = char(string(od.sections.label(k))); %#ok<SAGROW>
                    condSpan(end+1, :) = [od.sections.startSample(k), od.sections.endSample(k)]; %#ok<SAGROW>
                end
            end
            if isempty(condList)
                for k = 1:4
                    condList{end+1} = sprintf('q%d', k); %#ok<SAGROW>
                    condSpan(end+1, :) = [round(N*(k-1)/4) + 1, round(N*k/4)]; %#ok<SAGROW>
                end
            end

            [det, pk0, tr0] = prepBreathTrace_zlp(rsp, fs, 'conservative', blankF, cySpan);
            [o, pk, tr] = findInhaleOnsets_zlp(det, fs, pk0, tr0, 'kneeBacktrack', R2L, R3L, 0.50, 0.10);

            WB = round(0.5 * fs); WF = round(2.0 * fs);
            o = o(o >= WB + 1 & o + WF <= N);
            y0all = xN(o);
            isBad = (y0all < -0.5) | (y0all > 1.0);

            nC = numel(condList); nR = nC + 1;
            fig = figure('Visible', 'off', 'Position', [10 10 1550 170 * nR]);
            for c = 1:nC
                mid = round(mean(condSpan(c, :)));
                i0 = max(1, mid - 30 * fs); i1 = min(N, i0 + 60 * fs);
                t = (i0:i1) / fs;
                subplot(nR, nC, (c-1)*nC + (1:nC)); hold on
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
                    title(sprintf('%s — %s — conservative x kneeBacktrack rev12 (blue onset, red peak, green trough, black arrow = trough/late)', ...
                        strrep(id, '_', '\_'), tkey));
                end
            end
            % bottom row: per-condition overlays side by side
            st = struct('n', numel(o), 'bpm', numel(o) / (N / fs / 60), 'pctTrough', NaN, 'medY0', NaN);
            if ~isempty(o)
                st.pctTrough = 100 * mean(y0all < -0.5); st.medY0 = median(y0all);
            end
            for c = 1:nC
                subplot(nR, nC, nC*nC + c); hold on
                oc = o(o >= condSpan(c, 1) & o <= condSpan(c, 2));
                if numel(oc) >= 3
                    seg = zeros(numel(oc), WB + WF + 1);
                    for k = 1:numel(oc), seg(k, :) = xN(oc(k)-WB:oc(k)+WF); end
                    tv = (-WB:WF) / fs * 1000;
                    show = 1:numel(oc); if numel(oc) > 80, rng(8000 + si + c); show = sort(randperm(numel(oc), 80)); end
                    plot(tv, seg(show, :)', 'Color', [0 0 0 0.06]);
                    plot(tv, mean(seg, 1), 'Color', [0.75 0.1 0.1], 'LineWidth', 1.5);
                    yline(0, ':'); xline(0, ':');
                    y0c = seg(:, WB + 1);
                    text(0.97, 0.03, sprintf('n=%d tr%.0f%% Y0 %.2f', numel(oc), 100*mean(y0c < -0.5), median(y0c)), ...
                        'Units', 'normalized', 'HorizontalAlignment', 'right', 'VerticalAlignment', 'bottom', 'FontSize', 6, 'BackgroundColor', [1 1 1 0.7]);
                else
                    text(0.5, 0.5, sprintf('n=%d', numel(oc)), 'Units', 'normalized', 'HorizontalAlignment', 'center', 'FontSize', 7);
                end
                xlim([-500 2000]); ylim([-5 5]);
                xlabel(strrep(condList{c}, '_', '\_'), 'FontSize', 7);
            end
            saveas(fig, fullfile(outDir, sprintf('diag_%s_%s.jpg', tkey, id)));
            close(fig);
            SUM(end+1, :) = {id, tkey, st.n, st.bpm, st.medY0, st.pctTrough}; %#ok<AGROW>
            fprintf('DIAG %s %s: n=%d bpm=%.1f trough=%.0f%%\n', tkey, id, st.n, st.bpm, st.pctTrough);
            clear od rsp xN det
        catch ME
            fprintf('DIAG FAIL %s %s: %s\n', tkey, id, ME.message);
        end
    end
end
T = cell2table(SUM, 'VariableNames', {'session', 'task', 'n', 'bpm', 'medY0', 'pctTrough'});
writetable(T, fullfile(outDir, 'onsetDiagnostics_summary.csv'));
fprintf('qc4_onsetDiagnostics: DONE (%d rows)\n', height(T));

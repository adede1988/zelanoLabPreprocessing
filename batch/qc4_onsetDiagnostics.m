% qc4_onsetDiagnostics — per-session 3x3 grid (rows = prep: pwl /
% conservative / twoscale; cols = onset algo: slopeGate / kneeBacktrack /
% changepoint): overlay of the first 1000 ms after each detected inhale onset
% on the WINDOWED-NORMALIZED trace (raw-amplitude drift would confound the
% stats), bold mean waveform +/- 1 SD band, and a stats block per cell:
%   n, br/min           breath count (carving-up inflates this)
%   medY0 / iqrY0       onset-height bias and jitter (normalized units)
%   %trough             Y(0) < -0.5   (trough onsets - the key failure)
%   %late               Y(0) > +1.0   (marked on the risen slope)
%   %fall               negative slope in the first 250 ms (early onsets)
%   rise500             median Y(+500ms) - Y(0)
%   lat25               median onset -> 25%-of-rise crossing latency (s)
%   %1SD Y0 / Y500      requested within-1-SD shares
% Summary CSV across all sessions x prep x algo:
%   E:\reprocBackup_260824\qc4diag\onsetDiagnostics_summary.csv
% Figures: E:\reprocBackup_260824\qc4diag\diag_<task>_<id>.jpg

TASKS = { ...
 'breathingTask',          '_breathing*.mat'; ...
 'emotionalMovieTask',     '_EmotionalMovieTask*.mat'; ...
 'alternating6Blocks',     '_alternating6Blocks*.mat'; ...
 'breathingTasks_separate','_breathingTasks_separate*.mat'};
MODES = {'pwl', 'conservative', 'twoscale'};
METHODS = {'slopeGate', 'kneeBacktrack', 'changepoint'};
outDir = 'E:\reprocBackup_260824\qc4diag';
if ~exist(outDir, 'dir'), mkdir(outDir); end
SUM = {};
ctr = 0;
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
            % common normalized trace for overlays/stats (same for all cells)
            base = movmean(fillmissing(rsp, 'linear', 'EndValues', 'nearest'), round(0.15 * fs));
            scN = movstd(base, round(30 * fs));
            xN = base ./ max(scN, 0.05 * median(scN));
            % cyclicSigh span (breathing task)
            cySpan = [];
            if isfield(od, 'behDat') && ismember('task', od.behDat.Properties.VariableNames)
                tkc = od.behDat.task;
                if iscell(tkc), tkc(cellfun(@(x) ~(ischar(x) && isrow(x)) && ~(isstring(x) && isscalar(x)), tkc)) = {'NA'}; end
                cm = strcmp(string(tkc), 'cyclicSigh');
                if any(cm) && ismember('finalOnset', od.behDat.Properties.VariableNames)
                    cySpan = [min(od.behDat.finalOnset(cm)) - 15*fs, max(od.behDat.finalOnset(cm)) + 15*fs];
                end
            end
            W1 = round(1.0 * fs); W5 = round(0.5 * fs); W25 = round(0.25 * fs);
            mins = N / fs / 60;
            fig = figure('Visible', 'off', 'Position', [10 10 1550 1300]);
            for mo = 1:3
                [det, pk, tr] = prepBreathTrace_zlp(rsp, fs, MODES{mo}, blankF); %#ok<ASGLU>
                for mm = 1:3
                    o = findInhaleOnsets_zlp(det, fs, pk, tr, METHODS{mm});
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
                    o = o(o >= 1 & o + W1 <= N);
                    nB = numel(o);
                    subplot(3, 3, (mo-1)*3 + mm); hold on
                    st = struct('n', nB, 'bpm', nB / mins);
                    if nB >= 5
                        seg = zeros(nB, W1 + 1);
                        for k = 1:nB, seg(k, :) = xN(o(k):o(k)+W1); end
                        y0 = seg(:, 1); y5 = seg(:, W5 + 1);
                        slope0 = (seg(:, W25 + 1) - y0);
                        riseAmt = max(seg, [], 2) - y0;
                        lat = nan(nB, 1);
                        for k = 1:nB
                            c = find(seg(k, :) - y0(k) >= 0.25 * max(riseAmt(k), eps), 1);
                            if ~isempty(c), lat(k) = (c - 1) / fs; end
                        end
                        st.medY0 = median(y0); st.iqrY0 = iqr(y0);
                        st.pctTrough = 100 * mean(y0 < -0.5);
                        st.pctLate   = 100 * mean(y0 > 1.0);
                        st.pctFall   = 100 * mean(slope0 < 0);
                        st.rise500   = median(y5 - y0);
                        st.lat25     = median(lat, 'omitnan');
                        st.pct1sdY0  = 100 * mean(abs(y0 - mean(y0)) <= std(y0));
                        st.pct1sdY5  = 100 * mean(abs(y5 - mean(y5)) <= std(y5));
                        tv = (0:W1) / fs * 1000;
                        show = 1:nB;
                        if nB > 150, rng(6000 + ctr); show = sort(randperm(nB, 150)); end
                        plot(tv, seg(show, :)', 'Color', [0 0 0 0.06]);
                        mu = mean(seg, 1); sd = std(seg, 0, 1);
                        fill([tv fliplr(tv)], [mu+sd fliplr(mu-sd)], [0.85 0.3 0.2], 'FaceAlpha', 0.25, 'EdgeColor', 'none');
                        plot(tv, mu, 'Color', [0.75 0.1 0.1], 'LineWidth', 2);
                        yline(0, ':');
                        txt = sprintf('n=%d %.1f/min\nY0 %.2f iqr %.2f\ntrough %.0f%% late %.0f%% fall %.0f%%\nrise500 %.2f lat25 %.2fs\n1SD Y0 %.0f%% Y500 %.0f%%', ...
                            st.n, st.bpm, st.medY0, st.iqrY0, st.pctTrough, st.pctLate, st.pctFall, st.rise500, st.lat25, st.pct1sdY0, st.pct1sdY5);
                        text(0.02, 0.98, txt, 'Units', 'normalized', 'VerticalAlignment', 'top', 'FontSize', 7, 'BackgroundColor', [1 1 1 0.7]);
                        xlim([0 1000]);
                    else
                        text(0.5, 0.5, sprintf('n=%d (too few)', nB), 'Units', 'normalized', 'HorizontalAlignment', 'center');
                        st.medY0 = NaN; st.iqrY0 = NaN; st.pctTrough = NaN; st.pctLate = NaN;
                        st.pctFall = NaN; st.rise500 = NaN; st.lat25 = NaN; st.pct1sdY0 = NaN; st.pct1sdY5 = NaN;
                    end
                    if mo == 1, title(METHODS{mm}); end
                    if mm == 1, ylabel(MODES{mo}, 'FontWeight', 'bold'); end
                    SUM(end+1, :) = {id, tkey, MODES{mo}, METHODS{mm}, st.n, st.bpm, ...
                        st.medY0, st.iqrY0, st.pctTrough, st.pctLate, st.pctFall, ...
                        st.rise500, st.lat25, st.pct1sdY0, st.pct1sdY5}; %#ok<AGROW>
                end
            end
            sgtitle(sprintf('%s — %s — onset-locked first 1000 ms (normalized units)', strrep(id, '_', '\_'), tkey));
            saveas(fig, fullfile(outDir, sprintf('diag_%s_%s.jpg', tkey, id)));
            close(fig);
            fprintf('DIAG %s %s done\n', tkey, id);
            clear od rsp xN
        catch ME
            fprintf('DIAG FAIL %s %s: %s\n', tkey, id, ME.message);
        end
    end
end
T = cell2table(SUM, 'VariableNames', {'session', 'task', 'prep', 'algo', 'n', 'bpm', ...
    'medY0', 'iqrY0', 'pctTrough', 'pctLate', 'pctFall', 'rise500', 'lat25s', 'pct1sdY0', 'pct1sdY500'});
writetable(T, fullfile(outDir, 'onsetDiagnostics_summary.csv'));
fprintf('qc4_onsetDiagnostics: DONE (%d rows)\n', height(T));

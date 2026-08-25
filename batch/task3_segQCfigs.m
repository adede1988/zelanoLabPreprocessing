% task3_segQCfigs — breath-segmentation QC overlays for the Task-3 sessions
% whose breathMetrics breath count moved >25% vs the July (legacy-engine)
% final. Six seeded-random, non-overlapping 1-minute segments per session,
% respiration plotted exactly as the engine saw it (rspIDX selected, rspFlip
% applied), with breathMetrics inhale onsets (bmObj col 2) marked. New engine
% only — no legacy overlay.

SESS = { ...  % id, Delta% vs July (from runReport Task 3 soft-flag table)
 '251008_EEG_NWU_JC',   -29.0; ...
 '251009_EEG_NWU_JM',   +44.8; ...
 '250929_Dupi_NMH_GH_1', +52.7; ...
 '251110_EEG_NWU_GA',   -26.3; ...
 '251111_EEG_NWU_VW',   -65.7; ...
 '251113_EEG_NWU_GH',   -33.5; ...
 '250929_Dupi_NMH_GH_2', +46.5; ...
 '251002_Dupi_NMH_AB_2', -26.4; ...
 '251030_Dupi_NMH_DB_1', +51.2; ...
 '251030_Dupi_NMH_DB_2', +31.5};

outDir = 'E:\reprocBackup_260824\segQC';
if ~exist(outDir, 'dir'), mkdir(outDir); end

cfg = applyParams('breathingTask', 'main');
for k = 1:size(SESS, 1)
    id = SESS{k, 1};
    si = find(strcmp(cfg.sessionIDs, id), 1);
    if isempty(si), fprintf('%s: not in session list - SKIPPED\n', id); continue; end
    hits = dir(fullfile(cfg.root{si}, id, 'preProc', [id '_breathing*.mat']));
    if isempty(hits), fprintf('%s: no breathing final - SKIPPED\n', id); continue; end
    s = load(fullfile(hits(1).folder, hits(1).name));
    fn = fieldnames(s); od = s.(fn{1}); clear s

    isRsp = cellfun(@(x) contains(x, 'rsp'), od.labels);
    rsp = od.data(isRsp, :);
    rsp = rsp(od.rspIDX, :) .* od.rspFlip;        % the trace the engine segmented
    fs = od.fs;
    onsets = round(od.bmObj(:, 2) * fs);          % inhale-onset samples
    N = numel(rsp);

    % six distinct, non-overlapping 1-min bins, seeded for reproducibility
    nBins = floor(N / (60 * fs));
    rng(1000 + k, 'twister');
    bins = sort(randperm(nBins, min(6, nBins)));

    fig = figure('Visible', 'off', 'Position', [10 10 1500 1350]);
    for b = 1:numel(bins)
        i0 = (bins(b) - 1) * 60 * fs + 1;
        i1 = bins(b) * 60 * fs;
        t = (i0:i1) / fs;
        subplot(6, 1, b); hold on
        plot(t, rsp(i0:i1), 'k', 'LineWidth', 0.75);
        oi = onsets(onsets >= i0 & onsets <= i1);
        plot(oi / fs, rsp(oi), 'rv', 'MarkerFaceColor', 'r', 'MarkerSize', 6);
        xlim([t(1) t(end)]);
        ylabel(sprintf('min %d', bins(b)));
        if b == 1
            title(sprintf('%s — breathMetrics inhale onsets (n=%d breaths, %+.1f%% vs July)', ...
                strrep(id, '_', '\_'), size(od.bmObj, 1), SESS{k, 2}));
        end
        if b == numel(bins), xlabel('time (s)'); end
    end
    saveas(fig, fullfile(outDir, sprintf('segQC_%s.jpg', id)));
    close(fig);
    fprintf('%s: %d onsets marked across %d segments -> segQC_%s.jpg\n', ...
        id, size(od.bmObj, 1), numel(bins), id);
    clear od rsp
end
fprintf('task3_segQCfigs: DONE\n');

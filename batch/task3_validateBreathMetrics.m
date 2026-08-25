% task3_validateBreathMetrics — D8c/D8d agreement check, old engine vs breathMetrics
%
% For the three curated test sessions (one per Type), extract the chosen
% respiration trace from the existing July final, run BOTH engines on that
% same trace, and match inhale onsets within +/-250 ms in both directions.
% Bar: >= 90% matched in both directions for every session (D8d).
%
% Outputs (E:\reprocBackup_260824\bmValidation\):
%   bmValidate_<id>.png       overlay figures (3 zoom windows + whole trace)
%   bmValidation_results.mat  per-session match stats
% Prints a PASS/FAIL summary. Runs on the lab desktop with R: mapped.

TESTS = { ...            % sessID, task group root key per applyParams Type
    '251030_Dupi_NMH_DB_1'; ...
    '250908_OBE_NWU_AS'; ...
    '251008_EEG_NWU_GM'};
TOL   = 0.250;           % s, D8d
BAR   = 0.90;
OUTD  = 'E:\reprocBackup_260824\bmValidation';
if ~isfolder(OUTD), mkdir(OUTD); end

L = labPaths();
results = struct('id', {}, 'nOld', {}, 'nNew', {}, 'nSaved', {}, ...
                 'pctOldMatched', {}, 'pctNewMatched', {}, 'medAbsDt', {}, 'pass', {});

for t = 1:numel(TESTS)
    id = TESTS{t};
    P  = applyParams('breathingTask', id);
    cfg = applyParams('breathingTask', 'main');
    ri = find(strcmpi(cfg.sessionIDs, id), 1);
    root = cfg.root{ri};
    fpath = fullfile(root, id, 'preProc', [id '_breathingPreproc.mat']);
    fprintf('\n===== %s =====\nloading %s\n', id, fpath);
    S = load(fpath); fn = fieldnames(S); od = S.(fn{1}); clear S

    isRsp = cellfun(@(x) contains(x, 'rsp'), od.labels);
    rsp = od.data(isRsp, :);
    rsp = rsp(od.rspIDX, :) .* od.rspFlip;
    fs  = od.fs;
    savedN = size(od.bmObj, 1);

    % --- old engine, fresh run on the same trace ---
    bmOld = breathTemplates4(rsp, fs);
    onOld = bmOld(:, 2);

    % --- new engine ---
    [bmNew, feats] = segmentBreaths_breathMetrics(rsp, fs);
    onNew = bmNew(:, 2);

    % --- one-to-one nearest matching within TOL, both directions ---
    [pctOld, dtOld] = matchPct(onOld, onNew, TOL);
    [pctNew, ~]     = matchPct(onNew, onOld, TOL);
    medDt = median(abs(dtOld), 'omitnan');

    pass = pctOld >= BAR && pctNew >= BAR;
    fprintf(['%s: old %d breaths, new %d breaths (saved final had %d)\n' ...
             '  %% old matched by new: %.1f%%   %% new matched by old: %.1f%%   median |dt| = %.0f ms   -> %s\n'], ...
        id, numel(onOld), numel(onNew), savedN, 100*pctOld, 100*pctNew, 1000*medDt, tern(pass, 'PASS', 'FAIL'));

    results(end+1) = struct('id', id, 'nOld', numel(onOld), 'nNew', numel(onNew), ...
        'nSaved', savedN, 'pctOldMatched', pctOld, 'pctNewMatched', pctNew, ...
        'medAbsDt', medDt, 'pass', pass); %#ok<SAGROW>

    % --- overlay figure: whole trace + three 120-s zoom windows ---
    fig = figure('Visible', 'off', 'Position', [50 50 1600 900]);
    tim = (1:numel(rsp)) / fs;
    zoomStarts = round([0.10 0.50 0.90] * (tim(end) - 130));
    subplot(4, 1, 1); hold on
    dec = 1:10:numel(rsp);
    plot(tim(dec), rsp(dec), 'Color', [.6 .6 .6]);
    scatter(onOld, zeros(size(onOld)), 6, 'b', 'filled');
    scatter(onNew, zeros(size(onNew)) + 0.1 * std(rsp), 6, 'r', 'filled');
    title(sprintf('%s - whole trace (blue=old bT4, red=new breathMetrics)', strrep(id, '_', '\_')));
    for z = 1:3
        subplot(4, 1, 1 + z); hold on
        w = tim >= zoomStarts(z) & tim <= zoomStarts(z) + 120;
        plot(tim(w), rsp(w), 'k');
        oo = onOld(onOld >= zoomStarts(z) & onOld <= zoomStarts(z) + 120);
        nn = onNew(onNew >= zoomStarts(z) & onNew <= zoomStarts(z) + 120);
        scatter(oo, interp1(tim, rsp, oo), 30, 'b', 'filled');
        scatter(nn, interp1(tim, rsp, nn), 18, 'r', 'filled');
        title(sprintf('zoom %d: %d-%d s', z, zoomStarts(z), zoomStarts(z) + 120));
    end
    saveas(fig, fullfile(OUTD, ['bmValidate_' id '.png']));
    close(fig);
    clear od rsp
end

save(fullfile(OUTD, 'bmValidation_results.mat'), 'results');
fprintf('\n===== SUMMARY =====\n');
allPass = true;
for t = 1:numel(results)
    fprintf('%-22s old->new %.1f%%  new->old %.1f%%  med|dt| %.0f ms  %s\n', ...
        results(t).id, 100*results(t).pctOldMatched, 100*results(t).pctNewMatched, ...
        1000*results(t).medAbsDt, tern(results(t).pass, 'PASS', 'FAIL'));
    allPass = allPass && results(t).pass;
end
fprintf('OVERALL: %s (bar: >=%.0f%% both directions, tol +/-%d ms)\n', ...
    tern(allPass, 'PASS', 'FAIL'), 100*BAR, 1000*TOL);

% ============================ helpers ============================

function [pct, dts] = matchPct(a, b, tol)
% fraction of onsets in a with a one-to-one nearest match in b within tol.
% greedy nearest-pair matching: repeatedly take the globally closest pair.
    a = a(:); b = b(:);
    dts = nan(size(a));
    if isempty(a) || isempty(b), pct = 0; return; end
    D = abs(a - b');              % |a_i - b_j|
    D(D > tol) = Inf;
    nMatched = 0;
    while true
        [m, li] = min(D(:));
        if ~isfinite(m), break; end
        [i, j] = ind2sub(size(D), li);
        dts(i) = a(i) - b(j);
        nMatched = nMatched + 1;
        D(i, :) = Inf;
        D(:, j) = Inf;
    end
    pct = nMatched / numel(a);
end

function out = tern(c, x, y)
    if c, out = x; else, out = y; end
end

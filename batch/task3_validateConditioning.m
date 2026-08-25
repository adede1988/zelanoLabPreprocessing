% task3_validateConditioning — D8d fallback ladder for the two sessions that
% failed the 90% agreement bar (Tasks_260824.md Task 3 Part A step 3):
% light smoothing -> mean-centering -> z-scoring -> breathmetrics' own
% baseline-correction options, each compared against a fresh breathTemplates4
% run on the same trace. Prints one line per variant per session.

TESTS = {'251030_Dupi_NMH_DB_1'; '250908_OBE_NWU_AS'};
TOL = 0.250;

cfg = applyParams('breathingTask', 'main');
for t = 1:numel(TESTS)
    id = TESTS{t};
    ri = find(strcmpi(cfg.sessionIDs, id), 1);
    fpath = fullfile(cfg.root{ri}, id, 'preProc', [id '_breathingPreproc.mat']);
    fprintf('\n===== %s =====\n', id);
    S = load(fpath); fn = fieldnames(S); od = S.(fn{1}); clear S
    isRsp = cellfun(@(x) contains(x, 'rsp'), od.labels);
    rsp = od.data(isRsp, :);
    rsp = rsp(od.rspIDX, :) .* od.rspFlip;
    fs = od.fs;
    clear od

    onOld = breathTemplates4(rsp, fs);
    onOld = onOld(:, 2);

    variants = { ...
        'baseline (raw -> sliding)',        @(x) x,                                        'sliding'; ...
        'smooth 100 ms',                    @(x) smoothdata(x, 'gaussian', round(fs/10)),  'sliding'; ...
        'smooth 250 ms',                    @(x) smoothdata(x, 'gaussian', round(fs/4)),   'sliding'; ...
        'mean-centered',                    @(x) x - mean(x),                              'sliding'; ...
        'z-scored',                         @(x) (x - mean(x)) / std(x),                   'sliding'; ...
        'baselineCorrection = simple',      @(x) x,                                        'simple'; ...
        'smooth 250 ms + z-score',          @(x) zsc(smoothdata(x, 'gaussian', round(fs/4))), 'sliding'};

    for v = 1:size(variants, 1)
        [nm, condFn, blMethod] = variants{v, :};
        try
            x = condFn(double(rsp));
            bm = breathmetrics(x, fs, 'humanAirflow');
            bm.estimateAllFeatures(0, blMethod, 1, 0);
            onNew = double(bm.inhaleOnsets(:)) / fs;
            onNew = onNew(1:end-1);
            [pOld, ~] = matchPct(onOld, onNew, TOL);
            [pNew, ~] = matchPct(onNew, onOld, TOL);
            fprintf('  %-32s nOld=%4d nNew=%4d  old->new %5.1f%%  new->old %5.1f%%  %s\n', ...
                nm, numel(onOld), numel(onNew), 100*pOld, 100*pNew, ...
                tern(pOld >= .9 && pNew >= .9, 'PASS', 'fail'));
        catch ME
            fprintf('  %-32s ERROR: %s\n', nm, ME.message);
        end
    end
    clear rsp
end
fprintf('\ntask3_validateConditioning: DONE\n');

function z = zsc(x)
    z = (x - mean(x)) / std(x);
end

function [pct, dts] = matchPct(a, b, tol)
    a = a(:); b = b(:);
    dts = nan(size(a));
    if isempty(a) || isempty(b), pct = 0; return; end
    D = abs(a - b');
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

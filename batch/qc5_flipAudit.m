% qc5_flipAudit - rspFlip A/B audit (2026-08-28 user review).
%
% GA's cyclicSigh looks inverted (user), other conditions unclear, slowResp
% looks correct - suspicion: wrong rspFlip and/or a reconstruction that
% resolved a block's sign against the true orientation. Audit: every session
% with pctTrough >= 10% in the locked rev12b diagnostics run (+ GA always),
% detection run under BOTH the sheet flip and its inverse; the flip with
% collapsing trough rates and the higher template correlation is the
% evidence. Template = EEG ZL's audiobook run (textbook per user).
%
% Verdict rule (autonomous): PREFER THE SHEET. Flag 'INVERT' only when the
% inverse (a) cuts %trough to less than half AND by >= 8 points absolute,
% and (b) beats the sheet's template correlation. Anything smaller ->
% 'keep-sheet'. Per-condition template correlations are dumped for every
% audited breathing-family session (reconstructed blocks carry their own
% sign, so block-wise disagreement is the reconstruction-sign signature).
% NO sheet writes here - measurement only; decisions applied by the driver.
%
% Output (ZLP_DIAG_DIR, default E:\reprocBackup_260824\qc5flip):
%   qc5_flipAudit.csv  - one row per session with both-flip stats + verdict
%   flip_<sess>.jpg    - A/B figure (minute trace + mean overlay per flip)
%   log: per-condition corr table + GA reconstructedBlocks provenance

SUMCSV = 'E:\reprocBackup_260824\qc4diagAG\onsetDiagnostics_summary.csv';
TRTH = 10;                       % audit threshold, %trough
outDir = getenv('ZLP_DIAG_DIR');
if isempty(outDir), outDir = 'E:\reprocBackup_260824\qc5flip'; end
if ~exist(outDir, 'dir'), mkdir(outDir); end

TASKS = { ...
 'breathingTask',          '_breathing*.mat'; ...
 'emotionalMovieTask',     '_EmotionalMovieTask*.mat'; ...
 'alternating6Blocks',     '_alternating6Blocks*.mat'; ...
 'breathingTasks_separate','_breathingTasks_separate*.mat'};

SUM = readtable(SUMCSV);
auditIDs = SUM.session(SUM.pctTrough >= TRTH);
if ~any(contains(auditIDs, '_GA')), auditIDs{end+1} = '251110_EEG_NWU_GA'; end
fprintf('AUDIT LIST (%d): %s\n', numel(auditIDs), strjoin(auditIDs', ', '));

WB = round(0.5 * 500); WF = round(2.0 * 500);   % fs is 500 throughout

% ---------- template: EEG ZL (breathingTask) audio-block mean waveform ----------
cfgB = applyParams('breathingTask', 'main');
zi = find(contains(cfgB.sessionIDs, '_ZL'), 1);
zid = cfgB.sessionIDs{zi};
hits = dir(fullfile(cfgB.root{zi}, zid, 'preProc', [zid '_breathing*.mat']));
s = load(fullfile(hits(1).folder, hits(1).name)); fn = fieldnames(s); zod = s.(fn{1}); clear s
[~, ~, ~, ~, ~, xNz, oz] = flipStats(zod, zod.rspFlip, WB, WF, 'breathingTask');
tkz = zod.behDat.task;
if iscell(tkz), tkz(cellfun(@(x) ~(ischar(x) && isrow(x)) && ~(isstring(x) && isscalar(x)), tkz)) = {'NA'}; end
tkz = string(tkz);
osz = zod.behDat.finalOnset(contains(lower(tkz), 'audio'));
oz = oz(oz >= min(osz) & oz <= max(osz));
assert(numel(oz) >= 5, 'ZL audio template: too few onsets');
segZ = zeros(numel(oz), WB + WF + 1);
for k = 1:numel(oz), segZ(k, :) = xNz(oz(k)-WB:oz(k)+WF); end
tmplMean = mean(segZ, 1);
fprintf('TEMPLATE: %s audio block, %d breaths\n', zid, numel(oz));
clear zod xNz segZ

R = {};
for tt = 1:size(TASKS, 1)
    [tkey, glb] = TASKS{tt, :};
    cfg = applyParams(tkey, 'main');
    for si = 1:numel(cfg.sessionIDs)
        id = cfg.sessionIDs{si};
        if ~any(strcmp(auditIDs, id)), continue; end
        hits = dir(fullfile(cfg.root{si}, id, 'preProc', [id glb]));
        if isempty(hits), continue; end
        try
            s = load(fullfile(hits(1).folder, hits(1).name));
            fn = fieldnames(s); od = s.(fn{1}); clear s
            if ~isfield(od, 'bmFeatures'), continue; end
            sheetFlip = od.rspFlip;
            st = struct();
            fig = figure('Visible', 'off', 'Position', [10 10 1500 700]);
            for v = 1:2
                if v == 1, fl = sheetFlip; else, fl = -sheetFlip; end
                [n, bpm, trPct, medY0, mw, xN, o] = flipStats(od, fl, WB, WF, tkey);
                cc = NaN;
                if ~isempty(mw), cc = corr(mw(:), tmplMean(:)); end
                st(v).fl = fl; st(v).n = n; st(v).bpm = bpm;
                st(v).trPct = trPct; st(v).medY0 = medY0; st(v).cc = cc;
                st(v).xN = xN; st(v).o = o;
                % panel: minute trace
                N = numel(xN);
                i0 = max(1, round(N/2) - 30*500); i1 = min(N, i0 + 60*500);
                subplot(2, 2, (v-1)*2 + 1); hold on
                plot((i0:i1)/500, xN(i0:i1), 'k', 'LineWidth', 0.7);
                ol = o(o >= i0 & o <= i1);
                plot(ol/500, xN(ol), 'v', 'Color', [0.1 0.3 0.9], 'MarkerFaceColor', [0.1 0.3 0.9], 'MarkerSize', 5);
                ylabel(sprintf('flip=%+d%s', fl, ternStr(v == 1, ' (sheet)', ' (inverse)')));
                title(sprintf('n=%d bpm=%.1f trough=%.0f%% medY0=%.2f tmplCorr=%.2f', n, bpm, trPct, medY0, cc), 'FontSize', 9);
                subplot(2, 2, (v-1)*2 + 2); hold on
                if ~isempty(mw)
                    plot((-WB:WF)/500*1000, mw, 'r', 'LineWidth', 1.5);
                    plot((-WB:WF)/500*1000, tmplMean, 'k:', 'LineWidth', 1);
                end
                yline(0, ':'); xline(0, ':'); ylim([-3 3]);
                title('mean onset-locked (red) vs ZL template (dotted)', 'FontSize', 8);
            end
            sgtitle(sprintf('%s — %s — rspFlip audit', strrep(id, '_', '\_'), tkey), 'FontSize', 10);
            saveas(fig, fullfile(outDir, sprintf('flip_%s.jpg', id))); close(fig);

            % verdict
            bigDrop = st(2).trPct < 0.5 * st(1).trPct && (st(1).trPct - st(2).trPct) >= 8;
            betterCorr = isfinite(st(2).cc) && (~isfinite(st(1).cc) || st(2).cc > st(1).cc);
            if bigDrop && betterCorr, vd = 'INVERT'; else, vd = 'keep-sheet'; end
            R(end+1, :) = {id, tkey, sheetFlip, st(1).n, st(1).trPct, st(1).medY0, st(1).cc, ...
                           st(2).n, st(2).trPct, st(2).medY0, st(2).cc, vd}; %#ok<SAGROW>
            fprintf('FLIP %s %s: sheet(%+d) n=%d tr=%.0f%% cc=%.2f | inv n=%d tr=%.0f%% cc=%.2f -> %s\n', ...
                id, tkey, sheetFlip, st(1).n, st(1).trPct, st(1).cc, st(2).n, st(2).trPct, st(2).cc, vd);

            % per-condition template correlations, both flips (breathing family)
            if ismember('task', od.behDat.Properties.VariableNames)
                tkc = od.behDat.task;
                if iscell(tkc), tkc(cellfun(@(x) ~(ischar(x) && isrow(x)) && ~(isstring(x) && isscalar(x)), tkc)) = {'NA'}; end
                tkc = string(tkc);
                ub = unique(tkc, 'stable');
                for k = 1:numel(ub)
                    os = od.behDat.finalOnset(tkc == ub(k));
                    ccA = condCorr(st(1).xN, st(1).o, min(os), max(os), WB, WF, tmplMean);
                    ccB = condCorr(st(2).xN, st(2).o, min(os), max(os), WB, WF, tmplMean);
                    fprintf('  COND %s %-18s sheetCorr=%.2f invCorr=%.2f\n', id, char(ub(k)), ccA, ccB);
                end
            end
            if contains(id, '_GA') && isfield(od, 'reconstructedBlocks')
                fprintf('  GA reconstructedBlocks provenance:\n');
                disp(od.reconstructedBlocks);
            end
            clear od
        catch ME
            fprintf('FLIP FAIL %s %s: %s\n', tkey, id, ME.message);
        end
    end
end
T = cell2table(R, 'VariableNames', {'session', 'task', 'sheetFlip', ...
    'n_sheet', 'trough_sheet', 'medY0_sheet', 'corr_sheet', ...
    'n_inv', 'trough_inv', 'medY0_inv', 'corr_inv', 'verdict'});
writetable(T, fullfile(outDir, 'qc5_flipAudit.csv'));
fprintf('qc5_flipAudit: DONE (%d rows)\n', height(T));

% ---------------- helpers ----------------
function [n, bpm, trPct, medY0, mw, xN, o] = flipStats(od, fl, WB, WF, tkey)
    isRsp = cellfun(@(x) contains(x, 'rsp'), od.labels);
    r = double(od.data(isRsp, :)); r = r(od.rspIDX, :) .* fl;
    fs = od.fs; N = numel(r);
    blankF = [];
    if contains(od.sessID, '_MS') && ~strcmp(tkey, 'breathingTask'), blankF = 0.10; end
    cySpan = [];
    if ismember('task', od.behDat.Properties.VariableNames) && ismember('finalOnset', od.behDat.Properties.VariableNames)
        tkc = od.behDat.task;
        if iscell(tkc), tkc(cellfun(@(x) ~(ischar(x) && isrow(x)) && ~(isstring(x) && isscalar(x)), tkc)) = {'NA'}; end
        tkc = string(tkc);
        cm = tkc == "cyclicSigh";
        if any(cm)
            cySpan = [max(1, min(od.behDat.finalOnset(cm)) - 15*fs), min(N, max(od.behDat.finalOnset(cm)) + 15*fs)];
        end
    end
    base = movmean(fillmissing(r, 'linear', 'EndValues', 'nearest'), round(0.5 * fs));
    scN = movstd(base, round(30 * fs));
    xN = base ./ max(scN, 0.05 * median(scN));
    [det, pk0, tr0] = prepBreathTrace_zlp(r, fs, 'conservative', blankF, cySpan);
    o = findInhaleOnsets_zlp(det, fs, pk0, tr0, 'kneeBacktrack', 0.4, 1.25, 0.50, 0.10);
    o = o(o >= WB + 1 & o + WF <= N);
    n = numel(o); bpm = n / (N / fs / 60);
    if n > 0
        y0 = xN(o); trPct = 100 * mean(y0 < -0.5); medY0 = median(y0);
    else
        trPct = NaN; medY0 = NaN;
    end
    mw = [];
    if n >= 5
        seg = zeros(n, WB + WF + 1);
        for k = 1:n, seg(k, :) = xN(o(k)-WB:o(k)+WF); end
        mw = mean(seg, 1);
    end
end

function cc = condCorr(xN, o, lo, hi, WB, WF, tmplMean)
    cc = NaN;
    try
        oc = o(o >= lo & o <= hi);
        if numel(oc) >= 5
            seg = zeros(numel(oc), WB + WF + 1);
            for k = 1:numel(oc), seg(k, :) = xN(oc(k)-WB:oc(k)+WF); end
            cc = corr(mean(seg, 1)', tmplMean(:));
        end
    catch
    end
end

function out = ternStr(cond, a, b)
    if cond, out = a; else, out = b; end
end

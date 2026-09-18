% pacedBreathing_respHRV_summary - respiratory HRV (within-breath RSA) as a function
% of breath length and depth for a pacedBreathing session, plus a final-10-min
% (focused breathing) vs rest comparison. Runs on the compact pack written by
% batch/pacedBreathing_summaryPack.m (no EEG needed).
%
%   env ZLP_PACK    path to <id>_pacedBreathing_pack.mat
%   env ZLP_SUMOUT  output folder (figures PNG + stats JSON + CSV tables)
%   env ZLP_PRE_SEC   length of the opening natural-breathing period, s (default 480)
%   env ZLP_FINAL_SEC length of the closing focused-breathing period, s (default 600)
%
% Periods (time-defined, per the experimenter's description of each session -
% the pipeline's inferred blocks are NOT used for grouping):
%   pre      first PRE_SEC   = audiobook listening + instructions (natural breathing)
%   paced    PRE_SEC .. (end - FINAL_SEC) = paced breathing at a sweep of paces x depths
%   final10  last FINAL_SEC  = focused breathing
% Breaths flagged nearSeam (recording stop/restart seams, multi-file acquisitions)
% are excluded from the good set; seams are drawn on the time course.
%
% Definitions
%   RSA (ms)      per-breath RR_max_min from flagBadBreaths = max RR - min RR
%                 inside the breath (inhale onset -> next onset), ms
%   length (s)    breath period (bmObj col 7)
%   depth         PREDICTOR = bm_inhaleVolumesRaw (breathmetrics inhale volume on the
%                 raw trace, raw units); breath amplitude (bmObj col 8) is kept in the
%                 tables as a descriptor only. Falls back to amplitude if no volume.
%   good          flagBadBreaths goodBreath == 1
%   clean         good & nSubPeaks <= 1 & localPeriodCV < 0.20 (not ragged)

packPath = getenv('ZLP_PACK');   assert(~isempty(packPath), 'set ZLP_PACK');
outDir   = getenv('ZLP_SUMOUT'); if isempty(outDir), outDir = fullfile(fileparts(packPath), 'summary'); end
if ~isfolder(outDir), mkdir(outDir); end
PRE_SEC = str2double(getenv('ZLP_PRE_SEC'));     if ~isfinite(PRE_SEC),   PRE_SEC = 8 * 60;    end
FINAL_SEC = str2double(getenv('ZLP_FINAL_SEC')); if ~isfinite(FINAL_SEC), FINAL_SEC = 10 * 60; end
S = load(packPath);
B = S.behDat; K = S.blocks; fs = S.fs; fsP = S.fsPack;
durS = S.nSamples / fs;
id = S.sessID;
fprintf('%s: %d breaths, %.1f min\n', id, height(B), durS / 60);

% ---------------- per-breath derived quantities ----------------
onsetSec = B.finalOnset / fs;
B.onsetSec = onsetSec;
B.rsa_ms  = 1000 * B.RR_max_min;
B.good    = B.goodBreath == 1;
if ismember('nearSeam', B.Properties.VariableNames), B.good = B.good & ~B.nearSeam; end
seamSec = [];
if isfield(S, 'segments') && istable(S.segments) && height(S.segments) > 1, seamSec = S.segments.startSample(2:end) / fs; end
stats.seamMin = seamSec(:)' / 60; stats.preSec = PRE_SEC; stats.finalSec = FINAL_SEC;
B.clean   = B.good & B.nSubPeaks <= 1 & B.localPeriodCV < 0.20;
pre     = onsetSec < PRE_SEC;
final10 = onsetSec >= durS - FINAL_SEC;
paced   = ~pre & ~final10;
B.final10 = final10;
B.period = repmat("paced", height(B), 1); B.period(pre) = "pre"; B.period(final10) = "final10";
stats = struct();
stats.sessID = id; stats.durationMin = durS / 60;
stats.periods = struct('preEndMin', PRE_SEC / 60, 'pacedStartMin', PRE_SEC / 60, 'pacedEndMin', (durS - FINAL_SEC) / 60, 'final10StartMin', (durS - FINAL_SEC) / 60);
% mean RR / HR over each breath from the 50-Hz RRint
RR = S.RRint(:)';
B.meanRR = nan(height(B), 1);
for b = 1:height(B)
    i0 = max(1, round(onsetSec(b) * fsP)); i1 = min(numel(RR), round((onsetSec(b) + B.length(b)) * fsP));
    if i1 > i0, B.meanRR(b) = mean(RR(i0:i1), 'omitnan'); end
end
B.hrBPM = 60 ./ B.meanRR;
B.rsaNorm = B.rsa_ms ./ (1000 * B.meanRR);       % RSA as a fraction of the mean RR
hasVol = ismember('bm_inhaleVolumesRaw', B.Properties.VariableNames);
if hasVol, B.depthVol = B.bm_inhaleVolumesRaw; end
% DEPTH PREDICTOR = raw-unit inhale volume (breathmetrics integral of the inhale on
% the raw trace); amplitude stays in the tables as a descriptor only
if hasVol
    B.depth = B.depthVol; DEPTHLAB = 'inhale volume (raw units)'; DEPTHSHORT = 'volume';
else
    B.depth = B.amp;      DEPTHLAB = 'breath amplitude (raw units)'; DEPTHSHORT = 'amplitude';
end
B.depth(~isfinite(B.depth) | B.depth <= 0) = NaN;
stats.depthPredictor = DEPTHLAB;

stats.nBreaths = height(B); stats.nGood = sum(B.good); stats.nClean = sum(B.clean);
stats.nPaced = sum(paced); stats.nPre = sum(pre); stats.nFinal10 = sum(final10);
stats.ecgSkipped = S.ecgSkipped;
stats.hrOverall = median(B.hrBPM, 'omitnan');
stats.fracGoodPaced = mean(B.good(paced)); stats.fracCleanPaced = mean(B.clean(paced));
stats.fracMultiPeak = struct('paced', mean(B.nSubPeaks(paced) >= 2, 'omitnan'), 'pre', mean(B.nSubPeaks(pre) >= 2, 'omitnan'), 'final10', mean(B.nSubPeaks(final10) >= 2, 'omitnan'));

% ---------------- inferred-block table (kept for reference only) ----------------
K.medRSAgood_ms = nan(height(K), 1); K.fracClean = nan(height(K), 1); K.medSubPeaks = nan(height(K), 1);
for k = 1:height(K)
    m = B.condition == K.order(k);
    K.medRSAgood_ms(k) = median(B.rsa_ms(m & B.good), 'omitnan');
    K.fracClean(k) = mean(B.clean(m)); K.medSubPeaks(k) = median(B.nSubPeaks(m), 'omitnan');
end
K.startMin = K.startSample / fs / 60; K.endMin = K.endSample / fs / 60;
writetable(K, fullfile(outDir, [id '_blocks_summary.csv']));

% ---------------- RSA vs length x depth (paced breaths) ----------------
sel = paced & B.good & isfinite(B.rsa_ms) & B.length > 0 & isfinite(B.depth);
selC = sel & B.clean;
T = B(sel, :);
[rhoL, pL] = corr(log(T.length), T.rsa_ms, 'Type', 'Spearman', 'rows', 'complete');
okA = T.amp > 0;
[rhoA, pA] = corr(log(T.amp(okA)), T.rsa_ms(okA), 'Type', 'Spearman', 'rows', 'complete');
stats.spearman = struct('rsa_vs_logLength', [rhoL pL], 'rsa_vs_logDepth', [rhoA pA]);
if hasVol
    [rhoV, pV] = corr(log(max(T.depthVol, eps)), T.rsa_ms, 'Type', 'Spearman', 'rows', 'complete');
    stats.spearman.rsa_vs_logVol = [rhoV pV];
end
muL = mean(log(T.length)); muA = mean(log(T.depth));
mdlTbl = table(log(T.length) - muL, log(T.depth) - muA, T.rsa_ms, 'VariableNames', {'logLen', 'logDepth', 'rsa'});
m1 = fitlm(mdlTbl, 'rsa ~ logLen + logDepth', 'RobustOpts', 'on');
m2 = fitlm(mdlTbl, 'rsa ~ logLen * logDepth', 'RobustOpts', 'on');
mL = fitlm(mdlTbl, 'rsa ~ logLen', 'RobustOpts', 'on');
mA = fitlm(mdlTbl, 'rsa ~ logDepth', 'RobustOpts', 'on');
stats.model_additive = modelSummary(m1);
stats.model_interaction = modelSummary(m2);
stats.model_lengthOnly = modelSummary(mL);
stats.model_depthOnly = modelSummary(mA);
TC = B(selC, :);
if height(TC) > 30
    tc = table(log(TC.length) - mean(log(TC.length)), log(TC.depth) - mean(log(TC.depth)), TC.rsa_ms, 'VariableNames', {'logLen', 'logDepth', 'rsa'});
    stats.model_additive_clean = modelSummary(fitlm(tc, 'rsa ~ logLen + logDepth', 'RobustOpts', 'on'));
end
TA = B(paced & isfinite(B.rsa_ms) & B.length > 0 & isfinite(B.depth), :);
ta = table(log(TA.length) - mean(log(TA.length)), log(TA.depth) - mean(log(TA.depth)), TA.rsa_ms, 'VariableNames', {'logLen', 'logDepth', 'rsa'});
stats.model_additive_allPaced = modelSummary(fitlm(ta, 'rsa ~ logLen + logDepth', 'RobustOpts', 'on'));

% binned summaries
lenEdges = [0 4 5 6 7.5 9 11 Inf];
lenLab = {'<4', '4-5', '5-6', '6-7.5', '7.5-9', '9-11', '>11'};
ampQ = quantile(T.depth, [1/3 2/3]);
ampBin = 1 + (T.depth > ampQ(1)) + (T.depth > ampQ(2));
ampLab = {'shallow', 'medium', 'deep'};
lenBin = discretize(T.length, lenEdges);
binTbl = table();
for i = 1:numel(lenLab)
    for j = 1:3
        m = lenBin == i & ampBin == j;
        binTbl = [binTbl; table(string(lenLab{i}), string(ampLab{j}), sum(m), median(T.rsa_ms(m)), iqr(T.rsa_ms(m)), median(T.length(m)), median(T.depth(m)), median(T.amp(m)), median(T.hrBPM(m), 'omitnan'), ...
            'VariableNames', {'lengthBin', 'depthBin', 'n', 'medRSA_ms', 'iqrRSA_ms', 'medLength_s', 'medDepth', 'medAmp', 'medHR'})]; %#ok<AGROW>
    end
end
writetable(binTbl, fullfile(outDir, [id '_rsa_by_length_depth.csv']));
stats.depthTertileCuts = ampQ(:)';

% ---------------- final 10 min vs rest ----------------
grpNames = {'final10', 'restAll', 'pacedAll', 'preNatural'};
grpMask  = {final10, ~final10, paced, pre};
vars = {'length', 'rateBPM', 'amp', 'rsa_ms', 'rsaNorm', 'hrBPM', 'localPeriodCV', 'nSubPeaks'};
if hasVol, vars{end+1} = 'depthVol'; end
cmp = table();
for v = 1:numel(vars)
    x1 = B.(vars{v})(grpMask{1} & B.good);
    for g = 2:numel(grpNames)
        x2 = B.(vars{v})(grpMask{g} & B.good);
        x1f = x1(isfinite(x1)); x2f = x2(isfinite(x2));
        if numel(x1f) >= 5 && numel(x2f) >= 5
            p = ranksum(x1f, x2f); cd = cliffsDelta(x1f, x2f);
        else
            p = NaN; cd = NaN;
        end
        cmp = [cmp; table(string(vars{v}), string(grpNames{g}), numel(x1f), numel(x2f), median(x1f), median(x2f), quantile(x1f, .25), quantile(x1f, .75), quantile(x2f, .25), quantile(x2f, .75), p, cd, ...
            'VariableNames', {'measure', 'comparedTo', 'nFinal10', 'nOther', 'medFinal10', 'medOther', 'q1Final10', 'q3Final10', 'q1Other', 'q3Other', 'ranksumP', 'cliffsDelta'})]; %#ok<AGROW>
    end
end
writetable(cmp, fullfile(outDir, [id '_final10_vs_rest.csv']));
% matched-length comparison: final10 vs paced breaths in the same length bins
fB = B(final10 & B.good & isfinite(B.rsa_ms) & B.length > 0 & isfinite(B.depth), :);
pB = B(paced & B.good & isfinite(B.rsa_ms), :);
fLen = discretize(fB.length, lenEdges); pLen = discretize(pB.length, lenEdges);
matched = table();
for i = 1:numel(lenLab)
    a = fB.rsa_ms(fLen == i); c = pB.rsa_ms(pLen == i);
    if numel(a) >= 5 && numel(c) >= 5
        matched = [matched; table(string(lenLab{i}), numel(a), numel(c), median(a), median(c), ranksum(a, c), cliffsDelta(a, c), median(fB.depth(fLen == i)), median(pB.depth(pLen == i)), ...
            'VariableNames', {'lengthBin', 'nFinal10', 'nPaced', 'medRSAfinal_ms', 'medRSApaced_ms', 'ranksumP', 'cliffsDelta', 'medDepthFinal', 'medDepthPaced'})]; %#ok<AGROW>
    end
end
writetable(matched, fullfile(outDir, [id '_final10_vs_paced_matchedLength.csv']));
% additive-model prediction for the final-10 breaths
pf = predict(m1, table(log(fB.length) - muL, log(fB.depth) - muA, 'VariableNames', {'logLen', 'logDepth'}));
stats.final10_additiveModel = struct('n', numel(pf), 'meanObserved_ms', mean(fB.rsa_ms), 'meanPredicted_ms', mean(pf), ...
    'meanError_ms', mean(fB.rsa_ms - pf), 'semError_ms', std(fB.rsa_ms - pf) / sqrt(numel(pf)), 'medianError_ms', median(fB.rsa_ms - pf), ...
    'signrankP', signrank(fB.rsa_ms - pf), 'ttestP', ttestP(fB.rsa_ms - pf));
stats.final10_vs_pre = cmp(cmp.comparedTo == "preNatural", :);
stats.hr_pre = median(B.hrBPM(pre), 'omitnan'); stats.hr_paced = median(B.hrBPM(paced), 'omitnan'); stats.hr_final10 = median(B.hrBPM(final10), 'omitnan');

% ---------------- 2-D surface: local-linear (LOESS-style) RSA estimate on paced breaths ----------------
% predictors standardised in log space (paced set); Gaussian kernel, bandwidth h SD units
sdL = std(log(T.length)); sdA = std(log(T.depth));
u = (log(T.length) - muL) / sdL; v = (log(T.depth) - muA) / sdA;
h = 0.35;
gL = linspace(log(2.5), log(11), 46); gA = linspace(log(prctile(T.depth, 0.5)), log(prctile(T.depth, 99.5)), 46);
[GL, GA] = meshgrid(gL, gA);
GU = (GL - muL) / sdL; GV = (GA - muA) / sdA;
Zhat = nan(size(GL)); Wsum = zeros(size(GL));
for i = 1:numel(GL)
    d2 = ((u - GU(i)).^2 + (v - GV(i)).^2) / h^2;
    w = exp(-0.5 * d2); w(d2 > 9) = 0;
    ws = sum(w); Wsum(i) = ws;
    if ws < 8, continue; end
    X = [ones(size(u)), u - GU(i), v - GV(i)];
    beta = (X' * (w .* X)) \ (X' * (w .* T.rsa_ms));
    Zhat(i) = beta(1);
end
% predict the final-10 breaths from the same local-linear fit (on the paced data)
uF = (log(fB.length) - muL) / sdL; vF = (log(fB.depth) - muA) / sdA;
predF = nan(height(fB), 1); supF = zeros(height(fB), 1);
for k = 1:height(fB)
    d2 = ((u - uF(k)).^2 + (v - vF(k)).^2) / h^2;
    w = exp(-0.5 * d2); w(d2 > 9) = 0; supF(k) = sum(w);
    if supF(k) < 8, continue; end
    X = [ones(size(u)), u - uF(k), v - vF(k)];
    beta = (X' * (w .* X)) \ (X' * (w .* T.rsa_ms));
    predF(k) = beta(1);
end
errF = fB.rsa_ms - predF;
okF = isfinite(errF);
stats.final10_surfaceModel = struct('bandwidthSD', h, 'nFinal10', height(fB), 'nInsideSupport', sum(okF), ...
    'meanObserved_ms', mean(fB.rsa_ms(okF)), 'meanPredicted_ms', mean(predF(okF)), 'meanError_ms', mean(errF(okF)), ...
    'semError_ms', std(errF(okF)) / sqrt(sum(okF)), 'medianError_ms', median(errF(okF)), 'sdError_ms', std(errF(okF)), ...
    'signrankP', signrank(errF(okF)), 'ttestP', ttestP(errF(okF)), 'rmse_ms', sqrt(mean(errF(okF).^2)));
% kernel-weighted mean prediction error of the final-10 breaths over the grid
Zerr = nan(size(GL)); WsumF = zeros(size(GL));
for i = 1:numel(GL)
    d2 = ((uF(okF) - GU(i)).^2 + (vF(okF) - GV(i)).^2) / h^2;
    w = exp(-0.5 * d2); w(d2 > 9) = 0;
    ws = sum(w); WsumF(i) = ws;
    if ws < 3 || ~isfinite(Zhat(i)), continue; end
    Zerr(i) = sum(w .* errF(okF)) / ws;
end
fB.predSurface_ms = predF; fB.errSurface_ms = errF; fB.predAdditive_ms = pf; fB.errAdditive_ms = fB.rsa_ms - pf;
writetable(fB(:, {'onsetSec', 'length', 'depth', 'amp', 'rsa_ms', 'predSurface_ms', 'errSurface_ms', 'predAdditive_ms', 'errAdditive_ms', 'nSubPeaks', 'localPeriodCV'}), ...
    fullfile(outDir, [id '_final10_predictions.csv']));
% the final-10 block mean (good breaths)
fMean = struct('length', mean(fB.length), 'depth', mean(fB.depth), 'amp', mean(fB.amp), 'rsa', mean(fB.rsa_ms), ...
               'lengthSD', std(fB.length), 'depthSD', std(fB.depth), 'ampSD', std(fB.amp), 'rsaSD', std(fB.rsa_ms), 'n', height(fB));
stats.final10_mean = fMean;

% ---------------- inhale-locked RR (polarity + RSA shape check) ----------------
win = round(-2 * fsP):round(8 * fsP); tw = win / fsP;
lockRR = @(mask) cell2mat(arrayfun(@(o) lockedSeg(RR, round(o * fsP), win), onsetSec(mask & B.good), 'UniformOutput', false));
LK.paced = lockRR(paced); LK.pre = lockRR(pre); LK.final10 = lockRR(final10);
for f = fieldnames(LK)'
    M = LK.(f{1});
    if ~isempty(M)
        M = M - mean(M(:, tw >= -1 & tw <= 0), 2, 'omitnan');
        mu = mean(M, 1, 'omitnan') * 1000;
        [~, iMin] = min(mu(tw >= 0 & tw <= 6)); tt = tw(tw >= 0 & tw <= 6);
        stats.inhaleLocked.(f{1}) = struct('n', size(M, 1), 'minRRchange_ms', min(mu(tw >= 0 & tw <= 6)), 'timeOfMin_s', tt(iMin), ...
            'maxRRchange_ms', max(mu(tw >= 0 & tw <= 8)));
        LK.(f{1}) = mu;
    end
end

% ---------------- figures ----------------
cols = lines(7);
cFinal = [0.29 0.23 0.65];      % violet for the final 10 min
cPre = cols(2, :); cPaced = cols(5, :);
periodCol = {[0.80 0.90 1.0], [0.90 0.90 0.90], [1.0 0.90 0.80]};
% F1 time course with the three periods
fig = figure('Visible', 'off', 'Position', [40 40 1800 1100], 'Color', 'w');
panels = {'rateBPM', 'breath rate (/min)'; 'depth', DEPTHLAB; 'rsa_ms', 'RSA = within-breath RR max-min (ms)'; 'hrBPM', 'heart rate (bpm)'};
ax = gobjects(4, 1);
bounds = [0 PRE_SEC; PRE_SEC durS - FINAL_SEC; durS - FINAL_SEC durS] / 60;
for p = 1:4
    ax(p) = subplot(4, 1, p); hold on
    y = B.(panels{p, 1}); yl = [prctile(y, 0.5), prctile(y, 99.5)]; if p == 1, yl = [0 30]; end
    for k = 1:3
        patch([bounds(k, 1) bounds(k, 2) bounds(k, 2) bounds(k, 1)], [yl(1) yl(1) yl(2) yl(2)], periodCol{k}, 'EdgeColor', 'none', 'FaceAlpha', 0.6);
    end
    scatter(onsetSec(~B.good) / 60, y(~B.good), 6, [0.75 0.75 0.75], 'filled');
    scatter(onsetSec(B.good) / 60, y(B.good), 8, cols(1, :), 'filled');
    for k = 1:numel(seamSec), xline(seamSec(k) / 60, 'r--', 'LineWidth', 1); end
    ylim(yl); ylabel(panels{p, 2}); grid on
    if p == 1
        title(sprintf('%s - per-breath time course (blue band = first %g min audiobook/instructions, grey = paced breathing, orange = final %g min focused breathing; grey dots = failed breath QC; red dashed = recording seam)', id, PRE_SEC / 60, FINAL_SEC / 60), 'Interpreter', 'none');
    end
end
xlabel('time (min)'); linkaxes(ax, 'x'); xlim([0 durS / 60]);
saveas(fig, fullfile(outDir, 'F1_timecourse.png')); close(fig);

% F2 RSA vs length / depth with the final 10 min overlaid
fig = figure('Visible', 'off', 'Position', [40 40 1800 650], 'Color', 'w');
subplot(1, 3, 1); hold on
hs = gobjects(1, 5);
for j = 1:3
    m = ampBin == j; hs(j) = scatter(T.length(m), T.rsa_ms(m), 12, cols(j, :), 'filled', 'MarkerFaceAlpha', 0.35);
end
for i = 1:numel(lenLab)
    m = lenBin == i; if sum(m) < 8, continue; end
    errorbar(median(T.length(m)), median(T.rsa_ms(m)), iqr(T.rsa_ms(m)) / 2, 'ko', 'MarkerFaceColor', 'k', 'LineWidth', 1.2);
end
hs(4) = scatter(fB.length, fB.rsa_ms, 22, cFinal, 'filled', 'MarkerFaceAlpha', 0.7, 'MarkerEdgeColor', 'w');
errorbar(fMean.length, fMean.rsa, fMean.rsaSD, fMean.rsaSD, fMean.lengthSD, fMean.lengthSD, 'd', 'Color', cFinal, 'LineWidth', 1.5, 'CapSize', 6);
hs(5) = plot(fMean.length, fMean.rsa, 'd', 'MarkerSize', 13, 'MarkerFaceColor', cFinal, 'MarkerEdgeColor', 'k', 'LineWidth', 1.2);
xlabel('breath length (s)'); ylabel('RSA (ms)'); title('RSA vs length (paced, colour = volume tertile; final 10 min overlaid)'); grid on
legend(hs, [ampLab, {'final 10 min (breaths)', sprintf('final 10 min mean \\pm SD (n=%d)', fMean.n)}], 'Location', 'northwest');
subplot(1, 3, 2); hold on
hs = gobjects(1, 5);
lenBin3 = discretize(T.length, [0 5.5 8 Inf]); lenLab3 = {'short <5.5 s', 'medium 5.5-8 s', 'long >8 s'};
for i = 1:3
    m = lenBin3 == i; hs(i) = scatter(T.depth(m), T.rsa_ms(m), 12, cols(3 + i, :), 'filled', 'MarkerFaceAlpha', 0.35);
end
aE = quantile(T.depth, 0:0.2:1);
for i = 1:5
    m = T.depth >= aE(i) & T.depth <= aE(i + 1);
    errorbar(median(T.depth(m)), median(T.rsa_ms(m)), iqr(T.rsa_ms(m)) / 2, 'ko', 'MarkerFaceColor', 'k', 'LineWidth', 1.2);
end
hs(4) = scatter(fB.depth, fB.rsa_ms, 22, cFinal, 'filled', 'MarkerFaceAlpha', 0.7, 'MarkerEdgeColor', 'w');
errorbar(fMean.depth, fMean.rsa, fMean.rsaSD, fMean.rsaSD, fMean.depthSD, fMean.depthSD, 'd', 'Color', cFinal, 'LineWidth', 1.5, 'CapSize', 6);
hs(5) = plot(fMean.depth, fMean.rsa, 'd', 'MarkerSize', 13, 'MarkerFaceColor', cFinal, 'MarkerEdgeColor', 'k', 'LineWidth', 1.2);
xlim([0 max(prctile(T.depth, 99.5), max(fB.depth)) * 1.05]);
xlabel(DEPTHLAB); ylabel('RSA (ms)'); title(['RSA vs ' DEPTHSHORT ' (paced, colour = length tercile; final 10 min overlaid)']); grid on
legend(hs, [lenLab3, {'final 10 min (breaths)', 'final 10 min mean \pm SD'}], 'Location', 'northeast');
subplot(2, 3, 3); hold on
g = linspace(min(mdlTbl.logLen), max(mdlTbl.logLen), 50)';
yhatL = predict(m1, table(g, zeros(size(g)), 'VariableNames', {'logLen', 'logDepth'}));
ga = linspace(min(mdlTbl.logDepth), max(mdlTbl.logDepth), 50)';
yhatA = predict(m1, table(zeros(size(ga)), ga, 'VariableNames', {'logLen', 'logDepth'}));
yl2 = [min([yhatL; yhatA]) - 10, max([yhatL; yhatA]) + 10];
plot(exp(g + muL), yhatL, '-', 'Color', cols(1, :), 'LineWidth', 2); ylim(yl2);
xlabel('breath length (s) [at median depth]'); ylabel('model RSA (ms)'); grid on
title(sprintf('additive model, R^2 = %.2f: length effect', m1.Rsquared.Ordinary));
subplot(2, 3, 6); hold on
plot(exp(ga + muA), yhatA, '-', 'Color', cols(2, :), 'LineWidth', 2); ylim(yl2);
xlabel([DEPTHSHORT ' [at median length]']); ylabel('model RSA (ms)'); grid on
title([DEPTHSHORT ' effect (same y scale)']);
saveas(fig, fullfile(outDir, 'F2_rsa_vs_length_depth.png')); close(fig);

% F3 heat map (single-hue ramp)
blueRamp = interp1([0 1], [0.80 0.89 0.98; 0.05 0.21 0.42], linspace(0, 1, 64));
fig = figure('Visible', 'off', 'Position', [40 40 900 650], 'Color', 'w');
H = nan(3, numel(lenLab)); N = zeros(3, numel(lenLab));
for i = 1:numel(lenLab), for j = 1:3, m = lenBin == i & ampBin == j; N(j, i) = sum(m); if sum(m) >= 8, H(j, i) = median(T.rsa_ms(m)); end, end, end
imagesc(H, 'AlphaData', ~isnan(H)); colormap(blueRamp); cb = colorbar; cb.Label.String = 'median RSA (ms)';
set(gca, 'XTick', 1:numel(lenLab), 'XTickLabel', lenLab, 'YTick', 1:3, 'YTickLabel', ampLab, 'YDir', 'normal');
for i = 1:numel(lenLab), for j = 1:3, if N(j, i) > 0, tc = 'k'; if ~isnan(H(j, i)) && H(j, i) > 105, tc = 'w'; end, text(i, j, sprintf('%s\nn=%d', num2strOrDash(H(j, i)), N(j, i)), 'HorizontalAlignment', 'center', 'FontSize', 9, 'Color', tc); end, end, end
xlabel('breath length (s)'); ylabel('depth tertile (paced breaths)'); title('median RSA by breath length x depth (cells with n >= 8)');
saveas(fig, fullfile(outDir, 'F3_rsa_heatmap.png')); close(fig);

% F8 estimated-RSA surface (local-linear fit on paced breaths) with the final-10 breaths on top
tickL = [2.5 3 4 5 6 8 10];
tickA = unique(round(exp(linspace(gA(1), gA(end), 7)), 2, 'significant'));
if max(tickA) > 5000, tickALab = arrayfun(@(v) sprintf('%.0fk', v / 1e3), tickA, 'UniformOutput', false); else, tickALab = arrayfun(@(v) sprintf('%g', v), tickA, 'UniformOutput', false); end
fig = figure('Visible', 'off', 'Position', [40 40 1000 780], 'Color', 'w');
imagesc(gL, gA, Zhat, 'AlphaData', ~isnan(Zhat)); set(gca, 'YDir', 'normal'); hold on
colormap(gca, blueRamp); cb = colorbar; cb.Label.String = 'estimated RSA (ms), local-linear fit on paced breaths';
clim([50 160]);
[C, hc] = contour(gL, gA, Zhat, 60:20:160, 'LineColor', 'w', 'LineWidth', 1); clabel(C, hc, 'Color', 'w', 'FontSize', 9);
scatter(log(T.length), log(T.depth), 4, [0.55 0.55 0.55], 'filled', 'MarkerFaceAlpha', 0.35);
scatter(log(fB.length), log(fB.depth), 26, cFinal, 'filled', 'MarkerEdgeColor', 'w', 'LineWidth', 0.6);
plot(log(fMean.length), log(fMean.depth), 'd', 'MarkerSize', 15, 'MarkerFaceColor', cFinal, 'MarkerEdgeColor', 'k', 'LineWidth', 1.3);
set(gca, 'XTick', log(tickL), 'XTickLabel', tickL, 'YTick', log(tickA), 'YTickLabel', tickALab);
xlabel('breath length (s), log axis'); ylabel([DEPTHLAB ', log axis']);
title(sprintf('%s - estimated RSA over breath length x %s (paced breaths, n=%d; bandwidth %.2f SD; blank = too few paced breaths)\ngrey dots = paced breaths, violet = final 10 min (n=%d), diamond = final-10 mean', id, DEPTHSHORT, height(T), h, height(fB)), 'Interpreter', 'none');
saveas(fig, fullfile(outDir, 'F8_rsa_surface.png')); close(fig);

% F9 mean prediction error of the final-10 breaths over the same surface
divRamp = [interp1([0 1], [0.16 0.47 0.84; 0.91 0.91 0.90], linspace(0, 1, 32)); interp1([0 1], [0.91 0.91 0.90; 0.89 0.29 0.28], linspace(0, 1, 32))];
fig = figure('Visible', 'off', 'Position', [40 40 1000 780], 'Color', 'w');
lim = max(20, min(60, ceil(prctile(abs(Zerr(~isnan(Zerr))), 95) / 10) * 10));
imagesc(gL, gA, Zerr, 'AlphaData', ~isnan(Zerr)); set(gca, 'YDir', 'normal'); hold on
colormap(gca, divRamp); cb = colorbar; cb.Label.String = 'mean prediction error, observed - predicted RSA (ms)';
clim([-lim lim]);
contour(gL, gA, Zhat, 60:20:160, 'LineColor', [0.5 0.5 0.5], 'LineWidth', 0.8);
scatter(log(fB.length(okF)), log(fB.depth(okF)), 30, errF(okF), 'filled', 'MarkerEdgeColor', 'k', 'LineWidth', 0.5);
scatter(log(fB.length(~okF)), log(fB.depth(~okF)), 30, 'x', 'MarkerEdgeColor', 'k');
plot(log(fMean.length), log(fMean.depth), 'd', 'MarkerSize', 15, 'MarkerFaceColor', 'none', 'MarkerEdgeColor', 'k', 'LineWidth', 1.5);
set(gca, 'XTick', log(tickL), 'XTickLabel', tickL, 'YTick', log(tickA), 'YTickLabel', tickALab);
xlabel('breath length (s), log axis'); ylabel([DEPTHLAB ', log axis']);
sm = stats.final10_surfaceModel;
title(sprintf('%s - final 10 min: observed minus predicted RSA (model fitted on paced breathing)\nkernel-weighted mean error surface; dots = individual final-10 breaths coloured by their error (x = outside paced support)\nmean error %+.1f \\pm %.1f ms (SEM), median %+.1f ms, n=%d/%d, sign-rank p=%.3f, RMSE %.0f ms; grey contours = estimated RSA', ...
    strrep(id, '_', '\_'), sm.meanError_ms, sm.semError_ms, sm.medianError_ms, sm.nInsideSupport, sm.nFinal10, sm.signrankP, sm.rmse_ms), 'Interpreter', 'tex');
saveas(fig, fullfile(outDir, 'F9_final10_prediction_error.png')); close(fig);

% F5 final 10 min vs rest
fig = figure('Visible', 'off', 'Position', [40 40 1800 800], 'Color', 'w');
vlist = {'length', 'depth', 'rsa_ms', 'hrBPM', 'localPeriodCV', 'nSubPeaks'};
vname = {'breath length (s)', DEPTHLAB, 'RSA (ms)', 'heart rate (bpm)', 'local period CV', 'sub-peaks per breath'};
gm = {final10, pre, paced}; gcols = {cFinal, cPre, cPaced};
for v = 1:numel(vlist)
    subplot(2, 3, v); hold on
    for g2 = 1:3
        x = B.(vlist{v})(gm{g2} & B.good); x = x(isfinite(x));
        if isempty(x), continue; end
        boxchart(g2 * ones(size(x)), x, 'BoxFaceColor', gcols{g2}, 'MarkerStyle', '.');
    end
    set(gca, 'XTick', 1:3, 'XTickLabel', {sprintf('final %g min', FINAL_SEC / 60), sprintf('first %g min', PRE_SEC / 60), 'paced'}); ylabel(vname{v}); grid on
    if strcmp(vlist{v}, 'nSubPeaks'), ylim([0 6]); end
end
sgtitle(sprintf('%s - last %g min (focused) vs first %g min (audiobook/instructions) vs paced breathing (good breaths)', id, FINAL_SEC / 60, PRE_SEC / 60), 'Interpreter', 'none');
saveas(fig, fullfile(outDir, 'F5_final10_vs_rest.png')); close(fig);

% F6 inhale-locked RR
fig = figure('Visible', 'off', 'Position', [40 40 1000 550], 'Color', 'w'); hold on
lg = {};
for f = fieldnames(LK)'
    if isempty(LK.(f{1})), continue; end
    plot(tw, LK.(f{1}), 'LineWidth', 2); lg{end+1} = sprintf('%s (n=%d)', f{1}, stats.inhaleLocked.(f{1}).n); %#ok<AGROW>
end
xline(0, 'k--'); yline(0, 'k:'); xlabel('time from inhale onset (s)'); ylabel('RR change from pre-onset baseline (ms)');
title('inhale-locked mean RR interval (RR should fall = heart speeds up during inhalation)'); legend(lg, 'Location', 'best'); grid on
saveas(fig, fullfile(outDir, 'F6_inhale_locked_RR.png')); close(fig);

% ---------------- write stats ----------------
stats.binned = binTbl;
stats.final10_vs_rest = cmp;
stats.final10_vs_paced_matchedLength = matched;
fid = fopen(fullfile(outDir, [id '_stats.json']), 'w'); fwrite(fid, jsonencode(stats, 'PrettyPrint', true)); fclose(fid);
writetable(B, fullfile(outDir, [id '_perBreath_analysis.csv']));
save(fullfile(outDir, [id '_summary.mat']), 'stats', 'B', 'K', 'LK', 'tw', 'gL', 'gA', 'Zhat', 'Zerr', 'Wsum', 'WsumF');
fprintf('pacedBreathing_respHRV_summary: DONE -> %s\n', outDir);
fprintf('  periods: pre %d breaths (<%d s), paced %d, final10 %d\n', sum(pre), PRE_SEC, sum(paced), sum(final10));
fprintf('  additive model: len coef %.1f ms per log-unit (p=%.3g), amp coef %.1f (p=%.3g), R2=%.2f, n=%d\n', ...
    stats.model_additive.coef(2), stats.model_additive.p(2), stats.model_additive.coef(3), stats.model_additive.p(3), stats.model_additive.R2, stats.model_additive.n);
fprintf('  final10 surface prediction: obs %.1f pred %.1f err %+.1f +- %.1f (SEM) median %+.1f, n=%d/%d, p=%.3g\n', ...
    sm.meanObserved_ms, sm.meanPredicted_ms, sm.meanError_ms, sm.semError_ms, sm.medianError_ms, sm.nInsideSupport, sm.nFinal10, sm.signrankP);
am = stats.final10_additiveModel;
fprintf('  final10 additive prediction: obs %.1f pred %.1f err %+.1f +- %.1f median %+.1f p=%.3g\n', am.meanObserved_ms, am.meanPredicted_ms, am.meanError_ms, am.semError_ms, am.medianError_ms, am.signrankP);
disp(cmp(cmp.measure == "rsa_ms", :));

% ============================ helpers ============================
function s = modelSummary(m)
    s = struct('formula', char(m.Formula), 'coefNames', {m.CoefficientNames}, 'coef', m.Coefficients.Estimate', ...
               'se', m.Coefficients.SE', 'p', m.Coefficients.pValue', 'R2', m.Rsquared.Ordinary, 'R2adj', m.Rsquared.Adjusted, ...
               'n', m.NumObservations, 'rmse', m.RMSE);
end
function d = cliffsDelta(a, b)
    a = a(:); b = b(:); n = 0;
    for i = 1:numel(a), n = n + sum(a(i) > b) - sum(a(i) < b); end
    d = n / (numel(a) * numel(b));
end
function seg = lockedSeg(x, i0, win)
    idx = i0 + win; seg = nan(1, numel(win)); ok = idx >= 1 & idx <= numel(x); seg(ok) = x(idx(ok));
end
function s = num2strOrDash(v)
    if isnan(v), s = '-'; else, s = sprintf('%.0f', v); end
end
function p = ttestP(x)
    x = x(isfinite(x)); [~, p] = ttest(x);
end

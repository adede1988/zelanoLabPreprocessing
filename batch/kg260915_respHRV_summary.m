% kg260915_respHRV_summary - respiratory HRV (within-breath RSA) as a function
% of breath length and depth for a pacedBreathing session, plus a final-10-min
% (focused breathing) vs rest comparison. Runs on the compact pack written by
% batch/kg260915_summaryPack.m (no EEG needed).
%
%   env ZLP_PACK    path to <id>_pacedBreathing_pack.mat
%   env ZLP_SUMOUT  output folder (figures PNG + stats JSON + CSV tables)
%
% Definitions
%   RSA (ms)      per-breath RR_max_min from flagBadBreaths = max RR - min RR
%                 inside the breath (inhale onset -> next onset), ms
%   length (s)    breath period (bmObj col 7)
%   depth         breath amplitude (bmObj col 8, raw respiration units) and,
%                 where present, bm_inhaleVolumesRaw (raw-unit inhale volume)
%   good          flagBadBreaths goodBreath == 1
%   clean         good & nSubPeaks <= 1 & localPeriodCV < 0.20 (not ragged)
%   final10       breaths whose onset falls in the last 600 s of the recording
%                 (the user's definition of the focused-breathing period)

packPath = getenv('ZLP_PACK');   assert(~isempty(packPath), 'set ZLP_PACK');
outDir   = getenv('ZLP_SUMOUT'); if isempty(outDir), outDir = fullfile(fileparts(packPath), 'summary'); end
if ~isfolder(outDir), mkdir(outDir); end
S = load(packPath);
B = S.behDat; K = S.blocks; fs = S.fs; fsP = S.fsPack;
durS = S.nSamples / fs;
id = S.sessID;
fprintf('%s: %d breaths, %d blocks, %.1f min\n', id, height(B), height(K), durS / 60);

% ---------------- per-breath derived quantities ----------------
onsetSec = B.finalOnset / fs;
B.onsetSec = onsetSec;
B.rsa_ms  = 1000 * B.RR_max_min;
B.good    = B.goodBreath == 1;
B.clean   = B.good & B.nSubPeaks <= 1 & B.localPeriodCV < 0.20;
B.final10 = onsetSec >= durS - 600;
B.blockLabel = string(B.task);
% mean RR / HR over each breath from the 50-Hz RRint
RR = S.RRint(:)'; tP = S.t(:)';
B.meanRR = nan(height(B), 1);
for b = 1:height(B)
    i0 = max(1, round(onsetSec(b) * fsP)); i1 = min(numel(RR), round((onsetSec(b) + B.length(b)) * fsP));
    if i1 > i0, B.meanRR(b) = mean(RR(i0:i1), 'omitnan'); end
end
B.hrBPM = 60 ./ B.meanRR;
B.rsaNorm = B.rsa_ms ./ (1000 * B.meanRR);       % RSA as a fraction of the mean RR
hasVol = ismember('bm_inhaleVolumesRaw', B.Properties.VariableNames);
if hasVol, B.depthVol = B.bm_inhaleVolumesRaw; end

paced = B.blockLabel == "paced";
pre   = B.blockLabel == "pre";
fin   = B.blockLabel == "final";

stats = struct();
stats.sessID = id; stats.durationMin = durS / 60;
stats.nBreaths = height(B); stats.nGood = sum(B.good); stats.nClean = sum(B.clean);
stats.nPaced = sum(paced); stats.nPre = sum(pre); stats.nFinalBlock = sum(fin); stats.nFinal10 = sum(B.final10);
stats.ecgSkipped = S.ecgSkipped;
stats.hrOverall = median(B.hrBPM, 'omitnan');
stats.fracGoodPaced = mean(B.good(paced)); stats.fracCleanPaced = mean(B.clean(paced));

% ---------------- block table ----------------
K.medRSA_ms   = nan(height(K), 1); K.medRSAgood_ms = nan(height(K), 1);
K.medHR       = nan(height(K), 1); K.fracGood = nan(height(K), 1); K.fracClean = nan(height(K), 1);
K.medSubPeaks = nan(height(K), 1); K.medLocalPeriodCV = nan(height(K), 1);
if hasVol, K.medVol = nan(height(K), 1); end
for k = 1:height(K)
    m = B.condition == K.order(k);
    K.medRSA_ms(k) = median(B.rsa_ms(m), 'omitnan');
    K.medRSAgood_ms(k) = median(B.rsa_ms(m & B.good), 'omitnan');
    K.medHR(k) = median(B.hrBPM(m), 'omitnan');
    K.fracGood(k) = mean(B.good(m)); K.fracClean(k) = mean(B.clean(m));
    K.medSubPeaks(k) = median(B.nSubPeaks(m), 'omitnan');
    K.medLocalPeriodCV(k) = median(B.localPeriodCV(m), 'omitnan');
    if hasVol, K.medVol(k) = median(B.depthVol(m), 'omitnan'); end
end
K.startMin = K.startSample / fs / 60; K.endMin = K.endSample / fs / 60;
writetable(K, fullfile(outDir, [id '_blocks_summary.csv']));

% ---------------- RSA vs length x depth (paced breaths) ----------------
sel = paced & B.good & isfinite(B.rsa_ms) & B.length > 0 & B.amp > 0;
selC = sel & B.clean;
T = B(sel, :);
[rhoL, pL] = corr(log(T.length), T.rsa_ms, 'Type', 'Spearman', 'rows', 'complete');
[rhoA, pA] = corr(log(T.amp), T.rsa_ms, 'Type', 'Spearman', 'rows', 'complete');
stats.spearman = struct('rsa_vs_logLength', [rhoL pL], 'rsa_vs_logAmp', [rhoA pA]);
if hasVol
    [rhoV, pV] = corr(log(max(T.depthVol, eps)), T.rsa_ms, 'Type', 'Spearman', 'rows', 'complete');
    stats.spearman.rsa_vs_logVol = [rhoV pV];
end
% additive + interaction models on log scales (robust fit)
mdlTbl = table(log(T.length), log(T.amp), T.rsa_ms, 'VariableNames', {'logLen', 'logAmp', 'rsa'});
mdlTbl.logLen = mdlTbl.logLen - mean(mdlTbl.logLen); mdlTbl.logAmp = mdlTbl.logAmp - mean(mdlTbl.logAmp);
m1 = fitlm(mdlTbl, 'rsa ~ logLen + logAmp', 'RobustOpts', 'on');
m2 = fitlm(mdlTbl, 'rsa ~ logLen * logAmp', 'RobustOpts', 'on');
mL = fitlm(mdlTbl, 'rsa ~ logLen', 'RobustOpts', 'on');
mA = fitlm(mdlTbl, 'rsa ~ logAmp', 'RobustOpts', 'on');
stats.model_additive = modelSummary(m1);
stats.model_interaction = modelSummary(m2);
stats.model_lengthOnly = modelSummary(mL);
stats.model_ampOnly = modelSummary(mA);
% same on the clean subset
TC = B(selC, :);
if height(TC) > 30
    tc = table(log(TC.length) - mean(log(TC.length)), log(TC.amp) - mean(log(TC.amp)), TC.rsa_ms, 'VariableNames', {'logLen', 'logAmp', 'rsa'});
    stats.model_additive_clean = modelSummary(fitlm(tc, 'rsa ~ logLen + logAmp', 'RobustOpts', 'on'));
end
% ALL paced breaths incl. bad (sensitivity)
TA = B(paced & isfinite(B.rsa_ms) & B.length > 0 & B.amp > 0, :);
ta = table(log(TA.length) - mean(log(TA.length)), log(TA.amp) - mean(log(TA.amp)), TA.rsa_ms, 'VariableNames', {'logLen', 'logAmp', 'rsa'});
stats.model_additive_allPaced = modelSummary(fitlm(ta, 'rsa ~ logLen + logAmp', 'RobustOpts', 'on'));

% binned summaries
lenEdges = [0 4 5 6 7.5 9 11 Inf];
lenLab = {'<4', '4-5', '5-6', '6-7.5', '7.5-9', '9-11', '>11'};
ampQ = quantile(T.amp, [1/3 2/3]);
ampBin = 1 + (T.amp > ampQ(1)) + (T.amp > ampQ(2));
ampLab = {'shallow', 'medium', 'deep'};
lenBin = discretize(T.length, lenEdges);
binTbl = table();
for i = 1:numel(lenLab)
    for j = 1:3
        m = lenBin == i & ampBin == j;
        binTbl = [binTbl; table(string(lenLab{i}), string(ampLab{j}), sum(m), median(T.rsa_ms(m)), iqr(T.rsa_ms(m)), median(T.length(m)), median(T.amp(m)), median(T.hrBPM(m), 'omitnan'), ...
            'VariableNames', {'lengthBin', 'depthBin', 'n', 'medRSA_ms', 'iqrRSA_ms', 'medLength_s', 'medAmp', 'medHR'})]; %#ok<AGROW>
    end
end
writetable(binTbl, fullfile(outDir, [id '_rsa_by_length_depth.csv']));
stats.depthTertileCuts = ampQ(:)';

% ---------------- final 10 min vs rest ----------------
grpNames = {'final10', 'restAll', 'pacedAll', 'preNatural', 'finalBlock'};
grpMask  = {B.final10, ~B.final10, paced & ~B.final10, pre, fin};
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
        cmp = [cmp; table(string(vars{v}), string(grpNames{g}), numel(x1f), numel(x2f), median(x1f), median(x2f), iqr(x1f), iqr(x2f), p, cd, ...
            'VariableNames', {'measure', 'comparedTo', 'nFinal10', 'nOther', 'medFinal10', 'medOther', 'iqrFinal10', 'iqrOther', 'ranksumP', 'cliffsDelta'})]; %#ok<AGROW>
    end
end
writetable(cmp, fullfile(outDir, [id '_final10_vs_rest.csv']));
% matched-length comparison: final10 vs paced breaths in the same length bins
fB = B(B.final10 & B.good & isfinite(B.rsa_ms), :);
pB = B(paced & ~B.final10 & B.good & isfinite(B.rsa_ms), :);
fLen = discretize(fB.length, lenEdges); pLen = discretize(pB.length, lenEdges);
matched = table();
for i = 1:numel(lenLab)
    a = fB.rsa_ms(fLen == i); c = pB.rsa_ms(pLen == i);
    if numel(a) >= 5 && numel(c) >= 5
        matched = [matched; table(string(lenLab{i}), numel(a), numel(c), median(a), median(c), ranksum(a, c), cliffsDelta(a, c), median(fB.amp(fLen == i)), median(pB.amp(pLen == i)), ...
            'VariableNames', {'lengthBin', 'nFinal10', 'nPaced', 'medRSAfinal_ms', 'medRSApaced_ms', 'ranksumP', 'cliffsDelta', 'medAmpFinal', 'medAmpPaced'})]; %#ok<AGROW>
    end
end
writetable(matched, fullfile(outDir, [id '_final10_vs_paced_matchedLength.csv']));
% model-adjusted: predict final10 RSA from the paced additive model and compare residuals
pf = predict(m1, table(log(fB.length) - mean(log(T.length)), log(fB.amp) - mean(log(T.amp)), 'VariableNames', {'logLen', 'logAmp'}));
stats.final10_modelResidual_ms = struct('median', median(fB.rsa_ms - pf), 'iqr', iqr(fB.rsa_ms - pf), 'n', numel(pf), ...
    'signrankP', signrank(fB.rsa_ms - pf));
% pre-natural vs final10 (both natural breathing) summary
stats.final10_vs_pre = cmp(cmp.comparedTo == "preNatural", :);

% RR / HR over time: first 7 min vs middle vs final 10
stats.hr_pre = median(B.hrBPM(pre), 'omitnan'); stats.hr_paced = median(B.hrBPM(paced), 'omitnan'); stats.hr_final10 = median(B.hrBPM(B.final10), 'omitnan');

% ---------------- inhale-locked RR (polarity + RSA shape check) ----------------
win = round(-2 * fsP):round(8 * fsP); tw = win / fsP;
lockRR = @(mask) cell2mat(arrayfun(@(o) lockedSeg(RR, round(o * fsP), win), onsetSec(mask & B.good), 'UniformOutput', false));
LK.paced = lockRR(paced); LK.pre = lockRR(pre); LK.final10 = lockRR(B.final10);
for f = fieldnames(LK)'
    M = LK.(f{1});
    if ~isempty(M)
        M = M - mean(M(:, tw >= -1 & tw <= 0), 2, 'omitnan');      % baseline = 1 s before onset
        mu = mean(M, 1, 'omitnan') * 1000;
        [~, iMin] = min(mu(tw >= 0 & tw <= 6)); tt = tw(tw >= 0 & tw <= 6);
        stats.inhaleLocked.(f{1}) = struct('n', size(M, 1), 'minRRchange_ms', min(mu(tw >= 0 & tw <= 6)), 'timeOfMin_s', tt(iMin), ...
            'maxRRchange_ms', max(mu(tw >= 0 & tw <= 8)));
        LK.(f{1}) = mu;
    end
end

% ---------------- figures ----------------
cols = lines(7);
% F1 time course
fig = figure('Visible', 'off', 'Position', [40 40 1800 1100], 'Color', 'w');
panels = {'rateBPM', 'breath rate (/min)'; 'amp', 'breath amplitude (raw units)'; 'rsa_ms', 'RSA = within-breath RR max-min (ms)'; 'hrBPM', 'heart rate (bpm)'};
ax = gobjects(4, 1);
for p = 1:4
    ax(p) = subplot(4, 1, p); hold on
    y = B.(panels{p, 1}); yl = [prctile(y, 0.5), prctile(y, 99.5)]; if p == 1, yl = [0 30]; end
    for k = 1:height(K)
        c = [0.85 0.85 0.85]; if K.label(k) == "pre", c = [0.80 0.90 1.0]; elseif K.label(k) == "final", c = [1.0 0.90 0.80]; end
        patch([K.startMin(k) K.endMin(k) K.endMin(k) K.startMin(k)], [yl(1) yl(1) yl(2) yl(2)], c, 'EdgeColor', [0.6 0.6 0.6], 'FaceAlpha', 0.5 + 0.2 * mod(k, 2));
    end
    xline((durS - 600) / 60, 'r--', 'LineWidth', 1.2);
    scatter(onsetSec(~B.good) / 60, y(~B.good), 6, [0.75 0.75 0.75], 'filled');
    scatter(onsetSec(B.good) / 60, y(B.good), 8, cols(1, :), 'filled');
    ylim(yl); ylabel(panels{p, 2}); grid on
    if p == 1
        title(sprintf('%s - per-breath time course (grey = failed breath QC; shaded = inferred blocks; red dashed = last 10 min)', id), 'Interpreter', 'none');
        for k = 1:height(K), text((K.startMin(k) + K.endMin(k)) / 2, 29, sprintf('%d', k), 'HorizontalAlignment', 'center', 'FontSize', 7); end
    end
end
xlabel('time (min)'); linkaxes(ax, 'x'); xlim([0 durS / 60]);
saveas(fig, fullfile(outDir, 'F1_timecourse.png')); close(fig);

% F2 RSA vs length / depth
fig = figure('Visible', 'off', 'Position', [40 40 1800 650], 'Color', 'w');
subplot(1, 3, 1); hold on
for j = 1:3
    m = ampBin == j; scatter(T.length(m), T.rsa_ms(m), 12, cols(j, :), 'filled', 'MarkerFaceAlpha', 0.45);
end
for i = 1:numel(lenLab)
    m = lenBin == i; if sum(m) < 8, continue; end
    errorbar(median(T.length(m)), median(T.rsa_ms(m)), iqr(T.rsa_ms(m)) / 2, 'ko', 'MarkerFaceColor', 'k', 'LineWidth', 1.2);
end
xlabel('breath length (s)'); ylabel('RSA (ms)'); title('paced breaths (good QC): RSA vs length; colour = depth tertile'); legend(ampLab, 'Location', 'northwest'); grid on
subplot(1, 3, 2); hold on
lenBin3 = discretize(T.length, [0 5.5 8 Inf]); lenLab3 = {'short <5.5 s', 'medium 5.5-8 s', 'long >8 s'};
for i = 1:3
    m = lenBin3 == i; scatter(T.amp(m), T.rsa_ms(m), 12, cols(3 + i, :), 'filled', 'MarkerFaceAlpha', 0.45);
end
aE = quantile(T.amp, 0:0.2:1);
for i = 1:5
    m = T.amp >= aE(i) & T.amp <= aE(i + 1);
    errorbar(median(T.amp(m)), median(T.rsa_ms(m)), iqr(T.rsa_ms(m)) / 2, 'ko', 'MarkerFaceColor', 'k', 'LineWidth', 1.2);
end
xlabel('breath amplitude (raw units)'); ylabel('RSA (ms)'); title('RSA vs depth; colour = length tercile'); legend(lenLab3, 'Location', 'northwest'); grid on
subplot(1, 3, 3); hold on
% partial effects from the additive model
g = linspace(min(mdlTbl.logLen), max(mdlTbl.logLen), 50)';
yhatL = predict(m1, table(g, zeros(size(g)), 'VariableNames', {'logLen', 'logAmp'}));
ga = linspace(min(mdlTbl.logAmp), max(mdlTbl.logAmp), 50)';
yhatA = predict(m1, table(zeros(size(ga)), ga, 'VariableNames', {'logLen', 'logAmp'}));
plot(exp(g + mean(log(T.length))), yhatL, '-', 'Color', cols(1, :), 'LineWidth', 2);
xlabel('breath length (s) [at median depth]'); ylabel('model RSA (ms)');
yyaxis right; plot(exp(ga + mean(log(T.amp))), yhatA, '-', 'Color', cols(2, :), 'LineWidth', 2); ylabel('model RSA (ms) [at median length]');
ax3 = gca; ax3.XAxis.Visible = 'on';
title(sprintf('robust additive model: RSA ~ log(len) + log(amp)  R^2=%.2f', m1.Rsquared.Ordinary));
legend({'length effect', 'depth effect (top axis units differ)'}, 'Location', 'northwest'); grid on
saveas(fig, fullfile(outDir, 'F2_rsa_vs_length_depth.png')); close(fig);

% F3 heat map
fig = figure('Visible', 'off', 'Position', [40 40 900 650], 'Color', 'w');
H = nan(3, numel(lenLab)); N = zeros(3, numel(lenLab));
for i = 1:numel(lenLab), for j = 1:3, m = lenBin == i & ampBin == j; N(j, i) = sum(m); if sum(m) >= 8, H(j, i) = median(T.rsa_ms(m)); end, end, end
imagesc(H, 'AlphaData', ~isnan(H)); colormap(parula); cb = colorbar; cb.Label.String = 'median RSA (ms)';
set(gca, 'XTick', 1:numel(lenLab), 'XTickLabel', lenLab, 'YTick', 1:3, 'YTickLabel', ampLab, 'YDir', 'normal');
for i = 1:numel(lenLab), for j = 1:3, if N(j, i) > 0, text(i, j, sprintf('%s\nn=%d', num2strOrDash(H(j, i)), N(j, i)), 'HorizontalAlignment', 'center', 'FontSize', 9); end, end, end
xlabel('breath length (s)'); ylabel('depth tertile (paced breaths)'); title('median RSA by breath length x depth (cells with n >= 8)');
saveas(fig, fullfile(outDir, 'F3_rsa_heatmap.png')); close(fig);

% F4 block level
fig = figure('Visible', 'off', 'Position', [40 40 1400 600], 'Color', 'w');
subplot(1, 2, 1); hold on
kp = K.label == "paced";
scatter(K.medRateBPM(kp), K.medRSAgood_ms(kp), 20 + 3 * K.nBreaths(kp), K.medAmp(kp), 'filled', 'MarkerEdgeColor', 'k');
scatter(K.medRateBPM(~kp), K.medRSAgood_ms(~kp), 20 + 3 * K.nBreaths(~kp), K.medAmp(~kp), 's', 'filled', 'MarkerEdgeColor', 'r', 'LineWidth', 1.5);
for k = 1:height(K), text(K.medRateBPM(k), K.medRSAgood_ms(k), sprintf(' %d', k), 'FontSize', 8); end
cb = colorbar; cb.Label.String = 'block median amplitude'; xlabel('block median breath rate (/min)'); ylabel('block median RSA (ms, good breaths)');
title('one point per inferred block (size = n breaths; squares = pre/final)'); grid on
subplot(1, 2, 2); hold on
scatter(K.medAmp(kp), K.medRSAgood_ms(kp), 20 + 3 * K.nBreaths(kp), K.medRateBPM(kp), 'filled', 'MarkerEdgeColor', 'k');
scatter(K.medAmp(~kp), K.medRSAgood_ms(~kp), 20 + 3 * K.nBreaths(~kp), K.medRateBPM(~kp), 's', 'filled', 'MarkerEdgeColor', 'r', 'LineWidth', 1.5);
for k = 1:height(K), text(K.medAmp(k), K.medRSAgood_ms(k), sprintf(' %d', k), 'FontSize', 8); end
cb = colorbar; cb.Label.String = 'block median rate (/min)'; xlabel('block median amplitude'); ylabel('block median RSA (ms)'); grid on
title('block RSA vs depth (colour = rate)');
saveas(fig, fullfile(outDir, 'F4_blocks.png')); close(fig);

% F5 final 10 min vs rest
fig = figure('Visible', 'off', 'Position', [40 40 1800 800], 'Color', 'w');
vlist = {'length', 'amp', 'rsa_ms', 'hrBPM', 'localPeriodCV', 'nSubPeaks'};
vname = {'breath length (s)', 'amplitude', 'RSA (ms)', 'heart rate (bpm)', 'local period CV', 'sub-peaks per breath'};
groups = {'final10', 'preNatural', 'pacedAll'}; gm = {B.final10, pre, paced & ~B.final10};
for v = 1:numel(vlist)
    subplot(2, 3, v); hold on
    for g = 1:3
        x = B.(vlist{v})(gm{g} & B.good); x = x(isfinite(x));
        if isempty(x), continue; end
        boxchart(g * ones(size(x)), x, 'BoxFaceColor', cols(g, :), 'MarkerStyle', '.');
    end
    set(gca, 'XTick', 1:3, 'XTickLabel', {'final 10 min', 'pre (natural)', 'paced'}); ylabel(vname{v}); grid on
    if strcmp(vlist{v}, 'nSubPeaks'), ylim([0 6]); end
end
sgtitle(sprintf('%s - last 10 min vs the natural pre block and the paced blocks (good breaths)', id), 'Interpreter', 'none');
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

% F7 raggedness per block
fig = figure('Visible', 'off', 'Position', [40 40 1400 500], 'Color', 'w');
subplot(1, 2, 1); bar(K.order, [K.fracGood, K.fracClean]); legend({'good (breath QC)', 'clean (good & single-peaked & regular)'}, 'Location', 'southwest');
xlabel('inferred block'); ylabel('fraction of breaths'); title('breath quality per block'); grid on; ylim([0 1]);
subplot(1, 2, 2); yyaxis left; bar(K.order, K.medSubPeaks); ylabel('median sub-peaks per breath'); yyaxis right; plot(K.order, K.medLocalPeriodCV, 'o-', 'LineWidth', 1.5); ylabel('median local period CV');
xlabel('inferred block'); title('raggedness per block (more sub-peaks / higher CV = more ragged)'); grid on
saveas(fig, fullfile(outDir, 'F7_raggedness.png')); close(fig);

% ---------------- write stats ----------------
stats.blocks = K;
stats.binned = binTbl;
stats.final10_vs_rest = cmp;
stats.final10_vs_paced_matchedLength = matched;
fid = fopen(fullfile(outDir, [id '_stats.json']), 'w'); fwrite(fid, jsonencode(stats, 'PrettyPrint', true)); fclose(fid);
writetable(B, fullfile(outDir, [id '_perBreath_analysis.csv']));
save(fullfile(outDir, [id '_summary.mat']), 'stats', 'B', 'K', 'LK', 'tw');
fprintf('kg260915_respHRV_summary: DONE -> %s\n', outDir);
fprintf('  additive model: len coef %.1f ms per log-unit (p=%.3g), amp coef %.1f (p=%.3g), R2=%.2f, n=%d\n', ...
    stats.model_additive.coef(2), stats.model_additive.p(2), stats.model_additive.coef(3), stats.model_additive.p(3), stats.model_additive.R2, stats.model_additive.n);
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

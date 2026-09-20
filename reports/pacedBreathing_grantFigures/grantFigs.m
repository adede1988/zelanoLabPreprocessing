% grantFigs.m - grant-ready standalone figures from the KG/JW pacedBreathing packs.
% White figures, large bold fonts, bold axes so each panel reads when displayed small.
%   1) JW breath rate over time, dots coloured by period (baseline grey, pacing black, ATB blue)
%   2) RSA x breath-length bin medians for KG and JW on one plot (connected, one colour each,
%      each participant's ATB mean as a diamond, no error bars)
%   3) JW RSA x length local-linear surface, inhale-volume axis limited to 50k-250k
%   4) JW ATB prediction-error surface, same conventions as (3)
% ATB = the final-10-min focused-breathing period (period == "final10").
OUT = 'C:\Users\Adam\AppData\Local\Temp\claude\C--Users-Adam-Documents-GitHub-zelanoLabPreprocessing\3b2bb664-bfec-4a78-80b7-6f24ef8589dc\scratchpad\jw\grant';
if ~isfolder(OUT), mkdir(OUT); end
PACK.kg = 'C:\Users\Adam\AppData\Local\Temp\claude\C--Users-Adam-Documents-GitHub-zelanoLabPreprocessing\3b2bb664-bfec-4a78-80b7-6f24ef8589dc\scratchpad\pack\260915_EEG_NWU_KG_pacedBreathing_pack.mat';
PACK.jw = 'C:\Users\Adam\AppData\Local\Temp\claude\C--Users-Adam-Documents-GitHub-zelanoLabPreprocessing\3b2bb664-bfec-4a78-80b7-6f24ef8589dc\scratchpad\jw\pack\260917_EEG_NWU_JW_pacedBreathing_pack.mat';
PRESEC.kg = 8 * 60;  FINSEC = 10 * 60;   % KG opening = 8 min
PRESEC.jw = 361;                          % JW opening = first recording file (6.02 min)

% ---- fonts / axis styling (one place) ----
FS_TICK = 22; FS_LAB = 27; AXLW = 3;
FS_TICK_S = 26; FS_LAB_S = 31;   % slightly larger fonts for the two surface figures
styleAx = @(ax) set(ax, 'FontSize', FS_TICK, 'FontWeight', 'bold', 'LineWidth', AXLW, ...
    'Box', 'off', 'TickDir', 'out', 'Color', 'w', 'Layer', 'top');
cBase = [0.60 0.60 0.60]; cPace = [0 0 0]; cATB = [0 0.45 0.74];
cKG = [0.85 0.33 0.10]; cJW = [0 0.45 0.74];
blueRamp = interp1([0 1], [0.80 0.89 0.98; 0.05 0.21 0.42], linspace(0, 1, 64));
divRamp = [interp1([0 1], [0.16 0.47 0.84; 0.91 0.91 0.90], linspace(0, 1, 32)); ...
           interp1([0 1], [0.91 0.91 0.90; 0.89 0.29 0.28], linspace(0, 1, 32))];

% ---- load + derive a per-breath table for each participant ----
D = struct();
for tagc = {'kg', 'jw'}
    tag = tagc{1};
    S = load(PACK.(tag));
    B = S.behDat; fs = S.fs; durS = S.nSamples / fs;
    onsetSec = B.finalOnset / fs;
    rsa = 1000 * B.RR_max_min;
    len = B.length;
    depth = B.bm_inhaleVolumesRaw; depth(~isfinite(depth) | depth <= 0) = NaN;
    good = B.goodBreath == 1;
    nearSeam = false(height(B), 1);
    if ismember('nearSeam', B.Properties.VariableNames), nearSeam = logical(B.nearSeam); end
    % 10-s analysis-level seam exclusion (matches the summary script)
    seamSec = [];
    if isfield(S, 'segments') && istable(S.segments) && height(S.segments) > 1
        seamSec = S.segments.startSample(2:end) / fs;
    end
    nearWide = false(height(B), 1);
    for k = 1:numel(seamSec)
        nearWide = nearWide | (onsetSec - 10 <= seamSec(k) & onsetSec + len + 10 >= seamSec(k));
    end
    good = good & ~nearSeam & ~nearWide;
    pre = onsetSec < PRESEC.(tag);
    atb = onsetSec >= durS - FINSEC;
    paced = ~pre & ~atb;
    D.(tag) = struct('onsetSec', onsetSec, 'rate', 60 ./ len, 'len', len, 'depth', depth, ...
        'rsa', rsa, 'good', good, 'nearSeam', nearSeam, 'pre', pre, 'atb', atb, 'paced', paced, ...
        'durS', durS, 'seamSec', seamSec);
    fprintf('%s: %d breaths, dur %.1f min, good paced %d, good ATB %d\n', tag, height(B), durS/60, sum(good&paced), sum(good&atb));
end

%% ===== Figure 1: JW breath rate over time =====
J = D.jw;
keep = ~J.nearSeam;                 % drop breaths straddling the 56-s recording gap (rate artefact)
fig = figure('Color', 'w', 'Units', 'inches', 'Position', [1 1 9 5]);
ax = axes('Parent', fig); hold(ax, 'on');
xmax = J.durS / 60; ymax = 30;
% reserve a clear rectangle in the top-right corner for the legend and drop any
% breath that would fall inside it, so the legend sits on white
lgX0 = 0.67 * xmax; lgY0 = 19.5;
tmin = J.onsetSec / 60;
notLg = ~(tmin > lgX0 & J.rate > lgY0);
% figure-only colour boundaries (a display choice; the analysis periods are unchanged):
% baseline grey out to 12 min, ATB blue from 2 min before the final-10 window
greyMax = 12; blueMin = xmax - 12;
m = keep & notLg & tmin <  greyMax;                  scatter(ax, tmin(m), J.rate(m), 46, cBase, 'filled', 'MarkerFaceAlpha', 0.9);
m = keep & notLg & tmin >= greyMax & tmin < blueMin; scatter(ax, tmin(m), J.rate(m), 46, cPace, 'filled', 'MarkerFaceAlpha', 0.9);
m = keep & notLg & tmin >= blueMin;                  scatter(ax, tmin(m), J.rate(m), 46, cATB, 'filled', 'MarkerFaceAlpha', 0.95);
% large proxy markers so the legend dots are bigger than the data dots
hp = gobjects(1, 3);
hp(1) = plot(ax, nan, nan, 'o', 'MarkerFaceColor', cBase, 'MarkerEdgeColor', 'none', 'MarkerSize', 22);
hp(2) = plot(ax, nan, nan, 'o', 'MarkerFaceColor', cPace, 'MarkerEdgeColor', 'none', 'MarkerSize', 22);
hp(3) = plot(ax, nan, nan, 'o', 'MarkerFaceColor', cATB,  'MarkerEdgeColor', 'none', 'MarkerSize', 22);
xlim(ax, [0 xmax]); ylim(ax, [0 ymax]);
xlabel(ax, 'time (min)', 'FontSize', FS_LAB, 'FontWeight', 'bold');
ylabel(ax, 'breaths / min', 'FontSize', FS_LAB, 'FontWeight', 'bold');
styleAx(ax);
legend(hp, {'baseline', 'pacing', 'ATB'}, 'FontSize', FS_TICK, 'FontWeight', 'bold', ...
    'Location', 'northeast', 'Box', 'off');
exportgraphics(fig, fullfile(OUT, 'JW_breathRate_time.png'), 'Resolution', 300, 'BackgroundColor', 'white');
close(fig);

%% ===== Figure 2: RSA x length bin medians, KG + JW, ATB diamonds =====
lenEdges = [0 4 5 6 7.5 9 11 Inf]; MINN = 8;
fig = figure('Color', 'w', 'Units', 'inches', 'Position', [1 1 7.5 6]);
ax = axes('Parent', fig); hold(ax, 'on');
h = gobjects(1, 2); tags = {'kg', 'jw'}; cols = {cKG, cJW}; names = {'KG', 'JW'};
for t = 1:2
    P = D.(tags{t});
    sel = P.good & P.paced & isfinite(P.rsa) & P.len > 0;
    b = discretize(P.len(sel), lenEdges);
    L = P.len(sel); R = P.rsa(sel);
    xM = []; yM = [];
    for i = 1:numel(lenEdges) - 1
        mm = b == i;
        if sum(mm) >= MINN, xM(end+1) = median(L(mm)); yM(end+1) = median(R(mm)); end %#ok<AGROW>
    end
    plot(ax, xM, yM, '-', 'Color', cols{t}, 'LineWidth', AXLW);
    h(t) = plot(ax, xM, yM, 'o', 'MarkerSize', 11, 'MarkerFaceColor', cols{t}, 'MarkerEdgeColor', cols{t});
    % ATB mean diamond (no error bars)
    a = P.good & P.atb & isfinite(P.rsa) & P.len > 0;
    plot(ax, mean(P.len(a)), mean(P.rsa(a)), 'd', 'MarkerSize', 22, 'MarkerFaceColor', cols{t}, ...
        'MarkerEdgeColor', 'k', 'LineWidth', 2);
end
xlim(ax, [2.5 11]); ylim(ax, [0 240]);
xlabel(ax, 'breath length (s)', 'FontSize', FS_LAB, 'FontWeight', 'bold');
ylabel(ax, 'respHRV (ms)', 'FontSize', FS_LAB, 'FontWeight', 'bold');
styleAx(ax);
legend(h, names, 'FontSize', FS_TICK, 'FontWeight', 'bold', 'Location', 'northwest', 'Box', 'off');
exportgraphics(fig, fullfile(OUT, 'KG_JW_RSA_by_length.png'), 'Resolution', 300, 'BackgroundColor', 'white');
close(fig);

%% ===== shared surface fit for JW (local-linear on good paced breaths) =====
J = D.jw;
selP = J.good & J.paced & isfinite(J.rsa) & J.len > 0 & isfinite(J.depth);
Lp = J.len(selP); Ap = J.depth(selP); Rp = J.rsa(selP);
muL = mean(log(Lp)); muA = mean(log(Ap)); sdL = std(log(Lp)); sdA = std(log(Ap));
u = (log(Lp) - muL) / sdL; v = (log(Ap) - muA) / sdA; hbw = 0.35;
gL = linspace(log(2.5), log(11), 60);
gA = linspace(log(50000), log(250000), 60);      % Y AXIS LIMITED 50k-250k
[GL, GA] = meshgrid(gL, gA);
GU = (GL - muL) / sdL; GV = (GA - muA) / sdA;
Zhat = nan(size(GL));
for i = 1:numel(GL)
    d2 = ((u - GU(i)).^2 + (v - GV(i)).^2) / hbw^2;
    w = exp(-0.5 * d2); w(d2 > 9) = 0; ws = sum(w);
    if ws < 8, continue; end
    X = [ones(size(u)), u - GU(i), v - GV(i)];
    beta = (X' * (w .* X)) \ (X' * (w .* Rp)); Zhat(i) = beta(1);
end
% ATB breaths + per-breath prediction from the paced fit
selF = J.good & J.atb & isfinite(J.rsa) & J.len > 0 & isfinite(J.depth);
Lf = J.len(selF); Af = J.depth(selF); Rf = J.rsa(selF);
uF = (log(Lf) - muL) / sdL; vF = (log(Af) - muA) / sdA;
predF = nan(numel(Lf), 1);
for k = 1:numel(Lf)
    d2 = ((u - uF(k)).^2 + (v - vF(k)).^2) / hbw^2;
    w = exp(-0.5 * d2); w(d2 > 9) = 0;
    if sum(w) < 8, continue; end
    X = [ones(size(u)), u - uF(k), v - vF(k)];
    beta = (X' * (w .* X)) \ (X' * (w .* Rp)); predF(k) = beta(1);
end
errF = Rf - predF; okF = isfinite(errF);
Zerr = nan(size(GL));
for i = 1:numel(GL)
    d2 = ((uF(okF) - GU(i)).^2 + (vF(okF) - GV(i)).^2) / hbw^2;
    w = exp(-0.5 * d2); w(d2 > 9) = 0; ws = sum(w);
    if ws < 3 || ~isfinite(Zhat(i)), continue; end
    Zerr(i) = sum(w .* errF(okF)) / ws;
end
tickL = [2.5 3 4 5 6 8 10];
tickA = [50000 75000 100000 150000 200000 250000];
tickALab = arrayfun(@(z) sprintf('%gk', z/1000), tickA, 'UniformOutput', false);
inRange = @(z) z >= log(50000) & z <= log(250000);

%% ===== Figure 3: JW RSA x length surface =====
fig = figure('Color', 'w', 'Units', 'inches', 'Position', [1 1 8.5 6.5]);
ax = axes('Parent', fig);
imagesc(ax, gL, gA, Zhat, 'AlphaData', ~isnan(Zhat)); set(ax, 'YDir', 'normal'); hold(ax, 'on');
colormap(ax, blueRamp); clim(ax, [50 160]);
cb = colorbar(ax); cb.Label.String = 'respHRV (ms)'; cb.Label.FontSize = FS_LAB; cb.Label.FontWeight = 'bold';
cb.FontSize = FS_TICK; cb.LineWidth = AXLW;
[C, hc] = contour(ax, gL, gA, Zhat, 60:20:160, 'LineColor', 'w', 'LineWidth', 2);
clabel(C, hc, 'Color', 'w', 'FontSize', 18, 'FontWeight', 'bold');
gp = inRange(log(Ap)); scatter(ax, log(Lp(gp)), log(Ap(gp)), 12, [0.55 0.55 0.55], 'filled', 'MarkerFaceAlpha', 0.4);
gf = inRange(log(Af)); scatter(ax, log(Lf(gf)), log(Af(gf)), 40, cATB, 'filled', 'MarkerEdgeColor', 'w', 'LineWidth', 0.7);
plot(ax, log(mean(Lf)), log(mean(Af)), 'd', 'MarkerSize', 22, 'MarkerFaceColor', cATB, 'MarkerEdgeColor', 'k', 'LineWidth', 2);
xlim(ax, [log(2.5) log(11)]); ylim(ax, [log(50000) log(250000)]);
set(ax, 'XTick', log(tickL), 'XTickLabel', tickL, 'YTick', log(tickA), 'YTickLabel', tickALab);
xlabel(ax, 'breath length (s)', 'FontSize', FS_LAB, 'FontWeight', 'bold');
ylabel(ax, 'inhale volume', 'FontSize', FS_LAB, 'FontWeight', 'bold');
styleAx(ax);
set(ax, 'FontSize', FS_TICK_S); ax.XLabel.FontSize = FS_LAB_S; ax.YLabel.FontSize = FS_LAB_S;
cb.FontSize = FS_TICK_S; cb.Label.FontSize = FS_LAB_S;
exportgraphics(fig, fullfile(OUT, 'JW_RSA_surface.png'), 'Resolution', 300, 'BackgroundColor', 'white');
close(fig);

%% ===== Figure 4: JW ATB prediction-error surface =====
fig = figure('Color', 'w', 'Units', 'inches', 'Position', [1 1 8.5 6.5]);
ax = axes('Parent', fig);
lim = max(20, min(60, ceil(prctile(abs(Zerr(~isnan(Zerr))), 95) / 10) * 10));
imagesc(ax, gL, gA, Zerr, 'AlphaData', ~isnan(Zerr)); set(ax, 'YDir', 'normal'); hold(ax, 'on');
colormap(ax, divRamp); clim(ax, [-lim lim]);
cb = colorbar(ax); cb.Label.String = 'observed - predicted respHRV (ms)'; cb.Label.FontSize = FS_LAB - 5;
cb.Label.FontWeight = 'bold'; cb.FontSize = FS_TICK; cb.LineWidth = AXLW;
contour(ax, gL, gA, Zhat, 60:20:160, 'LineColor', [0.5 0.5 0.5], 'LineWidth', 1.5);
gf = inRange(log(Af)) & okF;
scatter(ax, log(Lf(gf)), log(Af(gf)), 46, errF(gf), 'filled', 'MarkerEdgeColor', 'k', 'LineWidth', 0.7);
plot(ax, log(mean(Lf)), log(mean(Af)), 'd', 'MarkerSize', 22, 'MarkerFaceColor', 'none', 'MarkerEdgeColor', 'k', 'LineWidth', 2.5);
xlim(ax, [log(2.5) log(11)]); ylim(ax, [log(50000) log(250000)]);
set(ax, 'XTick', log(tickL), 'XTickLabel', tickL, 'YTick', log(tickA), 'YTickLabel', tickALab);
xlabel(ax, 'breath length (s)', 'FontSize', FS_LAB, 'FontWeight', 'bold');
ylabel(ax, 'inhale volume', 'FontSize', FS_LAB, 'FontWeight', 'bold');
styleAx(ax);
set(ax, 'FontSize', FS_TICK_S); ax.XLabel.FontSize = FS_LAB_S; ax.YLabel.FontSize = FS_LAB_S;
cb.FontSize = FS_TICK_S; cb.Label.FontSize = FS_LAB_S - 6;
exportgraphics(fig, fullfile(OUT, 'JW_ATB_error_surface.png'), 'Resolution', 300, 'BackgroundColor', 'white');
close(fig);

fprintf('grantFigs: DONE -> %s\n', OUT);
d = dir(fullfile(OUT, '*.png'));
for i = 1:numel(d), fprintf('  %7.0f KB  %s\n', d(i).bytes/1024, d(i).name); end

function files = plotSniffTrains_cueTask3(outDat, R)
%PLOTSNIFFTRAINS_CUETASK3  QC figures of the cueTask3 sniff trains (saved, never shown).
%
%   files = plotSniffTrains_cueTask3(outDat, R)
%
%   Into outDat.figs:
%     allSniffs_bySniffIndex.jpg  R.smoothR aligned on finalOnset (-1..+2 s),
%                                 one panel per sniff index (wiTriali) + their means
%     sniffTrains_allTrials.jpg   every trial: the trace from the first SNIFF
%                                 cue - 1 s to the last + 2.5 s, with the cues
%                                 (red), inhale troughs (v) / peaks (^) and
%                                 finalOnset (blue dashed)
%     epochs_sniff<k>.jpg         one montage per sniff index: every trial's
%                                 epoch around that sniff's finalOnset (-1..+1.5 s)
%   files: the written paths.

    fs  = outDat.fs;
    bd  = outDat.behDat;
    s   = R.smoothR;
    T   = numel(s);
    TTL = outDat.TTL;
    sc  = table2array(TTL(:, startsWith(TTL.Properties.VariableNames, 'sniff')));   % nTrial x 3 cues
    nTrial = height(TTL);
    nIdx = size(sc, 2);
    files = {};
    cols = lines(nIdx);
    noOdorTxt = '';
    if ismember('noOdorDelivered', bd.Properties.VariableNames) && any(bd.noOdorDelivered)
        noOdorTxt = sprintf(' | no odor: trial %s', mat2str(unique(bd.n(bd.noOdorDelivered))'));
    end

    % ---- 1. all sniffs by sniff index ----
    t = (-round(1*fs)):round(2*fs);
    h = figure('Visible', 'off', 'Color', 'w', 'Position', [0 0 1800 450]);
    mu = nan(nIdx, numel(t));
    for k = 1:nIdx
        o = round(bd.finalOnset(bd.wiTriali == k));
        E = epochs(o, t);
        mu(k, :) = mean(E, 1, 'omitnan');
        subplot(1, nIdx + 1, k); hold on
        plot(t / fs, E', 'Color', [0.7 0.7 0.7]);
        plot(t / fs, mu(k, :), 'Color', cols(k, :), 'LineWidth', 2);
        xline(0, '--'); box on; grid on
        title(sprintf('sniff %d (n = %d)', k, numel(o)));
        xlabel('s from finalOnset'); if k == 1, ylabel('respiration (smoothed)'); end
    end
    subplot(1, nIdx + 1, nIdx + 1); hold on
    for k = 1:nIdx, plot(t / fs, mu(k, :), 'Color', cols(k, :), 'LineWidth', 2); end
    xline(0, '--'); box on; grid on
    legend(compose('sniff %d', 1:nIdx), 'Location', 'best'); title('means');
    sgtitle([outDat.sessID ' cueTask3: sniffs aligned on finalOnset' noOdorTxt], 'Interpreter', 'none');
    files{end+1} = save1(h, 'allSniffs_bySniffIndex.jpg');

    % ---- 2. every trial's train ----
    nc = 8; nr = ceil(nTrial / nc);
    h = figure('Visible', 'off', 'Color', 'w', 'Position', [0 0 2600 330 * nr]);
    for i = 1:nTrial
        subplot(nr, nc, i); hold on
        a = sc(i, 1) - round(1 * fs); b = sc(i, end) + round(2.5 * fs);
        a = max(1, a); b = min(T, b);
        x0 = sc(i, 1);
        plot(((a:b) - x0) / fs, s(a:b), 'k');
        xline((sc(i, :) - x0) / fs, 'r');
        r = bd.n == i;
        plot((bd.inhaleTrough(r) - x0) / fs, s(bd.inhaleTrough(r)), 'cv', 'MarkerFaceColor', 'c');
        plot((bd.inhalePeak(r) - x0) / fs, s(bd.inhalePeak(r)), 'm^', 'MarkerFaceColor', 'm');
        xline((bd.finalOnset(r) - x0) / fs, 'b--', 'LineWidth', 1.2);
        ttl = sprintf('trial %d', i);
        if any(r)
            j = find(r, 1);
            ttl = sprintf('%d r%d c%d o%d %s', i, bd.run(j), bd.cue(j), bd.odor(j), bd.type(j));
            if bd.noOdorDelivered(j), ttl = [ttl ' NO ODOR']; end %#ok<AGROW>
        end
        title(ttl, 'FontSize', 8); xlim([-1 (sc(i, end) - x0) / fs + 2.5]);
    end
    sgtitle([outDat.sessID ' cueTask3: red = SNIFF cues, v trough, ^ peak, blue = finalOnset (x: s from cue 1)'], ...
        'Interpreter', 'none');
    files{end+1} = save1(h, 'sniffTrains_allTrials.jpg');

    % ---- 3. one montage per sniff index ----
    t = (-round(1*fs)):round(1.5*fs);
    for k = 1:nIdx
        h = figure('Visible', 'off', 'Color', 'w', 'Position', [0 0 2600 300 * nr]);
        for i = 1:nTrial
            subplot(nr, nc, i); hold on
            r = find(bd.n == i & bd.wiTriali == k, 1);
            if isempty(r)
                title(sprintf('trial %d: none', i), 'FontSize', 8); continue
            end
            f0 = round(bd.finalOnset(r));
            ix = f0 + t; okx = ix >= 1 & ix <= T;
            plot(t(okx) / fs, s(ix(okx)), 'k');
            xline(0, 'b--', 'LineWidth', 1.2);
            xline((sc(i, :) - f0) / fs, 'r');
            plot((bd.inhaleTrough(r) - f0) / fs, s(bd.inhaleTrough(r)), 'cv', 'MarkerFaceColor', 'c');
            plot((bd.inhalePeak(r) - f0) / fs, s(bd.inhalePeak(r)), 'm^', 'MarkerFaceColor', 'm');
            xlim([t(1) t(end)] / fs);
            ttl = sprintf('trial %d', i);
            if bd.noOdorDelivered(r), ttl = [ttl ' NO ODOR']; end %#ok<AGROW>
            title(ttl, 'FontSize', 8);
        end
        sgtitle(sprintf('%s cueTask3 sniff %d: epochs on finalOnset (blue); red = SNIFF cues', ...
            outDat.sessID, k), 'Interpreter', 'none');
        files{end+1} = save1(h, sprintf('epochs_sniff%d.jpg', k)); %#ok<AGROW>
    end

    function E = epochs(o, tt)
        idx = o(:) + tt;
        v = idx >= 1 & idx <= T;
        idx(~v) = 1;
        E = s(idx);
        E(~v) = NaN;
    end

    function f = save1(hh, name)
        f = fullfile(outDat.figs, name);
        saveas(hh, f);
        close(hh);
    end
end

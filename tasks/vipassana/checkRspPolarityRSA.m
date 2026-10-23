function result = checkRspPolarityRSA(outDat)
%CHECKRSPPOLARITYRSA  Physiological check that outDat.rspFlip gives inhale-locked RSA.
%
%   result = checkRspPolarityRSA(outDat)
%
%   Respiratory sinus arrhythmia (RSA): heart rate rises (the RR interval
%   falls) shortly after inhale onset. With the chosen respiration polarity
%   (outDat.rspIDX / outDat.rspFlip) correct, the mean RRint time-locked to
%   GOOD inhale onsets inside STILL (task/meditation) blocks should dip just
%   after 0 s. This is a physiological sanity check on rspFlip, independent
%   of the manual polarity read of the raw trace documented in
%   vipassana_design.md section 1 - the main runs it only when respiration is
%   viable (probeRespViability_vipassana) and the ECG stage succeeded
%   (outDat.ecgSkipped == 0), since it consumes the RRint channel that
%   processECG appends.
%
%   Method
%     - onsets = behDat.finalOnset where behDat.goodBreath == 1 (flagBadBreaths)
%       and behDat.still == 1 (a task/meditation block, build_behavior_table_
%       vipassana) - the still blocks are the cleanest breathing;
%     - epoch the RRint channel (label contains 'RRint') from -2 to +4 s
%       around each onset, exactly as shared/plot_sniff_epochs.m epochs the
%       smoothed respiration (NaN where the window falls off the recording
%       edge);
%     - the grand mean across epochs at each lag is the RSA curve;
%     - deltaRRms = 1000 * (mean RRint at +0.5..+1.5 s - mean RRint at
%       -1..0 s) in milliseconds; RSA predicts RR falls after inhale onset,
%       so deltaRRms < 0 means the polarity is physiologically consistent;
%     - consistent = deltaRRms < 0 (NaN counts as not consistent - no
%       decision could be made); a warning is issued when it is not.
%
%   Output
%     result : struct
%       deltaRRms   : the RSA amplitude above (ms; NaN if no usable breaths)
%       nBreaths    : number of good, still epochs used
%       consistent  : logical (see above)
%   Also saves <outDat.figs>\inhaleLockedRR.jpg (grand mean +/- SEM).

    fs = outDat.fs;
    assert(isfield(outDat, 'behDat') && istable(outDat.behDat), 'checkRspPolarityRSA: outDat.behDat required');
    beh = outDat.behDat;
    need = {'finalOnset', 'goodBreath', 'still'};
    assert(all(ismember(need, beh.Properties.VariableNames)), ...
        'checkRspPolarityRSA: behDat must have columns %s', strjoin(need, ', '));

    isRR = cellfun(@(x) contains(x, 'RRint'), outDat.labels);
    assert(any(isRR), 'checkRspPolarityRSA: no RRint channel in outDat.data (run the ECG stage first)');
    RR = outDat.data(find(isRR, 1), :);

    sel = beh.goodBreath == 1 & beh.still == 1;
    onsets = round(beh.finalOnset(sel));
    onsets = onsets(isfinite(onsets) & onsets > 0);

    pre = round(2 * fs); post = round(4 * fs);
    offs = (-pre:post); t = offs / fs;

    result = struct('deltaRRms', NaN, 'nBreaths', numel(onsets), 'consistent', false);

    if isempty(onsets)
        warning('checkRspPolarityRSA:noBreaths', ...
            '%s: no good inhale onsets in still blocks - RSA polarity check skipped', outDat.sessID);
        return;
    end

    idxMat = onsets + offs;                       % nBreaths x nSamp
    T = numel(RR);
    valid = idxMat >= 1 & idxMat <= T;
    idxClamped = idxMat; idxClamped(~valid) = 1;
    epochs = RR(idxClamped);
    epochs(~valid) = NaN;

    mu = mean(epochs, 1, 'omitnan');
    post05_15 = mean(mu(t >= 0.5 & t <= 1.5), 'omitnan');
    pre10_0   = mean(mu(t >= -1 & t <= 0), 'omitnan');
    result.deltaRRms = 1000 * (post05_15 - pre10_0);
    result.consistent = isfinite(result.deltaRRms) && result.deltaRRms < 0;

    if ~result.consistent
        warning('checkRspPolarityRSA:inconsistent', ...
            ['%s: RR did not fall after inhale onset (deltaRRms = %.1f ms, n = %d breaths) - ' ...
             'rspFlip may be reversed; review inhaleLockedRR.jpg'], outDat.sessID, result.deltaRRms, result.nBreaths);
    end

    sem = std(epochs, 0, 1, 'omitnan') ./ sqrt(max(sum(isfinite(epochs), 1), 1));
    verdict = 'REVIEW'; if result.consistent, verdict = 'consistent'; end
    fig = figure('Visible', 'off', 'Position', [40 40 900 500]); hold on
    fill([t, fliplr(t)], [mu + sem, fliplr(mu - sem)], [0.7 0.7 0.9], 'EdgeColor', 'none', 'FaceAlpha', 0.5);
    plot(t, mu, 'k', 'LineWidth', 2);
    xline(0, '--');
    xlabel('Time from inhale onset (s)'); ylabel('RRint (s)');
    title(sprintf('%s inhale-locked RR (n=%d good, still breaths): deltaRRms = %.1f ms (%s)', ...
        outDat.sessID, result.nBreaths, result.deltaRRms, verdict), 'Interpreter', 'none');
    box on; grid on;
    if ~exist(outDat.figs, 'dir'), mkdir(outDat.figs); end
    saveas(fig, fullfile(outDat.figs, 'inhaleLockedRR.jpg'));
    close(fig);
end

function outDat = preprocess_macros(outDat, P)
%PREPROCESS_MACROS  SHARED: bipolar re-reference of the macro channels (+ spike clean).
%
%   outDat = preprocess_macros(outDat, P)
%
%   Finds the channels whose label contains 'macro' (any number >= 2), drops
%   P.macroRemove, bipolar re-references adjacent pairs and appends them as
%   macBP1..macBP<nMacro-1>, followed by spikeCleanVec. With P.spikeClean the
%   pairs are spike-cleaned by targeted ICA (spikeCleanVec = the ICA mixing
%   trace); too few spikes to train the ICA, or spikeClean off, keeps the
%   bipolar data as is with spikeCleanVec = all ones. QC figures go to
%   outDat.figs (macrosRaw, macrosRaw_zoom, macroSpikeRemoval).
%   (Cleanup C14: formerly hard-wired to 6 macros and a 50000:55000 zoom
%   window; output is unchanged for 6-macro recordings.)

    idx = cellfun(@(x) contains(x, 'macro'), outDat.labels);
    macroDat = outDat.data(idx, :);
    nMac = size(macroDat, 1);
    assert(nMac >= 2, 'preprocess_macros: %s has %d macro channel(s) - need >= 2 for bipolar pairs', ...
        outDat.sessID, nMac);
    nSamp = size(macroDat, 2);

    figure('visible', false, 'position', [0,0,1000,500])
    plot(macroDat(1,:))
    hold on
    for ii = 2:nMac
        plot(macroDat(ii,:)+(ii-1)*50)
    end
    legend()
    if ~isempty(P.macroRemove)
        plot(macroDat(P.macroRemove(1), :) + (P.macroRemove(1)-1)*50, ...
            'color', 'red')
    end
    title([outDat.sessID ' macros raw'], 'Interpreter','none')
    saveas(gcf,fullfile(outDat.figs, 'macrosRaw.jpg'));

    % 10-s zoom (5000 samples at 500 Hz): samples 50000:55000, clamped to the
    % end of short recordings
    z1 = min(55000, nSamp);
    z0 = max(1, z1 - 5000);
    figure('visible', false, 'position', [0,0,1000,500])
    plot(macroDat(1,z0:z1))
    hold on
    for ii = 2:nMac
        plot(macroDat(ii,z0:z1)+(ii-1)*50)
    end
    legend()
    if ~isempty(P.macroRemove)
        plot(macroDat(P.macroRemove(1), z0:z1) + ...
            (P.macroRemove(1)-1)*50, ...
            'color', 'red')
    end
    title([outDat.sessID ' macros raw 10s'], 'Interpreter','none')
    saveas(gcf,fullfile(outDat.figs, 'macrosRaw_zoom.jpg'));

    if ~isempty(P.macroRemove)
        macroDat(P.macroRemove,:) = [];
    end
    macOut = zeros([size(macroDat,1)-1, size(macroDat, [2,3])]);
    %do bipolar rereferencing
    for chani = 1:size(macroDat,1)-1
        macOut(chani, :, :) = squeeze(macroDat(chani, :) -...
                                      macroDat(chani+1,:));
    end

if P.spikeClean
    macOut = double(macOut);

    splitFreq = 10;          % Hz cutoff between "low" and "high" components
    hpOrder   = 4;           % 4th-order Butterworth for high-pass

    % Design high-pass for the spike-y part (> splitFreq)
    [b_hp, a_hp] = butter(hpOrder, splitFreq/(outDat.fs/2), 'high');

    % High-frequency component of the IC
    x_high = filtfilt(b_hp, a_hp, macOut.').';   % column
    % Low-frequency residual (everything not captured by high-pass)
    x_low  = macOut - x_high;

    z_high = (x_high - mean(x_high,2)) ./ std(x_high, [], 2);

    [test, prominence] = detect_spikes(z_high, 2,...
        P.spikeWin);
        %ICA is on the macro data after bipolar rereferencing because ICs
        %are more stable this way.
    out = ica_flag_spikes_targeted(x_high, test, prominence, ...
        'Fs', outDat.fs);
    if isempty(out)
        % Too few macro spikes to train the targeted ICA -> keep the bipolar
        % data as-is (no spike removal), matching the spikeClean=off path.
        % spikeCleanVec = all ones flags that nothing was removed.
        outDat = appendBipolar(outDat, macOut, ones(size(outDat.data,2),1));
        return;
    end
    %add low frequency component back into the clean data:
    out.data_clean = out.data_clean + x_low;
    whereSpikes = movmean(out.mixVector, 10*outDat.fs);
    [~, idx] = min(whereSpikes(20000:end-20000));
    idx = idx + 10000;
    idx = min(size(macOut,2)-outDat.fs*5-1, idx);
    x = figure('visible', false, 'position', [0,0,1000,500]);
    plot(macOut(1,idx-outDat.fs*5:idx+outDat.fs*5))
    hold on
    plot(out.data_clean(1,idx-outDat.fs*5:idx+outDat.fs*5))
    for ii = 2:size(macOut,1)
        plot(macOut(ii,idx-outDat.fs*5:idx+outDat.fs*5) + ii*30)
        hold on
        plot(out.data_clean(ii,idx-outDat.fs*5:idx+outDat.fs*5)+ ii*30)
    end

    title([outDat.sessID ' spike removal'], 'interpreter', 'none')
    saveas(x, fullfile(outDat.figs, 'macroSpikeRemoval.jpg'));

    outDat = appendBipolar(outDat, out.data_clean, out.mixVector);
else
    outDat = appendBipolar(outDat, macOut, ones(size(outDat.data,2),1));
end
end

function outDat = appendBipolar(outDat, bp, cleanVec)
% append the bipolar pairs as macBP1..macBP<C>, then spikeCleanVec (all
% ones when nothing was removed); spikeRemoval reads 1 in every branch
% (CLAUDE.md section 7 - inspect spikeCleanVec to see what happened)
    C = size(bp, 1);
    outDat.data(end+1:end+C, :) = bp;
    outDat.labels(end+1:end+C) = compose('macBP%d', 1:C);
    outDat.data(end+1, :) = cleanVec;
    outDat.labels{end+1} = "spikeCleanVec";
    outDat.spikeRemoval = 1;
end

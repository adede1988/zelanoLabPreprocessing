function [out, badChan, blinkIndicator, selInfo] = blinkRemoveWrapper(outDat, ...
                                                            chanIDX, fs, interpChan, opts)
% opts (optional struct, from preprocess_eeg / P.blinkSelect):
%   .selectMode  'frontal' (default since 2026-10-12) | 'legacy' (the pre-
%                2026-10-12 pick: IC most correlated with raw Fp1, z > 2)
%   .minFrontRatio (2) / .minRefCorr (0.6)   frontal-selection thresholds
%                (calibrated 2026-10-12 on 16 sections of 9 sessions: blink
%                ICs |r| 0.83-0.99, frontal non-blink ICs <= 0.51)
% selInfo = ica_blinks' selection record (+ labels), stored by preprocess_eeg
% as outDat.blinkICA.
%   .badTS       (from preprocess_eeg) samples in trials removeNoiseChansVolt
%                rejected; the ICA training window avoids them
%   .chanTestBadTS  true = the two bad-channel tests below (high range, flat)
%                ignore the .badTS epochs / samples: purged trials and
%                recording gaps are not evidence against one channel (the
%                'fixed' / 'band' detector's rule). preprocess_eeg sets it
%                with those detector modes (2026-10-15, tasks_261014 task 10);
%                absent / false = every epoch counts (as before).
%   .minGood     when the bad-channel tests leave fewer than minGood good
%                channels, nothing is run: out = the input rows 1:32, no
%                blinkIndicator, selInfo = struct('skipped', true, 'reason',
%                ..., 'nGoodLeft', n). preprocess_eeg passes 11 with the
%                'fixed' / 'band' detector (blink ICA and the Laplacian need
%                > 10 good channels); absent = no such check (as before).
    if nargin < 5 || isempty(opts), opts = struct(); end
    if ~isfield(opts, 'selectMode'), opts.selectMode = 'frontal'; end
    if ~isfield(opts, 'minFrontRatio'), opts.minFrontRatio = 2; end
    if ~isfield(opts, 'minRefCorr'), opts.minRefCorr = 0.6; end

    data = outDat.data(chanIDX, :); 
    origIs2D = ismatrix(data);
    if origIs2D
        data    = reshape(data,    size(data,1), size(data,2), 1);
        
    end
    [C,T,N] = size(data);
    data = reshape(data, C, []);
            
    %hard coded index of blink channel! 
    blinkChan = 1;      
    
    % data: [nChannels x nSamples], units = microvolts
    % outDat.fs: sampling rate (Hz)
    
    fs = outDat.fs;
    
    %% ---------- Criterion 1: high-voltage deviations in 2 s epochs ----------
    
    epochDurSec  = 2;                   % 2-second epochs
    epochSamples = round(epochDurSec * fs);
    nEpochs      = floor(T / epochSamples);
    
    % Trim to full epochs
    dataTrim   = data(:, 1:nEpochs*epochSamples);
    dataEpochs = reshape(dataTrim, C, epochSamples, nEpochs);  % [ch x samples x epochs]
    
    highRangeThresh = 700;   % µV: max - min >= 700 counts as a "bad" epoch
    epochFracThresh = 0.15;  % 15% of epochs
    
    % Range per channel per epoch
    epochMax   = squeeze(max(dataEpochs, [], 2));   % [nCh x nEpochs]
    epochMin   = squeeze(min(dataEpochs, [], 2));   % [nCh x nEpochs]
    epochRange = epochMax - epochMin;               % [nCh x nEpochs]
    
    % Epoch is "bad" if range >= 700 µV
    epochBad = epochRange >= highRangeThresh;       % logical [nCh x nEpochs]

    % opts.chanTestBadTS: epochs / samples in the detector's badTS are left
    % out of both channel tests (the 2-s epochs here coincide with the
    % detector's 2-s trials: both start at sample 1)
    tsMask = false(1, size(data, 2));
    if isfield(opts, 'chanTestBadTS') && ~isempty(opts.chanTestBadTS) && opts.chanTestBadTS && ...
            isfield(opts, 'badTS') && numel(opts.badTS) == size(data, 2)
        tsMask = reshape(opts.badTS ~= 0, 1, []);
    end
    keepEp = ~any(reshape(tsMask(1:nEpochs*epochSamples), epochSamples, nEpochs), 1);

    % Channel is bad if >= 15% of its (counted) epochs are bad
    if all(keepEp)
        badHighDev = (sum(epochBad, 2) ./ nEpochs) >= epochFracThresh;   % [nCh x 1]
    else
        badHighDev = (sum(epochBad(:, keepEp), 2) ./ max(1, nnz(keepEp))) >= epochFracThresh;
    end
    
    
    %% ---------- Criterion 2: flat periods (> 100 ms within ±1 µV) ----------
    
    flatAmpThresh      = 1;                % µV: between -1 and +1
    flatLenSec         = 0.100;            % 100 ms
    flatLenSamples     = round(flatLenSec * fs);
    flatTotalSecThresh = 30;               % 30 seconds total
    flatTotalSamples   = round(flatTotalSecThresh * fs);
    
    badFlat = false(C,1);
    % Samples where EVERY channel is flat are a recording gap (zero-filled
    % acquisition pause), not a dead channel: they must not count toward any
    % one channel's flat time (2026-10-12, 260805_EEG_NWU_CA: a ~208-s
    % all-channel gap flagged all 28 channels, both blink channels included,
    % so blink removal was skipped). Sessions without such a gap are
    % unaffected.
    allFlat = all(abs(data) <= flatAmpThresh, 1);

    for ch = 1:C
        x = data(ch,:);                         % 1 x nSamp
        isFlat = abs(x) <= flatAmpThresh & ~allFlat & ~tsMask;   % logical
    
        if ~any(isFlat)
            continue;                           % no flat segments at all
        end
    
        % Find contiguous flat segments via run-length encoding
        d = diff([0 isFlat 0]);                % edges
        starts = find(d == 1);                 % start indices of flat segments
        ends   = find(d == -1) - 1;            % end indices
    
        segLen = ends - starts + 1;            % length of each flat segment in samples
    
        % Only count segments that are at least 100 ms long
        longSegIdx = segLen >= flatLenSamples;
        totalFlatSamples = sum(segLen(longSegIdx));
    
        % Mark channel as bad if total flat time >= 30 s
        badFlat(ch) = totalFlatSamples >= flatTotalSamples;
    end
    
    
    %% ---------- Combine criteria ----------
    
    badChan = find(badHighDev | badFlat);% channels failing either criterion
    badChannelsHighDev = find(badHighDev);
    badChannelsFlat    = find(badFlat);

    % opts.minGood: too few good channels left for blink ICA / the Laplacian
    if isfield(opts, 'minGood') && ~isempty(opts.minGood) && C - numel(badChan) < opts.minGood
        out = outDat.data(1:32, :);
        blinkIndicator = [];
        selInfo = struct('skipped', true, 'nGoodLeft', C - numel(badChan), 'reason', ...
            sprintf(['blink-stage channel tests left %d of %d channels good (< %d): blink ICA ' ...
                     'not run'], C - numel(badChan), C, opts.minGood));
        if isfield(opts, 'chanTestBadTS')
            selInfo.chanTestBadTS = any(tsMask);
            selInfo.chanTestEpochsIgnored = nnz(~keepEp);
        end
        return
    end

    if ismember(blinkChan, badChan)
        if ismember(C, badChan)
            error('no available blink chan!')
        else
            blinkChan = C; 
        end
    end


    % Optional: display
    % fprintf('Bad channels (any criterion): %s\n', mat2str(badChan));
    % fprintf('Bad channels (high deviation): %s\n', mat2str(badChannelsHighDev));
    % fprintf('Bad channels (flat): %s\n', mat2str(badChannelsFlat));


    % figure; 
    % imagesc(data) %check for bad channels overall 
    % caxis([-200, 200])
    % 
    % badChan = input(sprintf(...
    % 'Enter the index of badChans (1..%d), or [] to skip: '...
    %                                         ,size(data,1)));
    % 
    % figure; 
    % imagesc(data) %check for bad channels overall 
    % caxis([-1, 1])
    % 
    % badChan = [badChan input(sprintf(...
    % 'Enter the index of badChans (1..%d), or [] to skip: '...
    %                                         ,size(data,1)))];
   
    chanIDX(badChan) = []; 
    trainDat = data; 
    trainDat(badChan, :) = []; 
    data(badChan, :) = []; 
    if blinkChan == C
        blinkChan = size(data, 1); 
    end
    
    
    eyeBlinkDat = data(blinkChan,:) - mean(trainDat,1); 
    [b,a] = butter(4, [3,10]/(fs/2), 'bandpass');
    eyeBlinkDat = filtfilt(b,a, eyeBlinkDat); 
    eyeBlinkDat = (eyeBlinkDat - mean(eyeBlinkDat,2)) ./ ...
                        std(eyeBlinkDat,[],2);
        
    % %check that eyeblink dat looks as expected
    % figure; 
    % plot(eyeBlinkDat')

    test = eyeBlinkDat>2;
    blinkIndicator = reshape(test, 1, T, N); 


    %% ---------- Select an ICA training window ----------
    % Prefer a window with a moderate blink rate (enough blinks to define the
    % component, but not so many the data are dominated by artifact) and the
    % fewest interpolated samples. Falls back gracefully for short recordings
    % or when no window lands in the target blink-density band.
    winLen = 100000; 
    if length(test) <= winLen + 1
        % recording too short for windowed selection: train on all of it
        selStart = 1; 
        selEnd   = size(trainDat, 2); 

    else
        cand         = 1:500:(length(test) - winLen);
        % keep the training window off trials removeNoiseChansVolt rejected
        % outright (badTS): the blink-band indicator below also fires on
        % large artifacts, so an artifact-rich stretch could be chosen and
        % the ICA would spend components on it (2026-10-12, 260625_OBE_NWU_HM_2
        % sleep: window over two ~1500 uV all-channel transients). Windows
        % with the fewest badTS samples stay candidates; no badTS = unchanged.
        if ~strcmpi(opts.selectMode, 'legacy') && isfield(opts, 'badTS') && ...
                numel(opts.badTS) == numel(test) && any(opts.badTS)
            cb = cumsum([0; double(opts.badTS(:) ~= 0)]);
            badCounts = cb(cand + winLen + 1) - cb(cand);
            cand = cand(badCounts == min(badCounts));
        end
        blinkCounts  = arrayfun(@(x) sum(test(x:x+winLen)), cand);
        interpCounts = arrayfun(@(x) mean(interpChan(x:x+winLen)), cand); 
        sel = find(blinkCounts > prctile(blinkCounts, 75) & ...
                   blinkCounts < prctile(blinkCounts, 90)); 
        if isempty(sel)
            % nothing in the target band: fall back to the busiest window
            [~, sel] = max(blinkCounts); 
        end
        interpSel = interpCounts(sel); 
        sel = sel(min(interpSel) == interpSel);   % among those, fewest interpolated
        if numel(sel) > 1
            sel = sel(round(numel(sel)/2));        % middle of the ties
        end
        selStart = cand(sel);                      % FIX: sample index, not list position
        selEnd   = selStart + winLen; 
    end

    %% ---------- Learn the blink topography on the >2 Hz band ----------
    % ICA is trained on a 2 Hz high-passed copy so slow drift does not smear
    % or split the blink component. The resulting spatial filter is applied
    % to the broadband data below (blink topography is frequency-stable, so a
    % filter learned >2 Hz is valid across the full band). Fs is deliberately
    % NOT passed to ica_blinks, so it applies no additional high-pass/notch.
    [bHP, aHP] = butter(4, 2/(fs/2), 'high'); 
    trainDatHP = filtfilt(bHP, aHP, trainDat.').'; 
    trainDatHP = trainDatHP(:, selStart:selEnd); 
    interpTrain = interpChan(selStart:selEnd); 
    k = size(trainDatHP,1) -  min(interpTrain); 
    


    % frontal-polar reference for the IC selection: mean of the good Fp1/Fp2
    % minus the common average of the good channels (removes the common-mode
    % / reference-site signal that dominates the raw Fp1 trace)
    goodLbl = string(outDat.labels(chanIDX));
    frontIdx = find(ismember(goodLbl, ["Fp1" "Fp2"]));
    blinkRef = mean(trainDatHP(frontIdx, :), 1) - mean(trainDatHP, 1);
    out = ica_blinks(trainDatHP, 'blinkChan', blinkChan, 'targIC', k, ...
        'selectMode', opts.selectMode, 'blinkRef', blinkRef, ...
        'frontIdx', frontIdx, 'selFs', fs, ...
        'minFrontRatio', opts.minFrontRatio, 'minRefCorr', opts.minRefCorr);
    selInfo = out.select;
    if isfield(opts, 'chanTestBadTS')
        % record (and proof for preprocess_eeg that this version honoured
        % the option): were badTS epochs left out of the channel tests
        selInfo.chanTestBadTS = any(tsMask);
        selInfo.chanTestEpochsIgnored = nnz(~keepEp);
    end
    selInfo.labels = cellstr(goodLbl);
    selInfo.trainStartSample = selStart;
    selInfo.removedLabel = '';
    if ~isempty(out.badICs)
        [~, pkR] = max(abs(out.A(:, out.badICs(1)) - mean(out.A(:, out.badICs(1)))));
        selInfo.removedLabel = char(goodLbl(pkR));
    end
    fprintf('%s blink IC (%s): %s | legacy pick IC%d (r=%.2f z=%.1f) | removed: %s\n', ...
        outDat.sessID, selInfo.mode, selInfo.reason, selInfo.legacyIC, ...
        selInfo.legacyCorr, selInfo.legacyZ, mat2str(out.badICs));
    try
        plotBlinkSelection(out, trainDatHP, blinkRef, frontIdx, goodLbl, ...
            outDat.eegLocs.X_flat(chanIDX), outDat.eegLocs.Y_flat(chanIDX), fs, outDat);
    catch MEp
        warning('%s: blink QC figure failed: %s', outDat.sessID, MEp.message);
    end

    if isfield(out, 'ambiguous') && out.ambiguous
        % Batch run could not auto-select a blink IC. Save a candidate-vs-blink
        % plot for manual review, then abort THIS session (the caller's
        % try/catch logs it as skipped). To reprocess after inspecting, set
        % ZLP_BLINK_IC to the chosen IC index and re-run just that session.
        try
            fA = figure('visible','off','Color','w'); nC = size(out.candSact,1);
            for ic = 1:nC
                subplot(nC,1,ic);
                zic = (out.candSact(ic,:)-mean(out.candSact(ic,:)))/max(std(out.candSact(ic,:)),eps);
                plot(zic); hold on; plot(out.blinkSig);
                ylabel(sprintf('IC %d', out.candIdx(ic)));
                if ic==1, title(sprintf('%s: choose blink IC, set ZLP\\_BLINK\\_IC', outDat.sessID)); end
            end
            if ~exist(outDat.figs,'dir'), mkdir(outDat.figs); end
            saveas(fA, fullfile(outDat.figs, ['blinkAmbiguous_' outDat.sessID '.jpg']));
            close(fA);
        catch, end
        error('ZLP:blinkAmbiguous', 'blink IC ambiguous for %s (candidate ICs %s)', ...
              outDat.sessID, mat2str(out.candIdx));
    end

    if ~isempty(out.badICs)
        ax = figure; 
        miniTopo(out.A(:,out.badICs(1)), outDat.eegLocs.X_flat(chanIDX), outDat.eegLocs.Y_flat(chanIDX)); 
      
        saveas(ax,fullfile(outDat.figs, 'removedBlink.jpg'));
        close(ax);
    elseif exist(fullfile(outDat.figs, 'removedBlink.jpg'), 'file')
        % nothing removed: a removedBlink.jpg left by an earlier run would
        % claim otherwise (blinkICA.jpg documents the decision)
        try, delete(fullfile(outDat.figs, 'removedBlink.jpg')); catch, end
    end

    %% ---------- Apply the spatial filter to the BROADBAND data ----------
    % Mean-centre first so that zeroing the blink IC does not subtract a
    % blink-shaped fraction of the channel means; add the means back after.
    dataMean = mean(data, 2); 
    Sclean   = out.W * (data - dataMean); 
    Sclean(out.badICs,:) = 0;                 % removal of blink IC entirely
    data_clean = out.A * Sclean + dataMean;   % back to channel space, means restored

    newEphys = outDat.data(1:32,:); 
    newEphys(chanIDX,:) = data_clean; 
    if ~origIs2D
        out = reshape(newEphys, C, T, N);
    else
        out = newEphys; 
    end
end


function plotBlinkSelection(out, trHP, blinkRef, frontIdx, goodLbl, xf, yf, fs, outDat)
% QC figure blinkICA.jpg (always saved): average-referenced maps (sign set so
% the frontal-polar weight is positive) of the removed IC, the legacy pick
% and the best frontal candidate, with 30 s of their activations against the
% frontal-polar reference (blinkRef) from the ICA training window.
    sel = out.select;
    Sact = out.W * (trHP - mean(trHP, 2));
    aRef = out.A - mean(out.A, 1);
    sgn = @(v) v * sign(sum(v(frontIdx)) + eps);
    show = {};
    if ~isempty(out.badICs), show(end+1, :) = {out.badICs(1), 'REMOVED'}; end
    show(end+1, :) = {sel.legacyIC, 'legacy pick'};
    if isfield(sel, 'refCorrAll') && isempty(out.badICs)
        cand = find(sel.eligAll);
        if ~isempty(cand)
            [~, j] = max(sel.refCorrAll(cand)); show(end+1, :) = {cand(j), 'best frontal (kept)'};
        end
    end
    f = figure('Visible', 'off', 'Color', 'w', 'Position', [0 0 1400 800]);
    nS = size(show, 1);
    for s = 1:nS
        subplot(2, 3, s);
        miniTopo(sgn(aRef(:, show{s, 1})), xf, yf);
        [~, pk] = max(abs(aRef(:, show{s, 1})));
        r = NaN; if isfield(sel, 'refCorrAll'), r = sel.refCorrAll(show{s, 1}); end
        title(sprintf('%s: IC%d (peak %s, r_{ref}=%.2f)', show{s, 2}, show{s, 1}, goodLbl(pk), r));
    end
    w = 1:min(size(trHP, 2), 30*fs); t = w/fs;
    zs = @(x) (x - mean(x)) / max(std(x), eps);
    subplot(2, 1, 2); hold on
    plot(t, zs(blinkRef(w)), 'k');
    for s = 1:nS
        plot(t, zs(sign(sum(aRef(frontIdx, show{s, 1})) + eps) * Sact(show{s, 1}, w)) - 6*s);
    end
    yticks(-6*(nS:-1:0)); yticklabels([flip(show(:, 2)'), {'Fp - avg'}]);
    xlabel('s (ICA training window)'); xlim(t([1 end]));
    sgtitle(sprintf('%s blink IC selection (%s): %s', outDat.sessID, sel.mode, sel.reason), ...
        'Interpreter', 'none');
    if ~exist(outDat.figs, 'dir'), mkdir(outDat.figs); end
    saveas(f, fullfile(outDat.figs, 'blinkICA.jpg'));
    close(f);
end

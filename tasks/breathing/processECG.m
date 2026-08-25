function outDat = processECG(outDat, P)

    % ECG channels -> band-passed, z-scored, with the min beat separation.
    % (Shared with paramCheckECG so the verification figure matches detection.)
    [ECGz, beatSep] = buildECGz(outDat);



    heartBeats = P.getBeats(ECGz, beatSep);



    % QC-figure window: nominally samples 100000:110000, clamped so short
    % recordings (e.g. brief condition sections in Task 9) don't crash the
    % figure indexing. Figure-only - beat detection above is unaffected.
    N  = size(ECGz, 2);
    w0 = min(100000, max(1, N - 10000));
    w1 = min(w0 + 10000, N);
    figure('visible', false, 'position', [0,0,1000,500]);
    hold on
    cols = {'k', 'red', 'green'};
    for ci = 1:min(3, size(ECGz, 1))
        plot(ECGz(ci, w0:w1), 'color', cols{ci})
    end
    xlim([0 w1 - w0])
    xlabel('samples (window)')
    inWin = heartBeats(heartBeats > w0 & heartBeats < w1) - w0;
    if ~isempty(inWin)
        xline(inWin, 'color', 'magenta', 'linestyle', '--')
    end
    maxVal = max(ECGz(:, w0:w1), [], 'all');
    minVal = min(ECGz(:, w0:w1), [], 'all');
    ylim([minVal*1.5 maxVal * 1.5])
    title(sprintf('ECG beat detection (%s)', ...
                  outDat.sessID), ...
          'Interpreter','none');
    saveas(gcf,fullfile(outDat.figs, ['ECG_beatDetect' '.jpg']));


    outDat.heartBeats = heartBeats; 


    %% with beats detected, establish RR interval timeseries
    
    idx = cellfun(@(x) contains(x, 'rsp'), outDat.labels);
    rspDat = outDat.data(idx, :); 
    
    %choose which one looks right
    % rspDatz = (rspDat - mean(rspDat, [2,3])) ./ std(rspDat, [], [2,3]); 
    
    idx = P.rspIDX; 
    rspDat = squeeze(rspDat(idx, :));  
    
    %flip signal
    rspDat = rspDat .* P.rspFlip;

    %convert beats indecies to beat times
    tim = 1/outDat.fs:1/outDat.fs:size(outDat.data,2)/outDat.fs; 
    beatTims = tim(outDat.heartBeats); 
    beatDiffs = diff(beatTims);
    beatTims(end) = [];
       
   
    %account for accidental misses and double counts and interpolate
    %across
    breakVals = [.2:.05:10]; 
    counts = arrayfun(@(x,y) sum(beatDiffs>x & beatDiffs<y), ...
    breakVals(1:end-1), breakVals(2:end));
    %locate the mode and find zeros around it to define central dist.
    [~, idx] = max(counts); 
    minVal = breakVals(idx - find(flip(counts(1:idx))<5, 1) + 1); 
    if isempty(minVal)
        minVal = .6; %interbeat interval of less than .6 is unrealistic for generally healthy people sitting still
    end
    maxVal = breakVals(idx + find(counts(idx:end)<5, 1) - 1); 

    %remove bad vals: 
    beatTims(beatDiffs < minVal) = []; 
    beatDiffs(beatDiffs < minVal) = []; 

    beatTims(beatDiffs > maxVal) = []; 
    beatDiffs(beatDiffs > maxVal) = []; 
    figure('visible', false, 'position', [0,0,1000,500]);
    histogram(beatDiffs)
    xlabel('interbeat interval (s)')  
    title(sprintf('Interbeat heart interval (%s)', ...
                  outDat.sessID), ...
          'Interpreter','none');
    saveas(gcf,fullfile(outDat.figs, ['interbeatHist' '.jpg']));

    %interpolate the interbeat interval into a full timeseries
    RRint = interp1(beatTims,beatDiffs, tim, 'linear');
    
    
    % clamped QC window (figure-only; see note above)
    v0 = min(100000, max(1, numel(rspDat) - 50000));
    v1 = min(v0 + 50000, numel(rspDat));
    figure('visible', false, 'position', [0,0,1000,500]);
    plot(rspDat(v0:v1))
    ylabel('Respiration velocity')
    yyaxis right
    plot(RRint(v0:v1))
    ylabel('Interbeat Interval (s)')
    xlim([0 v1 - v0])
    title(sprintf('Respiration and HRV (%s)', ...
                  outDat.sessID), ...
          'Interpreter','none');
    saveas(gcf,fullfile(outDat.figs, ['RespirationHeart' '.jpg']));

    outDat.data(end+1, :) = RRint; 
    outDat.labels{end+1} = 'RRint'; 




end
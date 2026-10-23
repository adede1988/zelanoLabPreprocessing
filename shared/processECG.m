function outDat = processECG(outDat, P)

    % ECG channels -> band-passed, z-scored, with the min beat separation.
    % (Shared with paramCheckECG so the verification figure matches detection.)
    [ECGz, beatSep] = buildECGz(outDat);



    heartBeats = P.getBeats(ECGz, beatSep);

    % Optional per-session refractory pruning (P.minIBI, seconds; set in
    % config/applyParams.m under an explicit per-session case, absent = off =
    % behaviour unchanged): drop every detected beat that follows the last
    % KEPT beat by less than P.minIBI, so over-detected beats (noise
    % crossings, double detections) never enter the RR series.
    minIBI = [];
    if isstruct(P) && isfield(P, 'minIBI') && ~isempty(P.minIBI), minIBI = P.minIBI; end
    if ~isempty(minIBI) && ~isempty(heartBeats)
        keep = heartBeats(1);
        for bi = 2:numel(heartBeats)
            if heartBeats(bi) - keep(end) >= minIBI * outDat.fs, keep(end+1) = heartBeats(bi); end %#ok<AGROW>
        end
        heartBeats = keep;
    end

    % Optional per-session ECG exclusion windows (P.ecgExcludeSec, [N x 2]
    % [start end] seconds on this outDat's own timeline; set in
    % config/applyParams.m under an explicit per-session case, absent / empty =
    % off = behaviour unchanged; tasks_261014 task 7). They mark stretches where
    % the ECG is unreadable (criterion + measurement tool: batch/
    % ecgUnreadableWindows). Beats inside a window are dropped from
    % outDat.heartBeats, every RR interval that touches a window is dropped,
    % and RRint is NaN from the last kept RR stamp before a window to the first
    % one after it (never interpolated across excluded data); flagBadBreaths
    % then blanks the within-breath HRV of the breaths that overlap that NaN
    % stretch. The IBI-range estimate below keeps using ALL detected beats
    % (hbAll), so RRint outside the NaN stretches is exactly what it would be
    % without the windows. Recorded in outDat.ecgExclude.
    hbAll = heartBeats;
    exWin = [];
    inEx  = false(size(heartBeats));
    if isstruct(P) && isfield(P, 'ecgExcludeSec') && ~isempty(P.ecgExcludeSec)
        exWin = P.ecgExcludeSec;
        assert(isnumeric(exWin) && size(exWin, 2) == 2 && all(exWin(:) >= 0) && ...
               all(exWin(:, 2) > exWin(:, 1)), ...
               'processECG: P.ecgExcludeSec must be an N x 2 matrix of [start end] seconds with end > start');
        for wi = 1:size(exWin, 1)
            inEx = inEx | (heartBeats / outDat.fs >= exWin(wi, 1) & heartBeats / outDat.fs <= exWin(wi, 2));
        end
        heartBeats(inEx) = [];
    end



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
    beatTims = tim(hbAll);   % = tim(outDat.heartBeats) unless P.ecgExcludeSec dropped beats
    beatDiffs = diff(beatTims);
    beatTims(end) = [];

    % Optional per-session premature-beat correction (P.ecgEctopic, struct of
    % options, struct() = defaults; set in config/applyParams.m under an
    % explicit per-session case, absent / empty = off = behaviour unchanged;
    % 2026-10-21, 261018_EEG_NWU_VL). Interval j (beat j -> j+1) is
    % premature when it is shorter than (1 - premFrac) x the local median
    % interval (moving median over winBeats intervals): beat j+1 came early.
    % Both intervals touching a premature beat are not normal-to-normal, so
    % they are dropped from the RR series and RRint is interpolated across
    % them (the linear interp1 below); outDat.heartBeats keeps every detected
    % beat. For the record, a premature beat whose two intervals add up to >=
    % ectSumMin x the local median (a compensatory or reset pause) counts as
    % an ectopic beat, one whose two intervals add up to < extraSumMax x it
    % (one normal interval split in two) as an extra detection; the rest are
    % ambiguous (e.g. runs). outDat.ecgEctopic records them.
    if isstruct(P) && isfield(P, 'ecgEctopic') && isstruct(P.ecgEctopic)
        eo = P.ecgEctopic;
        def = struct('premFrac', 0.2, 'winBeats', 11, 'ectSumMin', 1.5, 'extraSumMax', 1.25);
        fnE = fieldnames(def);
        for fi = 1:numel(fnE)
            if ~isfield(eo, fnE{fi}), eo.(fnE{fi}) = def.(fnE{fi}); end
        end
        refIv = movmedian(beatDiffs, eo.winBeats);
        prem = [beatDiffs(1:end-1) < (1 - eo.premFrac) * refIv(1:end-1), false];
        pairSum = [(beatDiffs(1:end-1) + beatDiffs(2:end)) ./ refIv(1:end-1), NaN];
        isEct = prem & pairSum >= eo.ectSumMin;
        isExtra = prem & pairSum < eo.extraSumMax;
        dropIv = prem | [false, prem(1:end-1)];
        bIdx = find(prem) + 1;                                  % premature beats, index into hbAll
        [~, inHB] = ismember(hbAll(bIdx), heartBeats);          % 0 = inside an ECG exclusion window
        recHours = (beatTims(end) + beatDiffs(end) - beatTims(1)) / 3600;
        col = @(v) reshape(v, [], 1);
        outDat.ecgEctopic = struct( ...
            'beat', col(inHB), 'sample', col(hbAll(bIdx)), 'timeSec', col(beatTims(bIdx)), ...
            'class', {repmat({'ambiguous'}, numel(bIdx), 1)}, ...
            'couplingRatio', col(beatDiffs(bIdx - 1) ./ refIv(bIdx - 1)), 'pairSumRatio', col(pairSum(bIdx - 1)), ...
            'nPremature', numel(bIdx), 'nEctopic', nnz(isEct), 'nExtraDetection', nnz(isExtra), ...
            'ectopicPerHour', nnz(isEct) / recHours, 'burdenPct', 100 * nnz(isEct) / numel(hbAll), ...
            'nIntervalsDropped', nnz(dropIv), 'opts', eo, ...
            'note', ['premature beats (interval < (1-premFrac) x local median): both intervals touching each ' ...
                     'are dropped from RRint, which is interpolated across them; heartBeats keeps every beat']);
        outDat.ecgEctopic.class(isEct(bIdx - 1)) = {'ectopic'};
        outDat.ecgEctopic.class(isExtra(bIdx - 1)) = {'extraDetection'};
        beatTims(dropIv) = [];
        beatDiffs(dropIv) = [];
    end

   
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
    if ~isempty(minIBI), minVal = max(minVal, minIBI); end   % explicit per-session floor (P.minIBI)
    maxVal = breakVals(idx + find(counts(idx:end)<5, 1) - 1);

    %remove bad vals: 
    beatTims(beatDiffs < minVal) = []; 
    beatDiffs(beatDiffs < minVal) = []; 

    beatTims(beatDiffs > maxVal) = []; 
    beatDiffs(beatDiffs > maxVal) = []; 

    % P.ecgExcludeSec: drop every interval with a beat inside a window or
    % spanning one (no-op without windows)
    if ~isempty(exWin)
        dropIv = false(size(beatTims));
        for wi = 1:size(exWin, 1)
            dropIv = dropIv | (beatTims + beatDiffs >= exWin(wi, 1) & beatTims <= exWin(wi, 2));
        end
        beatTims(dropIv) = [];
        beatDiffs(dropIv) = [];
    end
    figure('visible', false, 'position', [0,0,1000,500]);
    histogram(beatDiffs)
    xlabel('interbeat interval (s)')  
    title(sprintf('Interbeat heart interval (%s)', ...
                  outDat.sessID), ...
          'Interpreter','none');
    saveas(gcf,fullfile(outDat.figs, ['interbeatHist' '.jpg']));

    %interpolate the interbeat interval into a full timeseries
    RRint = interp1(beatTims,beatDiffs, tim, 'linear');
    if ~isempty(exWin)
        % P.ecgExcludeSec: no RR estimate inside the windows, and none that
        % would be interpolated across them: NaN between the last kept stamp
        % before each window and the first kept stamp after it
        exNaN = zeros(size(exWin, 1), 2);
        for wi = 1:size(exWin, 1)
            tL = max(beatTims(beatTims < exWin(wi, 1)));
            tR = min(beatTims(beatTims > exWin(wi, 2)));
            if isempty(tL), tL = 0; end
            if isempty(tR), tR = tim(end); end
            exNaN(wi, :) = [tL tR];
            RRint(tim > tL & tim < tR) = NaN;
        end
        ex = struct('windowsSec', exWin, 'rrNaNSec', exNaN, 'nBeatsDropped', nnz(inEx), ...
                    'note', '', 'nBreathsAffected', NaN, 'breathIdx', []);   % last two: flagBadBreaths
        if isfield(P, 'ecgExcludeNote'), ex.note = P.ecgExcludeNote; end
        outDat.ecgExclude = ex;
    end


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
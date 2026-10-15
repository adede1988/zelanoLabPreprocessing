function [outTTLs, raw] = detect_ttls_O15(raw, P)

    idx = cellfun(@(x) contains(x, 'event'), raw.labels);
    photoDiode = raw.data(idx, :); 
    

 % Find missing samples in the photodiode channel
        nanidx = isnan(photoDiode);
        nNan   = sum(nanidx);
        
        if nNan > 4000
            error('too many missing values!');
        end
        
        % Get raw data for this trial (rows = channels, cols = time)
        rawData = raw.data;
        
        if nNan > 0
            % --- 1) Interpolate photodiode (1-D vector) ---
            % Fill internal NaNs by linear interpolation
            photoDiode = fillmissing(photoDiode, 'linear');
            % Any leading/trailing NaNs get replaced by nearest neighbor
            photoDiode = fillmissing(photoDiode, 'nearest');
        
            % --- 2) Interpolate rawData along time (dimension 2) ---
            % Linear interpolation across time for each channel
            rawData = fillmissing(rawData, 'linear', 2);
            % Nearest neighbor for any remaining edge NaNs
            rawData = fillmissing(rawData, 'nearest', 2);
        end

        raw.data = rawData;

    % Held-button protocol (opt-in per session: P.ttl.protocol = 'heldButton'
    % in applyParams' O15 switch; tasks_261014 task 10). Default (absent or
    % 'pressPulse') = the legacy z-score path below, unchanged.
    if isfield(P, 'ttl') && isfield(P.ttl, 'protocol') && strcmp(P.ttl.protocol, 'heldButton')
        [outTTLs, raw] = heldButtonTTLs(raw, P, photoDiode);
        return
    end



    photoDiode = (photoDiode - mean(photoDiode)) / std(photoDiode);
    

    downs = find(photoDiode(1:end-1) > P.pd.zthresh & ...
                photoDiode(2:end)    < P.pd.zthresh);
    ups = find(photoDiode(1:end-1) < P.pd.zthresh & ...
               photoDiode(2:end)   > P.pd.zthresh);
    difVals = ups - downs; %difVals is length of TTL pulses
    downs(difVals>P.pd.maxPulseSamp) = []; 
    ups(difVals>P.pd.maxPulseSamp) = []; 
    difVals(difVals>P.pd.maxPulseSamp) = []; 

    starti = 1; 
    for di = 5:length(downs)
        if downs(di) - downs(di-4) < 3500
            starti = di; 
            if strcmp(raw.sessID, '250929_Dupi_NMH_GH_2') || ...
                strcmp(raw.sessID, '260105_OBE_NWU_ZF_1') || ... 
                strcmp(raw.sessID, '251120_Dupi_NMH_JL_2')
                break
            end
        end
    end
    downs(1:starti) = []; 
    difVals(1:starti) = []; 
    downs(difVals<P.pd.minPulseSamp) = []; 
    difVals(difVals<P.pd.minPulseSamp) = []; 

    trialMarks = downs(difVals < P.pd.trialSplitSamp);
    sniffMarks = downs(difVals > P.pd.trialSplitSamp); 

    trialMarks(diff(trialMarks)<raw.fs_raw) = []; 

    if ~isempty(P.ttl.removeTrialMarksIdx)
        trialMarks(P.ttl.removeTrialMarksIdx) = []; %aberant extra TTL  
    end
    
    
 

    if length(trialMarks) ~= P.ttl.expectedTrialCount
        error('wrong trial count!')
        
    end

    confirmMarks = [];
    for tt = 1:length(trialMarks)
        if tt < length(trialMarks)
            idx = find(sniffMarks>trialMarks(tt) & ...
                sniffMarks<trialMarks(tt+1));
        else
            idx = find(sniffMarks>trialMarks(tt));
        end
        if length(idx) == 2
            if sniffMarks(idx(2))- sniffMarks(idx(1)) < raw.fs_raw
                confirmMarks = [confirmMarks sniffMarks(idx(1))];
                sniffMarks(idx) = []; 
            end
        end
    end

    % (The 2026-10-12 DB_3-only 'confirmAfterPress' rule that stood here is
    % retired: it read DB_3's trials one event out of phase. DB_3 runs the
    % held-button protocol instead - see heldButtonTTLs below.)
    % confirmMarks = sniffMarks(diff(sniffMarks)<raw.fs_raw);
    % idx = find(diff(sniffMarks)<raw.fs_raw);
    % sniffMarks([idx, idx+1]) = []; 




    figure  %('visible', false, 'position', [0,0,1000,500])
    plot(photoDiode)
    xline(trialMarks)
    xline(confirmMarks, 'color', 'red')
    xline(sniffMarks, 'color', 'green')
    title([raw.sessID ' TTLs'])



    trialStarts = trialMarks(1:2:30); 
    xline(trialStarts, 'color', 'magenta')
    buttonPresses = trialMarks(2:2:30); 
    saveas(gcf,fullfile(raw.paths.fig, 'TTLs.jpg'));


    
    %store all TTLs into one matrix: 
    %col 1: trialStarts
    %col 2: buttonPress 
    %col 3: confirmatory sniff (trial end)
    %col 4: free sniff 1
    %col 5: free sniff 2 
    %      ....
    %col 20: free sniff 17
    TTLs = nan(15, 20); 
    TTLs(:,1) = trialStarts; 
    TTLs(:,2) = buttonPresses; 
    TTLs(:,3) = confirmMarks;  
    for triali = 1:15
        idx = sniffMarks;
        idx = idx(idx>trialStarts(triali) & ...
                            idx < buttonPresses(triali));
        for sniffi = 1:length(idx)
            TTLs(triali,3+sniffi) = idx(sniffi);
        end
    end
    TTLs =round(TTLs ./ (raw.fs_raw / P.fs_target));

    outTTLs = table; 
    outTTLs.trialStart = TTLs(:,1); 
    outTTLs.buttonPress = TTLs(:,2); 
    outTTLs.confirmSniff = TTLs(:,3); 
    outTTLs.free1 = TTLs(:,4); 
    outTTLs.free2 = TTLs(:,5); 
    outTTLs.free3 = TTLs(:,6); 
    outTTLs.free4 = TTLs(:,7); 
    outTTLs.free5 = TTLs(:,8); 
    outTTLs.free6 = TTLs(:,9); 
    outTTLs.free7 = TTLs(:,10); 
    outTTLs.free8 = TTLs(:,11); 
    outTTLs.free9 = TTLs(:,12); 
    outTTLs.free10= TTLs(:,13); 
    outTTLs.free11= TTLs(:,14); 
    outTTLs.free12= TTLs(:,15); 
    outTTLs.free13= TTLs(:,16); 
    outTTLs.free14= TTLs(:,17); 
    outTTLs.free15= TTLs(:,18); 
    outTTLs.free16= TTLs(:,19); 
    outTTLs.free17= TTLs(:,20);


end


function [outTTLs, raw] = heldButtonTTLs(raw, P, photoDiode)
%HELDBUTTONTTLS  O15 TTL table for the held-button protocol (tasks_261014 task 10).
%   The experimenter holds the button down while the odor bottle is under the
%   participant's nose (from ~Oct 2025; 251030_Dupi_NMH_DB_3) instead of tapping
%   once per observed sniff. Those holds occupy ~25 % of the samples on the
%   (rail-clipped, AC-coupled) event channel, so the legacy z-score threshold
%   finds no pulses and the hold widths exceed maxPulseSamp. parse_O15_events
%   parses the channel on median/rail-referenced levels instead, using the
%   fixed widths of the programmatic pulses (start / cue / press pair /
%   confirm pair).
%
%   TTL table: same columns as the legacy path (trialStart, buttonPress,
%   confirmSniff, free1..free17; samples at P.fs_target). free1 = the start
%   cue (as in the legacy path, where it is the first sniff mark of the trial
%   and detect_sniffs_from_TTLs labels its sniff 'start'); free2..free17 stay
%   NaN - the free events are button-DOWN PERIODS, returned in raw.buttonDown
%   (-> outDat.buttonDown), and heldButtonFreeSniffs_O15 turns the inhales
%   inside them into the 'free' sniffs.

    if ~isempty(P.ttl.removeTrialMarksIdx)
        error('detect_ttls_O15:heldButton', ...
            'removeTrialMarksIdx is not supported with the held-button protocol');
    end
    opts = struct;
    if isfield(P.ttl, 'heldOpts'), opts = P.ttl.heldOpts; end
    opts.expectedTrials = P.ttl.expectedTrialCount / 2;   % 2 trial marks per trial (start, press)
    [ev, pulses, info] = parse_O15_events(photoDiode, raw.fs_raw, opts);

    k = raw.fs_raw / P.fs_target;
    nT = numel(ev.trialStart);
    TTLs = nan(nT, 20);
    TTLs(:,1) = ev.trialStart;
    TTLs(:,2) = ev.press;
    TTLs(:,3) = ev.confirm;
    TTLs(:,4) = ev.cue;
    TTLs = round(TTLs ./ k);
    names = [{'trialStart', 'buttonPress', 'confirmSniff'}, ...
             arrayfun(@(x) sprintf('free%d', x), 1:17, 'UniformOutput', false)];
    outTTLs = array2table(TTLs, 'VariableNames', names);

    % button-down periods (one row per hold; samples at P.fs_target and raw)
    nW = cellfun(@(x) size(x, 1), ev.free);
    bd = zeros(0, 2); trialIdx = zeros(0, 1); winIdx = zeros(0, 1);
    for t = 1:nT
        bd = [bd; ev.free{t}];                         %#ok<AGROW>
        trialIdx = [trialIdx; repmat(t, nW(t), 1)];    %#ok<AGROW>
        winIdx = [winIdx; (1:nW(t))'];                 %#ok<AGROW>
    end
    BD = table;
    BD.trial     = trialIdx;
    BD.window    = winIdx;
    BD.onset     = round(bd(:,1) ./ k);
    BD.offset    = round(bd(:,2) ./ k);
    BD.durSec    = (bd(:,2) - bd(:,1)) ./ raw.fs_raw;
    BD.onsetRaw  = bd(:,1);
    BD.offsetRaw = bd(:,2);
    raw.buttonDown = BD;
    info.protocol = 'heldButton';
    info.fs_raw = raw.fs_raw;
    info.pulses = pulses;          % every pulse with its role (raw samples)
    raw.ttlInfo = info;

    % QC figure (TTLs.jpg, same file as the legacy path)
    hF = figure('visible', 'off', 'position', [0, 0, 1800, 500]);
    hold on
    dec = 10;
    tt = (0:dec:numel(photoDiode)-1) ./ raw.fs_raw;
    yl = [min(photoDiode) max(photoDiode)];
    for i = 1:height(BD)
        patch([BD.onsetRaw(i) BD.offsetRaw(i) BD.offsetRaw(i) BD.onsetRaw(i)] ./ raw.fs_raw, ...
            yl([1 1 2 2]), [1 .7 .3], 'EdgeColor', 'none', 'FaceAlpha', .5)
    end
    plot(tt, photoDiode(1:dec:end), 'color', [.4 .4 .4])
    xlim([0 tt(end)])
    xline(ev.trialStart ./ raw.fs_raw, 'color', 'magenta')
    xline(ev.cue ./ raw.fs_raw, 'color', 'green')
    xline(ev.press ./ raw.fs_raw, 'color', 'black')
    xline(ev.confirm ./ raw.fs_raw, 'color', 'red')
    yline(info.thresh, '--')
    xlabel('time (s)')
    title({sprintf('%s TTLs (held-button): %d trials, %d button-down periods (%.0f s held)', ...
        raw.sessID, nT, height(BD), sum(BD.durSec)), ...
        'magenta start, green cue, black press, red confirm, orange = button held'}, 'interpreter', 'none')
    saveas(hF, fullfile(raw.paths.fig, 'TTLs.jpg'));
    close(hF)
end
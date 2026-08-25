function [outDat, P] = paramCheck(outDat, P)
%PARAMCHECK  Verify rsp-channel and macro/spike choices for guess-param sessions.
%   Interactive by default. When P.allowGuessRun is true (Tasks_260824.md D4
%   run-on-guess batch override) it instead SAVES the same QC figures to the
%   session figure folder (P.figDir, falling back to outDat.figs) and returns
%   without prompting, leaving every parameter unchanged.

    if isfield(P, 'allowGuessRun') && P.allowGuessRun
        figDir = guessFigDir(outDat, P);
        idx = cellfun(@(x) contains(x, 'rsp'), outDat.labels);
        rspDat = outDat.data(idx, :);
        fig = figure('Visible', 'off', 'Position', [40 40 1400 500]);
        plot(rspDat', 'color', 'k'); hold on
        plot(rspDat(P.rspIDX, :) .* P.rspFlip, 'color', 'red')
        xlim([10000 min(100000, size(rspDat, 2))])
        title(sprintf('%s paramCheck rsp: rspIDX=%d rspFlip=%d (red = chosen)', ...
            outDat.sessID, P.rspIDX, P.rspFlip), 'Interpreter', 'none');
        saveas(fig, fullfile(figDir, [outDat.sessID '_paramCheck_rsp.png']));
        close(fig);

        idx = cellfun(@(x) contains(x, 'macro'), outDat.labels);
        if sum(idx) > 0
            macDat = outDat.data(idx, :);
            fig = figure('Visible', 'off', 'Position', [40 40 1400 700]);
            hold on
            for ii = 1:size(macDat, 1)
                plot(macDat(ii, :) + ii * 100)
            end
            xlim([10000 min(30000, size(macDat, 2))])
            title(sprintf('%s paramCheck macros: macroRemove=%s spikeClean=%d', ...
                outDat.sessID, mat2str(P.macroRemove), P.spikeClean), 'Interpreter', 'none');
            saveas(fig, fullfile(figDir, [outDat.sessID '_paramCheck_macros.png']));
            close(fig);
        end
        return;
    end

    set(0, 'defaultfigurewindowstyle', 'docked')

% is the respiration index correct?
    idx = cellfun(@(x) contains(x, 'rsp'), outDat.labels);
    rspDat = outDat.data(idx, :);

    
    figure; 
    plot(rspDat', 'color', 'k')
    hold on 
    plot(rspDat(P.rspIDX,:).*P.rspFlip, 'color', 'red')
    xlim([10000 100000])

    userData = input('Press 1 to accept; 0 to reject: ');
    ii = 1; 
    while userData == 0
        figure; 
        plot(rspDat(ii,:), 'color', 'k')
        xlim([10000 100000])
        userData = input('Press 1 to accept; 0 to reject: ');
        if userData == 1
            P.rspIDX = ii; 
            userData = input('should it be flipped? 0 = no; 1=yes');
            if userData == 0
                P.rspFlip = 1; 
            else 
                P.rspFlip = -1; 
            end
            userData = 1; 
        end
        ii = ii+1;
        if ii == 4
            ii = 1; 
        end
    end


% should we do spike cleaning or reject any macros? 
    figure;
    idx = cellfun(@(x) contains(x, 'macro'), outDat.labels);
    if sum(idx)>0
        macDat = outDat.data(idx,:); 
        
        hold on 
        for ii = 1:size(macDat,1)
            plot(macDat(ii,:)+ii*100)
        end
        legend()
        xlim([10000 30000])
        userData = input('remove any macros? enter as [# #] to indicate channels or [] to indicate none');
        
        P.macroRemove = userData;
        
        userData = input('spike removal, should be avoided if macro channels are being removed? 0=no; 1=yes');

        P.spikeClean = userData; 
    end









    set(0, 'defaultfigurewindowstyle', 'normal')















end

function figDir = guessFigDir(outDat, P)
% figure folder for run-on-guess QC output: P.figDir, else outDat.figs,
% else a reprocBackup fallback so the figures are never silently lost
    if isfield(P, 'figDir') && ~isempty(P.figDir)
        figDir = P.figDir;
    elseif isfield(outDat, 'figs') && ~isempty(outDat.figs)
        figDir = outDat.figs;
    else
        figDir = fullfile('E:\reprocBackup_260824', 'guessQC', outDat.sessID);
    end
    if ~isfolder(figDir), mkdir(figDir); end
end

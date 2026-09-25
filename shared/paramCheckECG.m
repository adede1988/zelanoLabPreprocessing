function P = paramCheckECG(outDat, P)
%PARAMCHECKECG  Interactive verification of the ECG beat-detection spec.
%
%   P = paramCheckECG(outDat, P)
%
%   Breathing-task counterpart to paramCheck: when a session's parameters are a
%   guess, this shows a short ECG segment with the beats the current
%   P.beatSpec detects and lets the user accept it or type a new spec and
%   re-check. Returns P with a possibly-updated .beatSpec / .getBeats.
%
%   This is breathing-only (the only task with ECG). It is a no-op for any P
%   that has no .beatSpec field.
%
%   The detector and the figure use the SAME band-passed/z-scored ECG as
%   processECG (via buildECGz), so what you accept here is what runs.

    if ~isfield(P, 'beatSpec')      % non-breathing safety
        return;
    end

    if isfield(P, 'allowGuessRun') && P.allowGuessRun
        % Tasks_260824.md D4 run-on-guess: save the QC figure + a beat-rate
        % summary instead of prompting; the spec is left as guessed.
        [ECGz, beatSep] = buildECGz(outDat);
        beats = detectBeats(ECGz, beatSep, P.beatSpec);
        durMin = size(ECGz, 2) / outDat.fs / 60;
        bpm = numel(beats) / durMin;
        fprintf('paramCheckECG (run-on-guess) %s: beatSpec=%s -> %d beats, %.1f bpm over %.1f min\n', ...
            outDat.sessID, P.beatSpec, numel(beats), bpm, durMin);
        if bpm < 30 || bpm > 160
            warning('paramCheckECG:oddRate', '%s: %.1f bpm is outside 30-160 - inspect the QC figure', ...
                outDat.sessID, bpm);
        end
        N  = size(ECGz, 2);
        w0 = min(100000, max(1, N - 10000));
        w1 = min(w0 + 10000, N);
        cols = {'k', 'r', 'g', 'b', 'm'};
        inWin = beats(beats >= w0 & beats <= w1) - w0 + 1;
        fig = figure('Visible', 'off', 'Position', [40 40 1400 500]); hold on
        for c = 1:size(ECGz, 1)
            plot(ECGz(c, w0:w1), 'color', cols{min(c, numel(cols))});
        end
        if ~isempty(inWin)
            xline(inWin, 'color', 'magenta', 'linestyle', '--');
        end
        title(sprintf('%s paramCheckECG (guess): beatSpec=%s, %.1f bpm overall', ...
            outDat.sessID, P.beatSpec, bpm), 'Interpreter', 'none');
        figDir = guessFigDirECG(outDat, P);
        saveas(fig, fullfile(figDir, [outDat.sessID '_paramCheck_ECG.png']));
        close(fig);
        return;
    end

    set(0, 'defaultfigurewindowstyle', 'docked');
    [ECGz, beatSep] = buildECGz(outDat);

    % a ~20 s window away from the recording edges
    N  = size(ECGz, 2);
    w0 = min(100000, max(1, N - 10000));
    w1 = min(w0 + 10000, N);
    cols = {'k', 'r', 'g', 'b', 'm'};

    accepted = false;
    while ~accepted
        beats = detectBeats(ECGz, beatSep, P.beatSpec);
        inWin = beats(beats >= w0 & beats <= w1) - w0 + 1;

        figure; hold on;
        for c = 1:size(ECGz, 1)
            plot(ECGz(c, w0:w1), 'color', cols{min(c, numel(cols))});
        end
        if ~isempty(inWin)
            xline(inWin, 'color', 'magenta', 'linestyle', '--');
        end
        title(sprintf('%s   beatSpec = %s   (%d beats in window)', ...
              outDat.sessID, P.beatSpec, numel(inWin)), 'Interpreter', 'none');
        xlabel('sample (within window)'); ylabel('ECG (z)');

        resp = input('Accept ECG beat detection? 1 = yes, 0 = enter a new beatSpec: ');
        if isequal(resp, 1)
            accepted = true;
        else
            ns = input('New beatSpec (e.g. ''1,0,gt,3 & 2,0,gt,4''): ', 's');
            if ~isempty(strtrim(ns))
                P.beatSpec = strtrim(ns);
                P.getBeats = @(ECGz, beatSep) detectBeats(ECGz, beatSep, P.beatSpec);
            end
        end
    end

    set(0, 'defaultfigurewindowstyle', 'normal');
end

function figDir = guessFigDirECG(outDat, P)
% figure folder for run-on-guess QC output (mirrors paramCheck>guessFigDir)
    if isfield(P, 'figDir') && ~isempty(P.figDir)
        figDir = P.figDir;
    elseif isfield(outDat, 'figs') && ~isempty(outDat.figs)
        figDir = outDat.figs;
    else
        figDir = fullfile('E:\reprocBackup_260824', 'guessQC', outDat.sessID);
    end
    if ~isfolder(figDir), mkdir(figDir); end
end

function TTL = detect_ttls_emotionalMovieTask(outDat, P, figDir)
%DETECT_TTLS_EMOTIONALMOVIETASK  Photodiode -> clip table for the movie task.
%
%   TTL = detect_ttls_emotionalMovieTask(outDat, P, figDir)
%
%   Port of ZelanoLabScripts/detect_ttls_EmotionalMovie.m (the old pipeline)
%   onto the raw-fs outDat built by emotionalMovieTask_makeOutDat. Clip onsets
%   are marked by 1 / 2 / 3 photodiode pulses = neutral / happy(positive) /
%   sad(negative) (P.pd.numNeu/numPos/numNeg). Detection: 60/120/180 Hz
%   notches, z-score, falling-edge crossings of P.pd.zthresh, <100-sample
%   dedupe, then pulse-group classification within P.pd.searchWin samples.
%
%   Returns a table with one row per clip:
%     clipOnset  : onset sample (fs_target = P.fs_target space)
%     clipEnd    : next clip's onset - P.pd.clipEndGapSec (old scripts' rule);
%                  NaN for the final clip (the old pipeline never defined its
%                  end - such breaths are dropped downstream per D10)
%     nPulses    : 1 / 2 / 3
%     valence    : "neutral" / "happy" / "sad"
%   A QC figure of the z-scored photodiode with classified onsets is saved to
%   figDir.

    idx = cellfun(@(x) contains(x, 'event'), outDat.labels);
    photoDiode = outDat.data(idx, :);
    fsRaw = outDat.fs;

    for f0 = [60 120 180]
        wo = f0 / (fsRaw / 2);
        bw = wo / 35;
        [b, a] = iirnotch(wo, bw);
        photoDiode = filtfilt(b, a, double(photoDiode));
    end
    photoDiode = (photoDiode - mean(photoDiode)) / std(photoDiode);

    TTLs = find(photoDiode(1:end-1) > P.pd.zthresh & ...
                photoDiode(2:end)   < P.pd.zthresh);
    diffVals = diff(TTLs);
    TTLs(diffVals < 100) = [];

    % group pulses into clips: process-then-check (the legacy loop's
    % semantics) so trailing clips are classified; groups whose lookahead
    % runs off the end are typed by however many pulses remain
    onset = zeros(500, 1);
    typ   = zeros(500, 1);
    ii = 1; ti = 1;
    nT = numel(TTLs);
    while ii <= nT
        curTTL = TTLs(ii);
        onset(ti) = curTTL;
        if ii + 2 <= nT && TTLs(ii + 2) - curTTL < P.pd.searchWin
            typ(ti) = P.pd.numNeg;      % 3 pulses = sad
            ii = ii + P.pd.numNeg;
        elseif ii + 1 <= nT && TTLs(ii + 1) - curTTL < P.pd.searchWin
            typ(ti) = P.pd.numPos;      % 2 pulses = happy
            ii = ii + P.pd.numPos;
        else
            typ(ti) = P.pd.numNeu;      % 1 pulse = neutral
            ii = ii + P.pd.numNeu;
        end
        ti = ti + 1;
    end
    keep = onset > 0;
    onset = onset(keep); typ = typ(keep);

    valNames = strings(size(typ));
    valNames(typ == P.pd.numNeu) = "neutral";
    valNames(typ == P.pd.numPos) = "happy";
    valNames(typ == P.pd.numNeg) = "sad";

    TTL = table();
    TTL.clipOnset = onset;
    TTL.clipEnd   = [onset(2:end) - P.pd.clipEndGapSec * fsRaw; NaN];
    TTL.nPulses   = typ;
    TTL.valence   = valNames;

    % QC figure
    fig = figure('Visible', 'off', 'Position', [0, 0, 1400, 500]);
    dec = 1:10:numel(photoDiode);
    plot(dec / fsRaw / 60, photoDiode(dec), 'k'); hold on
    cols = {'green', 'blue', 'red'};
    for np = 1:3
        xs = TTL.clipOnset(TTL.nPulses == np) / fsRaw / 60;
        if ~isempty(xs), xline(xs, 'color', cols{np}); end
    end
    title(sprintf('%s clip onsets (green=neutral blue=happy red=sad; %d clips)', ...
        outDat.sessID, height(TTL)), 'Interpreter', 'none');
    xlabel('minutes');
    if ~isfolder(figDir), mkdir(figDir); end
    saveas(fig, fullfile(figDir, [outDat.sessID '_movieClipTTLs.png']));
    close(fig);

    % convert to fs_target sample space (the makeOutDat convention)
    TTL.clipOnset = round(TTL.clipOnset ./ (fsRaw / P.fs_target));
    TTL.clipEnd   = round(TTL.clipEnd   ./ (fsRaw / P.fs_target));
end

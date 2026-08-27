function [peaks, troughs] = findAlternatingExtrema(resp, fs)
%FINDALTERNATINGEXTREMA  Strictly alternating breath peaks/troughs.
%
%   [peaks, troughs] = findAlternatingExtrema(resp, fs)
%
%   Backbone for the 2026-08 onset detectors (QC round 3). resp is the
%   windowed-normalized detection trace (unit-ish scale). Peaks and troughs
%   are found with a minimum prominence and a 1.5-s minimum separation (the
%   physiological refractory: nobody breathes faster), then forced to
%   alternate trough -> peak -> trough (of two same-type extrema in a row the
%   more extreme wins). One inhale onset per trough->peak pair is then
%   guaranteed by construction downstream.

    MINSEP  = round(1.5 * fs);
    PROM    = 0.35;                 % on the normalized trace (~unit variance)

    [~, peaks]   = findpeaks(resp,  'MinPeakProminence', PROM, 'MinPeakDistance', MINSEP);
    [~, troughs] = findpeaks(-resp, 'MinPeakProminence', PROM, 'MinPeakDistance', MINSEP);

    % merge into one alternating sequence
    ev = [peaks(:), ones(numel(peaks), 1); troughs(:), -ones(numel(troughs), 1)];
    ev = sortrows(ev, 1);
    keep = true(size(ev, 1), 1);
    i = 1;
    while i < size(ev, 1)
        j = i + 1;
        while j <= size(ev, 1) && ~keep(j), j = j + 1; end
        if j > size(ev, 1), break; end
        if ev(i, 2) == ev(j, 2)
            % two of the same type in a row: keep the more extreme
            if ev(i, 2) == 1     % two peaks
                if resp(ev(i, 1)) >= resp(ev(j, 1)), keep(j) = false; else, keep(i) = false; i = j; end
            else                 % two troughs
                if resp(ev(i, 1)) <= resp(ev(j, 1)), keep(j) = false; else, keep(i) = false; i = j; end
            end
        else
            i = j;
        end
    end
    ev = ev(keep, :);
    peaks   = ev(ev(:, 2) == 1, 1)';
    troughs = ev(ev(:, 2) == -1, 1)';
end

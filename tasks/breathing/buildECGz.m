function [ECGz, beatSep] = buildECGz(outDat)
%BUILDECGZ  Band-pass + z-score the ECG channels and return the beat-separation.
%
%   [ECGz, beatSep] = buildECGz(outDat)
%
%   Shared by processECG (beat detection -> HRV) and paramCheckECG (interactive
%   verification of the beat-detection spec) so both operate on identical ECGz
%   and beatSep. Breathing task only -- it is the only task with ECG channels.
%
%   ECGz    : channels whose label contains 'ECG', band-passed 5-40 Hz and
%             z-scored per channel (rows = channels, cols = time).
%   beatSep : minimum separation (samples) enforced between detected beats.

    idx = cellfun(@(x) contains(x, 'ECG'), outDat.labels);
    ECG = outDat.data(idx, :);

    d = designfilt('bandpassiir', 'FilterOrder', 4, ...
        'HalfPowerFrequency1', 5, 'HalfPowerFrequency2', 40, ...
        'SampleRate', outDat.fs);
    ECG = filtfilt(d, ECG')';

    % 260805_EEG_NWU_CA: intermittent high-amplitude noise bursts (~5% of
    % 10-s windows at 10-100x signal amplitude) swamp the global z-score and
    % compress real R-peaks below any usable threshold (they sit at ~62 bpm
    % on ch3- once the bursts are removed - see batch/task8_probeCA2 /
    % task89_probeBlankSim). Blank the noisy windows (per-channel robust
    % window-std > 3x median) before z-scoring. Explicit per-session special
    % case per repo convention.
    if isfield(outDat, 'sessID') && strcmp(outDat.sessID, '260805_EEG_NWU_CA')
        wLen = 10 * outDat.fs;
        nW = floor(size(ECG, 2) / wLen);
        for ch = 1:size(ECG, 1)
            x = ECG(ch, :);
            zr = (x - median(x)) / (1.4826 * mad(x, 1));
            wstd = zeros(1, nW);
            for w = 1:nW, wstd(w) = std(zr((w-1)*wLen+1 : w*wLen)); end
            for w = find(wstd > 3 * median(wstd))
                ECG(ch, (w-1)*wLen+1 : w*wLen) = 0;
            end
        end
    end

    ECGz = (ECG - mean(ECG, 2)) ./ std(ECG, [], 2);

    beatSep = outDat.fs / 20;
end

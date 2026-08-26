% task12_probeParams — measured parameters for the not-yet-run Dupi/OBE
% breathingTask guess sessions (2026-08-26 instruction). Requires the
% intermediates (run breathingTask_makeOutDat first; sessions whose makeOutDat
% failed - e.g. missing behavioral CSV - are reported and skipped).
%
% Per session, from the intermediate:
%   ECG    : beat rate per channel x polarity at 3.5/2.5/2.0 sigma ->
%            beatSpec '<ch>,0,<gt|lt>,<thr>' for the cleanest plausible
%            (40-110 bpm) combination; none plausible -> keep default + REVIEW.
%   macros : channels railing (>=2% of samples pinned at an extreme, or a
%            pinned run >= 5 s) -> macroRemove.
%   spikes : mean rate of |z|>10 events on kept macros; > 2/min on any
%            channel -> spikeClean = true.
%   hasEEG : true for all (instruction).
% Everything written with writeParams, paramSource stays 'guess'.

IDS = {'250623_Dupi_NMH_KS_3', '251110_Dupi_NMH_PC_2', '251120_Dupi_NMH_JL_2', ...
       '250811_Dupi_NMH_TB_3', '250929_Dupi_NMH_GH_3', '251002_Dupi_NMH_AB_3', ...
       '260326_OBE_NWU_AD_1', '251013_Dupi_NMH_JN_3', '260406_Dupi_NMH_BS_1', ...
       '260326_OBE_NWU_AD_2', '260316_Dupi_NMH_PD_1', '260504_Dupi_NMH_JA_1', ...
       '260514_OBE_NWU_BW_1', '260504_Dupi_NMH_JA_2'};

cfg = applyParams('breathingTask', 'main');
for k = 1:numel(IDS)
    id = IDS{k};
    si = find(strcmp(cfg.sessionIDs, id), 1);
    if isempty(si), fprintf('%s: NOT IN SESSION LIST\n', id); continue; end
    ip = fullfile(cfg.root{si}, id, 'preProc', [id '_breathingPreProc.mat']);
    if ~exist(ip, 'file')
        fprintf('%s: NO INTERMEDIATE (makeOutDat failed? check its log - missing behavior CSV?)\n', id);
        continue;
    end
    s = load(ip); fn = fieldnames(s); od = s.(fn{1}); clear s
    fsr = od.fs;               % intermediates are pre-downsample (raw rate)

    % ---------- ECG ----------
    isECG = cellfun(@(x) contains(x, 'ECG'), od.labels);
    best = struct('bpm', NaN, 'ch', NaN, 'sgn', '', 'thr', NaN, 'margin', 0);
    if any(isECG)
        ecg = od.data(isECG, :);
        mins = size(ecg, 2) / fsr / 60;
        minSep = round(fsr / 20);
        for ch = 1:size(ecg, 1)
            x = bandpass(fillmissing(double(ecg(ch, :)), 'linear', 'EndValues', 'nearest'), [5 40], fsr);
            x = (x - mean(x)) / std(x);
            for thr = [3.5 2.5 2.0]
                for sgn = [1 -1]
                    idx = find(sgn * x > thr);
                    if isempty(idx), nb = 0; else, nb = 1 + sum(diff(idx) > minSep); end
                    bpm = nb / mins;
                    idxO = find(-sgn * x > thr);          % opposite side, same thr
                    if isempty(idxO), nbO = 0; else, nbO = 1 + sum(diff(idxO) > minSep); end
                    margin = bpm / max(nbO / mins, 1);
                    if bpm >= 40 && bpm <= 110 && margin > best.margin
                        best = struct('bpm', bpm, 'ch', ch, ...
                            'sgn', ternLocal(sgn > 0, 'gt', 'lt'), ...
                            'thr', sgn * thr, 'margin', margin);
                    end
                end
            end
        end
    end
    if isfinite(best.bpm)
        beatSpec = sprintf('%d,0,%s,%g', best.ch, best.sgn, best.thr);
        ecgTxt = sprintf('%s (%.0f bpm, %.1fx side margin)', beatSpec, best.bpm, best.margin);
    else
        beatSpec = '1,0,gt,3.5';
        ecgTxt = 'NO plausible rate on any channel/polarity/threshold - default kept, REVIEW';
    end

    % ---------- macros: railing + spikiness ----------
    isMac = find(cellfun(@(x) contains(x, 'macro'), od.labels));
    railOut = []; spikey = false; macTxt = 'no macro channels';
    if ~isempty(isMac)
        railTxt = ''; spkMax = 0;
        for m = 1:numel(isMac)
            x = double(od.data(isMac(m), :));
            hi = mean(x == max(x)); lo = mean(x == min(x));
            % longest pinned-at-extreme run (samples)
            pin = (x == max(x)) | (x == min(x));
            d = diff([0 pin 0]); runLen = find(d == -1) - find(d == 1);
            maxRun = 0; if ~isempty(runLen), maxRun = max(runLen); end
            if max(hi, lo) >= 0.02 || maxRun >= 5 * fsr
                railOut(end+1) = m; %#ok<AGROW>
                railTxt = sprintf('%s mac%d(rail %.1f%%/run %.1fs)', railTxt, m, 100 * max(hi, lo), maxRun / fsr);
            else
                z = (x - mean(x)) / std(x);
                idx = find(abs(z) > 10);
                if isempty(idx), nSpk = 0; else, nSpk = 1 + sum(diff(idx) > fsr / 10); end
                spkMax = max(spkMax, nSpk / (numel(x) / fsr / 60));
            end
        end
        spikey = spkMax > 2;
        macTxt = sprintf('%d macros, drop [%s]%s, worst spike rate %.1f/min -> spikeClean=%d', ...
            numel(isMac), num2str(railOut), railTxt, spkMax, spikey);
    end

    % ---------- write ----------
    P = struct('task', 'breathingTask', 'paramSource', 'guess', ...
        'hasEEG', true, 'hasMacros', ~isempty(isMac), ...
        'spikeClean', spikey, 'spikeThresh', 20, 'spikeWin', 11, ...
        'beatSpec', beatSpec, 'isNewStd', true);
    if ~isempty(railOut), P.macroRemove = railOut; else, P.macroRemove = []; end
    writeParams(P, id);
    fprintf('%s:\n   ECG   : %s\n   macros: %s\n', id, ecgTxt, macTxt);
    clear od
end
fprintf('task12_probeParams: DONE\n');

function out = ternLocal(cond, a, b)
    if cond, out = a; else, out = b; end
end

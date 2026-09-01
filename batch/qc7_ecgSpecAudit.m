% qc7_ecgSpecAudit - heartbeat-detection spec audit (2026-08-31 user request).
%
% For each session (env ZLP_ECG_IDS, comma-separated): rebuild ECGz from the
% saved breathing final, evaluate the SHEET beatSpec (bpm, inter-beat
% regularity) and sweep simple single-conjunct candidates (lead x polarity x
% threshold) to find the best-scoring detector. REPORT ONLY - no sheet
% writes; the user reviews QC figures separately.
%
% Verdict: SPEC-OK when the sheet spec yields 40-120 bpm with >=80% of
% inter-beat intervals in the physiological 0.3-2 s band; otherwise
% SPEC-SUSPECT with the best candidate printed.

ids = strtrim(strsplit(getenv('ZLP_ECG_IDS'), ','));
assert(~isempty(ids) && ~isempty(ids{1}), 'set ZLP_ECG_IDS');
cfg = applyParams('breathingTask', 'main');
for ii = 1:numel(ids)
    id = ids{ii};
    try
        si = find(strcmp(cfg.sessionIDs, id), 1);
        hits = dir(fullfile(cfg.root{si}, id, 'preProc', [id '_breathing*.mat']));
        assert(~isempty(hits), 'no breathing file');
        s = load(fullfile(hits(1).folder, hits(1).name));
        fn = fieldnames(s); od = s.(fn{1}); clear s
        P = applyParams('breathingTask', id);
        durMin = size(od.data, 2) / od.fs / 60;
        [ECGz, beatSep] = buildECGz(od);
        fsE = size(ECGz, 2) / (durMin * 60);
        nStored = NaN;
        if isfield(od, 'heartBeats'), nStored = numel(od.heartBeats); end

        evalSpec = @(spec) specStats(ECGz, beatSep, spec, fsE, durMin);
        [bpm0, frac0, cv0] = evalSpec(P.beatSpec);
        best = struct('spec', '', 'bpm', NaN, 'frac', -1, 'cv', NaN);
        for L = 1:size(ECGz, 1)
            for c = {{'gt', '3.5'}, {'gt', '2.5'}, {'lt', '-3.5'}, {'lt', '-2.5'}}
                spec = sprintf('%d,0,%s,%s', L, c{1}{1}, c{1}{2});
                [b, f, v] = evalSpec(spec);
                good = b >= 40 && b <= 120;
                score = f - 0.5 * min(v, 1) + 0.5 * good;
                bestScore = best.frac - 0.5 * min(best.cv, 1) + ...
                    0.5 * (best.bpm >= 40 && best.bpm <= 120);
                if isnan(best.bpm) || score > bestScore
                    best = struct('spec', spec, 'bpm', b, 'frac', f, 'cv', v);
                end
            end
        end
        okSheet = bpm0 >= 40 && bpm0 <= 120 && frac0 >= 0.8;
        vd = 'SPEC-OK'; if ~okSheet, vd = 'SPEC-SUSPECT'; end
        fprintf('ECGAUD %s: sheet[%s] bpm=%.0f inRange=%.0f%% cv=%.2f stored=%d | best[%s] bpm=%.0f inRange=%.0f%% cv=%.2f | %s\n', ...
            id, P.beatSpec, bpm0, 100*frac0, cv0, nStored, best.spec, best.bpm, 100*best.frac, best.cv, vd);
        clear od ECGz
    catch ME
        fprintf('ECGAUD FAIL %s: %s\n', id, ME.message);
    end
end
fprintf('qc7_ecgSpecAudit: DONE\n');

function [bpm, inFrac, cv] = specStats(ECGz, beatSep, spec, fsE, durMin)
    bpm = NaN; inFrac = 0; cv = NaN;
    try
        b = detectBeats(ECGz, beatSep, spec);
        bpm = numel(b) / durMin;
        if numel(b) > 10
            ibi = diff(sort(b(:))) / fsE;
            inR = ibi(ibi > 0.3 & ibi < 2);
            inFrac = numel(inR) / numel(ibi);
            if numel(inR) > 5, cv = std(inR) / mean(inR); end
        end
    catch
    end
end

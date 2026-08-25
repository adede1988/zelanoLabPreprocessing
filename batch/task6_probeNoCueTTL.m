% task6_probeNoCueTTL — Task 6 Part A step 2: does a no-cue (cue==0) trial
% still produce a photodiode cue pulse?
%
% For the recent OBEControl cue sessions with no-cue trials, parse the
% photodiode with the production thresholds (cueTask_makeOutDat newSet branch:
% z-score, crossings at -1.5, pulse duration 300-1500 samples; cue < 850,
% sniff 850-1250, response > 1250) and compare pulse counts against the
% behavioral tables (staged at E:\reprocBackup_260824\cueBeh by Task 6 prep).
%
% Prints, per session: pulse-duration histogram, counts per class, the two
% competing count models (every trial pulses cue+sniff vs cued trials only),
% and which model the data match. Saves an annotated figure per session to
% E:\reprocBackup_260824\task6_probe\. Read-only.

IDS  = {'260702_OBE_NWU_SP_2', '260622_OBE_NWU_RC_1', '260720_OBE_NWU_KA_2'};
BEH  = 'E:\reprocBackup_260824\cueBeh';
OUTD = 'E:\reprocBackup_260824\task6_probe';
if ~isfolder(OUTD), mkdir(OUTD); end

L = labPaths();
for k = 1:numel(IDS)
    id = IDS{k};
    fprintf('\n===== %s =====\n', id);
    rawDir = dir(fullfile(L.rootOBE, id, 'raw'));
    idx = find(cellfun(@(x) contains(lower(x), 'raw_cuetask'), {rawDir.name}) & [rawDir.isdir]);
    if isempty(idx)
        fprintf('  no raw_cueTask* folder\n');
        continue;
    end
    fld = fullfile(rawDir(idx(1)).folder, rawDir(idx(1)).name);
    dd = dir(fullfile(fld, '*.mat'));
    if isempty(dd)
        fprintf('  raw folder %s has no .mat\n', rawDir(idx(1)).name);
        continue;
    end
    S = load(fullfile(dd(1).folder, dd(1).name));
    fn = fieldnames(S);
    cd0 = S.(fn{1});
    clear S
    labs = cd0.outLabs;
    pdi = find(cellfun(@(x) contains(x, 'event'), labs), 1);
    photoDiode = cd0.rawData.trial{1}(pdi, :);
    fsRaw = cd0.rawData.fsample;
    clear cd0
    photoDiode = fillmissing(photoDiode, 'linear');
    photoDiode = (photoDiode - mean(photoDiode)) / std(photoDiode);

    downs = find(photoDiode(1:end-1) > -1.5 & photoDiode(2:end) < -1.5);
    ups   = find(photoDiode(1:end-1) < -1.5 & photoDiode(2:end) > -1.5);
    if numel(ups) < numel(downs), downs(end) = []; end
    if numel(ups) > numel(downs), ups(1) = []; end
    difVals = ups - downs;
    keep = difVals >= 300 & difVals <= 1500;
    fprintf('  raw pulses: %d (kept %d in 300-1500 samples @ fs=%d)\n', numel(difVals), sum(keep), fsRaw);
    downs = downs(keep); difVals = difVals(keep);

    edges = [300 500 700 850 1000 1250 1500];
    fprintf('  duration histogram (edges %s): %s\n', mat2str(edges), mat2str(histcounts(difVals, edges)));
    nCue   = sum(difVals < 850);
    nSniff = sum(difVals >= 850 & difVals <= 1250);
    nResp  = sum(difVals > 1250);
    fprintf('  classes: cue-len %d | sniff-len %d | resp-len %d\n', nCue, nSniff, nResp);

    % start-marker bursts (5 pulses within 3500 samples)
    starti = [];
    for di = 5:numel(downs)
        if downs(di) - downs(di-4) < 3500, starti(end+1) = di; end %#ok<SAGROW>
    end
    fprintf('  start-burst hits: %d\n', numel(starti));

    % behavioral tables
    bd = dir(fullfile(BEH, id, '*_run*_cuelist_odor_results.mat'));
    nTrials = 0; nNoCue = 0; nMissed = 0;
    for b = 1:numel(bd)
        B = load(fullfile(bd(b).folder, bd(b).name));
        T = outMat_to_table(B.outMat, B.datalabel);
        nTrials = nTrials + height(T);
        nNoCue  = nNoCue + sum(T.cue == 0);
        nMissed = nMissed + sum(arrayfun(@(x) isequal(x, 999), T.response));
    end
    fprintf('  behavior: %d trials, %d no-cue, %d missed responses\n', nTrials, nNoCue, nMissed);
    fprintf('  model A (every trial pulses cue+sniff): expect %d task pulses\n', 3 * nTrials - nMissed);
    fprintf('  model B (no cue pulse on no-cue trials): expect %d task pulses\n', 3 * nTrials - nMissed - nNoCue);
    fprintf('  observed task-length pulses (excl start bursts, trailing): %d\n', numel(downs));

    fig = figure('Visible', 'off', 'Position', [40 40 1600 500]);
    plot(photoDiode(1:5:end), 'k'); hold on
    xline(downs(difVals < 850) / 5, 'm');
    xline(downs(difVals >= 850 & difVals <= 1250) / 5, 'g');
    xline(downs(difVals > 1250) / 5, 'b');
    title(sprintf('%s photodiode (magenta=cue green=sniff blue=resp)', strrep(id, '_', '\_')));
    saveas(fig, fullfile(OUTD, ['noCueTTL_' id '.png']));
    close(fig);
    clear photoDiode
end
fprintf('\ntask6_probeNoCueTTL: DONE\n');

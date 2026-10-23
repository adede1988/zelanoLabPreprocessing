% TASK-SPECIFIC ingestion for cueTask3 (event channel + run result files ->
% <id>_cueTask3PreProc.mat). Added 2026-10-16 with 261008_INR_NWU_SS_1.
%
% cueTask3 = the lab's odor-matching cue task (cueTask) with THREE sniffs per
% trial (task code OBE_task_backup\tasks\olf_cuetask\src\olf_cuetask_3sniff.m):
% per trial a cue word, a 3-2-1 count-down (the odor line opens at "1"), three
% SNIFF cues 1.1 s apart with the odor line open across them, then the Yes/No
% answer ("did the odor match the word?"). Two runs of 20 trials in ONE
% recording (raw\raw_cueTask3\raw_cueTask3.mat); one result file per run,
% <id>_3sniffs_run<k>_cuelist_odor_results.mat (the standard cue result
% format) in L.behCue\<id>_3sniffs\.
%
% Reuses the standard cue pieces: outMat_to_table (result file -> table), the
% cue task's odor-line recode (line 1 = air, so odor codes 2-11 -> 1-10 = the
% cue words), cueTrialType (hit / miss / cr / fa / skip / noCue), fillRawNaNs,
% toTargetSamples, findLoadDataScript. The event parse (parseEvents_cueTask3)
% is strict: the pulse sequence must match the protocol exactly, the response
% pulses must match the result files' answers, and the trial-start pulse
% intervals must match the task laptop's trial-start clock.
%
% Output (intermediate; cueTask3PreProc_main overwrites it with the final -
% same file on Windows, CLAUDE.md section 2): outDat.data / labels / CSClist /
% fs (raw rate), behDat (per trial: n (trial in run), cue, odor (recoded),
% trialtype, response, response_str, iti, trl_start, rsp_end, run, type),
% TTL table [nTrial x 5] (trialStart, response, sniff1, sniff2, sniff3; 500-Hz
% samples), ttlInfo (the parse record), task / type / OGdataDir / loadFile /
% preProcScript.

clear
% ---- machine paths (everything machine-specific comes from labPaths) ----
zlpHere=fileparts(mfilename('fullpath')); zlpRoot=zlpHere; while exist(fullfile(zlpRoot,'config','labPaths.m'),'file')~=2, zlpP=fileparts(zlpRoot); if strcmp(zlpP,zlpRoot), error('zelanoLabPreprocessing root not found'); end; zlpRoot=zlpP; end; addpath(genpath(zlpRoot));
L = labPaths();
addpath(genpath(L.repo))

cfg        = applyParams('cueTask3','makeOutDat');
sessionIDs = cfg.sessionIDs;
datPre     = cfg.datPre;
datPrei    = cfg.datPrei;
fsTarget   = 500;   % final sample rate (applyParams P.fs_target): TTLs are stored in these samples

% targeted-run filter: comma-separated session ids in ZLP_MAKEOUTDAT_ONLY
% restrict the sweep (blank = all sessions)
onlyEnv = getenv('ZLP_MAKEOUTDAT_ONLY');
onlyList = {};
if ~isempty(onlyEnv), onlyList = strtrim(strsplit(onlyEnv, ',')); end

for sessi = 1:numel(sessionIDs)
    id = sessionIDs{sessi};
    if ~isempty(onlyList) && ~any(strcmp(onlyList, id)), continue; end
    try
    sessDir   = fullfile(datPre{datPrei(sessi)}, id);
    preDir    = fullfile(sessDir, 'preProc');
    interPath = fullfile(preDir, [id '_cueTask3PreProc.mat']);
    if exist(interPath, 'file')
        disp(['already done on: ' id]);
        continue
    end
    disp(['Working on: ' id])

    % --- raw: one recording holds both runs ---
    dat1 = load(fullfile(sessDir, 'raw', 'raw_cueTask3', 'raw_cueTask3.mat'));
    dat1 = dat1.curDat;
    % recording gaps arrive as NaN from newer FieldTrip: fill them (as the cue
    % task does) so the event z-score is defined
    [dat1, nNan] = fillRawNaNs(dat1, 12000);
    fsRaw = dat1.rawData.fsample;

    % --- behaviour: one result file per run, run1..runK ---
    behDir = fullfile(L.behCue, [id '_3sniffs']);
    bf = dir(fullfile(behDir, '*_run*_cuelist_odor_results.mat'));
    runNo = zeros(numel(bf), 1);
    for k = 1:numel(bf)
        tok = regexp(bf(k).name, '_run(\d+)_cuelist_odor_results\.mat$', 'tokens', 'once');
        if isempty(tok), error('unexpected result file name %s', bf(k).name); end
        runNo(k) = str2double(tok{1});
    end
    [runNo, ord] = sort(runNo); bf = bf(ord);
    if isempty(bf) || ~isequal(runNo(:)', 1:numel(bf))
        error('cueTask3 result files in %s must be exactly run1..runK (found runs %s)', ...
            behDir, mat2str(runNo'));
    end
    behRuns = cell(numel(bf), 1);
    for k = 1:numel(bf)
        b = load(fullfile(bf(k).folder, bf(k).name));
        tk = outMat_to_table(b.outMat, b.datalabel);
        tk.run = repmat(k, height(tk), 1);
        behRuns{k} = tk;
    end
    beh = vertcat(behRuns{:});
    % odor-line recode (cue task): line 1 is air, so the task stores odor + 1;
    % codes 2-11 are the cue words 1-10. Strict: every code must be 2-11.
    if ~all(ismember(beh.odor, 2:11))
        error('odor codes outside 2-11: %s', mat2str(unique(beh.odor)'));
    end
    beh.odor = beh.odor - 1;
    beh.type = cueTrialType(beh);

    % --- event channel -> TTLs ---
    isEv = cellfun(@(x) contains(x, 'event'), dat1.outLabs);
    if sum(isEv) ~= 1, error('expected one event channel, found %d', sum(isEv)); end
    nPerRun = cellfun(@height, behRuns);
    [ttlRaw, ttlInfo] = parseEvents_cueTask3(dat1.rawData.trial{1}(isEv, :), fsRaw, ...
        nPerRun, beh.response ~= 999, beh.trl_start);
    ttlInfo.nNaNFilled = nNan;
    ttlInfo.behFiles = {bf.name};
    TTLs = toTargetSamples(ttlRaw, fsRaw, fsTarget);

    % --- intermediate outDat (same fields as the cue intermediate + ttlInfo) ---
    outDat = struct;
    outDat.labels  = dat1.outLabs;
    outDat.CSClist = dat1.ncslabels;
    outDat.fs      = fsRaw;
    outDat.sessID  = id;
    outDat.behDat  = beh;
    outDat.data    = dat1.rawData.trial{1};
    outDat.task    = "cueTask3";
    outDat.OGdataDir = sessDir;
    % LoadData provenance (shared lookup; never fatal)
    outDat.loadFile = findLoadDataScript(outDat.OGdataDir, 'cueTask3', dat1);
    outDat.preProcScript = 'cueTask3_makeOutDat.m';
    if datPrei(sessi) == 1
        outDat.type = 'Dupi';
    elseif datPrei(sessi) == 2
        outDat.type = 'OBE';
    end
    outDat.TTL = table(TTLs(:,1), TTLs(:,2), TTLs(:,3), TTLs(:,4), TTLs(:,5), ...
        'VariableNames', {'trialStart', 'response', 'sniff1', 'sniff2', 'sniff3'});
    outDat.ttlInfo = ttlInfo;

    % --- QC figure: the event channel with every parsed pulse ---
    figDir = fullfile(L.figPath, id, 'cueTask3');
    if ~isfolder(figDir), mkdir(figDir); end
    pdz = dat1.rawData.trial{1}(isEv, :);
    pdz = (pdz - mean(pdz)) / std(pdz);
    h = figure('Visible', 'off', 'Position', [0 0 2400 600]);
    plot((1:numel(pdz)) / fsRaw, pdz, 'Color', [0.5 0.5 0.5]); hold on
    pu = ttlInfo.pulses;
    roles = ["start" "cue" "sniff1" "sniff2" "sniff3" "response" "end"];
    rc = [0 0 0; 1 0 1; 0 0.6 0; 0 0.8 0.4; 0 0.4 0.8; 0 0 1; 0.5 0.5 0.5];
    for k = 1:numel(roles)
        m = pu.role == roles(k);
        if any(m), xline(pu.onsetRaw(m) / fsRaw, 'Color', rc(k, :)); end
    end
    xlabel('s'); ylabel('event (z)');
    title(sprintf('%s cueTask3 events: %d pulses, %d trials (%s per run); start/end black-grey, cue magenta, sniffs green-blue, response blue', ...
        id, height(pu), height(beh), mat2str(nPerRun')), 'Interpreter', 'none');
    saveas(h, fullfile(figDir, 'cueTask3_events.png'));
    close(h);

    fprintf(['%s: %d trials, %d pulses parsed; sniff spacing %.3f-%.3f s; cue->sniff1 %.2f-%.2f s; ' ...
             'trial-start clock residual max %.3f s; NaN filled %d\n'], id, height(beh), ttlInfo.nPulses, ...
             ttlInfo.sniffGapSec([1 3]), ttlInfo.cueToSniff1Sec([1 3]), ttlInfo.clockResidualMaxSec, nNan);

    if ~isfolder(preDir), mkdir(preDir); end
    save(interPath, 'outDat', '-v7.3');

    clear dat1 outDat beh behRuns pdz
    catch ME
        disp(['fail for ', id, ': ', ME.message])
        disp(getReport(ME, 'extended', 'hyperlinks', 'off'))
    end
    close all
end

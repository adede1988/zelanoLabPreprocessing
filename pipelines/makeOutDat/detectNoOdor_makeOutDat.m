% TASK-SPECIFIC ingestion (event channel + behavior result file ->
% <id>_detectNoOdorPreProc.mat). The whole body below is detectNoOdor-specific;
% only the header (labPaths + the applyParams cfg block) is shared boilerplate.
%
% detectNoOdor (added 2026-10-15 with 261008_INR_NWU_SS_1): cued sniffs, the
% participant tries to detect an odor but there is never one (the task script
% OBE_task_backup\tasks\odor_detection\src\Main_detectiontask_f.m opens the air
% line only). Per trial: countdown 3-2-1, SNIFF cue (0.5-s DAQ pulse), Yes/No
% answer on a button box (0.3-s DAQ pulse at the key press).
%   raw          <root>\<id>\raw\raw_detectNoOdor\raw_detectNoOdor.mat (exact name)
%   behavior     labPaths().behOdorDetection\results\results_OBE_Odor_detection\<id>\
%                (+ the run's cuelist for the counterbalanced Yes/No screen side):
%                tasks/detectNoOdor/loadBeh_detectNoOdor
%   event parse  tasks/detectNoOdor/parse_detectNoOdor_events (median / rail
%                levels, strict start code - trials - end code motif)
%   TTL          table [nTrial x 3] in final 500-Hz samples, columns
%                trialStart, response, sniff (the cue layout: the shared
%                detect_sniffs_from_TTLs reads the sniff targets from column 3
%                on); trialStart = sniff - 3 s, the nominal onset of the 3-2-1
%                countdown (not marked on the DAQ); response NaN = no answer
%   checks       nTrials == result-file trials; a response pulse exactly where
%                the file has an answer; cue-to-cue intervals vs the file's
%                trl_start intervals (max |residual| <= maxAlignErrSec)
% Figure: <figPath>\<id>\detectNoOdor\ttlParse_detectNoOdor.png

clear
% ---- machine paths (everything machine-specific comes from labPaths) ----
zlpHere=fileparts(mfilename('fullpath')); zlpRoot=zlpHere; while exist(fullfile(zlpRoot,'config','labPaths.m'),'file')~=2, zlpP=fileparts(zlpRoot); if strcmp(zlpP,zlpRoot), error('zelanoLabPreprocessing root not found'); end; zlpRoot=zlpP; end; addpath(genpath(zlpRoot));
L = labPaths();
addpath(genpath(L.repo))

cfg        = applyParams('detectNoOdor','makeOutDat');
sessionIDs = cfg.sessionIDs;
datPre     = cfg.datPre;
datPrei    = cfg.datPrei;
fsTarget   = 500;            % final sample rate (applyParams P.fs_target): TTLs are stored in these samples
countdownSec   = 3;          % trialStart = sniff cue - 3 s (three 1-s countdown steps, task code)
maxAlignErrSec = 0.25;       % cue-to-cue interval vs trl_start interval; ReadNCS phantom NaN
                             % tails insert up to ~0.2 s of time per partial Atlas record

% targeted-run filter: comma-separated session ids in ZLP_MAKEOUTDAT_ONLY
% restrict the sweep (blank = all sessions)
onlyEnv = getenv('ZLP_MAKEOUTDAT_ONLY');
onlyList = {};
if ~isempty(onlyEnv), onlyList = strtrim(strsplit(onlyEnv, ',')); end

for sessi = 1:numel(sessionIDs)
    sessID = sessionIDs{sessi};
    if ~isempty(onlyList) && ~any(strcmp(onlyList, sessID))
        continue
    end
    try
    disp(['Working on: ' sessID])
    sessDir    = fullfile(datPre{datPrei(sessi)}, sessID);
    preProcDir = fullfile(sessDir, 'preProc');
    interPath  = fullfile(preProcDir, [sessID '_detectNoOdorPreProc.mat']);
    if exist(interPath, 'file')
        disp(['already done on: ' sessID])
        continue
    end

    % ---- raw (exact folder name) ----
    rawMat = fullfile(sessDir, 'raw', 'raw_detectNoOdor', 'raw_detectNoOdor.mat');
    if ~exist(rawMat, 'file')
        error('detectNoOdor_makeOutDat:noRaw', 'raw file not found: %s', rawMat);
    end
    dat = load(rawMat);
    dat = dat.curDat;
    fsRaw = dat.rawData.fsample;
    % recording gaps / partial-record tails arrive as NaN (ReadNCS): note where,
    % then fill them (shared fillRawNaNs; same limit as the cue new set)
    nanCol = all(isnan(dat.rawData.trial{1}), 1);
    dn = diff([false nanCol false]);
    nanRuns = table((find(dn == 1)' - 1) / fsRaw, (find(dn == -1) - find(dn == 1))', ...
        'VariableNames', {'startSec', 'nSamples'});
    clear nanCol dn
    dat = fillRawNaNs(dat, 12000);

    % ---- behavior ----
    [behDat, behSrc] = loadBeh_detectNoOdor(L.behOdorDetection, sessID);

    % ---- event channel -> trials ----
    idxEvt = find(contains(dat.outLabs, 'event'));
    if ~isscalar(idxEvt)
        error('detectNoOdor_makeOutDat:event', 'expected exactly 1 event channel, found %d', numel(idxEvt));
    end
    photoDiode = dat.rawData.trial{1}(idxEvt, :);
    [ev, pulses, pInfo] = parse_detectNoOdor_events(photoDiode, fsRaw);

    nT = height(behDat);
    if pInfo.nTrials ~= nT
        error('detectNoOdor_makeOutDat:trialCount', ...
            '%d sniff cues on the event channel, %d trials in %s', pInfo.nTrials, nT, behSrc.resultFile);
    end
    hasPulse = ~isnan(ev.response);
    hasAns   = ~isnan(behDat.response);
    if ~isequal(hasPulse, hasAns)
        error('detectNoOdor_makeOutDat:responseMismatch', ...
            'response pulses and answered trials differ (trials %s)', mat2str(find(hasPulse ~= hasAns)'));
    end
    % cue-to-cue intervals vs the task clock (start_trl is taken just before the
    % SNIFF sound + pulse); the residuals also expose inserted NaN time
    alignResid = diff(ev.sniff) / fsRaw - diff(behDat.trl_start);
    if max(abs(alignResid)) > maxAlignErrSec
        [~, iw] = max(abs(alignResid));
        error('detectNoOdor_makeOutDat:alignment', ...
            'cue-to-cue interval %d->%d differs from the result file by %.3f s (> %.2f s)', ...
            iw, iw + 1, alignResid(iw), maxAlignErrSec);
    end
    % DAQ response latency vs the file's duration_trial (start_trl -> last
    % response-loop pass before the key press): informational
    latResid = (ev.response - ev.sniff) / fsRaw - behDat.duration_trial;

    % ---- TTL table (final 500-Hz samples) ----
    sniffT = toTargetSamples(ev.sniff, fsRaw, fsTarget);
    TTL = table;
    TTL.trialStart = toTargetSamples(ev.sniff - round(countdownSec * fsRaw), fsRaw, fsTarget);
    TTL.response   = toTargetSamples(ev.response, fsRaw, fsTarget);
    TTL.sniff      = sniffT;

    % ---- QC figure: the parse ----
    figDir = fullfile(L.figPath, sessID, 'detectNoOdor');
    if ~exist(figDir, 'dir'), mkdir(figDir); end
    tSec = (0:numel(photoDiode) - 1) / fsRaw;
    fig = figure('Visible', 'off', 'Position', [20 20 1800 700]);
    subplot(2, 1, 1)
    plot(tSec(1:10:end), photoDiode(1:10:end), 'Color', [0.5 0.5 0.5]); hold on
    yline(pInfo.thresh, 'k:');
    roles = ["preamble", "startCode", "sniff", "response", "endCode"];
    cols  = [0.6 0.6 0.6; 0.9 0.6 0; 0 0.7 0; 0.85 0 0; 0.5 0 0.8];
    hl = gobjects(0);
    for ri = 1:numel(roles)
        m = pulses.role == roles(ri);
        if any(m)
            h = xline(pulses.tSec(m), 'Color', cols(ri, :), 'LineWidth', 1);
            hl(end+1) = h(1); %#ok<SAGROW>
        end
    end
    legend(hl, roles(arrayfun(@(r) any(pulses.role == r), roles)), 'Location', 'eastoutside');
    xlabel('s (raw file)'); ylabel('event (\muV)');
    title(sprintf('%s detectNoOdor event parse: %d trials, %d responses, preamble %d pulse(s), start code %.2f s', ...
        sessID, pInfo.nTrials, pInfo.nResponses, pInfo.nPreamble, pInfo.startCodeSec), 'Interpreter', 'none');
    subplot(2, 2, 3)
    plot(1:numel(alignResid), 1000 * alignResid, 'ko-'); yline(0, ':');
    xlabel('cue-to-cue interval'); ylabel('DAQ - task clock (ms)');
    title('cue intervals vs result-file trl\_start intervals');
    subplot(2, 2, 4)
    plot(1:nT, (ev.response - ev.sniff) / fsRaw, 'ro'); hold on
    plot(1:nT, behDat.duration_trial, 'k.');
    legend({'DAQ response - cue', 'file duration\_trial'}, 'Location', 'best');
    xlabel('trial'); ylabel('s');
    saveas(fig, fullfile(figDir, 'ttlParse_detectNoOdor.png'));
    close(fig);

    % ---- intermediate outDat ----
    outDat = struct;
    outDat.labels  = dat.outLabs;
    outDat.CSClist = dat.ncslabels;
    outDat.fs      = fsRaw;
    outDat.sessID  = sessID;
    outDat.behDat  = behDat;
    outDat.data    = dat.rawData.trial{1};
    outDat.TTL     = TTL;
    ttlInfo = struct;
    ttlInfo.pulses = pulses;                       % raw-file samples / seconds
    ttlInfo.parse  = pInfo;
    ttlInfo.sniffRaw = ev.sniff;
    ttlInfo.responseRaw = ev.response;
    ttlInfo.startCodeRaw = ev.startCode;
    ttlInfo.endCodeRaw = ev.endCode;
    ttlInfo.trialStartNote = sprintf(['trialStart = sniff cue - %g s: nominal onset of the 3-2-1 ' ...
        'countdown (Main_detectiontask_f), not marked on the DAQ'], countdownSec);
    ttlInfo.alignResidSec = alignResid;            % DAQ cue-to-cue minus result-file trl_start intervals
    ttlInfo.latencyResidSec = latResid;            % DAQ response latency minus duration_trial
    ttlInfo.nanRuns = nanRuns;                     % all-channel NaN runs in the raw file (filled)
    outDat.ttlInfo = ttlInfo;
    outDat.behSource = behSrc;
    outDat.task = "detectNoOdor";
    outDat.OGdataDir = sessDir;
    outDat.loadFile = findLoadDataScript(outDat.OGdataDir, 'detectNoOdor', dat);
    outDat.preProcScript = 'detectNoOdor_makeOutDat.m';
    % (informational only: assembleOutDat sets the final's type from the sheet)
    if datPrei(sessi) == 1
        outDat.type = 'Dupi';
    elseif datPrei(sessi) == 2
        outDat.type = 'OBE';
    elseif datPrei(sessi) == 3
        outDat.type = 'EEG';
    end

    fprintf(['%s: %d trials, %d answered (Yes %d / No %d), cue-interval residual max %.3f s, ' ...
             'latency residual median %.3f s, %d NaN run(s) (%d samples)\n'], sessID, nT, sum(hasAns), ...
        sum(strcmp(behDat.response_str, 'Yes')), sum(strcmp(behDat.response_str, 'No')), ...
        max(abs(alignResid)), median(latResid, 'omitnan'), height(nanRuns), sum(nanRuns.nSamples));

    if ~exist(preProcDir, 'dir'), mkdir(preProcDir); end
    save(interPath, 'outDat', '-v7.3');

    clear dat outDat photoDiode behDat TTL ev pulses pInfo ttlInfo
    catch ME
        disp(['fail for ', sessID, ': ', ME.message])
        disp(getReport(ME, 'extended', 'hyperlinks', 'off'))
    end
    close all
end

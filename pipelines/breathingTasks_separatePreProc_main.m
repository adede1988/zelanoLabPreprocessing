
clear
% ---- machine paths (everything machine-specific comes from labPaths) ----
zlpHere=fileparts(mfilename('fullpath')); zlpRoot=zlpHere; while exist(fullfile(zlpRoot,'config','labPaths.m'),'file')~=2, zlpP=fileparts(zlpRoot); if strcmp(zlpP,zlpRoot), error('zelanoLabPreprocessing root not found'); end; zlpRoot=zlpP; end; addpath(genpath(zlpRoot));
L            = labPaths();
addpath(genpath(L.repo))
addpath(genpath(L.eeglab))

figPath      = L.figPath;
EEGLOC       = readtable(L.eegLocCsv);
set(0, 'defaultfigurewindowstyle', 'normal')

% =====================================================================
%  breathingTasks_separate preprocessing -- main pipeline (Tasks_260824 Task 9)
%  Each condition recording goes through the shared core + breath/ECG stages
%  SEPARATELY (filters, ICA and segmentation never straddle a file boundary),
%  then the results are concatenated (D12b, concatSections). No makeOutDat:
%  raw condition files are loaded directly (like O15).
%  TASK-SPECIFIC pieces: assembleRaw_breathingTasks_separate,
%  concatSections, build_behavior_table_breathingTasks_separate,
%  sepSectionP (one recording's per-condition parameters); its sheet
%  writer is config/writeSheetSep.
%
%  ECHEM MODE (tasks_261014 task 6): ZLP_SEP_ECHEM=1 runs the same pipeline
%  on each session's dataType ephys_echem condition rows (applyParams
%  'breathingTasks_separate_echem') and saves
%  <id>_breathingTasks_echem_separatepreproc.mat (+ its own processed-
%  behaviour CSV and figure folder); the default run is unchanged. Echem
%  mode requires ZLP_MAIN_ONLY: the sheet lists more ephys_echem rows with a
%  condition Task than have been reviewed for it (2026-10-14: RY_1, KA_2,
%  RX_2, RC_2 besides BW_2).
% =====================================================================

% echem mode: the ephys_echem condition recordings, into their own final
echemMode = strcmp(getenv('ZLP_SEP_ECHEM'), '1');
if echemMode
    sepTaskArg = 'breathingTasks_separate_echem';
    fileTag    = 'breathingTasks_echem_separate';
    disp('breathingTasks_separate ECHEM MODE (ZLP_SEP_ECHEM=1): dataType ephys_echem condition rows')
else
    sepTaskArg = 'breathingTasks_separate';
    fileTag    = 'breathingTasks_separate';
end
cfg        = applyParams(sepTaskArg,'main');
sessionIDs = cfg.sessionIDs;

% D4: ALL Task 9 sessions are run-on-guess under the batch override
allowGuessRunEnv = strcmp(getenv('ZLP_ALLOW_GUESS_RUN'), '1');
% targeted-run filter (mirrors cueTaskPreProc_main): ZLP_MAIN_ONLY = comma IDs
mainOnlyEnv = getenv('ZLP_MAIN_ONLY');
mainOnlyList = {};
if ~isempty(mainOnlyEnv), mainOnlyList = strtrim(strsplit(mainOnlyEnv, ',')); end
if echemMode && isempty(mainOnlyList)
    error('breathingTasks_separate echem mode: set ZLP_MAIN_ONLY to the session(s) to process');
end

for s = 1:numel(sessionIDs)
    try
    disp(['working on ', sessionIDs{s}])
    S = struct;
    S.id   = sessionIDs{s};
    if ~isempty(mainOnlyList) && ~any(strcmp(mainOnlyList, S.id)), continue; end
    S.root = cfg.root{s};
    S.fig  = fullfile(figPath, S.id);

    P = applyParams(sepTaskArg, S.id);
    isGuess = ~strcmpi(strtrim(P.paramSource), 'curated');
    P.allowGuessRun = allowGuessRunEnv;        % D4: every Task 9 session
    % task subfolder (= assembleOutDat's outDat.figs) so the paramCheck PNGs of the
    % session's different breath-type tasks cannot overwrite each other (C12);
    % echem mode: its own subfolder (fileTag) so the two runs never collide
    P.figDir = fullfile(S.fig, P.task);
    if echemMode, P.figDir = fullfile(S.fig, fileTag); end

    % --- done-check ---
    preDir = fullfile(S.root, S.id, 'preProc');
    fpath  = fullfile(preDir, [S.id '_' fileTag 'preproc.mat']);
    if isSessionDone(fpath, {'moreThan1', 'bmFeatures'})
        disp(['Done with ' S.id ' ; ' num2str(s)])
        continue
    end

    raws = assembleRaw_breathingTasks_separate(S, P);   % <-- TASK-SPECIFIC (applies P.condTrimSec)

    % respiration carry (full EEG rerun, 2026-10-22): with ZLP_CARRY_FROM set (the previous final) each
    % condition recording takes its rsp rows from the previous final's matching section (strict section
    % match, carryRespFromFinal); 'rspSelected' is rebuilt by concatSections and checked against it.
    % Without the variable CS is empty and nothing below changes.
    CS = carryOpenFinal(P, S.id, struct('ignoreLabels', {{'rspSelected'}}));
    secRecs = cell(1, numel(raws));

    % --- per-condition-file shared core + breath/ECG stages (D12b) ---
    segs = struct('od', {}, 'label', {}, 'condition', {}, 'srcFile', {}, ...
                  'raw', {}, 'blinkSkipped', {}, 'respSkipped', {});
    beatMixed = false;
    for c = 1:numel(raws)
        % NB: cell-valued struct() args must be wrapped in {} or struct()
        % builds a struct ARRAY with one element per cell entry
        raw = struct('sessID', S.id, 'fs_raw', raws(c).fs_raw, ...
                     'data', raws(c).data, 'labels', {raws(c).labels}, ...
                     'beh', table());
        % this recording's parameters (sepSectionP): its sheet row's
        % respiration channel/polarity and ECG beatSpec (identical to P's
        % unless the session's rows differ - 260921_OBE_NWU_BW_2 rsp) and the
        % optional per-condition switches P.condBlinkRemoval / condRespSkip.
        % Pc is P with those set; everything per-section below uses Pc.
        [Pc, secInfo] = sepSectionP(P, raws(c).condition);
        beatMixed = beatMixed || secInfo.beatMixed;
        od = assembleOutDat(raw, S, Pc);
        if echemMode
            od.figs = P.figDir;                % not the main run's figure folder
            if ~exist(od.figs, 'dir'), mkdir(od.figs); end
        end
        if c == 1 && isGuess
            [od, Pc] = paramCheck(od, Pc);   % run-on-guess: saves QC figures
            if secInfo.rspMixed
                % interactive edits to the rsp choice would apply to one section only
                Pc.rspIDX = secInfo.rspIDX; Pc.rspFlip = secInfo.rspFlip;
            else
                P.rspIDX = Pc.rspIDX; P.rspFlip = Pc.rspFlip;
            end
            % the fields paramCheck may change (the rest of Pc is per-section)
            P.macroRemove = Pc.macroRemove; P.spikeClean = Pc.spikeClean;
        end

        od = runSharedCore(od, Pc, EEGLOC);   % shared: downsample, EEG, macros
        if ~isempty(CS)
            od = carryRespFromFinal(od, Pc, CS, struct('index', c, 'label', raws(c).label, ...
                'nSections', numel(raws), 'rspIDX', Pc.rspIDX, 'rspFlip', Pc.rspFlip));
            secRecs{c} = od.carry;
        end
        % blink-ICA QC figures have fixed names; keep one per section (the
        % last section's used to overwrite the others - 2026-10-12)
        for fnm = {'removedBlink', 'blinkICA'}
            src = fullfile(od.figs, [fnm{1} '.jpg']);
            if exist(src, 'file')
                movefile(src, fullfile(od.figs, sprintf('%s_sec%d.jpg', fnm{1}, c)), 'f');
            end
        end

        if secInfo.respSkipped
            % respiration not recoverable in this recording (P.condRespSkip):
            % no segmentation - its breaths would be guesses. Empty bmObj and a
            % stub bmFeatures with the fields concatSections reads.
            fprintf('   section %d (%s): respiration SKIPPED (P.condRespSkip) - no breaths\n', c, raws(c).label);
            od.bmObj = zeros(0, 14);
            od.bmFeatures = struct('engine', 'none', 'version', '', 'dataType', '', 'srate', od.fs, ...
                'skipped', true, 'bmObjBreathIdx', zeros(1, 0), 'nInhalesDetected', 0, ...
                'secondaryFeatures', [], 'conditioning', []);
        else
            isRsp  = cellfun(@(x) contains(x, 'rsp'), od.labels);
            rspDat = od.data(isRsp, :);
            rspDat = rspDat(Pc.rspIDX, :) .* Pc.rspFlip;
            [od.bmObj, od.bmFeatures] = segmentBreaths_zlp(rspDat, od.fs);
            % (2026-10-22, user) the incomplete-exhale merge rule, after the engine, per recording
            od = applyBreathMerge(od, rspDat, Pc);
        end

        hasECG = sum(cellfun(@(x) contains(x, 'ECG'), od.labels)) > 0;
        if hasECG && c == 1
            % viability probe: a systematically wrong beatSpec (bad lead /
            % polarity) must not kill the session - drop ECG for ALL sections
            % so the concatenated labels stay identical (strict D12b). Uses
            % this recording's own beatSpec (Pc; = P.beatSpec unless the
            % session's rows differ)
            try
                [ECGzP, sepP] = buildECGz(od);
                bpmP = numel(Pc.getBeats(ECGzP, sepP)) / (size(od.data, 2) / od.fs / 60);
                if bpmP < 20
                    warning('%s: beat detection implausible (%.1f bpm) - ECG dropped for the session, REVIEW', ...
                        S.id, bpmP);
                    hasECGSession = false;
                else
                    hasECGSession = true;
                end
                clear ECGzP
            catch
                hasECGSession = false;
            end
        elseif ~hasECG
            hasECGSession = false;
        end
        secECG = hasECG && hasECGSession;
        if secECG && c > 1
            % per-section viability (2026-09-25, 260831_OBE_NWU_CS_2: the ECG
            % died in the last section only). The session keeps its ECG; this
            % section gets an all-NaN RRint row so the labels still match (D12b)
            try
                [ECGzS, sepS] = buildECGz(od);
                bpmS = numel(Pc.getBeats(ECGzS, sepS)) / (size(od.data, 2) / od.fs / 60);   % this recording's spec
                clear ECGzS
            catch
                bpmS = 0;
            end
            if bpmS < 20
                warning('%s section %d (%s): beat detection implausible (%.1f bpm) - NaN RRint for this section, REVIEW', ...
                    S.id, c, raws(c).label, bpmS);
                secECG = false;
                od.data(end+1, :) = NaN;
                od.labels{end+1} = 'RRint';
            end
        end
        if secECG
            od = processECG(od, Pc);
            % processECG saves fixed-name QC figures; keep one per section
            for fnm = {'ECG_beatDetect', 'interbeatHist', 'RespirationHeart'}
                src = fullfile(od.figs, [fnm{1} '.jpg']);
                if exist(src, 'file')
                    movefile(src, fullfile(od.figs, sprintf('%s_sec%d.jpg', fnm{1}, c)), 'f');
                end
            end
        end
        fprintf('   section %d (%s): %d samples, %d breaths\n', c, raws(c).label, ...
            size(od.data, 2), size(od.bmObj, 1));
        rawInfo = struct('rawFirstSample', raws(c).rawFirstSample, 'rawLastSample', raws(c).rawLastSample, ...
                         'rawSamples', raws(c).rawSamples, 'trimSec', raws(c).trimSec);
        segs(c) = struct('od', od, 'label', raws(c).label, ...
                         'condition', raws(c).condition, 'srcFile', raws(c).srcFile, ...
                         'raw', rawInfo, 'blinkSkipped', secInfo.blinkSkipped, ...
                         'respSkipped', 2 * double(secInfo.respSkipped));
        clear od raw
    end

    % --- concatenate (D12b) + behavior table (D12c) ---
    outDat = concatSections(segs, S, P);
    clear segs
    outDat.moreThan1 = 1;
    if ~isfield(outDat, 'rspSelectedNote')   % concatSections built 'rspSelected' when the sections' channels differ
        outDat.rspIDX  = P.rspIDX;
        outDat.rspFlip = P.rspFlip;
    end
    if echemMode
        outDat.sepEchem = true;
        outDat.echemNote = ['condition recording(s) made during electrochemistry (sheet dataType ephys_echem), ' ...
            'processed apart from the session''s breathingTasks_separate final; the echem voltammetry ' ...
            'artifacts on the macro channels are NOT cleaned (tasks_261014 task 6)'];
    end

    outDat = build_behavior_table_breathingTasks_separate(outDat);

    hasRR = any(cellfun(@(x) contains(x, 'RRint'), outDat.labels));
    if hasRR
        if isGuess
            if beatMixed
                % one spec cannot describe sections with different specs: the
                % per-section ECG_beatDetect_sec<c> figures are the QC here
                disp('paramCheckECG skipped: per-condition beatSpecs differ (see ECG_beatDetect_sec<c>.jpg)')
            else
                P = paramCheckECG(outDat, P);
            end
        end
        outDat = flagBadBreaths(outDat);
    else
        outDat.behDat = fillNaNHRV(outDat.behDat);
        outDat.ecgSkipped = 1;
    end
    % breaths whose QC window crosses a section boundary get goodBreath = 0
    % (the window would mix two recordings)
    if ismember('goodBreath', outDat.behDat.Properties.VariableNames)
        for b = 1:height(outDat.sections)
            edges = [outDat.sections.startSample(b), outDat.sections.endSample(b)];
            for e = edges
                near = abs(outDat.behDat.finalOnset - e) < 10 * outDat.fs;
                outDat.behDat.goodBreath(near) = 0;
            end
        end
    end

    if isfield(outDat, 'respSkipped') && outDat.respSkipped == 2
        disp('respiration skipped in every section (P.condRespSkip): no breaths, no sniff-epoch figure')
    else
        R = preprocess_respiration_wholetrace(outDat);
        plot_sniff_epochs(outDat, R);
    end

    % carry: the carried rows must have survived to here (the whole-session rows, rspSelected included);
    % the previous final's post-hoc fields are kept; the record gets one entry per section
    outDat = carryFinishFromFinal(outDat, CS, secRecs);

    % --- Guess gate (D4: all Task 9 sessions run under the override) ---
    if isGuess
        if ~P.allowGuessRun
            error(['breathingTasks_separate guess params: inspect the saved ' ...
                   'figures, then set paramSource=curated and re-run.']);
        end
        disp(['RUN-ON-GUESS (D4): saving outputs for ' S.id '; paramSource stays guess'])
    else
        P.paramSource = 'curated';
        writeSheetSep(P, S.id, 'params');
    end

    if ~exist(L.procBehavior, 'dir'), mkdir(L.procBehavior); end
    writetable(outDat.behDat, fullfile(L.procBehavior, ...
        [outDat.sessID '_' fileTag '_processedBreathing.csv']));

    if ~exist(preDir, 'dir'), mkdir(preDir); end
    save(fpath, 'outDat', '-v7.3');
    writeSheetSep(P, S.id, 'X');    % D12d: every in-scope condition row (echem mode: the ephys_echem ones)

    catch ME
        disp(['fail for ', sessionIDs{s}, ': ', ME.message]); disp(getReport(ME, 'extended', 'hyperlinks', 'off'))
    end
    close all
end

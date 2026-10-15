function out = applyParams(task, sel, xlsxPath)
% applyParams  Single source of truth for session lists and per-session params.
%
%   Reads dataTracking.xlsx and returns either:
%     Mode A (cfg)  : a session-list config for a loop      (sel = 'makeOutDat'|'main')
%     Mode B (P)    : a per-session parameter struct        (sel = a session ID)
%
%   Replaces the hard-coded arrays in the *_makeOutDat / *_main scripts and the
%   entire parameter switch in getSessionParams_<task>.m.
%
%   Usage
%     cfg = applyParams(task, 'makeOutDat' | 'main' [, xlsxPath])   % Mode A
%     P   = applyParams(task, sessID                  [, xlsxPath]) % Mode B
%
%   task in {'breathingTask','cueTask','threshTask','O15','EmotionalMovieTask',
%            'alternating6Blocks','breathingTasks_separate','pacedBreathing',
%            'vipassana','ADmeditation','respiratorySweep'}
%     + 'breathingTasks_separate_echem' (tasks_261014 task 6): the same task
%       (P.task = 'breathingTasks_separate', P.sepEchem = true) whose session
%       rows are the dataType ephys_echem condition rows instead of the
%       ephys ones - the condition recordings made during electrochemistry,
%       processed into their own final by the sep main (ZLP_SEP_ECHEM=1)
%   default xlsxPath = labPaths().adminXlsx, the lab master
%     (R:\Neurology\Zelano_Lab\Lab_Common\Admin\Data\dataTracking.xlsx). If that
%     file is unreachable or lacks the datPre parameter column, falls back - with
%     an applyParams:localFallback warning on every call - to the copy at the
%     repo root, <repo>\dataTracking.xlsx.
%     EXCEPTION - ADmeditation (2026-10-08) is tracked in its own sheet,
%     labPaths().adMedXlsx (Admin\Data\dataTracking_AD_meditation.xlsx, same
%     layout: header row 2, data from row 3); no local fallback. That sheet
%     carries only the parameter columns this task uses; the master-only
%     columns are treated as blank (padMissingCols).
%
%   Mode A cfg fields:
%     .sessionIDs (n x 1 cell)  .root (n x 1 cell)  .datPre (1 x k cell, fixed order)
%     .datPrei (1 x n)  .isNewStd (1 x n logical)  .newIDs (cell)
%     .rspIDX (1 x n)  .rspFlip (1 x n)  .paramSource (1 x n cell)
%
%   See CLAUDE.md section 3 for the full contract.

    % --- canonical roots (order is load-bearing: 1=Dupi 2=OBEControl 3=EEGbreathing) ---
    % Sourced from labPaths so they follow the machine's lab-common drive.
    L = labPaths();
    ROOT_DUPI = L.rootDupi;
    ROOT_OBE  = L.rootOBE;
    ROOT_EEG  = L.rootEEG;

    tkey = taskKey(task);
    if isempty(tkey)
        error('applyParams:badTask', 'Unknown task "%s".', char(string(task)));
    end
    % breathingTasks_separate takes the dataType ephys condition rows; its
    % echem mode (caller key breathingTasks_separate_echem, tasks_261014 task
    % 6) is the same task on the dataType ephys_echem condition rows
    sepDT = 'ephys';
    if strcmp(tkey, 'sepEchem')
        tkey = 'sep';
        sepDT = 'ephys_echem';
    end

    if nargin < 3 || isempty(xlsxPath)
        if strcmp(tkey, 'adMed')
            xlsxPath = L.adMedXlsx;       % the task's own tracking sheet
        else
            xlsxPath = resolveDefaultXlsx();
        end
    end

    C = readSheetCached(xlsxPath);
    if strcmp(tkey, 'adMed')
        % the AD sheet holds only the columns this task uses: the master-only
        % parameter columns read below are appended blank (-> defaults)
        C = padMissingCols(C, {'spikeThresh', 'spikeWin', 'macroRemove', 'respThresh', ...
            'cuedBackBuff', 'adjWin', 'ttlRemoveIdx', 'ttlNote', 'isNewStd'});
    end

    % --- locate columns by trimmed header name (header row = 2) ---
    hdr = C(2, :);
    col = @(name) findCol(hdr, name);
    cSub  = col('Subject ID');
    cType = col('Type');
    cTask = col('Task');
    cRaw  = col('Raw Data Extracted');
    cPre  = col('datPre');
    cRsp  = col('rspIDX');
    cFlip = col('rspFlip');
    cHasE = col('hasEEG');
    cSpkC = col('spikeClean');
    cSpkT = col('spikeThresh');
    cSpkW = col('spikeWin');
    cMacR = col('macroRemove');
    cHasM = col('hasMacros');
    cRespT= col('respThresh');
    cBack = col('cuedBackBuff');
    cAdj  = col('adjWin');
    cBeat = col('beatSpec');
    cTtlR = col('ttlRemoveIdx');
    cTtlN = col('ttlNote');
    cNew  = col('isNewStd');
    cPS   = col('paramSource');
    cDT   = findColSoftLocal(hdr, 'dataType');

    % --- select rows: task matches AND raw extracted (not blank, not INCOMPLETE) ---
    data = C(3:end, :);
    nAll = size(data, 1);
    keep = false(nAll, 1);
    for r = 1:nAll
        keep(r) = isEligibleRow(data(r, :), tkey, cSub, cTask, cRaw, cDT, sepDT);
    end
    rows = data(keep, :);

    % --- group the condition rows per session (breathingTasks_separate only):
    %     a session = one Subject ID with >=1 eligible condition row; its file
    %     list = the condition Task values in sheet order (D12a) ---
    sepConditions = {};
    if strcmp(tkey, 'sep')
        ids = cellfun(@(v) strtrim(asChar(v)), rows(:, cSub), 'UniformOutput', false);
        [~, ia] = unique(lower(ids), 'stable');
        for u = 1:numel(ia)
            m = strcmpi(ids, ids{ia(u)});
            sepConditions{u} = cellfun(@(v) strtrim(asChar(v)), rows(m, cTask), ...
                                       'UniformOutput', false); %#ok<AGROW>
        end
    end

    % --- dedupe by sessID (case-insensitive, keep first), stable sheet order ---
    n = size(rows, 1);
    seen = {};
    keep2 = false(n, 1);
    for r = 1:n
        id = strtrim(asChar(rows{r, cSub}));
        if any(strcmpi(id, seen)), continue; end
        seen{end+1} = id; %#ok<AGROW>
        keep2(r) = true;
    end
    rows = rows(keep2, :);
    n = size(rows, 1);

    selStr = strtrim(asChar(sel));
    isModeA = any(strcmpi(selStr, {'makeOutDat', 'main'}));

    if isModeA
        % ------------------------- Mode A: cfg -------------------------
        cfg = struct();
        cfg.sessionIDs = cell(n, 1);
        cfg.root       = cell(n, 1);
        cfg.rspIDX     = zeros(1, n);
        cfg.rspFlip    = zeros(1, n);
        cfg.isNewStd   = false(1, n);
        cfg.paramSource= cell(1, n);

        datPre = {ROOT_DUPI, ROOT_OBE, ROOT_EEG};
        for r = 1:n
            id = strtrim(asChar(rows{r, cSub}));
            cfg.sessionIDs{r} = id;

            rt = rootForRow(rows{r, cPre}, rows{r, cType}, L);
            if strcmp(tkey, 'adMed') && isBlank(rows{r, cPre})
                rt = L.rootADmed;   % blank datPre: the study folder (Type EEG_meditation would map to EEGbreathing)
            end
            cfg.root{r} = rt;

            cfg.rspIDX(r)  = num_or(rows{r, cRsp}, 1);
            cfg.rspFlip(r) = num_or(rows{r, cFlip}, 1);
            cfg.isNewStd(r)= bool_or(rows{r, cNew}, false);
            ps = rows{r, cPS};
            if isBlank(ps), cfg.paramSource{r} = ''; else, cfg.paramSource{r} = asChar(ps); end
        end

        % build datPre with any extra distinct roots appended after the fixed 3
        for r = 1:n
            if ~anyEqI(cfg.root{r}, datPre)
                datPre{end+1} = cfg.root{r}; %#ok<AGROW>
            end
        end
        cfg.datPre = datPre;

        cfg.datPrei = zeros(1, n);
        for r = 1:n
            cfg.datPrei(r) = idxEqI(cfg.root{r}, datPre);
        end

        cfg.newIDs = cfg.sessionIDs(cfg.isNewStd);
        if strcmp(tkey, 'sep')
            cfg.conditions = sepConditions;   % per-session condition Task values
        end

        out = cfg;
        return;
    end

    % ------------------------- Mode B: P -------------------------
    ri = 0;
    for r = 1:n
        if strcmpi(selStr, strtrim(asChar(rows{r, cSub})))
            ri = r; break;
        end
    end
    if ri == 0
        error('applyParams:noSession', ...
            'No %s row with raw-extracted data for session "%s".', task, selStr);
    end

    typeStudy = studyOf(rows{ri, cType});

    P = struct();
    P.task        = taskCallerKey(task);
    P.type        = typeStr(typeStudy);
    P.fs_target   = 500;
    P.rspIDX      = num_or(rows{ri, cRsp}, 1);
    P.rspFlip     = num_or(rows{ri, cFlip}, 1);

    isO15 = strcmp(tkey, 'O15');
    P.hasEEG     = bool_or(rows{ri, cHasE}, ~isO15);   % default true except O15
    P.spikeClean = bool_or(rows{ri, cSpkC}, ~isO15);   % default true except O15
    P.spikeThresh= num_or(rows{ri, cSpkT}, 20);
    P.spikeWin   = num_or(rows{ri, cSpkW}, 11);
    P.macroRemove= list_or(rows{ri, cMacR}, []);
    P.paramSource= asChar(rows{ri, cPS});

    row = rows(ri, :);
    switch tkey
        case 'breathing'
            P = ecgParams(P, row, cHasM, cBeat, true, '1,0,gt,3');
            % P.ecgExcludeSec ([N x 2] seconds on the session's own timeline) +
            % P.ecgExcludeNote: stretches where the ECG is unreadable. shared/
            % processECG drops the beats inside them and leaves RRint NaN there;
            % shared/flagBadBreaths sets maxRR / minRR / RR_max_min to NaN for the
            % breaths overlapping them (goodBreath untouched); outDat.ecgExclude
            % records windows, criterion and affected breaths. Absent = off.
            % Per-session, explicit, measured with batch/ecgUnreadableWindows;
            % not a sheet column.
            switch selStr
                case '251110_Dupi_NMH_PC_2'
                    % 2026-10-14 reviewer (tasks_261014 task 7): leave the breaths
                    % whose ECG is unreadable out of HRV. batch/ecgUnreadableWindows
                    % (defaults) on the pre-exclusion final's beats (583 beats, median
                    % IBI 0.976 s, timeline 0-599.8 s, block start 299.7 s): (a) no
                    % readable regular beat pair (IBI within +-40 % of the median,
                    % successive IBIs within 0.3 s) for >= 4 s, readable islands
                    % < 20 s absorbed; (b) a burst of pseudo-beats (>= 4 consecutive
                    % intervals below the physiological floor 0.586 s, window =
                    % first..last beat of the run). Edges on the 0.1-s grid: a
                    % hole's edge is the neighbouring READABLE beat and the window
                    % stops just short of it (processECG's test is inclusive, so
                    % the beat and the readable interval next to the hole stay),
                    % a burst's edges are its own junk beats, rounded outward.
                    % [25.2 30.2] and [459.5 473.9] are EMG / movement bursts,
                    % [209.3 300.8] is the ~90-s heavy movement stretch (buildECGz
                    % blanks only ~240-270 s of it; the clean beats at 209.298 and
                    % 300.854 are kept, second verification: [209.2 300.9] dropped
                    % 300.854 and cost breath 61, whose ECG is clean, its HRV),
                    % [335.0 336.3] is a 1.3-s EMG burst (6 consecutive junk
                    % intervals; found in verification, too short for (a): the junk
                    % intervals 334.15->335.00 = 0.85 s and 336.29->337.40 = 1.11 s
                    % passed the interval filter and made breath 68's RR_max_min
                    % the session's largest).
                    P.ecgExcludeSec  = [25.2 30.2; 209.3 300.8; 335.0 336.3; 459.5 473.9];
                    P.ecgExcludeNote = ['no readable beat pair (IBI +-40% of median, successive diff <= 0.3 s) ' ...
                                        'for >= 4 s, islands < 20 s absorbed, or a burst of >= 4 consecutive sub-physiological ' ...
                                        'intervals; edges just short of the neighbouring readable beats; ' ...
                                        'batch/ecgUnreadableWindows, tasks_261014 task 7'];
            end

        case 'cue'
            P = sniffParams(P, row, cRespT, cBack, cAdj);
            % P.dropTrials: trial numbers (behDat.n) whose sniff rows
            % cueTaskPreProc_main removes from behDat (the trial is then
            % simply absent, like an undetected trial) and records in
            % outDat.droppedTrials (trial, reason). Default empty = nothing
            % dropped. Per-session, explicit; not a sheet column.
            % P.dropTrialsReason is the reason text stored for every dropped trial.
            P.dropTrials       = [];
            P.dropTrialsReason = '';
            switch selStr
                case '260917_OBE_NWU_RC_2'
                    % 2026-10-14 reviewer (tasks_261014 task 5): trial 23 has a
                    % small bump before the main sniff and the two cannot be
                    % separated reliably, so the trial's onset would be a guess
                    % -> drop it (59 trials remain)
                    P.dropTrials       = 23;
                    P.dropTrialsReason = 'reviewer 2026-10-14: small bump cannot be reliably separated from the main sniff';
            end

        case 'thresh'
            P = sniffParams(P, row, cRespT, cBack, cAdj);

        case 'O15'
            P = sniffParams(P, row, cRespT, cBack, cAdj);
            P.pd = struct('zthresh', -2, 'minPulseSamp', 200, ...
                          'maxPulseSamp', 1200, 'trialSplitSamp', 850);
            % P.ttl.protocol: how the experimenter marks free sniffs.
            %   'pressPulse' (default, every session unless listed below): one
            %     ~0.5 s pulse per sniff the experimenter saw; legacy z-score
            %     parse in detect_ttls_O15.
            %   'heldButton': the experimenter HOLDS the button while the odor
            %     bottle is under the nose; the inhales inside each button-down
            %     period are the free sniffs (detect_ttls_O15 -> parse_O15_events,
            %     O15PreProc_main -> heldButtonFreeSniffs_O15). Opt-in per session.
            P.ttl = struct( ...
                'expectedTrialCount', 30, ...
                'removeTrialMarksIdx', list_or(rows{ri, cTtlR}, []), ...
                'note', stringOrEmpty(rows{ri, cTtlN}), ...
                'protocol', 'pressPulse');
            switch selStr
                case '251030_Dupi_NMH_DB_3'
                    % tasks_261014 task 10 (2026-10-14): DB_3 was run with the
                    % held-button protocol (45 button-down periods, 0.16-22.1 s,
                    % 282 s held; 25 % of the event channel on the negative rail,
                    % so the legacy z-score threshold finds nothing). Replaces the
                    % 2026-10-12 case (zthresh -1, removeTrialMarksIdx 1,
                    % confirmAfterPress), which read every trial one event out of
                    % phase (its trial mark 1 was the real start of trial 1).
                    P.ttl.protocol = 'heldButton';
                case '260917_OBE_NWU_RC_2'
                    % tasks_261014 task 10 survey (2026-10-14): held-button too
                    % (51 holds, 0.9-24.7 s, 186 s held; 17 % of the event channel
                    % on the negative rail; the legacy parse errors). Trial 12's
                    % first press pulse is hidden in a hold (parse_O15_events
                    % infers it). Not yet processed; sheet parameters still blank.
                    P.ttl.protocol = 'heldButton';
            end

        case 'movie'
            % EmotionalMovieTask (Tasks_260824.md Task 7): breathing-type
            % processing + the legacy photodiode clip-pulse parameters
            % (ZelanoLabScripts getSessionParams_emotionTask).
            % EEG_breathing recordings have no macro channels, so the blank-
            % cell default is Type-aware.
            P = ecgParams(P, row, cHasM, cBeat, ~strcmp(typeStudy, 'eeg'), '1,0,gt,3.5');
            P.pd = struct('zthresh', -2, 'minPulseSamp', 350, ...
                          'maxPulseSamp', 2000, 'searchWin', 2000, ...
                          'numNeg', 3, 'numPos', 2, 'numNeu', 1, ...
                          'clipEndGapSec', 1.6);
            % Per-session ECG override (explicit switch on the ID, repo convention).
            % P.minIBI (s) is honoured by shared/processECG: beats closer than
            % this to the last kept beat are dropped before the RR series.
            switch selStr
                case '251009_OBE_NWU_CP_1'
                    % 2026-10-12 reviewer: over-detected beats (IBI 0.1-0.7 s, true
                    % rate ~66 bpm / IBI ~0.9 s) -> discard every IBI below 0.7 s
                    P.minIBI = 0.7;
            end

        case 'alt6'
            % alternating6Blocks (Tasks_260824.md Task 8): breathing-type
            % processing; blocks/ratings come from the Google-Drive behavioral
            % files (sniffLogicLog + mindfulBreathing), aligned in makeOutDat
            P = ecgParams(P, row, cHasM, cBeat, false, '1,0,gt,3.5');   % EEG_breathing: no macros

        case 'paced'
            % pacedBreathing (added 2026-09-15): breathing-type processing of a
            % single continuous EEG_breathing recording with NO event marks and
            % no behavioral file (~7 min audiobook/survey, ~90 min paced breathing
            % at a sweep of paces x depths, ~10 min focused breathing). Blocks are
            % INFERRED from the segmented breaths (inferBlocks_pacedBreathing)
            % with P.pacedOpts; there is no makeOutDat (raw loaded directly).
            P = ecgParams(P, row, cHasM, cBeat, false, '1,0,gt,3.5');   % EEG_breathing: no macros
            % block-inference options: empty = the documented defaults inside
            % inferBlocks_pacedBreathing (minBlockSec 60, gapSec 15, penaltyBIC 4,
            % merge tolerances ...). Override per session here if a review of
            % the blocks_inferred figure calls for it (explicit switch on ID).
            P.pacedOpts = struct();

        case 'sweep'
            % respiratorySweep (added 2026-10-08): breathing-type processing of
            % one continuous EEG_breathing recording (audiobook, 18 paced blocks
            % = 3 depth passes x 6 paces, then stopwatch-timed focused-breathing
            % / audiobook blocks). The Atlas recording has no event marks: the
            % session's LoadData script builds the event table from the
            % SniffLogic log(s) + the session notes (buildSweepTTL) and stores
            % it in the raw file; there is no makeOutDat (raw loaded directly).
            P = ecgParams(P, row, cHasM, cBeat, false, '1,0,gt,3.5');   % EEG_breathing: no macros
            % breath-merge rule (user 2026-10-15, every respiratorySweep session): an inhale is
            % not a new breath unless the exhale since the previous inhale is >= 20 % of that
            % inhale (shared/mergeIncompleteExhales, run after the locked engine)
            P.sweepOpts = struct('mergeExhaleFrac', 0.20);

        case 'sep'
            % breathingTasks_separate (Tasks_260824.md Task 9 / D12): the
            % session's condition recordings, processed per file then
            % concatenated. Params are stored identically on every in-scope
            % condition row (D12d); this reads the first one.
            sepBeatDefault = '1,0,gt,3.5';
            P = ecgParams(P, row, cHasM, cBeat, true, sepBeatDefault);
            % which condition recordings this session has (sheet order): the
            % session's rows that the Mode-A selection accepts for 'sep'
            allConds = {}; allRsp = []; allFlip = []; allBeat = {};
            for r2 = 1:size(data, 1)
                if ~isEligibleRow(data(r2, :), 'sep', cSub, cTask, cRaw, cDT, sepDT), continue; end
                if ~strcmpi(strtrim(asChar(data{r2, cSub})), selStr), continue; end
                allConds{end+1} = strtrim(asChar(data{r2, cTask})); %#ok<AGROW>
                allRsp(end+1)   = num_or(data{r2, cRsp}, 1);        %#ok<AGROW>
                allFlip(end+1)  = num_or(data{r2, cFlip}, 1);       %#ok<AGROW>
                bs = asChar(data{r2, cBeat});                       % blank -> the task default (as ecgParams)
                if isBlank(data{r2, cBeat}), bs = sepBeatDefault; end
                allBeat{end+1}  = bs;                               %#ok<AGROW>
            end
            % a duplicated condition row would load the same recording twice
            [uc, iu] = unique(lower(allConds), 'stable');
            if numel(uc) < numel(allConds)
                warning('applyParams:dupCondition', ...
                    '%s: duplicate condition rows collapsed (%d -> %d)', ...
                    selStr, numel(allConds), numel(uc));
            end
            P.conditions = allConds(iu);
            % per-condition respiration channel (2026-10-12, 260921_OBE_NWU_BW_2:
            % binaps in three recordings, spirometer for the mouth recording):
            % each condition row's own rspIDX / rspFlip, aligned with
            % P.conditions. P.rspIDX / P.rspFlip stay the first row's (as
            % before); the main only changes behaviour when these differ.
            P.condRspIDX  = allRsp(iu);
            P.condRspFlip = allFlip(iu);
            % per-condition ECG beatSpec (tasks_261014 task 9): each condition
            % row's own beatSpec (blank -> the task default), aligned with
            % P.conditions. P.beatSpec / P.getBeats stay the first row's; every
            % row carried the same spec before 2026-10-14, so the per-section
            % spec (tasks/breathingSeparate/sepSectionP) equals P.beatSpec there.
            P.condBeatSpec = allBeat(iu);
            if strcmp(sepDT, 'ephys_echem')
                % echem mode (tasks_261014 task 6): the ephys_echem condition
                % rows, saved by the main as <id>_breathingTasks_echem_separatepreproc.mat
                P.sepEchem = true;
            end
            % Optional per-condition settings, explicit per session (absent =
            % off). Each is aligned with P.conditions and set by condition
            % NAME (condSetting), so it holds in either mode:
            %   P.condTrimSec      [nCond x 2] keep [start end) s of that raw
            %                      recording (NaN = no trim at that end); applied
            %                      by assembleRaw_breathingTasks_separate
            %   P.condBlinkRemoval [nCond x 1] logical, false = that recording's
            %                      EEG stage skips blink removal (zero
            %                      blinkIndicator row inserted by concatSections)
            %   P.condRespSkip     [nCond x 1] logical, true = respiration not
            %                      recoverable there: no breath segmentation, no
            %                      breaths (outDat.respSkipped)
            %   P.condMinIBI       [nCond x 1] s, that recording's P.minIBI
            %                      (processECG beat pruning + RR floor; NaN = not
            %                      set there)
            switch selStr
                case '260625_OBE_NWU_HM_2'
                    % tasks_261014 task 8 (reviewer 2026-10-14): truncate the
                    % recording before the end-of-session noise. From 921.09 s
                    % into the raw sleep recording (raw sample 1842180 at 2 kHz,
                    % ~1893 s session time) to its end (1131.78 s) an abrupt
                    % ~1-2 Hz train of large pulses (macros +-1000 uV) covers the
                    % EEG + macro channels (ECG / respiration clean); no precursor
                    % in the 60 s before it. Measured on the raw file
                    % (E:\claudeWork\u1014\sepCode\hm2cut.m; figure
                    % guessReview_261014\HM_2\HM2_sleepTrim.png). Keep the sleep
                    % recording's first 916 s (5.09-s margin before the onset).
                    P.condTrimSec = condSetting(P.conditions, {'sleep'}, [0 916], [NaN NaN]);
                case '260831_OBE_NWU_CS_2'
                    % tasks_261014 task 9 (reviewer 2026-10-14): no blink removal
                    % in the sleep recording (the frontal blink-IC rule removed
                    % nothing there anyway; the reviewer wants none attempted)
                    P.condBlinkRemoval = condSetting(P.conditions, {'sleep'}, false, true);
                    % tasks_261014 task 9, sleep beats: with its ECG3 noise windows
                    % blanked (shared/buildECGz NOISYECG) the sleep spec recovers the
                    % beats, but 109 double detections (IBI 0.07-0.39 s, at artifact
                    % bursts in 25 of 130 10-s windows) filled every IBI-histogram bin
                    % below the mode, so processECG's acceptance window fell back to
                    % its 0.6-s default: 19 % of the sleep IBIs (219 ordinary ones of
                    % 0.5-0.6 s between normal neighbours) were left out of RRint,
                    % floored at 0.600 s. Pruning beats < 0.5 s after the last kept
                    % one (1961 beats, 90.3 bpm) gives the window [0.50 0.75] of the
                    % three awake sections (their beats are left as the reviewer
                    % accepted them) and keeps 99.1 % of the sleep IBIs (E:\claudeWork\
                    % u1014\sepRun\followup2.m / followup3.m).
                    P.condMinIBI = condSetting(P.conditions, {'sleep'}, 0.5, NaN);
            end

        case 'vip'
            % vipassana (added 2026-09-26): three single-session BrainVision
            % actiCHamp EEG_vipassana recordings (audiobook / anapana /
            % questionnaire / vipassana / questionnaire / metta /
            % questionnaire / audiobook protocol). Blocks are INFERRED from
            % an EEG activity-evidence index (inferBlocks_vipassana) with the
            % hand-pressed markers as hints only; there is no makeOutDat (raw
            % loaded directly, like O15 / pacedBreathing). Respiration may be
            % unusable in a given session (probeRespViability_vipassana).
            P = ecgParams(P, row, cHasM, cBeat, false, '1,0,gt,3.5');   % EEG_vipassana: no macros
            % no blink removal (2026-09-27): the participants' eyes were
            % closed throughout every period, so there are no blinks to
            % remove - an ICA "blink" component here would be alpha or
            % slow eye drift. Task-level flag honoured by
            % shared/preprocess_eeg (absent/true = blink removal runs, the
            % default for every other task); not a sheet column.
            P.blinkRemoval = false;
            % explicit per-session override switch on the ID (none needed
            % yet; add a case here if a review of blocks_inferred.jpg calls
            % for a P.vipOpts tweak - mirrors the P.pacedOpts pattern)
            switch selStr
            end
            P.vipOpts = struct();

        case 'adMed'
            % ADmeditation (added 2026-10-08): Adam's repeated ~60-min seated
            % meditation recordings on the EEG_breathing Atlas rig (Zelano_
            % EEGbreathing.cfg: 32-ch EEG, ECG1-3, rsp1-2, event), tracked in
            % their own sheet (labPaths().adMedXlsx). One continuous recording
            % per session, no behavioral file; the only marker is a button on
            % the event channel pressed at a "good" meditative state (a ~5-s
            % AC-coupled pulse: a step at the press, the opposite step at the
            % release; negative-first in the extracted raw - the detector takes
            % the polarity from the data, see detectButtonPresses_ADmeditation).
            % No makeOutDat (raw loaded directly, like pacedBreathing). Every
            % recording is trimmed: the first 3 min and the last 1 min are
            % dropped (user, 2026-10-08) before any processing.
            % Parameters (measured 2026-10-08 on all 14 non-empty recordings:
            % batch/probeMontage + the AD probes in E:\claudeWork\adMed1008):
            %  - rsp = CSC31 (rsp1; CSC32 = rsp2 is its inverted duplicate),
            %    inhale UP as recorded -> rspFlip +1, the lab's polarity for
            %    CSC31 on this rig (SniffLogic nasal pressure, inhale-positive;
            %    every 2026 EEG_breathing session, user-confirmed for these
            %    recordings 2026-10-08). NB an inhale-locked RR window test
            %    suggested -1: it is timing-sensitive (processECG stamps each
            %    RR interval at its FIRST beat) and is not a polarity test here;
            %  - ECG: lead 1 (CSC25) changes polarity between sessions, lead 3
            %    (CSC27) has a negative R wave in every session and gives the
            %    right rate in all 14 -> beatSpec '3,0,lt,-3.5';
            %  - eyes closed throughout (frontal blink rate ~0/min in every
            %    session) -> no blink removal (as vipassana): an ICA "blink"
            %    component would be eye drift / alpha, and the batch blink-IC
            %    selection errors when none is blink-like;
            %  - 32-ch EEG present (hasEEG), no macros (hasMacros / spikeClean
            %    false).
            % The recording setup is the same in every session, so these
            % blank-cell defaults serve them all (sheet cells override).
            P = ecgParams(P, row, cHasM, cBeat, false, '3,0,lt,-3.5');  % EEG rig: no macros
            P.spikeClean   = bool_or(row{cSpkC}, false);               % no macros to spike-clean
            P.blinkRemoval = false;                                    % task-level, not a sheet column
            % trimming + button-press detection options (see
            % detectButtonPresses_ADmeditation for the detector's defaults)
            P.adMedOpts = struct('trimStartSec', 180, 'trimEndSec', 60, 'press', struct());
            switch selStr     % explicit per-session overrides (none needed yet)
            end
    end

    out = P;
end

function C = padMissingCols(C, names)
% Append a blank column (header in row 2) for every name the header row lacks,
% so findCol below resolves it and every cell reads as blank -> its default.
    hdr = C(2, :);
    for i = 1:numel(names)
        if findColSoftLocal(hdr, names{i}) == 0
            C(:, end + 1) = {missing}; %#ok<AGROW>
            C{2, end} = names{i};
            hdr = C(2, :);
        end
    end
end

% ======================= helpers =======================

function tf = isEligibleRow(row, tkey, cSub, cTask, cRaw, cDT, sepDT)
% A sheet row feeds task tkey iff it has a Subject ID, its Task maps to tkey,
% and Raw Data Extracted is non-blank and not INCOMPLETE. breathingTasks_
% separate (D12a/D1) additionally takes ONLY condition rows of dataType sepDT:
% 'ephys' (the default; ephys_echem recordings are skipped) or, in its echem
% mode (tasks_261014 task 6), 'ephys_echem'. Shared by the Mode-A row
% selection and the per-session condition list of Mode B.
    if nargin < 7, sepDT = 'ephys'; end
    tf = false;
    if isBlank(row{cSub}), return; end                   % fully empty / no-ID rows
    if ~strcmp(canonTask(row{cTask}), tkey), return; end
    rawv = row{cRaw};
    if isBlank(rawv), return; end
    if strcmpi(strtrim(asChar(rawv)), 'INCOMPLETE'), return; end
    if strcmp(tkey, 'sep') && cDT > 0 && ~strcmpi(strtrim(asChar(row{cDT})), sepDT)
        return;
    end
    if strcmp(tkey, 'sep') && cDT == 0 && ~strcmp(sepDT, 'ephys')
        return;   % echem mode needs the dataType column to find its rows
    end
    tf = true;
end

function v = condSetting(conds, names, val, dflt)
% Per-condition setting for breathingTasks_separate, aligned with conds (=
% P.conditions, one row each): val for the conditions named in names (sheet
% Task values, case/whitespace-insensitive), dflt for the others.
    v = repmat(dflt, numel(conds), 1);
    for i = 1:numel(conds)
        if any(strcmpi(strtrim(conds{i}), strtrim(names))), v(i, :) = val; end
    end
end

function P = ecgParams(P, row, cHasM, cBeat, hasMacrosDefault, defaultSpec)
% breath-type tasks: hasMacros (blank cell -> the task's default) and the ECG
% beat-detection spec (blank cell -> the task's default spec) + P.getBeats
    P.hasMacros = bool_or(row{cHasM}, hasMacrosDefault);
    beatSpec    = asChar(row{cBeat});
    if isBlank(row{cBeat}), beatSpec = defaultSpec; end
    P.beatSpec  = beatSpec;
    P.getBeats  = @(ECGz, beatSep) detectBeats(ECGz, beatSep, beatSpec);
end

function P = sniffParams(P, row, cRespT, cBack, cAdj)
% sniff tasks (cue / thresh / O15): the macro stage always runs (the sheet's
% hasMacros cell is not read) + the sniff-detection windows
    P.hasMacros    = true;
    P.respThresh   = num_or(row{cRespT}, 500);
    P.cuedBackBuff = num_or(row{cBack}, 150);
    P.adjWin       = num_or(row{cAdj}, 500);
end

function p = resolveDefaultXlsx()
% Prefer the lab Admin master IF it already carries the parameter columns;
% otherwise fall back LOUDLY (warning applyParams:localFallback) to the
% repo-local param-enriched copy at the REPO ROOT (<repo>\dataTracking.xlsx,
% i.e. fullfile(labPaths().repo, ...)), so a stale local copy can never be
% used unnoticed. Only a master resolution is cached for the session: a
% fallback is re-resolved (and re-warned) on every call, so the master is
% picked up again as soon as it is reachable.
    persistent RESOLVED
    if ~isempty(RESOLVED), p = RESOLVED; return; end
    L = labPaths();
    adminP = L.adminXlsx;
    localP = fullfile(L.repo, 'dataTracking.xlsx');
    if hasParamCols(adminP)
        p = adminP;
        RESOLVED = p;
    elseif exist(localP, 'file') == 2
        warning('applyParams:localFallback', ...
            ['Lab master sheet not found (or missing param cols) at %s; ' ...
             'using repo-local copy %s - may be stale.'], adminP, localP);
        p = localP;
    else
        p = adminP;   % last resort -> readSheetCached errors informatively
    end
end

function tf = hasParamCols(p)
    tf = false;
    if exist(p, 'file') ~= 2, return; end
    try
        C = readcell(p, 'Sheet', 'Sheet1', 'Range', '2:2');   % header row only
        hdr = C(1, :);
        tf = any(cellfun(@(x) (ischar(x) || isstring(x)) && ...
                 strcmpi(strtrim(char(x)), 'datPre'), hdr));
    catch
        tf = false;
    end
end

function C = readSheetCached(xlsxPath)
    persistent CACHE
    d = dir(xlsxPath);
    if isempty(d)
        error('applyParams:noFile', 'Spreadsheet not found: %s', xlsxPath);
    end
    key = lower(strtrim(xlsxPath));
    if ~isempty(CACHE) && isfield(CACHE, 'key') && strcmp(CACHE.key, key) ...
            && CACHE.mtime == d.datenum
        C = CACHE.C;
        return;
    end
    C = readcell(xlsxPath, 'Sheet', 'Sheet1');
    CACHE = struct('key', key, 'mtime', d.datenum, 'C', {C});
end

function idx = findCol(hdr, name)
    idx = 0;
    for c = 1:numel(hdr)
        v = hdr{c};
        if ischar(v) || isstring(v)
            if strcmpi(strtrim(char(v)), name)
                idx = c; return;
            end
        end
    end
    if idx == 0
        error('applyParams:noColumn', 'Column "%s" not found in header row.', name);
    end
end

function idx = findColSoftLocal(hdr, name)
% like findCol but returns 0 instead of erroring when the column is absent
    idx = 0;
    for c = 1:numel(hdr)
        v = hdr{c};
        if (ischar(v) || isstring(v)) && strcmpi(strtrim(char(v)), name)
            idx = c; return;
        end
    end
end

function tf = isBlank(v)
    if isa(v, 'missing'), tf = true; return; end
    if isnumeric(v) && isempty(v), tf = true; return; end
    if isnumeric(v) && isscalar(v) && isnan(v), tf = true; return; end
    if (ischar(v) || isstring(v)) && strlength(strtrim(string(v))) == 0, tf = true; return; end
    if iscell(v) && isempty(v), tf = true; return; end
    tf = false;
end

function s = asChar(v)
    if isa(v, 'missing'), s = ''; return; end
    if ischar(v), s = v; return; end
    if isstring(v), s = char(v); return; end
    if isnumeric(v) || islogical(v)
        if isscalar(v), s = num2str(v); else, s = mat2str(v); end
        return;
    end
    s = char(string(v));
end

function s = stringOrEmpty(v)
    if isBlank(v), s = ""; else, s = string(asChar(v)); end
end

function x = num_or(v, d)
    if isBlank(v), x = d; return; end
    if isnumeric(v) || islogical(v), x = double(v); return; end
    x = str2double(asChar(v));
    if isnan(x), x = d; end
end

function tf = bool_or(v, d)
    if isBlank(v), tf = d; return; end
    if islogical(v), tf = logical(v); return; end
    if isnumeric(v), tf = (v ~= 0); return; end
    s = lower(strtrim(asChar(v)));
    tf = ismember(s, {'true', '1', 'yes'});
end

function r = list_or(v, d)
    if isBlank(v), r = d; return; end
    if isnumeric(v), r = double(v(:))'; return; end
    if islogical(v), r = double(v(:))'; return; end
    s = asChar(v);
    try
        r = str2num(['[' s ']']); %#ok<ST2NM>
    catch
        r = d; return;
    end
    if isempty(r), r = d; end
end

function k = canonTask(t)
    if isBlank(t), k = ''; return; end
    s = lower(asChar(t));
    s = s(~isspace(s));
    switch s
        case {'breathingtasks', 'wavebreathing', 'breathingtask'}
            k = 'breathing';
        case {'odorcuetask'}
            k = 'cue';
        case {'o15'}
            k = 'O15';
        case {'threshold'}
            k = 'thresh';
        case {'emotionalmovietask'}
            k = 'movie';
        case {'alternating6blocks'}
            k = 'alt6';
        case {'pacedbreathing'}
            k = 'paced';   % pacedBreathing (added 2026-09-15)
        case {'vipassana'}
            k = 'vip';     % vipassana (added 2026-09-26)
        case {'admeditation'}
            k = 'adMed';   % ADmeditation (added 2026-10-08; own sheet)
        case {'respiratorysweep'}
            k = 'sweep';   % respiratorySweep (added 2026-10-08)
        otherwise
            % breathingTasks_separate condition rows (D12a; OBE button/mouth
            % 2026-09-22; plain focusedBreathing_button and <cond>_run<N>
            % 2026-09-25) - the one condition list is config/sepConditionInfo
            if isempty(sepConditionInfo(asChar(t)))
                k = '';
            else
                k = 'sep';
            end
    end
end

function k = taskKey(task)
    % caller task key -> internal canon
    s = lower(asChar(task));
    s = s(~isspace(s));
    switch s
        case 'breathingtask',      k = 'breathing';
        case 'cuetask',            k = 'cue';
        case 'threshtask',         k = 'thresh';
        case 'o15',                k = 'O15';
        case 'emotionalmovietask', k = 'movie';
        case 'alternating6blocks', k = 'alt6';
        case 'pacedbreathing',     k = 'paced';
        case 'vipassana',          k = 'vip';
        case 'admeditation',       k = 'adMed';
        case 'respiratorysweep',   k = 'sweep';
        case {'breathingtasks_separate', 'breathingtasksseparate'}, k = 'sep';
        case 'breathingtasks_separate_echem', k = 'sepEchem';   % sep echem mode (tasks_261014 task 6)
        otherwise,                 k = '';
    end
end

function s = taskCallerKey(task)
    % normalize the caller's task spelling back to the canonical P.task value
    switch taskKey(task)
        case 'breathing', s = 'breathingTask';
        case 'cue',       s = 'cueTask';
        case 'thresh',    s = 'threshTask';
        case 'O15',       s = 'O15';
        case 'movie',     s = 'EmotionalMovieTask';
        case 'alt6',      s = 'alternating6Blocks';
        case 'paced',     s = 'pacedBreathing';
        case 'sep',       s = 'breathingTasks_separate';
        case 'sepEchem',  s = 'breathingTasks_separate';   % same task; P.sepEchem marks the mode
        case 'vip',       s = 'vipassana';
        case 'adMed',     s = 'ADmeditation';
        case 'sweep',     s = 'respiratorySweep';
        otherwise,        s = asChar(task);
    end
end

function st = studyOf(typeVal)
    s = lower(asChar(typeVal));
    if contains(s, 'dupi')
        st = 'dupi';
    elseif contains(s, 'eeg')
        st = 'eeg';
    else
        st = 'obe';   % obecontrol / obe... / anything else
    end
end

function t = typeStr(study)
    switch study
        case 'dupi', t = 'Dupi';
        case 'eeg',  t = 'EEG';
        otherwise,   t = 'OBE';
    end
end

function rt = rootForRow(preVal, typeVal, L)
    if ~isBlank(preVal)
        rt = rebaseLabCommon(strtrim(asChar(preVal)), L);
        return;
    end
    switch studyOf(typeVal)
        case 'dupi', rt = L.rootDupi;
        case 'eeg',  rt = L.rootEEG;
        otherwise,   rt = L.rootOBE;
    end
end

function rt = rebaseLabCommon(rt, L)
% The sheet stores absolute datPre paths under the canonical Lab_Common prefix.
% Swap that prefix for this machine's labCommon so the sheet stays portable.
% No-op when they match (every machine that maps the share to R:).
    canon = L.labCommonCanon;
    if numel(rt) >= numel(canon) && strncmpi(rt, canon, numel(canon))
        rt = [L.labCommon, rt(numel(canon)+1:end)];
    end
end

function tf = anyEqI(s, lst)
    tf = false;
    for i = 1:numel(lst)
        if strcmpi(strtrim(s), strtrim(lst{i})), tf = true; return; end
    end
end

function idx = idxEqI(s, lst)
    idx = 0;
    for i = 1:numel(lst)
        if strcmpi(strtrim(s), strtrim(lst{i})), idx = i; return; end
    end
end

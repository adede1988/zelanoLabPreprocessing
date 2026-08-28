
clear
% ---- machine paths (everything machine-specific comes from labPaths) ----
zlpHere=fileparts(mfilename('fullpath')); zlpRoot=zlpHere; while exist(fullfile(zlpRoot,'config','labPaths.m'),'file')~=2, zlpP=fileparts(zlpRoot); if strcmp(zlpP,zlpRoot), error('zelanoLabPreprocessing root not found'); end; zlpRoot=zlpP; end; addpath(genpath(zlpRoot));
L            = labPaths();
addpath(genpath(L.repo))
addpath(genpath(L.slowBreathing))
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
%  concatSections, build_behavior_table_breathingTasks_separate, writeSheetSep.
% =====================================================================

cfg        = applyParams('breathingTasks_separate','main');
sessionIDs = cfg.sessionIDs;

% D4: ALL Task 9 sessions are run-on-guess under the batch override
allowGuessRunEnv = strcmp(getenv('ZLP_ALLOW_GUESS_RUN'), '1');

success = ones(length(sessionIDs),1);
for s = 1:numel(sessionIDs)
    try
    disp(['working on ', sessionIDs{s}])
    S = struct;
    S.id   = sessionIDs{s};
    S.root = cfg.root{s};
    S.fig  = fullfile(figPath, S.id);

    P = applyParams('breathingTasks_separate', S.id);
    isGuess = ~strcmpi(strtrim(P.paramSource), 'curated');
    P.allowGuessRun = allowGuessRunEnv;        % D4: every Task 9 session
    P.figDir = S.fig;

    % --- done-check ---
    preDir = fullfile(S.root, S.id, 'preProc');
    fpath  = fullfile(preDir, [S.id '_breathingTasks_separatepreproc.mat']);
    if exist(fpath, 'file')
        chk = load(fpath); fn = fieldnames(chk); chk = chk.(fn{1});
        if isfield(chk, 'moreThan1') && isfield(chk, 'bmFeatures')
            disp(['Done with ' S.id ' ; ' num2str(s)])
            clear chk
            continue
        end
        clear chk
    end

    raws = assembleRaw_breathingTasks_separate(S, P);   % <-- TASK-SPECIFIC

    % --- per-condition-file shared core + breath/ECG stages (D12b) ---
    segs = struct('od', {}, 'label', {}, 'condition', {}, 'srcFile', {});
    for c = 1:numel(raws)
        % NB: cell-valued struct() args must be wrapped in {} or struct()
        % builds a struct ARRAY with one element per cell entry
        raw = struct('sessID', S.id, 'fs_raw', raws(c).fs_raw, ...
                     'data', raws(c).data, 'labels', {raws(c).labels}, ...
                     'beh', table());
        od = assembleOutDat(raw, S, P);
        if c == 1 && isGuess
            [od, P] = paramCheck(od, P);   % run-on-guess: saves QC figures
        end

        od = downsample_data(od, P.fs_target);
        if P.hasEEG, od = preprocess_eeg(od, EEGLOC, P); end
        if P.hasMacros, od = preprocess_macros(od, P); end

        isRsp  = cellfun(@(x) contains(x, 'rsp'), od.labels);
        rspDat = od.data(isRsp, :);
        rspDat = rspDat(P.rspIDX, :) .* P.rspFlip;
        [od.bmObj, od.bmFeatures] = segmentBreaths_zlp(rspDat, od.fs);

        hasECG = sum(cellfun(@(x) contains(x, 'ECG'), od.labels)) > 0;
        if hasECG && c == 1
            % viability probe: a systematically wrong beatSpec (bad lead /
            % polarity) must not kill the session - drop ECG for ALL sections
            % so the concatenated labels stay identical (strict D12b)
            try
                [ECGzP, sepP] = buildECGz(od);
                bpmP = numel(P.getBeats(ECGzP, sepP)) / (size(od.data, 2) / od.fs / 60);
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
        if hasECG && hasECGSession
            od = processECG(od, P);
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
        segs(c) = struct('od', od, 'label', raws(c).label, ...
                         'condition', raws(c).condition, 'srcFile', raws(c).srcFile);
        clear od raw
    end

    % --- concatenate (D12b) + behavior table (D12c) ---
    outDat = concatSections(segs, S, P);
    clear segs
    outDat.moreThan1 = 1;
    outDat.rspIDX  = P.rspIDX;
    outDat.rspFlip = P.rspFlip;

    outDat = build_behavior_table_breathingTasks_separate(outDat);

    hasRR = any(cellfun(@(x) contains(x, 'RRint'), outDat.labels));
    if hasRR
        if isGuess, P = paramCheckECG(outDat, P); end
        outDat = flagBadBreaths(outDat);
    else
        n = height(outDat.behDat);
        outDat.behDat.goodBreath = nan(n, 1);
        outDat.behDat.maxRR      = nan(n, 1);
        outDat.behDat.minRR      = nan(n, 1);
        outDat.behDat.RR_max_min = nan(n, 1);
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

    R = preprocess_respiration_wholetrace(outDat);
    plot_sniff_epochs(outDat, R);

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
        [outDat.sessID '_breathingTasks_separate_processedBreathing.csv']));

    if ~exist(preDir, 'dir'), mkdir(preDir); end
    save(fpath, 'outDat', '-v7.3');
    writeSheetSep(P, S.id, 'X');    % D12d: every in-scope condition row

    catch ME
        success(s) = 0;
        disp(['fail for ', sessionIDs{s}, ': ', ME.message]); disp(getReport(ME, 'extended', 'hyperlinks', 'off'))
    end
    close all
end

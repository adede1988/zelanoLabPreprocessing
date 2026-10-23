function [behDat, design] = loadBeh_multiRun_threshTask(sessID, behFiles)
%LOADBEH_MULTIRUN_THRESHTASK  TASK-SPECIFIC: behaviour of a multi-run PEA
%   threshold session (several result files, one per run).
%
%   [behDat, design] = loadBeh_multiRun_threshTask(sessID, behFiles)
%
%   The legacy threshold design (every session up to 2026-10) is ONE run of 45
%   trials, odor codes 1/2/3 = air/low/med, in ONE result file
%   <id>_run1_results.mat; threshPreProc_makeOutDat handles it unchanged.
%   From 261008_INR_NWU_SS_1 (recorded 2026-10-15) the task runs the 4-condition
%   design of the task code's make_cuelist_thr_3odors.m: air (olfactometer
%   line 1) and three PEA lines 2 / 3 / 12, 10 trials per condition per run,
%   2 runs of 40 trials (80 in all), each run saving its own
%   <id>_run<k>_results.mat. The code is the olfactometer line the trial opened
%   (threshold_task_new.m: OlfOpenLines(cuelist.odor(n))); line 12 is the
%   "High" (pure) PEA the session's note sheet added; lines 2 / 3 are the
%   legacy low / med.
%
%   Two task builds run this design; the build is read from the files, never
%   assumed:
%     standard  (threshold_task_new.m, 261008_INR_NWU_SS_1): files
%               <sessID>_run<k>_results.mat, outMat rows of 8 cells.
%     detection (threshold_task_det.m, from 261012_INR_NWU_VC_1, recorded
%               2026-10-19): a Yes/No "Was there an odor?" screen (2.5 s, mouse
%               click) before the intensity and pleasantness ratings. The task
%               appends _det to the ID, so the files are
%               <sessID>_det_run<k>_results.mat in a <sessID>_det folder, and
%               each outMat row has 10 cells: the 8 legacy ones + 9 detection
%               (the ANSWER, 1 = Yes / 0 = No / NaN = no click; the screen side,
%               counterbalanced by cuelist.trialtype, is already decoded) and
%               10 detection_rt (s from the detection-screen onset, NaN = no
%               click). Each .mat must have its .txt twin (written trial by
%               trial by the task) whose header names the 10 columns and whose
%               trial / odor / detection columns equal the .mat.
%
%   behFiles: dir() entries of the session's result .mat files (>= 2). They
%   must be exactly <sessID>_run1_results.mat ... <sessID>_runK_results.mat,
%   or exactly <sessID>_det_run1..K_results.mat in a <sessID>_det folder (a
%   re-saved duplicate such as ..._results_<clock>.mat, a missing run, a mixed
%   set or a foreign file is an error - strict, like the single-file loader).
%
%   behDat: one row per trial in recording order (run 1 then run 2 ...), the
%   legacy 8 columns (trialNum = trial number WITHIN its run) + run, and in the
%   detection build + detect, detectRT. Empty pleasantness / intensity cells
%   (no rating click) are filled with 735 in the standard build, like the
%   legacy loader; in the detection build they are NaN (listed in
%   design.emptyRatings).
%   design: struct documenting the design (stored as outDat.threshDesign); the
%   detection build adds build, resultID, taskCode, behColumns, behTxtFiles,
%   emptyRatingFill, emptyRatings, nYesPerCode, nNoClick.

    if numel(behFiles) < 2
        error('PEA loader: multi-run design needs >= 2 result files for %s (got %d).', ...
            sessID, numel(behFiles));
    end
    names = {behFiles.name};
    runPat = @(pref) ['^' regexptranslate('escape', pref) '_run(\d+)_results\.mat$'];
    tokStd = regexp(names, runPat(sessID), 'tokens', 'once');
    tokDet = regexp(names, runPat([sessID '_det']), 'tokens', 'once');
    if ~any(cellfun(@isempty, tokStd))
        isDet = false;
        tok = tokStd;
    elseif ~any(cellfun(@isempty, tokDet))
        isDet = true;
        tok = tokDet;
    else
        msg = sprintf(['PEA loader: %d behavioral .mat for %s, but they are not exactly a run set ' ...
            '<id>_run<k>_results.mat or <id>_det_run<k>_results.mat:\n'], numel(names), sessID);
        for k = 1:numel(names), msg = [msg sprintf('  - %s\n', names{k})]; end %#ok<AGROW>
        error('%s', msg);
    end
    runNum = cellfun(@(t) str2double(t{1}), tok);
    [runNum, ord] = sort(runNum);
    behFiles = behFiles(ord);
    if ~isequal(runNum(:)', 1:numel(runNum))
        error('PEA loader: result files of %s are runs [%s], expected 1..%d.', ...
            sessID, num2str(runNum(:)'), numel(runNum));
    end

    varNames = {'trialNum', 'Odor', 'RT', 'pleasantness', 'intensity', 'ITI', ...
                'Trial_StartTime', 'Trial_EndTime'};
    if isDet
        % the detection build's folder is <sessID>_det (threshold_task_det.m:
        % resultsFolder = results\<subID>_det)
        [~, fld] = cellfun(@fileparts, {behFiles.folder}, 'UniformOutput', false);
        if ~all(strcmp(fld, [sessID '_det']))
            error('PEA loader: detection-build result files of %s must be in a %s_det folder (found %s).', ...
                sessID, sessID, strjoin(unique(fld), ', '));
        end
        varNames = [varNames, {'detect', 'detectRT'}];
        txtHeader = {'trial', 'odor', 'resptime', 'pleasantness_x', 'intensity_x', 'iti', ...
                     'trial_start', 'response_end', 'detection', 'detection_rt'};
        txtFiles = cell(numel(behFiles), 1);
        emptyRun = zeros(0, 1); emptyTrial = zeros(0, 1); emptyCol = strings(0, 1);
    end
    behDat = table;
    nPerRun = zeros(1, numel(behFiles));
    for r = 1:numel(behFiles)
        f = fullfile(behFiles(r).folder, behFiles(r).name);
        L = load(f);
        if ~isfield(L, 'outMat')
            error('PEA loader: behavioral file for %s does not contain outMat: %s', sessID, f);
        end
        B = cat(1, L.outMat{:});
        if size(B, 2) ~= numel(varNames)
            error('PEA loader: outMat of %s has %d columns, expected %d.', f, size(B, 2), numel(varNames));
        end
        if isDet
            % no rating click = empty cell: NaN (never a scale position), and
            % listed; no detection click is stored as NaN by the task (an
            % empty cell would be read the same way)
            for c = [4 5]
                e = cellfun(@isempty, B(:, c));
                B(e, c) = {NaN};
                emptyRun   = [emptyRun; repmat(r, sum(e), 1)]; %#ok<AGROW>
                emptyTrial = [emptyTrial; find(e)]; %#ok<AGROW>
                emptyCol   = [emptyCol; repmat(string(varNames{c}), sum(e), 1)]; %#ok<AGROW>
            end
            for c = [9 10]
                B(cellfun(@isempty, B(:, c)), c) = {NaN};
            end
        else
            % universal fill for missing pleasantness / intensity: 735 (as legacy)
            for c = [4 5]
                e = cellfun(@isempty, B(:, c));
                B(e, c) = {735};
            end
        end
        T = array2table(cell2mat(B), 'VariableNames', varNames);
        if isDet
            checkDetection(T, f, txtHeader);
            txtFiles{r} = regexprep(f, '\.mat$', '.txt');
        end
        T.run = repmat(r, height(T), 1);
        if isDet
            T = movevars(T, 'run', 'Before', 'detect');   % legacy 8 + run, then the detection pair
        end
        nPerRun(r) = height(T);
        behDat = [behDat; T]; %#ok<AGROW>
    end

    % the design's odor codes (olfactometer lines) and readable labels
    odorCodes  = [1 2 3 12];
    odorLabels = {'air', 'low', 'med', 'high'};
    bad = ~ismember(behDat.Odor, odorCodes);
    if any(bad)
        error('PEA loader: %s has odor codes [%s] outside the multi-run design [%s].', ...
            sessID, num2str(unique(behDat.Odor(bad))'), num2str(odorCodes));
    end

    design = struct;
    design.name       = 'multiRun';
    design.nRuns      = numel(behFiles);
    design.trialsPerRun = nPerRun;
    design.nTrials    = height(behDat);
    design.odorCodes  = odorCodes;
    design.odorLabels = odorLabels;
    design.nPerCode   = arrayfun(@(c) sum(behDat.Odor == c), odorCodes);
    design.behFiles   = arrayfun(@(d) fullfile(d.folder, d.name), behFiles(:), 'UniformOutput', false);
    design.note = ['4-condition PEA threshold (make_cuelist_thr_3odors): air = olfactometer line 1, ' ...
        'PEA lines 2 / 3 / 12 = low / med / high (12 = pure PEA, added 2026-10-15), ' ...
        '10 trials per condition per run; odor = the line code; behDat.n indexes TTL rows across runs'];
    if isDet
        design.build       = 'detection';
        design.resultID    = [sessID '_det'];
        design.taskCode    = 'threshold_task_det.m';
        design.behColumns  = txtHeader;
        design.behTxtFiles = txtFiles;
        design.emptyRatingFill = NaN;
        design.emptyRatings = table(emptyRun, emptyTrial, emptyCol, ...
            'VariableNames', {'run', 'trialNum', 'column'});
        design.nYesPerCode = arrayfun(@(c) sum(behDat.Odor == c & behDat.detect == 1), odorCodes);
        design.nNoClick    = sum(isnan(behDat.detect));
        design.note = [design.note '; detection build (threshold_task_det.m): a Yes/No "Was there ' ...
            'an odor?" screen (2.5 s) before the intensity and pleasantness ratings, behDat.detect = ' ...
            'the answer (1 Yes / 0 No / NaN no click), behDat.detectRT = s from the screen onset; ' ...
            'an empty rating (no click) is NaN, not 735'];
    end
end

function checkDetection(T, f, txtHeader)
% the detection pair as the task wrote it: answers 0 / 1 / NaN, an RT exactly
% when there is an answer, and the .txt twin naming the 10 columns with the
% same trial / odor / detection values
    if any(~ismember(T.detect(~isnan(T.detect)), [0 1]))
        error('PEA loader: %s has detection values outside {0, 1, NaN}.', f);
    end
    if ~isequal(isnan(T.detect), isnan(T.detectRT)) || any(T.detectRT(~isnan(T.detectRT)) < 0)
        error('PEA loader: %s has detection RTs that do not match the answers (NaN pattern or < 0).', f);
    end
    txt = regexprep(f, '\.mat$', '.txt');
    if exist(txt, 'file') ~= 2
        error('PEA loader: detection-build result %s has no .txt twin (%s) naming its columns.', f, txt);
    end
    fid = fopen(txt, 'r');
    hdr = fgetl(fid);
    fclose(fid);
    if ~ischar(hdr) || ~isequal(strtrim(strsplit(strtrim(hdr), '\t')), txtHeader)
        error('PEA loader: %s header is not the detection build''s [%s].', txt, strjoin(txtHeader, ' '));
    end
    X = readmatrix(txt, 'FileType', 'text', 'Delimiter', '\t', 'NumHeaderLines', 1);
    if size(X, 1) ~= height(T) || size(X, 2) ~= numel(txtHeader) || ...
            ~isequal(X(:, 1), T.trialNum) || ~isequal(X(:, 2), T.Odor) || ~isequaln(X(:, 9), T.detect)
        error('PEA loader: %s does not match %s (rows / trial / odor / detection).', txt, f);
    end
end

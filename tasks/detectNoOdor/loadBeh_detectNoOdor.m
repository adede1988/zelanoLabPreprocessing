function [beh, src] = loadBeh_detectNoOdor(behRoot, sessID)
%LOADBEH_DETECTNOODOR  TASK-SPECIFIC: the detectNoOdor result file -> trial table (strict).
%
%   [beh, src] = loadBeh_detectNoOdor(behRoot, sessID)
%
%   behRoot : labPaths().behOdorDetection (OBE_task_backup\tasks\odor_detection)
%   sessID  : the session ID (results\results_OBE_Odor_detection\<sessID>\)
%
%   The task (src\Main_detectiontask_f.m, the "fake" odor-detection task: the
%   olfactometer only ever opens the air line) saves at the end of the run
%   <sessID>_run<k>_cuelist_results[_<stamp>_<n>].mat with outMat (one cell per
%   trial), datalabel {n odor response response_str trl_start end_trl
%   duration_trial} and note = 'no odor'. An aborted attempt leaves only a .txt.
%   Exactly one .mat is required (strict).
%
%   Response coding (resolved from the task code, 2026-10-15):
%     response      the KEY pressed: 1 = left button (key code 30), 2 = right
%                   button (key code 31); [] when no key within 13 s
%     response_str  the ANSWER: the Yes/No label of that key on this trial's
%                   screen. The screen layout is counterbalanced by the cuelist's
%                   trialtype (1: Yes left / No right, 2: No left / Yes right),
%                   which the result file does not store -> read from the
%                   participant's cuelist (participants\<id>_cuelist\<id>_run<k>_cuelist.mat)
%   response_str is AUTHORITATIVE for Yes/No; response is the button side, so
%   response == 1 is "Yes" on trialtype-1 trials and "No" on trialtype-2 trials.
%   Every answered trial is checked: response_str must equal the label of
%   `response` under its trialtype (error otherwise).
%     odor          the cuelist's planned condition code (1 / 2; in the real
%                   detection task 2 opens odor line 12) - NEVER delivered here
%
%   beh (one row per trial): n, odor, response (NaN = no answer), response_str
%   ('' = no answer), trl_start, end_trl, duration_trial (s, task-laptop clock),
%   trialType. src: file names, note.

    resDir = fullfile(behRoot, 'results', 'results_OBE_Odor_detection', sessID);
    d = dir(fullfile(resDir, '*.mat'));
    d = d(~[d.isdir]);
    if numel(d) ~= 1
        error('loadBeh_detectNoOdor:nFiles', ...
            'expected exactly 1 result .mat in %s, found %d', resDir, numel(d));
    end
    resFile = fullfile(d.folder, d.name);
    r = load(resFile);
    if ~isfield(r, 'outMat') || ~isfield(r, 'datalabel')
        error('loadBeh_detectNoOdor:format', '%s lacks outMat / datalabel', resFile);
    end
    % only the fake task (Main_detectiontask_f) writes note = 'no odor'; the
    % odor-delivering Main_detectiontask writes no note -> not this task
    if ~isfield(r, 'note') || ~strcmpi(strtrim(char(string(r.note))), 'no odor')
        error('loadBeh_detectNoOdor:notNoOdor', ...
            '%s has no note ''no odor'': not a detect-no-odor run (Main_detectiontask_f)', resFile);
    end
    expLab = {'n', 'odor', 'response', 'response_str', 'trl_start', 'end_trl', 'duration_trial'};
    if ~isequal(cellstr(r.datalabel(:))', expLab)
        error('loadBeh_detectNoOdor:labels', 'unexpected datalabel in %s: %s', resFile, strjoin(cellstr(r.datalabel), ' '));
    end

    nT = numel(r.outMat);
    n = nan(nT, 1); odor = nan(nT, 1); resp = nan(nT, 1); rstr = repmat({''}, nT, 1);
    t0 = nan(nT, 1); t1 = nan(nT, 1); dur = nan(nT, 1);
    for k = 1:nT
        row = r.outMat{k};
        if numel(row) == 7                     % answered trial
            resp(k) = row{3}; rstr{k} = char(row{4}); v = row([1 2 5 6 7]);
        elseif numel(row) == 6 && isempty(row{3})
            % no key: detection_str{[]} is an empty list, so the row is one short
            v = row([1 2 4 5 6]);
        else
            error('loadBeh_detectNoOdor:row', 'trial %d: unexpected outMat row (%d values)', k, numel(row));
        end
        n(k) = v{1}; odor(k) = v{2}; t0(k) = v{3}; t1(k) = v{4}; dur(k) = v{5};
    end
    if ~isequal(n, (1:nT)')
        error('loadBeh_detectNoOdor:order', 'trial numbers are not 1..%d', nT);
    end

    % ---- the cuelist (screen layout) of this run ----
    [~, base] = fileparts(d.name);
    tok = regexp(base, '^(.*_cuelist)_results', 'tokens', 'once');
    if isempty(tok)
        error('loadBeh_detectNoOdor:cuelistName', 'cannot derive the cuelist name from %s', d.name);
    end
    cueFile = fullfile(behRoot, 'participants', [sessID '_cuelist'], [tok{1} '.mat']);
    if ~exist(cueFile, 'file')
        error('loadBeh_detectNoOdor:noCuelist', 'cuelist not found: %s', cueFile);
    end
    c = load(cueFile);
    c = c.cuelist;
    if numel(c.trialtype) < nT || ~isequal(c.odor(1:nT), odor)
        error('loadBeh_detectNoOdor:cuelistMismatch', 'cuelist %s does not match the result file''s odor column', cueFile);
    end
    trialType = c.trialtype(1:nT);
    trialType = trialType(:);
    labs = {{'Yes', 'No'}, {'No', 'Yes'}};      % detection_str per trialtype (task code)
    for k = 1:nT
        if isnan(resp(k)), continue; end
        if ~strcmp(labs{trialType(k)}{resp(k)}, rstr{k})
            error('loadBeh_detectNoOdor:respCoding', ...
                'trial %d: response %d on trialtype %d should read %s, file says %s', ...
                k, resp(k), trialType(k), labs{trialType(k)}{resp(k)}, rstr{k});
        end
    end

    beh = table(n, odor, resp, rstr, t0, t1, dur, trialType, 'VariableNames', ...
        {'n', 'odor', 'response', 'response_str', 'trl_start', 'end_trl', 'duration_trial', 'trialType'});
    src = struct('resultFile', resFile, 'cuelistFile', cueFile, 'note', char(string(r.note)), ...
        'responseCoding', ['response = key pressed (1 left, 2 right); response_str = Yes/No under the ' ...
                           'cuelist trialtype layout (1: Yes left, 2: Yes right) - authoritative; ' ...
                           'odor = planned cuelist code, never delivered (air line only)']);
end

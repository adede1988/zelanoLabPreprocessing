function T = fr_buildManifest(outDir, opts)
%FR_BUILDMANIFEST  The manifest of the full EEG rerun: every current EEG final of the lab, with everything the driver needs.
%
%   T = fr_buildManifest(outDir, opts)         (run on the lab desktop with R: mapped; READ-ONLY on data and sheet)
%
%   Writes outDir\manifest.csv (the work list, in run order), outDir\manifest_excluded.csv (finals left out and why) and
%   outDir\manifest_notes.txt.  Nothing on R: is written.
%
%   How it works.  A FRESH listing of the preProc folders of the four lab roots (Dupi, OBEControl, OBEControl\anosmics,
%   AllStudyData\EEGbreathing) finds every file that is a pipeline final (<id>_<suffix>.mat, the save-line names).  Each is
%   described by the job1020 EEG-survey reader (eiMeta / h5meta: top-level fields, EEGCleaningInfo, blink IC - no data load).
%   A file that is unchanged since the survey (same path, size and date as in opts.inventoryCsv) takes its description from
%   that inventory; a new or changed file (VC_1, the G2 reruns, ...) is read again.  The sheet is read through applyParams
%   (the same session list and paramSource the mains use).
%
%   Exclusions (the user's instructions, 2026-10-22): vipassana, ADmeditation, every 260917_OBE_NWU_RC_2 final,
%   261019_INR_NWU_DD_1, finals without an EEG stage that are NOT breath-type (a cue / thresh / O15 final without an EEG stage has
%   nothing to rerun), stale duplicates, unreadable finals (kept in the manifest DISABLED so the decision is visible).
%   Breath-type finals WITHOUT an EEG stage (user, 2026-10-23: 1 breathingTask, 6 breathingTasks_separate, 1 EmotionalMovieTask)
%   ARE in the manifest (hasEEG = 0): they gain the current engine + the breath merge rule and keep their respiration (carry);
%   their main runs with the sheet's hasEEG = 0, so no EEG stage.  A sheet that says hasEEG = 1 for such a final disables the row
%   (the rerun would add an EEG stage the final never had).  Three of them (the shortest of each kind) join the validation set.
%
%   Manifest columns: order, set (validation | sniff | breath), key, task, sessID, root, finalPath, finalBytes, finalDate,
%   durMin, hasEEG, paramSource, makeOutDat, main, envFlags, timeoutMin, enabled, gateAfter, carry, ttlProtocol, note
%   Order: the validation set, then cueTask / threshTask / O15 / detectNoOdor / cueTask3 (shortest first), then the breath-type
%   tasks (breathingTask, breathingTasks_separate, EmotionalMovieTask, alternating6Blocks, pacedBreathing, respiratorySweep,
%   airPuff; shortest first within a task).
%
%   opts (all optional): inventoryCsv (default E:\claudeWork\job1020\eeg\inventory.csv), harnessDir (E:\claudeWork\job1020\eeg\harness),
%   validationExtra (cellstr of 'task|sessID' to add to the validation set), noCache (true = read every final again)
if nargin < 1 || isempty(outDir), outDir = 'E:\claudeWork\rerun1022'; end
if nargin < 2, opts = struct(); end
opts = defaults(opts);
if ~exist(outDir, 'dir'), mkdir(outDir); end
t00 = tic;
L = labPaths(); lc = L.labCommon;
if exist('eiMeta', 'file') ~= 2, addpath(opts.harnessDir); end
assert(exist('eiMeta', 'file') == 2, 'fr_buildManifest:noEiMeta', 'eiMeta.m / h5meta.m (job1020 EEG survey) not found in %s', opts.harnessDir);
fprintf('fr_buildManifest %s  labCommon %s  repo %s\n', datestr(now), lc, L.repo);

% ---- task table: the final-name suffix of each save line, the entry points ---------------------------------------
TK = taskTable(L.repo);

% ---- 1. fresh listing ---------------------------------------------------------------------------------------------
roots = {L.rootDupi, L.rootOBE, fullfile(L.rootOBE, 'anosmics'), L.rootEEG};
files = {}; fdate = []; fbytes = [];
for r = 1:numel(roots)
    rt = roots{r};
    if ~exist(rt, 'dir'), fprintf('missing root %s\n', rt); continue; end
    cand = [dir(fullfile(rt, 'preProc', '*.mat')); dir(fullfile(rt, '*', 'preProc', '*.mat')); dir(fullfile(rt, '*', '*', 'preProc', '*.mat'))];
    for k = 1:numel(cand)
        if cand(k).isdir, continue; end
        f = fullfile(cand(k).folder, cand(k).name);
        if any(strcmpi(files, f)), continue; end
        files{end+1} = f; fdate(end+1) = cand(k).datenum; fbytes(end+1) = cand(k).bytes; %#ok<AGROW>
    end
end
rx = ['^(?<id>.+?)_(?<suf>' strjoin({TK.suffixRx}, '|') ')\.mat$'];
fprintf('%d .mat files in the preProc folders of %d roots\n', numel(files), numel(roots));

% ---- 2. inventory cache ----------------------------------------------------------------------------------------
cache = containers.Map('KeyType', 'char', 'ValueType', 'any');
frCache = fullfile(outDir, 'inventory_fr.csv');     % written by the previous run of this function (newer than the survey's)
for cf = {opts.inventoryCsv, frCache}
    if ~opts.noCache && isfile(cf{1})
        I = readtable(cf{1}, 'TextType', 'string', 'VariableNamingRule', 'preserve');
        for i = 1:height(I), cache(lower(char(I.file(i)))) = I(i, :); end
        fprintf('inventory cache: %d rows from %s\n', height(I), cf{1});
    end
end
inv = {};     % the described finals, saved as the cache of the next run

% ---- 3. the sheet as the mains see it --------------------------------------------------------------------------
SH = struct();
for k = 1:numel(TK)
    key = TK(k).sheetKey;
    if isfield(SH, matlab.lang.makeValidName(key)), continue, end
    try
        cfg = applyParams(key, 'main');
        s = struct('ids', {cfg.sessionIDs}, 'roots', {cfg.root}, 'ps', {cellfun(@(x) char(string(x)), cfg.paramSource, 'UniformOutput', false)});
        SH.(matlab.lang.makeValidName(key)) = s;
        fprintf('sheet %-32s %3d sessions\n', key, numel(cfg.sessionIDs));
    catch ME
        SH.(matlab.lang.makeValidName(key)) = struct('ids', {{}}, 'roots', {{}}, 'ps', {{}});
        fprintf('sheet %-32s applyParams failed: %s\n', key, ME.message);
    end
end

% ---- 4. one record per final -----------------------------------------------------------------------------------
recs = {}; nRead = 0; nCached = 0;
for k = 1:numel(files)
    f = files{k};
    [~, nm, ex] = fileparts(f);
    tok = regexp([nm ex], rx, 'names', 'once', 'ignorecase');
    if isempty(tok), continue; end
    ti = find(cellfun(@(s) ~isempty(regexpi(tok.suf, ['^' s '$'], 'once')), {TK.suffixRx}), 1);
    r = struct('file', f, 'fileId', tok.id, 'folderId', folderOf(f), 'task', TK(ti).task, 'datenum', fdate(k), 'bytes', fbytes(k));
    c = [];
    if isKey(cache, lower(f))
        c = cache(lower(f));
        same = abs(double(c.fileDatenum) - fdate(k)) < 1/1440 && abs(double(c.fileMB) * 1e6 - fbytes(k)) < 2e3;
        if ~same, c = []; end
    end
    if ~isempty(c)
        nCached = nCached + 1;
        r.src = 'inventory'; r.err = cs(c.err); r.ok = isempty(strtrim(r.err));
        r.sessID = cs(c.sessID); r.hasEEG = double(c.hasEEG); r.durMin = double(c.durMin); r.moreThan1 = double(c.moreThan1);
        r.ciMode = cs(c.ciMode); r.nSections = double(c.nSections);
        if isnan(r.nSections), r.nSections = 1; end
        if startsWith(r.task, 'breathingTasks_separate') && ~r.hasEEG && r.ok, r.nSections = sepSections(f); end
    else
        nRead = nRead + 1;
        t0 = tic; M = eiMeta(f, true);
        r.src = 'read'; r.ok = M.ok; r.err = strtrim([M.err ' ' M.rowErr ' ' M.metaErr]);
        r.sessID = M.sessID; r.hasEEG = double(~isnan(M.nBad) || ~isnan(M.EEGCleaning));
        r.durMin = M.nSamp / max(M.fs, 1) / 60; r.moreThan1 = M.moreThan1; r.ciMode = M.ciMode; r.nSections = 1;
        if startsWith(r.task, 'breathingTasks_separate') && r.ok, r.nSections = sepSections(f); end
        fprintf('  read %-30s %-26s %.1f s\n', r.fileId, r.task, toc(t0));
    end
    recs{end+1} = r; %#ok<AGROW>
    inv(end+1, :) = {f, r.sessID, r.task, r.hasEEG, r.durMin, r.moreThan1, r.ciMode, r.nSections, r.err, fdate(k), fbytes(k) / 1e6}; %#ok<AGROW>
end
fprintf('%d finals: %d from the inventory cache, %d (re)read\n', numel(recs), nCached, nRead);
if ~isempty(inv)
    Tinv = cell2table(inv, 'VariableNames', {'file', 'sessID', 'taskKind', 'hasEEG', 'durMin', 'moreThan1', 'ciMode', 'nSections', 'err', 'fileDatenum', 'fileMB'});
    writetable(Tinv, frCache);
end
% finals of the two study tasks that another agent handles (listed from the survey inventory; not read again)
studyExcl = {};
if isfile(opts.inventoryCsv)
    I0 = readtable(opts.inventoryCsv, 'TextType', 'string', 'VariableNamingRule', 'preserve');
    for i = 1:height(I0)
        tk0 = cs(I0.taskKind(i));
        if any(strcmp(tk0, {'vipassana', 'ADmeditation'})) && double(I0.isCurrent(i)) == 1
            studyExcl(end+1, :) = {tk0, cs(I0.fileId(i)), cs(I0.file(i)), 'study handled by another agent (user)'}; %#ok<AGROW>
        end
    end
end

% ---- 5. decide: manifest row or exclusion ----------------------------------------------------------------------
rows = {}; excl = {};
breathTasks = {'breathingTask', 'breathingTasks_separate', 'breathingTasks_separate_echem', 'EmotionalMovieTask', 'alternating6Blocks', ...
    'pacedBreathing', 'respiratorySweep', 'airPuff'};     % a breath-type final without an EEG stage still gains the engine + the merge rule
for k = 1:numel(recs)
    r = recs{k};
    tk = TK(strcmp({TK.task}, r.task));
    why = '';                       % non-empty = excluded
    note = '';                      % reasons for enabled = 0
    sid = r.fileId;
    if contains(sid, '260917_OBE_NWU_RC_2') || contains(r.folderId, '260917_OBE_NWU_RC_2'), why = 'RC_2: left alone (user)';
    elseif contains(sid, '261019_INR_NWU_DD_1'), why = 'DD_1: never processed, left alone (user)';
    elseif ~r.hasEEG && r.ok && ~any(strcmp(r.task, breathTasks)), why = 'no EEG stage in this final: nothing to rerun';
    end
    if ~isempty(why), excl(end+1, :) = {r.task, sid, r.file, why}; continue, end %#ok<AGROW>
    % sheet row (exact id; then the folder id)
    s = SH.(matlab.lang.makeValidName(tk.sheetKey));
    ix = find(strcmp(s.ids, sid), 1);
    if isempty(ix), ix = find(strcmpi(s.ids, sid), 1); end
    sheetId = ''; ps = ''; sroot = '';
    if ~isempty(ix), sheetId = s.ids{ix}; ps = s.ps{ix}; sroot = s.roots{ix}; end
    if isempty(sheetId)
        note = addNote(note, 'no sheet row with this id: the main would not process it');
    else
        want = [sheetId tk.suffix];
        [~, nm, ex] = fileparts(r.file);
        if ~strcmpi([nm ex], want), note = addNote(note, ['the main writes ' want ' (file name differs)']); end
    end
    if ~r.ok, note = addNote(note, ['unreadable final (' strtrim(r.err) '): the carry needs the old final']); end
    if r.ok && r.hasEEG == 0 && ~isempty(sheetId)
        % no EEG stage in the final: the sheet must say so too, or the rerun would add an EEG stage the final never had
        try
            Pn = applyParams(tk.sheetKey, sheetId);
            if isfield(Pn, 'hasEEG') && logical(Pn.hasEEG), note = addNote(note, 'the final has no EEG stage but the sheet says hasEEG = 1: the rerun would add one'); end
        catch ME
            note = addNote(note, ['applyParams failed for a final without an EEG stage: ' ME.message]);
        end
    end
    % stale duplicate: another final of the same task in the same session folder whose id equals the folder name
    if ~strcmp(r.fileId, r.folderId)
        sib = cellfun(@(q) strcmp(q.task, r.task) && strcmp(q.folderId, r.folderId) && strcmp(q.fileId, q.folderId), recs);
        if any(sib), excl(end+1, :) = {r.task, sid, r.file, 'stale duplicate: the folder holds the current final with the folder id'}; continue, end %#ok<AGROW>
    end
    env = {['ZLP_MAIN_ONLY=' sheetOr(sheetId, sid)]};       % the id filters (one id per run; the carry needs it)
    if ~isempty(tk.makeOutDat), env = [env {['ZLP_MAKEOUTDAT_ONLY=' sheetOr(sheetId, sid)]}]; end %#ok<AGROW>
    if ~strcmpi(strtrim(ps), 'curated'), env = [env {'ZLP_ALLOW_GUESS_RUN=1', 'ZLP_ALLOW_GUESS_RUN_ALL=1'}]; end %#ok<AGROW>
    if strcmp(r.task, 'breathingTasks_separate_echem'), env = [env {'ZLP_SEP_ECHEM=1'}]; end %#ok<AGROW>
    ttlProt = '';
    row = struct('order', NaN, 'set', '', 'key', [r.task '__' sid], 'task', r.task, 'sessID', sheetOr(sheetId, sid), 'root', fileparts(fileparts(fileparts(r.file))), ...
        'finalPath', r.file, 'finalBytes', r.bytes, 'finalDate', datestr(r.datenum, 'yyyy-mm-dd HH:MM'), 'durMin', round(r.durMin, 2), ...
        'hasEEG', r.hasEEG, 'paramSource', ps, 'makeOutDat', tk.makeOutDat, 'main', tk.main, 'envFlags', strjoin(env, ';'), ...
        'timeoutMin', 0, 'enabled', double(isempty(note)), 'gateAfter', 0, 'carry', 1, 'ttlProtocol', ttlProt, 'note', note);
    row.timeoutMin = min(360, round(30 + r.durMin + 12 * (r.nSections - 1)));
    if strcmp(r.task, 'O15') && ~isempty(sheetId), row.ttlProtocol = o15Protocol(sheetId); end
    row.nSections = r.nSections; row.ciMode = r.ciMode;
    rows{end+1} = row; %#ok<AGROW>
end
M = struct2table([rows{:}], 'AsArray', true);

% ---- 6. order: validation set, then the sniff tasks, then the breath tasks ------------------------------------------
grp = {'cueTask', 'threshTask', 'O15', 'detectNoOdor', 'cueTask3', 'breathingTask', 'breathingTasks_separate', 'breathingTasks_separate_echem', ...
    'EmotionalMovieTask', 'alternating6Blocks', 'pacedBreathing', 'respiratorySweep', 'airPuff'};
sniff = {'cueTask', 'threshTask', 'O15', 'detectNoOdor', 'cueTask3'};
M.set = repmat({'breath'}, height(M), 1);
M.set(ismember(M.task, sniff)) = {'sniff'};
vkeys = validationKeys(M, opts);
M.set(ismember(M.key, vkeys)) = {'validation'};
gi = cellfun(@(t) find(strcmp(grp, t), 1), M.task);
setRank = cellfun(@(s) find(strcmp({'validation', 'sniff', 'breath'}, s), 1), M.set);
% validation: in the order of vkeys (so the quick ones come first) ; the rest: group, then shortest first
vOrd = zeros(height(M), 1);
for i = 1:height(M), q = find(strcmp(vkeys, M.key{i}), 1); if ~isempty(q), vOrd(i) = q; end, end
[~, ord] = sortrows([setRank, vOrd, gi, M.durMin, M.finalBytes]);
M = M(ord, :);
M.order = (1:height(M))';
lastV = find(strcmp(M.set, 'validation'), 1, 'last');
if ~isempty(lastV), M.gateAfter(lastV) = 1; end

% ---- 7. write ----------------------------------------------------------------------------------------------
cols = {'order', 'set', 'key', 'task', 'sessID', 'root', 'finalPath', 'finalBytes', 'finalDate', 'durMin', 'hasEEG', 'paramSource', ...
    'makeOutDat', 'main', 'envFlags', 'timeoutMin', 'enabled', 'gateAfter', 'carry', 'ttlProtocol', 'note'};
T = M(:, cols);
if isfile(fullfile(outDir, 'manifest.csv'))     % the previous manifest stays (state files are keyed by row key, so a rebuild is safe, but keep the old one)
    copyfile(fullfile(outDir, 'manifest.csv'), fullfile(outDir, ['manifest_prev_' datestr(now, 'yyyymmdd_HHMMSS') '.csv']));
end
writetable(T, fullfile(outDir, 'manifest.csv'));
excl = [excl; studyExcl; {'(none)', '261019_INR_NWU_DD_1', '', 'DD_1: never processed, no final exists, left alone (user)'}];
E = cell2table(excl, 'VariableNames', {'task', 'sessID', 'finalPath', 'reason'});
writetable(E, fullfile(outDir, 'manifest_excluded.csv'));
% notes
fid = fopen(fullfile(outDir, 'manifest_notes.txt'), 'w');
fprintf(fid, 'fr_buildManifest %s\nrepo %s\n%d finals in scope: %d enabled, %d disabled; %d excluded\n\n', datestr(now), L.repo, height(T), sum(T.enabled == 1), sum(T.enabled == 0), size(excl, 1));
fprintf(fid, 'by set:\n');
for s = {'validation', 'sniff', 'breath'}, fprintf(fid, '  %-11s %d\n', s{1}, sum(strcmp(T.set, s{1}))); end
fprintf(fid, '\nby task (enabled / disabled / sum of file GB):\n');
for t = grp
    m = strcmp(T.task, t{1}); if ~any(m), continue, end
    fprintf(fid, '  %-32s %3d / %2d / %6.1f GB\n', t{1}, sum(T.enabled(m) == 1), sum(T.enabled(m) == 0), sum(T.finalBytes(m)) / 1e9);
end
fprintf(fid, '\nbreath-type finals WITHOUT an EEG stage (engine + merge rule + carry only): %d\n', sum(T.hasEEG == 0));
for i = find(T.hasEEG == 0)', fprintf(fid, '  %s (%s)\n', T.key{i}, T.set{i}); end
fprintf(fid, '\nexcluded:\n');
[ur, ~, ui] = unique(E.reason);
for i = 1:numel(ur), fprintf(fid, '  %3d  %s\n', sum(ui == i), ur{i}); end
fprintf(fid, '\ndisabled rows (a decision is needed):\n');
for i = find(T.enabled == 0)', fprintf(fid, '  %s: %s\n', T.key{i}, T.note{i}); end
fclose(fid);
fprintf('manifest: %d rows (%d enabled, %d disabled), %d excluded; total %.1f GB; %.0f s\nMANIFEST DONE\n', height(T), sum(T.enabled == 1), sum(T.enabled == 0), size(excl, 1), sum(T.finalBytes) / 1e9, toc(t00));
end

% =====================================================================================================
function o = defaults(o)
d = struct('inventoryCsv', 'E:\claudeWork\job1020\eeg\inventory.csv', 'harnessDir', 'E:\claudeWork\job1020\eeg\harness', ...
    'validationExtra', {{}}, 'noCache', false);
f = fieldnames(d);
for i = 1:numel(f), if ~isfield(o, f{i}), o.(f{i}) = d.(f{i}); end, end
end

function s = cs(x)
% char of a table cell (a missing string becomes '')
if ismissing(x), s = ''; else, s = char(x); end
end
function s = addNote(s, t)
if isempty(s), s = t; else, s = [s '; ' t]; end
end
function x = sheetOr(a, b)
if isempty(a), x = b; else, x = a; end
end
function id = folderOf(f)
[~, id] = fileparts(fileparts(fileparts(f)));
end

function TK = taskTable(repo)
% task | final-name suffix (regex of the save line, case-insensitive) | the exact suffix the main writes | entry points
d = {
 'breathingTask',                 'breathingPreproc',                         '_breathingPreproc.mat',                 'pipelines/makeOutDat/breathingTask_makeOutDat.m',      'pipelines/breathingTaskPreProc_main.m',             'breathingTask'
 'cueTask',                       'cueTaskPreproc',                           '_cueTaskPreproc.mat',                   'pipelines/makeOutDat/cueTask_makeOutDat.m',            'pipelines/cueTaskPreProc_main.m',                   'cueTask'
 'cueTask3',                      'cueTask3preproc',                          '_cueTask3preproc.mat',                  'pipelines/makeOutDat/cueTask3_makeOutDat.m',           'pipelines/cueTask3PreProc_main.m',                  'cueTask3'
 'threshTask',                    'PEA_threshold_preproc',                    '_PEA_threshold_preproc.mat',            'pipelines/makeOutDat/threshPreProc_makeOutDat.m',      'pipelines/threshPreProc_main.m',                    'threshTask'
 'O15',                           'O15preproc',                               '_O15preproc.mat',                       '',                                                     'pipelines/O15PreProc_main.m',                       'O15'
 'EmotionalMovieTask',            'EmotionalMovieTaskpreproc',                '_EmotionalMovieTaskpreproc.mat',        'pipelines/makeOutDat/emotionalMovieTask_makeOutDat.m', 'pipelines/emotionalMovieTaskPreProc_main.m',        'EmotionalMovieTask'
 'alternating6Blocks',            'alternating6Blockspreproc',                '_alternating6Blockspreproc.mat',        'pipelines/makeOutDat/alternating6Blocks_makeOutDat.m', 'pipelines/alternating6BlocksPreProc_main.m',        'alternating6Blocks'
 'pacedBreathing',                'pacedBreathingpreproc',                    '_pacedBreathingpreproc.mat',            '',                                                     'pipelines/pacedBreathingPreProc_main.m',            'pacedBreathing'
 'breathingTasks_separate',       'breathingTasks_separatepreproc',           '_breathingTasks_separatepreproc.mat',   '',                                                     'pipelines/breathingTasks_separatePreProc_main.m',   'breathingTasks_separate'
 'breathingTasks_separate_echem', 'breathingTasks_echem_separatepreproc',     '_breathingTasks_echem_separatepreproc.mat', '',                                                 'pipelines/breathingTasks_separatePreProc_main.m',   'breathingTasks_separate_echem'
 'detectNoOdor',                  'detectNoOdorpreproc',                      '_detectNoOdorpreproc.mat',              'pipelines/makeOutDat/detectNoOdor_makeOutDat.m',       'pipelines/detectNoOdorPreProc_main.m',              'detectNoOdor'
 'airPuff',                       'airPuffpreproc',                           '_airPuffpreproc.mat',                   '',                                                     'pipelines/airPuffPreProc_main.m',                   'airPuff'
 'respiratorySweep',              'respiratorySweeppreproc',                  '_respiratorySweeppreproc.mat',          '',                                                     'pipelines/respiratorySweepPreProc_main.m',          'respiratorySweep'
 'vipassana',                     'vipassanapreproc',                         '_vipassanapreproc.mat',                 '',                                                     'pipelines/vipassanaPreProc_main.m',                 'vipassana'
 'ADmeditation',                  'ADmeditationpreproc',                      '_ADmeditationpreproc.mat',              '',                                                     'pipelines/ADmeditationPreProc_main.m',              'ADmeditation'};
% the rerun covers every task but the two excluded study tasks (their finals are not listed in the roots scanned here)
d = d(~ismember(d(:, 1), {'vipassana', 'ADmeditation'}), :);
TK = struct('task', d(:, 1), 'suffixRx', d(:, 2), 'suffix', d(:, 3), 'makeOutDat', d(:, 4), 'main', d(:, 5), 'sheetKey', d(:, 6));
for i = 1:numel(TK)
    if ~isempty(TK(i).makeOutDat), assert(isfile(fullfile(repo, TK(i).makeOutDat)), 'missing %s', TK(i).makeOutDat); end
    assert(isfile(fullfile(repo, TK(i).main)), 'missing %s', TK(i).main);
end
end

function n = sepSections(f)
% number of sections of a sep final (reads the sections table; the whole final is loaded - sep finals are small)
n = 1;
try
    s = load(f, 'outDat'); n = max(1, height(s.outDat.sections));
catch
    try, s = load(f); fn = fieldnames(s); n = max(1, height(s.(fn{1}).sections)); catch, end
end
end

function p = o15Protocol(id)
% the sheet's ttlProtocol of an O15 row, through applyParams (informational column of the manifest)
p = '';
try
    P = applyParams('O15', id);
    if isfield(P, 'ttl') && isfield(P.ttl, 'protocol'), p = char(string(P.ttl.protocol)); end
catch
end
end

function keys = validationKeys(M, opts)
% the validation set: the shortest enabled final of every task + the special cases (ids that exercise a rule of the rerun)
keys = {};
en = M.enabled == 1;
shortest = @(task) pickShortest(M, en & M.hasEEG == 1 & strcmp(M.task, task));      % the EEG finals; the ones without an EEG stage are added below
quick = {'airPuff', 'detectNoOdor', 'cueTask3', 'threshTask', 'cueTask', 'O15', 'EmotionalMovieTask', 'alternating6Blocks', 'respiratorySweep', 'pacedBreathing'};
for t = quick, k = shortest(t{1}); if ~isempty(k), keys{end+1} = k; end, end %#ok<AGROW>
special = {
 'O15|251030_Dupi_NMH_DB_3'                       % held-button protocol, already fixed once
 'O15|250929_Dupi_NMH_GH_2'                       % explicit confirmRule case + post-hoc fields to carry
 'breathingTask|251027_Dupi_NMH_DL_1'             % DL_1: no blink removal (G2f)
 'breathingTasks_separate|251027_Dupi_NMH_DL_1'   % sleep-only sep session (G2d zero blinkIndicator row)
 'breathingTasks_separate|260921_OBE_NWU_BW_2'    % mixed respiration channels, rspSelected
 'breathingTasks_separate_echem|260921_OBE_NWU_BW_2'
 'breathingTask|251111_EEG_NWU_VW'                % reconstructedBlocks to carry
 'threshTask|261008_INR_NWU_SS_1'                 % multi-run thresh design
 'breathingTasks_separate|261008_INR_NWU_SS_1'};  % 4 sections, already fixed
for i = 1:numel(opts.validationExtra), special{end+1, 1} = opts.validationExtra{i}; end %#ok<AGROW>
for i = 1:numel(special)
    p = strsplit(special{i}, '|');
    k = [p{1} '__' p{2}];
    if any(strcmp(M.key, k) & en) && ~any(strcmp(keys, k)), keys{end+1} = k; end %#ok<AGROW>
end
% breath-type finals WITHOUT an EEG stage (the main runs with hasEEG = 0; no scratch run covered this path): the shortest of each kind
noEEG = en & M.hasEEG == 0;
for t = {'breathingTask', 'EmotionalMovieTask', 'breathingTasks_separate'}
    k = pickShortest(M, noEEG & strcmp(M.task, t{1}));
    if ~isempty(k) && ~any(strcmp(keys, k)), keys{end+1} = k; end %#ok<AGROW>
end
end
function k = pickShortest(M, mask)
k = '';
if ~any(mask), return, end
idx = find(mask); [~, j] = min(M.durMin(idx)); k = M.key{idx(j)};
end

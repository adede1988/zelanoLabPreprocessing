% task1_inventory — build inventory_260824.csv from the sheet AND the disk
%
% Tasks_260824.md Task 1 steps 3-5. Runs on the lab desktop with R: mapped.
% Reads the Admin master through labPaths (run task1_fixSP2 first so the SP_2
% IDs are already corrected), checks every in-scope row against the disk, and
% writes:
%   E:\reprocBackup_260824\inventory_260824.csv   (the batch driver copies this
%       into the repo root and commits it - this script does not touch the repo)
%   E:\reprocBackup_260824\inventory_260824.mat   (table, consumed by task1_syncPreProcX)
% and prints the run-report summaries to stdout.
%
% Definitions (work order §0):
%   preprocessed = final loads and has moreThan1 (+ bmObj & baseEmotion for the
%                  breathing task group)  [field presence read via h5info -- all
%                  finals are -v7.3/HDF5; anything unreadable is flagged]
%   current      = preprocessed AND behDat carries manOnset. Detected via the
%                  file mtime (>= 2026-07-01 = written by the July rerun), then
%                  spot-verified by fully loading one stale and one current final.

OUT_DIR = 'E:\reprocBackup_260824';
CUR_CUTOFF = datetime(2026, 7, 1);

% known sheet-ID -> session-folder-name mismatches (CLAUDE.md §7, intentional)
FOLDER_ALIAS = containers.Map( ...
    {'250904_obe_nwu_ti_1'}, ...
    {'250904_OBE_NWU_TI'});

L = labPaths();
xlsxPath = L.adminXlsx;
fprintf('task1_inventory: sheet = %s\n', xlsxPath);
C   = readcell(xlsxPath, 'Sheet', 'Sheet1');
hdr = C(2, :);

cSub  = findColX(hdr, 'Subject ID');
cDate = findColX(hdr, 'Test Date');
cType = findColX(hdr, 'Type');
cDT   = findColX(hdr, 'dataType');
cTask = findColX(hdr, 'Task');
cSrv  = findColX(hdr, 'Data On Server');
cRaw  = findColX(hdr, 'Raw Data Extracted');
cPreX = findColX(hdr, 'Data Preprocessed');
cDatP = findColX(hdr, 'datPre');
cPS   = findColX(hdr, 'paramSource');

% ---------------- pass 1: collect in-scope-task rows from the sheet ----------------
N = size(C, 1);
rowsOut = {};   % accumulate row structs
for r = 3:N
    id = cs(C{r, cSub});
    if isempty(id), continue; end
    tRaw = cs(C{r, cTask});
    [grp, cond] = groupOf(tRaw);
    if isempty(grp), continue; end

    R = struct();
    R.excelRow   = r;
    R.SubjectID  = strtrim(id);
    R.TestDate   = dateStr(C{r, cDate});
    R.Type       = cs(C{r, cType});
    R.dataType   = lower(strtrim(cs(C{r, cDT})));
    R.Task       = strtrim(tRaw);
    R.taskGroup  = grp;
    R.condition  = cond;
    R.DataOnServer = cs(C{r, cSrv});
    R.RawExtracted = cs(C{r, cRaw});
    R.DataPreprocessed = cs(C{r, cPreX});
    R.datPre     = cs(C{r, cDatP});
    R.paramSource = lower(strtrim(cs(C{r, cPS})));
    R.inScope    = isempty(R.dataType) || strcmp(R.dataType, 'ephys');
    R.eligible   = ~isempty(strtrim(R.RawExtracted)) && ...
                   ~strcmpi(strtrim(R.RawExtracted), 'INCOMPLETE');
    rowsOut{end+1} = R; %#ok<AGROW>
end
n = numel(rowsOut);
fprintf('in-scope-task rows found: %d\n', n);

% ---------------- pass 2: disk checks ----------------
% cache per session folder so repeated sessions cost one dir() each
dirCache = containers.Map('KeyType', 'char', 'ValueType', 'any');
finCache = containers.Map('KeyType', 'char', 'ValueType', 'any');

for i = 1:n
    R = rowsOut{i};
    root = rootFor(R.datPre, R.Type, L);
    % prefer the sheet-ID folder; fall back to a known alias (TI vs TI_1 quirk)
    folderName = R.SubjectID;
    if ~isfolder(fullfile(root, folderName)) && isKey(FOLDER_ALIAS, lower(R.SubjectID))
        alias = FOLDER_ALIAS(lower(R.SubjectID));
        if isfolder(fullfile(root, alias)), folderName = alias; end
    end
    sessDir = fullfile(root, folderName);
    R.root = root;
    R.folderName = folderName;

    key = lower(sessDir);
    if isKey(dirCache, key)
        DC = dirCache(key);
    else
        DC = struct();
        DC.folder = isfolder(sessDir);
        DC.rawDirs = {};
        if DC.folder
            d = dir(fullfile(sessDir, 'raw'));
            for k = 1:numel(d)
                if d(k).isdir && strncmpi(d(k).name, 'raw_', 4)
                    DC.rawDirs{end+1} = d(k).name;
                end
            end
        end
        dirCache(key) = DC;
    end
    R.folderOnDisk = DC.folder;
    R.rawDirs = strjoin(DC.rawDirs, ';');
    R.rawOnDisk = rawPresent(R.taskGroup, R.condition, DC.rawDirs, sessDir);

    % ---- preProc file (intermediate and final share one name on Windows) ----
    % filename normally carries the sheet ID; for aliased folders try both spellings
    fpath = fullfile(sessDir, 'preProc', finalName(R.taskGroup, R.SubjectID));
    if isempty(dir(fpath)) && ~strcmp(folderName, R.SubjectID)
        alt = fullfile(sessDir, 'preProc', finalName(R.taskGroup, folderName));
        if ~isempty(dir(alt)), fpath = alt; end
    end
    fkey = lower(fpath);
    if isKey(finCache, fkey)
        FC = finCache(fkey);
    else
        FC = struct('present', false, 'mtime', NaT, 'sizeMB', 0, ...
                    'topVar', '', 'fields', {{}}, 'fmt', '', 'path', fpath);
        fd = dir(fpath);
        if ~isempty(fd)
            FC.present = true;
            FC.mtime   = datetime(fd(1).datenum, 'ConvertFrom', 'datenum');
            FC.sizeMB  = fd(1).bytes / 1e6;
            [FC.topVar, FC.fields, FC.fmt] = finalFields(fpath);
        end
        finCache(fkey) = FC;
    end
    R.finalPath = FC.path;
    R.preProcFilePresent = FC.present;
    R.finalMtime = FC.mtime;
    R.finalSizeMB = round(FC.sizeMB);
    R.finalTopVar = FC.topVar;
    R.finalFmt = FC.fmt;

    needsBm   = ismember(R.taskGroup, {'breathing'});
    needsBase = ismember(R.taskGroup, {'breathing'});
    hasF = @(f) any(strcmp(FC.fields, f));
    % validity is only actionable when the file's structure could be read:
    % absent -> definitively invalid; readable -> decided by fields; an
    % unreadable present file stays UNKNOWN so the sheet sync leaves it alone.
    R.finalKnown = ~FC.present || ismember(FC.fmt, {'v7.3', 'v7-loaded'});
    R.finalValid = FC.present && R.finalKnown && hasF('moreThan1') && ...
                   (~needsBm || hasF('bmObj')) && (~needsBase || hasF('baseEmotion'));
    R.finalCurrent = R.finalValid && ~isnat(FC.mtime) && FC.mtime >= CUR_CUTOFF;
    R.intermediateOnly = FC.present && R.finalKnown && ~R.finalValid;

    R.plannedAction = plannedFor(R);
    rowsOut{i} = R;
end

T = struct2table([rowsOut{:}]);

% ---------------- spot-verify the mtime->manOnset proxy ----------------
% load up to 2 stale and 2 current finals in full and check behDat.manOnset;
% a failed load does NOT count toward the quota.
fprintf('\n--- manOnset spot check (proxy: mtime >= %s) ---\n', string(CUR_CUTOFF));
spotNeed = [2 2];   % [stale current]
for i = 1:height(T)
    if ~T.finalValid(i), continue; end
    isCur = T.finalCurrent(i);
    slot = 1 + isCur;
    if spotNeed(slot) <= 0, continue; end
    fpath = T.finalPath{i};
    fprintf('loading (%s, %d MB): %s ...\n', tern(isCur, 'current', 'stale'), T.finalSizeMB(i), fpath);
    try
        S = load(fpath); fn = fieldnames(S); od = S.(fn{1}); clear S
        if isfield(od, 'behDat') && istable(od.behDat)
            hasMan = ismember('manOnset', od.behDat.Properties.VariableNames);
        else
            hasMan = false;
        end
        fprintf('  behDat manOnset present: %d  (proxy says %d)\n', hasMan, isCur);
        if hasMan ~= isCur
            warning('task1:proxyMismatch', 'manOnset proxy mismatch for %s', fpath);
        end
        spotNeed(slot) = spotNeed(slot) - 1;
    catch ME
        fprintf('  spot-check load FAILED (does not count): %s\n', ME.message);
    end
    clear od
    if all(spotNeed <= 0), break; end
end
if any(spotNeed > 0)
    fprintf('note: spot-check quota not fully met (remaining [stale current] = %s)\n', mat2str(spotNeed));
end

% ---------------- write outputs ----------------
if ~isfolder(OUT_DIR), mkdir(OUT_DIR); end
csvPath = fullfile(OUT_DIR, 'inventory_260824.csv');
writetable(T, csvPath);
save(fullfile(OUT_DIR, 'inventory_260824.mat'), 'T');
fprintf('\nwrote %s (%d rows)\n', csvPath, height(T));

% ---------------- summaries for the run report ----------------
fprintf('\n===== SUMMARY =====\n');
fprintf('dataType distribution (in-scope task groups):\n');
ud = unique(T.dataType);
for u = 1:numel(ud)
    fprintf('  %-14s %d\n', ['"' ud{u} '"'], sum(strcmp(T.dataType, ud{u})));
end

inS = T.inScope;
fprintf('\nrows out of scope (dataType echem/ephys_echem): %d\n', sum(~inS));
for i = find(~inS)'
    fprintf('  row %d  %-28s %-22s dataType=%s\n', T.excelRow(i), T.SubjectID{i}, T.Task{i}, T.dataType{i});
end

fprintf('\n-- per task group (in-scope rows) --\n');
ug = unique(T.taskGroup);
for u = 1:numel(ug)
    m = strcmp(T.taskGroup, ug{u}) & inS;
    fprintf('%s: %d rows | folder %d | raw %d | preProcFile %d | valid %d | current %d\n', ...
        ug{u}, sum(m), sum(T.folderOnDisk(m)), sum(T.rawOnDisk(m)), ...
        sum(T.preProcFilePresent(m)), sum(T.finalValid(m)), sum(T.finalCurrent(m)));
end

fprintf('\n-- on server (sheet) but session folder missing on disk --\n');
for i = 1:height(T)
    if inS(i) && ~isempty(strtrim(T.DataOnServer{i})) && ...
       ~strcmpi(strtrim(T.DataOnServer{i}), 'INCOMPLETE') && ~T.folderOnDisk(i)
        fprintf('  row %d  %-28s %-22s\n', T.excelRow(i), T.SubjectID{i}, T.Task{i});
    end
end

fprintf('\n-- sheet says extracted but no raw found on disk --\n');
for i = 1:height(T)
    if inS(i) && T.eligible(i) && ~T.rawOnDisk(i)
        fprintf('  row %d  %-28s %-22s rawDirs=[%s]\n', T.excelRow(i), T.SubjectID{i}, T.Task{i}, T.rawDirs{i});
    end
end

fprintf('\n-- raw on disk but sheet does not say extracted --\n');
for i = 1:height(T)
    if inS(i) && ~T.eligible(i) && T.rawOnDisk(i)
        fprintf('  row %d  %-28s %-22s\n', T.excelRow(i), T.SubjectID{i}, T.Task{i});
    end
end

fprintf('\n-- Data Preprocessed drift (sheet flag vs disk validity; in-scope rows) --\n');
for i = 1:height(T)
    if ~inS(i), continue; end
    flag = ~isempty(strtrim(T.DataPreprocessed{i}));
    if flag ~= T.finalValid(i)
        fprintf('  row %d  %-28s %-22s sheet=%s disk-valid=%d\n', T.excelRow(i), ...
            T.SubjectID{i}, T.Task{i}, tern(flag, 'X', 'blank'), T.finalValid(i));
    end
end

fprintf('\n-- preprocessed but STALE (valid final, no manOnset era) --\n');
for i = 1:height(T)
    if inS(i) && T.finalValid(i) && ~T.finalCurrent(i)
        fprintf('  row %d  %-28s %-22s mtime=%s\n', T.excelRow(i), T.SubjectID{i}, T.Task{i}, string(T.finalMtime(i)));
    end
end

fprintf('\n-- finals present but UNREADABLE (validity unknown; sheet sync will skip) --\n');
for i = 1:height(T)
    if T.preProcFilePresent(i) && ~T.finalKnown(i)
        fprintf('  row %d  %-28s %-22s fmt=%s %s\n', T.excelRow(i), T.SubjectID{i}, ...
            T.Task{i}, T.finalFmt{i}, T.finalPath{i});
    end
end

fprintf('\n-- duplicate Subject ID + task-group rows --\n');
keys = strcat(lower(strtrim(T.SubjectID)), '|', T.taskGroup, '|', T.condition);
[uk, ~, ic] = unique(keys);
for u = 1:numel(uk)
    m = find(ic == u);
    if numel(m) > 1
        fprintf('  %s: rows %s (eligible: %s)\n', uk{u}, mat2str(T.excelRow(m)'), mat2str(T.eligible(m)'));
    end
end

fprintf('\ntask1_inventory: DONE\n');

% ============================ helpers ============================

function s = cs(v)
    if isa(v, 'missing'), s = ''; return; end
    if ischar(v), s = v; return; end
    if isstring(v), s = char(v); return; end
    if isnumeric(v) || islogical(v)
        if isscalar(v), s = num2str(v); else, s = mat2str(v); end
        return;
    end
    if isdatetime(v), s = char(string(v)); return; end
    s = char(string(v));
end

function s = dateStr(v)
    if isa(v, 'missing'), s = ''; return; end
    if isdatetime(v), s = char(string(v, 'yyyy-MM-dd')); return; end
    s = cs(v);
end

function idx = findColX(hdr, name)
    idx = 0;
    for c = 1:numel(hdr)
        v = hdr{c};
        if (ischar(v) || isstring(v)) && strcmpi(strtrim(char(v)), name)
            idx = c; return;
        end
    end
    error('column "%s" not found', name);
end

function [grp, cond] = groupOf(tRaw)
    cond = '';
    s = lower(tRaw);
    s = s(~isspace(s));
    switch s
        case {'breathingtasks', 'breathingtask', 'wavebreathing'}
            grp = 'breathing';
        case 'odorcuetask'
            grp = 'cue';
        case 'threshold'
            grp = 'thresh';
        case 'o15'
            grp = 'O15';
        case 'emotionalmovietask'
            grp = 'EmotionalMovieTask';
        case 'alternating6blocks'
            grp = 'alternating6Blocks';
        case {'audiobook', 'distractedbreathing', 'focusedbreathing', ...
              'sleep', 'sleepwithodor', 'restingbaseline'}
            grp = 'breathingTasks_separate';
            cond = s;
        otherwise
            grp = '';
    end
end

function rt = rootFor(preVal, typeVal, L)
    if ~isempty(strtrim(preVal))
        rt = strtrim(preVal);
        canon = L.labCommonCanon;
        if numel(rt) >= numel(canon) && strncmpi(rt, canon, numel(canon))
            rt = [L.labCommon, rt(numel(canon)+1:end)];
        end
        return;
    end
    s = lower(typeVal);
    if contains(s, 'dupi')
        rt = L.rootDupi;
    elseif contains(s, 'eeg')
        rt = L.rootEEG;
    else
        rt = L.rootOBE;
    end
end

function fname = finalName(grp, id)
    switch grp
        case 'breathing',            fname = [id '_breathingPreproc.mat'];
        case 'cue',                  fname = [id '_cueTaskPreproc.mat'];
        case 'thresh',               fname = [id '_PEA_threshold_preproc.mat'];
        case 'O15',                  fname = [id '_O15preproc.mat'];
        case 'EmotionalMovieTask',   fname = [id '_EmotionalMovieTaskpreproc.mat'];
        case 'alternating6Blocks',   fname = [id '_alternating6Blockspreproc.mat'];
        case 'breathingTasks_separate', fname = [id '_breathingTasks_separatepreproc.mat'];
    end
end

function tf = rawPresent(grp, cond, rawDirs, sessDir)
    tf = false;
    for k = 1:numel(rawDirs)
        nm = lower(rawDirs{k});
        switch grp
            case 'breathing'
                % raw_audioBook is deliberately NOT counted: it is only a
                % supplement for one special-case session and would mask a
                % missing raw_breathingTasks
                hit = ~isempty(regexp(nm, '^raw_breathingtasks\d*$', 'once')) || ...
                      strcmp(nm, 'raw_wavebreathing');
            case 'cue'
                hit = contains(nm, 'raw_cuetaskodor');
            case 'thresh'
                hit = contains(nm, 'raw_peaintensitypleasantness');
            case 'O15'
                hit = strcmp(nm, 'raw_o15');
            case 'EmotionalMovieTask'
                hit = contains(nm, 'movie');
            case 'alternating6Blocks'
                hit = contains(nm, 'alternating');
            case 'breathingTasks_separate'
                hit = ~isempty(regexp(nm, ['^raw_' cond '\d*$'], 'once'));
        end
        if hit
            dd = dir(fullfile(sessDir, 'raw', rawDirs{k}, '*.mat'));
            if ~isempty(dd), tf = true; return; end
        end
    end
end

function [top, flds, fmt] = finalFields(p)
    top = ''; flds = {}; fmt = '';
    for attempt = 1:2    % one retry: a transient share hiccup must not
        try              % misclassify a good final as invalid
            gi = h5info(p, '/');
            cand = {};
            for g = 1:numel(gi.Groups)
                nm = gi.Groups(g).Name;   % like '/outDat'
                nm = nm(2:end);
                if ~isempty(nm) && nm(1) ~= '#', cand{end+1} = nm; end %#ok<AGROW>
            end
            for d = 1:numel(gi.Datasets)
                nm = gi.Datasets(d).Name;
                if ~isempty(nm) && nm(1) ~= '#', cand{end+1} = nm; end %#ok<AGROW>
            end
            if isempty(cand), fmt = 'v7.3-empty'; return; end
            top = cand{1};
            fmt = 'v7.3';
            g2 = h5info(p, ['/' top]);
            for d = 1:numel(g2.Datasets), flds{end+1} = g2.Datasets(d).Name; end %#ok<AGROW>
            for g = 1:numel(g2.Groups)
                nm = g2.Groups(g).Name;
                slash = find(nm == '/', 1, 'last');
                flds{end+1} = nm(slash+1:end); %#ok<AGROW>
            end
            return;
        catch
            pause(2);
        end
    end
    % not HDF5 (or unreadable via h5): a legacy v7 file up to 3 GB gets a
    % full-load field check so a valid legacy final is not misclassified
    d = dir(p);
    if ~isempty(d) && d(1).bytes < 3e9
        try
            S = load(p);
            fn = fieldnames(S);
            top = fn{1};
            if isstruct(S.(top)), flds = fieldnames(S.(top))'; end
            fmt = 'v7-loaded';
            clear S
            return;
        catch
        end
    end
    fmt = 'unreadable';
end

function a = plannedFor(R)
    if ~R.inScope
        a = 'skip (D1: dataType not ephys)'; return;
    end
    switch R.taskGroup
        case 'breathing'
            if ~R.eligible && ~R.rawOnDisk
                if contains(lower(R.Type), 'eeg')
                    a = 'Task 2 extract, then Task 3';
                else
                    a = 'not extracted - list only';
                end
            elseif strcmp(R.paramSource, 'curated')
                a = 'Task 3 rerun from raw';
            elseif contains(lower(R.Type), 'eeg')
                a = 'Task 3 run-on-guess (D4)';
            elseif isempty(R.paramSource)
                a = 'Task 3 guess, one attempt if listed in D6';
            else
                a = 'Task 3 guess list only';
            end
        case 'cue',    a = pendAct(R, 'Task 6');
        case 'thresh', a = pendAct(R, 'Task 5');
        case 'O15',    a = pendAct(R, 'Task 4');
        case 'EmotionalMovieTask'
            if contains(lower(R.Type), 'eeg')
                a = 'Task 2 extract, then Task 7 run-on-guess';
            else
                a = 'Task 7 guess list only';
            end
        case 'alternating6Blocks'
            a = 'Task 2 extract, then Task 8 run-on-guess';
        case 'breathingTasks_separate'
            a = 'Task 9 run-on-guess';
    end
end

function a = pendAct(R, tk)
    if ~strcmp(R.paramSource, 'curated')
        a = [tk ' guess list only'];
    elseif R.finalCurrent
        a = 'none (current)';
    elseif R.finalValid
        a = [tk ' one attempt (stale final, D6)'];
    else
        a = [tk ' run (curated, pending)'];
    end
end

function out = tern(c, a, b)
    if c, out = a; else, out = b; end
end

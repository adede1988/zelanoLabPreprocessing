% qc6_inventoryAudit - full sheet-vs-disk inventory (2026-08-31 user request).
%
% For every pipeline task x session the sheet exposes (applyParams 'main'
% cfg = mapped Task + Raw Data Extracted non-blank), checks the disk:
%   raw folder present? final present? final structurally valid (h5 member
%   check on the -v7.3 file: moreThan1 [+ bmObj/bmFeatures/behDat for the
%   breathing family])? behavioral CSV present (breathing family)?
% and compares with the sheet's Data Preprocessed X (read directly from the
% sheet; sep sessions aggregate their per-condition rows). Also scans for
% mapped rows whose Raw Data Extracted is BLANK (recorded, not yet
% extracted), unmapped Task values, and echem rows.
%
% Output: printed AUD lines + E:\reprocBackup_260824\qc6_inventory.csv.

% ---------- raw sheet read (header row 2, data from row 3) ----------
L = labPaths();
C = readcell(L.adminXlsx, 'Sheet', 'Sheet1');
hdr = C(2, :);
colIdx = @(n) find(cellfun(@(x) (ischar(x) || isstring(x)) && strcmpi(strtrim(char(string(x))), n), hdr), 1);
cID = colIdx('Subject ID'); cTask = colIdx('Task');
cRaw = colIdx('Raw Data Extracted'); cPre = colIdx('Data Preprocessed');
cDT = colIdx('dataType');
canon = @(t) canonOf(t);
sheetX = containers.Map('KeyType', 'char', 'ValueType', 'any');   % 'canon|id' -> cellstr of X marks
nBlankExtract = 0; blankList = {}; nUnmapped = 0; nEchem = 0;
for r = 3:size(C, 1)
    idv = C{r, cID};
    if ~(ischar(idv) || isstring(idv)) || strlength(string(idv)) == 0, continue; end
    id = strtrim(char(string(idv)));
    ck = canon(C{r, cTask});
    dt = ''; if ~isempty(cDT), dt = lower(strtrim(char(string(cellVal(C{r, cDT}))))); end
    if contains(dt, 'echem'), nEchem = nEchem + 1; continue; end
    if isempty(ck)
        tks = strtrim(char(string(cellVal(C{r, cTask}))));
        if ~isempty(tks), nUnmapped = nUnmapped + 1; end
        continue;
    end
    rawv = cellVal(C{r, cRaw});
    if strlength(strtrim(string(rawv))) == 0
        nBlankExtract = nBlankExtract + 1;
        blankList{end+1} = sprintf('%s | %s', id, char(string(cellVal(C{r, cTask})))); %#ok<SAGROW>
        continue;
    end
    key = [ck '|' id];
    xv = strtrim(char(string(cellVal(C{r, cPre}))));
    if sheetX.isKey(key), v = sheetX(key); else, v = {}; end
    v{end+1} = xv; %#ok<AGROW>
    sheetX(key) = v;
end

% ---------- disk audit per pipeline task ----------
TASKS = { ...
 'breathingTask',           'breathing', {'raw_breathingTasks', 'raw_waveBreathing', 'raw_audioBook'}, '_breathingPre*.mat',            true;  ...
 'cueTask',                 'cue',       {'raw_cueTask'},                                              '*cueTask*.mat',                 false; ...
 'threshTask',              'thresh',    {'raw_PEAintensityPleasantness_threshold', 'raw_threshTask'}, '*threshold*preproc*.mat',       false; ...
 'O15',                     'O15',       {'raw_O15'},                                                  '*O15*preproc*.mat',             false; ...
 'EmotionalMovieTask',      'movie',     {'raw_EmotionalMovieTask'},                                   '*EmotionalMovieTask*.mat',      true;  ...
 'alternating6Blocks',      'alt6',      {'raw_alternating6Blocks'},                                   '*alternating6Blocks*.mat',      true;  ...
 'breathingTasks_separate', 'sep',       {},                                                           '*breathingTasks_separate*.mat', true};
codePre = 'E:\GitHub\';
R = {};
for tt = 1:size(TASKS, 1)
    [tkey, ck, rawPats, finPat, isBreathFam] = TASKS{tt, :};
    cfg = applyParams(tkey, 'main');
    for si = 1:numel(cfg.sessionIDs)
        id = cfg.sessionIDs{si};
        sroot = fullfile(cfg.root{si}, id);
        % ---- raw presence ----
        if strcmp(ck, 'sep')
            P = applyParams(tkey, id);
            nCond = numel(P.conditions); nFound = 0; missCond = {};
            for c = 1:nCond
                cn = P.conditions{c}; cn = cn(~isspace(cn));
                hitsR = dir(fullfile(sroot, 'raw', ['raw_' cn '*']));
                hitsR = hitsR([hitsR.isdir]);
                if isempty(hitsR) && numel(cn) > 1
                    hitsR = dir(fullfile(sroot, 'raw', ['raw_*' cn(2:end) '*']));
                    hitsR = hitsR([hitsR.isdir]);
                end
                if ~isempty(hitsR), nFound = nFound + 1; else, missCond{end+1} = cn; end %#ok<SAGROW>
            end
            rawOK = nFound == nCond && nCond > 0;
            rawState = sprintf('%d/%d cond', nFound, nCond);
            if ~isempty(missCond), rawState = [rawState ' missing:' strjoin(missCond, '+')]; end %#ok<AGROW>
        else
            rawOK = false; rawState = 'MISSING';
            for rp = 1:numel(rawPats)
                hitsR = dir(fullfile(sroot, 'raw', [rawPats{rp} '*']));
                hitsR = hitsR([hitsR.isdir]);
                if ~isempty(hitsR)
                    m = dir(fullfile(sroot, 'raw', hitsR(1).name, '*.mat'));
                    if ~isempty(m), rawOK = true; rawState = hitsR(1).name; break; end
                end
            end
        end
        % ---- final presence + structural validity ----
        finState = 'NONE'; finOK = false;
        hitsF = dir(fullfile(sroot, 'preProc', finPat));
        hitsF = hitsF(~contains({hitsF.name}, 'condLabels'));
        if strcmp(tkey, 'breathingTask')
            hitsF = hitsF(~contains(lower({hitsF.name}), 'separate'));
        end
        if ~isempty(hitsF)
            fpath = fullfile(hitsF(1).folder, hitsF(1).name);
            try
                info = h5info(fpath);
                gn = {info.Groups.Name};
                gi = find(~strcmp(gn, '/#refs#'), 1);
                mem = {};
                if ~isempty(info.Groups(gi).Datasets), mem = {info.Groups(gi).Datasets.Name}; end
                if ~isempty(info.Groups(gi).Groups)
                    mem = [mem, cellfun(@(x) x(find(x=='/',1,'last')+1:end), ...
                        {info.Groups(gi).Groups.Name}, 'UniformOutput', false)];
                end
                need = {'moreThan1'};
                if isBreathFam, need = [need, {'bmObj', 'bmFeatures', 'behDat'}]; end
                if all(ismember(need, mem))
                    finOK = true; finState = 'VALID';
                else
                    finState = ['INCOMPLETE missing:' strjoin(setdiff(need, mem), '+')];
                end
            catch
                try
                    w = whos('-file', fpath);
                    finState = sprintf('LEGACY-v7(%s)', w(1).name);
                    finOK = true;
                catch
                    finState = 'UNREADABLE';
                end
            end
        end
        % ---- behavioral CSV (breathing-family ingestion prerequisite) ----
        csvState = '-';
        if isBreathFam
            c1 = exist(fullfile(codePre, 'closed-loop-respiration', 'processedBehavior', [id '.csv']), 'file') == 2;
            c2 = exist(fullfile(codePre, 'experiment_EEGsync', 'processedBehavior', [id '.csv']), 'file') == 2;
            if c1, csvState = 'closed-loop'; elseif c2, csvState = 'EEGsync'; else, csvState = 'MISSING'; end
        end
        % ---- sheet X (sep aggregates condition rows) ----
        key = [ck '|' id]; xs = '';
        if sheetX.isKey(key)
            v = sheetX(key);
            nx = sum(~cellfun(@isempty, v));
            if nx == numel(v) && nx > 0, xs = 'X';
            elseif nx > 0, xs = sprintf('partial(%d/%d)', nx, numel(v));
            end
        else
            xs = 'row?';
        end
        drift = '';
        if finOK && isempty(xs), drift = 'DISK-AHEAD'; end
        if ~finOK && strcmp(xs, 'X'), drift = 'SHEET-AHEAD'; end
        ps = cfg.paramSource{si};
        if isnumeric(ps), ps = ''; end
        R(end+1, :) = {tkey, id, rawState, finState, csvState, xs, strtrim(char(string(ps))), drift}; %#ok<SAGROW>
        fprintf('AUD %s | %s | raw=%s | final=%s | csv=%s | X=%s | src=%s | %s\n', ...
            tkey, id, rawState, finState, csvState, xs, strtrim(char(string(ps))), drift);
    end
end
T = cell2table(R, 'VariableNames', {'task','session','raw','final','csv','sheetX','paramSource','drift'});
writetable(T, 'E:\reprocBackup_260824\qc6_inventory.csv');

fprintf('AUDSHEET mapped rows with BLANK Raw Data Extracted (recorded, not yet extracted): %d\n', nBlankExtract);
for k = 1:numel(blankList), fprintf('AUDSHEET blank-extract: %s\n', blankList{k}); end
fprintf('AUDSHEET unmapped-task rows (excl echem): %d | echem rows: %d\n', nUnmapped, nEchem);
fprintf('qc6_inventoryAudit: DONE (%d task-session rows)\n', height(T));

function v = cellVal(x)
    if ismissing(string(x)), v = ''; else, v = x; end
end

function k = canonOf(t)
    if ismissing(string(t)), k = ''; return; end
    s = lower(char(string(t))); s = s(~isspace(s));
    switch s
        case {'breathingtasks', 'wavebreathing', 'breathingtask'}, k = 'breathing';
        case {'odorcuetask'}, k = 'cue';
        case {'o15'}, k = 'O15';
        case {'threshold'}, k = 'thresh';
        case {'emotionalmovietask'}, k = 'movie';
        case {'alternating6blocks'}, k = 'alt6';
        case {'audiobook', 'distractedbreathing', 'focusedbreathing', ...
              'sleep', 'sleepwithodor', 'restingbaseline'}, k = 'sep';
        otherwise, k = '';
    end
end

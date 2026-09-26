function loadFile = findLoadDataScript(sessDir, task, src)
%FINDLOADDATASCRIPT  SHARED: which LoadData script produced a session's raw file (provenance).
%
%   loadFile = findLoadDataScript(sessDir, task)
%   loadFile = findLoadDataScript(sessDir, task, src)
%
%   sessDir  the participant folder, <root>\<id>
%   task     canonical task name (P.task spelling: 'breathingTask', 'cueTask',
%            'threshTask', 'O15', 'pacedBreathing', 'alternating6Blocks',
%            'EmotionalMovieTask', ...) - selects the legacy tie-break below
%   src      optional struct carrying provenance: the raw file's curDat (or a
%            raw struct copied from it). A LoadData script records itself by
%            storing   curDat.loadFile = [mfilename '.m'];   in every raw .mat
%            it writes.
%
%   Returns the script's file name (no folder), or '' when it cannot be
%   identified. It NEVER errors because a folder holds several LoadData
%   scripts (old + *_claude.m scripts now live side by side); an unresolved
%   case warns (findLoadDataScript:ambiguous / :none) and returns ''.
%
%   Resolution order:
%     1. src.loadFile, when present and non-empty (explicit provenance)
%     2. the only *LoadData*.m file in sessDir (macOS '._' AppleDouble junk
%        is ignored)
%     3. several candidates: the unique *_claude.m script
%     4. the task's legacy tie-break, when it matches exactly one candidate:
%          breathingTask       LoadData_<id>.m (canonical name)
%          cueTask, threshTask name ends in 'AD.m'
%          O15                 name contains 'AD'
%          pacedBreathing / alternating6Blocks / EmotionalMovieTask
%                              name contains the task name
%     5. '' with a warning
%   NB: step 3 names the *_claude.m script for EVERY task of such a folder;
%   a raw file extracted by an older script is attributed correctly only when
%   it carries src.loadFile. The field is provenance only (O15 / pacedBreathing
%   finals; the makeOutDat intermediates are overwritten by their finals).

    if nargin < 3, src = []; end

    % 1. explicit provenance written by the LoadData script
    if isstruct(src) && isfield(src, 'loadFile') && ~isempty(src.loadFile)
        loadFile = char(string(src.loadFile));
        return;
    end

    d = dir(fullfile(sessDir, '*LoadData*.m'));
    d = d(~[d.isdir]);
    names = {d.name};
    names = names(endsWith(names, '.m') & ~startsWith(names, '._'));

    % 2. a single candidate
    if isscalar(names)
        loadFile = names{1};
        return;
    end
    if isempty(names)
        loadFile = '';
        warning('findLoadDataScript:none', 'no LoadData script in %s', sessDir);
        return;
    end

    % 3. the unique *_claude.m script
    hit = names(endsWith(names, '_claude.m', 'IgnoreCase', true));
    if isscalar(hit)
        loadFile = hit{1};
        return;
    end

    % 4. legacy per-task tie-breaks (behaviour of the loaders before C13)
    [~, id] = fileparts(regexprep(char(sessDir), '[\\/]+$', ''));
    switch lower(char(string(task)))
        case 'breathingtask'
            hit = names(strcmpi(names, ['LoadData_' id '.m']));
        case {'cuetask', 'threshtask'}
            hit = names(endsWith(names, 'AD.m'));
        case 'o15'
            hit = names(contains(names, 'AD'));
        case {'pacedbreathing', 'alternating6blocks', 'emotionalmovietask'}
            hit = names(contains(names, char(string(task))));
        otherwise
            hit = {};
    end
    if isscalar(hit)
        loadFile = hit{1};
        return;
    end

    % 5. unresolved: provenance unknown, never fatal
    loadFile = '';
    warning('findLoadDataScript:ambiguous', ...
        '%s: LoadData script not identified uniquely (%d candidates: %s) - loadFile left empty', ...
        sessDir, numel(names), strjoin(names, ', '));
end

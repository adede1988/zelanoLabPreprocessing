function ratings = parse_sweepRatings(csvPaths)
%PARSE_SWEEPRATINGS  State ratings of a respiratorySweep session (PsychoPy mindfulBreathing csv).
%
%   ratings = parse_sweepRatings(csvPaths)
%
%   csvPaths : cellstr of the session's <id>_mindfulBreathing_<datetime>.csv
%              files (a restarted run leaves several; aborted runs carry no
%              responses and contribute nothing)
%
%   Each run asks the same 12 state questions (affective / mindfulness /
%   breathing) as alternating6Blocks. In the 2026-10 protocol a run holds a
%   baseline set (before the audiobook) and, once all pacing blocks are done,
%   a post-sweep set; question sets whose loop was skipped have empty slider
%   responses and are dropped. Rated rows are clustered into sets by time gaps
%   (> 120 s on the run's clock) and each set is labelled by its position
%   relative to the run's pacing blocks (rows with cndName = Sweep,
%   playBackNormal.started): before the first block = 'baseline', after the
%   last = 'postSweep', in between = 'midSweep'; a run with no pacing block
%   rows labels its sets 'baseline'. Repeats of a label (another run) get a
%   numeric suffix ('baseline_2') in file order.
%
%   Returns a table, one row per rated question:
%     set, file, Q_short, type (= trialType), question, rsp, t (run clock, s)
%   Q_short map as in parse_mindfulBreathing (alternating6Blocks). An unmapped
%   question is an error (a changed questionnaire must be mapped deliberately).

    if ischar(csvPaths) || isstring(csvPaths), csvPaths = cellstr(csvPaths); end
    csvPaths = sort(csvPaths(:));            % the <yyyy-MM-dd_HHhMM.SS> stamp sorts chronologically

    qmap = { ...
        'relaxed', 'relaxed'; 'upset', 'upset'; 'tense', 'tense'; ...
        'worried', 'worried'; 'content', 'content'; 'calm', 'calm'; ...
        'pleasant and unpleasant thoughts',   'plsntThoughts'; ...
        'to see the patterns of my thinking', 'thinkPatterns'; ...
        'emotions come and go',               'emoComeGo'; ...
        'the quality of my breathing',        'breathQuality'; ...
        'present in my body',                 'bodyPresent'; ...
        'the sensations of my breathing',     'breathSensations'};

    ratings = table('Size', [0 7], 'VariableTypes', {'string', 'string', 'string', 'string', 'string', 'double', 'double'}, ...
        'VariableNames', {'set', 'file', 'Q_short', 'type', 'question', 'rsp', 't'});
    for f = 1:numel(csvPaths)
        [~, fn, ext] = fileparts(csvPaths{f});
        T = readtable(csvPaths{f}, 'VariableNamingRule', 'preserve', 'Delimiter', ',');
        if height(T) == 0 || ~ismember('question', T.Properties.VariableNames), continue; end
        vn = T.Properties.VariableNames;
        respCols = vn(~cellfun('isempty', regexp(vn, '^(\w+\.)?slider\w*\.response$', 'once')));

        % pacing-block starts on this run's clock
        swT = [];
        if all(ismember({'cndName', 'playBackNormal.started'}, vn))
            isSw = strcmpi(strtrim(string(T.cndName)), "Sweep");
            swT = colNumV(T, 'playBackNormal.started');
            swT = swT(isSw & isfinite(swT));
        end

        R = table('Size', [0 7], 'VariableTypes', {'string', 'string', 'string', 'string', 'string', 'double', 'double'}, ...
            'VariableNames', {'set', 'file', 'Q_short', 'type', 'question', 'rsp', 't'});
        for r = 1:height(T)
            q = strtrim(colStr(T, 'question', r));
            if isempty(q), continue; end
            rsp = NaN;
            for c = 1:numel(respCols)
                v = colNum(T, respCols{c}, r);
                if isfinite(v), rsp = v; break; end
            end
            if ~isfinite(rsp), continue; end
            qi = find(strcmpi(qmap(:, 1), q), 1);
            if isempty(qi)
                error('parse_sweepRatings:unknownQuestion', 'unmapped question "%s" in %s', q, csvPaths{f});
            end
            R(end+1, :) = {"", string([fn ext]), string(qmap{qi, 2}), string(colStr(T, 'trialType', r)), ...
                           string(q), rsp, colNum(T, 'thisRow.t', r)}; %#ok<AGROW>
        end
        if height(R) == 0, continue; end
        R = sortrows(R, 't');
        setId = cumsum([1; diff(R.t) > 120]);
        for s = 1:max(setId)
            m = setId == s;
            tm = median(R.t(m));
            if isempty(swT) || tm < min(swT)
                lab = "baseline";
            elseif tm > max(swT)
                lab = "postSweep";
            else
                lab = "midSweep";
            end
            R.set(m) = lab;
        end
        ratings = [ratings; R]; %#ok<AGROW>
    end

    % repeated labels across runs -> numbered (file order = chronological)
    if height(ratings) > 0
        keyRun = ratings.file + "|" + ratings.set;
        [uk, ia] = unique(keyRun, 'stable');
        labs = ratings.set(ia);
        for k = 1:numel(uk)
            prev = sum(labs(1:k-1) == labs(k));
            if prev > 0
                ratings.set(keyRun == uk(k)) = labs(k) + "_" + (prev + 1);
            end
        end
    end
    sets = unique(ratings.set, 'stable');
    cnt = arrayfun(@(s) sum(ratings.set == s), sets);
    fprintf('parse_sweepRatings: %d rated rows in %d set(s): %s\n', height(ratings), numel(sets), ...
        strjoin(sets + "(" + string(cnt) + ")", ', '));
end

function s = colStr(T, name, r)
    if ~ismember(name, T.Properties.VariableNames), s = ''; return; end
    v = T.(name)(r);
    if iscell(v), v = v{1}; end
    if isstring(v), v = char(v); end
    if isnumeric(v)
        if isnan(v), s = ''; else, s = num2str(v); end
        return;
    end
    s = char(v);
end

function x = colNum(T, name, r)
    if ~ismember(name, T.Properties.VariableNames), x = NaN; return; end
    v = T.(name)(r);
    if iscell(v), v = v{1}; end
    if ischar(v) || isstring(v), x = str2double(v); return; end
    x = double(v);
end

function x = colNumV(T, name)
    v = T.(name);
    if iscell(v) || isstring(v), x = str2double(string(v)); else, x = double(v); end
end

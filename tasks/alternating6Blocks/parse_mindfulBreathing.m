function ratings = parse_mindfulBreathing(csvPath)
%PARSE_MINDFULBREATHING  Read the PsychoPy ratings file for alternating6Blocks.
%
%   ratings = parse_mindfulBreathing(csvPath)
%
%   The <ID>_mindfulBreathing_<DATETIME>.csv holds 12 questions x 8 sets
%   (baseline via the STARTstateQuestions routine, post-audiobook via the
%   stateQuestions_audio routine, six post-playback sets via stateQ_playbacks).
%   Slider responses live in routine-specific columns; each rated row carries
%   trialType (affective / mindfulness / breathing), question, and thisRow.t.
%
%   Returns a table with one row per rated question:
%     set (1..8, by time cluster; gaps > 120 s), order (set-1: 0 = baseline,
%     k = after block k), Q_short, type (=trialType), question, rsp, t
%
%   Q_short map (documented convention for this task):
%     relaxed/upset/tense/worried/content/calm  -> verbatim        (affective)
%     'pleasant and unpleasant thoughts'        -> plsntThoughts   (mindfulness)
%     'to see the patterns of my thinking'      -> thinkPatterns   (mindfulness)
%     'emotions come and go'                    -> emoComeGo       (mindfulness)
%     'the quality of my breathing'             -> breathQuality   (breathing)
%     'present in my body'                      -> bodyPresent     (breathing)
%     'the sensations of my breathing'          -> breathSensations(breathing)
%   Errors loudly if the file does not yield exactly 8 sets (D11c).

    T = readtable(csvPath, 'VariableNamingRule', 'preserve');

    respCols = {'slider.response', 'slider_4.response', 'slider_2.response', ...
                'trials_2.slider.response', 'trials_4.slider_4.response', ...
                'stateQ_playbacks.slider_2.response'};
    respCols = respCols(ismember(respCols, T.Properties.VariableNames));

    qmap = { ...
        'relaxed', 'relaxed'; 'upset', 'upset'; 'tense', 'tense'; ...
        'worried', 'worried'; 'content', 'content'; 'calm', 'calm'; ...
        'pleasant and unpleasant thoughts',   'plsntThoughts'; ...
        'to see the patterns of my thinking', 'thinkPatterns'; ...
        'emotions come and go',               'emoComeGo'; ...
        'the quality of my breathing',        'breathQuality'; ...
        'present in my body',                 'bodyPresent'; ...
        'the sensations of my breathing',     'breathSensations'};

    rows = [];
    for r = 1:height(T)
        q = colStr(T, 'question', r);
        if isempty(q), continue; end
        rsp = NaN;
        for c = 1:numel(respCols)
            v = colNum(T, respCols{c}, r);
            if isfinite(v), rsp = v; break; end
        end
        if ~isfinite(rsp), continue; end
        qi = find(strcmpi(qmap(:, 1), strtrim(q)), 1);
        if isempty(qi)
            error('parse_mindfulBreathing:unknownQuestion', ...
                'unmapped question "%s" in %s', q, csvPath);
        end
        R = struct();
        R.Q_short  = string(qmap{qi, 2});
        R.type     = string(colStr(T, 'trialType', r));
        R.question = string(strtrim(q));
        R.rsp      = rsp;
        R.t        = colNum(T, 'thisRow.t', r);
        rows = [rows; R]; %#ok<AGROW>
    end
    ratings = struct2table(rows);
    ratings = sortrows(ratings, 't');

    % cluster into sets by time gaps
    setId = cumsum([1; diff(ratings.t) > 120]);
    ratings.set = setId;
    ratings.order = setId - 1;      % 0 = baseline, k = after block k

    nSets = max(setId);
    counts = accumarray(setId, 1);
    fprintf('parse_mindfulBreathing: %d rated rows in %d sets (counts: %s)\n', ...
        height(ratings), nSets, mat2str(counts'));
    assert(nSets == 8, 'parse_mindfulBreathing:badSets', ...
        'expected 8 rating sets (baseline + 7 blocks), got %d (D11c)', nSets);
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

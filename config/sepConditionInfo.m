function info = sepConditionInfo(taskValue)
%SEPCONDITIONINFO  The breathingTasks_separate condition vocabulary (one list).
%
%   info = sepConditionInfo(taskValue)
%
%   taskValue  a sheet Task cell (char / string)
%   info       [] when the value is not a breathingTasks_separate condition,
%              else a struct with
%                .key        normalized value (lower case, whitespace removed)
%                .label      canonical section label (D12c): the behDat
%                            'task' value / outDat.sections label
%                .rawRegex   cellstr of anchored regexes; the condition's raw
%                            folder is the ONE folder under <id>\raw whose
%                            lower-cased name matches any of them
%
%   Shared by applyParams (canonTask: which rows belong to the task),
%   writeSheetSep (which rows it writes) and
%   assembleRaw_breathingTasks_separate (label + raw folder), so the three
%   can never disagree. Matching is exact on the normalized value - no fuzzy
%   matching - and a *_echem recording never matches.
%
%   Conditions (sheet Task value -> label; raw folder):
%     audiobook, distractedBreathing   -> audiobook
%     focusedBreathing                 -> focusedBreathing
%     sleep                            -> sleep
%     sleepWithOdor                    -> sleepWithOdor
%     restingBaseline                  -> restingBaseline
%     focusedBreathing_button1/2       -> focusedBreathing_button (two OBE takes)
%     focusedBreathing_button_mouth    -> focusedBreathing_mouth
%       raw folder for all of the above: raw_<value>, optionally followed by
%       digits (the historical ^raw_<value>\d*$ rule)
%     focusedBreathing_button          -> focusedBreathing_button; raw folder
%       raw_focusedBreathing_button<digits>, or the exact older names
%       raw_focusedBreathButtonPress / raw_buttonPressFocusedBreathing
%     <condition>_run<N> for any condition above except the button1/2/mouth
%       variants (e.g. sleep_run1 / sleep_run2 of 240822_OBE_NMH_FM)
%                                      -> the condition's label; raw folder
%       exactly raw_<condition>_run<N>

    info = [];
    if isa(taskValue, 'missing') || isempty(taskValue), return; end
    if ~(ischar(taskValue) || isstring(taskValue)), return; end
    key = lower(char(taskValue));
    key = key(~isspace(key));

    % base conditions: normalized value -> label
    base = { ...
        'audiobook',                     'audiobook'; ...
        'distractedbreathing',           'audiobook'; ...
        'focusedbreathing',              'focusedBreathing'; ...
        'sleep',                         'sleep'; ...
        'sleepwithodor',                 'sleepWithOdor'; ...
        'restingbaseline',               'restingBaseline'; ...
        'focusedbreathing_button',       'focusedBreathing_button'; ...
        'focusedbreathing_button1',      'focusedBreathing_button'; ...
        'focusedbreathing_button2',      'focusedBreathing_button'; ...
        'focusedbreathing_button_mouth', 'focusedBreathing_mouth'};
    % bases that may carry a _run<N> suffix
    runBases = {'audiobook', 'distractedbreathing', 'focusedbreathing', 'sleep', ...
                'sleepwithodor', 'restingbaseline', 'focusedbreathing_button'};

    hit = find(strcmp(base(:, 1), key), 1);
    if ~isempty(hit)
        info.key = key;
        info.label = base{hit, 2};
        info.rawRegex = {['^raw_' regexptranslate('escape', key) '\d*$']};
        if strcmp(key, 'focusedbreathing_button')
            % older extractions of this condition used other folder names
            info.rawRegex = [info.rawRegex, ...
                {'^raw_focusedbreathbuttonpress$', '^raw_buttonpressfocusedbreathing$'}];
        end
        return;
    end

    tok = regexp(key, '^(.+)_run(\d+)$', 'tokens', 'once');
    if ~isempty(tok) && any(strcmp(runBases, tok{1}))
        info.key = key;
        info.label = base{strcmp(base(:, 1), tok{1}), 2};
        info.rawRegex = {['^raw_' regexptranslate('escape', key) '$']};
    end
end

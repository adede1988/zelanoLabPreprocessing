function T = probeECGpolarity(ids, task)
%PROBEECGPOLARITY  ECG beat rate per channel x polarity on saved finals.
%
%   T = probeECGpolarity(ids)                  % task = 'breathingTasks_separate'
%   T = probeECGpolarity(ids, task)
%
%   ids  : session ID (char) or cell of session IDs.
%   task : any breath-type task with ECG - 'breathingTask',
%          'breathingTasks_separate' (default), 'alternating6Blocks',
%          'EmotionalMovieTask', 'pacedBreathing'.
%
%   For each session: load the final, z-score each 5-40 Hz band-passed ECG
%   channel (buildECGz's conditioning), count threshold crossings at +/-3.5
%   sigma with the detectBeats minimum separation (fs/20), and report bpm for
%   every channel x side. A plausible resting rate (40-110 bpm) on exactly one
%   side identifies the right beatSpec ('<ch>,0,gt,3.5' or '<ch>,0,lt,-3.5');
%   ambiguous sessions need manual curation. Read-only (no sheet writes).
%   T has one row per session x channel x side: id, ch, side, nBeats, bpm.
%
%   Complements batch/qc7_ecgSpecAudit.m (breathingTask finals only, full
%   spec sweep) and batch/probeSessionParams.m (breathingTask intermediates).
%   Originally batch/task9_probeECGpolarity.m (Tasks_260824.md Task 9).

    if nargin < 2 || isempty(task), task = 'breathingTasks_separate'; end
    ids = cellstr(ids);
    switch lower(task)
        case 'breathingtask',            finalTag = '_breathingPreproc.mat';
        case 'breathingtasks_separate',  finalTag = '_breathingTasks_separatepreproc.mat';
        case 'alternating6blocks',       finalTag = '_alternating6Blockspreproc.mat';
        case 'emotionalmovietask',       finalTag = '_EmotionalMovieTaskpreproc.mat';
        case 'pacedbreathing',           finalTag = '_pacedBreathingpreproc.mat';
        otherwise
            error('probeECGpolarity:badTask', 'No ECG final for task "%s".', task);
    end

    T = table('Size', [0 5], 'VariableTypes', {'string', 'double', 'string', 'double', 'double'}, ...
        'VariableNames', {'id', 'ch', 'side', 'nBeats', 'bpm'});
    cfg = applyParams(task, 'main');
    for k = 1:numel(ids)
        id = ids{k};
        si = find(strcmp(cfg.sessionIDs, id), 1);
        if isempty(si), fprintf('%s: not in session list\n', id); continue; end
        fpath = fullfile(cfg.root{si}, id, 'preProc', [id finalTag]);
        if ~exist(fpath, 'file'), fprintf('%s: no final\n', id); continue; end
        s = load(fpath); fn = fieldnames(s); od = s.(fn{1}); clear s

        isECG = cellfun(@(x) contains(x, 'ECG'), od.labels);
        ecg = od.data(isECG, :);
        fs = od.fs;
        mins = size(ecg, 2) / fs / 60;
        fprintf('%s: %d ECG chans, %.1f min\n', id, size(ecg, 1), mins);
        minSep = round(fs / 20);
        for ch = 1:size(ecg, 1)
            x = bandpass(ecg(ch, :), [5 40], fs);
            x = (x - mean(x)) / std(x);
            for sgn = [1 -1]
                idx = find(sgn * x > 3.5);
                if isempty(idx)
                    nb = 0;
                else
                    nb = 1 + sum(diff(idx) > minSep);
                end
                pm = '+-';
                fprintf('   ch%d %c3.5: %5d beats = %6.1f bpm\n', ch, ...
                    pm((3 - sgn) / 2), nb, nb / mins);
                T(end+1, :) = {string(id), ch, string(pm((3 - sgn) / 2)), nb, nb / mins}; %#ok<AGROW>
            end
        end
        clear od ecg
    end
    fprintf('probeECGpolarity: DONE\n');
end

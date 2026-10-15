function raws = assembleRaw_breathingTasks_separate(S, P)
%ASSEMBLERAW_BREATHINGTASKS_SEPARATE  Load a session's condition recordings (D12b).
%
%   raws = assembleRaw_breathingTasks_separate(S, P)
%
%   For every in-scope condition row of the session (P.conditions, from
%   applyParams), loads the single .mat of the condition's raw folder -
%   raw\raw_<condition>\ as a rule, with the documented older aliases and
%   the exact raw_<condition>_run<N> folders of repeated runs; the rules and
%   the section labels live in config/sepConditionInfo (folder names matched
%   case-insensitively, exactly one folder required) - requires identical
%   labels and sampling rate across files (error otherwise), and returns a
%   struct array ordered chronologically by recording start (D12b).
%
%   Ordering evidence (ft_appenddata drops the Neuralynx hdr, so
%   FirstTimeStamp is unavailable): (1) the Neuralynx channel-file SUFFIX
%   parsed from curDat.ncslabels ('' = first recording of an acquisition
%   folder, '_000N' = the N-th stop/start - suffixes increment
%   chronologically), and (2) the acquisition-folder datetime recovered from
%   the fieldtrip cfg.previous provenance (dataset path), used when
%   conditions came from different folders. Multi-file sessions error if the
%   combined key is not strictly ordered. Single-file sessions need no
%   ordering.
%
%   Each element: .condition (sheet Task value) .label (D12c canonical, from
%   sepConditionInfo: audioBook/audiobook/distractedBreathing -> 'audiobook',
%   focusedBreathing_button[1|2] -> 'focusedBreathing_button', <cond>_run<N>
%   -> <cond>'s label, ...) .data .labels .fs_raw .suffix .folderTime .srcFile
%   .rawFirstSample .rawLastSample .rawSamples .trimSec
%
%   Optional per-condition trim (P.condTrimSec, [nCond x 2] aligned with
%   P.conditions, set in an explicit applyParams case; tasks_261014 task 8):
%   [start end] in seconds from the start of that condition's raw recording;
%   only the raw samples k with start <= (k-1)/fs_raw < end are kept (NaN start
%   = from the first sample, NaN end = to the last). Applied here, before any
%   processing. .rawFirstSample/.rawLastSample give the kept range in the raw
%   file's samples (1 / rawSamples when untrimmed); .trimSec the setting.

    rawRoot = fullfile(S.root, S.id, 'raw');
    d = dir(rawRoot);
    dirNames = {d([d.isdir]).name};

    raws = struct('condition', {}, 'label', {}, 'data', {}, 'labels', {}, ...
                  'fs_raw', {}, 'suffix', {}, 'folderTime', {}, 'srcFile', {}, ...
                  'rawFirstSample', {}, 'rawLastSample', {}, 'rawSamples', {}, 'trimSec', {});
    for c = 1:numel(P.conditions)
        cond = P.conditions{c};
        info = sepConditionInfo(cond);   % label + raw-folder rule (one shared list)
        assert(~isempty(info), 'assembleRaw_breathingTasks_separate:condition', ...
            '%s: "%s" is not a breathingTasks_separate condition', S.id, cond);
        hit = find(cellfun(@(nm) any(cellfun(@(rx) ~isempty(regexp(lower(nm), rx, 'once')), ...
              info.rawRegex)), dirNames));
        assert(numel(hit) == 1, ...
            'assembleRaw_breathingTasks_separate:rawFolder', ...
            '%s: expected exactly 1 raw folder for condition "%s", found %d', ...
            S.id, cond, numel(hit));
        fld = dirNames{hit};
        mats = dir(fullfile(rawRoot, fld, '*.mat'));
        assert(isscalar(mats), '%s: expected 1 .mat in %s, found %d', S.id, fld, numel(mats));
        fpath = fullfile(mats(1).folder, mats(1).name);
        tmp = load(fpath);
        cd0 = tmp.curDat; clear tmp

        % NB: fields must be created in the template's exact order for the
        % struct-array assignment below
        R = struct();
        R.condition  = cond;
        R.label      = info.label;
        R.data       = cd0.rawData.trial{1};
        % outLabs cells can hold string objects; downstream (strjoin, isequal
        % across sections) needs plain char vectors
        R.labels     = cellstr(string(cd0.outLabs(:)))';
        R.fs_raw     = cd0.rawData.fsample;
        R.suffix     = suffixOf(cd0.ncslabels);
        R.folderTime = provenanceTime(cd0.rawData);
        R.srcFile    = fpath;
        if any(isnan(R.data(:)))
            R.data = fillmissing(R.data, 'linear', 2, 'EndValues', 'nearest');
        end
        % per-condition trim (tasks_261014 task 8); untrimmed = the whole file
        nRaw = size(R.data, 2);
        R.rawFirstSample = 1;
        R.rawLastSample  = nRaw;
        R.rawSamples     = nRaw;
        R.trimSec        = [NaN NaN];
        if isfield(P, 'condTrimSec') && any(~isnan(P.condTrimSec(c, :)))
            R.trimSec = P.condTrimSec(c, :);
            [R.rawFirstSample, R.rawLastSample] = trimRange(R.trimSec, R.fs_raw, nRaw, S.id, cond);
            R.data = R.data(:, R.rawFirstSample:R.rawLastSample);
            fprintf('   %s: TRIM keeps raw samples %d-%d of %d (%.2f-%.2f s of %.2f s)\n', cond, ...
                R.rawFirstSample, R.rawLastSample, nRaw, (R.rawFirstSample - 1) / R.fs_raw, ...
                R.rawLastSample / R.fs_raw, nRaw / R.fs_raw);
        end
        ftDisp = 'unknown';
        if ~isnat(R.folderTime), ftDisp = char(string(R.folderTime)); end
        fprintf('   %s: suffix %d, folder time %s\n', cond, R.suffix, ftDisp);
        raws(end+1) = R; %#ok<AGROW>
        clear cd0
    end

    % identical labels + fs across files (D12b)
    for c = 2:numel(raws)
        assert(isequal(raws(c).labels(:), raws(1).labels(:)), ...
            '%s: channel labels differ between condition recordings', S.id);
        assert(raws(c).fs_raw == raws(1).fs_raw, ...
            '%s: sampling rates differ between condition recordings', S.id);
    end

    % chronological order (folder datetime, then Neuralynx suffix)
    if numel(raws) > 1
        ft = [raws.folderTime];
        if any(isnat(ft))
            % no per-file folder provenance: all files must share one
            % acquisition folder, so the suffix alone must disambiguate
            sfx = [raws.suffix];
            assert(numel(unique(sfx)) == numel(sfx), ...
                'assembleRaw_breathingTasks_separate:orderAmbiguous', ...
                '%s: no folder provenance and duplicate suffixes %s - cannot order (D12b)', ...
                S.id, mat2str(sfx));
            [~, ord] = sort(sfx);
        else
            key = datenum(ft) * 1e6 + [raws.suffix];
            assert(numel(unique(key)) == numel(key), ...
                '%s: ordering key not unique - cannot order (D12b)', S.id);
            [~, ord] = sort(key);
        end
        raws = raws(ord);
    end
    fprintf('%s: %d condition recordings, chronological order: %s\n', S.id, ...
        numel(raws), strjoin({raws.condition}, ' -> '));
end

function [first, last] = trimRange(trimSec, fs, nRaw, id, cond)
% raw samples k (1-based) with trimSec(1) <= (k-1)/fs < trimSec(2); NaN = open
% end. Strict: the window must lie inside the recording and keep >= 1 s.
    t0 = trimSec(1); t1 = trimSec(2);
    if isnan(t0), t0 = 0; end
    first = floor(t0 * fs) + 1;
    if isnan(t1)
        last = nRaw;
    else
        assert(t1 * fs <= nRaw, 'assembleRaw_breathingTasks_separate:trim', ...
            '%s %s: trim end %.3f s is beyond the recording (%.3f s)', id, cond, t1, nRaw / fs);
        last = ceil(t1 * fs);
    end
    assert(first >= 1 && last - first + 1 >= fs, 'assembleRaw_breathingTasks_separate:trim', ...
        '%s %s: trim [%g %g] s keeps less than 1 s of the %.3f-s recording', id, cond, ...
        trimSec(1), trimSec(2), nRaw / fs);
end

function n = suffixOf(ncslabels)
% Neuralynx channel-file suffix of this recording: '' -> 0, '_000N' -> N.
% (A capture group nested in an optional non-capturing group returns empty
% tokens in MATLAB even on a match, so the suffix is captured directly.)
    tok = regexp(char(string(ncslabels{1})), '_(\d+)$', 'tokens', 'once');
    if isempty(tok)
        n = 0;
    else
        n = str2double(tok{1});
    end
end

function t = provenanceTime(rd)
% acquisition-folder datetime recovered from the fieldtrip provenance chain
    t = NaT;
    q = {};
    if isfield(rd, 'cfg'), q = {rd.cfg}; end
    depth = 0;
    while ~isempty(q) && depth < 200
        c = q{1}; q(1) = [];
        depth = depth + 1;
        if ~isstruct(c), continue; end
        for f = {'dataset', 'datafile', 'headerfile'}
            if isfield(c, f{1}) && (ischar(c.(f{1})) || isstring(c.(f{1})))
                m = regexp(char(string(c.(f{1}))), '\d{4}-\d{2}-\d{2}_\d{2}-\d{2}-\d{2}', 'match', 'once');
                if ~isempty(m)
                    t = datetime(m, 'InputFormat', 'yyyy-MM-dd_HH-mm-ss');
                    return;
                end
            end
        end
        if isfield(c, 'previous') && ~isempty(c.previous)
            p = c.previous;
            if iscell(p)
                q = [q, p(:)']; %#ok<AGROW>
            elseif isstruct(p)
                for k = 1:numel(p), q{end+1} = p(k); end %#ok<AGROW>
            end
        end
    end
end

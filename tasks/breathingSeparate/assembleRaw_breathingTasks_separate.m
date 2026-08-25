function raws = assembleRaw_breathingTasks_separate(S, P)
%ASSEMBLERAW_BREATHINGTASKS_SEPARATE  Load a session's condition recordings (D12b).
%
%   raws = assembleRaw_breathingTasks_separate(S, P)
%
%   For every in-scope condition row of the session (P.conditions, from
%   applyParams), loads raw\raw_<condition>\raw_<condition>.mat (folder found
%   case-insensitively), requires identical labels and sampling rate across
%   files (error otherwise), and returns a struct array ordered
%   chronologically by recording start (Neuralynx hdr.FirstTimeStamp; errors
%   if unavailable rather than guessing). A single-file session is simply the
%   one-section case.
%
%   Each element: .condition (sheet Task value) .label (D12c canonical:
%   audioBook/audiobook/distractedBreathing -> 'audiobook', rest verbatim)
%   .data .labels .fs_raw .firstTS .srcFile

    rawRoot = fullfile(S.root, S.id, 'raw');
    d = dir(rawRoot);
    dirNames = {d([d.isdir]).name};

    raws = struct('condition', {}, 'label', {}, 'data', {}, 'labels', {}, ...
                  'fs_raw', {}, 'firstTS', {}, 'srcFile', {});
    for c = 1:numel(P.conditions)
        cond = P.conditions{c};
        condNorm = lower(strrep(cond, ' ', ''));
        hit = find(cellfun(@(nm) ~isempty(regexp(lower(nm), ...
              ['^raw_' regexptranslate('escape', condNorm) '\d*$'], 'once')), dirNames));
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
        R.condition = cond;
        R.label     = canonicalCondLabel(cond);
        R.data      = cd0.rawData.trial{1};
        R.labels    = cd0.outLabs;
        R.fs_raw    = cd0.rawData.fsample;
        R.firstTS   = NaN;
        R.srcFile   = fpath;
        if isfield(cd0.rawData, 'hdr')
            h = cd0.rawData.hdr;
            if isfield(h, 'FirstTimeStamp')
                R.firstTS = double(h.FirstTimeStamp);
            elseif isfield(h, 'orig') && isfield(h.orig, 'FirstTimeStamp')
                R.firstTS = double(h.orig.FirstTimeStamp);
            end
        end
        assert(isfinite(R.firstTS), ...
            'assembleRaw_breathingTasks_separate:noTimestamp', ...
            '%s: no Neuralynx FirstTimeStamp in %s - cannot order recordings chronologically (D12b); stop and ask', ...
            S.id, fld);
        if any(isnan(R.data(:)))
            R.data = fillmissing(R.data, 'linear', 2, 'EndValues', 'nearest');
        end
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

    % chronological order by recording start
    [~, ord] = sort([raws.firstTS]);
    raws = raws(ord);
    fprintf('%s: %d condition recordings, chronological order: %s\n', S.id, ...
        numel(raws), strjoin({raws.condition}, ' -> '));
end

function lab = canonicalCondLabel(cond)
    switch lower(strrep(cond, ' ', ''))
        case {'audiobook', 'distractedbreathing'}
            lab = 'audiobook';
        case 'focusedbreathing'
            lab = 'focusedBreathing';
        case 'sleep'
            lab = 'sleep';
        case 'sleepwithodor'
            lab = 'sleepWithOdor';
        case 'restingbaseline'
            lab = 'restingBaseline';
        otherwise
            error('unknown condition "%s"', cond);
    end
end

function raw = assembleRaw_ADmeditation(S, P)
%ASSEMBLERAW_ADMEDITATION  TASK-SPECIFIC raw load for ADmeditation (+ presses, trim).
%
%   raw = assembleRaw_ADmeditation(S, P)   S.id, S.root (from the main loop);
%                                          P.adMedOpts (applyParams)
%
%   ADmeditation recordings have no behavioral file and one marker type (the
%   "good meditative state" button on the event channel), so - like O15 /
%   pacedBreathing - there is no makeOutDat: the raw file written by the
%   study's loader,
%       <root>\raw\<id>_raw.mat   (curDat; root = AD_repeatRecordings),
%   is loaded directly.
%
%   Steps
%     1. load + fill NaN samples (discontinuous Neuralynx read), as pacedBreathing
%     2. detect the button presses on the WHOLE event trace
%        (detectButtonPresses_ADmeditation), before trimming, so a press in a
%        trimmed stretch is still listed (inAnalysisWindow = false)
%     3. TRIM: drop the first P.adMedOpts.trimStartSec (180 s) and the last
%        P.adMedOpts.trimEndSec (60 s) of the recording (user, 2026-10-08).
%        Everything downstream - the shared core, breaths, ECG, the final's
%        sample indices - lives on the trimmed timeline; raw.trim records the
%        mapping (firstRawSample = raw sample that becomes sample 1).
%     4. recording segments (an acquisition stopped and restarted, stitched by
%        the loader) are carried on the trimmed timeline (startSample at fs_raw)
%
%   Returns the fields shared/assembleOutDat.m reads (data / labels / fs_raw /
%   beh; no TTL - the main sets TTL to the presses at the final rate) plus
%   the provenance extras (CSClist, OGdataDir, loadFile, atlasFolder) and
%   presses / pressInfo / trim / segments, which the main carries onto outDat.

    rawFile = fullfile(S.root, 'raw', [S.id '_raw.mat']);
    if ~exist(rawFile, 'file')
        error('assembleRaw_ADmeditation:MissingRaw', ...
            'Expected extracted raw file at %s (run LoadData_ADmeditation_claude.m first).', rawFile);
    end
    tmp = load(rawFile);
    assert(isfield(tmp, 'curDat'), 'assembleRaw_ADmeditation: %s must contain curDat', rawFile);
    dat = tmp.curDat; clear tmp

    data = dat.rawData.trial{1};
    if any(isnan(data(:)))
        nBad = sum(isnan(data(1, :)));
        fprintf('assembleRaw_ADmeditation: filling %d NaN samples (discontinuous Neuralynx read)\n', nBad);
        data = fillmissing(data, 'linear', 2, 'EndValues', 'nearest');
    end
    fs = dat.rawData.fsample;
    labels = dat.outLabs;
    assert(size(data, 1) == numel(labels), ...
        'assembleRaw_ADmeditation: %d data rows vs %d labels', size(data, 1), numel(labels));
    assert(any(cellfun(@(x) contains(x, 'rsp'), labels)), ...
        'assembleRaw_ADmeditation: no respiration (rsp) channel in the raw file');
    evRow = find(strcmp(labels, 'event'));
    assert(isscalar(evRow), 'assembleRaw_ADmeditation: exactly one ''event'' channel expected');

    % ---- 2. button presses on the whole (untrimmed) recording ----
    o = P.adMedOpts;
    [presses, pressInfo] = detectButtonPresses_ADmeditation(data(evRow, :), fs, o.press);

    % ---- 3. trim ----
    nRaw = size(data, 2);
    k0 = round(o.trimStartSec * fs) + 1;
    k1 = nRaw - round(o.trimEndSec * fs);
    assert(k1 - k0 + 1 >= 10 * 60 * fs, ...
        'assembleRaw_ADmeditation: %s is %.1f min - too short to trim %g s + %g s and keep 10 min', ...
        S.id, nRaw / fs / 60, o.trimStartSec, o.trimEndSec);
    data = data(:, k0:k1);
    trim = struct('trimStartSec', o.trimStartSec, 'trimEndSec', o.trimEndSec, ...
                  'rawSamples', nRaw, 'rawDurSec', nRaw / fs, 'fsRaw', fs, ...
                  'firstRawSample', k0, 'lastRawSample', k1, ...
                  'keptDurSec', (k1 - k0 + 1) / fs, ...
                  'note', ['first trimStartSec and last trimEndSec of the recording dropped ' ...
                           'before processing; final sample s <-> raw sample s - 1 + firstRawSample ' ...
                           '(at fsRaw; divide by origFS/fs for the final rate)']);
    presses.inAnalysisWindow = presses.onsetRaw >= k0 & presses.onsetRaw <= k1;
    presses.onsetTrim   = presses.onsetRaw - k0 + 1;      % on the trimmed raw timeline
    presses.releaseTrim = presses.releaseRaw - k0 + 1;
    presses.onsetTrim(~presses.inAnalysisWindow) = NaN;
    presses.releaseTrim(~presses.inAnalysisWindow | presses.releaseRaw > k1) = NaN;

    % ---- 4. segments on the trimmed timeline ----
    raw = struct();
    if isfield(dat, 'segments') && istable(dat.segments) && height(dat.segments) > 0
        sg = dat.segments;
        segEnd = sg.startSample + sg.nSamples - 1;
        keep = segEnd >= k0 & sg.startSample <= k1;
        sg = sg(keep, :);
        sg.startSample = max(sg.startSample - k0 + 1, 1);
        sg.nSamples = [diff(sg.startSample); size(data, 2) - sg.startSample(end) + 1];
        raw.segments = sg;
    end

    raw.sessID    = S.id;
    raw.fs_raw    = fs;
    raw.data      = data;
    raw.labels    = labels;
    raw.beh       = table();          % no behavioral file for this task
    raw.CSClist   = dat.ncslabels;
    raw.atlasFolder = dat.atlasFolder;
    raw.OGdataDir = fullfile(S.root, dat.atlasFolder);
    raw.loadFile  = findLoadDataScript(S.root, 'ADmeditation', dat);
    raw.presses   = presses;
    raw.pressInfo = pressInfo;
    raw.trim      = trim;
end

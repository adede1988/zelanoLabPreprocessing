function raw = assembleRaw_vipassana(S)
%ASSEMBLERAW_VIPASSANA  TASK-SPECIFIC raw load for vipassana.
%
%   raw = assembleRaw_vipassana(S)   S.id, S.root (from the main loop)
%
%   vipassana recordings are single BrainVision (actiCHamp) files with no
%   photodiode/behavioral file and only hand-pressed, incomplete period-
%   transition button presses, so (like O15 / pacedBreathing) there is no
%   makeOutDat step: the extracted raw file written by the session's
%   LoadData script,
%       <root>\<id>\raw\raw_vipassana\raw_vipassana.mat  (curDat),
%   is loaded directly. Block structure (audiobook / meditation /
%   questionnaire periods) is inferred later in the main from the raw scalp
%   EEG activity evidence (inferBlocks_vipassana), so no TTL is returned
%   here (assembleOutDat's TTL passthrough is data-driven on the field).
%
%   35 raw channels, in the LoadData script's fixed order: rows 1-32 the
%   standard 32-ch montage with Cz INSERTED as an all-zero row (Cz is the
%   BrainVision recording reference, so its potential relative to itself is
%   0 - see vipassana_design.md section 1 / 3a), then ECG1 (contains 'ECG'),
%   rsp1 (contains 'rsp'), event (the photodiode input; carries no events in
%   this task, kept only for structural parity with the other tasks).
%
%   Returns the fields shared/assembleOutDat.m reads (data / labels / fs_raw /
%   beh) plus:
%     - the O15/pacedBreathing-style provenance extras (CSClist, OGdataDir,
%       loadFile) the main copies onto outDat;
%     - vipassana-specific extras the main also copies onto outDat: markers
%       (table of every marker incl. 'New Segment', at the RAW sampling rate
%       - the main filters to Stimulus presses and converts to 500 Hz),
%       header (the parsed .vhdr struct, incl. recStart) and refChan ('Cz').

    rawFile = fullfile(S.root, S.id, 'raw', 'raw_vipassana', 'raw_vipassana.mat');
    if ~exist(rawFile, 'file')
        error('assembleRaw_vipassana:MissingRaw', ...
            'Expected extracted raw file at %s (run the session''s LoadData script first).', rawFile);
    end
    tmp = load(rawFile);
    assert(isfield(tmp, 'curDat'), 'assembleRaw_vipassana: %s must contain curDat', rawFile);
    dat = tmp.curDat; clear tmp

    data = dat.rawData.trial{1};
    if any(isnan(data(:)))
        nBad = sum(any(isnan(data), 1));
        fprintf('assembleRaw_vipassana: filling %d NaN samples\n', nBad);
        data = fillmissing(data, 'linear', 2, 'EndValues', 'nearest');
    end

    raw = struct();
    raw.sessID    = S.id;
    raw.fs_raw    = dat.rawData.fsample;
    raw.data      = data;
    raw.labels    = dat.outLabs;
    raw.beh       = table();          % no behavioral file for this task
    raw.CSClist   = dat.ncslabels;
    raw.OGdataDir = fullfile(S.root, S.id);

    % vipassana-specific provenance the main copies onto outDat
    if isfield(dat, 'markers') && istable(dat.markers), raw.markers = dat.markers; else, raw.markers = table(); end
    if isfield(dat, 'header')  && isstruct(dat.header),  raw.header  = dat.header;  else, raw.header  = struct(); end
    raw.refChan = '';
    if isfield(dat, 'refChan'), raw.refChan = char(string(dat.refChan)); end

    % which LoadData script produced the raw file (provenance, as in
    % O15/pacedBreathing; shared lookup - curDat.loadFile first, never fatal)
    raw.loadFile = findLoadDataScript(raw.OGdataDir, 'vipassana', dat);

    % ---- asserts (Prefer strict: loud errors on unexpected raw shape) ----
    assert(size(raw.data, 1) == numel(raw.labels), ...
        'assembleRaw_vipassana: %d data rows vs %d labels', size(raw.data, 1), numel(raw.labels));
    assert(numel(raw.labels) == 35, ...
        ['assembleRaw_vipassana: expected 35 channels (32 EEG incl. inserted Cz + ' ...
         'ECG1 + rsp1 + event), got %d'], numel(raw.labels));

    L = labPaths();
    eegLocs = readtable(L.eegLocCsv);
    stdLabs = string(eegLocs.Label(:))';
    gotLabs = string(raw.labels(1:32));
    assert(isequal(gotLabs, stdLabs), ...
        ['assembleRaw_vipassana: rows 1-32 must be the standard 32-ch montage (with Cz ' ...
         'inserted) in order; got %s'], strjoin(gotLabs, ' '));

    assert(any(cellfun(@(x) contains(x, 'ECG'), raw.labels)), ...
        'assembleRaw_vipassana: no ECG channel in the raw file');
    assert(any(cellfun(@(x) contains(x, 'rsp'), raw.labels)), ...
        'assembleRaw_vipassana: no respiration (rsp) channel in the raw file');
end

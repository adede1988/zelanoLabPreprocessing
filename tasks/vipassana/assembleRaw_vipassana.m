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
%   That evidence (artifactIndex_vipassana) is computed HERE, on the raw,
%   UN-NOTCHED scalp rows, before the line-noise notch below, and returned
%   as raw.artifactIndex for the main: it needs the pre-cleaning EEG (its
%   line-dominated-row exclusion is part of its design), and feeding it the
%   notched rows changed the inferred blocks (tested 2026-09-27 on the three
%   sessions: 260918_EEG_NWU_DD's audiobook1 moved from 153-476 s to
%   479-693 s, anapana shrank to 11.7 min on the unused 11.60-min press and
%   audiobook2 started 95 s from its press; CC's unmarked audiobook1 start
%   moved 60 s; AS within 2 s). Computing it here keeps the approved
%   segmentation exactly as before the notch was added.
%
%   35 raw channels, in the LoadData script's fixed order: rows 1-32 the
%   standard 32-ch montage with Cz INSERTED as an all-zero row (Cz is the
%   BrainVision recording reference, so its potential relative to itself is
%   0 - see vipassana_design.md section 1 / 3a), then ECG1 (contains 'ECG'),
%   rsp1 (contains 'rsp'), event (the photodiode input; carries no events in
%   this task, kept only for structural parity with the other tasks).
%
%   LINE-NOISE NOTCH AT INGESTION (added 2026-09-27; TASK-SPECIFIC). The 32
%   scalp rows (rows 1-32 ONLY; ECG1 / rsp1 / event untouched) are notched at
%   60, 120 and 180 Hz before returning, with the lab's off-the-shelf design:
%   designfilt('bandstopiir', FilterOrder 2, HalfPowerFrequency1/2 = f-1 / f+1,
%   DesignMethod 'butter', SampleRate = the raw fs), applied zero-phase with
%   filtfilt (the ~2-Hz-wide stop band of the pipeline's former 60/120/180-Hz
%   notch). Why here and not in the shared core: the actiCHamp dry
%   electrodes carry heavy 60-Hz pickup, and the shared core's bad-channel
%   detector (removeNoiseChansVolt: amplitude rules on the unfiltered data)
%   then flags channels for LINE NOISE rather than for bad electrode contact
%   - before this notch it flagged 22 of 260918_EEG_NWU_DD's 32 channels
%   (leaving 10, so preprocess_eeg took its <=10-channel branch: no
%   Laplacian) and put nearly all of its first audiobook in badTS (87.6 % of
%   the samples, 154 of 161 2-s windows). With the notch (re-run 2026-09-27)
%   DD's badChans are Cz only, its still-block badTS 0.2 %, dataLap is
%   computed again; AS 6 -> 4 and CC 12 -> 8 badChans, same blocks, breaths
%   and beats in all three. The shared core keeps NO notch by design (the Atlas
%   rigs; downsample_data's notch was removed in July 2026), so this task
%   notches at ingestion instead and the shared core is not edited. The
%   inserted all-zero Cz row stays exactly zero (a linear filter of zeros).
%   raw.notchHz / raw.notchNote record it; the main copies them onto outDat.
%   Everything downstream of this function (the shared core, the stored
%   outDat.data rows 1-32, dataLap) sees the notched scalp rows; only the
%   activity evidence above is computed on the un-notched ones.
%
%   Returns the fields shared/assembleOutDat.m reads (data / labels / fs_raw /
%   beh) plus:
%     - the O15/pacedBreathing-style provenance extras (CSClist, OGdataDir,
%       loadFile) the main copies onto outDat;
%     - vipassana-specific extras the main also copies onto outDat: markers
%       (table of every marker incl. 'New Segment', at the RAW sampling rate
%       - the main filters to Stimulus presses and converts to 500 Hz),
%       header (the parsed .vhdr struct, incl. recStart), refChan ('Cz'),
%       notchHz ([60 120 180]) and notchNote (the notch provenance string);
%     - artifactIndex: the activity-evidence table of the UN-NOTCHED scalp
%       rows (artifactIndex_vipassana at the raw fs), which the main stores
%       as outDat.artifactIndex and segments with inferBlocks_vipassana.

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

    % ---- activity evidence on the RAW, UN-NOTCHED scalp rows (see header) ----
    % assembleOutDat copies data / fs_raw unchanged and the raw fs is already
    % the 500-Hz target, so this is the same call the main made on
    % outDat.data(1:32,:) before the notch existed.
    raw.artifactIndex = artifactIndex_vipassana(raw.data(1:32, :), raw.fs_raw);

    % ---- line-noise notch of the 32 scalp rows (see header) ----
    raw.notchHz = [60 120 180];
    assert(max(raw.notchHz) + 1 < raw.fs_raw / 2, ...
        'assembleRaw_vipassana: notch at %g Hz needs fs > %g Hz (raw fs = %g)', ...
        max(raw.notchHz), 2 * (max(raw.notchHz) + 1), raw.fs_raw);
    for f = raw.notchHz
        d = designfilt('bandstopiir', 'FilterOrder', 2, ...
            'HalfPowerFrequency1', f - 1, 'HalfPowerFrequency2', f + 1, ...
            'DesignMethod', 'butter', 'SampleRate', raw.fs_raw);
        for ch = 1:32                     % one row at a time (memory)
            raw.data(ch, :) = filtfilt(d, double(raw.data(ch, :)));
        end
    end
    raw.notchNote = sprintf(['assembleRaw_vipassana: scalp rows 1-32 notched at %s Hz ' ...
        '(designfilt bandstopiir, order 2, f-1..f+1 Hz, butter, fs %g Hz, filtfilt) at ingestion, ' ...
        'before the shared core; ECG/rsp/event rows untouched'], mat2str(raw.notchHz), raw.fs_raw);
end

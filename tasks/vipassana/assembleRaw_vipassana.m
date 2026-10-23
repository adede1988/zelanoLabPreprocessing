function raw = assembleRaw_vipassana(S, P)
%ASSEMBLERAW_VIPASSANA  TASK-SPECIFIC raw load for vipassana.
%
%   raw = assembleRaw_vipassana(S, P)   S.id, S.root (from the main loop);
%                                       P from applyParams (P.vipOpts)
%
%   vipassana recordings are single BrainVision (actiCHamp) files with no
%   makeOutDat step (like O15 / pacedBreathing): the extracted raw file
%   written by the session's LoadData script,
%       <root>\<id>\raw\raw_vipassana\raw_vipassana.mat  (curDat),
%   is loaded directly. Two protocol versions (P.vipOpts.protocol, set per
%   session by applyParams):
%
%   v1 - 260918_EEG_NWU_AS / CC / DD (unmarked; behaviour unchanged since
%   2026-09-27). Block structure (audiobook / meditation / questionnaire
%   periods) is inferred later in the main from the raw scalp EEG activity
%   evidence (inferBlocks_vipassana), so no TTL is returned here
%   (assembleOutDat's TTL passthrough is data-driven on the field). That
%   evidence (artifactIndex_vipassana) is computed HERE, on the raw,
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
%   v2 - every session from 2026-09-27 on (audiobook1 / paced1 / audiobook2 /
%   anapana / vipassana / metta / paced2 protocol, see blocksFromMarks_
%   vipassana). The blocks are MARKED, not inferred:
%     - photodiode: the PsychoPy script draws a white square under the
%       sensor during every block, so the 'event' row (BrainVision
%       'photoDiode') is parsed HERE (parsePhotodiode_vipassana -> raw.
%       photodiode), on the unfiltered trace - the shared core's 0.03-Hz
%       high-pass (time constant ~5 s) would decay the 5-15-min plateaus;
%     - SniffLogic log: when <root>\<id>\behavioralDat holds a
%       *sniffLogicLog*.csv (exactly one; strict), it is parsed
%       (parseLog_vipassana: block identities, the pressure the logger
%       recorded, the paced-breathing target) and its clock mapped onto the
%       recording by aligning its pressure trace with the recording's
%       respiration channel (alignLog_vipassana: the BrainVision 'Resp'
%       input is the analog output of the same sensor) -> raw.sniffLogic;
%       the aligned log pressure is appended as an extra respiration row
%       'rspSniffLogic' (Pa, inhale-POSITIVE, 500-Hz grid, held at the first /
%       last logged value where the log does not cover the recording -
%       raw.sniffLogic.coverage; rsp index 2 - select it with sheet
%       rspIDX 2 / rspFlip 1 if a session's BrainVision trace is unusable),
%       and the target trace the participant followed is returned as
%       raw.targTrace (Pa, 0 outside the sweeps; the main appends it as the
%       'targTrace' row after the shared core, like breathingTask);
%     - respiration filter: the BrainVision 'Resp' input carries heavy
%       60-Hz pickup in every v2 recording (and broadband noise), so rsp1 is
%       low-passed at ingestion: 4th-order Butterworth at
%       P.vipOpts.rspLowpassHz (5 Hz), zero-phase (filtfilt) - breathing
%       lives below ~2 Hz and the inhale upstroke below ~5 Hz; 60 Hz is
%       attenuated > 150 dB. raw.rspFilterNote records it;
%     - activity evidence (artifactIndex_vipassana) is still computed, as a
%       QC trace only (the v2 blocks do not use it);
%     - ECG notch (P.vipOpts.ecgNotchHz = [60 120 180]; the same design as
%       the v1 EEG notch, ECG1 row only): the v2 ECG input carries 60-Hz
%       pickup hundreds of times its 10-Hz power, and the ripple the shared
%       5-40 Hz band-pass leaves locks the detected beat times to the line
%       cycle (probe 2026-10-20: IBI phase concentration at 1/60 s 0.17-0.58
%       in 6 of 7 sessions, <= 0.03 notched; 260927_EEG_NWU_BM RMSSD 82 vs
%       20 ms). raw.ecgNotchHz / raw.ecgNotchNote record it;
%     - NO line-noise notch (P.vipOpts.notchHz = []; user: no notch unless
%       necessary): the v2 EEG carries a flat broadband noise floor (~1-5
%       uV^2/Hz up to the amplifier's 140-Hz cutoff, 10-20x the v1
%       recordings'), so the shared detector (lab default 'fixed' mode)
%       flags every channel whether notched or not (probe 2026-10-20) -
%       a notch cannot rescue it, unlike v1 where 60 Hz was the cause.
%
%   35 raw channels from the LoadData script (both versions), in a fixed
%   order: rows 1-32 the standard 32-ch montage with Cz INSERTED as an
%   all-zero row (Cz is the BrainVision recording reference, so its
%   potential relative to itself is 0), then ECG1 (contains 'ECG'), rsp1
%   (contains 'rsp'), event (the photodiode input; carries no events in v1).
%   v2 sessions with a log get the 36th row 'rspSniffLogic'.
%
%   LINE-NOISE NOTCH AT INGESTION (v1 only, P.vipOpts.notchHz = [60 120
%   180]; added 2026-09-27). The 32 scalp rows (rows 1-32 ONLY; ECG1 / rsp1
%   / event untouched) are notched before returning, with the lab's
%   off-the-shelf design: designfilt('bandstopiir', FilterOrder 2,
%   HalfPowerFrequency1/2 = f-1 / f+1, DesignMethod 'butter', SampleRate =
%   the raw fs), applied zero-phase with filtfilt. Why: the v1 actiCHamp dry
%   electrodes carry heavy 60-Hz pickup, and the shared core's bad-channel
%   detector (removeNoiseChansVolt: amplitude rules on the unfiltered data)
%   then flagged channels for LINE NOISE rather than for bad electrode
%   contact - before this notch it flagged 22 of 260918_EEG_NWU_DD's 32
%   channels and put nearly all of its first audiobook in badTS. With the
%   notch (re-run 2026-09-27) DD's badChans are Cz only, AS 6 -> 4 and CC 12
%   -> 8 badChans, same blocks, breaths and beats in all three. The shared
%   core keeps NO notch by design, so this task notches at ingestion
%   instead. raw.notchHz / raw.notchNote record what was done (notchHz = []
%   for v2).
%
%   AVERAGE REFERENCE (both versions, P.vipOpts.avgRef = true; added
%   2026-10-21, user: the EEG should be average-referenced before cleaning).
%   The BrainVision recording reference is Cz, so as recorded every scalp row
%   is "electrode - Cz" and Cz is the all-zero row. After the activity
%   evidence above (v1's approved block inference keeps its recording-
%   reference input) and the v1 notch, the 32 rows are re-referenced to a
%   robust common average (shared/robustAvgRef: rows that read flat in the
%   recording reference - dead / railed inputs - and rows that are robust
%   outliers in more than 1 % of 2-s windows are kept out of the mean; every
%   row is re-referenced except in its flat windows, which stay flat for the
%   shared detector), which recovers Cz as a real channel (Cz_avg = -mean of
%   the reference set) and cancels noise common to every row as recorded
%   (e.g. carried by the Cz electrode itself; probe 2026-10-21, 60 s
%   mid-vipassana, 70-110 Hz floor: the average reference removes 88 % of
%   261016_EEG_NWU_NE's and 73 % of 261018_EEG_NWU_VL's). raw.avgRef records
%   the reference set, the excluded rows with their reasons and the per-row
%   statistics. With avgRef false the rows stay
%   in the recording reference and the main re-zeroes the Cz row after the
%   shared core (the pre-2026-10-21 behaviour).
%
%   Returns the fields shared/assembleOutDat.m reads (data / labels / fs_raw /
%   beh) plus the provenance extras (CSClist, OGdataDir, loadFile), markers
%   (every BrainVision marker incl. 'New Segment', raw fs), header (parsed
%   .vhdr incl. recStart), refChan ('Cz', the RECORDING reference), avgRef,
%   notchHz / notchNote, artifactIndex, protocol ('v1'/'v2'), acqSegments (the LoadData script's
%   acquisition-segment table in .eeg file samples, when present) and, for v2, photodiode,
%   sniffLogic ([] without a log), targTrace ([] without a log),
%   rspFilterHz / rspFilterNote and behFiles (the behavioralDat listing).

    vo = P.vipOpts;
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
    raw.protocol  = vo.protocol;
    raw.fs_raw    = dat.rawData.fsample;
    raw.data      = data;
    raw.labels    = dat.outLabs;
    raw.beh       = table();          % behavior lives in outDat.blocks / behDat (built by the main)
    raw.CSClist   = dat.ncslabels;
    raw.OGdataDir = fullfile(S.root, S.id);

    % vipassana-specific provenance the main copies onto outDat
    if isfield(dat, 'markers') && istable(dat.markers), raw.markers = dat.markers; else, raw.markers = table(); end
    if isfield(dat, 'header')  && isstruct(dat.header),  raw.header  = dat.header;  else, raw.header  = struct(); end
    raw.refChan = '';
    if isfield(dat, 'refChan'), raw.refChan = char(string(dat.refChan)); end
    % the LoadData script's acquisition segments (file samples, incl. dropped
    % ones) - NOT the seam table other tasks call outDat.segments
    if isfield(dat, 'segments'), raw.acqSegments = dat.segments; end

    % which LoadData script produced the raw file (provenance, as in
    % O15/pacedBreathing; shared lookup - curDat.loadFile first, never fatal)
    raw.loadFile = findLoadDataScript(raw.OGdataDir, 'vipassana', dat);

    % ---- asserts (Prefer strict: loud errors on unexpected raw shape) ----
    assert(size(raw.data, 1) == numel(raw.labels), ...
        'assembleRaw_vipassana: %d data rows vs %d labels', size(raw.data, 1), numel(raw.labels));
    assert(numel(raw.labels) == 35, ...
        ['assembleRaw_vipassana: expected 35 channels (32 EEG incl. inserted Cz + ' ...
         'ECG1 + rsp1 + event), got %d'], numel(raw.labels));
    assert(isequal(cellstr(string(raw.labels(33:35))), {'ECG1', 'rsp1', 'event'}), ...
        'assembleRaw_vipassana: rows 33-35 must be ECG1 rsp1 event, got %s', strjoin(cellstr(string(raw.labels(33:35))), ' '));

    L = labPaths();
    eegLocs = readtable(L.eegLocCsv);
    stdLabs = string(eegLocs.Label(:))';
    gotLabs = string(raw.labels(1:32));
    assert(isequal(gotLabs, stdLabs), ...
        ['assembleRaw_vipassana: rows 1-32 must be the standard 32-ch montage (with Cz ' ...
         'inserted) in order; got %s'], strjoin(gotLabs, ' '));

    % ---- activity evidence on the RAW, UN-NOTCHED scalp rows (see header) ----
    % assembleOutDat copies data / fs_raw unchanged and the raw fs is already
    % the 500-Hz target, so this is the same call the main made on
    % outDat.data(1:32,:) before the notch existed.
    raw.artifactIndex = artifactIndex_vipassana(raw.data(1:32, :), raw.fs_raw);

    % ---- line-noise notch of the 32 scalp rows (v1; see header) ----
    raw.notchHz = vo.notchHz(:)';
    if ~isempty(raw.notchHz)
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
    else
        raw.notchNote = ['assembleRaw_vipassana: no line-noise notch (protocol ' vo.protocol ...
            '; the shared detector runs in P.eegClean.mode ''' eegMode(P) ''')'];
    end

    % ---- common-average reference of the 32 scalp rows, Cz recovered (see header) ----
    if isfield(vo, 'avgRef') && vo.avgRef
        arOpts = struct();
        if isfield(vo, 'avgRefOpts'), arOpts = vo.avgRefOpts; end
        [raw.data(1:32, :), raw.avgRef] = robustAvgRef(raw.data(1:32, :), raw.labels(1:32), raw.fs_raw, arOpts);
        raw.avgRef.applied = true;
        raw.avgRef.recordingRef = raw.refChan;
        fprintf('%s\n', raw.avgRef.note);
    else
        raw.avgRef = struct('applied', false, 'recordingRef', raw.refChan, ...
            'note', 'assembleRaw_vipassana: scalp rows left in the recording reference (Cz = all-zero row)');
    end

    % ---- ECG line-noise notch (v2; see header) ----
    raw.ecgNotchHz = [];
    if isfield(vo, 'ecgNotchHz'), raw.ecgNotchHz = vo.ecgNotchHz(:)'; end
    if ~isempty(raw.ecgNotchHz)
        ecgRow = find(strcmp(cellstr(string(raw.labels)), 'ECG1'));
        assert(isscalar(ecgRow), 'assembleRaw_vipassana: exactly one ECG1 row expected');
        for f = raw.ecgNotchHz
            d = designfilt('bandstopiir', 'FilterOrder', 2, ...
                'HalfPowerFrequency1', f - 1, 'HalfPowerFrequency2', f + 1, ...
                'DesignMethod', 'butter', 'SampleRate', raw.fs_raw);
            raw.data(ecgRow, :) = filtfilt(d, double(raw.data(ecgRow, :)));
        end
        raw.ecgNotchNote = sprintf(['assembleRaw_vipassana: ECG1 notched at %s Hz (designfilt bandstopiir, order 2, ' ...
            'f-1..f+1 Hz, butter, filtfilt) at ingestion - residual line ripple after the shared 5-40 Hz band-pass ' ...
            'locked beat times to the 60-Hz cycle'], mat2str(raw.ecgNotchHz));
    else
        raw.ecgNotchNote = 'assembleRaw_vipassana: ECG1 not notched';
    end

    if strcmp(vo.protocol, 'v1'), return; end

    % ===================== v2: marked blocks =====================
    fs = raw.fs_raw;
    N = size(raw.data, 2);
    rspRow = 34; evRow = 35;

    % ---- photodiode (unfiltered event row) ----
    raw.photodiode = parsePhotodiode_vipassana(raw.data(evRow, :), fs, vo.photodiode);

    % ---- behavioral files ----
    behDir = fullfile(S.root, S.id, 'behavioralDat');
    bf = dir(fullfile(behDir, '*'));
    bf = bf(~[bf.isdir]);
    raw.behFiles = string({bf.name})';
    logF = dir(fullfile(behDir, '*sniffLogicLog*.csv'));
    assert(numel(logF) <= 1, 'assembleRaw_vipassana:manyLogs', ...
        '%s: %d SniffLogic logs in %s - one per session expected', S.id, numel(logF), behDir);

    % ---- SniffLogic log: identities, aligned pressure, target ----
    raw.sniffLogic = [];
    raw.targTrace = [];
    if isscalar(logF)
        LG = struct();
        LG.file = fullfile(logF.folder, logF.name);
        LG.log = parseLog_vipassana(LG.file);
        LG.align = alignLog_vipassana(LG.log, raw.data(rspRow, :), fs, vo.logAlign);
        A = LG.align;
        tRawSec = (0:N - 1) / fs;
        tLogAtRaw = (tRawSec - A.intercept) / (1 + A.slope);
        % aligned log pressure on the recording's grid (Pa, inhale-positive)
        pAl = interp1(LG.log.t, LG.log.p, tLogAtRaw, 'linear', NaN);
        covered = isfinite(pAl);
        c0 = find(covered, 1, 'first'); c1 = find(covered, 1, 'last');
        LG.coverage = [c0, c1];
        LG.coverageNote = sprintf(['rspSniffLogic covers samples %d-%d of %d; held at the first / last logged ' ...
            'value outside (no step for the shared high-pass to spread)'], c0, c1, N);
        pAl(1:c0 - 1) = pAl(c0);
        pAl(c1 + 1:end) = pAl(c1);
        % paced-breathing target (Pa) inside each sweep, 0 elsewhere
        tg = zeros(1, N);
        sw = LG.log.blocks(startsWith(lower(LG.log.blocks.name), "sweep"), :);
        for k = 1:height(sw)
            te = sw.tEnd(k); if ~isfinite(te), te = LG.log.t(end); end
            inS = LG.log.tTarget >= sw.tStart(k) & LG.log.tTarget <= te;
            if nnz(inS) < 2, continue; end
            tt = LG.log.tTarget(inS); vv = LG.log.target(inS);
            m = tLogAtRaw >= tt(1) & tLogAtRaw <= tt(end);
            tg(m) = interp1(tt, vv, tLogAtRaw(m), 'linear');
        end
        raw.targTrace = tg;
        % target cycles on the recording (cycle start sample)
        SB = LG.log.sweepBreaths;
        SB.sample = round((A.intercept + (1 + A.slope) * SB.t) * fs) + 1;
        LG.log.sweepBreaths = SB;
        % the log's block times on the recording (s), for QC
        LB = LG.log.blocks;
        LB.rawStartSec = A.intercept + (1 + A.slope) * LB.tStart;
        LB.rawEndSec = A.intercept + (1 + A.slope) * LB.tEnd;
        LG.log.blocks = LB;
        % keep the struct small: the raw pressure lives in the rspSniffLogic row
        LG.log = rmfield(LG.log, {'t', 'p', 'tTarget', 'target'});
        raw.sniffLogic = LG;
        raw.data(end + 1, :) = pAl;
        raw.labels{end + 1} = 'rspSniffLogic';
        raw.CSClist{end + 1} = 'SniffLogic pressure_pa (aligned log)';
    end
    pf = dir(fullfile(behDir, '*mindfulBreathing*.csv'));
    raw.psychopyFiles = string({pf.name})';

    % ---- respiration filter (rsp1; see header) ----
    raw.rspFilterHz = vo.rspLowpassHz;
    if ~isempty(vo.rspLowpassHz)
        [b, a] = butter(4, vo.rspLowpassHz / (fs / 2), 'low');
        x = double(raw.data(rspRow, :));
        mu = median(x);
        raw.data(rspRow, :) = filtfilt(b, a, x - mu) + mu;
        raw.rspFilterNote = sprintf(['assembleRaw_vipassana: rsp1 (BrainVision Resp) low-passed at ingestion: ' ...
            '4th-order Butterworth %g Hz, filtfilt (60-Hz pickup)'], vo.rspLowpassHz);
    else
        raw.rspFilterNote = 'assembleRaw_vipassana: rsp1 not filtered at ingestion';
    end
end

function m = eegMode(P)
    m = 'fixed';
    if isfield(P, 'eegClean') && isstruct(P.eegClean) && isfield(P.eegClean, 'mode'), m = P.eegClean.mode; end
end

%% LoadData_ADmeditation_claude.m
% ONE loader for every recording in AllStudyData\AD_repeatRecordings (Adam's
% repeated meditation sessions, task ADmeditation in zelanoLabPreprocessing).
% It lives in that folder and, each time it is run:
%   1. finds the Atlas date-stamp folders (yyyy-mm-dd_hh-mm-ss) in this folder;
%   2. skips every recording that is already imported (raw\<sessID>_raw.mat
%      exists) - so it only ever extracts the NEW ones;
%   3. extracts the channels below from each new recording, stitching
%      acquisition segments (CSCn.ncs, CSCn_0001.ncs, ...) end to end;
%   4. writes raw\<sessID>_raw.mat (curDat, the lab's raw layout) and adds /
%      updates the session's row in Admin\Data\dataTracking_AD_meditation.xlsx
%      (created on the first run). These sessions are NOT tracked in
%      dataTracking.xlsx.
% Then run zelanoLabPreprocessing\pipelines\ADmeditationPreProc_main.m.
%
% Session ID: <yymmdd>_ADmed_<hhmm> from the date-stamp folder, e.g.
% 2026-06-12_09-22-52 -> 260612_ADmed_0922.
%
% Segments: Pegasus starts a new file set (suffix _0001, _0002, ...) whenever
% acquisition is restarted; most of these recordings hold the data in one set
% and leave header-only or few-ms stubs in the others. Segments shorter than
% minSegSec are ignored; longer ones are concatenated in order (the lab's
% run-stitching convention, no gap samples) and recorded in curDat.segments.
% A recording with no segment >= minSegSec is listed in the sheet as empty
% (Raw Data Extracted blank, a note) and not extracted.
%
%% Channel correspondence (Zelano_EEGbreathing.cfg rig; verified 2026-10-08
%% with batch/probeMontage on 2026-06-12 and 2026-09-25 - identical map)
% CSC33:64     - EEG (10-20 order, 32 ch)
% CSC25/26/27  - ECG1/2/3 (CSC26 is unconnected on this setup; kept for the
%                standard layout - the pipeline's beatSpec uses ECG3 = CSC27,
%                whose R wave is negative in every session)
% CSC31        - respiration (rsp1; inhale DOWN as recorded -> rspFlip -1)
% CSC32        - rsp2, inverted duplicate of CSC31
% CSC269       - event: the "good meditative state" button (a ~5-s pulse,
%                AC-coupled, under heavy 60-Hz pickup; detected in the pipeline)
%
% Written 2026-10-08 (Claude). Requires FieldTrip (ft_read_header) and the
% lab's ReadNCS (Lab_Common\Matlab_Code), as the other LoadData scripts.

%% path specification and fieldtrip start
clear
if exist('E:\GitHub\fieldtrip-20230118', 'dir')
    addpath('E:\GitHub\fieldtrip-20230118')   % lab desktop
else
    addpath('G:\My Drive\GitHub\fieldtrip-20230118')
end
addpath('R:\Neurology\Zelano_Lab\Lab_Common\Matlab_Code')   % ReadNCS
ft_defaults

%% settings (edit as needed)
rootDir = fileparts(mfilename('fullpath'));                 % = AD_repeatRecordings
if isempty(rootDir), rootDir = 'R:\Neurology\Zelano_Lab\Lab_Common\AllStudyData\AD_repeatRecordings'; end
lc = regexp(rootDir, '^(.*Lab_Common)', 'tokens', 'once');
assert(~isempty(lc), 'LoadData_ADmeditation: %s is not under Lab_Common', rootDir);
sheetPath = fullfile(lc{1}, 'Admin', 'Data', 'dataTracking_AD_meditation.xlsx');
if ~isempty(getenv('ZLP_ADMED_XLSX')), sheetPath = getenv('ZLP_ADMED_XLSX'); end   % staging copy (as labPaths)
rawDir = fullfile(rootDir, 'raw');
minSegSec = 60;            % shorter acquisition segments are stubs, not data
reimport = {};             % session IDs to extract again even if their raw file exists

CSClist = [arrayfun(@(x) ['CSC' num2str(x)], 33:64, 'uniformoutput', false), ...
           {'CSC25', 'CSC26', 'CSC27', 'CSC31', 'CSC32', 'CSC269'}];
ReadableLabs = {'Fp1', 'Fz' , 'F3' , 'F7' , 'FT9', 'FC5', 'FC1', ...
                'C3' , 'T7' , 'TP9', 'CP5', 'CP1', 'Pz' , 'P3' , ...
                'P7' , 'O1' , 'Oz' , 'O2' , 'P4' , 'P8' , 'TP10',...
                'CP6', 'CP2', 'Cz' , 'C4' , 'T8' ,'FT10', 'FC6', ...
                'FC2', 'F4' , 'F8' , 'Fp2', ...
                'ECG1', 'ECG2', 'ECG3', ...
                'rsp1', 'rsp2', 'event'};
assert(numel(CSClist) == numel(ReadableLabs), 'channel list and labels differ in length');

hdrNames = {'Subject ID', 'Task', 'Type', 'dataType', 'Atlas Folder', 'Recording Date', ...
            'Start Time', 'Segments', 'Raw Duration (min)', 'Raw Data Extracted', 'Extraction Date', ...
            'Analyzed Duration (min)', 'nButtonPresses', 'nPressesTrimmed', 'nBreaths', 'meanHR (bpm)', ...
            'Data Preprocessed', 'datPre', 'rspIDX', 'rspFlip', 'hasEEG', 'hasMacros', 'spikeClean', ...
            'beatSpec', 'paramSource', 'Notes'};

%% find recordings and the ones not yet imported
if ~exist(rawDir, 'dir'), mkdir(rawDir); end
if ~exist(fullfile(rootDir, 'preProc'), 'dir'), mkdir(fullfile(rootDir, 'preProc')); end
ensureSheet(sheetPath, hdrNames);
d = dir(rootDir);
d = d([d.isdir] & ~cellfun('isempty', regexp({d.name}, '^\d{4}-\d{2}-\d{2}_\d{2}-\d{2}-\d{2}$', 'once')));
fprintf('%d recording folders in %s\n', numel(d), rootDir);

warning('off', 'all')
for i = 1:numel(d)
    atlas = d(i).name;
    stamp = datetime(atlas, 'InputFormat', 'yyyy-MM-dd_HH-mm-ss');
    sessID = sprintf('%s_ADmed_%s', char(stamp, 'yyMMdd'), char(stamp, 'HHmm'));
    rawFile = fullfile(rawDir, [sessID '_raw.mat']);
    if exist(rawFile, 'file') && ~any(strcmpi(reimport, sessID))
        fprintf('%s (%s): already imported\n', sessID, atlas);
        continue
    end
    recDir = fullfile(rootDir, atlas);

    % ---- acquisition segments from the respiration channel's files ----
    f31 = dir(fullfile(recDir, 'CSC31*.ncs'));
    suf = regexp({f31.name}, '^CSC31(_\d{4})?\.ncs$', 'tokens', 'once');
    ok = ~cellfun('isempty', suf);
    f31 = f31(ok); suf = cellfun(@(c) c{1}, suf(ok), 'uniformoutput', false);
    [suf, o] = sort(suf); f31 = f31(o);                     % '' < '_0001' < '_0002'
    segSec = zeros(1, numel(f31));
    for s = 1:numel(f31)
        segSec(s) = ncsDurationSec(fullfile(recDir, f31(s).name));
    end
    segInfo = strjoin(arrayfun(@(s) sprintf('%s:%.1fs', segName(suf{s}), segSec(s)), 1:numel(f31), 'uniformoutput', false), ' ');
    keep = segSec >= minSegSec;
    % sheet cells for this recording: {column name, value} (column names have spaces)
    row = {'Subject ID', sessID; 'Task', 'ADmeditation'; 'Type', 'EEG_meditation'; ...
           'dataType', 'ephys'; 'Atlas Folder', atlas; 'Recording Date', char(stamp, 'yyyy-MM-dd'); ...
           'Start Time', char(stamp, 'HH:mm:ss'); 'datPre', [rootDir filesep]};
    if ~any(keep)
        fprintf('%s (%s): EMPTY recording (%s) - not extracted\n', sessID, atlas, segInfo);
        row = [row; {'Segments', segInfo; 'Raw Duration (min)', round(sum(segSec) / 60, 2); ...
               'Notes', sprintf('empty recording (no acquisition segment >= %d s: %s) - not extracted', minSegSec, segInfo)}]; %#ok<AGROW>
        updateSheetRow(sheetPath, hdrNames, row, false);
        continue
    end
    segList = suf(keep);
    fprintf('%s (%s): extracting segment(s) %s  [%s]\n', sessID, atlas, strjoin(cellfun(@segName, segList, 'uniformoutput', false), ', '), segInfo);

    % ---- read every kept segment, then stitch them end to end ----
    nSeg = numel(segList);
    segDat = cell(1, nSeg);
    for s = 1:nSeg
        segLabs = cellfun(@(x) [x segList{s}], CSClist, 'uniformoutput', false);
        segDat{s} = ReadNCS(recDir, segLabs);
    end
    fsAll = cellfun(@(x) x.fsample, segDat);
    assert(all(fsAll == fsAll(1)), '%s: sampling rate differs across segments', sessID)
    for s = 1:nSeg
        assert(isequal(regexprep(segDat{s}.label(:)', [segList{s} '$'], ''), CSClist), ...
            '%s: channel order of segment %s differs from CSClist', sessID, segName(segList{s}))
    end
    nSamp = cellfun(@(x) size(x.trial{1}, 2), segDat);
    startSample = cumsum([1, nSamp(1:end-1)]);
    % wall-clock timing from the Neuralynx headers (first timestamp, us);
    % ReadNCS returns no hdr, so the first channel's header is read per segment
    t0us = nan(1, nSeg); tsPerSamp = nan(1, nSeg);
    for s = 1:nSeg
        hdrFile = fullfile(recDir, [CSClist{1} segList{s} '.ncs']);
        hdr = ft_read_header(hdrFile);
        t0us(s) = double(hdr.FirstTimeStamp);
        tsPerSamp(s) = double(hdr.TimeStampPerSample);
    end
    endUs = t0us + nSamp .* tsPerSamp;
    gapBeforeSec = [0, (t0us(2:end) - endUs(1:end-1)) / 1e6];

    trials = cellfun(@(x) x.trial{1}, segDat, 'uniformoutput', false);
    rawdata = segDat{1};
    rawdata.trial = {cat(2, trials{:})};
    rawdata.time  = {(0:size(rawdata.trial{1}, 2) - 1) / rawdata.fsample};
    rawdata.sampleinfo = [1, size(rawdata.trial{1}, 2)];
    rawdata.label = CSClist(:);                             % base CSC names (suffix stripped)
    clear segDat trials

    curDat = struct;
    curDat.ncslabels = CSClist;
    curDat.rawData   = rawdata;
    curDat.outLabs   = ReadableLabs;
    curDat.segments  = table(string(segList(:)), nSamp(:), startSample(:), t0us(:), tsPerSamp(:), gapBeforeSec(:), ...
        'VariableNames', {'suffix', 'nSamples', 'startSample', 'firstTimeStampUs', 'timeStampPerSample', 'gapBeforeSec'});
    curDat.sessID      = sessID;
    curDat.atlasFolder = atlas;
    curDat.recStart    = char(stamp, 'yyyy-MM-dd HH:mm:ss');
    curDat.loadFile    = [mfilename '.m'];
    curDat.segmentsSeen = segInfo;
    save(rawFile, 'curDat', '-v7.3')
    durMin = size(rawdata.trial{1}, 2) / rawdata.fsample / 60;
    clear rawdata curDat

    row = [row; {'Segments', strjoin(cellfun(@segName, segList, 'uniformoutput', false), '+'); ...
           'Raw Duration (min)', round(durMin, 2); 'Raw Data Extracted', 'X'; ...
           'Extraction Date', char(datetime('now'), 'yyyy-MM-dd')}]; %#ok<AGROW>
    updateSheetRow(sheetPath, hdrNames, row, true);
    fprintf('   saved %s (%.1f min)\n', rawFile, durMin);
end
warning('on', 'all')
disp('LoadData_ADmeditation_claude: done')

%% ---------------- local functions ----------------
function s = segName(suf)
    if isempty(suf), s = '(base)'; else, s = suf; end
end

function sec = ncsDurationSec(fn)
% duration of a .ncs file from its size and header (16384-byte header, 1044-byte records of 512 samples)
    fid = fopen(fn, 'r', 'ieee-le');
    hdr = fread(fid, 16384, '*char')';
    fseek(fid, 0, 'eof'); nBytes = ftell(fid);
    fclose(fid);
    tok = regexp(hdr, '-SamplingFrequency\s+([-+0-9.eE]+)', 'tokens', 'once');
    if isempty(tok) || nBytes <= 16384, sec = 0; return; end
    sec = floor((nBytes - 16384) / 1044) * 512 / str2double(tok{1});
end

function ensureSheet(sheetPath, hdrNames)
% create the tracking sheet (title row 1, header row 2, data from row 3) if it does not exist
    if exist(sheetPath, 'file'), return; end
    writecell({['AD_repeatRecordings - Adam''s repeated meditation recordings (task ADmeditation, ' ...
        'zelanoLabPreprocessing). Header row 2, one row per recording from row 3. Rows are added by ' ...
        'LoadData_ADmeditation_claude.m; parameter / summary columns by ADmeditationPreProc_main.m. ' ...
        'Blank parameter cells = the task defaults in applyParams (case adMed).']}, ...
        sheetPath, 'Sheet', 'Sheet1', 'Range', 'A1');
    writecell(hdrNames, sheetPath, 'Sheet', 'Sheet1', 'Range', 'A2');
    fprintf('created %s\n', sheetPath);
end

function updateSheetRow(sheetPath, hdrNames, row, isNewRaw)
% add or update the row keyed by Subject ID (row = {column name, value; ...});
% only those cells are written, and paramSource is set to 'guess' only when
% blank (a curated row stays curated)
    C = readcell(sheetPath, 'Sheet', 'Sheet1');
    hdr = C(2, :);
    col = @(n) find(cellfun(@(v) (ischar(v) || isstring(v)) && strcmpi(strtrim(char(v)), n), hdr), 1);
    for k = 1:numel(hdrNames)
        assert(~isempty(col(hdrNames{k})), 'tracking sheet lacks column "%s"', hdrNames{k});
    end
    cSub = col('Subject ID');
    r = [];
    for k = 3:size(C, 1)
        v = C{k, cSub};
        if (ischar(v) || isstring(v)) && strcmpi(strtrim(char(v)), row{strcmp(row(:, 1), 'Subject ID'), 2}), r = k; break; end
    end
    if isempty(r), r = max(3, size(C, 1) + 1); end
    for k = 1:size(row, 1)
        writecell(row(k, 2), sheetPath, 'Sheet', 'Sheet1', 'Range', sprintf('%s%d', colLetter(col(row{k, 1})), r));
    end
    if isNewRaw
        cPS = col('paramSource');
        cur = '';
        if r <= size(C, 1), v = C{r, cPS}; if ischar(v) || isstring(v), cur = strtrim(char(v)); end, end
        if isempty(cur)
            writecell({'guess'}, sheetPath, 'Sheet', 'Sheet1', 'Range', sprintf('%s%d', colLetter(cPS), r));
        end
    end
end

function s = colLetter(n)
    s = '';
    while n > 0
        m = mod(n - 1, 26);
        s = [char('A' + m) s]; %#ok<AGROW>
        n = floor((n - 1) / 26);
    end
end

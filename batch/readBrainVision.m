function [X, hdr, mrk] = readBrainVision(vhdrPath, varargin)
%READBRAINVISION  Read a BrainVision Recorder (actiCHamp) .vhdr/.vmrk/.eeg export.
%
%   [X, hdr, mrk] = readBrainVision(vhdrPath)
%   [X, hdr, mrk] = readBrainVision(vhdrPath, 'chans', idx, 'range', [begSamp endSamp])
%
%   vhdrPath   path to the .vhdr header file. The .eeg and .vmrk files are
%              located NEXT TO IT via the DataFile / MarkerFile fields parsed
%              from inside the .vhdr (BrainVision's own convention) - the
%              three files must always be kept together / renamed together.
%   'chans'    optional vector of channel indices (1-based, into hdr.chanNames)
%              to return; default all channels. Because BrainVision stores
%              samples MULTIPLEXED (all channels for sample 1, then all
%              channels for sample 2, ...), every channel's bytes must be
%              read regardless of 'chans' - the subset is taken after the
%              read, so 'chans' saves memory/output size, not disk I/O.
%   'range'    optional [begSamp endSamp], 1-based inclusive, in samples at
%              hdr.fs; default the whole recording. Use this (with fseek
%              under the hood) to avoid reading a whole multi-hundred-MB file
%              when only a window is needed (e.g. probeMontageBV).
%
%   X    [numel(chans) x nSampInRange] double, native units (the header's
%        per-channel "Resolution" has ALREADY been multiplied in - for these
%        recordings that is microvolts for every channel).
%   hdr  struct: fs, nChan, chanNames (1 x nChan cell, '\1'-unescaped),
%        resolution (1 x nChan double), unit (1 x nChan cell), binaryFormat,
%        orientation, dataFormat, dataFile, markerFile, refChan (parsed from
%        the "Reference Channel Name = " line in the header's free-text
%        [Comment] section; 'Cz' for these recordings), recStart (datetime,
%        parsed from the New Segment marker's date field
%        yyyymmddHHMMSSFFFFFF - FFFFFF is MICROSECONDS; NaT if no such
%        marker), impedanceText (the raw [Comment] section text, including
%        the per-channel impedance table when the amplifier logged one; ''
%        if the recording has no [Comment] section).
%   mrk  table: type, description, sample, sizeSamples, channel, minutes -
%        EVERY marker in the .vmrk, file order, including "New Segment"
%        (minutes = sample / hdr.fs / 60).
%
%   Parsing handled: the Codepage line (informational - fileread already
%   decodes the file as UTF-8, which is what these recorders write), ';'
%   comment lines, '[Section]' headers, and BrainVision's '\1' escape for a
%   literal comma inside a channel-name or marker-description text field
%   (unescaped back to ',').
%
%   Only BinaryFormat=IEEE_FLOAT_32 and DataOrientation=MULTIPLEXED are
%   implemented (both true for every actiCHamp export seen so far) - anything
%   else errors rather than silently misreading.
%
%   Read-only; never writes anything. Used by batch/probeMontageBV.m and
%   pasted as local functions into the vipassana task's standalone
%   LoadData_<id>_claude.m scripts (which must not depend on the repo).

    p = inputParser;
    p.addParameter('chans', []);
    p.addParameter('range', []);
    p.parse(varargin{:});
    chans = p.Results.chans;
    range = p.Results.range;

    assert(exist(vhdrPath, 'file') == 2, 'readBrainVision: vhdr not found: %s', vhdrPath);
    bvDir = fileparts(vhdrPath);

    hdr = readVhdrBV(vhdrPath);

    markerPath = fullfile(bvDir, hdr.markerFile);
    [mrk, dateStr] = readVmrkBV(markerPath, hdr.fs);
    hdr.recStart = parseBVDateBV(dateStr);

    if isempty(chans), chans = 1:hdr.nChan; end
    chans = chans(:)';
    assert(all(chans >= 1 & chans <= hdr.nChan), ...
        'readBrainVision: chans out of range 1..%d', hdr.nChan);

    dataPath = fullfile(bvDir, hdr.dataFile);
    d = dir(dataPath);
    assert(~isempty(d), 'readBrainVision: .eeg not found: %s', dataPath);
    assert(strcmpi(hdr.binaryFormat, 'IEEE_FLOAT_32'), ...
        'readBrainVision: unsupported BinaryFormat %s (only IEEE_FLOAT_32 implemented)', hdr.binaryFormat);
    assert(strcmpi(hdr.orientation, 'MULTIPLEXED'), ...
        'readBrainVision: unsupported DataOrientation %s (only MULTIPLEXED implemented)', hdr.orientation);
    assert(strcmpi(hdr.dataFormat, 'BINARY'), ...
        'readBrainVision: unsupported DataFormat %s (only BINARY implemented)', hdr.dataFormat);

    bytesPerSamp = 4;   % IEEE_FLOAT_32
    NtotalExact = d.bytes / (hdr.nChan * bytesPerSamp);
    Ntotal = round(NtotalExact);
    assert(abs(NtotalExact - Ntotal) < 1e-6 && d.bytes == hdr.nChan * Ntotal * bytesPerSamp, ...
        'readBrainVision: %s is %d bytes, not a whole number of samples for %d channels x %d bytes', ...
        dataPath, d.bytes, hdr.nChan, bytesPerSamp);

    if isempty(range), range = [1 Ntotal]; end
    assert(numel(range) == 2 && range(1) >= 1 && range(2) <= Ntotal && range(1) <= range(2), ...
        'readBrainVision: range [%s] out of bounds 1..%d', mat2str(range), Ntotal);
    nRead = range(2) - range(1) + 1;

    fid = fopen(dataPath, 'r', 'ieee-le');
    assert(fid > 0, 'readBrainVision: could not open %s', dataPath);
    c = onCleanup(@() fclose(fid)); %#ok<NASGU>
    fseek(fid, (range(1) - 1) * hdr.nChan * bytesPerSamp, 'bof');
    raw = fread(fid, [hdr.nChan, nRead], 'float32=>double');
    assert(size(raw, 2) == nRead, ...
        'readBrainVision: short read (%d of %d requested samples) from %s - truncated .eeg?', ...
        size(raw, 2), nRead, dataPath);

    res = hdr.resolution(chans);
    X = raw(chans, :) .* res(:);
    hdr.chanNames = hdr.chanNames(:)';
end

% ================= local functions =================

function hdr = readVhdrBV(vhdrPath)
    txt = fileread(vhdrPath);
    lines = regexp(txt, '\r\n|\r|\n', 'split');
    hdr = struct();
    hdr.fs = NaN; hdr.nChan = NaN; hdr.chanNames = {}; hdr.resolution = []; hdr.unit = {};
    hdr.binaryFormat = ''; hdr.orientation = ''; hdr.dataFormat = ''; hdr.dataFile = ''; hdr.markerFile = '';
    sec = ''; inComment = false; commentLines = {};
    for i = 1:numel(lines)
        Lraw = lines{i};
        if inComment, commentLines{end+1} = Lraw; continue; end %#ok<AGROW>
        L = strtrim(Lraw);
        if isempty(L) || L(1) == ';', continue; end
        if L(1) == '['
            secName = lower(strtrim(L(2:end-1)));
            sec = secName;
            if strcmp(secName, 'comment'), inComment = true; end
            continue;
        end
        eq = find(L == '=', 1);
        if isempty(eq), continue; end
        key = strtrim(L(1:eq-1));
        val = strtrim(L(eq+1:end));
        switch sec
            case 'common infos'
                switch key
                    case 'DataFile',         hdr.dataFile = val;
                    case 'MarkerFile',       hdr.markerFile = val;
                    case 'NumberOfChannels', hdr.nChan = str2double(val);
                    case 'SamplingInterval', hdr.fs = 1e6 / str2double(val);
                    case 'DataOrientation',  hdr.orientation = val;
                    case 'DataFormat',       hdr.dataFormat = val;
                    % Codepage: informational only - fileread already decodes UTF-8
                end
            case 'binary infos'
                if strcmpi(key, 'BinaryFormat'), hdr.binaryFormat = val; end
            case 'channel infos'
                parts = regexp(val, ',', 'split');
                hdr.chanNames{end+1} = unescapeBV(parts{1}); %#ok<AGROW>
                r = NaN;
                if numel(parts) >= 3, r = str2double(parts{3}); end
                if isnan(r), r = 1; end
                hdr.resolution(end+1) = r; %#ok<AGROW>
                if numel(parts) >= 4, hdr.unit{end+1} = unescapeBV(parts{4}); else, hdr.unit{end+1} = ''; end %#ok<AGROW>
        end
    end
    assert(~isnan(hdr.nChan) && numel(hdr.chanNames) == hdr.nChan, ...
        'readBrainVision: [Channel Infos] has %d entries but NumberOfChannels=%g (%s)', ...
        numel(hdr.chanNames), hdr.nChan, vhdrPath);
    assert(~isnan(hdr.fs) && hdr.fs > 0, 'readBrainVision: could not parse SamplingInterval (%s)', vhdrPath);
    assert(~isempty(hdr.dataFile), 'readBrainVision: [Common Infos] DataFile missing (%s)', vhdrPath);
    assert(~isempty(hdr.markerFile), 'readBrainVision: [Common Infos] MarkerFile missing (%s)', vhdrPath);

    hdr.impedanceText = strtrim(strjoin(commentLines, sprintf('\n')));
    m = regexp(hdr.impedanceText, 'Reference Channel Name\s*=\s*(\S+)', 'tokens', 'once');
    if ~isempty(m), hdr.refChan = m{1}; else, hdr.refChan = 'Cz'; end
end

function [mrk, dateStr] = readVmrkBV(vmrkPath, fs)
    assert(exist(vmrkPath, 'file') == 2, 'readBrainVision: vmrk not found: %s', vmrkPath);
    txt = fileread(vmrkPath);
    lines = regexp(txt, '\r\n|\r|\n', 'split');
    type = {}; desc = {}; samp = []; sz = []; chan = []; dateStr = '';
    for i = 1:numel(lines)
        L = strtrim(lines{i});
        if isempty(L) || L(1) == ';' || ~startsWith(L, 'Mk'), continue; end
        eq = find(L == '=', 1);
        if isempty(eq), continue; end
        parts = regexp(L(eq+1:end), ',', 'split');
        assert(numel(parts) >= 5, 'readBrainVision: malformed marker line "%s" in %s', L, vmrkPath);
        type{end+1}  = unescapeBV(parts{1}); %#ok<AGROW>
        desc{end+1}  = unescapeBV(parts{2}); %#ok<AGROW>
        samp(end+1)  = str2double(parts{3}); %#ok<AGROW>
        sz(end+1)    = str2double(parts{4}); %#ok<AGROW>
        chan(end+1)  = str2double(parts{5}); %#ok<AGROW>
        if numel(parts) >= 6 && ~isempty(parts{6}) && isempty(dateStr)
            dateStr = parts{6};   % first marker carrying a date (New Segment)
        end
    end
    assert(~isempty(samp), 'readBrainVision: no markers parsed from %s', vmrkPath);
    mrk = table(type(:), desc(:), samp(:), sz(:), chan(:), samp(:) / fs / 60, ...
        'VariableNames', {'type', 'description', 'sample', 'sizeSamples', 'channel', 'minutes'});
end

function dt = parseBVDateBV(s)
    % BrainVision New-Segment date: yyyymmddHHMMSS + fractional-second digits
    % (microseconds, 6 digits, on every export seen so far).
    if isempty(s) || numel(strtrim(s)) < 14, dt = NaT; return; end
    s = strtrim(s);
    yyyy = str2double(s(1:4)); mm = str2double(s(5:6)); dd = str2double(s(7:8));
    HH = str2double(s(9:10)); MM = str2double(s(11:12)); SS = str2double(s(13:14));
    us = 0;
    if numel(s) > 14
        frac = s(15:end);
        us = str2double(frac) / 10 ^ numel(frac);
    end
    dt = datetime(yyyy, mm, dd, HH, MM, SS + us);
end

function s = unescapeBV(s)
    s = strrep(s, '\1', ',');
end

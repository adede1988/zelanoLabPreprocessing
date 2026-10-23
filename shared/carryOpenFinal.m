function CS = carryOpenFinal(P, sessID, opts)
%CARRYOPENFINAL  Open the previous final named by ZLP_CARRY_FROM / P.carryFrom (respiration carry).
%
%   CS = carryOpenFinal(P, sessID)
%   CS = carryOpenFinal(P, sessID, opts)
%
%   The respiration carry (2026-10-22 full EEG rerun): a rerun of a session
%   keeps the respiratory traces of its previous final - a trace repaired
%   after the pipeline (reconstructed playback blocks, a decided polarity) is
%   not reproduced by a rerun from raw. carryRespFromFinal copies them into
%   the new outDat right after runSharedCore; carryFinishFromFinal records the
%   carry and keeps the previous final's post-hoc fields. This function is
%   the first step: it finds and reads the previous final once.
%
%   Switch: the environment variable ZLP_CARRY_FROM = the full path of the
%   previous final (the batch driver sets it per final), or P.carryFrom (same
%   meaning, wins over the variable). Neither set -> CS = [] and every caller
%   runs exactly as it always did. The path is NOT the session's live final:
%   the driver moves the previous final away (superseded_*) before the rerun,
%   so the caller's own save cannot overwrite it. Optional ZLP_CARRY_SHA256 =
%   the SHA-256 the driver measured when it backed the file up; a different
%   hash errors (the file changed since).
%
%   opts (optional): .ignoreLabels  cellstr of 'rsp'-labelled rows that are
%        NOT carried (breathingTasks_separate: {'rspSelected'}, which
%        concatSections rebuilds from the carried rsp rows and which
%        carryFinishFromFinal then checks)
%
%   CS (struct) holds the small part of the previous final that the carry
%   needs - the source path / hash / modified time, the stored variable's
%   name (outDat / chanDat / out), sessID, fs, sample count, every rsp* row
%   (rspLabels, rspRows) and the targTrace row (targRow), rspIDX / rspFlip,
%   reconstructedBlocks, the section table of a breathingTasks_separate final
%   (+ the per-section respiration choice secRsp), the rspSelected row, the
%   top-level field names (prevFields) and a few facts about how it was made.
%   The EEG data and everything else are dropped after reading.
%
%   Strict: a missing file, an unreadable or ambiguous variable, a final
%   without data / labels / fs or without an rsp row, or a hash mismatch
%   errors (carryOpenFinal:*).

    if nargin < 3 || isempty(opts), opts = struct(); end
    ignore = {};
    if isfield(opts, 'ignoreLabels'), ignore = cellstr(opts.ignoreLabels); end

    src = '';
    if isstruct(P) && isfield(P, 'carryFrom') && ~isempty(P.carryFrom), src = char(string(P.carryFrom)); end
    if isempty(src), src = strtrim(getenv('ZLP_CARRY_FROM')); end
    if isempty(src), CS = []; return; end

    if ~isfile(src)
        error('carryOpenFinal:noFile', '%s: ZLP_CARRY_FROM / P.carryFrom names no file: %s', sessID, src);
    end
    fi = dir(src);
    sha = sha256File(src);
    shaEnv = lower(strtrim(getenv('ZLP_CARRY_SHA256')));
    if ~isempty(shaEnv) && ~isempty(sha) && ~strcmp(shaEnv, sha)
        error('carryOpenFinal:hashMismatch', ...
            '%s: %s has SHA-256 %s, not the %s ZLP_CARRY_SHA256 says - the file changed after it was backed up', ...
            sessID, src, sha, shaEnv);
    end

    w = whos('-file', src);
    isCand = ismember({w.name}, {'outDat', 'chanDat', 'out'}) & strcmp({w.class}, 'struct');
    if sum(isCand) ~= 1
        error('carryOpenFinal:variable', '%s: expected exactly one struct variable outDat / chanDat / out in %s (found %s)', ...
            sessID, src, strjoin({w.name}, ', '));
    end
    varName = w(isCand).name;
    s = load(src, varName);
    old = s.(varName);
    clear s
    for f = {'data', 'labels', 'fs'}
        if ~isfield(old, f{1})
            error('carryOpenFinal:noField', '%s: previous final %s has no field %s', sessID, src, f{1});
        end
    end

    lab = cellfun(@(x) char(string(x)), old.labels(:)', 'UniformOutput', false);
    isRsp = cellfun(@(x) contains(x, 'rsp'), lab) & ~ismember(lab, ignore);
    isTarg = strcmp(lab, 'targTrace');
    if ~any(isRsp)
        error('carryOpenFinal:noRsp', '%s: previous final %s has no rsp row', sessID, src);
    end
    if sum(isTarg) > 1
        error('carryOpenFinal:targTrace', '%s: previous final %s has %d targTrace rows', sessID, src, sum(isTarg));
    end

    CS = struct();
    CS.path = src;
    CS.sha256 = sha;
    CS.bytes = fi.bytes;
    CS.modified = fi.date;
    CS.varName = varName;
    CS.sessID = '';
    if isfield(old, 'sessID'), CS.sessID = char(string(old.sessID)); end
    CS.task = '';
    if isfield(old, 'task'), CS.task = char(string(old.task)); end
    CS.fs = double(old.fs);
    CS.nSamp = size(old.data, 2);
    CS.ignore = ignore;
    CS.rspLabels = lab(isRsp);
    CS.rspRows = double(old.data(isRsp, :));
    CS.targRow = [];
    if any(isTarg), CS.targRow = double(old.data(isTarg, :)); end
    CS.rspIDX = [];  CS.rspFlip = [];
    if isfield(old, 'rspIDX') && ~isempty(old.rspIDX), CS.rspIDX = double(old.rspIDX); end
    if isfield(old, 'rspFlip') && ~isempty(old.rspFlip), CS.rspFlip = double(old.rspFlip); end
    CS.reconstructedBlocks = [];
    if isfield(old, 'reconstructedBlocks'), CS.reconstructedBlocks = old.reconstructedBlocks; end

    % breathingTasks_separate: the section table and each section's respiration choice
    CS.sections = [];
    CS.secRsp = [];
    if isfield(old, 'sections') && istable(old.sections) && all(ismember({'label', 'startSample', 'endSample'}, old.sections.Properties.VariableNames))
        vn = old.sections.Properties.VariableNames;
        CS.sections = old.sections(:, vn(ismember(vn, {'label', 'startSample', 'endSample', 'rspIDX', 'rspFlip'})));
        nSec = height(CS.sections);
        if all(ismember({'rspIDX', 'rspFlip'}, vn))
            CS.secRsp = [double(old.sections.rspIDX(:)), double(old.sections.rspFlip(:))];   % rspSelected case: per section
        elseif ~isempty(CS.rspIDX) && ~isempty(CS.rspFlip)
            CS.secRsp = repmat([CS.rspIDX, CS.rspFlip], nSec, 1);
        end
    end
    CS.rspSelectedRow = [];
    iSel = find(strcmp(lab, 'rspSelected'));
    if isscalar(iSel), CS.rspSelectedRow = double(old.data(iSel, :)); end

    CS.prevFields = fieldnames(old);
    CS.hadCarry = isfield(old, 'carry');
    CS.nNonFinite = sum(~isfinite(CS.rspRows(:))) + sum(~isfinite(CS.targRow(:)));
    if CS.nNonFinite > 0
        warning('carryOpenFinal:nonFinite', '%s: %d non-finite samples in the previous final''s rsp / targTrace rows', ...
            sessID, CS.nNonFinite);
    end
    CS.made = struct('bmEngine', '', 'eegCleaningMode', '', 'moreThan1', NaN, 'hadBreathMerge', isfield(old, 'breathMerge'));
    if isfield(old, 'bmFeatures') && isstruct(old.bmFeatures) && isfield(old.bmFeatures, 'version')
        CS.made.bmEngine = char(string(old.bmFeatures.version));
    end
    if isfield(old, 'EEGCleaningInfo') && isstruct(old.EEGCleaningInfo) && isfield(old.EEGCleaningInfo, 'mode')
        CS.made.eegCleaningMode = char(string(old.EEGCleaningInfo.mode));
    elseif isfield(old, 'EEGCleaning')
        CS.made.eegCleaningMode = 'legacy (no EEGCleaningInfo)';
    end
    if isfield(old, 'moreThan1'), CS.made.moreThan1 = double(old.moreThan1); end
    fprintf('%s: respiration carry from %s (%d rsp row(s)%s, %d samples, SHA-256 %s)\n', sessID, src, ...
        sum(isRsp), ternary(any(isTarg), ' + targTrace', ''), CS.nSamp, sha);
end

function v = ternary(c, a, b)
    if c, v = a; else, v = b; end
end

function h = sha256File(path)
% SHA-256 of a file, streamed in 64-MB chunks through the JVM ('' when the JVM is not available)
    h = '';
    try
        md = java.security.MessageDigest.getInstance('SHA-256');
        fid = fopen(path, 'r');
        c = onCleanup(@() fclose(fid));
        while true
            chunk = fread(fid, 64 * 2^20, '*int8');
            if isempty(chunk), break; end
            md.update(chunk);
        end
        d = typecast(int8(md.digest()), 'uint8');
        h = lower(reshape(dec2hex(d, 2)', 1, []));
    catch
        h = '';
    end
end

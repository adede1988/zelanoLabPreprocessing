% resegmentAll_zlp - IN-PLACE re-segmentation of every breathMetrics-based
% final under the LOCKED engine (segmentBreaths_zlp, rev12b) with behDat
% rebuilt anew (2026-08-28 user work order).
%
% NEVER re-runs from raw: the reconstructed slowBreath/slowRec/cyclicSigh
% traces live ONLY in the finals. Per session: backup the final to
% E:\reprocBackup_260824\r12\<task>\, re-detect on the stored trace,
% rebuild bmObj/bmFeatures/behDat (per-block metadata and ratings carried
% over from the OLD behDat by condition), redo goodBreath/HRV, save in
% place (-v7.3, original variable name), verify, and rewrite the
% processedBehavior CSV.
%
% Env vars:
%   ZLP_RESEG_ONLY  comma-separated session ids - validation subset
%   ZLP_FLIPFIX     'task|id=-1,task2|id2=1' rspFlip overrides decided by
%                   the qc5 flip audit, keyed task|id because one session
%                   can carry different verdicts per task (DL_1: breathing
%                   keep, sep invert); updates od.rspFlip in the final
%                   (sheet updates + review flags handled by the caller)

BKD = 'E:\reprocBackup_260824\r12';
TASKS = { ...
 'breathingTask',          '_breathing*.mat',                'i_processedBreathing.csv'; ...
 'emotionalMovieTask',     '_EmotionalMovieTask*.mat',       'i_EmotionalMovieTask_processedBreathing.csv'; ...
 'alternating6Blocks',     '_alternating6Blocks*.mat',       'i_alternating6Blocks_processedBreathing.csv'; ...
 'breathingTasks_separate','_breathingTasks_separate*.mat',  'i_breathingTasks_separate_processedBreathing.csv'};

onlyEnv = getenv('ZLP_RESEG_ONLY');
onlyList = {};
if ~isempty(onlyEnv), onlyList = strtrim(strsplit(onlyEnv, ',')); end
flipFix = containers.Map('KeyType', 'char', 'ValueType', 'double');
ffEnv = getenv('ZLP_FLIPFIX');
if ~isempty(ffEnv)
    pairs = strsplit(ffEnv, ',');
    for p = 1:numel(pairs)
        kv = strsplit(strtrim(pairs{p}), '=');
        flipFix(kv{1}) = str2double(kv{2});
    end
end
L = labPaths();
if ~exist(L.procBehavior, 'dir'), mkdir(L.procBehavior); end

CORE = {'sniffOnset','finalOnset','manOnset','condition','Yonset','inhaleMax', ...
        'inMaxTim','Yend','endTim','length','amp','exhaleMin','exMinTim','index'};
KNOWN = [CORE, {'task','noseMouth','shadowFile','warp','goodBreath','maxRR', ...
        'minRR','RR_max_min','clipIndex','clipValence','clipOnset'}];

nOK = 0; nSkip = 0; nFail = 0;
for tt = 1:size(TASKS, 1)
    [tkey, glb, csvPat] = TASKS{tt, :};
    cfg = applyParams(tkey, 'main');
    for si = 1:numel(cfg.sessionIDs)
        id = cfg.sessionIDs{si};
        % ZLP_RESEG_ONLY entries may be bare ids (all tasks) or 'task|id'
        % (2026-09-01: rev13 reruns target single task-sessions - a bare id
        % would also resegment the same subject's other, already-approved
        % task finals)
        if ~isempty(onlyList) && ...
                ~any(strcmp(onlyList, id)) && ...
                ~any(strcmp(onlyList, [tkey '|' id]))
            continue;
        end
        hits = dir(fullfile(cfg.root{si}, id, 'preProc', [id glb]));
        if isempty(hits), continue; end
        fpath = fullfile(hits(1).folder, hits(1).name);
        try
            S = load(fpath); vNames = fieldnames(S); vName = vNames{1};
            od = S.(vName); clear S
            if ~isfield(od, 'bmFeatures') || ~isfield(od, 'bmObj')
                fprintf('RESEG SKIP %s %s: no bmFeatures (not a bm final)\n', tkey, id);
                nSkip = nSkip + 1; clear od; continue;
            end
            nOldBreaths = height(od.behDat);
            oldBeh = od.behDat;

            % ---- backup BEFORE any modification ----
            bdir = fullfile(BKD, tkey);
            if ~exist(bdir, 'dir'), mkdir(bdir); end
            bfile = fullfile(bdir, hits(1).name);
            if ~exist(bfile, 'file'), copyfile(fpath, bfile); end

            % ---- flip decision (keyed task|id) ----
            fl = od.rspFlip;
            fkey = [tkey '|' id];
            if flipFix.isKey(fkey)
                fl = flipFix(fkey);
                fprintf('RESEG FLIPFIX %s %s: rspFlip %+d -> %+d\n', tkey, id, od.rspFlip, fl);
            end
            od.rspFlip = fl;
            isRsp = cellfun(@(x) contains(x, 'rsp'), od.labels);
            r = double(od.data(isRsp, :)); r = r(od.rspIDX, :) .* fl;
            fs = od.fs; N = numel(r);
            blank = [];
            if contains(id, '_MS') && ~strcmp(tkey, 'breathingTask'), blank = 0.10; end

            switch tkey
                case 'breathingTask'
                    tkc = sanitizeStr(oldBeh.task);
                    cySpan = [];
                    cm = tkc == "cyclicSigh";
                    if any(cm)
                        cySpan = [max(1, min(oldBeh.finalOnset(cm)) - 15*fs), ...
                                  min(N, max(oldBeh.finalOnset(cm)) + 15*fs)];
                    end
                    [bmObj, bmF] = segmentBreaths_zlp(r, fs, [], [], cySpan);
                    % condition from the stored TTL boundary vector (main's rule)
                    if isfield(od, 'TTL') && ~isempty(od.TTL)
                        TaskBreaks = [od.TTL(:)' / fs, N / fs];
                    else
                        TaskBreaks = 0:300:(max(oldBeh.condition) * 300 - 10);
                    end
                    for cndi = 1:numel(TaskBreaks)
                        bmObj(bmObj(:, 2) > TaskBreaks(cndi), 12) = cndi;
                    end
                    od.bmObj = bmObj; od.bmFeatures = bmF;
                    beh = coreTable(bmObj, fs, N);
                    % per-condition block metadata + emotion columns from OLD behDat
                    metaEmo = [{'task','noseMouth','shadowFile','warp'}, ...
                        setdiff(oldBeh.Properties.VariableNames, KNOWN, 'stable')];
                    metaEmo = metaEmo(~startsWith(metaEmo, 'bm_'));
                    metaEmo = metaEmo(ismember(metaEmo, oldBeh.Properties.VariableNames));
                    for c = 1:numel(metaEmo)
                        beh.(metaEmo{c}) = repmat(oldBeh.(metaEmo{c})(1), height(beh), 1);
                    end
                    uc = unique(beh.condition)';
                    for cnd = uc
                        ii = find(oldBeh.condition == cnd, 1);
                        rows = beh.condition == cnd;
                        if isempty(ii)
                            fprintf('RESEG WARN %s: condition %d absent in old behDat - metadata from row 1\n', id, cnd);
                            continue;
                        end
                        for c = 1:numel(metaEmo)
                            beh.(metaEmo{c})(rows) = oldBeh.(metaEmo{c})(ii);
                        end
                    end
                    od.behDat = beh;
                    od = appendBMcols(od);
                    od = hrvOrNaN(od);

                case 'emotionalMovieTask'
                    [od.bmObj, od.bmFeatures] = segmentBreaths_zlp(r, fs, [], blank, []);
                    od = build_behavior_table_emotionalMovieTask(od);
                    od = hrvOrNaN(od);

                case 'alternating6Blocks'
                    [bmObj, bmF] = segmentBreaths_zlp(r, fs, [], blank, []);
                    B = od.blocks;
                    onsetSamp = round(bmObj(:, 2) * fs);
                    blkIdx = zeros(size(onsetSamp));
                    for b = 1:height(B)
                        in = onsetSamp >= B.startSample(b) & onsetSamp <= B.endSample(b);
                        blkIdx(in) = b;
                    end
                    keep = blkIdx > 0;
                    fprintf('%s: %d/%d breaths inside the %d blocks\n', id, sum(keep), numel(keep), height(B));
                    bmObj(:, 12) = blkIdx;
                    bmObj = bmObj(keep, :); blkIdx = blkIdx(keep);
                    bmObj(:, 14) = 1:size(bmObj, 1);
                    bmF.bmObjBreathIdx = bmF.bmObjBreathIdx(keep);
                    od.bmObj = bmObj; od.bmFeatures = bmF;
                    beh = coreTable(bmObj, fs, N);
                    beh.task = cellstr(B.label(blkIdx));
                    n = height(beh);
                    beh.noseMouth  = repmat("NA", n, 1);
                    beh.shadowFile = repmat("NA", n, 1);
                    beh.warp       = nan(n, 1);
                    emoCols = setdiff(oldBeh.Properties.VariableNames, KNOWN, 'stable');
                    emoCols = emoCols(~startsWith(emoCols, 'bm_'));
                    for c = 1:numel(emoCols)
                        beh.(emoCols{c}) = nan(n, 1);
                        for b = 1:height(B)
                            ii = find(oldBeh.condition == b, 1);
                            if isempty(ii), continue; end
                            beh.(emoCols{c})(blkIdx == b) = oldBeh.(emoCols{c})(ii);
                        end
                    end
                    od.behDat = beh;
                    od = appendBMcols(od);
                    od = hrvOrNaN(od);

                case 'breathingTasks_separate'
                    sec = od.sections; nSeg = height(sec);
                    sampIdxFields = {'inhaleOnsets','exhaleOnsets','inhaleOffsets','exhaleOffsets', ...
                                     'inhalePeaks','exhaleTroughs','inhalePauseOnsets','exhalePauseOnsets'};
                    otherPerBreath = {'peakInspiratoryFlows','troughExpiratoryFlows', ...
                                      'inhaleTimeToPeak','exhaleTimeToTrough','inhaleVolumes', ...
                                      'exhaleVolumes','inhaleDurations','exhaleDurations', ...
                                      'inhalePauseDurations','exhalePauseDurations', ...
                                      'inhaleVolumesRaw','exhaleVolumesRaw'};
                    bmObj = []; F = struct(); featOffset = 0;
                    for c = 1:nSeg
                        a = sec.startSample(c); b2 = sec.endSample(c);
                        [bo, f] = segmentBreaths_zlp(r(a:b2), fs);
                        offSec = (a - 1) / fs;
                        bo(:, [2 4 6 11]) = bo(:, [2 4 6 11]) + offSec;
                        bo(:, 9) = bo(:, 9) + (a - 1);
                        bo(:, 12) = c;
                        bmObj = [bmObj; bo]; %#ok<AGROW>
                        for k = 1:numel(sampIdxFields)
                            F = appendFeat(F, sampIdxFields{k}, f.(sampIdxFields{k}) + (a - 1));
                        end
                        for k = 1:numel(otherPerBreath)
                            F = appendFeat(F, otherPerBreath{k}, f.(otherPerBreath{k}));
                        end
                        if ~isfield(F, 'shapeFeatures'), F.shapeFeatures = f.shapeFeatures;
                        else, F.shapeFeatures = [F.shapeFeatures; f.shapeFeatures]; end
                        F = appendFeat(F, 'bmObjBreathIdx', f.bmObjBreathIdx + featOffset);
                        F.secondaryFeaturesPerSection{c} = f.secondaryFeatures;
                        F.conditioningPerSection{c} = f.conditioning;
                        featOffset = featOffset + f.nInhalesDetected;
                    end
                    bmObj(:, 14) = 1:size(bmObj, 1);
                    F.engine = 'zlp-locked + breathmetrics features';
                    F.version = ['segmentation: ZLP rev12b (2026-08-28); features: ' ...
                        'qhyang42/breathmetrics 9791153 vendored'];
                    F.dataType = 'humanAirflow'; F.srate = fs;
                    F.nBreathsSegmented = size(bmObj, 1);
                    od.bmObj = bmObj; od.bmFeatures = F;
                    od = build_behavior_table_breathingTasks_separate(od);
                    od = hrvOrNaN(od);
                    if ismember('goodBreath', od.behDat.Properties.VariableNames)
                        for b = 1:height(od.sections)
                            edges = [od.sections.startSample(b), od.sections.endSample(b)];
                            for e = edges
                                near = abs(od.behDat.finalOnset - e) < 10 * fs;
                                od.behDat.goodBreath(near) = 0;
                            end
                        end
                    end
            end

            od.moreThan1 = 1;
            assert(height(od.behDat) > 0 && ...
                all(ismember({'finalOnset', 'manOnset', 'condition'}, od.behDat.Properties.VariableNames)), ...
                'behDat contract violated');
            assert(height(od.behDat) == size(od.bmObj, 1), 'behDat/bmObj row mismatch');

            % ---- save in place, original variable name ----
            tmp = struct(); tmp.(vName) = od;
            save(fpath, '-struct', 'tmp', '-v7.3');
            w = whos('-file', fpath);
            assert(numel(w) == 1 && strcmp(w(1).name, vName) && w(1).bytes > 1e6, 'post-save verify failed');

            % ---- processedBehavior CSV ----
            csvName = strrep(csvPat, 'i_', [id '_']);
            writetable(od.behDat, fullfile(L.procBehavior, csvName));

            fprintf('RESEG OK %s %s: breaths %d -> %d (flip %+d)\n', ...
                tkey, id, nOldBreaths, height(od.behDat), fl);
            nOK = nOK + 1;
            clear od tmp oldBeh bmObj bmF beh F
        catch ME
            fprintf('RESEG FAIL %s %s: %s (%s line %d)\n', tkey, id, ME.message, ...
                ME.stack(1).name, ME.stack(1).line);
            nFail = nFail + 1;
            clear od
        end
    end
end
fprintf('resegmentAll_zlp: DONE ok=%d skip=%d fail=%d\n', nOK, nSkip, nFail);

% ---------------- helpers ----------------
function beh = coreTable(bmObj, fs, N)
% the shared breathing-layout core columns (builder-identical semantics:
% times in bmObj are exact sample/fs, so round() reproduces find(x<=tim,1))
    beh = table();
    idx = min(max(round(bmObj(:, 2) * fs), 1), N);
    beh.sniffOnset = idx;
    beh.finalOnset = idx;
    beh.manOnset   = nan(size(idx));
    beh.condition  = bmObj(:, 12);
    beh.Yonset     = bmObj(:, 1);
    beh.inhaleMax  = bmObj(:, 3);
    beh.inMaxTim   = min(max(round(bmObj(:, 4) * fs), 1), N);
    beh.Yend       = bmObj(:, 5);
    beh.endTim     = min(max(round(bmObj(:, 6) * fs), 1), N);
    beh.length     = bmObj(:, 7);
    beh.amp        = bmObj(:, 8);
    beh.exhaleMin  = bmObj(:, 10);
    beh.exMinTim   = min(max(round(bmObj(:, 11) * fs), 1), N);
    beh.index      = bmObj(:, 14);
end

function od = appendBMcols(od)
% bm_* per-breath feature columns (shared convention, D8e)
    F = od.bmFeatures;
    if ~isfield(F, 'bmObjBreathIdx'), return; end
    bi = F.bmObjBreathIdx(:);
    if numel(bi) ~= height(od.behDat)
        warning('resegmentAll_zlp:bmMisaligned', '%s: bm_* skipped (map %d vs rows %d)', ...
            od.sessID, numel(bi), height(od.behDat));
        return;
    end
    perBreath = {'inhaleOnsets','exhaleOnsets','inhaleOffsets','exhaleOffsets', ...
                 'inhalePeaks','exhaleTroughs','peakInspiratoryFlows', ...
                 'troughExpiratoryFlows','inhaleTimeToPeak','exhaleTimeToTrough', ...
                 'inhaleVolumes','exhaleVolumes','inhaleDurations','exhaleDurations', ...
                 'inhalePauseOnsets','exhalePauseOnsets', ...
                 'inhalePauseDurations','exhalePauseDurations', ...
                 'inhaleVolumesRaw','exhaleVolumesRaw'};
    for f = 1:numel(perBreath)
        fld = perBreath{f};
        if isfield(F, fld) && numel(F.(fld)) >= max(bi)
            v = F.(fld)(:);
            od.behDat.(['bm_' fld]) = v(bi);
        end
    end
    if isfield(F, 'shapeFeatures') && istable(F.shapeFeatures) && height(F.shapeFeatures) >= max(bi)
        sv = F.shapeFeatures.Properties.VariableNames;
        for f = 1:numel(sv)
            if strcmp(sv{f}, 'breath_id'), continue; end
            v = F.shapeFeatures.(sv{f});
            od.behDat.(['bm_' sv{f}]) = v(bi);
        end
    end
end

function od = hrvOrNaN(od)
% goodBreath + within-breath HRV via flagBadBreaths when an RRint channel
% exists (and ECG wasn't flagged skipped); NaN columns otherwise
    hasRR = any(cellfun(@(x) contains(x, 'RRint'), od.labels));
    skipped = isfield(od, 'ecgSkipped') && od.ecgSkipped > 0;
    if hasRR && ~skipped
        od = flagBadBreaths(od);
        % breaths never visited by the QC window keep 0/NaN defaults
        if ~ismember('goodBreath', od.behDat.Properties.VariableNames)
            od.behDat.goodBreath = zeros(height(od.behDat), 1);
        end
    else
        n = height(od.behDat);
        od.behDat.goodBreath = nan(n, 1);
        od.behDat.maxRR      = nan(n, 1);
        od.behDat.minRR      = nan(n, 1);
        od.behDat.RR_max_min = nan(n, 1);
    end
end

function s = sanitizeStr(v)
    if iscell(v)
        v(cellfun(@(x) ~(ischar(x) && isrow(x)) && ~(isstring(x) && isscalar(x)), v)) = {'NA'};
    end
    s = string(v);
end

function F = appendFeat(F, name, v)
    v = v(:)';
    if ~isfield(F, name), F.(name) = v; else, F.(name) = [F.(name), v]; end
end

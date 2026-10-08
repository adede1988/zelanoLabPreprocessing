function outDat = build_behavior_table_respiratorySweep(outDat)
%BUILD_BEHAVIOR_TABLE_RESPIRATORYSWEEP  Per-breath behDat for respiratorySweep.
%
%   Consumes outDat.bmObj / bmFeatures, outDat.blocks (fs = 500 samples; built
%   by the main from the raw file's event table) and the ratings table that
%   assembleRaw_respiratorySweep left in outDat.behDat.
%
%   ONE ROW PER DETECTED BREATH OF THE WHOLE RECORDING (unlike
%   alternating6Blocks, breaths between blocks are kept - rests, instructions,
%   ratings - so transitions can be studied; filter on inBlock / blockType):
%     shared 14 base columns (behDatFromBreaths); condition = block order of
%       the block holding the inhale onset (bmObj col 12), 0 = between blocks
%     task        block label ('audiobook_pre', 'Sweep_b07_cpm15_depth0.85',
%                 'focusedBreathing_post1', ...) or 'none'
%     blockType   'audiobook' / 'sweep' / 'focusedBreathing' / 'none'
%     phase       'pre' / 'sweep' / 'post' / 'none'
%     inBlock     onset inside a block
%     cpm, depth, sweepNum   target pace (breaths/min), depth scale and pass
%                 number of a sweep block (NaN elsewhere)
%     noseMouth / shadowFile / warp   'NA' / 'NA' / NaN (breathing-layout
%                 compatibility; no stimulus files in this task)
%     rateBPM, localPeriodCV, localAmpCV, nSubPeaks   breath rate and local
%                 regularity, as in pacedBreathing (window of +/-3 breaths that
%                 never straddles a block edge; nSubPeaks = local maxima with
%                 prominence >= 15% of the breath amplitude, 100-ms smoothing)
%     bm_*        breathMetrics features (appendBmFeatureCols)
%   Ratings: outDat.ratings (long table, parse_sweepRatings), outDat.baseEmotion
%   (the 'baseline' set) and outDat.postSweepEmotion (the 'postSweep' set), one
%   row each in the alternating6Blocks baseEmotion layout (task / noseMouth /
%   shadowFile / warp + <Q_short>_<type>); empty tables when a set is missing.

    ratings = outDat.behDat;
    B = outDat.blocks;
    bmObj = outDat.bmObj;
    n = size(bmObj, 1);
    fs = outDat.fs;

    onsetSamp = round(bmObj(:, 2) * fs);
    blk = zeros(n, 1);
    for b = 1:height(B)
        blk(onsetSamp >= B.startSample(b) & onsetSamp <= B.endSample(b)) = b;
    end
    bmObj(:, 12) = blk;
    outDat.bmObj = bmObj;
    fprintf('%s: %d/%d breaths inside the %d blocks\n', outDat.sessID, sum(blk > 0), n, height(B));

    behDat = behDatFromBreaths(bmObj, size(outDat.data, 2), fs);   % shared 14 base columns
    idx = behDat.sniffOnset;

    inB = blk > 0;
    task = repmat("none", n, 1);      task(inB) = B.label(blk(inB));
    btyp = repmat("none", n, 1);      btyp(inB) = B.blockType(blk(inB));
    phase = repmat("none", n, 1);     phase(inB) = B.phase(blk(inB));
    cpm = nan(n, 1);                  cpm(inB) = B.cpm(blk(inB));
    depth = nan(n, 1);                depth(inB) = B.depth(blk(inB));
    sweepNum = nan(n, 1);             sweepNum(inB) = B.sweepNum(blk(inB));
    behDat.task       = cellstr(task);
    behDat.blockType  = btyp;
    behDat.phase      = phase;
    behDat.inBlock    = inB;
    behDat.cpm        = cpm;
    behDat.depth      = depth;
    behDat.sweepNum   = sweepNum;
    behDat.noseMouth  = repmat("NA", n, 1);
    behDat.shadowFile = repmat("NA", n, 1);
    behDat.warp       = nan(n, 1);

    % ---- rate + local regularity + sub-peak count (pacedBreathing measures) ----
    behDat.rateBPM = 60 ./ behDat.length;
    per = behDat.length; amp = behDat.amp;
    runId = cumsum([1; diff(blk) ~= 0]);          % contiguous stretches with one block index
    behDat.localPeriodCV = nan(n, 1);
    behDat.localAmpCV    = nan(n, 1);
    for b = 1:n
        w = max(1, b - 3):min(n, b + 3);
        w = w(runId(w) == runId(b));              % never straddle a block edge
        if numel(w) >= 4
            behDat.localPeriodCV(b) = std(per(w)) / mean(per(w));
            behDat.localAmpCV(b)    = std(amp(w)) / mean(amp(w));
        end
    end

    isRsp = cellfun(@(x) contains(x, 'rsp'), outDat.labels);
    rsp = outDat.data(isRsp, :);
    rsp = rsp(outDat.rspIDX, :) .* outDat.rspFlip;
    rspS = smoothdata(rsp, 'gaussian', round(0.1 * fs));
    behDat.nSubPeaks = nan(n, 1);
    for b = 1:n
        s0 = idx(b);
        if b < n, s1 = idx(b + 1) - 1; else, s1 = min(numel(rspS), s0 + round(behDat.length(b) * fs)); end
        if s1 - s0 < round(0.3 * fs) || ~isfinite(amp(b)) || amp(b) <= 0, continue; end
        seg = rspS(s0:s1);
        [~, pk] = findpeaks(seg, 'MinPeakProminence', 0.15 * amp(b), ...
                            'MinPeakDistance', max(1, round(0.15 * fs)));
        behDat.nSubPeaks(b) = numel(pk);
    end

    outDat.behDat = behDat;

    % ---- ratings ----
    outDat.ratings = ratings;
    outDat.baseEmotion      = ratingRow(ratings, "baseline");
    outDat.postSweepEmotion = ratingRow(ratings, "postSweep");

    % ---- bm_* columns (shared convention) ----
    outDat = appendBmFeatureCols(outDat, 'build_behavior_table_respiratorySweep');
end

function E = ratingRow(ratings, setName)
% one-row table in the alternating6Blocks baseEmotion layout; empty if absent
    E = table();
    if ~istable(ratings) || height(ratings) == 0 || ~ismember('set', ratings.Properties.VariableNames), return; end
    q = ratings(ratings.set == setName, :);
    if height(q) == 0, return; end
    E.task = setName;
    E.noseMouth = "NA";
    E.shadowFile = "NA";
    E.warp = NaN;
    for r = 1:height(q)
        E.(char(q.Q_short(r) + "_" + q.type(r))) = q.rsp(r);
    end
end

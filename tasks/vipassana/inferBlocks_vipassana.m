function [blocks, TTL, info] = inferBlocks_vipassana(evid, tSec, markersSec, fs, nSamp, opts)
%INFERBLOCKS_VIPASSANA  Protocol-constrained segmentation of a vipassana recording.
%
%   [blocks, TTL, info] = inferBlocks_vipassana(evid, tSec, markersSec, fs, nSamp)
%   [blocks, TTL, info] = inferBlocks_vipassana(evid, tSec, markersSec, fs, nSamp, opts)
%
%   Every vipassana recording follows one FIXED sequence of periods
%   (order 0..9):
%
%       0 pre             setup before the first audiobook (optional, may be 0 s)
%       1 audiobook1      ~5 min, still
%       2 anapana         15 min meditation, still
%       3 questionnaire1  ~2 min, movement
%       4 vipassana       15 min meditation, still
%       5 questionnaire2  ~2 min, movement
%       6 metta           8 min meditation, still
%       7 questionnaire3  ~2 min, movement
%       8 audiobook2      ~5 min, still
%       9 post            after audiobook2 (optional, may be 0 s)
%
%   so the labels are FIXED by position in the sequence (not positional
%   guesses as in pacedBreathing): only the 9 internal boundaries are
%   inferred. The hand-pressed markers (Stimulus 'S  1') are shaky and
%   incomplete (CC has 4 of 8, DD has an extra press and a double press), so
%   they are HINTS in the cost, never constraints. The data evidence is the
%   per-second activity series from artifactIndex_vipassana (high = movement
%   / EMG): still periods are long stretches of low evidence, the
%   questionnaires are stretches of high evidence.
%
%   Method - exact dynamic programme over a 1-s grid
%     Grid: second k (k = 1..T, T = floor(nSamp/fs)) spans [k-1, k) s; a
%     boundary sits at an integer position a = 0..T (s). evid is mapped onto
%     the grid centres (k - 0.5) by nearest-neighbour lookup in tSec (the
%     identity for the artifactIndex_vipassana output).
%     Cost of an assignment = sum over periods of
%       data cost   per second: still period  evid(t) - c0
%                               active period c1 - evid(t)
%                   (questionnaires are the active periods; pre is data-
%                   neutral (0) by default - opts.preCost - and post is
%                   active by default - opts.postCost)
%       duration    audiobook1/2      wDur*((d-audNom)/audSd)^2,   d in audLim (hard)
%                   anapana/vipassana wDur*((d-medNom)/medSd)^2,   d in medLim
%                   metta             wDur*((d-mettaNom)/mettaSd)^2, d in mettaLim
%                   questionnaires    wQ*(max(0, d-qSoftSec) + max(0, qSoftLoSec-d))/60,
%                                     d in qLim
%                   pre / post        wGap*d/60,  d in preLim / postLim (0 allowed)
%       marker      at every internal boundary position a (all 9, including
%                   pre|audiobook1 and audiobook2|post):
%                   -B * sum_m exp(-(a - m)^2 / (2*sigma^2)); with
%                   opts.markerDedup (default) the two boundaries a, b of a
%                   questionnaire share ONE bonus -B * sum_m max(k(a-m), k(b-m))
%                   so a single press cannot reward both
%     The data cost is O(1) per period from cumulative sums; the recursion
%       F_p(b) = C_p(b) + min_a [ F_{p-1}(a) + M(a) - C_p(a) + dur_p(b - a) ]
%     loops over periods and end positions b with a vectorised min over the
%     admissible start positions a (b - hi_p .. b - lo_p): O(T * maxDur) per
%     period. The global optimum ends post at T; back-tracking gives the 9
%     boundaries.
%   Boundary margins
%     For each internal boundary j the programme is re-solved with boundary j
%     forbidden within +/- marginWin s of its optimum. margin = altCost -
%     optCost (cost units; >= 0; Inf = no feasible alternative) and the
%     alternative position altSec are reported. A small margin (a few units)
%     means the data + markers barely prefer the chosen position over one at
%     least marginWin s away: review that boundary on the figure. For scale:
%     one second moved from the right to the wrong class costs c1 - c0 + |evid
%     difference|, i.e. about 0.5-3 units; a marker is worth up to B.
%   Markers
%     markersSec is filtered to finite values inside the recording, sorted,
%     and presses closer than mergeMarkerSec to the previous kept press are
%     dropped (a double press counts once).
%
%   Inputs
%     evid       : activity evidence per window (artifactIndex_vipassana .evid)
%     tSec       : window centres (s from the first sample), same length as evid
%     markersSec : marker times (s from the first sample; (sample-1)/fs), may be empty
%     fs         : sampling rate of the sample axis the blocks refer to (500)
%     nSamp      : number of samples of the recording at fs
%     opts       : optional struct; missing / empty fields take the defaults
%       c0 0.3, c1 0.8               still / active per-second cost offsets
%       wDur 20                      Gaussian duration-prior weight
%       audNom 300, audSd 90, audLim [150 540]        audiobook1/2 (s)
%       medNom 900, medSd 90, medLim [600 1200]       anapana, vipassana (s)
%       mettaNom 480, mettaSd 60, mettaLim [300 720]  metta (s)
%       qLim [60 1200], qSoftSec 240, qSoftLoSec 90,  questionnaires (qNom is only
%       wQ 5, qNom 120                                 reported as nominalSec)
%       preLim [0 1500], postLim [0 600], wGap 2      pre / post
%       preCost 'zero', postCost 'active'  data cost of pre / post: 'zero' (data-
%                                      neutral) or 'active' (c1 - evid)
%       B 60, sigma 20                 marker bonus height / width (s)
%       markerDedup true               one shared bonus for a questionnaire's 2 boundaries
%       mergeMarkerSec 5               double-press merge distance (s)
%       marginWin 60                   exclusion half-width for the margins (s)
%       markerNearSec 120              max |distance| for blocks.markerDistSec (s)
%
%   Outputs
%     blocks : table tiling the recording (zero-length pre / post rows dropped)
%       label               string, the fixed protocol label
%       order               protocol index 0..9 (0 = pre, 9 = post)
%       still               1 = task period (still EEG expected), 0 = pre / questionnaire / post
%       startSample         first sample at fs (1 for the first block)
%       endSample           last sample (= next block's startSample - 1; nSamp for the last)
%       durationSec         (endSample - startSample + 1) / fs
%       nominalSec          protocol duration (s); NaN for pre / post
%       meanEvid            mean grid evidence inside the block
%       markerDistSec       SIGNED distance of the nearest marker to the block start
%                           (marker time - start time, s; > 0 = marker after the start),
%                           NaN if no marker within markerNearSec
%       boundaryMarginStart margin (cost units) of the boundary that starts the block;
%                           NaN for a block starting at the recording start as pre
%     TTL    : breathing-style row vector of block-start samples (= blocks.startSample')
%     info   : struct (plain data, no function handles - it is saved in the .mat)
%       method, labelsFixed (= true), opts
%       markersSecInput, markersSec (after filtering / merging)
%       periodLabels (1x10 string), periodStill (1x10)
%       T (grid seconds), boundariesSec (1x11: start of periods 0..9, then T)
%       totalCost
%       costs      table per protocol period (all 10, zero-length ones included):
%                  label, order, startSec, endSec, durSec, dataCost, durPen, markerBonus, total
%                  (markerBonus = the bonus at the period's START boundary; with
%                  markerDedup a questionnaire row carries the shared bonus of both
%                  its boundaries and the period after it 0)
%       margins    table per internal boundary (9): boundary, before, after, optSec,
%                  altSec, margin, altTotalCost
%       altBoundariesSec [9 x 11]: the full alternative segmentation of each re-solve
%       evidence   table on the grid: tSec, evid, periodOrder (0..9), blkIdx
%       blkOfSec   [T x 1] row of blocks each grid second belongs to
%       Block of a sample s: find(blocks.startSample <= s, 1, 'last') (identical to
%       blkOfSec(floor((s-1)/fs)+1) for integer fs, because boundaries sit on whole
%       seconds).
%
%   Caveats
%     - The programme always returns the full protocol: it cannot detect a
%       missing or reordered period. A recording that deviates from the
%       protocol must get a per-session opts override (P.vipOpts) or it will
%       be forced into the sequence - review blocks_inferred.jpg.
%     - Boundaries are quantised to 1 s and located where the ACTIVITY changes
%       (the movement artifact starts / stops), which can differ by several
%       seconds from the instruction onset; downstream analyses should trim
%       a few seconds at each block edge.
%     - The still/active contrast is relative to a 10-min baseline: a still
%       period that is noisy throughout (bad electrodes) still segments, but
%       with smaller margins.
%     - The absolute cost values depend on opts; margins are comparable
%       within a recording and across recordings run with the same opts.
%
%   DEVIATIONS from the 2026-09-26 design spec (added after review; the
%   spec's behaviour is opts preCost 'active', audSd 60, preLim [0 900],
%   qLim [30 1200], qSoftLoSec 0, markerDedup false)
%     - pre is data-neutral (preCost 'zero'), audSd 60 -> 90, preLim 900 ->
%       1500 s. Priced as an active period, a quiet setup (or one whose EMG
%       the 10-min baseline absorbed) cost ~0.7/s - about 20x wGap - so the
%       programme stretched audiobook1 / anapana backwards to shrink pre:
%       260918_EEG_NWU_CC anapana started 137 s before its press (16.38 vs
%       18.67 min) and lasted 18 min; now 18.72 min, 15.6 min long. A
%       synthetic protocol with a 600-s quiet pre had worst errors of
%       422 / 303 s at boundaries 1 / 2 with all 9 markers; now 9 / 3 s. AS
%       and DD with markers are unchanged except the unmarked pre|audiobook1
%       of DD (2.15 -> 2.55 min). The AS audiobook1 is ~6.7 min between its
%       presses, hence the wider audiobook sd. Trade-off: without its press,
%       pre|audiobook1 is now held only by audiobook1's still evidence
%       (~0.3/s) against the duration prior - on the builder's synthetic
%       test1 (60-s ACTIVE pre, 400-s audiobook1) its worst error with that
%       press missing rose from 22 to 40 s, while the unmarked
%       audiobook1|anapana error fell from 70 to 51 s. post stays ACTIVE
%       (postCost 'active'): a data-neutral post absorbs a noisy recording
%       tail for free, which left the AS audiobook2|post boundary with a
%       margin of 1 and, without markers, collapsed AS questionnaire3 to 30 s.
%       (Real-session numbers measured on the evidence of the current
%       artifactIndex_vipassana, i.e. with its line-dominated rows excluded.)
%     - Questionnaires: markerDedup (one press cannot reward both boundaries
%       of a questionnaire - one press centred in a 30-s questionnaire earned
%       ~1.5*B), a lower-side soft prior below qSoftLoSec (90 s) and a 60-s
%       hard minimum (the protocol questionnaires take "a couple of
%       minutes"). CC questionnaire2 had collapsed to exactly 30 s straddling
%       its press (51.87-52.37 min); it is now 50.73-52.13 min (84 s), where
%       the 30-100 Hz power is raised, and metta starts at the press.

    if nargin < 6 || isempty(opts), opts = struct(); end
    dflt = struct('c0', 0.3, 'c1', 0.8, 'wDur', 20, ...
                  'audNom', 300, 'audSd', 90, 'audLim', [150 540], ...
                  'medNom', 900, 'medSd', 90, 'medLim', [600 1200], ...
                  'mettaNom', 480, 'mettaSd', 60, 'mettaLim', [300 720], ...
                  'qLim', [60 1200], 'qSoftSec', 240, 'qSoftLoSec', 90, 'wQ', 5, 'qNom', 120, ...
                  'preLim', [0 1500], 'postLim', [0 600], 'wGap', 2, 'preCost', 'zero', 'postCost', 'active', ...
                  'B', 60, 'sigma', 20, 'markerDedup', true, ...
                  'mergeMarkerSec', 5, 'marginWin', 60, 'markerNearSec', 120);
    fn = fieldnames(dflt);
    for k = 1:numel(fn)
        if ~isfield(opts, fn{k}) || isempty(opts.(fn{k})), opts.(fn{k}) = dflt.(fn{k}); end
    end
    opts.preCost  = lower(char(string(opts.preCost)));
    opts.postCost = lower(char(string(opts.postCost)));
    assert(all(ismember({opts.preCost, opts.postCost}, {'zero', 'active'})), ...
        'inferBlocks_vipassana: opts.preCost / opts.postCost must be ''zero'' or ''active''');
    opts.markerDedup = logical(opts.markerDedup);

    % ---- inputs ----
    evid = double(evid(:)); tSec = double(tSec(:));
    assert(numel(evid) == numel(tSec) && numel(evid) >= 10, ...
        'inferBlocks_vipassana: evid and tSec must be equal-length vectors (>= 10 values)');
    assert(any(isfinite(evid)), 'inferBlocks_vipassana: evid has no finite value');
    assert(isscalar(fs) && fs > 0 && isscalar(nSamp) && nSamp >= fs, 'inferBlocks_vipassana: bad fs / nSamp');
    T = floor(nSamp / fs);                               % grid seconds
    g = (1:T)' - 0.5;                                    % grid centres (s)
    ok = isfinite(evid) & isfinite(tSec);
    if numel(tSec) == T && all(ok) && max(abs(tSec - g)) < 1e-6
        e = evid;
    else
        e = interp1(tSec(ok), evid(ok), g, 'nearest', 'extrap');
    end

    % ---- markers ----
    if isempty(markersSec), markersSec = zeros(0, 1); end
    mIn = double(markersSec(:));
    m = sort(mIn(isfinite(mIn) & mIn >= 0 & mIn <= nSamp / fs));
    if numel(m) > 1
        keep = true(size(m)); last = m(1);
        for i = 2:numel(m)
            if m(i) - last < opts.mergeMarkerSec, keep(i) = false; else, last = m(i); end
        end
        m = m(keep);
    end

    % ---- protocol ----
    labels = ["pre", "audiobook1", "anapana", "questionnaire1", "vipassana", ...
              "questionnaire2", "metta", "questionnaire3", "audiobook2", "post"];
    still  = [0 1 1 0 1 0 1 0 1 0];
    nP = numel(labels);
    lims = [opts.preLim; opts.audLim; opts.medLim; opts.qLim; opts.medLim; ...
            opts.qLim; opts.mettaLim; opts.qLim; opts.audLim; opts.postLim];
    lims = round(lims);
    nomS = [NaN opts.audNom opts.medNom opts.qNom opts.medNom opts.qNom opts.mettaNom opts.qNom opts.audNom NaN];
    pen = cell(1, nP);                                   % pen{p}(d+1), d = 0..hi
    for p = 1:nP
        d = 0:lims(p, 2);
        switch labels(p)
            case {"audiobook1", "audiobook2"}, v = opts.wDur * ((d - opts.audNom) / opts.audSd) .^ 2;
            case {"anapana", "vipassana"},     v = opts.wDur * ((d - opts.medNom) / opts.medSd) .^ 2;
            case "metta",                      v = opts.wDur * ((d - opts.mettaNom) / opts.mettaSd) .^ 2;
            case {"pre", "post"},              v = opts.wGap * d / 60;
            otherwise                                                        % questionnaires
                v = opts.wQ * (max(0, d - opts.qSoftSec) + max(0, opts.qSoftLoSec - d)) / 60;
        end
        v(d < lims(p, 1)) = Inf;
        pen{p} = v(:);
    end
    assert(sum(lims(:, 1)) <= T && sum(lims(:, 2)) >= T, ...
        ['inferBlocks_vipassana: recording of %d s cannot hold the protocol (min %d s, max %d s) - ' ...
         'override the duration limits in P.vipOpts'], T, sum(lims(:, 1)), sum(lims(:, 2)));

    % cumulative data costs (index = position + 1, positions 0..T)
    Cst = [0; cumsum(e - opts.c0)];
    Cac = [0; cumsum(opts.c1 - e)];
    Cp  = cell(1, nP);
    for p = 1:nP, if still(p), Cp{p} = Cst; else, Cp{p} = Cac; end, end
    if strcmp(opts.preCost, 'zero'),  Cp{1}  = zeros(T + 1, 1); end   % data-neutral pre (see DEVIATIONS)
    if strcmp(opts.postCost, 'zero'), Cp{nP} = zeros(T + 1, 1); end
    pos = (0:T)';
    K = zeros(T + 1, numel(m));                          % marker kernels at each boundary position
    for i = 1:numel(m)
        K(:, i) = exp(-(pos - m(i)) .^ 2 / (2 * opts.sigma ^ 2));
    end
    Mb = -opts.B * sum(K, 2);                            % marker bonus at each boundary position
    MK = struct('Mb', Mb, 'K', K, 'B', opts.B, 'pairP', zeros(1, 0));
    if opts.markerDedup
        MK.pairP = find(startsWith(labels, "questionnaire"));   % periods whose 2 boundaries share a press
    end

    % ---- optimum ----
    [optCost, bOpt] = solveDP(Cp, pen, lims, MK, T, [], []);
    assert(isfinite(optCost), 'inferBlocks_vipassana: no feasible segmentation');

    % ---- margins: re-solve with each internal boundary forbidden near its optimum ----
    nBd = nP - 1;
    altSec = nan(nBd, 1); margin = inf(nBd, 1); altTot = inf(nBd, 1);
    altB = nan(nBd, nP + 1);
    for j = 1:nBd
        fwin = [max(0, bOpt(j + 1) - opts.marginWin), min(T, bOpt(j + 1) + opts.marginWin)];
        [c, bA] = solveDP(Cp, pen, lims, MK, T, j, fwin);
        altTot(j) = c;
        if isfinite(c)
            margin(j) = c - optCost; altSec(j) = bA(j + 1); altB(j, :) = bA;
        end
    end

    % ---- per-period cost breakdown ----
    cSt = bOpt(1:nP)'; cEn = bOpt(2:nP + 1)'; cD = cEn - cSt;
    dataCost = zeros(nP, 1); durPen = zeros(nP, 1); mkB = zeros(nP, 1);
    for p = 1:nP
        dataCost(p) = Cp{p}(cEn(p) + 1) - Cp{p}(cSt(p) + 1);
        durPen(p)   = pen{p}(cD(p) + 1);
        if ismember(p, MK.pairP)                         % de-duplicated pair bonus of both boundaries
            mkB(p) = pairBonus(MK, cSt(p), cEn(p));
        elseif p > 1 && ~ismember(p - 1, MK.pairP)       % start bonus (already in the pair after a questionnaire)
            mkB(p) = Mb(cSt(p) + 1);
        end
    end
    costs = table(labels(:), (0:nP - 1)', cSt, cEn, cD, dataCost, durPen, mkB, dataCost + durPen + mkB, ...
        'VariableNames', {'label', 'order', 'startSec', 'endSec', 'durSec', 'dataCost', 'durPen', 'markerBonus', 'total'});

    margins = table((1:nBd)', labels(1:nBd)', labels(2:nP)', bOpt(2:nP)', altSec, margin, altTot, ...
        'VariableNames', {'boundary', 'before', 'after', 'optSec', 'altSec', 'margin', 'altTotalCost'});

    % ---- blocks table ----
    keepP = find(cD > 0);                                % pre / post may be empty
    nB = numel(keepP);
    startSec = cSt(keepP);
    startSample = round(startSec * fs) + 1; startSample(1) = 1;
    endSample = [startSample(2:nB) - 1; nSamp];
    blkOfSec = zeros(T, 1); perOfSec = zeros(T, 1);
    for b = 1:nB
        p = keepP(b);
        blkOfSec(cSt(p) + 1:cEn(p)) = b;
        perOfSec(cSt(p) + 1:cEn(p)) = p - 1;
    end
    assert(all(blkOfSec > 0), 'inferBlocks_vipassana: internal error, grid not tiled');

    blocks = table();
    blocks.label       = labels(keepP)';
    blocks.order       = keepP - 1;
    blocks.still       = still(keepP)';
    blocks.startSample = startSample;
    blocks.endSample   = endSample;
    blocks.durationSec = (endSample - startSample + 1) / fs;
    blocks.nominalSec  = nomS(keepP)';
    blocks.meanEvid    = arrayfun(@(b) mean(e(blkOfSec == b)), (1:nB)');
    mkD = nan(nB, 1);
    for b = 1:nB
        if isempty(m), break; end
        [dm, i] = min(abs(m - startSec(b)));
        if dm <= opts.markerNearSec, mkD(b) = m(i) - startSec(b); end
    end
    blocks.markerDistSec = mkD;
    bm = nan(nB, 1);
    for b = 1:nB
        o = keepP(b) - 1;                                % boundary index j = order (1..9)
        if o >= 1, bm(b) = margin(o); end
    end
    blocks.boundaryMarginStart = bm;
    assert(blocks.startSample(1) == 1 && blocks.endSample(end) == nSamp && ...
           all(blocks.startSample(2:end) == blocks.endSample(1:end-1) + 1) && ...
           all(blocks.endSample >= blocks.startSample), 'inferBlocks_vipassana: blocks do not tile 1..nSamp');

    TTL = blocks.startSample';

    % ---- info ----
    info = struct();
    dedupTxt = '';
    if opts.markerDedup, dedupTxt = ' (one shared bonus per questionnaire)'; end
    info.method = ['inferBlocks_vipassana: exact 1-s dynamic programme over the fixed 10-period protocol ' ...
                   '(still cost evid-c0 / active cost c1-evid, pre ' opts.preCost ' / post ' opts.postCost ' data cost, ' ...
                   'Gaussian duration priors with hard bounds, questionnaire soft caps on both sides, pre/post gap ' ...
                   'penalty, Gaussian marker bonus on internal boundaries' dedupTxt '); ' ...
                   'margins by re-solving with each boundary forbidden within +/- marginWin s'];
    info.labelsFixed     = true;
    info.opts            = opts;
    info.markersSecInput = mIn(:)';
    info.markersSec      = m(:)';
    info.periodLabels    = labels;
    info.periodStill     = still;
    info.T               = T;
    info.boundariesSec   = bOpt;
    info.totalCost       = optCost;
    info.costs           = costs;
    info.margins         = margins;
    info.altBoundariesSec = altB;
    info.evidence        = table(g, e, perOfSec, blkOfSec, 'VariableNames', {'tSec', 'evid', 'periodOrder', 'blkIdx'});
    info.blkOfSec        = blkOfSec;

    fprintf('inferBlocks_vipassana: T = %d s, %d markers used, total cost %.1f, min margin %.1f (boundary %s|%s)\n', ...
        T, numel(m), optCost, min(margin), margins.before(find(margin == min(margin), 1)), ...
        margins.after(find(margin == min(margin), 1)));
    for b = 1:nB
        fprintf('   %-15s start %6.2f min  dur %5.2f min  meanEvid %5.2f  marker %7s  margin %s\n', ...
            blocks.label(b), (blocks.startSample(b) - 1) / fs / 60, blocks.durationSec(b) / 60, blocks.meanEvid(b), ...
            num2strNaN(blocks.markerDistSec(b), '%+.0fs'), num2strNaN(blocks.boundaryMarginStart(b), '%.1f'));
    end
end

% ============================ helpers ============================

function [cost, bnd] = solveDP(Cp, pen, lims, MK, T, jForbid, fwin)
% Exact DP over boundary positions 0..T. bnd(p) = start of period p (s),
% bnd(nP+1) = T. Boundary j (= start of period j+1) is forbidden inside
% fwin = [lo hi] when jForbid is given. MK: marker bonus - Mb (per boundary
% position), K (per position x marker kernels), B, pairP (periods whose start
% AND end boundaries share one de-duplicated bonus, added inside the period).
    nP = numel(Cp);
    Mb = MK.Mb;
    F   = inf(nP, T + 1);
    arg = zeros(nP, T + 1);
    minCum = cumsum(lims(:, 1)); maxCum = cumsum(lims(:, 2));
    restMin = [flipud(cumsum(flipud(lims(2:end, 1)))); 0];   % sum of minima of periods after p
    % period 1 starts at 0
    bLo = lims(1, 1); bHi = min([lims(1, 2), T - restMin(1)]);
    if bHi >= bLo
        b = (bLo:bHi)';
        F(1, b + 1) = Cp{1}(b + 1) - Cp{1}(1) + pen{1}(b + 1);
    end
    for p = 2:nP
        isPair = ismember(p, MK.pairP);                      % bonus of both boundaries added below
        if isPair || ismember(p - 1, MK.pairP)               % start = end of a pair period: already counted
            G = F(p - 1, :)' - Cp{p};
        else
            G = F(p - 1, :)' + Mb - Cp{p};                   % function of the start position a
        end
        if ~isempty(jForbid) && jForbid == p - 1
            G(fwin(1) + 1:fwin(2) + 1) = Inf;
        end
        lo = lims(p, 1); hi = lims(p, 2); pv = pen{p};
        if p == nP
            bRange = T;
        else
            bRange = max(minCum(p), 0):min(maxCum(p), T - restMin(p));
        end
        for b = bRange
            aLo = max(0, b - hi); aHi = b - lo;
            if aHi < aLo, continue; end
            v = G(aLo + 1:aHi + 1) + pv(b - aLo + 1:-1:lo + 1);
            if isPair
                v = v + pairBonus(MK, (aLo:aHi)', b);
            end
            [mv, i] = min(v);
            if isfinite(mv)
                F(p, b + 1) = Cp{p}(b + 1) + mv;
                arg(p, b + 1) = aLo + i - 1;
            end
        end
    end
    cost = F(nP, T + 1);
    bnd = zeros(1, nP + 1); bnd(nP + 1) = T;
    if ~isfinite(cost), bnd(:) = NaN; return; end
    for p = nP:-1:2
        bnd(p) = arg(p, bnd(p + 1) + 1);
    end
    bnd(1) = 0;
end

function v = pairBonus(MK, a, b)
% De-duplicated marker bonus of a period spanning a..b (a: vector of start
% positions, b: scalar end position): -B * sum_m max(k(a - m), k(b - m)), so
% each press rewards at most ONE of the period's two boundaries. Computed as
% Mb(a) minus the extra of the presses near b.
    v = MK.Mb(a + 1);
    if isempty(MK.K), return; end
    kb = MK.K(b + 1, :);
    for i = find(kb > 1e-12)
        v = v - MK.B * max(0, kb(i) - MK.K(a + 1, i));
    end
end

function s = num2strNaN(x, f)
    if isnan(x), s = '-'; else, s = sprintf(f, x); end
end

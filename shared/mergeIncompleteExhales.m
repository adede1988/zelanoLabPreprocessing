function [bmObj, bmFeatures, info] = mergeIncompleteExhales(bmObj, bmFeatures, rsp, fs, exFrac, minorFrac)
% mergeIncompleteExhales  an inhale is not a new breath unless there has been an exhale since the last one.
%
%   [bmObj, bmFeatures, info] = mergeIncompleteExhales(bmObj, bmFeatures, rsp, fs, exFrac, minorFrac)
%
% Rule (user, 2026-10-15; respiratorySweep): walking the breaths of the LOCKED engine
% (segmentBreaths_zlp, untouched - this runs after it, like mergeCyclicSighBreaths) in order,
% breath k is NOT a new breath when the exhale since the last counted inhale onset is below
% exFrac (default 0.20) x the inhale since that onset; it is merged into the counted breath. A
% double inhale (two pulses with no real exhale between, e.g. 261007_EEG_NWU_AL 2551 s) and a
% chain of pulses all become one breath.
%
% Volumes = areas of the respiration trace above (inhale) / below (exhale) the ZERO-FLOW level,
% summed over everything since the last counted onset, [onset(c), onset(k)). Zero-flow level = the
% rest level at the detected inhale onsets: the trace value at each onset, moving median over
% +-30 s, interpolated in time (an onset is where an inhale leaves rest; the 60-s moving mean is
% pulled below rest by long exhales and pauses, and breathmetrics' exhaleVolumes integrate |trace|
% over its exhale window, so a dip that never goes below zero flow still gets a sizeable "exhale
% volume" - AL 2551 s: bm 39 % of the inhale, true area below zero flow 0 %).
%
% Minor-pulse guard (minorFrac, default 0.30; 0 = off): when the merged run's FIRST pulse is minor -
% its peak above the rest level below minorFrac x the run's highest pulse peak - it is not an inhale
% but a bump in the pause after the previous exhale (the engine can mark one there, e.g. RC 1971 s),
% and keeping its onset would start the breath seconds early. The run then starts at its first
% major pulse; the minor pulse's span goes to the breath before (that breath's pause). Otherwise
% the merged breath starts at its first pulse (keep-first).
%
% Merged breath (kept row) absorbs the rows after it: end (cols 5-7) = the last absorbed row's end;
% inhale peak (cols 3, 4, 9) = the highest pulse peak; exhale trough (cols 10-11) = the lowest
% trough; amplitude (col 8) recomputed. bmFeatures per-breath arrays are NOT rebuilt (as
% mergeCyclicSighBreaths): bmObjBreathIdx keeps the kept row's own feature index, so the bm_*
% columns of a merged breath describe its first (major) pulse only; info.nPulses / inhaleArea /
% exhaleArea describe the merged breath itself. A row given to the breath before (minor pulse)
% only extends that breath's end.
%
% info: exFrac, minorFrac, zeroFlow ('onset rest level, +-30 s moving median'), nBefore, nAfter,
% nMerged (pulses merged away), nMinorReassigned, and per KEPT row: nPulses, inhaleArea, exhaleArea
% (trace units x ms, over the final breath), exInRatio, origRows (cell of the engine rows it holds).

    if nargin < 5 || isempty(exFrac), exFrac = 0.20; end
    if nargin < 6 || isempty(minorFrac), minorFrac = 0.30; end
    x = fillmissing(double(rsp(:)'), 'linear', 'EndValues', 'nearest');
    N = numel(x);
    n0 = size(bmObj, 1);
    on = min(max(round(bmObj(:, 2) * fs), 1), N);      % onset samples (the engine stores sample / fs)
    en = min(max(round(bmObj(:, 6) * fs), 1), N);      % breath end = next onset
    pk = min(max(round(bmObj(:, 4) * fs), 1), N);

    % zero-flow level: rest level at the onsets
    tO = on / fs; vO = x(on);
    medO = zeros(n0, 1);
    for k = 1:n0, medO(k) = median(vO(abs(tO - tO(k)) <= 30)); end
    if n0 >= 2
        z = interp1(on, medO, 1:N, 'linear', 'extrap');
    else
        z = repmat(medO, 1, N);
    end
    pkH = x(pk)' - z(pk)';                             % pulse peak above rest

    % ---- pass 1: groups of consecutive rows with no exhale between their onsets ----
    grp = zeros(n0, 1); grp(1) = 1; c = 1;
    for k = 2:n0
        seg = x(on(c):max(on(c), on(k) - 1)) - z(on(c):max(on(c), on(k) - 1));
        I = sum(seg(seg > 0)); E = -sum(seg(seg < 0));
        if E < exFrac * I
            grp(k) = grp(c);                           % k is not a new breath
        else
            c = k; grp(k) = grp(k - 1) + 1;
        end
    end

    % ---- pass 2: minor first pulse -> the run starts at its first major pulse ----
    owner = (1:n0)';                                    % row whose kept breath absorbs each row
    nMinor = 0;
    for g = unique(grp)'
        r = find(grp == g);
        if numel(r) < 2, continue; end
        first = r(1);
        if minorFrac > 0
            major = r(pkH(r) >= minorFrac * max(pkH(r)));
            if major(1) ~= first && first > 1
                minor = r(r < major(1));
                owner(minor) = owner(first - 1);       % the pause bump belongs to the breath before
                nMinor = nMinor + numel(minor);
                first = major(1);
                r = r(r >= first);
            end
        end
        owner(r) = first;
    end
    % resolve chains (a minor row's owner may itself be owned)
    for k = 1:n0, while owner(k) ~= owner(owner(k)), owner(k) = owner(owner(k)); end, end

    % ---- build the merged rows ----
    keepRows = find(owner == (1:n0)');
    nK = numel(keepRows);
    nP = zeros(nK, 1); origRows = cell(nK, 1); inA = nan(nK, 1); exA = nan(nK, 1);
    for q = 1:nK
        kr = keepRows(q);
        mem = find(owner == kr);
        origRows{q} = mem';
        last = mem(end);
        % pulses = rows of the merge run (minor rows handed over only extend the end)
        pulses = mem(grp(mem) == grp(kr) & mem >= kr);
        nP(q) = numel(pulses);
        bmObj(kr, 5) = bmObj(last, 5); bmObj(kr, 6) = bmObj(last, 6);
        bmObj(kr, 7) = bmObj(kr, 6) - bmObj(kr, 2);
        [~, ip] = max(pkH(pulses));
        bmObj(kr, [3 4 9]) = bmObj(pulses(ip), [3 4 9]);
        [~, it] = min(bmObj(mem, 10));
        bmObj(kr, [10 11]) = bmObj(mem(it), [10 11]);
        bmObj(kr, 8) = bmObj(kr, 3) - (bmObj(kr, 1) + bmObj(kr, 5)) / 2;
        seg = x(on(kr):max(on(kr), en(last) - 1)) - z(on(kr):max(on(kr), en(last) - 1));
        inA(q) = sum(seg(seg > 0)) / fs * 1000; exA(q) = -sum(seg(seg < 0)) / fs * 1000;
    end
    bmObj = bmObj(keepRows, :);
    bmObj(:, 14) = 1:nK;
    if isfield(bmFeatures, 'bmObjBreathIdx')
        bmFeatures.bmObjBreathIdx = bmFeatures.bmObjBreathIdx(keepRows);
        bmFeatures.nBreathsSegmented = nK;
    end
    info = struct('rule', sprintf(['an inhale is not a new breath unless the exhale since the last counted ' ...
        'inhale onset is >= %g x its inhale (areas below / above zero flow); minor first pulses (< %g x the ' ...
        'run''s highest peak) go to the breath before'], exFrac, minorFrac), ...
        'exFrac', exFrac, 'minorFrac', minorFrac, 'zeroFlow', 'onset rest level (+-30 s moving median of the trace at the inhale onsets)', ...
        'nBefore', n0, 'nAfter', nK, 'nMerged', n0 - nK, 'nMinorReassigned', nMinor, ...
        'nPulses', nP, 'inhaleArea', inA, 'exhaleArea', exA, 'exInRatio', exA ./ inA, 'origRows', {origRows});
    if isfield(bmFeatures, 'conditioning')
        bmFeatures.conditioning.incompleteExhaleMerge = rmfield(info, {'nPulses', 'inhaleArea', 'exhaleArea', 'exInRatio', 'origRows'});
    end
end

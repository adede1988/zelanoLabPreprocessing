function outDat = preprocess_eeg(outDat, standardEEGlocs, P)



    %check electrode names
    for chan = 1:32
        if ~strcmp(standardEEGlocs.Label(chan), outDat.labels(chan))
            error('EEG channels not labeled as expected')
        end
    end

    phi = standardEEGlocs.phi_deg .*pi ./ 180; 
    theta = standardEEGlocs.theta_deg .*pi ./ 180; 
    X = standardEEGlocs.X_nose_m;
    Y = standardEEGlocs.Y_left_m; 
    Z = standardEEGlocs.Z_up_m; 

    lbls = string(outDat.labels(1:32));
    lbls = reshape(lbls, [length(lbls), 1]);

    outDat.eegLocs = table(lbls, 'VariableNames', {'labels'}); 
    outDat.eegLocs.X = X; 
    outDat.eegLocs.Y = Y; 
    outDat.eegLocs.Z = Z; 
    outDat.eegLocs.theta = theta; 
    outDat.eegLocs.phi = phi; 
    outDat.eegLocs.X_flat = standardEEGlocs.X2D_right;
    outDat.eegLocs.Y_flat = standardEEGlocs.Y2D_front; 
    
    % Optional P.eegClean (struct): .mode 'fixed' (default since 2026-10-14,
    % tasks_261014 task 10: trial purges / recording gaps no longer count as
    % evidence against every channel) | 'band' (fixed + amplitude statistics
    % on a 1-40 Hz copy; .statBand) | 'legacy' (the pre-2026-10-14 detector,
    % verbatim) - see removeNoiseChansVolt. The decision is recorded in
    % outDat.EEGCleaningInfo.
    cleanOpts = struct();
    if isstruct(P) && isfield(P, 'eegClean') && isstruct(P.eegClean)
        cleanOpts = P.eegClean;
    end
    % the detector set (removeNoiseChansVolt.m + removeNoiseChansVolt_legacy.m
    % + this file + concatSections.m) is deployed together: fail loudly on a
    % stale detector rather than with "too many input arguments"
    if nargin('removeNoiseChansVolt') < 5
        error('preprocess_eeg:staleDetector', ...
            ['%s takes %d inputs; preprocess_eeg needs the 2026-10-14 removeNoiseChansVolt ' ...
             '(5th input opts) - deploy shared/removeNoiseChansVolt.m, removeNoiseChansVolt_legacy.m, ' ...
             'preprocess_eeg.m, blinkRemoveWrapper.m and tasks/breathingSeparate/concatSections.m together'], ...
            which('removeNoiseChansVolt'), nargin('removeNoiseChansVolt'));
    end
    [badTS, badChans, outDat.data(1:32,:), interpChan, cleanInfo] = ...
            removeNoiseChansVolt(outDat.data(1:32,:), outDat.fs, [1 32], outDat.eegLocs, cleanOpts);
    if strcmp(cleanInfo.mode, 'legacy')
        title(outDat.sessID, 'interpreter', 'none')   % the legacy detector's QC figure
    end
    EXEMPT = [1 32];
    detBad = unique(badChans(:));
     % only non-exempt get flagged
    badChans = setdiff(unique(badChans(:)), EXEMPT);

    % 3) Build good-channel index for blink removal
    chanIDX = setdiff(1:32, badChans);% includes 1 & 32 even if detected bad


    % Optional task-level flag P.blinkRemoval (set by applyParams; absent or
    % true = blink removal runs, the default for every task). false = the
    % task has no blinks to remove (vipassana: eyes closed throughout); it
    % takes the SAME degrade path as "both blink channels bad" below, so bad-
    % channel handling, the interpolated copy for the Laplacian, dataLap,
    % badTS / interpChan and outDat.blinkRemoval = 0 are exactly as there.
    skipBlink = isstruct(P) && isfield(P, 'blinkRemoval') && ...
        ~isempty(P.blinkRemoval) && ~P.blinkRemoval;

    blinkBad  = [];      % channels the blink stage adds (blinkRemoveWrapper's own tests)
    blinkGate = false;   % 'fixed' / 'band': the blink stage's tests left <= 10 good channels
    lapOK = length(chanIDX) > 10;
    if lapOK
    % 4) Blink removal on good channels. If BOTH candidate blink channels are
    % bad (blinkRemoveWrapper's own criteria) blink removal is impossible for
    % this session: degrade to blinkRemoval=0 (the already-defined state) and
    % keep the rest of the EEG stage rather than losing the session - REVIEW
    if skipBlink
        fprintf('%s: P.blinkRemoval = false (task setting) - blink removal not run\n', ...
            outDat.sessID);
        out = outDat.data(1:32, :);
        badChan2 = [];
        blinkOK = false;
        % per-session reason (applyParams P.blinkRemovalReason), when given
        if isfield(P, 'blinkRemovalReason') && ~isempty(P.blinkRemovalReason)
            outDat.blinkRemovalNote = P.blinkRemovalReason;
        end
    else
    try
        % optional P.blinkSelect (struct: selectMode 'frontal' default |
        % 'legacy', minFrontRatio, minRefCorr) - see blinkRemoveWrapper
        blinkOpts = struct();
        if isstruct(P) && isfield(P, 'blinkSelect') && isstruct(P.blinkSelect)
            blinkOpts = P.blinkSelect;
        end
        blinkOpts.badTS = badTS;   % keep the ICA training window off rejected 2-s trials
        if ~strcmp(cleanInfo.mode, 'legacy')
            % 'fixed' / 'band' (2026-10-15, tasks_261014 task 10): the blink
            % stage's own bad-channel tests ignore badTS epochs too (purges /
            % gaps are not evidence against one channel), and the > 10-good-
            % channel requirement is applied to what survives those tests
            % (else ICA would run on a handful of channels and dataLap be
            % interpolated from them)
            blinkOpts.chanTestBadTS = true;
            blinkOpts.minGood = 11;
        end
        [out, badChan2, blinkIndicator, blinkSel] = blinkRemoveWrapper(outDat,...
                                                    chanIDX,...
                                                    outDat.fs, interpChan, blinkOpts);
        if isfield(blinkOpts, 'chanTestBadTS') && ~isfield(blinkSel, 'chanTestBadTS')
            error('preprocess_eeg:staleBlinkWrapper', ...
                ['%s ignored opts.chanTestBadTS / minGood - deploy the 2026-10-15 ' ...
                 'shared/blinkRemoveWrapper.m with this file (tasks_261014 task 10)'], ...
                which('blinkRemoveWrapper'));
        end
        if isfield(blinkSel, 'skipped') && blinkSel.skipped
            warning('preprocess_eeg:blinkStageGate', '%s: %s - no blink removal, no dataLap', ...
                outDat.sessID, blinkSel.reason);
            blinkGate = true;
            blinkOK = false;
        else
            outDat.blinkICA = blinkSel;
            blinkOK = true;
        end
    catch MEblink
        if contains(MEblink.message, 'no available blink chan')
            warning('%s: both blink channels bad - blink removal SKIPPED, REVIEW', ...
                outDat.sessID);
            out = outDat.data(1:32, :);
            badChan2 = [];
            blinkOK = false;
        else
            rethrow(MEblink);
        end
    end
    end

    tmp = chanIDX(badChan2);
    badChans = [badChans(:); tmp(:)];
    blinkBad = tmp(:);
    lapOK = ~blinkGate;   % blinkGate: same outputs as <= 10 good channels (below)
    end

    if lapOK
    % Interpolate bad channels into a TEMPORARY copy used ONLY for the surface
    % Laplacian. The Laplacian is a spatial high-pass and is corrupted by bad
    % channels, so they must be interpolated before it is computed. The
    % broadband data written back to outDat.data below keeps the bad channels
    % at their real (blink-cleaned) values, leaving their disposition to the
    % end user. Epoch-wise interpolation and blink removal have already
    % removed the worst transient artifact from those real values.
    % (The interpolation keeps the electrodes' own 3-D geometry: leaving that
    % geometry unchanged predicts held-out channels clearly better than a
    % spherical projection - 2026-10-22 hold-out test.)
    if ~isempty(badChans)
        lapInput = interpolate_perrinX(out, X, Y, Z, badChans);
    else
        lapInput = out;
    end
    % The Laplacian is a SPHERICAL-spline method (Perrin et al. 1989): its
    % cos(angle) = 1 - d^2/2 holds only for electrodes on one sphere. Fed the
    % head coordinates of eegLocs_standard_coords.csv (radii 0.081-0.114 m from
    % the coordinate origin, which is ~1.7 cm in front of the head centre) it
    % returned a common-mode signal (97 % of the variance in the channel mean,
    % median inter-channel |r| 0.98 - found 2026-09-27). Since 2026-10-22 the
    % electrodes are projected onto the unit sphere around the least-squares
    % sphere centre (lapSphereCoords); the result equals FieldTrip's spline
    % ft_scalpcurrentdensity up to scale. Finals made before that date carry the
    % common-mode dataLap and have no outDat.dataLapGeometry.
    [Xs, Ys, Zs, lapGeom] = lapSphereCoords(X, Y, Z);
    dataLap = laplacian_perrinX(lapInput, Xs, Ys, Zs);


    outDat.badChans = outDat.labels(badChans);
    outDat.dataLap = dataLap;
    outDat.dataLapGeometry = lapGeom;
    % dataLap was computed on a copy with badChans interpolated, so it carries
    % no independent information at those sites; mask outDat.badChans for any
    % per-channel Laplacian analysis.
    outDat.dataLapFromInterp = 1; 
    outDat.data(1:32,:) = out;
    if blinkOK
        outDat.data(end+1, :,:) = blinkIndicator;
        outDat.labels{end+1} = "blinkIndicator";
    end
    outDat.data(end+1, :,:) = badTS;
    outDat.labels{end+1} = "badTS";
    outDat.data(end+1, :,:) = interpChan;
    outDat.labels{end+1} = "interpChan";
    outDat.EEGInterpolation = 1;
    outDat.EEGCleaning = 1;
    outDat.blinkRemoval = double(blinkOK);

    else

    outDat.badChans = outDat.labels(badChans); 
    outDat.dataLap = []; 
    outDat.dataLapFromInterp = 0; 
    % outDat.data(1:32,:) = ephysDat; 
    % outDat.data(end+1, :,:) = blinkIndicator; 
    % outDat.labels{end+1} = "blinkIndicator";
    outDat.data(end+1, :,:) = badTS; 
    outDat.labels{end+1} = "badTS";
    outDat.data(end+1, :,:) = interpChan; 
    outDat.labels{end+1} = "interpChan";
    outDat.EEGInterpolation = 1;
    outDat.EEGCleaning = 1;
    outDat.blinkRemoval = 0;




    end

    % Record of the cleaning decision (2026-10-14). outDat.EEGCleaning stays
    % the scalar 1 that downstream code reads; this struct says HOW: detector
    % mode/version, which stage flagged which channel, purge / gap fractions
    % and the detector's per-rule record (channel fields as labels).
    lbl = @(ix) cellstr(string(outDat.labels(ix(:)')));
    detRec = cleanInfo;
    for fn = {'outBad', 'chanRuleBad', 'p2ChanInitial', 'p2ChanFinal'}
        if isfield(detRec, fn{1}), detRec.(fn{1}) = lbl(detRec.(fn{1})); end
    end
    rec = struct();
    rec.mode          = cleanInfo.mode;
    rec.version       = cleanInfo.version;
    % detector rule U: fewer than max(6, 10 %) of the 2-s trials judged ->
    % every channel bad (fixed / band only; legacy collapses such recordings
    % by its own rules)
    rec.unjudgeable   = isfield(cleanInfo, 'unjudgeable') && cleanInfo.unjudgeable;
    rec.detectorBad   = lbl(detBad);                     % removeNoiseChansVolt verdict
    rec.exemptIgnored = lbl(intersect(detBad, EXEMPT));  % flagged Fp1/Fp2, kept (EXEMPT)
    rec.blinkStageBad = lbl(blinkBad);                   % added by blinkRemoveWrapper
    rec.nBad          = numel(outDat.badChans);
    rec.nGoodForBlink = numel(chanIDX);                  % blink removal / dataLap need > 10
    rec.nGoodAfterBlinkStage = numel(chanIDX) - numel(blinkBad);
    rec.blinkGate     = blinkGate;   % fixed / band: blink-stage tests left <= 10 good -> no ICA, no dataLap
    rec.fracBadTS     = mean(badTS ~= 0);
    rec.fracInterp    = mean(interpChan > 0);
    rec.detector      = detRec;
    outDat.EEGCleaningInfo = rec;








end


function [xs, ys, zs, info] = lapSphereCoords(x, y, z)
%LAPSPHERECOORDS  Electrode coordinates on the unit sphere for laplacian_perrinX.
%   Fits a sphere to the electrodes by least squares (centre c, radius R:
%   |p|^2 = 2 p.c + (R^2 - |c|^2), linear in c) and returns the unit vectors
%   (p - c)/|p - c|. Deterministic. For config/eegLocs_standard_coords.csv the
%   centre is ~1.7 cm behind the coordinate origin and the fitted radii are
%   0.083-0.104 m (CV 0.06; from the origin 0.081-0.114 m, CV 0.11).
%   info: centre (m, same frame as eegLocs X/Y/Z), radiusM (mean distance to the
%   centre; dataLap is per unit-sphere^2 - divide by radiusM^2 for per m^2),
%   radiusCV, radiusMinMax, method. Validated 2026-10-22 against FieldTrip
%   ft_scalpcurrentdensity (spline; same fit): per-sample spatial correlation 1.000.
    x = x(:); y = y(:); z = z(:);
    sol = [2*x 2*y 2*z ones(numel(x), 1)] \ (x.^2 + y.^2 + z.^2);
    c = sol(1:3)';
    d = [x y z] - c;
    r = sqrt(sum(d.^2, 2));
    xs = d(:, 1) ./ r;  ys = d(:, 2) ./ r;  zs = d(:, 3) ./ r;
    info = struct('method', 'least-squares sphere through the electrodes, radial projection from its centre', ...
        'centre', c, 'radiusM', mean(r), 'radiusCV', std(r) / mean(r), 'radiusMinMax', [min(r) max(r)], ...
        'note', ['dataLap = laplacian_perrinX of the 32 rows (bad channels interpolated) on these unit-sphere ' ...
                 'coordinates, per unit-sphere^2; finals made before 2026-10-22 have no dataLapGeometry and a common-mode dataLap']);
end

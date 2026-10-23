function [badTS, badChans, newEEG, interpChan, info] = removeNoiseChansVolt(EEG, fs, skipChans, chanLocs, opts)
%REMOVENOISECHANSVOLT  Voltage-threshold bad-channel / bad-time detector with
%per-trial spatial repair of transiently bad channels (the EEG stage's first
%step, called by preprocess_eeg on rows 1:32).
%
%   [badTS, badChans, newEEG, interpChan, info] = ...
%       removeNoiseChansVolt(EEG, fs, skipChans, chanLocs, opts)
%
%input:
%       EEG         channels X time matrix of EEG data (microvolts)
%       fs          sampling rate in Hz
%       skipChans   vector of channel indices to protect from high-amplitude
%                   flagging (e.g. EOG, which is legitimately high-amplitude
%                   and should not be removed for exceeding the voltage
%                   thresholds). These channels ARE still eligible to be
%                   flagged and removed if flat/dead.
%       chanLocs    struct/table with fields .X .Y .Z giving channel
%                   coordinates, used for Perrin spherical-spline interpolation
%       opts        optional struct (preprocess_eeg passes P.eegClean):
%         .mode     'fixed'  (DEFAULT since 2026-10-14) the detector below
%                   'band'   'fixed' + every amplitude statistic computed on a
%                            1-40 Hz band-passed COPY of the data (opts.statBand;
%                            the data written back stay broadband - no filter
%                            reaches outDat.data); the flat / dead and recording-
%                            gap tests stay broadband. Policy option: "bad" =
%                            bad in the analysis band, not "carries EMG / line
%                            noise" (see the 2026-10-14 EEG audit). Each 2-s
%                            trial is judged on its OWN band content: see
%                            "BAND COPY" below.
%                   'legacy' the pre-2026-10-14 function, verbatim
%                            (removeNoiseChansVolt_legacy.m - a separate file
%                            that must be deployed with this one), incl. its
%                            QC figure
%         .statBand [lo hi] Hz for 'band' (default [1 40])
%       'fixed' / 'band' require finite EEG (error removeNoiseChansVolt:nonFinite;
%       NaN gaps are filled upstream by the makeOutDats). 'legacy' left a NaN
%       channel silently unflagged.
%
%output:
%       badTS       L X 1 binary time mask: 2-s trials to drop entirely. A
%                   trial is bad when it was PURGED (too many channels over
%                   threshold at once, or a recording gap where every channel
%                   is flat) or when every channel carries a channel-specific
%                   flag. The final trial is forced to 0.
%       badChans    unique channel indices to treat as bad: (a) channels with
%                   channel-specific flags in >= 60 % of the JUDGED (= not
%                   purged, not gap) trials, plus (b) channels the pass-1
%                   blockwise detector flags in > 50 % of the judged trials.
%                   When fewer than 10 % of the trials (and at least 6 =
%                   one block) are judged, no channel can be judged and
%                   EVERY channel is returned (rule U below). They are NOT
%                   removed from newEEG; removal is left to the caller.
%       newEEG      channels X time cleaned data, same shape as EEG, with
%                   transiently bad channels spatially interpolated per 2-s
%                   trial (only where fewer than half the channels were
%                   flagged in that trial). Gap and pass-1-purged trials
%                   are in no block, so nothing is repaired in them (newEEG
%                   = EEG there, interpChan 0).
%       interpChan  L X 1 count, per timepoint, of how many channels were
%                   interpolated in the covering trial (repair intensity).
%       info        struct recording what the detector did (mode, version,
%                   thresholds, per-trial code, purge fractions, which rule
%                   flagged which channel, ...); preprocess_eeg stores it in
%                   outDat.EEGCleaningInfo.detector. Field list at the end of
%                   this function.
%
%PROCESSING ('fixed' / 'band'; thresholds are the legacy values)
%  Epoch into non-overlapping 2-s trials (final short trial edge-padded for
%  the statistics, written back at its true length).
%  PASS 1 (detect + repair): statistic = largest peak-to-peak in a sliding
%  10-ms window per channel per trial (w1 = round(10 ms / (1000/fs)) = 5 at
%  500 Hz; movmax/movmin over [0 w1] span 6 samples = 10 ms first-to-last,
%  window starts every round(w1/4) samples - the legacy arithmetic).
%   R0 gap:    a trial in which EVERY channel's broadband statistic is < 5 uV
%              is a recording gap (acquisition / headbox dropout) -> badTS,
%              neutral (NaN) for every channel rule, excluded from every
%              denominator.
%   R1 purge:  trials with > 75 % of channels > 100 uV -> badTS, neutral.
%   R2 block:  sliding block of 6 consecutive JUDGED trials (gap / purged
%              trials are skipped - the block reaches past them - so they
%              count as neither clean nor flat; with no gap / purge these
%              are the legacy 6-trial blocks); a channel is flagged in the
%              block's 6 trials when it exceeds 50 uV ("noisy"; skipChans
%              exempt) or falls below 5 uV ("flat"; broadband; nobody
%              exempt) in >= 3 of them.
%   R3 outBad: channels flagged by R2 in > 50 % of the judged trials.
%   R4 repair: trials with 1..(nChan/2 - 1) flagged channels -> interpolate
%              them (interpolate_perrinX); trials with >= nChan/2 flagged ->
%              those channels get a channel-specific flag in that trial.
%  PASS 2 (on the repaired data): statistic = largest peak-to-peak in a
%  sliding 80-ms window (w2 = 40 at 500 Hz: 41 samples first-to-last, starts
%  every 10 samples).
%   R5 channel: > 100 uV in > 50 % of the JUDGED trials (skipChans exempt)
%              -> channel-specific flag in every trial.
%   R6 rough:  if R5 would flag > 25 % of channels, first purge trials with
%              > 75 % of channels > 100 uV (-> badTS), then re-evaluate R5
%              over the remaining judged trials.
%   R7 purge:  trials with > 25 % of the remaining channels > 100 uV -> badTS.
%  VERDICT: badChans = channel-specific flags in >= 60 % of judged trials
%  UNION R3. Purges only ever go to badTS.
%   U unjudgeable: if fewer than max(6, ceil(10 % of the trials)) are judged
%              (the rest purged or gaps; 6 = one full R2 block), the channel
%              rules have (almost) no evidence to work on, so EVERY channel
%              is returned bad - the outcome 'legacy' gives such recordings -
%              with a warning and info.unjudgeable = true (otherwise an all-
%              purged recording would come back with no bad channel and
%              preprocess_eeg would run blink ICA / the Laplacian on it;
%              verifier, 2026-10-15). A recording shorter than 12 s (< 6
%              trials) is therefore always unjudgeable.
%
%BAND COPY ('band' only, 2026-10-15). The band copy is a zero-phase IIR
%filter of the CONTINUOUS recording, so a large burst in one trial rings
%into the first / last ~100 ms of its neighbours and would be counted there
%as evidence (synthetic case: 12 clean channels flagged). Each statistic is
%therefore taken per channel from a copy in which that trial's immediate
%neighbours are removed whenever they are SOURCES - over an amplitude
%threshold in the plain band copy (10-ms > 50 uV or 80-ms > 100 uV), or a
%gap trial (pass 1 and 2) or pass-1-purged trial (pass 2): every source
%trial of the other parity (odd / even trial number) is replaced by a
%straight line between the samples just outside it, the copy is filtered
%again, and the statistic of every trial of this parity that has a source
%neighbour is read from it (two extra filter runs per pass). Trials with no
%source neighbour keep the plain band-copy statistic. A trial's own samples
%are never altered, so its own content is judged in full.
%
%WHAT CHANGED vs 'legacy' (2026-10-14, tasks_261014 task 10; the EEG audit's
%"stage A", evidence R:\...\Dupi_processing\guessReview_261014\eegAudit\):
%  1. Trial purges (R1/R6/R7) were written into EVERY channel's bad record
%     and counted toward the >= 60 %-of-trials channel rule, so a recording
%     with >= 60 % purged trials lost ALL channels (251030_Dupi_NMH_DB_3 O15:
%     61 % purged -> all 30, incl. Fz/FC1/Cz/FC2 with robust SD 5-11 uV) and
%     below that the purged fraction was added to every channel. Purges now
%     go to badTS only; channel rules are judged over the non-purged trials.
%  2. Purged trials had their pass-1 statistic set to 0, which the R2 flat
%     test (< 5 uV) read as FLAT: every channel was flagged in each block
%     holding >= 3 purged trials (dilating the purge into R3 / the >= nChan/2
%     rule). They now take no part in R2 (2026-10-15b: skipped by the block,
%     which spans 6 judged trials; the 2026-10-14 version kept the fixed
%     6-trial window with purged trials neutral, which starved the rule).
%  3. R5 divided by ALL trials although purged trials were zeroed, so the
%     rough-purge branch could only lower each channel's fraction and turned
%     channel evidence into purges (DB_3 O15: 15 channels -> 0, then 214
%     trials purged). R5 now divides by the judged trials.
%  4. Recording gaps (every channel flat: 260608_OBE_NWU_RX_1 thresh, a 247-s
%     scalp-amplifier dropout) were counted as flat evidence against each
%     channel; they are now badTS only (R0).
%  5. (2026-10-15) rule U above; finite-input check; 'band' neighbour
%     bridging (BAND COPY above).
%  6. (2026-10-15b) R2 blocks of 6 judged trials (see 2.); rule U floor 6
%     judged trials (was 1). Gap and pass-1-purged trials are in no block,
%     so no channel is repaired inside them; trials purged later (R6 / R7)
%     keep their pass-1 repair, as in 'legacy'. ('legacy' repaired a pass-1-
%     purged trial whenever the blocks covering it flagged 1-15 channels.)
%  Effect relative to 'legacy': the fixes remove no-evidence flags, but four
%  structural consequences can go the other way. (a) R3 / R5 / the 60 % rule
%  now divide by the judged trials, so a channel bad in a large share of the
%  JUDGED trials can be flagged where 'legacy' (dividing by all trials, gaps
%  included) did not - e.g. > 100 uV in 45 % of all trials with a 23 % gap =
%  58 % of the judged ones. (b) R0 marks a single isolated all-flat trial as
%  badTS, where 'legacy' needed >= 3 flat trials in a 6-trial block. (c) An
%  R2 block spans the purges between its 6 judged trials, so a channel over
%  threshold in 3 of 6 judged trials that purges keep apart is flagged there
%  even if no 6-trial window of 'legacy' held 3 of them. (d) A judged trial
%  next to purges can now collect >= nChan/2 flags (R4: not repaired); if its
%  own data then have > 25 % of the channels over 100 uV, R7 purges it, where
%  'legacy' had rebuilt 9-15 of its channels by interpolation and kept it.
%  19-session validation (2026-10-15b): no channel added vs 'legacy' in any
%  session ((a) and (c) not seen); badTS above 'legacy' in 2 sessions via (d)
%  (250904_OBE_NWU_TI_1 movie 14.26 -> 14.84 %, 260702_OBE_NWU_SP_2 thresh
%  44.11 -> 44.36 %: trials with 9-13 channels over 100 uV unrepaired). Trials
%  that 'legacy' marked badTS only because the accumulated per-channel records
%  happened to cover all channels there (mostly neighbours of purges, via 2.)
%  are no longer badTS (validation: 251006_OBE_NWU_RY_1 O15 71 % -> 43 %,
%  251030_Dupi_NMH_DB_3 O15 66 % -> 60 %).

%written by Adam Dede (adam.osman.dede@gmail.com)
%Fall 2025; 'fixed' / 'band' modes 2026-10-14; rule U, finite check, band
%neighbour bridging 2026-10-15; R2 blocks of judged trials, U floor 6
%2026-10-15b

if nargin < 5 || isempty(opts), opts = struct(); end
if ~isfield(opts, 'mode') || isempty(opts.mode), opts.mode = 'fixed'; end
mode = lower(char(opts.mode));

switch mode
    case 'legacy'
        if exist('removeNoiseChansVolt_legacy', 'file') ~= 2
            error('removeNoiseChansVolt:legacyMissing', ...
                ['mode ''legacy'' needs shared/removeNoiseChansVolt_legacy.m, which is not on the path - ' ...
                 'deploy it together with removeNoiseChansVolt.m, preprocess_eeg.m, blinkRemoveWrapper.m and ' ...
                 'tasks/breathingSeparate/concatSections.m (tasks_261014 task 10)']);
        end
        [badTS, badChans, newEEG, interpChan] = ...
            removeNoiseChansVolt_legacy(EEG, fs, skipChans, chanLocs);
        info = struct('mode', 'legacy', 'version', 'pre-2026-10-14', ...
            'nTrial', ceil(size(EEG, 2) / (2*fs)), 'fracBadTS', mean(badTS), ...
            'fracInterp', mean(interpChan > 0));
        return
    case {'fixed', 'band'}
        % below
    otherwise
        error('removeNoiseChansVolt:mode', ...
            'unknown opts.mode ''%s'' (expected ''fixed'', ''band'' or ''legacy'')', mode);
end
if nargout < 5
    % the only pipeline caller (preprocess_eeg) stores info in
    % outDat.EEGCleaningInfo; a 4-output call means a stale preprocess_eeg.m
    % was left next to this file, and its finals would carry no record of the
    % cleaning mode (= look like legacy finals)
    warning('removeNoiseChansVolt:noInfo', ...
        ['called without the 5th output (info): the cleaning record is not kept - ' ...
         'if this is preprocess_eeg, deploy the 2026-10-14 preprocess_eeg.m with this file']);
end
nonFin = ~isfinite(EEG);
if any(nonFin(:))
    error('removeNoiseChansVolt:nonFinite', ...
        ['%d non-finite sample(s) in EEG row(s) %s: mode ''%s'' needs finite data ' ...
         '(NaN gaps are filled upstream by the makeOutDats)'], ...
        nnz(nonFin), mat2str(find(any(nonFin, 2))'), mode);
end
clear nonFin
useBand = strcmp(mode, 'band');
statBand = [];
if useBand
    statBand = [1 40];
    if isfield(opts, 'statBand') && ~isempty(opts.statBand), statBand = opts.statBand; end
end

% thresholds = the legacy values
T = struct('p1NoisyUV', 50, 'flatUV', 5, 'p2UV', 100, ...
    'purgeFracRough', 3/4, 'purgeFracModerate', 1/4, 'chanFrac', 0.6, ...
    'outBadFrac', 0.5, 'p2ChanFrac', 0.5, 'blockSize', 5, 'trialSec', 2, ...
    'win1ms', 10, 'win2ms', 80, 'minJudgedFrac', 0.1);

[c, L] = size(EEG);
isSkip = false(c, 1); isSkip(skipChans) = true;

snipL  = fs * T.trialSec;
starts = 1:snipL:L;
nTrial = numel(starts);
epochLen = min(snipL, L - starts(:) + 1);   % true (unpadded) length of each trial

if useBand
    bp = designfilt('bandpassiir', 'FilterOrder', 4, ...
        'HalfPowerFrequency1', statBand(1), 'HalfPowerFrequency2', statBand(2), ...
        'SampleRate', fs);
end

%% ---------------- PASS 1: 10-ms statistic, detect + repair ----------------
w1 = round(T.win1ms / (1000 / fs));
w2 = round(T.win2ms / (1000 / fs));
tmpEEG   = epochData(EEG, starts, snipL);
flatStat = slidingP2P(tmpEEG, w1);              % broadband: flat / dead and gap tests

% R0 recording gap: every channel flat (broadband) -> badTS, neutral everywhere
gap = all(flatStat < T.flatUV, 1);

bandRedo = [0 0];   % 'band': fraction of channel-trials re-judged without source neighbours
if useBand
    [p1, ~, bandRedo(1)] = bandTrialStats(EEG, bp, starts, snipL, w1, w2, T, gap);
else
    p1 = flatStat;
end
p1(:, gap) = NaN; flatStat(:, gap) = NaN;

% R1 pass-1 trial purge (> 75 % of channels over 100 uV) -> badTS, neutral
% (NaN > x and NaN < x are both false, so neutral trials never count)
purge1 = sum(p1 > T.p2UV, 1) > c * T.purgeFracRough;
p1(:, purge1) = NaN; flatStat(:, purge1) = NaN;

% R2 blockwise noisy / flat channel flags over a sliding block of 6 JUDGED
% trials: gap / purged trials are skipped (the block reaches past them to
% the next judged trial), so every block holds 6 judged trials and the
% legacy >= 3-of-6 strength is kept however the purges are scattered (with
% NaN-neutral trials inside a fixed 6-trial window, a block holding <= 2
% judged trials could flag nothing - verifier 2026-10-15: a dead channel
% passed under 1-in-3 judged trials). No gap / purge = the legacy blocks.
bs = T.blockSize;
judged1 = ~gap & ~purge1;
jIdx = find(judged1);
flagMap = false(c, nTrial);
for block = 1:numel(jIdx) - bs
    cols  = jIdx(block:block + bs);
    noisy = sum(p1(:, cols) > T.p1NoisyUV, 2) > bs/2 & ~isSkip;
    flat  = sum(flatStat(:, cols) < T.flatUV, 2) > bs/2;
    flagMap(noisy | flat, cols) = true;
end

% R3 outBad over the judged trials
outBad  = find(sum(flagMap(:, judged1), 2) > max(1, sum(judged1)) * T.outBadFrac);

% R4 per-trial repair / channel-specific flags
chanRecord  = false(c, nTrial);
interpCount = zeros(nTrial, 1);
for tt = 1:nTrial
    nf = sum(flagMap(:, tt));
    if nf > 0
        if nf < c/2
            tmpEEG(:, :, tt) = interpolate_perrinX(tmpEEG(:, :, tt), ...
                chanLocs.X, chanLocs.Y, chanLocs.Z, find(flagMap(:, tt)));
            interpCount(tt) = nf;
        else
            chanRecord(flagMap(:, tt), tt) = true;
        end
    end
end

newEEG     = zeros(size(EEG));
interpChan = zeros(L, 1);
for tt = 1:nTrial
    cols = starts(tt):starts(tt) + epochLen(tt) - 1;
    newEEG(:, cols)  = tmpEEG(:, 1:epochLen(tt), tt);   % write only the real samples
    interpChan(cols) = interpCount(tt);
end
clear tmpEEG

%% ---------------- PASS 2: 80-ms statistic on the repaired data ----------------
if useBand
    [~, p2, bandRedo(2)] = bandTrialStats(newEEG, bp, starts, snipL, w1, w2, T, gap | purge1);
else
    p2 = slidingP2P(epochData(newEEG, starts, snipL), w2);
end
nChanOverP2 = sum(p2 > T.p2UV, 1);          % per trial, before any purge (record)
judged2 = judged1;
p2(:, ~judged2) = 0;                         % gap / pass-1-purged trials never count again

noiseChans = find(overFrac(p2, judged2, T.p2UV) > T.p2ChanFrac & ~isSkip);
p2ChanInitial = noiseChans;
purgeRough = false(1, nTrial);
p2branch = 'direct';
if numel(noiseChans) > c * T.purgeFracModerate
    % R6: too many channels look bad - purge the worst trials first, then
    % re-judge the channels over the trials that remain
    p2branch = 'roughPurgeFirst';
    purgeRough = sum(p2 > T.p2UV, 1) > c * T.purgeFracRough;
    p2(:, purgeRough) = 0;
    judged2 = judged2 & ~purgeRough;
    noiseChans = find(overFrac(p2, judged2, T.p2UV) > T.p2ChanFrac & ~isSkip);
end
chanRecord(noiseChans, :) = true;
p2(noiseChans, :) = 0;

% R7 moderate trial purge (> 25 % of channels over 100 uV) -> badTS
purgeMod = sum(p2 > T.p2UV, 1) > c * T.purgeFracModerate;

%% ---------------- verdict ----------------
purged = gap | purge1 | purgeRough | purgeMod;
nJudged = sum(~purged);
chanFracBad = sum(chanRecord(:, ~purged), 2) / max(1, nJudged);
chanRuleBad = find(chanFracBad >= T.chanFrac);
% U: too few judged trials -> no channel can be judged -> every channel bad.
% Floor = one full R2 block (6 judged trials): below it no channel verdict
% rests on more than a few 2-s trials (verifier 2026-10-15: with a floor of
% 1, a single judged trial decided every channel).
minJudged   = max(T.blockSize + 1, ceil(T.minJudgedFrac * nTrial));
unjudgeable = nJudged < minJudged;
if unjudgeable
    warning('removeNoiseChansVolt:unjudgeable', ...
        ['%d of %d 2-s trials were purged or gaps (%d judged < %d): no channel can be ' ...
         'judged - EVERY channel is returned bad'], nTrial - nJudged, nTrial, nJudged, minJudged);
end

badTrials = all(chanRecord, 1) | purged;
badTrials(end) = false;
badTS = zeros(L, 1);
for tt = 1:nTrial
    if badTrials(tt)
        badTS(starts(tt):min(L, starts(tt) + snipL - 1)) = 1;
    end
end

badChans = unique([chanRuleBad(:); outBad(:)]);
if unjudgeable
    badChans = (1:c)';
end

%% ---------------- record ----------------
% trialCode per 2-s trial: 0 judged, 1 recording gap (R0), 2 pass-1 purge
% (R1), 3 rough purge (R6), 4 moderate purge (R7)
trialCode = zeros(1, nTrial, 'uint8');
trialCode(purgeMod) = 4; trialCode(purgeRough) = 3; trialCode(purge1) = 2; trialCode(gap) = 1;
info = struct();
info.mode        = mode;
info.version     = '2026-10-15b';
info.statBand    = statBand;
info.unjudgeable = unjudgeable;         % rule U fired: every channel returned bad
info.minJudged   = minJudged;
info.bandRedo    = bandRedo;            % 'band': [pass 1, pass 2] fraction of channel-trials
                                        % re-judged without their source neighbours
info.thresholds  = T;
info.nTrial      = nTrial;
info.trialCode   = trialCode;
info.nChanOverP2 = uint8(nChanOverP2);
info.fracGap          = mean(gap);
info.fracPurgeP1      = mean(purge1);
info.fracPurgeRough   = mean(purgeRough);
info.fracPurgeModerate = mean(purgeMod);
info.fracPurged  = mean(purged);
info.nJudged     = nJudged;
info.nBlocksP1   = max(0, numel(jIdx) - bs);   % R2 blocks (each of 6 judged trials)
info.fracBadTS   = mean(badTS);
info.fracInterp  = mean(interpChan > 0);
info.p2branch    = p2branch;
info.outBad      = outBad(:)';          % R3 channel indices
info.chanRuleBad = chanRuleBad(:)';     % >= 60 % channel-specific flags
info.p2ChanInitial = p2ChanInitial(:)'; % R5 before the rough purge
info.p2ChanFinal = noiseChans(:)';      % R5 applied
info.fracFlaggedP1  = sum(flagMap(:, judged1), 2)' / max(1, sum(judged1));   % R2, per channel
info.fracChanRecord = chanFracBad(:)';  % channel-specific flags, per channel
end


function tmp = epochData(X, starts, snipL)
% channels x snipL x nTrial; the final short trial is edge-padded (last real
% sample replicated) so the sliding peak-to-peak reflects only real data
[c, L] = size(X);
nTrial = numel(starts);
tmp = zeros(c, snipL, nTrial);
for ii = 1:nTrial
    s0 = starts(ii); s1 = min(L, s0 + snipL - 1); n = s1 - s0 + 1;
    tmp(:, 1:n, ii) = X(:, s0:s1);
    if n < snipL
        tmp(:, n+1:snipL, ii) = repmat(X(:, s1), 1, snipL - n);
    end
end
end


function md = slidingP2P(tmp, window)
% largest peak-to-peak over i:(i+window) per channel per trial, sampled every
% round(window/4) samples (the legacy arithmetic)
[nChan, nTime, nTrial] = size(tmp);
step = round(window / 4);
startIdx = 1:step:(nTime - window);
x = permute(tmp, [1 3 2]);
x = reshape(x, [], nTime);
winRange = movmax(x, [0 window], 2) - movmin(x, [0 window], 2);
md = max(winRange(:, startIdx), [], 2);
md = reshape(md, nChan, nTrial);
end


function f = overFrac(md, judged, thr)
% per-channel fraction of the judged trials whose statistic exceeds thr
f = sum(md(:, judged) > thr, 2) / max(1, sum(judged));
end


function [s1, s2, fracRedo] = bandTrialStats(X, bp, starts, snipL, w1, w2, T, forceSrc)
% 'band' statistics (10-ms -> s1, 80-ms -> s2; channels x trials) of the
% band-passed copy of X, each 2-s trial judged on its own content (header,
% BAND COPY): channel-trials over a threshold in the plain band copy, plus
% the forceSrc trials (1 x nTrial: gaps / purged), are SOURCES; a channel-
% trial with a source neighbour is re-read from a copy in which the
% other-parity sources of that channel are bridged by a straight line.
[c, ~] = size(X);
nTrial = numel(starts);
E  = epochData(filtfilt(bp, X')', starts, snipL);
s1 = slidingP2P(E, w1);
s2 = slidingP2P(E, w2);
clear E
src = s1 > T.p1NoisyUV | s2 > T.p2UV | repmat(logical(forceSrc(:)'), c, 1);
nbSrc = [false(c, 1), src(:, 1:end-1)] | [src(:, 2:end), false(c, 1)];
par = repmat(mod(1:nTrial, 2), c, 1);
redoAll = false(c, nTrial);
for p = 0:1
    redo = nbSrc & par == p;             % channel-trials of this parity to re-judge
    if ~any(redo(:)), continue; end
    Xb = bridgeTrials(X, starts, snipL, src & par ~= p);   % never two adjacent
    Eb = epochData(filtfilt(bp, Xb')', starts, snipL);
    clear Xb
    t1 = slidingP2P(Eb, w1);
    t2 = slidingP2P(Eb, w2);
    clear Eb
    s1(redo) = t1(redo);
    s2(redo) = t2(redo);
    redoAll = redoAll | redo;
end
fracRedo = mean(redoAll(:));
end


function X = bridgeTrials(X, starts, snipL, br)
% replace channel-trial (ch, t) where br(ch, t) by a straight line between
% the samples just outside the trial (br never holds two adjacent trials of
% a channel, so both anchors are real, unbridged samples); an edge trial is
% held at its single inside neighbour's value
L = size(X, 2);
for t = find(any(br, 1))
    a0 = starts(t); a1 = min(L, a0 + snipL - 1); n = a1 - a0 + 1;
    ch = find(br(:, t));
    if a0 > 1, left = X(ch, a0 - 1); else, left = []; end
    if a1 < L, right = X(ch, a1 + 1); else, right = []; end
    if isempty(left), left = right; end
    if isempty(right), right = left; end
    if isempty(left), continue; end      % single-trial recording: nothing to bridge to
    X(ch, a0:a1) = left + (right - left) .* ((1:n) / (n + 1));
end
end

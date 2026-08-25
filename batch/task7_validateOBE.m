% task7_validateOBE — Task 7 step 6, first half: validate the movie pipeline
% on one OBEControl session (250225_OBE_NWU_AS_4) up to - NOT past - the guess
% gate, entirely IN MEMORY (its old-format final shares the intermediate
% filename and must not be touched, so nothing is written to preProc).
% Prints clip count / valence sequence for plausibility against the old
% pipeline's expectations and the in-clip breath yield; saves QC figures to
% E:\reprocBackup_260824\task7_probe\.

ID = '250225_OBE_NWU_AS_4';
QC = 'E:\reprocBackup_260824\task7_probe';
if ~isfolder(QC), mkdir(QC); end

L = labPaths();
addpath(genpath(L.eeglab));

P = applyParams('emotionalMovieTask', ID);
P.allowGuessRun = true;      % figure-saving QC paths, no prompts
P.figDir = QC;

% ---- in-memory makeOutDat body ----
rawFile = fullfile(L.rootOBE, ID, 'raw', 'raw_EmotionalMovieTask', 'raw_EmotionalMovieTask.mat');
dat = load(rawFile); dat = dat.curDat;
outDat = struct();
outDat.labels  = dat.outLabs;
outDat.CSClist = dat.ncslabels;
outDat.fs      = dat.rawData.fsample;
outDat.sessID  = ID;
outDat.data    = dat.rawData.trial{1};
clear dat
nanCols = isnan(outDat.data(end, :));
if any(nanCols), outDat.data(:, nanCols) = []; end
if any(isnan(outDat.data(:)))
    outDat.data = fillmissing(outDat.data, 'linear', 2, 'EndValues', 'nearest');
end
outDat.type = 'OBE';
outDat.figs = QC;

outDat.TTL = detect_ttls_emotionalMovieTask(outDat, P, QC);
T = outDat.TTL;
fprintf('\n%s clip table: %d clips | %d neutral / %d happy / %d sad\n', ID, height(T), ...
    sum(T.valence == "neutral"), sum(T.valence == "happy"), sum(T.valence == "sad"));
fprintf('valence sequence: %s\n', strjoin(cellstr(T.valence'), ' '));
durs = (T.clipEnd - T.clipOnset) / 500;
fprintf('clip durations (s): median %.1f  range [%.1f %.1f] (final clip unbounded by design)\n', ...
    median(durs, 'omitnan'), min(durs), max(durs, [], 'omitnan'));

% ---- shared pipeline up to the gate ----
[outDat, P] = paramCheck(outDat, P);
outDat = downsample_data(outDat, P.fs_target);
if P.hasEEG, outDat = preprocess_eeg(outDat, readtable(L.eegLocCsv), P); end
if P.hasMacros, outDat = preprocess_macros(outDat, P); end

isRsp  = cellfun(@(x) contains(x, 'rsp'), outDat.labels);
rspDat = outDat.data(isRsp, :);
rspDat = rspDat(P.rspIDX, :) .* P.rspFlip;
[outDat.bmObj, outDat.bmFeatures] = segmentBreaths_breathMetrics(rspDat, outDat.fs);
outDat.moreThan1 = 1;
outDat.rspIDX = P.rspIDX; outDat.rspFlip = P.rspFlip;

outDat = build_behavior_table_emotionalMovieTask(outDat);
fprintf('behDat: %d in-clip breaths x %d cols; valence counts:\n', ...
    height(outDat.behDat), width(outDat.behDat));
disp(groupcounts(outDat.behDat, 'clipValence'));

hasECG = sum(cellfun(@(x) contains(x, 'ECG'), outDat.labels)) > 0;
fprintf('ECG channels present: %d\n', hasECG);
if hasECG
    P2 = paramCheckECG(outDat, P);  %#ok<NASGU> % saves the QC figure
end

fprintf(['\ntask7_validateOBE: DONE - validated up to the guess gate; ' ...
         'NOTHING written to preProc (old final untouched).\n']);

% task4_runPD1 — Tasks_260824.md Task 4: the single D6 attempt at the stale
% O15 session 260316_Dupi_NMH_PD_1 (July failure: photodiode TTL parse
% returned the wrong trial count; a valid pre-July final is on disk).
%
% Replicates the O15PreProc_main body for this ONE session (the main script is
% currently in July's REDO-ALL configuration and would reprocess dozens of
% sessions). The stale final is backed up to E:\reprocBackup_260824\O15\ first;
% the pipeline saves only on success, so a failure leaves the original intact.

ID = '260316_Dupi_NMH_PD_1';
BK = 'E:\reprocBackup_260824\O15';
if ~isfolder(BK), mkdir(BK); end

L = labPaths();
EEGLOC = readtable(L.eegLocCsv);
figPath = L.figPath;

cfg = applyParams('O15', 'main');
ri = find(strcmpi(cfg.sessionIDs, ID), 1);
assert(~isempty(ri), 'PD_1 not in O15 session list');

% ---- backup (tmp+rename; do NOT delete - save-on-success semantics) ----
src = fullfile(cfg.root{ri}, ID, 'preProc', [ID '_O15preproc.mat']);
dst = fullfile(BK, [ID '_O15preproc.mat']);
if exist(src, 'file') && ~exist(dst, 'file')
    copyfile(src, [dst '.tmp']);
    movefile([dst '.tmp'], dst, 'f');
    fprintf('backed up stale final (%d MB)\n', round(dir(dst).bytes / 1e6));
end

% ---- O15 main body for this session ----
S = struct();
S.id = ID; S.root = cfg.root{ri}; S.figPath = figPath;
if ~isfolder(fullfile(S.figPath, S.id)), mkdir(fullfile(S.figPath, S.id)); end
P = applyParams('O15', S.id);
assert(strcmpi(P.paramSource, 'curated'), 'PD_1 expected curated');

[raw, TTL] = assembleRaw_O15(S, P);
outDat     = assembleOutDat(raw, S, P);
outDat     = assembleOutDat_O15extras(outDat, S, raw);
disp(['........................Loaded ', ID])

outDat.rspIDX = P.rspIDX;
outDat.rspFlip = P.rspFlip;
outDat.TTL = TTL;

outDat = downsample_data(outDat, P.fs_target);
if P.hasEEG, outDat = preprocess_eeg(outDat, EEGLOC, P); end
outDat = preprocess_macros(outDat, P);
disp(['........................spike and blink ', ID])

outDat.moreThan1 = 1;
R = preprocess_respiration_wholetrace(outDat);
sniffs = detect_sniffs_from_TTLs(R, P, outDat);

P.paramSource = 'curated';
writeParams(P, S.id);

outDat.behDat = build_behavior_table_O15(sniffs, raw.beh);
outDat = refine_onsets_with_phase(outDat, R, P);
plot_sniff_epochs(outDat, R);
disp(['........................breath behave ', ID])

if ~isfolder(fullfile(outDat.OGdataDir, 'preProc'))
    mkdir(fullfile(outDat.OGdataDir, 'preProc'))
end
save(fullfile(outDat.OGdataDir, 'preProc', [outDat.sessID '_O15preproc.mat']), ...
     'outDat', '-v7.3')
writePreProcX(P, S.id)
fprintf('task4_runPD1: SUCCESS - final saved (%d behDat rows)\n', height(outDat.behDat));

% task6_validateNoCue — Task 6 Part A step 4: validate the no-cue path on one
% no-cue session (260702_OBE_NWU_SP_2) up to — NOT past — the guess gate.
% Runs the exact main-pipeline stages on the SP_2 intermediate with
% allowGuessRun QC figures, checks the no-cue bookkeeping, and does NOT save
% any final (moreThan1 is never set, nothing is written to preProc).

ID = '260702_OBE_NWU_SP_2';
QC = 'E:\reprocBackup_260824\task6_probe\SP2_QC';
if ~isfolder(QC), mkdir(QC); end

L = labPaths();
addpath(genpath(L.eeglab));      % runica for the blink ICA
EEGLOC = readtable(L.eegLocCsv);
S = struct('id', ID, 'root', L.rootOBE, 'fig', QC);

P = applyParams('cueTask', ID);
assert(strcmpi(P.paramSource, 'guess'), 'expected SP_2 to be a guess row');
P.allowGuessRun = true;    % QC figures instead of interactive prompts
P.figDir = QC;

% intermediate must exist (cueTask_makeOutDat run beforehand)
outDat = load(fullfile(S.root, ID, 'preProc', [ID '_cueTaskPreProc.mat']));
fn = fieldnames(outDat); outDat = outDat.(fn{1});
assert(~isfield(outDat, 'moreThan1'), 'SP_2 already has a final?!');

% --- behavioral bookkeeping checks on the intermediate ---
bd = outDat.behDat;
fprintf('intermediate behDat: %d x %d\n', height(bd), width(bd));
fprintf('cue values: %s\n', mat2str(unique(bd.cue)'));
fprintf('type counts:\n'); disp(groupcounts(bd, 'type'));
assert(sum(bd.cue == 0) == 20, 'expected 20 no-cue trials, got %d', sum(bd.cue == 0));
assert(all(strcmp(bd.type(bd.cue == 0), "noCue")), 'no-cue trials not typed noCue');
assert(~any(strcmp(bd.type(bd.cue ~= 0), "noCue")), 'cued trial mistyped noCue');
assert(max(bd.odor) <= 10 && min(bd.odor) >= 1, 'odor recode not applied');
fprintf('no-cue bookkeeping checks PASSED\n');

% --- shared pipeline up to the onset gate ---
[outDat, P] = paramCheck(outDat, P);              % saves QC figures (batch path)
outDat.rspIDX = P.rspIDX; outDat.rspFlip = P.rspFlip;
raw    = assembleRaw_cueTask(S);
outDat = assembleOutDat(raw, S, P);
outDat = downsample_data(outDat, P.fs_target);
if P.hasEEG, outDat = preprocess_eeg(outDat, EEGLOC, P); end
outDat = preprocess_macros(outDat, P);
R = preprocess_respiration_wholetrace(outDat);
sniffs = detect_sniffs_from_TTLs(R, P, outDat);
outDat.behDat = build_behavior_table_cueTask(sniffs, raw.beh);
outDat = refine_onsets_with_phase(outDat, R, P);

bd = outDat.behDat;
fprintf('\npost-pipeline behDat: %d x %d\n', height(bd), width(bd));
fprintf('columns: %s\n', strjoin(bd.Properties.VariableNames, ','));
fprintf('type counts:\n'); disp(groupcounts(bd, 'type'));
fprintf('finalOnset finite: %d/%d | manOnset all NaN: %d\n', ...
    sum(isfinite(bd.finalOnset)), height(bd), all(isnan(bd.manOnset)));
assert(sum(bd.cue == 0) == 20 && all(strcmp(bd.type(bd.cue == 0), "noCue")), ...
    'noCue coding lost through the sniff/behavior build');

% QC figure of onsets (the deliberate onset-gate stop happens here: no save)
plot_sniff_epochs(outDat, R);
figs = findobj('Type', 'figure');
for k = 1:numel(figs)
    try %#ok<TRYNC>
        saveas(figs(k), fullfile(QC, sprintf('%s_onsetQC_%d.png', ID, k)));
    end
end
close all
fprintf(['\ntask6_validateNoCue: DONE - validated up to the guess gate; ' ...
         'NO final saved (guess row awaits human verification).\n']);

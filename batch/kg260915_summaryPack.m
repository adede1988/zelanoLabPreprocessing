% kg260915_summaryPack - export a compact analysis pack from a pacedBreathing
% final so the respHRV summary can be built off-server (the final itself is
% ~1.5 GB of EEG). READ-ONLY with respect to the final.
%
%   env ZLP_PACK_ID  session id (default 260915_EEG_NWU_KG)
%   env ZLP_PACK_OUT output folder (default E:\kg260915\pack)
%
% Pack contents (<id>_pacedBreathing_pack.mat, v7.3):
%   fsPack      50 Hz
%   t           time axis (s) at fsPack
%   rsp         chosen respiration trace (rspIDX/rspFlip applied), decimated
%   RRint       interpolated RR-interval series (s), decimated
%   ECGz        band-passed z-scored ECG lead used for beats, decimated to 100 Hz (ecgT, fsECG)
%   heartBeats  beat sample indices at the final's fs (500 Hz)
%   bmObj, blocks, blockInference, behDat (table), sessID, fs (500)
%   ecgSkipped, badChans, blinkRemoval, labels
% plus <id>_pacedBreathing_behDat.csv and <id>_pacedBreathing_blocks.csv.

id  = getenv('ZLP_PACK_ID');  if isempty(id),  id  = '260915_EEG_NWU_KG'; end
out = getenv('ZLP_PACK_OUT'); if isempty(out), out = 'E:\kg260915\pack'; end
if ~isfolder(out), mkdir(out); end

cfg = applyParams('pacedBreathing', 'main');
si = find(strcmp(cfg.sessionIDs, id), 1);
assert(~isempty(si), 'session %s not in the pacedBreathing list', id);
fpath = fullfile(cfg.root{si}, id, 'preProc', [id '_pacedBreathingpreproc.mat']);
assert(exist(fpath, 'file') == 2, 'final missing: %s', fpath);
s = load(fpath); fn = fieldnames(s); od = s.(fn{1}); clear s
assert(isfield(od, 'moreThan1') && isfield(od, 'bmObj') && isfield(od, 'blocks'), 'not a complete pacedBreathing final');

fs = od.fs;
isRsp = cellfun(@(x) contains(x, 'rsp'), od.labels);
rsp = od.data(isRsp, :); rsp = rsp(od.rspIDX, :) .* od.rspFlip;
hasRR = any(cellfun(@(x) contains(x, 'RRint'), od.labels));
if hasRR
    RR = od.data(cellfun(@(x) contains(x, 'RRint'), od.labels), :);
else
    RR = nan(1, size(od.data, 2));
end

fsPack = 50; dec = round(fs / fsPack);
pack = struct();
pack.sessID = id; pack.fs = fs; pack.fsPack = fsPack;
pack.t     = (1:dec:size(od.data, 2)) / fs;
pack.rsp   = rsp(1:dec:end);
pack.RRint = RR(1:dec:end);
if hasRR
    [ECGz, ~] = buildECGz(od);
    fsECG = 100; decE = round(fs / fsECG);
    pack.ECGz = ECGz(:, 1:decE:end); pack.fsECG = fsECG; pack.ecgT = (1:decE:size(ECGz, 2)) / fs;
    clear ECGz
end
if isfield(od, 'heartBeats'), pack.heartBeats = od.heartBeats; end
pack.bmObj = od.bmObj;
pack.blocks = od.blocks;
pack.blockInference = od.blockInference;
pack.behDat = od.behDat;
pack.labels = od.labels;
for f = {'ecgSkipped', 'badChans', 'blinkRemoval', 'rspIDX', 'rspFlip', 'task', 'type', 'CSClist', 'loadFile'}
    if isfield(od, f{1}), pack.(f{1}) = od.(f{1}); end
end
if isfield(od, 'bmFeatures') && isfield(od.bmFeatures, 'conditioning')
    pack.bmConditioning = od.bmFeatures.conditioning;
end
% EEG QC summary only (no EEG data in the pack)
pack.nSamples = size(od.data, 2);
pack.durMin = size(od.data, 2) / fs / 60;

save(fullfile(out, [id '_pacedBreathing_pack.mat']), '-struct', 'pack', '-v7.3');
writetable(od.behDat, fullfile(out, [id '_pacedBreathing_behDat.csv']));
writetable(od.blocks, fullfile(out, [id '_pacedBreathing_blocks.csv']));
fprintf('kg260915_summaryPack: %s -> %s (%d breaths, %d blocks, %.1f min, hasRR=%d)\n', ...
    id, out, size(od.bmObj, 1), height(od.blocks), pack.durMin, hasRR);

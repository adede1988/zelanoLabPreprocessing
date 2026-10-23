function testBlocksOfMergedBreaths_pacedBreathing()
%TESTBLOCKSOFMERGEDBREATHS_PACEDBREATHING  Self-test of the pacedBreathing block carry-over across the breath merge
%   (tasks/pacedBreathing/blocksOfMergedBreaths_pacedBreathing) and of the main's order of stages: the blocks come
%   from the ENGINE's breaths, the merge shrinks only the per-breath table (decision 2026-10-23).
%   Synthetic: a nasal-pressure trace of three paced stretches (15, 9 and 6 /min) with occasional double inhales,
%   segmented by segmentBreaths_zlp, blocks inferred on the engine bmObj, then applyBreathMerge.
%   Run: testBlocksOfMergedBreaths_pacedBreathing   (errors if a check fails; needs the repo on the path)
nfail = 0;

% ---------- 1) the mapping on a hand-made merge record ----------
n0 = 10;
blkEngine = [1 1 1 1 2 2 2 2 3 3]';
oR = {1; 2; [3 4]; 5; [6 7]; 8; [9 10]};          % engine rows 3+4 (block 1), 6+7 (block 2), 9+10 (block 3) merged
bm = struct('nBefore', n0, 'nAfter', numel(oR), 'origRows', {oR});
[blk, info] = blocksOfMergedBreaths_pacedBreathing(bm, blkEngine, 3);
nfail = nfail + ~chk('merged breath takes the block of its first engine breath', isequal(blk, [1 1 1 2 2 2 3]'));
nfail = nfail + ~chk('per-block counts, engine and merged', isequal(info.nBreathsEngine, [4 4 2]) && isequal(info.nBreathsMerged, [3 3 1]) && info.nEmptyBlocks == 0);
% a merged breath that spans a block boundary: first engine breath decides
oR2 = {1; 2; 3; [4 5]; 6; 7; 8; 9; 10};          % rows 4 (block 1) + 5 (block 2)
bm2 = struct('nBefore', n0, 'nAfter', numel(oR2), 'origRows', {oR2});
[blk2, info2] = blocksOfMergedBreaths_pacedBreathing(bm2, blkEngine, 3);
nfail = nfail + ~chk('a breath straddling a boundary belongs to the block it starts in', blk2(4) == 1 && info2.nStraddling == 1 && numel(blk2) == 9);
nfail = nfail + ~chk('mismatching record errors (engine count)', strcmp(tryId(@() blocksOfMergedBreaths_pacedBreathing(bm, blkEngine(1:9), 3)), 'blocksOfMergedBreaths_pacedBreathing:nBefore'));
bm3 = bm; bm3.nAfter = 6;
nfail = nfail + ~chk('mismatching record errors (merged count)', strcmp(tryId(@() blocksOfMergedBreaths_pacedBreathing(bm3, blkEngine, 3)), 'blocksOfMergedBreaths_pacedBreathing:nAfter'));

% ---------- 2) the stages in the main's order on a synthetic trace ----------
fs = 500; rng(7);
segs = [15 150; 9 150; 6 180];                      % [breaths/min, seconds]
x = [];
for k = 1:size(segs, 1)
    per = 60 / segs(k, 1); t = (0:1 / fs:segs(k, 2))';
    ph = mod(t / per, 1);
    x = [x; sin(2 * pi * ph) + 0.15 * sin(4 * pi * ph) + 0.03 * randn(size(t))]; %#ok<AGROW>
end
x = x(:)' * 100;
% double inhales: a second small inhale peak right after the first on every 7th breath of the 9 /min stretch
t0 = segs(1, 2); per = 60 / segs(2, 1);
for b = 3:7:floor(segs(2, 2) / per) - 1
    i0 = round((t0 + (b + 0.30) * per) * fs);
    w = round(0.6 * fs); seg = 40 * (0.5 - 0.5 * cos(2 * pi * (0:w - 1) / (w - 1)));
    x(i0:i0 + w - 1) = x(i0:i0 + w - 1) + seg;
end
outDat = struct('sessID', 'SYNTH', 'fs', fs, 'data', x, 'labels', {{'rsp1'}});
[outDat.bmObj, outDat.bmFeatures] = segmentBreaths_zlp(x, fs);
bmEngine = outDat.bmObj;
nEng = size(bmEngine, 1);
opts = struct();
[blocks, TTL, binf] = inferBlocks_pacedBreathing(bmEngine, fs, numel(x), opts);
outDat.blocks = blocks; outDat.TTL = TTL; outDat.blockInference = binf;
outDat = applyBreathMerge(outDat, x, struct());
nMerged = size(outDat.bmObj, 1);
[cond, mi] = blocksOfMergedBreaths_pacedBreathing(outDat.breathMerge, binf.blkOfBreath, height(blocks));
outDat.bmObj(:, 12) = cond;
fprintf('   synthetic: %d engine breaths, %d after the merge, %d blocks\n', nEng, nMerged, height(blocks));
nfail = nfail + ~chk('the merge removed some breaths (the test is meaningful)', nMerged < nEng);
nfail = nfail + ~chk('blocks / TTL are the inference on the engine breaths, whatever the merge did', ...
    isequaln(blocks, inferBlocksQuiet(bmEngine, fs, numel(x), opts)) && isequal(TTL, blocks.startSample'));
nfail = nfail + ~chk('breath-to-block accounting adds up', sum(mi.nBreathsEngine) == nEng && sum(mi.nBreathsMerged) == nMerged && mi.nEmptyBlocks == 0);
% every merged breath's onset lies inside its block's sample span
on = round(outDat.bmObj(:, 2) * fs);
inSpan = on >= blocks.startSample(cond) & on <= blocks.endSample(cond);
nfail = nfail + ~chk('every merged breath onset lies inside its block', all(inSpan));

fprintf('\n== %d failure(s)\n', nfail);
if nfail > 0, error('testBlocksOfMergedBreaths_pacedBreathing: %d failures', nfail); end
end

function b = inferBlocksQuiet(bm, fs, n, opts)
    evalc('b = inferBlocks_pacedBreathing(bm, fs, n, opts);');
end

function ok = chk(name, cond)
    if cond, fprintf('  ok   %s\n', name); ok = true; else, fprintf('  FAIL %s\n', name); ok = false; end
end

function e = tryId(f), try, f(); e = 'none'; catch ME, e = ME.identifier; end, end

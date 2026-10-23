function testCarryRespFromFinal()
%TESTCARRYRESPFROMFINAL  Synthetic self-test of the respiration carry (shared/carryOpenFinal,
%   carryRespFromFinal, carryFinishFromFinal). Writes fake "previous finals" to a temp folder and checks
%   the rows / targTrace / reconstructedBlocks that must be carried, the post-hoc fields kept, the SHA-256
%   against Get-FileHash, every strict error (sample count, labels, rspFlip, another recording, session id,
%   sample rate, hash, a row changed later), the breathingTasks_separate per-section mode (section label /
%   length / respiration-choice mismatches, rspSelected) and a second rerun on a carried final.
%   Run: testCarryRespFromFinal   (errors if any check fails; touches only tempdir; needs the repo on the path)
set(0, 'DefaultFigureVisible', 'off');

tmp = fullfile(tempdir, 'zlp_carry_test'); if ~exist(tmp, 'dir'), mkdir(tmp); end
fs = 500; n = fs * 120;
rng(1);
t = (0:n - 1) / fs;
base = sin(2 * pi * 0.25 * t) + 0.05 * randn(1, n);
nfail = 0;

% ---------- previous final ----------
labels = {'Fp1', 'Fz', 'macro1', 'rsp1', 'rsp2', 'ECG1', 'event', 'badTS', 'targTrace'};
old = struct();
old.labels = labels;
old.fs = fs;
old.sessID = 'TEST_SESS_1';
old.task = 'breathingTask';
old.rspIDX = 1; old.rspFlip = 1;
D = randn(numel(labels), n);
D(4, :) = base * 100 + 5;                 % rsp1
D(5, :) = base * 80 - 3;                  % rsp2
D(9, :) = sin(2 * pi * 0.1 * t);          % targTrace
old.data = D;
rb = table(["a.csv"; "b.csv"], [1000; 30000], [2000; 31000], 'VariableNames', {'srcFile', 'i0', 'i1'});
old.reconstructedBlocks = rb;
old.bestMac = struct('x', 1:5);           % a post-hoc field
old.ridgeInfo = 'abc';
old.behDat = table((1:3)', 'VariableNames', {'a'});
old.bmFeatures = struct('version', 'ZLP rev13');
old.moreThan1 = 1;
% stage outputs of the previous run that a rerun configured differently does not produce (251027_Dupi_NMH_DL_1 breathingTask:
% blink removal on in the old final, off since G2f): must NOT be carried
old.blinkICA = struct('rule', 'frontal', 'nRemoved', 1); old.blinkRemoval = 1;
old.EEGCleaningInfo = struct('mode', 'fixed'); old.dataLap = randn(2, 5);
outDat = old;                              % the stored variable is called outDat
srcFile = fullfile(tmp, 'TEST_SESS_1_breathingPreproc.mat');
save(srcFile, 'outDat', '-v7.3');
clear outDat

% ---------- new outDat after the shared core: own rsp rows, no targTrace, no post-hoc fields ----------
nw = struct();
nw.labels = labels(1:8);
nw.fs = fs; nw.sessID = 'TEST_SESS_1'; nw.task = 'breathingTask';
nw.rspIDX = 1; nw.rspFlip = 1;
Dn = D(1:8, :);
Dn(4, :) = Dn(4, :) + 0.5 * randn(1, n);   % small difference (e.g. filter) -> still r ~ 1
Dn(4, 1000:2000) = 0;                      % inside the reconstructed block: must not count
nw.data = Dn;
nw.behDat = old.behDat; nw.bmFeatures = old.bmFeatures; nw.moreThan1 = 1;
P = struct('rspIDX', 1, 'rspFlip', 1);

% 1) no env var -> nothing happens
setenv('ZLP_CARRY_FROM', ''); setenv('ZLP_CARRY_SHA256', '');
[o1, CS1] = carryRespFromFinal(nw, P);
nfail = nfail + ~chk('no env: outDat untouched, CS empty', isempty(CS1) && isequaln(o1, nw));
o1 = carryFinishFromFinal(o1, CS1);
nfail = nfail + ~chk('no env: finish is a no-op', isequaln(o1, nw));

% 2) carry
setenv('ZLP_CARRY_FROM', srcFile);
[o2, CS2] = carryRespFromFinal(nw, P);
nfail = nfail + ~chk('rsp1 carried', isequal(o2.data(4, :), D(4, :)));
nfail = nfail + ~chk('rsp2 carried', isequal(o2.data(5, :), D(5, :)));
nfail = nfail + ~chk('targTrace appended', strcmp(o2.labels{end}, 'targTrace') && isequal(o2.data(end, :), D(9, :)));
nfail = nfail + ~chk('reconstructedBlocks carried', isequal(o2.reconstructedBlocks, rb));
nfail = nfail + ~chk('carry record', o2.carry.targTraceCarried && o2.carry.reconstructedCarried && ~isempty(o2.carry.sha256) && o2.carry.checks.r(1) > 0.99);
nfail = nfail + ~chk('excluded samples counted', o2.carry.checks.nExcluded == 2002);
o2.bmObj = []; % pipeline would add fields here
o2.heartBeats = 1;
o2 = carryFinishFromFinal(o2, CS2);
nfail = nfail + ~chk('post-hoc fields kept', isfield(o2, 'carriedFromPrevFinal') && isfield(o2.carriedFromPrevFinal, 'bestMac') && isfield(o2.carriedFromPrevFinal, 'ridgeInfo'));
nfail = nfail + ~chk('post-hoc names recorded', isequal(sort(o2.carry.postHocFields), sort({'bestMac', 'ridgeInfo'})) && o2.carry.rowsVerified);
% the DL_1 breathing case: the old blinkICA (and the other EEG-stage outputs the new run did not produce) is NOT carried, only named
nfail = nfail + ~chk('old blinkICA / EEGCleaningInfo / blinkRemoval / dataLap are not in carriedFromPrevFinal', ...
    ~any(isfield(o2.carriedFromPrevFinal, {'blinkICA', 'EEGCleaningInfo', 'blinkRemoval', 'dataLap'})) && ~isfield(o2, 'blinkICA'));
nfail = nfail + ~chk('stage fields named in carry.stageFieldsNotCarried', ...
    isequal(sort(o2.carry.stageFieldsNotCarried), sort({'EEGCleaningInfo', 'blinkICA', 'blinkRemoval', 'dataLap'})) && ~isempty(o2.carry.stageFieldsNote));
nfail = nfail + ~chk('no carry of EEG rows', isequal(o2.data(1:3, :), Dn(1:3, :)));
sha = o2.carry.sha256;
[~, ref] = system(sprintf('powershell -NoProfile -Command "(Get-FileHash -Algorithm SHA256 -LiteralPath ''%s'').Hash"', srcFile));
nfail = nfail + ~chk('sha256 equals Get-FileHash', strcmpi(strtrim(ref), sha));

% 3) hash env: right and wrong
setenv('ZLP_CARRY_SHA256', sha);
[~, C3] = carryRespFromFinal(nw, P); nfail = nfail + ~chk('hash env equal accepted', ~isempty(C3));
setenv('ZLP_CARRY_SHA256', repmat('0', 1, 64));
try, carryRespFromFinal(nw, P); chk('hash mismatch errors', false); nfail = nfail + 1; catch ME, nfail = nfail + ~chk('hash mismatch errors', strcmp(ME.identifier, 'carryOpenFinal:hashMismatch')); end
setenv('ZLP_CARRY_SHA256', '');

% 4) strict errors
x = nw; x.data = x.data(:, 1:end-1);
nfail = nfail + ~chk('sample-count mismatch errors', strcmp(tryId(@() carryRespFromFinal(x, P)), 'carryRespFromFinal:nSamp'));
x = nw; x.labels{5} = 'rsp3';
nfail = nfail + ~chk('label mismatch errors', strcmp(tryId(@() carryRespFromFinal(x, P)), 'carryRespFromFinal:labels'));
nfail = nfail + ~chk('rspFlip mismatch errors', strcmp(tryId(@() carryRespFromFinal(nw, struct('rspIDX', 1, 'rspFlip', -1))), 'carryRespFromFinal:rspMismatch'));
x = nw; x.data(4, :) = randn(1, n);
nfail = nfail + ~chk('other recording errors', strcmp(tryId(@() carryRespFromFinal(x, P)), 'carryRespFromFinal:notSameRecording'));
% line pickup on an auxiliary row (the pre-July notch had removed it): carried, the respiration-band r stays ~1 (validation 2026-10-22, GH_2 rsp2)
x = nw; x.data(5, :) = x.data(5, :) + 150 * sin(2 * pi * 60 * (0:n - 1) / fs);
ox = carryRespFromFinal(x, P);
nfail = nfail + ~chk('aux row with 60 Hz pickup passes: r (< 5 Hz) ~ 1, rBroad < 0.9 kept', ox.carry.checks.r(2) > 0.99 && ox.carry.checks.rBroad(2) < 0.9 && isequal(ox.carry.checks.selected', [true false]));
% the selected channel with the same pickup passes too; an auxiliary row that is another recording only WARNS
x = nw; x.data(4, :) = x.data(4, :) + 150 * sin(2 * pi * 60 * (0:n - 1) / fs);
ox = carryRespFromFinal(x, P);
nfail = nfail + ~chk('selected row with 60 Hz pickup passes', ox.carry.checks.r(1) > 0.99 && ox.carry.checks.rBroad(1) < 0.9);
x = nw; x.data(5, :) = randn(1, n);
lastwarn('');
ox = carryRespFromFinal(x, P); [~, wid] = lastwarn;
nfail = nfail + ~chk('auxiliary row of another recording warns, does not error', strcmp(wid, 'carryRespFromFinal:auxRow') && isequal(ox.carry.checks.auxLow, 2) && isequal(ox.data(5, :), D(5, :)));
x = nw; x.data(4, :) = circshift(x.data(4, :), 2 * fs);   % selected row shifted by 2 s (half a breath): still rejected
nfail = nfail + ~chk('selected row shifted 2 s errors', strcmp(tryId(@() carryRespFromFinal(x, P)), 'carryRespFromFinal:notSameRecording'));
x = nw; x.sessID = 'OTHER';
nfail = nfail + ~chk('session mismatch errors', strcmp(tryId(@() carryRespFromFinal(x, P)), 'carryRespFromFinal:sessID'));
x = nw; x.fs = 250;
nfail = nfail + ~chk('fs mismatch errors', strcmp(tryId(@() carryRespFromFinal(x, P)), 'carryRespFromFinal:fs'));
% a later stage altering a carried row
[o4, CS4] = carryRespFromFinal(nw, P); o4.data(4, 77) = 1e3;
nfail = nfail + ~chk('changed row caught at the end', strcmp(tryId(@() carryFinishFromFinal(o4, CS4)), 'carryFinishFromFinal:rowChanged'));
% finish without apply
nfail = nfail + ~chk('finish without apply errors', strcmp(tryId(@() carryFinishFromFinal(nw, CS4)), 'carryFinishFromFinal:noCarry'));

% 5) P.carryFrom wins over the variable; sections
setenv('ZLP_CARRY_FROM', fullfile(tmp, 'nonexistent.mat'));
P5 = P; P5.carryFrom = srcFile;
[~, C5] = carryRespFromFinal(nw, P5); nfail = nfail + ~chk('P.carryFrom wins', ~isempty(C5));
nfail = nfail + ~chk('missing file errors', strcmp(tryId(@() carryRespFromFinal(nw, P)), 'carryOpenFinal:noFile'));

% ---------- separate: sections + rspSelected ----------
nA = fs * 50; nB = n - nA;
sepOld = old; sepOld = rmfield(sepOld, {'reconstructedBlocks'});
sepOld.labels = {'Fp1', 'rsp1', 'rsp2', 'rspSelected', 'badTS'};
Ds = randn(5, n);
Ds(2, :) = base * 100;  Ds(3, :) = base * 50 + 1;
Ds(4, 1:nA) = Ds(2, 1:nA); Ds(4, nA+1:end) = Ds(3, nA+1:end);       % section 2 uses rsp2
sepOld.data = Ds;
sepOld.sections = table(["sleep"; "audioBook"], [1; nA + 1], [nA; n], [1; 2], [1; 1], 'VariableNames', {'label', 'startSample', 'endSample', 'rspIDX', 'rspFlip'});
sepOld.rspIDX = 3; sepOld.rspFlip = 1;
outDat = sepOld; srcSep = fullfile(tmp, 'TEST_SESS_1_breathingTasks_separatepreproc.mat'); save(srcSep, 'outDat', '-v7.3'); clear outDat
setenv('ZLP_CARRY_FROM', srcSep);
Psep = struct('rspIDX', 1, 'rspFlip', 1);
CSs = carryOpenFinal(Psep, 'TEST_SESS_1', struct('ignoreLabels', {{'rspSelected'}}));
recs = cell(1, 2); lens = [nA nB]; offs = [0 nA]; secLab = {'sleep', 'audioBook'}; secRsp = [1 1; 2 1];
parts = cell(1, 2);
for c = 1:2
    s = struct('labels', {{'Fp1', 'rsp1', 'rsp2', 'badTS'}}, 'fs', fs, 'sessID', 'TEST_SESS_1');
    s.data = Ds([1 2 3 5], offs(c) + (1:lens(c))) + 0.001 * randn(4, lens(c)) .* [0; 1; 1; 0];
    s = carryRespFromFinal(s, Psep, CSs, struct('index', c, 'label', secLab{c}, 'nSections', 2, 'rspIDX', secRsp(c, 1), 'rspFlip', secRsp(c, 2)));
    recs{c} = s.carry; parts{c} = s;
end
nfail = nfail + ~chk('section rows carried', isequal(parts{1}.data(2, :), Ds(2, 1:nA)) && isequal(parts{2}.data(3, :), Ds(3, nA+1:end)));
% concatenated "final"
fin = parts{1}; fin.data = [parts{1}.data, parts{2}.data]; fin.labels = parts{1}.labels;
sel = [fin.data(2, 1:nA), fin.data(3, nA+1:end)];
fin.data(end+1, :) = sel; fin.labels{end+1} = 'rspSelected';
fin.sessID = 'TEST_SESS_1'; fin.heartBeats = 1;
fin = carryFinishFromFinal(fin, CSs, recs);
nfail = nfail + ~chk('sep record has perSection', numel(fin.carry.perSection) == 2 && fin.carry.rowsVerified && fin.carry.rspSelectedVerified);
nfail = nfail + ~chk('sep post-hoc fields', isfield(fin, 'carriedFromPrevFinal') && isfield(fin.carriedFromPrevFinal, 'bestMac'));
nfail = nfail + ~chk('sep section label mismatch errors', strcmp(tryId(@() carryRespFromFinal(parts{1}, Psep, CSs, struct('index', 1, 'label', 'focused', 'nSections', 2, 'rspIDX', 1, 'rspFlip', 1))), 'carryRespFromFinal:sectionLabel'));
nfail = nfail + ~chk('sep section length mismatch errors', strcmp(tryId(@() carryRespFromFinal(parts{2}, Psep, CSs, struct('index', 1, 'label', 'sleep', 'nSections', 2, 'rspIDX', 1, 'rspFlip', 1))), 'carryRespFromFinal:nSamp'));
nfail = nfail + ~chk('sep per-section rsp mismatch errors', strcmp(tryId(@() carryRespFromFinal(parts{2}, Psep, CSs, struct('index', 2, 'label', 'audioBook', 'nSections', 2, 'rspIDX', 1, 'rspFlip', 1))), 'carryRespFromFinal:rspMismatch'));
bad = fin; bad.data(end, 5) = 7;
nfail = nfail + ~chk('rspSelected change caught', strcmp(tryId(@() carryFinishFromFinal(bad, CSs, recs)), 'carryFinishFromFinal:rowChanged') ...
    || strcmp(tryId(@() carryFinishFromFinal(bad, CSs, recs)), 'carryFinishFromFinal:rspSelected'));
setenv('ZLP_CARRY_FROM', '');

% ---------- second rerun: previous final has carry + carriedFromPrevFinal ----------
o2b = o2; outDat = o2b; src2 = fullfile(tmp, 'TEST_SESS_1_rerun2.mat'); save(src2, 'outDat', '-v7.3'); clear outDat
setenv('ZLP_CARRY_FROM', src2);
[o6, C6] = carryRespFromFinal(nw, P); o6.heartBeats = 1; o6.bmObj = [];
o6 = carryFinishFromFinal(o6, C6);
nfail = nfail + ~chk('chained rerun keeps earlier post-hoc fields', isfield(o6, 'carriedFromPrevFinal') && isfield(o6.carriedFromPrevFinal, 'bestMac') && isfield(o6.carry, 'previous'));
setenv('ZLP_CARRY_FROM', '');

% ---------- the exclusion set covers every field the repo's code writes (drift guard) ----------
root = fileparts(fileparts(mfilename('fullpath')));
pipe = carryPipelineFields();
nfail = nfail + ~chk('carryPipelineFields: a sorted, unique column', iscolumn(pipe) && isequal(pipe, unique(pipe)));
written = scanOutDatFields(root);
unlisted = setdiff(written, [pipe; {'carry'; 'carriedFromPrevFinal'; 'reconstructedBlocks'}]);
nfail = nfail + ~chk(sprintf('every outDat field written under pipelines/ shared/ tasks/ config/ is in carryPipelineFields (%d scanned; unlisted: %s)', ...
    numel(written), strjoin(unlisted(:)', ', ')), isempty(unlisted));
nfail = nfail + ~chk('post-hoc fields (O15 bestMac ..., reconstructedBlocks) and the carry records are not in carryPipelineFields', ...
    ~any(ismember({'bestMac', 'bestMacMethod', 'powerPhaseContinuity', 'ridgeInfo', 'reconstructedBlocks', 'carry', 'carriedFromPrevFinal'}, pipe)));

fprintf('\n== %d failure(s)\n', nfail);
if nfail > 0, error('testCarryRespFromFinal: %d failures', nfail); end
end

function ok = chk(name, cond)
    if cond, fprintf('  ok   %s\n', name); ok = true; else, fprintf('  FAIL %s\n', name); ok = false; end
end

function e = tryId(f), try, f(); e = 'none'; catch ME, e = ME.identifier; end, end

function names = scanOutDatFields(root)
% top-level fields assigned as  outDat.<f> = / outDat.<f>.<g>(..) = / [outDat.<f>, ...] =  in the pipeline code
    names = {};
    for d = {'pipelines', 'shared', 'tasks', 'config'}
        files = dir(fullfile(root, d{1}, '**', '*.m'));
        for k = 1:numel(files)
            lines = regexp(fileread(fullfile(files(k).folder, files(k).name)), '\r?\n', 'split');
            for i = 1:numel(lines)
                code = regexprep(lines{i}, '%.*$', '');
                tok = regexp(code, '\<outDat\.(\w+)(?:\.\w+|\([^)]*\))*\s*=(?!=)', 'tokens');
                for t = 1:numel(tok), names{end + 1, 1} = tok{t}{1}; end %#ok<AGROW>
                lhs = regexp(code, '^\s*\[([^\]]*)\]\s*=', 'tokens', 'once');
                if ~isempty(lhs)
                    tok = regexp(lhs{1}, '\<outDat\.(\w+)', 'tokens');
                    for t = 1:numel(tok), names{end + 1, 1} = tok{t}{1}; end %#ok<AGROW>
                end
            end
        end
    end
    names = unique(names);
end

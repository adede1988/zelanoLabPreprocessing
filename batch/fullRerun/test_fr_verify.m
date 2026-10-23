function test_fr_verify()
%TEST_FR_VERIFY  Self-test of fr_verify's carry gate (codeReview M2) on synthetic finals - no data, no lab, a few seconds.
%
%   test_fr_verify          % run from the repo (batch/fullRerun is on the path via genpath) ; errors on the first wrong verdict
%
%   Builds a tiny "O15"-shaped old and new final in a temp folder, with an outDat.carry record of the shape carryRespFromFinal /
%   carryFinishFromFinal write, and checks fr_verify's verdict for: a clean carry; a NaN r on the selected channel (must FAIL, deterministic);
%   a shifted recording (r 0.93: fails for a previous final from before the notch removal AND, by nDiff, for one from after it); an
%   auxiliary row with a NaN r (only a warning); an unrecorded rspIDX / rspFlip (a warning); a breathingTasks_separate-style record with
%   perSection checks; and that an unrelated failure is NOT deterministic.
td = fullfile(tempname, 'frVerifyTest'); mkdir(td);
cleanup = onCleanup(@() rmdir(fileparts(td), 's')); %#ok<NASGU>
fs = 500; n = 60 * fs;
t = (0:n-1) / fs;
base = struct('data', [sin(2*pi*0.25*t); sin(2*pi*0.3*t + 1); 0.1*randn(1, n)], 'labels', {{'rsp1_a', 'rsp2_b', 'event'}}, ...
    'fs', fs, 'moreThan1', 0, 'sessID', 'S1', 'task', 'O15', 'type', 'OBE');
base.behDat = table([1; 2], [3; 4], [100; 200], 'VariableNames', {'n', 'manOnset', 'finalOnset'});
base.TTL = [1 2];

okAll = true;
% 1. clean carry, previous final saved after the notch removal
okAll = check('clean carry (post-notch)', td, base, mkCarry(1, 1, 0, true), datenum(2026, 9, 1), true, false, {}) && okAll;
% 2. NaN r on the selected channel
okAll = check('NaN r on the selected channel', td, base, mkCarry(NaN, 1, 0, true), datenum(2026, 9, 1), false, true, {'no finite same-recording correlation'}) && okAll;
% 3. shifted recording: r = 0.93 and half of the samples differ; the previous final is from before the notch removal
okAll = check('r 0.93, notch era', td, base, mkCarry(0.93, 1, 0.5, true), datenum(2026, 5, 1), false, true, {'predates the notch removal'}) && okAll;
% 4. the same r in a post-notch previous final: nDiff fails it (the same processing must give the same row)
okAll = check('r 0.93 + many differing samples, post-notch', td, base, mkCarry(0.93, 1, 0.5, true), datenum(2026, 9, 1), false, true, {'differs from the rerun''s own row in'}) && okAll;
% 5. a notch-era previous final: every sample differs (the notch) but r is ~1: only fine
okAll = check('r 0.999 with all samples differing, notch era', td, base, mkCarry(0.999, 1, 1, true), datenum(2026, 5, 1), true, false, {}) && okAll;
% 6. r below 0.90
okAll = check('r 0.7', td, base, mkCarry(0.7, 1, 0, true), datenum(2026, 9, 1), false, true, {'correlates r = 0.700'}) && okAll;
% 7. auxiliary row NaN: a warning only
okAll = check('auxiliary row NaN', td, base, mkCarry(1, NaN, 0, true), datenum(2026, 9, 1), true, false, {'auxiliary'}) && okAll;
% 8. no rspIDX / rspFlip recorded in the previous final: a warning
okAll = check('rspMatch false', td, base, mkCarry(1, 1, 0, false), datenum(2026, 9, 1), true, false, {'records no rspIDX'}) && okAll;
% 9. a sep-style record: perSection, one section NaN
cs = mkCarry(1, 1, 0, true);
rec2 = mkCarry(NaN, 1, 0, true).checks;
sepCarry = cs; sepCarry.perSection = {cs, struct('checks', rec2, 'rowsCarried', {{'rsp1_a', 'rsp2_b'}})}; sepCarry.checks = struct('perSection', true);
okAll = check('sep perSection, section 2 NaN', td, base, sepCarry, datenum(2026, 9, 1), false, true, {'(section 2)'}) && okAll;
% 10. no checks recorded at all
bad = mkCarry(1, 1, 0, true); bad = rmfield(bad, 'checks'); bad.checks = struct('nSamp', n);
okAll = check('carry record without per-row checks', td, base, bad, datenum(2026, 9, 1), false, true, {'no per-row checks'}) && okAll;
% 11. an unrelated failure (fs wrong) is not deterministic
b2 = base; b2.fs = 250;
okAll = check('fs 250 (not a carry failure)', td, b2, mkCarry(1, 1, 0, true), datenum(2026, 9, 1), false, false, {'fs is not 500'}) && okAll;
if ~okAll, error('test_fr_verify:failed', 'at least one case gave the wrong verdict - see the lines above'); end
fprintf('test_fr_verify: all cases passed\n');
end

function carry = mkCarry(rSel, rAux, fracDiff, rspMatch)
% an outDat.carry record of the shape carryRespFromFinal / carryFinishFromFinal write (2 carried rows, the first one is the selected channel)
n = 60 * 500;
chk = struct('nSamp', n, 'sessIDMatch', true, 'labelsMatch', true, 'rspMatch', rspMatch, 'r', [rSel; rAux], 'rBroad', [rSel; rAux], ...
    'maxAbsDiff', [0.4 * (fracDiff > 0); 0], 'nDiff', [round(fracDiff * n); 0], 'selected', [true; false], 'auxLow', zeros(1, 0), ...
    'nExcluded', 0, 'nNonFinite', 0);
carry = struct('source', 'x', 'sha256', 'abc', 'rowsCarried', {{'rsp1_a', 'rsp2_b'}}, 'rowsVerified', true, 'postHocFields', {{}}, 'checks', chk);
end

function c = tocell(x)
% jsondecode gives [] for no entries, a char row for one, a cellstr for several
if isempty(x), c = cell(0, 1); elseif ischar(x), c = {x}; else, c = x(:); end
end

function ok = check(name, td, base, carry, oldDate, wantOk, wantDet, wantText)
% writes the old / new finals, runs fr_verify, compares the verdict
N = base; N.carry = carry;
oldF = fullfile(td, 'old.mat'); newF = fullfile(td, 'new.mat');
outDat = base; save(oldF, 'outDat', '-v7'); %#ok<NASGU>
outDat = N; save(newF, 'outDat', '-v7');
% the old final's modification time is what fr_verify uses as "when it was saved"
jf = java.io.File(oldF); jf.setLastModified(int64((oldDate - 719529) * 86400000));
resF = fullfile(td, 'res.json');
A = struct('key', 'T__x', 'task', 'O15', 'sessID', 'S1', 'newFinal', newF, 'oldFinal', oldF, 'hasEEG', false, 'carry', true, 'paramSource', 'curated', ...
    'resultJson', resF, 'compareDir', fullfile(td, 'cmp'), 'sheetBefore', '', 'sheetAfter', '', 'runStartUtc', '', 'scratch', true, 'backupSha', 'abc', 'sepEchem', false);
aj = fullfile(td, 'args.json'); fid = fopen(aj, 'w'); fwrite(fid, jsonencode(A), 'char'); fclose(fid);
evalc('fr_verify(aj);');
R = jsondecode(fileread(resF));
txt = strjoin([tocell(R.failures); tocell(R.warnings)]', ' | ');
ok = (R.ok == wantOk) && (R.deterministic == wantDet);
for k = 1:numel(wantText), ok = ok && contains(txt, wantText{k}); end
if ok, fprintf('  ok   %s\n', name);
else, fprintf('  FAIL %s: ok=%d (want %d) deterministic=%d (want %d)\n       %s\n', name, R.ok, wantOk, R.deterministic, wantDet, txt); end
end

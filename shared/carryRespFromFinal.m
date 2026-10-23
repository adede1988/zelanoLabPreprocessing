function [outDat, CS] = carryRespFromFinal(outDat, P, CS, sec)
%CARRYRESPFROMFINAL  Copy the previous final's respiration rows into the new outDat (rerun carry).
%
%   [outDat, CS] = carryRespFromFinal(outDat, P)            % opens the source itself
%   [outDat, CS] = carryRespFromFinal(outDat, P, CS)         % CS from carryOpenFinal
%   [outDat, CS] = carryRespFromFinal(outDat, P, CS, sec)    % one breathingTasks_separate section
%
%   Call it right after runSharedCore, before anything reads the respiration
%   (sniff detection, segmentation, target alignment, ECG). Without
%   ZLP_CARRY_FROM / P.carryFrom (carryOpenFinal) CS is [] and outDat is
%   returned untouched, so a main that calls it runs exactly as before.
%
%   What it does, strictly (any mismatch errors, carryRespFromFinal:*):
%     - sample rate, sample count (the whole recording; for a section, the
%       section's span in the previous final), session id (or the id in the
%       source path) must agree;
%     - the new outDat's rsp* rows must have the same labels, in the same
%       order, as the previous final's (rspIDX indexes them);
%     - the previous final's rspIDX / rspFlip must equal the sheet's (P): the
%       carried rows are read through them. A decision written only into a
%       final (ZLP_FLIPFIX / ZLP_RSPIDXFIX) has to be in the sheet first;
%     - the SELECTED respiration channel (rspIDX) must still be the same
%       recording: Pearson r between the new pipeline's own row and the previous
%       final's, outside the reconstructed blocks, >= 0.90. The correlation is
%       taken on the respiration band (< 5 Hz, 4th-order Butterworth, zero
%       phase): finals made before July 2026 went through a 60/120/180 Hz notch
%       that the shared core no longer applies, and an auxiliary channel with
%       strong line pickup correlates only r ~ 0.4 broadband although it is the
%       same recording (validation 2026-10-22, 250929_Dupi_NMH_GH_2 rsp2:
%       broadband 0.41, < 5 Hz 0.98). The other rsp rows are carried too and
%       only WARN (carryRespFromFinal:auxRow, chk.auxLow) below 0.90; the
%       broadband r of every row is kept in chk.rBroad.
%   Then every rsp row of outDat is REPLACED by the previous final's, a
%   targTrace row is appended (or replaced) when the previous final has one,
%   and outDat.reconstructedBlocks is copied when it has that (single
%   recording only: it is a table of the previous final's block spans).
%   outDat.carry records what happened:
%     source, sha256, bytes, modified, sourceVar, date; made (the previous
%     final's engine version / EEG cleaning mode / moreThan1 / breath-merge);
%     rowsCarried (labels), targTraceCarried, reconstructedCarried,
%     rspIDX, rspFlip; section (index, label, span in the previous final;
%     sections only); checks: nSamp, sessIDMatch, labelsMatch, rspMatch,
%     per carried row r / maxAbsDiff / nDiff (samples where the new pipeline's
%     own row differs from the carried one beyond 1e-6 of its range, outside
%     the reconstructed blocks) / nExcluded (samples inside reconstructed
%     blocks), nNonFinite (in the carried rows);
%     note (what the carry means).
%   Mains finish with carryFinishFromFinal (verifies the rows survived to the
%   save, keeps the previous final's post-hoc fields, completes the record).
%
%   sec (breathingTasks_separate, one call per condition recording): struct
%   with .index (position in the session), .label (the section's condition
%   label), .nSections, .rspIDX / .rspFlip (this recording's sheet choice).
%   The section must be the index-th row of the previous final's section
%   table with the same label, and its sample span must equal this
%   recording's length. Not applicable to a previous final without sections.

    if nargin < 3, CS = carryOpenFinal(P, outDat.sessID); end
    if isempty(CS), return; end
    if nargin < 4, sec = []; end
    id = outDat.sessID;

    % ---- the span of the previous final this outDat corresponds to ----
    nNew = size(outDat.data, 2);
    if isempty(sec)
        i0 = 1; i1 = CS.nSamp;
    else
        if isempty(CS.sections)
            error('carryRespFromFinal:noSections', '%s: the previous final has no section table (%s)', id, CS.path);
        end
        if height(CS.sections) ~= sec.nSections
            error('carryRespFromFinal:sectionCount', '%s: the previous final has %d sections, the rerun %d', ...
                id, height(CS.sections), sec.nSections);
        end
        if ~strcmp(char(string(CS.sections.label(sec.index))), char(string(sec.label)))
            error('carryRespFromFinal:sectionLabel', '%s: section %d is %s in the previous final but %s in the rerun', ...
                id, sec.index, char(string(CS.sections.label(sec.index))), char(string(sec.label)));
        end
        i0 = double(CS.sections.startSample(sec.index));
        i1 = double(CS.sections.endSample(sec.index));
    end
    chk = struct();
    if abs(CS.fs - outDat.fs) > 1e-9
        error('carryRespFromFinal:fs', '%s: sample rate %g in the previous final, %g now', id, CS.fs, outDat.fs);
    end
    if i1 - i0 + 1 ~= nNew
        where = '';
        if ~isempty(sec), where = sprintf(' (section %d)', sec.index); end
        error('carryRespFromFinal:nSamp', '%s: %d samples in the previous final%s, %d now - not the same recording / processing', ...
            id, i1 - i0 + 1, where, nNew);
    end
    chk.nSamp = nNew;
    chk.sessIDMatch = isempty(CS.sessID) || strcmp(CS.sessID, id) || contains(CS.path, id);
    if ~chk.sessIDMatch
        error('carryRespFromFinal:sessID', '%s: the previous final (%s) belongs to session %s', id, CS.path, CS.sessID);
    end

    % ---- labels ----
    lab = cellfun(@(x) char(string(x)), outDat.labels(:)', 'UniformOutput', false);
    newRsp = find(cellfun(@(x) contains(x, 'rsp'), lab) & ~ismember(lab, CS.ignore));
    if ~isequal(lab(newRsp), CS.rspLabels)
        error('carryRespFromFinal:labels', '%s: rsp rows %s now, %s in the previous final', id, ...
            strjoin(lab(newRsp), ','), strjoin(CS.rspLabels, ','));
    end
    chk.labelsMatch = true;

    % ---- respiration channel / polarity must be what the sheet says ----
    if isempty(sec)
        expIDX = P.rspIDX; expFlip = P.rspFlip;
        oldIDX = CS.rspIDX; oldFlip = CS.rspFlip;
    else
        expIDX = sec.rspIDX; expFlip = sec.rspFlip;
        oldIDX = []; oldFlip = [];
        if ~isempty(CS.secRsp), oldIDX = CS.secRsp(sec.index, 1); oldFlip = CS.secRsp(sec.index, 2); end
    end
    chk.rspMatch = true;
    if ~isempty(oldIDX) && ~isempty(oldFlip)
        if oldIDX ~= expIDX || oldFlip ~= expFlip
            error('carryRespFromFinal:rspMismatch', ['%s: the previous final reads respiration through rspIDX %g / rspFlip %+g, ' ...
                'the sheet says %g / %+g - make the sheet and the final agree first (CLAUDE.md section 7), then rerun'], ...
                id, oldIDX, oldFlip, expIDX, expFlip);
        end
    else
        chk.rspMatch = false;   % the previous final records no channel choice: nothing to compare
    end

    % ---- same recording? (new pipeline's own row vs the carried one) ----
    skip = false(1, nNew);
    rb = CS.reconstructedBlocks;
    if isempty(sec) && istable(rb) && all(ismember({'i0', 'i1'}, rb.Properties.VariableNames))
        for k = 1:height(rb)
            a = max(1, round(rb.i0(k))); b = min(nNew, round(rb.i1(k)));
            if b >= a, skip(a:b) = true; end
        end
    end
    nR = numel(newRsp);
    % the selected channel (rspIDX = position among ALL 'rsp' rows); when it cannot be found among the
    % carried rows, every carried row is held to the hard test (the strict behaviour before 2026-10-22)
    allRsp = find(cellfun(@(x) contains(x, 'rsp'), lab));
    isSel = false(nR, 1);
    if isfinite(expIDX) && expIDX >= 1 && expIDX <= numel(allRsp), isSel = (newRsp(:) == allRsp(expIDX)); end
    selFound = any(isSel);
    if ~selFound, isSel(:) = true; end
    lowd = designfilt('lowpassiir', 'FilterOrder', 4, 'HalfPowerFrequency', 5, 'SampleRate', outDat.fs);
    chk.r = nan(nR, 1); chk.rBroad = nan(nR, 1); chk.maxAbsDiff = nan(nR, 1); chk.nDiff = nan(nR, 1);
    chk.selected = isSel; chk.auxLow = zeros(1, 0);
    for j = 1:nR
        a = double(outDat.data(newRsp(j), :));
        b = CS.rspRows(j, i0:i1);
        ok = isfinite(a) & isfinite(b) & ~skip;
        if nnz(ok) >= 100
            aa = a(ok); bb = b(ok);
            if std(aa) > 0 && std(bb) > 0
                cc = corrcoef(aa, bb);
                chk.rBroad(j) = cc(1, 2);
                % respiration band (< 5 Hz): same recording => ~1 whatever the line pickup / the old notch did
                af = filtfilt(lowd, fillmissing(a, 'linear', 'EndValues', 'nearest'));
                bf = filtfilt(lowd, fillmissing(double(b), 'linear', 'EndValues', 'nearest'));
                if std(af(ok)) > 0 && std(bf(ok)) > 0
                    cc = corrcoef(af(ok), bf(ok));
                    chk.r(j) = cc(1, 2);
                else
                    chk.r(j) = chk.rBroad(j);
                end
            end
            chk.maxAbsDiff(j) = max(abs(aa - bb));
            chk.nDiff(j) = nnz(abs(aa - bb) > 1e-6 * max(1, max(abs(aa))));
        end
        if selFound && isSel(j) && ~isfinite(chk.r(j))
            % the selected channel must be shown to be the same recording: a flat row or < 100 usable
            % samples gives no correlation, which is a refusal, not a pass
            error('carryRespFromFinal:notSameRecording', ['%s: the selected %s gives no usable correlation with ' ...
                'the rerun''s own row (flat or < 100 finite samples outside reconstructed spans) - cannot confirm ' ...
                'the same recording'], id, CS.rspLabels{j});
        end
        if isfinite(chk.r(j)) && chk.r(j) < 0.90
            if isSel(j)
                error('carryRespFromFinal:notSameRecording', ['%s: %s of the previous final correlates r = %.3f (< 5 Hz; broadband %.3f) ' ...
                    'with the rerun''s own %s (need >= 0.90) - not the same recording or a shifted one'], ...
                    id, CS.rspLabels{j}, chk.r(j), chk.rBroad(j), CS.rspLabels{j});
            else
                chk.auxLow(end + 1) = j; %#ok<AGROW>
                warning('carryRespFromFinal:auxRow', ['%s: auxiliary %s of the previous final correlates r = %.3f (< 5 Hz; broadband %.3f) ' ...
                    'with the rerun''s own row - carried as it is (the selected channel agrees)'], id, CS.rspLabels{j}, chk.r(j), chk.rBroad(j));
            end
        end
    end
    chk.nExcluded = nnz(skip);
    chk.nNonFinite = CS.nNonFinite;

    % ---- replace the rsp rows; targTrace; reconstructed blocks ----
    for j = 1:nR
        outDat.data(newRsp(j), :) = CS.rspRows(j, i0:i1);
    end
    targCarried = false;
    if ~isempty(CS.targRow)
        iT = find(strcmp(lab, 'targTrace'));
        if isempty(iT)
            outDat.data(end + 1, :) = CS.targRow(1, i0:i1);
            outDat.labels{end + 1} = 'targTrace';
        elseif isscalar(iT)
            outDat.data(iT, :) = CS.targRow(1, i0:i1);
        else
            error('carryRespFromFinal:targTrace', '%s: %d targTrace rows in the rerun', id, numel(iT));
        end
        targCarried = true;
    end
    recCarried = false;
    if isempty(sec) && ~isempty(rb)
        outDat.reconstructedBlocks = rb;
        recCarried = true;
    end

    % ---- the record ----
    rec = struct();
    rec.source = CS.path;
    rec.sha256 = CS.sha256;
    rec.bytes = CS.bytes;
    rec.modified = CS.modified;
    rec.sourceVar = CS.varName;
    rec.date = char(datetime('now', 'Format', 'yyyy-MM-dd HH:mm:ss'));
    rec.made = CS.made;
    rec.rowsCarried = CS.rspLabels;
    rec.targTraceCarried = targCarried;
    rec.reconstructedCarried = recCarried;
    rec.rspIDX = expIDX;
    rec.rspFlip = expFlip;
    rec.checks = chk;
    if ~isempty(sec)
        rec.section = struct('index', sec.index, 'label', char(string(sec.label)), 'sourceFirstSample', i0, 'sourceLastSample', i1);
    end
    rec.note = ['respiration kept from the previous final (CLAUDE.md section 6.1 carry): every rsp* row ' ...
        '(and targTrace, reconstructedBlocks when the previous final had them) was copied from the source file ' ...
        'after the shared core; breath segmentation, sniff detection, ECG and the EEG were redone on top of it'];
    outDat.carry = rec;    % (breathingTasks_separate: the main collects the per-section records, carryFinishFromFinal)
    fprintf('%s: carried %s%s%s from the previous final (r vs the rerun''s own rows: %s)\n', id, strjoin(CS.rspLabels, ','), ...
        ternary(targCarried, ' + targTrace', ''), ternary(recCarried, ' + reconstructedBlocks', ''), mat2str(round(chk.r', 4)));
end

function v = ternary(c, a, b)
    if c, v = a; else, v = b; end
end

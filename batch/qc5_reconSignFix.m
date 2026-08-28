% qc5_reconSignFix - per-block reconstruction SIGN audit/fix (2026-08-28).
%
% The qc5 flip audit showed GA's reconstructedBlocks carry MIXED resolved
% signs within one session (cyclicSigh/slowBreath1,3/slowRec2,3 sgn=-1 vs
% slowBreath2/slowRec1 sgn=+1). The recording CSV's voltage orientation is
% constant within a session, so mixed signs = sign-resolution errors: those
% blocks are stored INVERTED (the user's "GA cyclicSigh is upside down").
%
% Ground truth per block: the CSV's own target column is canonically
% inhale-UP, so sgnCSV = sign(corr(voltage, target)) gives the voltage
% orientation without any filtering concerns (both columns are clean 20 Hz
% recordings). The stored segment displays inhale-up as data x rspFlip, and
% the reconstruction wrote segment = sgnUsed x scale x voltage, so the
% requirement is:
%     sgnRequired = rspFlip * sgnCSV
% Any block with sgnUsed ~= sgnRequired is stored inverted -> multiply the
% stored segment by -1 (edge-blend zones included; the blend mixed in
% correctly-signed natural trace, so the 1-s edges are approximate either
% way) and update the provenance row (sgn, status 'reconstructed-signfixed').
%
% DRY RUN by default: reports every block of every session with
% reconstructedBlocks. The zero-lag corr(voltage,target) turned out to be
% UNRELIABLE for cyclic patterns (tracking lag flips the sign - everyone's
% cyclicSigh reads ~-0.2), so CSV verdicts are REPORT-ONLY. Writes happen
% ONLY for sessions named in ZLP_RECONFIX_FORCE ('id=+1,...'): for those,
% every reconstructed block whose stored sgn differs from the forced
% required sgn is flipped in place (about its local mean). Requires
% ZLP_RECONFIX_APPLY=1 as well; finals are backed up to
% E:\reprocBackup_260824\reconSignFix\ first.

APPLY = strcmp(getenv('ZLP_RECONFIX_APPLY'), '1');
FORCE = containers.Map('KeyType', 'char', 'ValueType', 'double');
fEnv = getenv('ZLP_RECONFIX_FORCE');
if ~isempty(fEnv)
    pairs = strsplit(fEnv, ',');
    for p = 1:numel(pairs)
        kv = strsplit(strtrim(pairs{p}), '=');
        FORCE(kv{1}) = str2double(kv{2});
    end
end
BKD = 'E:\reprocBackup_260824\reconSignFix';
if APPLY && ~exist(BKD, 'dir'), mkdir(BKD); end
fprintf('qc5_reconSignFix: APPLY=%d\n', APPLY);

cfg = applyParams('breathingTask', 'main');
nFix = 0; nOK = 0; nUnres = 0;
for si = 1:numel(cfg.sessionIDs)
    id = cfg.sessionIDs{si};
    hits = dir(fullfile(cfg.root{si}, id, 'preProc', [id '_breathing*.mat']));
    if isempty(hits), continue; end
    fpath = fullfile(hits(1).folder, hits(1).name);
    try
        S = load(fpath); vNames = fieldnames(S); vName = vNames{1};
        od = S.(vName); clear S
        if ~isfield(od, 'reconstructedBlocks') || isempty(od.reconstructedBlocks)
            clear od; continue;
        end
        RB = od.reconstructedBlocks;
        isRsp = cellfun(@(x) contains(x, 'rsp'), od.labels);
        rspRow = find(isRsp); rspRow = rspRow(od.rspIDX);
        modified = false;

        % ---- forced session-level fix (the only write path) ----
        if APPLY && FORCE.isKey(id)
            sgnReq = FORCE(id);
            for b = 1:height(RB)
                if RB.sgn(b) == sgnReq, continue; end
                if ~modified
                    bfile = fullfile(BKD, hits(1).name);
                    if ~exist(bfile, 'file'), copyfile(fpath, bfile); end
                end
                seg = od.data(rspRow, RB.i0(b):RB.i1(b));
                mu = mean(seg);
                od.data(rspRow, RB.i0(b):RB.i1(b)) = mu - (seg - mu);
                od.reconstructedBlocks.sgn(b) = sgnReq;
                od.reconstructedBlocks.status(b) = {'reconstructed-signfixed'};
                fprintf('RSF FORCEFIX %s %-24s: sgn %+d -> %+d, block [%d..%d] flipped\n', ...
                    id, char(string(RB.shadowFile(b))), RB.sgn(b), sgnReq, RB.i0(b), RB.i1(b));
                modified = true;
            end
            if modified
                tmp = struct(); tmp.(vName) = od;
                save(fpath, '-struct', 'tmp', '-v7.3');
                fprintf('RSF SAVED %s\n', id);
                nFix = nFix + 1;
            end
            clear od; continue;
        end

        for b = 1:height(RB)
            src = char(string(RB.srcFile(b)));
            sgnUsed = RB.sgn(b);
            lbl = char(string(RB.shadowFile(b)));
            if ~exist(src, 'file')
                fprintf('RSF UNRES %s %-24s: CSV missing (%s)\n', id, lbl, src);
                nUnres = nUnres + 1; continue;
            end
            T = readtable(src);
            vn = lower(T.Properties.VariableNames);
            vi = find(contains(vn, 'voltage'), 1);
            ti = find(contains(vn, 'target'), 1);
            if isempty(vi) || isempty(ti)
                fprintf('RSF UNRES %s %-24s: no voltage/target column\n', id, lbl);
                nUnres = nUnres + 1; continue;
            end
            v = fillmissing(double(T.(T.Properties.VariableNames{vi})), 'linear', 'EndValues', 'nearest');
            tg = fillmissing(double(T.(T.Properties.VariableNames{ti})), 'linear', 'EndValues', 'nearest');
            if std(tg) < 1e-9 || std(v) < 1e-9
                fprintf('RSF UNRES %s %-24s: flat voltage/target\n', id, lbl);
                nUnres = nUnres + 1; continue;
            end
            cv = corr(v, tg);
            if abs(cv) < 0.3
                fprintf('RSF UNRES %s %-24s: weak corr(v,t)=%.2f (sgnUsed=%+d)\n', id, lbl, cv, sgnUsed);
                nUnres = nUnres + 1; continue;
            end
            sgnCSV = sign(cv);
            sgnReq = od.rspFlip * sgnCSV;
            if sgnUsed == sgnReq
                fprintf('RSF OK    %s %-24s: corr(v,t)=%+.2f sgnCSV=%+d rspFlip=%+d sgnUsed=%+d\n', ...
                    id, lbl, cv, sgnCSV, od.rspFlip, sgnUsed);
                nOK = nOK + 1;
            else
                fprintf('RSF WRONG %s %-24s: corr(v,t)=%+.2f sgnCSV=%+d rspFlip=%+d sgnUsed=%+d (report-only; fix via ZLP_RECONFIX_FORCE)\n', ...
                    id, lbl, cv, sgnCSV, od.rspFlip, sgnUsed);
                nFix = nFix + 1;
            end
        end
        clear od
    catch ME
        fprintf('RSF FAIL %s: %s\n', id, ME.message);
    end
end
fprintf('qc5_reconSignFix: DONE ok=%d wrong=%d unresolved=%d (APPLY=%d)\n', nOK, nFix, nUnres, APPLY);

function out = ternS(cond, a, b)
    if cond, out = a; else, out = b; end
end

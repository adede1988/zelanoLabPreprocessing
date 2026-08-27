% reconstructPacedBlocks — QC round 3 step 1: the acquisition low-cut filter
% distorts slow breathing, so slowBreath/slowRec/cyclicSigh paced blocks are
% reconstructed from the SniffLogic playback recordings
% (G:\My Drive\cZelano\breathingDataFiles\<sessID><shadowFile>_recording.csv).
% Per block: align by normalized xcorr at 20 Hz (sign = polarity), pchip-
% upsample to 500 Hz, rescale to the session's free-breathing amplitude,
% overwrite ONLY the chosen rsp row over the block span (1-s edge blend),
% record provenance in outDat.reconstructedBlocks, resave (finals backed up
% to E:\reprocBackup_260824\recon\ first). Blocks with |r|<0.5 are left
% untouched and logged REVIEW.

L = labPaths();
BK = 'E:\reprocBackup_260824\recon';
if ~isfolder(BK), mkdir(BK); end
GD = fullfile(L.gdrive, 'cZelano', 'breathingDataFiles');
STEMS = {'slowBreath', 'slowRec', 'cyclicSigh'};

cfg = applyParams('breathingTask', 'main');
for si = 1:numel(cfg.sessionIDs)
    id = cfg.sessionIDs{si};
    fp = fullfile(cfg.root{si}, id, 'preProc', [id '_breathingPreproc.mat']);
    if ~exist(fp, 'file'), continue; end
    try
        % rerun-safe: if a pristine backup exists, restore it first (covers
        % re-reconstruction after an aligner change)
        bk0 = fullfile(BK, [id '_breathingPreproc.mat']);
        if exist(bk0, 'file'), copyfile(bk0, fp); end
        s = load(fp); fn = fieldnames(s); od = s.(fn{1}); clear s
        if ~isfield(od, 'behDat') || ~ismember('shadowFile', od.behDat.Properties.VariableNames), continue; end
        sfAll = unique(string(od.behDat.shadowFile));
        targets = sfAll(contains(sfAll, STEMS) & contains(sfAll, 'playback'));
        if isempty(targets), continue; end

        rspRows = find(cellfun(@(x) contains(x, 'rsp'), od.labels));
        rr = rspRows(od.rspIDX);
        rsp = double(od.data(rr, :)) .* od.rspFlip;   % work in inhale-positive space
        fs = od.fs; N = numel(rsp);

        % session amplitude reference: free-breathing blocks
        freeM = ismember(string(od.behDat.task), ["audio", "naturalFocus", "fastFocus"]);
        refIdx = [];
        if any(freeM)
            oR = od.behDat.finalOnset(freeM);
            refIdx = max(1, min(oR)) : min(N, max(oR));
        end
        if isempty(refIdx), refIdx = 1:N; end
        targIQR = iqr(rsp(refIdx));

        rec = struct('shadowFile', {}, 'srcFile', {}, 'i0', {}, 'i1', {}, ...
                     'lagSec', {}, 'r', {}, 'sgn', {}, 'scale', {}, 'status', {}, 'strategy', {});
        changed = false;
        for tt = 1:numel(targets)
            sf = char(targets(tt));
            m = strcmp(string(od.behDat.shadowFile), sf);
            o0 = min(od.behDat.finalOnset(m)); o1 = max(od.behDat.finalOnset(m));
            % expand to enclosing TTL block boundaries
            T = od.TTL(:)';
            lb = T(T <= o0); ub = T(T >= o1);
            if isempty(lb), i0 = max(1, o0 - 30*fs); else, i0 = max(1, lb(end)); end
            if isempty(ub), i1 = min(N, o1 + 30*fs); else, i1 = min(N, ub(1)); end
            csv = fullfile(GD, [id sf '_recording.csv']);
            if ~exist(csv, 'file'), csv = fullfile(GD, [id sf '_playback_recording.csv']); end
            R = struct('shadowFile', sf, 'srcFile', csv, 'i0', i0, 'i1', i1, ...
                       'lagSec', NaN, 'r', NaN, 'sgn', 0, 'scale', NaN, 'status', 'no-file', 'strategy', 'none');
            if ~exist(csv, 'file'), rec(end+1) = R; continue; end %#ok<*SAGROW>

            P = readmatrix(csv);
            tP = P(:, 1); vP = P(:, 2);
            ok = isfinite(tP) & isfinite(vP); tP = tP(ok); vP = vP(ok);
            [tP, iu] = unique(tP); vP = vP(iu);
            FSa = 20;
            % common 20-Hz grids, lowpassed <1 Hz
            tg = (tP(1):1/FSa:tP(end))';
            pL = lowpass(interp1(tP, vP, tg, 'linear') - mean(vP), 1, FSa);
            segR = rsp(i0:i1);
            tR = (0:numel(segR)-1)'/fs;
            tgr = (0:1/FSa:tR(end))';
            pR = lowpass(interp1(tR, double(segR)', tgr, 'linear') - mean(segR), 1, FSa);
            % --- filter-aware alignment (0.1-Hz acquisition high-pass makes
            % the RECORDED slow trace ~ the DERIVATIVE of the true one; a
            % sine correlates with its derivative at r~1 a QUARTER-CYCLE OFF,
            % so plain xcorr can look great at the wrong lag). Strategies:
            %   plain : pR vs pL           (fine for sharp cyclicSigh events)
            %   deriv : pR vs d/dt(pL)     (correct for high-passed slow)
            %   events: steep-rise delta trains, 0.5-s smoothed (shape-free)
            Np = max(numel(pR), numel(pL));
            zp = @(v) [v(:); zeros(Np - numel(v), 1)];
            dL = movmean([0; diff(pL(:))] * FSa, round(0.5 * FSa));
            evTrain = @(v) movmean(double(([0; diff(v(:))] * FSa) > prctile([0; diff(v(:))] * FSa, 85)), round(0.5 * FSa));
            cands = {zp(pR), zp(pL), 'plain'; zp(pR), zp(dL), 'deriv'; ...
                     zp(evTrain(pR)), zp(evTrain(pL)), 'events'; ...
                     zp(evTrain(-pR)), zp(evTrain(pL)), 'events-neg'};
            bestR = 0; bestLag = NaN; bestSgn = 0; bestStrat = 'none';
            for cc = 1:size(cands, 1)
                [xc, lg] = xcorr(cands{cc, 1}, cands{cc, 2}, 'normalized');
                [pkv, pii] = max(abs(xc));
                thr = 0.5; if contains(cands{cc, 3}, 'events'), thr = 0.35; end
                if pkv >= thr && pkv > bestR
                    bestR = pkv; bestLag = lg(pii) / FSa; bestStrat = cands{cc, 3};
                    if strcmp(cands{cc, 3}, 'events-neg'), bestSgn = -1;
                    elseif contains(cands{cc, 3}, 'events'), bestSgn = 1;
                    else, bestSgn = sign(xc(pii)); end
                end
            end
            R.r = bestR; R.sgn = bestSgn; R.lagSec = bestLag; R.strategy = bestStrat;
            if bestR == 0 || bestSgn == 0
                R.status = 'weak-alignment-SKIPPED-REVIEW'; rec(end+1) = R; continue;
            end
            % playback time -> block-local seconds: tBlock = tP - tP(1) + lagSec
            tBlk = (tP - tP(1)) + R.lagSec;
            vSig = (vP - median(vP)) * R.sgn;
            R.scale = targIQR / iqr(vSig);
            vSig = vSig * R.scale + median(double(segR));
            gridT = (0:(i1-i0))'/fs;
            ovl = gridT >= max(0, tBlk(1)) & gridT <= min(gridT(end), tBlk(end));
            newSeg = double(segR)';
            newSeg(ovl) = interp1(tBlk, vSig, gridT(ovl), 'pchip');
            % 1-s cosine blend at overlap edges
            eN = round(1 * fs); oi = find(ovl);
            if ~isempty(oi)
                for edge = 1:2
                    if edge == 1, ii = oi(1):min(oi(1)+eN-1, oi(end)); wgt = linspace(0,1,numel(ii))';
                    else, ii = max(oi(1), oi(end)-eN+1):oi(end); wgt = linspace(1,0,numel(ii))'; end
                    newSeg(ii) = wgt .* newSeg(ii) + (1-wgt) .* double(segR(ii))';
                end
            end
            rsp(i0:i1) = newSeg';
            R.status = 'reconstructed'; changed = true;
            rec(end+1) = R;
        end
        if changed
            bk = fullfile(BK, [id '_breathingPreproc.mat']);
            if ~exist(bk, 'file'), copyfile(fp, [bk '.tmp']); movefile([bk '.tmp'], bk, 'f'); end
            od.data(rr, :) = rsp .* od.rspFlip;      % back to stored polarity
            od.reconstructedBlocks = struct2table(rec);
            outDat = od; %#ok<NASGU>
            save(fp, 'outDat', '-v7.3');
        end
        for k = 1:numel(rec)
            fprintf('RECON %s %-28s r=%.2f sgn=%+d scale=%.3g [%s]\n', id, rec(k).shadowFile, rec(k).r, rec(k).sgn, rec(k).scale, rec(k).status);
        end
        clear od rsp
    catch ME
        fprintf('RECON FAIL %s: %s\n', id, ME.message);
    end
end
fprintf('reconstructPacedBlocks: DONE\n');

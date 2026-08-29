% qc5_hrvRepair - re-run the FIXED flagBadBreaths over every bm final
% (2026-08-29 review): repairs the goodBreath==0 HRV indexing bug (rrDat ->
% curRR) and gives never-evaluated edge-window breaths NaN instead of a
% silent 0. Touches ONLY behDat's goodBreath/maxRR/minRR/RR_max_min (+ the
% processedBehavior CSV re-export); segmentation and all other fields are
% untouched. Sessions without a usable RRint (or flagged ecgSkipped) keep
% their NaN HRV columns. sep finals re-apply the section-boundary
% goodBreath=0 rule after flagging. Recovery path if a save is interrupted:
% restore from E:\reprocBackup_260824\r12\<task>\ and re-run
% resegmentAll_zlp for that session (deterministic), then this repair.

TASKS = { ...
 'breathingTask',          '_breathing*.mat',                'i_processedBreathing.csv'; ...
 'emotionalMovieTask',     '_EmotionalMovieTask*.mat',       'i_EmotionalMovieTask_processedBreathing.csv'; ...
 'alternating6Blocks',     '_alternating6Blocks*.mat',       'i_alternating6Blocks_processedBreathing.csv'; ...
 'breathingTasks_separate','_breathingTasks_separate*.mat',  'i_breathingTasks_separate_processedBreathing.csv'};
L = labPaths();
nOK = 0; nNaNOnly = 0; nSkip = 0; nFail = 0;
for tt = 1:size(TASKS, 1)
    [tkey, glb, csvPat] = TASKS{tt, :};
    cfg = applyParams(tkey, 'main');
    for si = 1:numel(cfg.sessionIDs)
        id = cfg.sessionIDs{si};
        hits = dir(fullfile(cfg.root{si}, id, 'preProc', [id glb]));
        if isempty(hits), continue; end
        fpath = fullfile(hits(1).folder, hits(1).name);
        try
            S = load(fpath); vNames = fieldnames(S); vName = vNames{1};
            od = S.(vName); clear S
            if ~isfield(od, 'bmFeatures') || ~isfield(od, 'behDat')
                fprintf('HRVFIX SKIP %s %s: not a bm final\n', tkey, id);
                nSkip = nSkip + 1; clear od; continue;
            end
            hasRR = any(cellfun(@(x) contains(x, 'RRint'), od.labels));
            skipped = isfield(od, 'ecgSkipped') && od.ecgSkipped > 0;
            if hasRR && ~skipped
                od = flagBadBreaths(od);
                if strcmp(tkey, 'breathingTasks_separate') && isfield(od, 'sections')
                    for b = 1:height(od.sections)
                        edges = [od.sections.startSample(b), od.sections.endSample(b)];
                        for e = edges
                            near = abs(od.behDat.finalOnset - e) < 10 * od.fs;
                            od.behDat.goodBreath(near) = 0;
                        end
                    end
                end
                tag = 'flagged';
                nOK = nOK + 1;
            else
                n = height(od.behDat);
                od.behDat.goodBreath = nan(n, 1);
                od.behDat.maxRR      = nan(n, 1);
                od.behDat.minRR      = nan(n, 1);
                od.behDat.RR_max_min = nan(n, 1);
                tag = 'NaN (no usable ECG)';
                nNaNOnly = nNaNOnly + 1;
            end
            tmp = struct(); tmp.(vName) = od;
            save(fpath, '-struct', 'tmp', '-v7.3');
            w = whos('-file', fpath);
            assert(numel(w) == 1 && strcmp(w(1).name, vName) && w(1).bytes > 1e6, 'post-save verify failed');
            csvName = strrep(csvPat, 'i_', [id '_']);
            writetable(od.behDat, fullfile(L.procBehavior, csvName));
            gb = od.behDat.goodBreath;
            fprintf('HRVFIX OK %s %s: %s | good=%d bad=%d edgeNaN=%d\n', tkey, id, tag, ...
                sum(gb == 1), sum(gb == 0), sum(isnan(gb)));
            clear od tmp
        catch ME
            fprintf('HRVFIX FAIL %s %s: %s\n', tkey, id, ME.message);
            nFail = nFail + 1; clear od
        end
    end
end
fprintf('qc5_hrvRepair: DONE flagged=%d nanOnly=%d skip=%d fail=%d\n', nOK, nNaNOnly, nSkip, nFail);

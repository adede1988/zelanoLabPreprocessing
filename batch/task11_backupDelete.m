% task11_backupDelete — back up + remove EVERY breathMetrics final ahead of
% the engine-v3 full re-detection rerun (2026-08-26 QC review). Sweeps the
% full session list of all four breath-based tasks; sessions without a final
% are skipped. Deleting a final also deletes its same-named intermediate
% (case quirk) - the makeOutDats regenerate them; breathingTasks_separate has
% no intermediates. tmp+rename backups; delete only after the backup exists
% at matching size.

BK = 'E:\reprocBackup_260824\r10';

TASKS = { ...
 'breathingTask',           '_breathingPreproc.mat'; ...
 'emotionalMovieTask',      '_EmotionalMovieTaskpreproc.mat'; ...
 'alternating6Blocks',      '_alternating6Blockspreproc.mat'; ...
 'breathingTasks_separate', '_breathingTasks_separatepreproc.mat'};

nDel = 0; nSkip = 0;
for tt = 1:size(TASKS, 1)
    [tkey, sfx] = TASKS{tt, :};
    cfg = applyParams(tkey, 'main');
    bkDir = fullfile(BK, tkey);
    if ~isfolder(bkDir), mkdir(bkDir); end
    for si = 1:numel(cfg.sessionIDs)
        id = cfg.sessionIDs{si};
        f = fullfile(cfg.root{si}, id, 'preProc', [id sfx]);
        fd = dir(f);
        if isempty(fd), nSkip = nSkip + 1; continue; end
        % only breathMetrics finals are in scope: a final without bmFeatures
        % (old-format, deliberately preserved) is left alone
        try
            hasBM = ~isempty(who('-file', f, 'outDat')) || ~isempty(who('-file', f, 'chanDat')) || ~isempty(who('-file', f, 'out'));
            info = h5info(f);
            top = {info.Groups.Name};
            vn = strrep(top{1}, '/', '');
            bmOK = false;
            try, h5info(f, ['/' vn '/bmFeatures']); bmOK = true; catch, end
        catch
            bmOK = false;
        end
        if ~bmOK
            fprintf('LEAVE %-24s %s: no bmFeatures (old-format final, preserved)\n', tkey, id);
            nSkip = nSkip + 1;
            continue;
        end
        dest = fullfile(bkDir, [id sfx]);
        tmp  = [dest '.tmp'];
        copyfile(f, tmp);
        movefile(tmp, dest, 'f');
        dd = dir(dest);
        assert(~isempty(dd) && dd.bytes == fd.bytes, '%s: backup size mismatch', id);
        delete(f);
        assert(~exist(f, 'file'), '%s: delete failed', id);
        nDel = nDel + 1;
        fprintf('DEL %-24s %s (%.0f MB backed up)\n', tkey, id, fd.bytes / 1e6);
    end
end
fprintf('task11_backupDelete: DONE (%d removed, %d skipped/left)\n', nDel, nSkip);

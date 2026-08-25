% task3_backupDelete — back up and remove every applyParams-eligible breathing
% session's preProc file so the Task 3 rerun re-parses from raw (D13).
%
% The session list comes from applyParams('breathingTask','main') — exactly the
% sessions breathingTask_makeOutDat / breathingTaskPreProc_main will process.
% Every file is copied to E:\reprocBackup_260824\breathing\ and only deleted
% after the copy's size matches (an existing equal-size backup from an earlier
% attempt also qualifies — rerunnable). Nothing else on R: is touched.

BK = 'E:\reprocBackup_260824\breathing';
if ~isfolder(BK), mkdir(BK); end

cfg = applyParams('breathingTask', 'main');
nDel = 0; nSkip = 0;
for s = 1:numel(cfg.sessionIDs)
    id = cfg.sessionIDs{s};
    f  = fullfile(cfg.root{s}, id, 'preProc', [id '_breathingPreproc.mat']);
    fd = dir(f);
    if isempty(fd)
        nSkip = nSkip + 1;
        continue;
    end
    dest = fullfile(BK, [id '_breathingPreproc.mat']);
    tmp  = [dest '.tmp'];
    % Windows copyfile preallocates the destination to full size before the
    % data streams, so SIZE EQUALITY ALONE cannot prove a backup is complete
    % (a killed earlier copy can be full-size but garbage). Copy to .tmp and
    % rename: dest existing at all then proves the copy finished. Backups from
    % before this pattern (or any doubt) are re-verified by h5info readability.
    dd = dir(dest);
    if isempty(dd) || dd(1).bytes ~= fd(1).bytes || ~backupReadable(dest)
        copyfile(f, tmp);
        movefile(tmp, dest, 'f');
        dd = dir(dest);
    end
    assert(~isempty(dd) && dd(1).bytes == fd(1).bytes && backupReadable(dest), ...
        'task3_backupDelete:badBackup', ...
        'backup of %s failed verification after re-copy - aborting so the rerun cannot silently skip it', id);
    delete(f);
    assert(exist(f, 'file') ~= 2, 'task3_backupDelete:deleteFailed', ...
        'could not delete %s (locked?) - aborting', f);
    nDel = nDel + 1;
    fprintf('BACKED UP + REMOVED  %-26s (%d MB)\n', id, round(fd(1).bytes / 1e6));
end
fprintf('task3_backupDelete: DONE  removed=%d no-file=%d of %d sessions\n', ...
    nDel, nSkip, numel(cfg.sessionIDs));

function tf = backupReadable(p)
% structural readability check: the HDF5 metadata of a -v7.3 backup must open
    try
        h5info(p);
        tf = true;
    catch
        tf = false;
    end
end

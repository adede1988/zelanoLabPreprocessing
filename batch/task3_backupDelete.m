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
    dd = dir(dest);
    if isempty(dd) || dd(1).bytes ~= fd(1).bytes
        % no backup yet, or a partial copy from a killed earlier attempt:
        % (re)copy before considering deletion
        copyfile(f, dest);
        dd = dir(dest);
    end
    if ~isempty(dd) && dd(1).bytes == fd(1).bytes
        delete(f);
        nDel = nDel + 1;
        fprintf('BACKED UP + REMOVED  %-26s (%d MB)\n', id, round(fd(1).bytes / 1e6));
    else
        % a stale final left in place would make the rerun silently skip this
        % session as "Done" - fail loudly instead
        error('task3_backupDelete:copyFailed', ...
            'backup of %s does not match source after re-copy (src %d, backup %d bytes)', ...
            id, fd(1).bytes, dd(1).bytes);
    end
end
fprintf('task3_backupDelete: DONE  removed=%d no-file=%d of %d sessions\n', ...
    nDel, nSkip, numel(cfg.sessionIDs));

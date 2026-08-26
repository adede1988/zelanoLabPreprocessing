% task389_backupDelete — back up + remove the finals being rebuilt in the
% round-9 rerun (windowed-amplitude engine + corrected August polarity):
%   breathing (5): the segmentation-QC under-detectors VW, AB_2, JC, GA, GH
%   alternating6Blocks (8) + EmotionalMovieTask (7): every August session
%     (finals were built with rspFlip=-1; the cohort needs no flip)
% Deleting a final also deletes its same-named intermediate (Windows case
% quirk) - the makeOutDats regenerate them. tmp+rename backup pattern; a file
% is deleted only after its backup exists at matching size.

BK = 'E:\reprocBackup_260824\r9';

JOBS = { ...  % taskKey, final suffix glob-less name builder, ids
 'breathingTask', '_breathingPreproc.mat', {'251111_EEG_NWU_VW', '251002_Dupi_NMH_AB_2', ...
    '251008_EEG_NWU_JC', '251110_EEG_NWU_GA', '251113_EEG_NWU_GH'}; ...
 'alternating6Blocks', '_alternating6Blockspreproc.mat', {'260805_EEG_NWU_CA', ...
    '260806_EEG_NWU_JH', '260806_EEG_NWU_MM', '260807_EEG_NWU_GP', '260810_EEG_NWU_IS', ...
    '260810_EEG_NWU_AL', '260811_EEG_NWU_MS', '260811_EEG_NWU_HK'}; ...
 'emotionalMovieTask', '_EmotionalMovieTaskpreproc.mat', {'260806_EEG_NWU_JH', ...
    '260806_EEG_NWU_MM', '260807_EEG_NWU_GP', '260810_EEG_NWU_IS', '260810_EEG_NWU_AL', ...
    '260811_EEG_NWU_MS', '260811_EEG_NWU_HK'}};

for j = 1:size(JOBS, 1)
    [tkey, sfx, ids] = JOBS{j, :};
    cfg = applyParams(tkey, 'main');
    bkDir = fullfile(BK, tkey);
    if ~isfolder(bkDir), mkdir(bkDir); end
    for k = 1:numel(ids)
        id = ids{k};
        si = find(strcmp(cfg.sessionIDs, id), 1);
        assert(~isempty(si), '%s not in %s session list', id, tkey);
        f = fullfile(cfg.root{si}, id, 'preProc', [id sfx]);
        fd = dir(f);
        if isempty(fd)
            fprintf('%s %s: no final on R: (already removed?)\n', tkey, id);
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
        fprintf('%s %s: backed up + removed (%.0f MB)\n', tkey, id, fd.bytes / 1e6);
    end
end
fprintf('task389_backupDelete: DONE\n');

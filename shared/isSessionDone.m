function tf = isSessionDone(fpath, fields)
%ISSESSIONDONE  SHARED done-check: does a final exist and carry every sentinel field?
%
%   tf = isSessionDone(fpath, fields)
%
%   fpath   full path of the session's final .mat
%   fields  cellstr of fields the stored struct must have, e.g.
%           {'moreThan1', 'bmFeatures'} (a new-format breath-type final)
%
%   The file's single top-level variable is read whatever its name (outDat /
%   chanDat / out). False when the file does not exist or any field is
%   missing. Used by the pacedBreathing, EmotionalMovieTask,
%   alternating6Blocks and breathingTasks_separate mains.

    tf = false;
    if ~exist(fpath, 'file'), return; end
    chk = load(fpath);
    fn = fieldnames(chk);
    chk = chk.(fn{1});
    tf = all(isfield(chk, fields));
end

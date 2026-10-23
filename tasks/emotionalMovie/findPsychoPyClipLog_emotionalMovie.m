function [csvPath, where] = findPsychoPyClipLog_emotionalMovie(sessDir, sessID)
%FINDPSYCHOPYCLIPLOG_EMOTIONALMOVIE  The session's PsychoPy clip log of the movie task.
%
%   [csvPath, where] = findPsychoPyClipLog_emotionalMovie(sessDir, sessID)
%
%   sessDir  the session folder (<root>\<id>)
%   sessID   the session ID
%   csvPath  full path of <id>_emotionalMovieTask_<datetime>.csv, '' when the session has none
%   where    the folder the log was found in (relative to sessDir), '' when none
%
%   The log is the task's behavioral file (one row per clip: fileName, group, the DEVO2 norms,
%   photoDiode1.started, movie.started / movie.stopped; see matchClipsToPsychoPy). Folders, in order,
%   first one with a match wins:
%     behavioralData\                  every EEG-study session
%     BehaviorResults\emotionClips\    250225_OBE_NWU_AS_4 (June 2025, the 2025 OBE layout; that folder
%                                      also holds other participants' logs - only files named for this
%                                      session are taken)
%   Within a folder the largest file wins (an aborted start leaves a near-empty csv).
%   250904_OBE_NWU_TI_1 and 251009_OBE_NWU_CP_1 have no log anywhere on the server (checked 2026-10-22).

    folders = {'behavioralData', fullfile('BehaviorResults', 'emotionClips')};
    csvPath = ''; where = '';
    for k = 1:numel(folders)
        pp = dir(fullfile(sessDir, folders{k}, [sessID '_emotionalMovieTask_*.csv']));
        if ~isempty(pp)
            [~, ib] = max([pp.bytes]);
            csvPath = fullfile(pp(ib).folder, pp(ib).name);
            where = folders{k};
            return
        end
    end
end

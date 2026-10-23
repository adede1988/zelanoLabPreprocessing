function raw = assembleRaw_cueTask(S, stem)
%ASSEMBLERAW_CUETASK  TASK-SPECIFIC raw load for cueTask (and cueTask3).
%   raw = assembleRaw_cueTask(S)         loads <id>_cueTaskPreProc.mat
%   raw = assembleRaw_cueTask(S, stem)   loads <id>_<stem>PreProc.mat
%       (stem 'cueTask3': the three-sniff cue task, cueTask3PreProc_main)
%   Uses the shared loadIntermediateRaw and passes through the intermediate's
%   TTL table (+ the documentation fields below when present). Called by
%   cueTaskPreProc_main and cueTask3PreProc_main.

    if nargin < 2 || isempty(stem), stem = 'cueTask'; end
    matPath = fullfile(S.root, S.id, 'preProc', [S.id '_' stem 'PreProc.mat']);
    [raw, od] = loadIntermediateRaw(matPath);
    if isfield(od, 'TTL'), raw.TTL = od.TTL; end
    % rebuilt (surrogate) markers: the documentation travels with the TTLs
    if isfield(od, 'surrogateTTL'), raw.surrogateTTL = od.surrogateTTL; end
    % cueTask3: the event-channel parse record (parseEvents_cueTask3)
    if isfield(od, 'ttlInfo'), raw.ttlInfo = od.ttlInfo; end
end

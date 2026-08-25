% task78_writeGuesses — guess parameters for the EmotionalMovieTask and
% alternating6Blocks rows (Tasks_260824.md Tasks 7+8, D3/D4).
%
% Must run AFTER alternating6Blocks_makeOutDat: each EEG subject's rspFlip
% comes from the empirical log-alignment polarity stored in its intermediate
% (h5-read of /outDat/logAlign/rspFlip - CSC31-era polarity cannot be assumed
% from the CSC270-era curated majority).
%
% EEG subjects (8 alternating + 7 movie rows): EEG standard set (rspIDX=1,
% hasEEG=true, hasMacros=false, spikeClean=false, 20/11, beatSpec 1,0,gt,3.5,
% isNewStd=true) + the empirical rspFlip.
% Old OBEControl movie rows (AS_4, TI_1, CP_1): inherit rsp/spike settings
% from a curated row of the same session (D3.1), overridden where the old
% ZelanoLabScripts getSessionParams_emotionTask recorded better-informed
% values (TI: spikeThresh 50, beatSpec '1,0,lt,-2 & 2,1,gt,3 & 3,2,lt,0';
% CP_1: spikeThresh 15, spikeWin 7, macroRemove 6, beatSpec '3,0,lt,-3').
% Everything written with paramSource='guess'.

L = labPaths();
ROOT = L.rootEEG;

EEG_ALT   = {'260805_EEG_NWU_CA', '260806_EEG_NWU_JH', '260806_EEG_NWU_MM', ...
             '260807_EEG_NWU_GP', '260810_EEG_NWU_IS', '260810_EEG_NWU_AL', ...
             '260811_EEG_NWU_MS', '260811_EEG_NWU_HK'};
EEG_MOVIE = EEG_ALT(2:end);   % all but CA

flips = containers.Map();
for k = 1:numel(EEG_ALT)
    id = EEG_ALT{k};
    f = fullfile(ROOT, id, 'preProc', [id '_alternating6BlocksPreProc.mat']);
    try
        fl = h5read(f, '/outDat/logAlign/rspFlip');
        flips(id) = double(fl);
        fprintf('%s: empirical rspFlip = %+d\n', id, double(fl));
    catch ME
        warning('task78:noFlip', '%s: no alternating intermediate/logAlign (%s) - rows skipped this pass', ...
            id, ME.message);
    end
end

% beatSpec: the 2026-08 subjects' ECG lead 1 is INVERTED relative to the older
% EEG_breathing subjects (measured on JH movie ECGz: 2884 crossings below
% -3.5 sigma over 35 min = 82 bpm, vs 108 above +3.5), so R-peaks are detected
% on the negative side
base = struct('rspIDX', 1, 'hasEEG', true, 'hasMacros', false, ...
    'spikeClean', false, 'spikeThresh', 20, 'spikeWin', 11, ...
    'macroRemove', [], 'beatSpec', '1,0,lt,-3.5', 'isNewStd', true, ...
    'paramSource', 'guess');

for k = 1:numel(EEG_ALT)
    if ~isKey(flips, EEG_ALT{k}), continue; end
    P = base; P.task = 'alternating6Blocks'; P.rspFlip = flips(EEG_ALT{k});
    writeParams(P, EEG_ALT{k});
end
for k = 1:numel(EEG_MOVIE)
    if ~isKey(flips, EEG_MOVIE{k}), continue; end
    P = base; P.task = 'EmotionalMovieTask'; P.rspFlip = flips(EEG_MOVIE{k});
    writeParams(P, EEG_MOVIE{k});
end

% ---- old OBEControl movie rows (not run; D3.1 inherit + old-script values) ----
C = readcell(L.adminXlsx, 'Sheet', 'Sheet1');
hdr = C(2, :);
col = @(nm) find(cellfun(@(v) (ischar(v) || isstring(v)) && strcmpi(strtrim(char(string(v))), nm), hdr), 1);
cSub = col('Subject ID'); cPS = col('paramSource');
cIdx = col('rspIDX'); cFlip = col('rspFlip');

% hasEEG follows the old getSessionParams_emotionTask: AS_4 had NO EEG cap
OLD = { ...
 '250225_OBE_NWU_AS_4', struct('hasEEG', false, 'spikeClean', false, 'spikeThresh', 20, 'spikeWin', 11, 'macroRemove', [], 'beatSpec', '1,0,gt,3.5'); ...
 '250904_OBE_NWU_TI_1', struct('hasEEG', true, 'spikeClean', true, 'spikeThresh', 50, 'spikeWin', 11, 'macroRemove', [], 'beatSpec', '1,0,lt,-2 & 2,1,gt,3 & 3,2,lt,0'); ...
 '251009_OBE_NWU_CP_1', struct('hasEEG', true, 'spikeClean', true, 'spikeThresh', 15, 'spikeWin', 7, 'macroRemove', 6, 'beatSpec', '3,0,lt,-3')};
for k = 1:size(OLD, 1)
    id = OLD{k, 1};
    ov = OLD{k, 2};
    donor = 0;
    for r = 3:size(C, 1)
        v = C{r, cSub};
        if ~(ischar(v) || isstring(v)) || ~strcmpi(strtrim(char(string(v))), id), continue; end
        ps = C{r, cPS};
        if (ischar(ps) || isstring(ps)) && strcmpi(strtrim(char(string(ps))), 'curated')
            donor = r; break;
        end
    end
    P = struct('task', 'EmotionalMovieTask', 'paramSource', 'guess', ...
               'hasEEG', true, 'hasMacros', true, 'isNewStd', true);
    if donor > 0
        vi = C{donor, cIdx}; vf = C{donor, cFlip};
        if isnumeric(vi) && isscalar(vi) && isfinite(vi), P.rspIDX = double(vi); else, P.rspIDX = 1; end
        if isnumeric(vf) && isscalar(vf) && isfinite(vf), P.rspFlip = double(vf); else, P.rspFlip = 1; end
        fprintf('%s: inherited rspIDX=%d rspFlip=%+d from curated row %d\n', id, P.rspIDX, P.rspFlip, donor);
    else
        P.rspIDX = 1; P.rspFlip = 1;
        fprintf('%s: no curated donor row - defaults\n', id);
    end
    fn = fieldnames(ov);
    for f2 = 1:numel(fn), P.(fn{f2}) = ov.(fn{f2}); end
    writeParams(P, id);
end
fprintf('task78_writeGuesses: DONE\n');

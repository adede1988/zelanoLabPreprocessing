% qc9_rawVolumes - in-place backfill of inhaleVolumesRaw / exhaleVolumesRaw
% (2026-09-02 user request).
%
% The breathmetrics feature flow runs on the windowed-normalized detection
% trace, so its inhaleVolumes/exhaleVolumes are in normalization units that
% drift with local breathing depth. This pass adds raw-scale twins to every
% existing breathMetrics-family final WITHOUT re-detection: the volume
% integral (sum(abs(trace))/fs*1000, breathmetrics' own formula) is
% recomputed over the raw-unit trace (60-s moving-mean baseline removed,
% matching bmObj's amplitude convention) between the SAME stored
% inhale/exhale onset/offset landmark indices. Timing metrics untouched.
%
% Per session: backup -> compute -> bmFeatures.inhaleVolumesRaw/
% exhaleVolumesRaw + conditioning.rawVolumeSpec -> behDat
% bm_inhaleVolumesRaw/bm_exhaleVolumesRaw (bmObjBreathIdx alignment) ->
% in-place save (original variable name) -> processedBehavior CSV rewrite.
% Sep finals integrate on per-section baselines (their landmarks are
% absolute indices into the concatenated trace, but each section was
% segmented on its own local baseline).
%
% Env: ZLP_QC9_ONLY = comma list of ids or task|id (blank = all).
% Already-backfilled sessions (field + column present) are skipped -> resumable.

BKD = 'E:\reprocBackup_260824\rawVol';
TASKS = { ...
 'breathingTask',          '_breathing*.mat',                'i_processedBreathing.csv'; ...
 'emotionalMovieTask',     '_EmotionalMovieTask*.mat',       'i_EmotionalMovieTask_processedBreathing.csv'; ...
 'alternating6Blocks',     '_alternating6Blocks*.mat',       'i_alternating6Blocks_processedBreathing.csv'; ...
 'breathingTasks_separate','_breathingTasks_separate*.mat',  'i_breathingTasks_separate_processedBreathing.csv'};

L = labPaths();
onlyEnv = getenv('ZLP_QC9_ONLY');
onlyList = {};
if ~isempty(onlyEnv), onlyList = strtrim(strsplit(onlyEnv, ',')); end

nOK = 0; nSkip = 0; nFail = 0;
for tt = 1:size(TASKS, 1)
    [tkey, glb, csvPat] = TASKS{tt, :};
    cfg = applyParams(tkey, 'main');
    for si = 1:numel(cfg.sessionIDs)
        id = cfg.sessionIDs{si};
        if ~isempty(onlyList) && ~any(strcmp(onlyList, id)) && ...
                ~any(strcmp(onlyList, [tkey '|' id]))
            continue;
        end
        hits = dir(fullfile(cfg.root{si}, id, 'preProc', [id glb]));
        if strcmp(tkey, 'breathingTask')
            hits = hits(~contains(lower({hits.name}), 'separate'));
        end
        if isempty(hits), continue; end
        fpath = fullfile(hits(1).folder, hits(1).name);
        try
            S = load(fpath); vNames = fieldnames(S); vName = vNames{1};
            od = S.(vName); clear S
            if ~isfield(od, 'bmFeatures') || ~isfield(od, 'bmObj') || ~isfield(od, 'behDat')
                fprintf('RAWVOL SKIP %s %s: not a complete bm final\n', tkey, id);
                nSkip = nSkip + 1; clear od; continue;
            end
            F = od.bmFeatures;
            if isfield(F, 'inhaleVolumesRaw') && ...
                    ismember('bm_inhaleVolumesRaw', od.behDat.Properties.VariableNames)
                fprintf('RAWVOL SKIP %s %s: already backfilled\n', tkey, id);
                nSkip = nSkip + 1; clear od F; continue;
            end

            % ---- backup BEFORE any modification ----
            bdir = fullfile(BKD, tkey);
            if ~exist(bdir, 'dir'), mkdir(bdir); end
            bfile = fullfile(bdir, hits(1).name);
            if ~exist(bfile, 'file'), copyfile(fpath, bfile); end

            % ---- raw-scale trace (bmObj amplitude convention) ----
            if isstring(od.labels), od.labels = cellstr(od.labels); end
            isRsp = cellfun(@(x) contains(char(string(x)), 'rsp'), od.labels);
            r = double(od.data(isRsp, :));
            r = r(od.rspIDX, :) .* od.rspFlip;
            r = fillmissing(r, 'linear', 'EndValues', 'nearest');
            fs = od.fs; N = numel(r);
            respRaw = nan(1, N);
            if isfield(od, 'sections') && istable(od.sections)
                % sep: per-section baseline, matching the section-local engine runs
                for c = 1:height(od.sections)
                    a = od.sections.startSample(c); b = od.sections.endSample(c);
                    respRaw(a:b) = r(a:b) - movmean(r(a:b), round(60 * fs));
                end
                gap = isnan(respRaw);          % anything between sections
                respRaw(gap) = r(gap) - mean(r);
            else
                respRaw = r - movmean(r, round(60 * fs));
            end

            % ---- integrals over the stored landmarks ----
            vIn = volInteg(respRaw, fs, F.inhaleOnsets, F.inhaleOffsets, N);
            vEx = volInteg(respRaw, fs, F.exhaleOnsets, F.exhaleOffsets, N);
            F.inhaleVolumesRaw = vIn;
            F.exhaleVolumesRaw = vEx;
            spec = ['inhale/exhaleVolumesRaw = sum(abs(respRaw(onset:offset)))/fs*1000 ' ...
                'on the RAW-unit trace (60-s moving-mean baseline removed), same ' ...
                'landmarks as the windowed-normalized volumes; backfilled in place 2026-09-02'];
            if isfield(F, 'conditioning') && isstruct(F.conditioning)
                F.conditioning.rawVolumeSpec = spec;
            else
                F.rawVolumeSpec = spec;   % sep finals keep conditioningPerSection
            end
            od.bmFeatures = F;

            % ---- behDat columns (builder convention) ----
            colsDone = false;
            if isfield(F, 'bmObjBreathIdx')
                bi = F.bmObjBreathIdx(:);
                if numel(bi) == height(od.behDat) && ~isempty(bi) && max(bi) <= numel(vIn)
                    vc = vIn(:); od.behDat.bm_inhaleVolumesRaw = vc(bi);
                    vc = vEx(:); od.behDat.bm_exhaleVolumesRaw = vc(bi);
                    colsDone = true;
                end
            end
            if ~colsDone
                fprintf('RAWVOL WARN %s %s: bmObjBreathIdx misaligned - behDat columns skipped\n', tkey, id);
            end

            % ---- in-place save, original variable name + verify ----
            tmp = struct(); tmp.(vName) = od;
            save(fpath, '-struct', 'tmp', '-v7.3');
            w = whos('-file', fpath);
            assert(numel(w) == 1 && strcmp(w(1).name, vName) && w(1).bytes > 1e6, ...
                'post-save verify failed');

            % ---- processedBehavior CSV rewrite ----
            csvName = strrep(csvPat, 'i_', [id '_']);
            writetable(od.behDat, fullfile(L.procBehavior, csvName));

            % sanity: raw vs normalized volume correlation (finite pairs)
            cc = NaN;
            fin = isfinite(vIn(:)) & isfinite(F.inhaleVolumes(:));
            if sum(fin) > 10, cc = corr(vIn(fin)', F.inhaleVolumes(fin)'); end
            fprintf('RAWVOL OK %s %s: %d breaths, medianRawInVol=%.1f, corr(raw,norm)=%.2f, cols=%d\n', ...
                tkey, id, height(od.behDat), median(vIn, 'omitnan'), cc, colsDone);
            nOK = nOK + 1;
            clear od F tmp
        catch ME
            fprintf('RAWVOL FAIL %s %s: %s\n', tkey, id, ME.message);
            disp(getReport(ME, 'extended', 'hyperlinks', 'off'))
            nFail = nFail + 1;
        end
    end
end
fprintf('qc9_rawVolumes: DONE ok=%d skip=%d fail=%d\n', nOK, nSkip, nFail);

function v = volInteg(trace, fs, ons, offs, N)
% breathmetrics' findRespiratoryVolumes integral, NaN-safe, bounds-clamped
    n = numel(ons);
    v = nan(1, n);
    for k = 1:n
        if k <= numel(offs) && isfinite(ons(k)) && isfinite(offs(k))
            a = max(1, round(ons(k)));
            b = min(N, round(offs(k)));
            if b >= a, v(k) = sum(abs(trace(a:b))) / fs * 1000; end
        end
    end
end

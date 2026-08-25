% task2_probeChannels — scratch analysis before writing the Task 2 load scripts
%
% For each of the nine new EEG_breathing subjects (Tasks_260824.md Task 2):
%   - find the Neuralynx recording folder(s) and the per-channel recording
%     "suffixes" present ('' = first recording, '_0001', '_0002', ...) with
%     real data (>1 MB per channel file)
%   - for each recording: read candidate channels CSC31 / CSC270 (respiration
%     candidates), CSC269 (photodiode), CSC25 (ECG), CSC33 (EEG); report
%     fsample, duration, per-channel variance and 0.1-0.5 Hz fraction
%   - detect square pulses on the z-scored CSC269 and report their times
%     (combined JH/MM recordings should show pulses only in the last ~30 min;
%     movie recordings of split subjects should show pulses throughout)
%   - save a figure per recording: CSC269 overview + CSC31/CSC270 2-min zooms
%
% Output: E:\reprocBackup_260824\task2_probe\  (figures + task2_probe_results.mat)
% Read-only with respect to R: raw data.

SUBJ = {'260227_EEG_NWU_HW', '260805_EEG_NWU_CA', '260806_EEG_NWU_JH', ...
        '260806_EEG_NWU_MM', '260807_EEG_NWU_GP', '260810_EEG_NWU_IS', ...
        '260810_EEG_NWU_AL', '260811_EEG_NWU_MS', '260811_EEG_NWU_HK'};
OUTD = 'E:\reprocBackup_260824\task2_probe';
if ~isfolder(OUTD), mkdir(OUTD); end

L = labPaths();
if isfolder(L.fieldtrip)
    addpath(L.fieldtrip);
else
    addpath('E:\GitHub\fieldtrip-20230118');
end
ft_defaults

ROOT = L.rootEEG;
CAND = {'CSC31', 'CSC270', 'CSC269', 'CSC25', 'CSC33'};

results = struct('subj', {}, 'recDir', {}, 'suffix', {}, 'fs', {}, 'durMin', {}, ...
                 'chanStats', {}, 'pulseOnsetsSec', {}, 'note', {});

for si = 1:numel(SUBJ)
    id = SUBJ{si};
    base = fullfile(ROOT, id);
    fprintf('\n===== %s =====\n', id);

    % recording folders: datetime-named dirs directly in the subject folder
    % and/or inside AtlasData
    recDirs = {};
    for holder = {base, fullfile(base, 'AtlasData')}
        d = dir(holder{1});
        for k = 1:numel(d)
            if d(k).isdir && ~isempty(regexp(d(k).name, '^\d{4}-\d{2}-\d{2}_', 'once'))
                recDirs{end+1} = fullfile(holder{1}, d(k).name); %#ok<AGROW>
            end
        end
    end
    if isempty(recDirs)
        fprintf('  NO recording folder found\n');
        continue;
    end

    for r = 1:numel(recDirs)
        rd = recDirs{r};
        fprintf('  recording dir: %s\n', rd);

        % which suffixes carry real data? use CSC33 file sizes as the probe
        suffixes = {};
        d = dir(fullfile(rd, 'CSC33*.ncs'));
        for k = 1:numel(d)
            tok = regexp(d(k).name, '^CSC33(_\d+)?\.ncs$', 'tokens', 'once');
            if isempty(tok), continue; end
            sfx = tok{1};
            if d(k).bytes > 1e6
                suffixes{end+1} = sfx; %#ok<AGROW>
            end
        end
        fprintf('    data-carrying suffixes: {%s}\n', strjoin(cellfun(@(x) ['''' x ''''], suffixes, 'UniformOutput', false), ' '));

        for s = 1:numel(suffixes)
            sfx = suffixes{s};
            R = struct('subj', id, 'recDir', rd, 'suffix', sfx, 'fs', NaN, ...
                       'durMin', NaN, 'chanStats', struct(), 'pulseOnsetsSec', [], 'note', '');
            cs = struct();
            for c = 1:numel(CAND)
                f = fullfile(rd, [CAND{c} sfx '.ncs']);
                fd = dir(f);
                if isempty(fd) || fd(1).bytes < 1e6
                    continue;
                end
                cfg = []; cfg.dataset = f;
                try
                    dat = ft_preprocessing(cfg);
                catch ME
                    fprintf('    %s%s: LOAD FAILED %s\n', CAND{c}, sfx, ME.message);
                    continue;
                end
                x = dat.trial{1};
                fs = dat.fsample;
                R.fs = fs;
                R.durMin = numel(x) / fs / 60;
                st = struct();
                st.std = std(x);
                % fraction of power in the respiration band (0.1-0.5 Hz),
                % computed on a decimated copy
                dec = max(1, floor(fs / 20));
                xd = x(1:dec:end); fsd = fs / dec;
                xd = xd - mean(xd);
                if numel(xd) > 4096
                    [pxx, fq] = pwelch(xd, hamming(4096), 2048, 4096, fsd);
                    st.respBandFrac = sum(pxx(fq >= 0.1 & fq <= 0.5)) / sum(pxx(fq <= 5));
                else
                    st.respBandFrac = NaN;
                end
                cs.(CAND{c}) = st;
                fprintf('    %s%s: fs=%d dur=%.1f min  std=%.3g respFrac=%.2f\n', ...
                    CAND{c}, sfx, fs, R.durMin, st.std, st.respBandFrac);

                if strcmp(CAND{c}, 'CSC269')
                    z = (x - mean(x)) / std(x);
                    % square pulses: threshold crossings of |z| > 3 with
                    % 0.5 s refractory
                    hits = find(abs(z) > 3);
                    if ~isempty(hits)
                        keep = [true, diff(hits) > 0.5 * fs];
                        R.pulseOnsetsSec = hits(keep) / fs;
                    end
                    fprintf('      CSC269 pulses: %d  first=%.1f s  last=%.1f s\n', ...
                        numel(R.pulseOnsetsSec), ...
                        min([R.pulseOnsetsSec inf]), max([R.pulseOnsetsSec -inf]));

                    fig = figure('Visible', 'off', 'Position', [40 40 1500 800]);
                    subplot(3, 1, 1);
                    di = 1:dec:numel(x);
                    plot(di / fs / 60, z(1:dec:end), 'k');
                    title(sprintf('%s %s CSC269 z-scored (min)', strrep(id, '_', '\_'), sfx), 'Interpreter', 'tex');
                    fpath2 = fullfile(rd, ['CSC31' sfx '.ncs']);
                    fd2 = dir(fpath2);
                    if ~isempty(fd2) && fd2(1).bytes > 1e6
                        cfg2 = []; cfg2.dataset = fpath2;
                        d2 = ft_preprocessing(cfg2);
                        w = 1:min(numel(d2.trial{1}), round(120 * d2.fsample));
                        subplot(3, 1, 2); plot(w / d2.fsample, d2.trial{1}(w)); title('CSC31 first 2 min');
                    end
                    fpath3 = fullfile(rd, ['CSC270' sfx '.ncs']);
                    fd3 = dir(fpath3);
                    if ~isempty(fd3) && fd3(1).bytes > 1e6
                        cfg3 = []; cfg3.dataset = fpath3;
                        d3 = ft_preprocessing(cfg3);
                        w = 1:min(numel(d3.trial{1}), round(120 * d3.fsample));
                        subplot(3, 1, 3); plot(w / d3.fsample, d3.trial{1}(w)); title('CSC270 first 2 min');
                    end
                    sfxTag = strrep(sfx, '_', '');
                    saveas(fig, fullfile(OUTD, sprintf('probe_%s_%s.png', id, sfxTag)));
                    close(fig);
                end
                clear dat x z
            end
            R.chanStats = cs;
            results(end+1) = R; %#ok<SAGROW>
        end
    end
end

save(fullfile(OUTD, 'task2_probe_results.mat'), 'results');
fprintf('\ntask2_probeChannels: DONE (%d recordings probed)\n', numel(results));

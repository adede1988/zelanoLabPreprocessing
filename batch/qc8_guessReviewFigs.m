% qc8_guessReviewFigs - per-session review material for EVERY paramSource=guess
% row (2026-09-01 user request: guessReview.html).
%
% For each guess task-session with a final on disk this script:
%   * loads the final (full struct, one at a time)
%   * breathing-family tasks (breathingTask / EmotionalMovieTask /
%     alternating6Blocks / breathingTasks_separate): renders
%       <id>_qc8_ecg.png      3 x 30 s ECG (buildECGz channels) + stored
%                             heartBeats overlaid
%       <id>_qc8_rsp.png      3 x 30 s respiration + bmObj onset/peak/trough
%       <id>_qc8_macroRaw.png 2 x 30 s raw macro channels (if recorded)
%       <id>_qc8_macroBP.png  2 x 30 s bipolar macBP channels (if present)
%     and lists the conditions in the final's behDat.
%   * sniff-family tasks (cueTask / threshTask / O15): renders the two macro
%     figures only (sniff + blink figures already exist as pipeline JPGs).
%   * 260326_OBE_NWU_AD_2 breathingTask: extra full-session event-channel
%     figure with pulse-group detection + known block annotation
%     (<id>_qc8_ad2events.png).
%   * harvests the standard pipeline JPGs/PNGs from the session figure folder
%     (task subfolder first, then session-root breathing-family names),
%     recompressing JPGs > 400 KB.
%   * writes info.json (flags: blink removal, spike removal, macroRemove,
%     sheet params, conditions, beat counts, notes).
%
% Output tree: E:\reprocBackup_260824\guessReview\figs\<task>\<id>\
% Env: ZLP_QC8_ONLY = comma list of session ids (blank = all guess rows).

L = labPaths();
OUT = 'E:\reprocBackup_260824\guessReview\figs';
if ~isfolder(OUT), mkdir(OUT); end

onlyEnv = getenv('ZLP_QC8_ONLY');
onlyList = {};
if ~isempty(onlyEnv), onlyList = strtrim(strsplit(onlyEnv, ',')); end

% task key | breathing-family | final glob | fig-folder aliases
TASKS = { ...
 'breathingTask',           true,  '*breathingPre*.mat',            {'breathingTask', 'breathing'}; ...
 'cueTask',                 false, '*cueTask*.mat',                 {'cueTask'}; ...
 'threshTask',              false, '*threshold*preproc*.mat',      {'threshTask'}; ...
 'O15',                     false, '*O15*preproc*.mat',             {'O15'}; ...
 'EmotionalMovieTask',      true,  '*EmotionalMovieTask*.mat',      {'EmotionalMovieTask', 'emotionalMovieTask'}; ...
 'alternating6Blocks',      true,  '*alternating6Blocks*.mat',      {'alternating6Blocks'}; ...
 'breathingTasks_separate', true,  '*breathingTasks_separate*.mat', {'breathingTasks_separate'}};

for tt = 1:size(TASKS, 1)
    [tkey, isBreathFam, finPat, figAliases] = TASKS{tt, :};
    cfg = applyParams(tkey, 'main');
    for si = 1:numel(cfg.sessionIDs)
        id = cfg.sessionIDs{si};
        ps = cfg.paramSource{si};
        if isnumeric(ps), ps = ''; end
        ps = lower(strtrim(char(string(ps))));
        if ~strcmp(ps, 'guess'), continue; end
        if ~isempty(onlyList) && ~any(strcmp(onlyList, id)), continue; end

        outDir = fullfile(OUT, tkey, id);
        if ~isfolder(outDir), mkdir(outDir); end
        info = struct('sessID', id, 'task', tkey, 'paramSource', ps, ...
            'status', 'ok', 'notes', {{}});
        fprintf('QC8 %s | %s : start\n', tkey, id);
        try
            % ---------------- sheet params ----------------
            try
                P = applyParams(tkey, id);
                for pf = {'type', 'hasEEG', 'spikeClean', 'macroRemove', ...
                          'rspIDX', 'rspFlip', 'beatSpec', 'hasMacros', ...
                          'respThresh', 'cuedBackBuff', 'adjWin'}
                    if isfield(P, pf{1}), info.(['sheet_' pf{1}]) = P.(pf{1}); end
                end
            catch ME2
                info.notes{end+1} = ['applyParams failed: ' ME2.message];
            end

            % ---------------- locate + load final ----------------
            sroot = fullfile(cfg.root{si}, id);
            hitsF = dir(fullfile(sroot, 'preProc', finPat));
            hitsF = hitsF(~contains({hitsF.name}, 'condLabels'));
            if strcmp(tkey, 'breathingTask')
                hitsF = hitsF(~contains(lower({hitsF.name}), 'separate'));
            end
            if isempty(hitsF)
                info.status = 'NO FINAL ON DISK';
                writeInfo(outDir, info);
                fprintf('QC8 %s | %s : NO FINAL\n', tkey, id);
                continue;
            end
            fpath = fullfile(hitsF(1).folder, hitsF(1).name);
            info.finalFile = hitsF(1).name;
            Sld = load(fpath);
            fn = fieldnames(Sld);
            od = Sld.(fn{1});
            clear Sld

            if ~isfield(od, 'moreThan1')
                info.status = 'INCOMPLETE final (no moreThan1) - intermediate only';
            end
            fs = od.fs; nS = size(od.data, 2);
            info.fs = fs; info.durMin = round(nS / fs / 60, 1);
            if isstring(od.labels), od.labels = cellstr(od.labels); end
            labs = cellfun(@(x) char(string(x)), od.labels, 'UniformOutput', false);

            % ---------------- flags from the final ----------------
            if isfield(od, 'blinkRemoval')
                info.blinkRemoval = od.blinkRemoval;
                if ~od.blinkRemoval
                    info.notes{end+1} = 'FLAG: NO blink removal ran for this session';
                end
            else
                info.blinkRemoval = -1;
                info.notes{end+1} = 'FLAG: no blinkRemoval field (no EEG preprocessing ran)';
            end
            if isfield(od, 'badChans') && ~isempty(od.badChans)
                info.badChans = cellfun(@(x) char(string(x)), od.badChans, 'UniformOutput', false);
            end
            iMacro = find(cellfun(@(x) contains(x, 'macro'), labs));
            iBP    = find(cellfun(@(x) contains(x, 'macBP'), labs));
            iSCV   = find(strcmp(labs, 'spikeCleanVec'));
            info.nMacro = numel(iMacro); info.nMacBP = numel(iBP);
            if isempty(iMacro)
                info.notes{end+1} = 'no macro channels recorded';
            end
            if ~isempty(iSCV)
                scv = od.data(iSCV(1), :);
                nCleaned = sum(scv ~= 1);
                info.spikeCleanRan = 1;
                info.spikeSamplesAltered = nCleaned;
                if nCleaned == 0
                    info.notes{end+1} = 'spikeCleanVec all-ones: spike clean ran but removed nothing';
                else
                    info.notes{end+1} = sprintf('spike clean altered %d samples (%.2f%% of recording)', ...
                        nCleaned, 100 * nCleaned / nS);
                end
            else
                info.spikeCleanRan = 0;
                if ~isempty(iBP)
                    info.notes{end+1} = 'FLAG: macros bipolar-referenced but NO spikeCleanVec stored';
                end
            end

            % ---------------- window helpers ----------------
            win = round(30 * fs);
            clampWin = @(c) max(1, min(nS - win + 1, round(c - win / 2)));

            % ---------------- breathing-family figures ----------------
            if isBreathFam && isfield(od, 'moreThan1')
                % ECG + beats
                try
                    hb = [];
                    if isfield(od, 'heartBeats'), hb = od.heartBeats(:)'; end
                    hasECG = any(cellfun(@(x) contains(x, 'ECG'), labs));
                    if hasECG
                        ECGz = buildECGz(od);
                        info.nBeats = numel(hb);
                        if ~isempty(hb)
                            info.bpm = round(numel(hb) / (nS / fs / 60), 1);
                            cts = round(quantile(hb, [0.2 0.5 0.8]));
                        else
                            info.notes{end+1} = 'FLAG: no stored heartbeats (empty heartBeats)';
                            cts = round(nS .* [0.2 0.5 0.8]);
                        end
                        fig = figure('Visible', 'off', 'Position', [0 0 1500 850]);
                        cols = {'k', 'red', 'green'};
                        for w = 1:3
                            s0 = clampWin(cts(w)); s1 = s0 + win - 1;
                            subplot(3, 1, w); hold on
                            for ci = 1:min(3, size(ECGz, 1))
                                plot((s0:s1) / fs, ECGz(ci, s0:s1), 'color', cols{ci});
                            end
                            bIn = hb(hb >= s0 & hb <= s1);
                            if ~isempty(bIn), xline(bIn / fs, 'm--'); end
                            xlim([s0 s1] / fs); ylabel('z'); xlabel('time (s)');
                            title(sprintf('%s ECG window %d/3 (%d beats in window)', id, w, numel(bIn)), 'Interpreter', 'none');
                        end
                        saveas(fig, fullfile(outDir, [id '_qc8_ecg.png'])); close(fig);
                    else
                        info.notes{end+1} = 'no ECG channels in final';
                    end
                catch ME2
                    info.notes{end+1} = ['ECG figure failed: ' ME2.message];
                end

                % respiration + bmObj markers
                try
                    iRsp = find(cellfun(@(x) contains(x, 'rsp'), labs));
                    ri = 1; rf = 1;
                    if isfield(od, 'rspIDX'), ri = od.rspIDX; end
                    if isfield(od, 'rspFlip'), rf = od.rspFlip; end
                    rsp = od.data(iRsp(min(ri, numel(iRsp))), :) .* rf;
                    bm = od.bmObj;
                    onT = bm(:, 2); pkT = bm(:, 4); trT = bm(:, 11);
                    cts = round(quantile(onT, [0.2 0.5 0.8]) * fs);
                    fig = figure('Visible', 'off', 'Position', [0 0 1500 850]);
                    for w = 1:3
                        s0 = clampWin(cts(w)); s1 = s0 + win - 1;
                        tw = (s0:s1) / fs;
                        subplot(3, 1, w); hold on
                        plot(tw, rsp(s0:s1), 'k');
                        oIn = onT(onT >= tw(1) & onT <= tw(end));
                        pIn = pkT(pkT >= tw(1) & pkT <= tw(end));
                        eIn = trT(trT >= tw(1) & trT <= tw(end));
                        yv = @(tv) interp1(tw, rsp(s0:s1), tv);
                        if ~isempty(oIn), plot(oIn, yv(oIn), 'g^', 'MarkerFaceColor', 'g', 'MarkerSize', 7); end
                        if ~isempty(pIn), plot(pIn, yv(pIn), 'rv', 'MarkerFaceColor', 'r', 'MarkerSize', 7); end
                        if ~isempty(eIn), plot(eIn, yv(eIn), 'bo', 'MarkerFaceColor', 'b', 'MarkerSize', 6); end
                        xlim([tw(1) tw(end)]); xlabel('time (s)');
                        title(sprintf('%s respiration window %d/3 (green=onset red=peak blue=trough; %d breaths total)', ...
                            id, w, size(bm, 1)), 'Interpreter', 'none');
                    end
                    saveas(fig, fullfile(outDir, [id '_qc8_rsp.png'])); close(fig);
                    info.nBreaths = size(bm, 1);
                catch ME2
                    info.notes{end+1} = ['rsp figure failed: ' ME2.message];
                end

                % conditions in the final
                try
                    bd = od.behDat;
                    conds = unique(bd.condition(:)');
                    cl = {};
                    for c = conds
                        idxc = bd.condition == c;
                        lbl = '';
                        for cc = {'task', 'noseMouth', 'shadowFile'}
                            if ismember(cc{1}, bd.Properties.VariableNames)
                                v = bd.(cc{1})(idxc);
                                v = char(string(v(1)));
                                lbl = [lbl ' ' cc{1} '=' v]; %#ok<AGROW>
                            end
                        end
                        cl{end+1} = sprintf('condition %d: %d breaths%s', c, sum(idxc), lbl); %#ok<AGROW>
                    end
                    info.conditions = cl;
                catch ME2
                    info.notes{end+1} = ['condition list failed: ' ME2.message];
                end
            end

            % ---------------- macro figures (all tasks) ----------------
            try
                if ~isempty(iMacro)
                    plotChanWins(od, iMacro, labs, fs, nS, win, 2, ...
                        fullfile(outDir, [id '_qc8_macroRaw.png']), [id ' raw macro']);
                end
                if ~isempty(iBP)
                    plotChanWins(od, iBP, labs, fs, nS, win, 2, ...
                        fullfile(outDir, [id '_qc8_macroBP.png']), [id ' bipolar macBP']);
                end
            catch ME2
                info.notes{end+1} = ['macro figures failed: ' ME2.message];
            end

            % ---------------- sniff-family context ----------------
            if ~isBreathFam && isfield(od, 'behDat')
                try
                    info.nTrials = height(od.behDat);
                    if ismember('type', od.behDat.Properties.VariableNames)
                        tv = string(od.behDat.type);
                        ut = unique(tv);
                        info.trialTypes = arrayfun(@(u) sprintf('%s=%d', u, sum(tv == u)), ut, 'UniformOutput', false);
                    end
                catch ME2
                    info.notes{end+1} = ['behDat summary failed: ' ME2.message];
                end
            end

            % ---------------- AD_2 special: event-channel block audit ----------------
            if strcmp(id, '260326_OBE_NWU_AD_2') && strcmp(tkey, 'breathingTask')
                try
                    info = ad2EventFigure(od, labs, fs, nS, outDir, id, info);
                catch ME2
                    info.notes{end+1} = ['AD_2 event figure failed: ' ME2.message];
                end
            end

            % ---------------- harvest existing pipeline figures ----------------
            try
                base = fullfile(L.figPath, id);
                copied = {};
                for a = 1:numel(figAliases)
                    d = fullfile(base, figAliases{a});
                    if isfolder(d)
                        copied = harvestDir(d, outDir, copied);
                    end
                end
                if isBreathFam
                    % legacy/paramCheck figures at session root (breathing-family names)
                    pats = {'*paramCheck*', 'RespirationHeart*', 'ECG_beatDetect*', ...
                        'interbeatHist*', 'breathLengths*', 'HeartByBreathLengths*', ...
                        'shadowResp*', 'removedBlink*', 'blinkAmbiguous*', ...
                        'macrosRaw*', 'macroSpikeRemoval*', '*logAlign*', '*movieClipTTLs*'};
                    for p = 1:numel(pats)
                        hits = dir(fullfile(base, pats{p}));
                        hits = hits(~[hits.isdir]);
                        for h = 1:numel(hits)
                            if ~any(strcmp(copied, hits(h).name))
                                copyfile(fullfile(hits(h).folder, hits(h).name), ...
                                    fullfile(outDir, hits(h).name));
                                copied{end+1} = hits(h).name; %#ok<AGROW>
                            end
                        end
                    end
                end
                info.nHarvested = numel(copied);
                recompressDir(outDir);
            catch ME2
                info.notes{end+1} = ['figure harvest failed: ' ME2.message];
            end

            writeInfo(outDir, info);
            fprintf('QC8 %s | %s : done (%s)\n', tkey, id, info.status);
        catch ME
            info.status = ['FAILED: ' ME.message];
            try writeInfo(outDir, info); catch, end
            fprintf('QC8 %s | %s : FAIL %s\n', tkey, id, ME.message);
            disp(getReport(ME, 'extended', 'hyperlinks', 'off'))
        end
        clear od
        close all
    end
end
disp('qc8_guessReviewFigs: DONE')

% ======================= helpers =======================

function plotChanWins(od, rows, labs, fs, nS, win, nWin, outPath, ttl)
    cts = round(nS .* linspace(0.3, 0.7, nWin));
    nCh = min(8, numel(rows));
    fig = figure('Visible', 'off', 'Position', [0 0 1500 300 * nWin + 150]);
    for w = 1:nWin
        s0 = max(1, min(nS - win + 1, round(cts(w) - win / 2))); s1 = s0 + win - 1;
        subplot(nWin, 1, w); hold on
        for k = 1:nCh
            x = od.data(rows(k), s0:s1);
            x = (x - mean(x)) / max(std(x), eps);
            plot((s0:s1) / fs, x + (k - 1) * 5, 'LineWidth', 0.5);
        end
        yticks((0:nCh-1) * 5);
        yticklabels(cellfun(@(x) strrep(char(string(x)), '_', '\_'), labs(rows(1:nCh)), 'UniformOutput', false));
        xlim([s0 s1] / fs); xlabel('time (s)');
        extra = '';
        if numel(rows) > nCh, extra = sprintf(' (first %d of %d ch)', nCh, numel(rows)); end
        title(sprintf('%s window %d/%d%s', ttl, w, nWin, extra), 'Interpreter', 'none');
    end
    saveas(fig, outPath); close(fig);
end

function info = ad2EventFigure(od, labs, fs, nS, outDir, id, info)
    iEv = find(cellfun(@(x) contains(x, 'event'), labs), 1);
    if isempty(iEv)
        info.notes{end+1} = 'AD_2: no event channel in final';
        return;
    end
    z = od.data(iEv, :);
    z = (z - mean(z)) / std(z);
    t = (1:nS) / fs;
    % downward photodiode pulses (same convention as the makeOutDats)
    lo = z < -1.5;
    d = diff([0 lo 0]);
    ps = find(d == 1); pe = find(d == -1) - 1;
    keep = (pe - ps) >= round(0.05 * fs);          % ignore < 50 ms glitches
    ps = ps(keep); pe = pe(keep);
    pulseT = (ps + pe) / 2 / fs;
    % group pulses separated by > 20 s into distinct TTL events/trains
    groups = zeros(0, 3);                          % [tStart tEnd nPulses]
    if ~isempty(pulseT)
        gb = [0 find(diff(pulseT) > 20) numel(pulseT)];
        for k = 1:numel(gb) - 1
            seg = pulseT(gb(k) + 1 : gb(k + 1));
            groups(end + 1, :) = [seg(1), seg(end), numel(seg)]; %#ok<AGROW>
        end
    end
    info.ad2_nPulses = numel(pulseT);
    info.ad2_nPulseGroups = size(groups, 1);
    info.ad2_groups = arrayfun(@(k) sprintf('group %d: %.1f-%.1f s (%d pulses)', ...
        k, groups(k, 1), groups(k, 2), groups(k, 3)), 1:size(groups, 1), 'UniformOutput', false);

    fig = figure('Visible', 'off', 'Position', [0 0 1600 500]);
    hold on
    dec = 10;
    plot(t(1:dec:end), z(1:dec:end), 'k');
    yl = [min(z) max(z)];
    % pulse groups
    for k = 1:size(groups, 1)
        patch([groups(k, 1) groups(k, 2) + 1 groups(k, 2) + 1 groups(k, 1)], ...
              [yl(1) yl(1) yl(2) yl(2)], [1 0.6 0.2], 'FaceAlpha', 0.25, 'EdgeColor', 'none');
    end
    % known block: audio, measured window start 30 s (300 s block)
    patch([30 330 330 30], [yl(1) yl(1) yl(2) yl(2)], [0.2 0.8 0.2], ...
        'FaceAlpha', 0.15, 'EdgeColor', 'none');
    text(180, yl(2) * 0.9, 'audio block (measured, 30-330 s)', ...
        'HorizontalAlignment', 'center', 'Color', [0 0.4 0]);
    % stored TTL boundaries
    if isfield(od, 'TTL') && isnumeric(od.TTL) && ~isempty(od.TTL)
        xline(od.TTL(:) / fs, 'b-', 'LineWidth', 1.5);
        info.ad2_TTLstored = od.TTL(:)' / fs;
    end
    xlabel('time (s)'); ylabel('event channel (z)');
    title(sprintf('%s event channel: %d pulse group(s) / %d pulses detected; orange = pulse groups, green = known audio block, blue = stored TTL', ...
        id, size(groups, 1), numel(pulseT)), 'Interpreter', 'none');
    xlim([0 t(end)]);
    saveas(fig, fullfile(outDir, [id '_qc8_ad2events.png'])); close(fig);
end

function copied = harvestDir(srcDir, outDir, copied)
    hits = [dir(fullfile(srcDir, '*.jpg')); dir(fullfile(srcDir, '*.png'))];
    for h = 1:numel(hits)
        copyfile(fullfile(hits(h).folder, hits(h).name), fullfile(outDir, hits(h).name));
        copied{end+1} = hits(h).name; %#ok<AGROW>
    end
end

function recompressDir(outDir)
% keep the repo payload sane: re-encode any JPG over 400 KB at quality 70,
% capping width at 1600 px. PNGs are left alone (line art compresses well).
    hits = dir(fullfile(outDir, '*.jpg'));
    for h = 1:numel(hits)
        if hits(h).bytes <= 400 * 1024, continue; end
        fp = fullfile(hits(h).folder, hits(h).name);
        try
            img = imread(fp);
            if size(img, 2) > 1600
                img = imresize(img, 1600 / size(img, 2));
            end
            imwrite(img, fp, 'Quality', 70);
        catch
        end
    end
end

function writeInfo(outDir, info)
    try
        txt = jsonencode(info, 'PrettyPrint', true);
    catch
        txt = jsonencode(info);   % PrettyPrint needs R2021a+
    end
    fid = fopen(fullfile(outDir, 'info.json'), 'w');
    fwrite(fid, txt); fclose(fid);
end

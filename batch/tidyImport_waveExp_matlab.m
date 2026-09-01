% tidyImport_waveExp_matlab - MATLAB port of experiment_EEGsync's
% tidyDataImport_waveExp.R (2026-08-31; R is not installed on the lab
% machine). Converts a session's raw psychopy
% <id>_mindfulBreathing_<date>.csv (G:\My Drive\cZelano\breathingDataFiles)
% into the processedBehavior\<id>.csv the breathing makeOutDat consumes.
%
% Faithful to the R script's logic: cndCount = #question=='relaxed' rating
% sets; 12 questions per set; order 0 = pre (slider.response), order 1 =
% audio (slider_4 if present else slider_2; onsets from audioRecording),
% orders 2..cndCount-1 = blocks, named via the oldNames->canonical map,
% onsets from focusedBreathing (sequential), playBackNormal, or
% verticalLine; shadowFile = outFile; wave stats for the wave-machine
% blocks; ratings slider_2 (fallback slider_3); warp = warpRatio.
% Output columns and 'NA' text conventions mirror R's write.csv so
% downstream readtable sees the same behDat.
%
% Env: ZLP_TIDY_IDS = comma-separated session ids (required).

datFolder = 'G:\My Drive\cZelano\breathingDataFiles';
outFolder = 'E:\GitHub\experiment_EEGsync\processedBehavior';
ids = strtrim(strsplit(getenv('ZLP_TIDY_IDS'), ','));
assert(~isempty(ids) && ~isempty(ids{1}), 'set ZLP_TIDY_IDS');

qShort = containers.Map( ...
 {'calm','tense','upset','relaxed','content','worried', ...
  'pleasant and unpleasant thoughts','emotions come and go', ...
  'to see the patterns of my thinking','present in my body', ...
  'the quality of my breathing','the sensations of my breathing'}, ...
 {'calm','tense','upset','relaxed','content','worried', ...
  'pl_up_thoughts','emo_come_go','thtPat','bodyPresent','breathQual','breathSense'});
oldRaw = {'slow','fast','natural', ...
          'fastRec1_playback','fastRec2_playback','fastRec3_playback', ...
          'natRec1_playback','natRec2_playback','natRec3_playback', ...
          'slowRec1_playback','slowRec2_playback','slowRec3_playback', ...
          'noRhythm','slowFocus','slowResp','fastFocus','cyclicSigh', ...
          'naturalFocus','slowPlayback', ...
          'slowBreath1_playback','slowBreath2_playback','slowBreath3_playback', ...
          'cyclicSigh1_playback','cyclicSigh2_playback','cyclicSigh3_playback'};
oldCanon = {'slowFocus','fastFocus','ownSpeedFocus', ...
            'fastPlayback','fastPlayback','fastPlayback', ...
            'natPlayback','natPlayback','natPlayback', ...
            'slowPlayback','slowPlayback','slowPlayback', ...
            'naturalFocus','slowFocus','slowResp','fastFocus','cyclicSigh', ...
            'naturalFocus','slowPlayback', ...
            'slowResp','slowResp','slowResp', ...
            'cyclicSigh','cyclicSigh','cyclicSigh'};

for ii = 1:numel(ids)
    id = ids{ii};
    try
        cand = dir(fullfile(datFolder, [id '_mindfulBreathing_*.csv']));
        assert(~isempty(cand), '%s: no mindfulBreathing csv', id);
        [~, big] = max([cand.bytes]);          % skip 0-KB false starts
        src = fullfile(cand(big).folder, cand(big).name);
        opts = detectImportOptions(src, 'VariableNamingRule', 'preserve');
        df = readtable(src, opts);
        col = @(n) df.(n);
        has = @(n) ismember(n, df.Properties.VariableNames);
        getS = @(n, r) cellstr(string(df.(n)(r)));   % string col rows -> cellstr

        q = cellstr(string(col('question')));
        cndCount = sum(strcmp(q, 'relaxed'));
        assert(cndCount >= 3, '%s: cndCount=%d too small', id, cndCount);
        n = cndCount * 12;
        O = struct();
        O.task = repmat({'h'}, n, 1);      O.type = repmat({'h'}, n, 1);
        O.noseMouth = repmat({'NA'}, n, 1); O.shadowFile = repmat({'NA'}, n, 1);
        O.Q_long = repmat({'h'}, n, 1);    O.Q_short = repmat({'h'}, n, 1);
        O.rsp = zeros(n, 1);               O.rt = zeros(n, 1);
        O.warp = nan(n, 1);                O.cndOnset = zeros(n, 1);
        O.cndOffset = zeros(n, 1);         O.order = (1:n)';
        O.cndName = repmat({'h'}, n, 1);   O.lenQ = ones(n, 1);
        O.cndSpacing = nan(n, 1);
        O.waveMean = nan(n, 1); O.waveMin = nan(n, 1); O.waveMax = nan(n, 1);
        O.waveSD = nan(n, 1);   O.waveIQR = nan(n, 1);
        tt = col('trialTime'); O.trialTim = repmat(tt(1), n, 1);
        fr = col('frameRate'); O.FPS = repmat(fr(1), n, 1);

        qShortOf = @(qc) cellfun(@(x) mapOr(qShort, x), qc, 'UniformOutput', false);

        % ---- pre (order 0) ----
        r = 1:12;
        idx = find(~isnan(col('slider.response')));
        O.task(r) = {'pre'}; O.cndName(r) = {'pre'};
        O.order(r) = 0; O.lenQ(r) = NaN;
        if isempty(idx)
            O.type(r) = {'SKIP'}; O.Q_long(r) = {'SKIP'}; O.Q_short(r) = {'SKIP'};
        else
            O.type(r) = getS('trialType', idx);
            O.Q_long(r) = q(idx); O.Q_short(r) = qShortOf(q(idx));
            v = col('slider.response'); O.rsp(r) = v(idx);
            v = col('slider.rt');       O.rt(r)  = v(idx);
        end

        % ---- audio (order 1) ----
        r = 13:24;
        audioOK = true;
        if has('slider_4.response')
            idx = find(~isnan(col('slider_4.response')));
            idx = idx(1:min(12, numel(idx)));
            if numel(idx) == 12
                v = col('slider_4.response'); O.rsp(r) = v(idx);
                v = col('slider_4.rt');       O.rt(r)  = v(idx);
            else, audioOK = false; end
        elseif has('slider_2.response')
            idx = find(~isnan(col('slider_2.response')));
            idx = idx(1:min(12, numel(idx)));
            if numel(idx) == 12
                v = col('slider_2.response'); O.rsp(r) = v(idx);
                v = col('slider_2.rt');       O.rt(r)  = v(idx);
            else, audioOK = false; end
        else
            audioOK = false;
        end
        O.task(r) = {'audio'}; O.cndName(r) = {'audio'};
        O.noseMouth(r) = {'nose'}; O.order(r) = 1; O.cndSpacing(r) = 1.0;
        s3 = col('slider_3.response'); s3i = find(~isnan(s3), 1);
        if ~isempty(s3i), O.lenQ(r) = s3(s3i); end
        if audioOK
            O.type(r) = getS('trialType', idx);
            O.Q_long(r) = q(idx); O.Q_short(r) = qShortOf(q(idx));
            if has('audioRecording.started')
                a = col('audioRecording.started'); a = a(~isnan(a));
                b = col('audioRecording.stopped'); b = b(~isnan(b));
                if ~isempty(a), O.cndOnset(r) = a(1); O.cndOffset(r) = b(1); end
            end
        else
            O.type(r) = {'SKIP'}; O.Q_long(r) = {'SKIP'}; O.Q_short(r) = {'SKIP'};
        end

        % ---- blocks (orders 2..cndCount-1) ----
        qIdxAll = find(ismember(q, qShort.keys));
        if mod(numel(qIdxAll), 12) ~= 0
            fprintf('TIDY WARN %s: question rows %d not multiple of 12\n', id, numel(qIdxAll));
        end
        cn = repmat({''}, height(df), 1);
        if has('cndName'), cn = cellstr(string(col('cndName'))); end
        of = repmat({''}, height(df), 1);
        if has('outFile'), of = cellstr(string(col('outFile'))); end
        fbS = []; fbE = [];
        if has('focusedBreathing.started')
            fbS = col('focusedBreathing.started'); fbS = find(~isnan(fbS));
            fbE0 = col('focusedBreathing.stopped');
        end
        oldfi = 1;
        for cndi = 2:(cndCount - 1)
            r = (cndi*12+1):((cndi+1)*12);
            sel = qIdxAll((cndi*12+1):((cndi+1)*12));
            i1 = sel(1);
            rawName = strtrim(cn{i1});
            if strlength(string(rawName)) > 0 && any(strcmp(oldRaw, rawName))
                canonN = oldCanon{find(strcmp(oldRaw, rawName), 1)};
                O.task(r) = {canonN}; O.cndName(r) = {canonN};
                O.shadowFile(r) = of(i1);
                if ~isempty(fbS) && oldfi <= numel(fbS)
                    v = col('focusedBreathing.started');
                    O.cndOnset(r) = v(fbS(oldfi));
                    e = fbE0(~isnan(fbE0));
                    if oldfi <= numel(e), O.cndOffset(r) = e(oldfi); end
                    oldfi = oldfi + 1;
                elseif any(strcmp(oldRaw, strtrim(of{i1})))
                    canonN = oldCanon{find(strcmp(oldRaw, strtrim(of{i1})), 1)};
                    O.task(r) = {canonN}; O.cndName(r) = {canonN};
                    v = col('playBackNormal.started'); O.cndOnset(r) = v(i1);
                    v = col('playBackNormal.stopped'); O.cndOffset(r) = v(i1);
                else
                    v = col('verticalLine.started');
                    tmp = find(~isnan(v(1:i1)));
                    if ~isempty(tmp), O.cndOnset(r) = v(tmp(end)); end
                    v = col('verticalLine.stopped'); O.cndOffset(r) = v(i1);
                end
                O.lenQ(r) = s3(i1);
            elseif any(contains(of(sel), 'playback'))
                canonN = oldCanon{find(strcmp(oldRaw, strtrim(of{i1})), 1)};
                O.task(r) = {canonN}; O.cndName(r) = {canonN};
                O.shadowFile(r) = of(i1);
                v = col('playBackNormal.started'); O.cndOnset(r) = v(i1);
                v = col('playBackNormal.stopped'); O.cndOffset(r) = v(i1);
                O.lenQ(r) = s3(i1);
            else
                error('%s: block %d unidentifiable (cndName="%s" outFile="%s")', id, cndi, rawName, of{i1});
            end
            O.type(r) = getS('trialType', sel);
            O.noseMouth(r) = {'nose'};
            if has('cndSpacing'), v = col('cndSpacing'); O.cndSpacing(r) = v(sel); end
            if ismember(O.cndName{r(1)}, {'slowFocus', 'fastFocus', 'ownSpeedFocus'}) && has('waveCycleLen_s')
                tmp = find(strcmp(of, O.shadowFile{r(1)}));
                w = col('waveCycleLen_s'); w = w(tmp); w = w(~isnan(w));
                if ~isempty(w)
                    O.waveMean(r) = mean(w); O.waveMax(r) = max(w); O.waveMin(r) = min(w);
                    O.waveSD(r) = std(w); O.waveIQR(r) = prctile(w, 75) - prctile(w, 25);
                end
            end
            O.Q_long(r) = q(sel); O.Q_short(r) = qShortOf(q(sel));
            s2ok = has('slider_2.response');
            if s2ok
                v = col('slider_2.response');
                s2ok = ~all(isnan(v(sel)));
            end
            if s2ok
                v = col('slider_2.response'); O.rsp(r) = v(sel);
                v = col('slider_2.rt');       O.rt(r)  = v(sel);
            else
                O.rsp(r) = s3(sel);
                v = col('slider_3.rt'); O.rt(r) = v(sel);
            end
            if has('warpRatio'), v = col('warpRatio'); O.warp(r) = v(sel); end
            O.order(r) = cndi;
        end

        T = struct2table(O);
        T = addvars(T, (1:n)', 'Before', 1, 'NewVariableNames', 'Var1');
        T.datFolder = repmat({datFolder}, n, 1);
        writetable(T, fullfile(outFolder, [id '.csv']));
        fprintf('TIDY OK %s: %d rating sets -> %d rows (%s)\n', id, cndCount, n, cand(big).name);
    catch ME
        fprintf('TIDY FAIL %s: %s (%s line %d)\n', id, ME.message, ME.stack(1).name, ME.stack(1).line);
    end
end
fprintf('tidyImport_waveExp_matlab: DONE\n');

function v = mapOr(m, k)
    if m.isKey(k), v = m(k); else, v = 'SKIP'; end
end

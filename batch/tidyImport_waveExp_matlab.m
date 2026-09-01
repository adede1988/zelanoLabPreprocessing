% tidyImport_waveExp_matlab - MATLAB port of the behavioral importers
% (2026-08-31; R is not installed on the lab machine). Converts a session's
% raw psychopy <id>_mindfulBreathing_<date>.csv
% (G:\My Drive\cZelano\breathingDataFiles) into the processedBehavior CSV
% the breathing makeOutDat consumes. TWO source formats, auto-detected:
%
%  WAVE/EEG format (has slider_3): port of experiment_EEGsync's
%    tidyDataImport_waveExp.R - cndName/outFile blocks, oldNames map,
%    focusedBreathing/playBackNormal/verticalLine onset branches, wave
%    stats; 24-col schema -> experiment_EEGsync\processedBehavior\.
%
%  DUPI/closed-loop format (no slider_3; derived 2026-08-31 from
%    TB_2-processed vs TB_3-raw comparison): pre + blocks in temporal
%    order of audioRecording/focusedBreathing/playBackNormal starts
%    (task = audio/focus/shadow), shadowFile = fileType, warp = warpRatio;
%    15-col schema -> closed-loop-respiration\processedBehavior\.
%
% Env: ZLP_TIDY_IDS = comma-separated session ids (required).

datFolder = 'G:\My Drive\cZelano\breathingDataFiles';
outWave = 'E:\GitHub\experiment_EEGsync\processedBehavior';
outDupi = 'E:\GitHub\closed-loop-respiration\processedBehavior';
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
        has = @(n) ismember(n, df.Properties.VariableNames);
        numOf = @(n) str2double(string(df.(n)));            % cell/str/num safe
        strOf = @(n, r) cellstr(fillmissing(strtrim(string(df.(n)(r))), 'constant', string('NA')));

        q = cellstr(fillmissing(string(df.question), 'constant', string('')));
        cndCount = sum(strcmp(q, 'relaxed'));
        assert(cndCount >= 2, '%s: cndCount=%d too small', id, cndCount);
        qIdxAll = find(ismember(q, qShort.keys));
        if mod(numel(qIdxAll), 12) ~= 0
            fprintf('TIDY WARN %s: question rows %d not multiple of 12\n', id, numel(qIdxAll));
        end
        qShortOf = @(qc) cellfun(@(x) mapOr(qShort, x), qc, 'UniformOutput', false);
        isWave = has('slider_3.response');

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
        tt = numOf('trialTime'); O.trialTim = repmat(tt(find(~isnan(tt), 1)), n, 1);
        fr = numOf('frameRate'); O.FPS = repmat(fr(find(~isnan(fr), 1)), n, 1);

        % ---- pre (order 0), shared by both formats ----
        r = 1:12;
        sp = numOf('slider.response');
        idx = find(~isnan(sp));
        O.task(r) = {'pre'}; O.cndName(r) = {'pre'};
        O.order(r) = 0; O.lenQ(r) = NaN;
        if isempty(idx)
            O.type(r) = {'SKIP'}; O.Q_long(r) = {'SKIP'}; O.Q_short(r) = {'SKIP'};
        else
            idx = idx(1:min(12, numel(idx)));
            O.type(r(1:numel(idx))) = strOf('trialType', idx);
            O.Q_long(r(1:numel(idx))) = q(idx);
            O.Q_short(r(1:numel(idx))) = qShortOf(q(idx));
            O.rsp(r(1:numel(idx))) = sp(idx);
            v = numOf('slider.rt'); O.rt(r(1:numel(idx))) = v(idx);
        end

        if isWave
            % ================= WAVE / EEG format (R-script port) =========
            s3 = numOf('slider_3.response');
            s3rt = numOf('slider_3.rt');
            % audio (order 1)
            r = 13:24;
            audioOK = true;
            if has('slider_4.response')
                v = numOf('slider_4.response'); idx = find(~isnan(v));
            else
                v = numOf('slider_2.response'); idx = find(~isnan(v));
            end
            idx = idx(1:min(12, numel(idx)));
            if numel(idx) == 12
                O.rsp(r) = v(idx);
                if has('slider_4.response'), w = numOf('slider_4.rt');
                else, w = numOf('slider_2.rt'); end
                O.rt(r) = w(idx);
            else
                audioOK = false;
            end
            O.task(r) = {'audio'}; O.cndName(r) = {'audio'};
            O.noseMouth(r) = {'nose'}; O.order(r) = 1; O.cndSpacing(r) = 1.0;
            s3i = find(~isnan(s3), 1);
            if ~isempty(s3i), O.lenQ(r) = s3(s3i); end
            if audioOK
                O.type(r) = strOf('trialType', idx);
                O.Q_long(r) = q(idx); O.Q_short(r) = qShortOf(q(idx));
                if has('audioRecording.started')
                    a = numOf('audioRecording.started'); a = a(~isnan(a));
                    b = numOf('audioRecording.stopped'); b = b(~isnan(b));
                    if ~isempty(a), O.cndOnset(r) = a(1); O.cndOffset(r) = b(1); end
                end
            else
                O.type(r) = {'SKIP'}; O.Q_long(r) = {'SKIP'}; O.Q_short(r) = {'SKIP'};
            end
            % blocks (orders 2..cndCount-1)
            cn = repmat({''}, height(df), 1);
            if has('cndName'), cn = cellstr(fillmissing(strtrim(string(df.cndName)), 'constant', string(''))); end
            of = repmat({''}, height(df), 1);
            if has('outFile'), of = cellstr(fillmissing(strtrim(string(df.outFile)), 'constant', string(''))); end
            fbS = []; fbE = [];
            if has('focusedBreathing.started')
                v = numOf('focusedBreathing.started'); fbS = v(~isnan(v));
                v = numOf('focusedBreathing.stopped'); fbE = v(~isnan(v));
            end
            oldfi = 1;
            for cndi = 2:(cndCount - 1)
                r = (cndi*12+1):((cndi+1)*12);
                sel = qIdxAll((cndi*12+1):((cndi+1)*12));
                i1 = sel(1);
                rawName = cn{i1};
                if ~isempty(rawName) && any(strcmp(oldRaw, rawName))
                    canonN = oldCanon{find(strcmp(oldRaw, rawName), 1)};
                    O.task(r) = {canonN}; O.cndName(r) = {canonN};
                    O.shadowFile(r) = of(i1);
                    if oldfi <= numel(fbS)
                        O.cndOnset(r) = fbS(oldfi);
                        if oldfi <= numel(fbE), O.cndOffset(r) = fbE(oldfi); end
                        oldfi = oldfi + 1;
                    elseif any(strcmp(oldRaw, of{i1}))
                        canonN = oldCanon{find(strcmp(oldRaw, of{i1}), 1)};
                        O.task(r) = {canonN}; O.cndName(r) = {canonN};
                        v = numOf('playBackNormal.started'); O.cndOnset(r) = v(i1);
                        v = numOf('playBackNormal.stopped'); O.cndOffset(r) = v(i1);
                    else
                        v = numOf('verticalLine.started');
                        tmp = find(~isnan(v(1:i1)));
                        if ~isempty(tmp), O.cndOnset(r) = v(tmp(end)); end
                        v = numOf('verticalLine.stopped'); O.cndOffset(r) = v(i1);
                    end
                elseif any(contains(of(sel), 'playback'))
                    canonN = oldCanon{find(strcmp(oldRaw, of{i1}), 1)};
                    O.task(r) = {canonN}; O.cndName(r) = {canonN};
                    O.shadowFile(r) = of(i1);
                    v = numOf('playBackNormal.started'); O.cndOnset(r) = v(i1);
                    v = numOf('playBackNormal.stopped'); O.cndOffset(r) = v(i1);
                else
                    error('%s: block %d unidentifiable (cndName="%s" outFile="%s")', id, cndi, rawName, of{i1});
                end
                O.lenQ(r) = s3(i1);
                O.type(r) = strOf('trialType', sel);
                O.noseMouth(r) = {'nose'};
                if has('cndSpacing'), v = numOf('cndSpacing'); O.cndSpacing(r) = v(sel); end
                if ismember(O.cndName{r(1)}, {'slowFocus', 'fastFocus', 'ownSpeedFocus'}) && has('waveCycleLen_s')
                    tmp = find(strcmp(of, O.shadowFile{r(1)}));
                    w = numOf('waveCycleLen_s'); w = w(tmp); w = w(~isnan(w));
                    if ~isempty(w)
                        O.waveMean(r) = mean(w); O.waveMax(r) = max(w); O.waveMin(r) = min(w);
                        O.waveSD(r) = std(w); O.waveIQR(r) = prctile(w, 75) - prctile(w, 25);
                    end
                end
                O.Q_long(r) = q(sel); O.Q_short(r) = qShortOf(q(sel));
                s2 = nan(height(df), 1);
                if has('slider_2.response'), s2 = numOf('slider_2.response'); end
                if ~all(isnan(s2(sel)))
                    O.rsp(r) = s2(sel);
                    v = numOf('slider_2.rt'); O.rt(r) = v(sel);
                else
                    O.rsp(r) = s3(sel); O.rt(r) = s3rt(sel);
                end
                if has('warpRatio'), v = numOf('warpRatio'); O.warp(r) = v(sel); end
                O.order(r) = cndi;
            end
            T = struct2table(O);
            T = addvars(T, (1:n)', 'Before', 1, 'NewVariableNames', 'Var1');
            T.datFolder = repmat({datFolder}, n, 1);
            outp = fullfile(outWave, [id '.csv']);
        else
            % ================= DUPI / closed-loop format =================
            % blocks = temporal order of audio/focus/shadow start events
            ev = zeros(0, 3);   % [onset offset family] 1=audio 2=focus 3=shadow
            fams = {'audioRecording', 'focusedBreathing', 'playBackNormal'};
            for f = 1:3
                if ~has([fams{f} '.started']), continue; end
                a = numOf([fams{f} '.started']); a = a(~isnan(a));
                b = numOf([fams{f} '.stopped']); b = b(~isnan(b));
                for k = 1:numel(a)
                    if k <= numel(b), off = b(k); else, off = NaN; end
                    ev(end+1, :) = [a(k), off, f]; %#ok<AGROW>
                end
            end
            ev = sortrows(ev, 1);
            nBlocks = size(ev, 1);
            if nBlocks ~= cndCount - 1
                fprintf('TIDY WARN %s: %d blocks vs %d rating sets (using min)\n', id, nBlocks, cndCount - 1);
            end
            famName = {'audio', 'focus', 'shadow'};
            s2 = nan(height(df), 1);
            if has('slider_2.response'), s2 = numOf('slider_2.response'); end
            s2rt = nan(height(df), 1);
            if has('slider_2.rt'), s2rt = numOf('slider_2.rt'); end
            for b = 1:min(nBlocks, cndCount - 1)
                r = (b*12+1):((b+1)*12);
                sel = qIdxAll((b*12+1):((b+1)*12));
                i1 = sel(1);
                O.task(r) = famName(ev(b, 3));
                O.cndName(r) = famName(ev(b, 3));
                O.cndOnset(r) = ev(b, 1); O.cndOffset(r) = ev(b, 2);
                O.order(r) = b;
                O.type(r) = strOf('trialType', sel);
                O.Q_long(r) = q(sel); O.Q_short(r) = qShortOf(q(sel));
                O.rsp(r) = s2(sel); O.rt(r) = s2rt(sel);
                nmv = {'nose'};
                if has('noseMouth')
                    t = strOf('noseMouth', i1);
                    if ~strcmp(t{1}, 'NA'), nmv = t; end
                end
                O.noseMouth(r) = nmv;
                if ev(b, 3) == 3    % shadow: source + warp
                    if has('fileType'), O.shadowFile(r) = strOf('fileType', i1); end
                    if has('warpRatio'), v = numOf('warpRatio'); O.warp(r) = v(i1); end
                end
            end
            T = struct2table(rmfield(O, {'cndName', 'lenQ', 'cndSpacing', ...
                'waveMean', 'waveMin', 'waveMax', 'waveSD', 'waveIQR'}));
            T = addvars(T, (1:n)', 'Before', 1, 'NewVariableNames', 'Var1');
            outp = fullfile(outDupi, [id '.csv']);
        end
        writetable(T, outp);
        fprintf('TIDY OK %s [%s]: %d sets -> %d rows -> %s\n', id, ...
            ternS(isWave, 'wave', 'dupi'), cndCount, n, outp);
    catch ME
        fprintf('TIDY FAIL %s: %s (%s line %d)\n', id, ME.message, ME.stack(1).name, ME.stack(1).line);
    end
end
fprintf('tidyImport_waveExp_matlab: DONE\n');

function v = mapOr(m, k)
    if m.isKey(k), v = m(k); else, v = 'SKIP'; end
end
function out = ternS(cond, a, b)
    if cond, out = a; else, out = b; end
end

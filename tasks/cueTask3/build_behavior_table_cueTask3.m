function [behDat, noOdor] = build_behavior_table_cueTask3(sniffs, rawBeh, P)
%BUILD_BEHAVIOR_TABLE_CUETASK3  Per-sniff behaviour table of cueTask3 (3 sniffs per trial).
%
%   [behDat, noOdor] = build_behavior_table_cueTask3(sniffs, rawBeh, P)
%
%   sniffs  detect_sniffs_from_TTLs output in train mode (P.sniffTrain): one
%           row per detected sniff, col 3 = its cue number 1-3, cols 8 / 9 =
%           the inhale trough / peak sample
%   rawBeh  the intermediate's per-trial table (cue, odor, response,
%           response_str, type, run, ...), one row per TTL row
%   P       applyParams struct: P.noOdorTrials / P.noOdorReason
%
%   The cue task's builder (build_behavior_table_cueTask: the shared six
%   columns + cue / odor / response / respString / type broadcast to every
%   sniff of the trial), then:
%     run              the trial's run (1 / 2)
%     noOdorDelivered  true on every sniff of a trial listed in
%                      P.noOdorTrials (no odor reached the participant although
%                      the result file lists one; the rows stay, type unchanged)
%     inhaleTrough / inhalePeak  the train detector's bounds; read by
%                      refine_onsets_with_phase (train mode)
%   noOdor  table (trial, reason) of P.noOdorTrials, empty when none.

    behDat = build_behavior_table_cueTask(sniffs, rawBeh);
    behDat.run = rawBeh.run(behDat.n);

    nTrial = height(rawBeh);
    bad = P.noOdorTrials(:);
    if any(bad < 1 | bad > nTrial | bad ~= round(bad))
        error('build_behavior_table_cueTask3:noOdorTrials', ...
            'P.noOdorTrials %s outside the session''s trials 1-%d', mat2str(bad'), nTrial);
    end
    behDat.noOdorDelivered = ismember(behDat.n, bad);
    noOdor = table(bad, repmat(string(P.noOdorReason), numel(bad), 1), ...
        'VariableNames', {'trial', 'reason'});

    behDat.inhaleTrough = sniffs(:, 8);
    behDat.inhalePeak   = sniffs(:, 9);
end

function [Pc, info] = sepSectionP(P, condition)
%SEPSECTIONP  Parameter struct of ONE breathingTasks_separate condition recording.
%
%   [Pc, info] = sepSectionP(P, condition)
%
%   Pc = P with this recording's per-condition settings applied. Every
%   per-condition field is set by applyParams, aligned with P.conditions
%   (sheet order), and matched here by the condition's sheet Task value:
%
%     rspIDX / rspFlip    P.condRspIDX / condRspFlip (via sepSectionRsp; the
%                         sheet row's own respiration channel, 2026-10-12)
%     beatSpec / getBeats P.condBeatSpec (the sheet row's own ECG beatSpec,
%                         tasks_261014 task 9). With every row's spec equal
%                         (all sessions before 2026-10-14) this is P.beatSpec
%     blinkRemoval        the condition's default from config/sepConditionInfo
%                         (.blinkRemoval: false for sleep / sleepWithOdor and
%                         their _run<N> takes - reviewer 2026-10-20, G2b -
%                         true otherwise), unless the session sets
%                         P.condBlinkRemoval (optional, explicit per-session
%                         case in applyParams), which wins: its value for this
%                         recording (NaN = use the condition default). false =
%                         this recording's EEG stage skips blink removal
%                         (preprocess_eeg's P.blinkRemoval path). Pc.blinkRemoval
%                         is set only when the recording skips it, or when
%                         P.condBlinkRemoval sets it, so a session without
%                         either runs exactly as before
%     respSkip            P.condRespSkip (optional, explicit per-session case;
%                         true = respiration not recoverable in this recording:
%                         no breath segmentation, no breaths from it)
%     minIBI              P.condMinIBI (optional, explicit per-session case; s,
%                         this recording's shared/processECG P.minIBI: beats
%                         closer than that to the last kept beat are dropped
%                         and the RR series floored there). NaN = not set for
%                         this recording (a session-wide P.minIBI, if any, holds)
%
%     seedTag             always: the condition (sheet Task value); with the
%                         session ID it is the key of the macro spike ICA's
%                         random seed (preprocess_macros, 2026-10-22)
%
%   (A per-condition trim, P.condTrimSec, is applied to the raw data by
%   assembleRaw_breathingTasks_separate, before anything else.)
%
%   info: .k (index into P.conditions, [] if not listed) .rspIDX .rspFlip
%         .rspMixed (conditions differ in channel/polarity) .beatMixed
%         (conditions differ in beatSpec) .blinkSkipped .respSkipped
%         .blinkReason ('' = blink removal not switched off; 'conditionDefault'
%         = the sepConditionInfo default; 'session' = P.condBlinkRemoval)

    [idx, flip, rspMixed] = sepSectionRsp(P, condition);
    Pc = P;
    Pc.rspIDX = idx; Pc.rspFlip = flip;
    % the section's identity for the shared stages' random seeds (2026-10-22):
    % preprocess_macros seeds its spike ICA from sessID | stage | seedTag
    Pc.seedTag = char(string(condition));

    k = [];
    if isfield(P, 'conditions')
        k = find(strcmpi(strtrim(P.conditions), strtrim(condition)), 1);
    end
    info = struct('k', k, 'rspIDX', idx, 'rspFlip', flip, 'rspMixed', rspMixed, ...
                  'beatMixed', false, 'blinkSkipped', false, 'respSkipped', false, ...
                  'blinkReason', '');

    if isfield(P, 'condBeatSpec') && ~isempty(k)
        info.beatMixed = numel(unique(P.condBeatSpec)) > 1;
        spec = P.condBeatSpec{k};
        Pc.beatSpec = spec;
        Pc.getBeats = @(ECGz, beatSep) detectBeats(ECGz, beatSep, spec);
    end
    % blink removal: an explicit per-session setting wins; else the
    % condition's default (G2b: none in sleep / sleepWithOdor recordings)
    ci = sepConditionInfo(condition);
    if isfield(P, 'condBlinkRemoval') && ~isempty(k) && ~isnan(double(P.condBlinkRemoval(k)))
        Pc.blinkRemoval = logical(P.condBlinkRemoval(k));
        info.blinkSkipped = ~Pc.blinkRemoval;
        if info.blinkSkipped, info.blinkReason = 'session'; end
    elseif ~isempty(ci) && ~ci.blinkRemoval
        Pc.blinkRemoval = false;
        info.blinkSkipped = true;
        info.blinkReason = 'conditionDefault';
    end
    if isfield(P, 'condRespSkip') && ~isempty(k)
        Pc.respSkip = logical(P.condRespSkip(k));
        info.respSkipped = Pc.respSkip;
    end
    if isfield(P, 'condMinIBI') && ~isempty(k) && ~isnan(P.condMinIBI(k))
        Pc.minIBI = P.condMinIBI(k);
    end
end

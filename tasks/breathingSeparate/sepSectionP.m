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
%     blinkRemoval        P.condBlinkRemoval (optional, explicit per-session
%                         case in applyParams; false = this recording's EEG
%                         stage skips blink removal, preprocess_eeg's
%                         P.blinkRemoval path). Absent = not set = the default
%     respSkip            P.condRespSkip (optional, explicit per-session case;
%                         true = respiration not recoverable in this recording:
%                         no breath segmentation, no breaths from it)
%     minIBI              P.condMinIBI (optional, explicit per-session case; s,
%                         this recording's shared/processECG P.minIBI: beats
%                         closer than that to the last kept beat are dropped
%                         and the RR series floored there). NaN = not set for
%                         this recording (a session-wide P.minIBI, if any, holds)
%
%   (A per-condition trim, P.condTrimSec, is applied to the raw data by
%   assembleRaw_breathingTasks_separate, before anything else.)
%
%   info: .k (index into P.conditions, [] if not listed) .rspIDX .rspFlip
%         .rspMixed (conditions differ in channel/polarity) .beatMixed
%         (conditions differ in beatSpec) .blinkSkipped .respSkipped

    [idx, flip, rspMixed] = sepSectionRsp(P, condition);
    Pc = P;
    Pc.rspIDX = idx; Pc.rspFlip = flip;

    k = [];
    if isfield(P, 'conditions')
        k = find(strcmpi(strtrim(P.conditions), strtrim(condition)), 1);
    end
    info = struct('k', k, 'rspIDX', idx, 'rspFlip', flip, 'rspMixed', rspMixed, ...
                  'beatMixed', false, 'blinkSkipped', false, 'respSkipped', false);

    if isfield(P, 'condBeatSpec') && ~isempty(k)
        info.beatMixed = numel(unique(P.condBeatSpec)) > 1;
        spec = P.condBeatSpec{k};
        Pc.beatSpec = spec;
        Pc.getBeats = @(ECGz, beatSep) detectBeats(ECGz, beatSep, spec);
    end
    if isfield(P, 'condBlinkRemoval') && ~isempty(k)
        Pc.blinkRemoval = logical(P.condBlinkRemoval(k));
        info.blinkSkipped = ~Pc.blinkRemoval;
    end
    if isfield(P, 'condRespSkip') && ~isempty(k)
        Pc.respSkip = logical(P.condRespSkip(k));
        info.respSkipped = Pc.respSkip;
    end
    if isfield(P, 'condMinIBI') && ~isempty(k) && ~isnan(P.condMinIBI(k))
        Pc.minIBI = P.condMinIBI(k);
    end
end

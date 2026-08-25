% task9_respecs — measured beatSpecs for the breathingTasks_separate sessions
% whose round-4 HRV was implausible or probe-dropped (task9_probeECGpolarity,
% 2026-08-25, bpm per channel x polarity on the saved finals):
%   HM_2: ch3 -3.5 = 67.9 bpm (ch3 +3.5 = 1.3)      -> 3,0,lt,-3.5
%   SP_2: ch2 +3.5 = 67.7 bpm (all others <18)       -> 2,0,gt,3.5
%   RC_1: ch1 -3.5 = 51.0 bpm (ch1 +3.5 = 7.3)       -> 1,0,lt,-3.5
%   KA_2: ch1 -3.5 = 61.1 bpm (ch1 +3.5 = 3.4)       -> 1,0,lt,-3.5
%   RY_1: no channel/side above 6.5 bpm - no cardiac signal recorded; the
%         final keeps NaN HRV (correct) and is NOT respec'd.

SPEC = {'260625_OBE_NWU_HM_2', '3,0,lt,-3.5'; ...
        '260702_OBE_NWU_SP_2', '2,0,gt,3.5'; ...
        '260622_OBE_NWU_RC_1', '1,0,lt,-3.5'; ...
        '260720_OBE_NWU_KA_2', '1,0,lt,-3.5'};
for k = 1:size(SPEC, 1)
    id = SPEC{k, 1};
    P = applyParams('breathingTasks_separate', id);
    P.beatSpec = SPEC{k, 2};
    P.paramSource = 'guess';           % still unverified by a human
    writeSheetSep(P, id, 'params');
    fprintf('%s: beatSpec -> %s\n', id, SPEC{k, 2});
end
fprintf('task9_respecs: DONE\n');

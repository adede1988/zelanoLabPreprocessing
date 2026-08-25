% task8_fixCA — CA's ECG has a clear rhythm masked by noise bursts (user
% report, confirmed by batch/task8_probeCA2 + task89_probeBlankSim): after
% blanking noisy windows (now a per-session special case in buildECGz), ch3
% shows 62.0 bpm below -3.5 sigma vs 2.9 above (ch1/ch2 are biphasic).
% Point CA's beatSpec at the clean side before the rebuild.

id = '260805_EEG_NWU_CA';
P = applyParams('alternating6Blocks', id);
P.beatSpec = '3,0,lt,-3.5';
P.paramSource = 'guess';           % still unverified by a human
writeParams(P, id);
fprintf('%s: beatSpec -> %s\n', id, P.beatSpec);
fprintf('task8_fixCA: DONE\n');

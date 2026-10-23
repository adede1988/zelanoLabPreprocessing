function outDat = runSharedCore(outDat, P, EEGLOC)
%RUNSHAREDCORE  SHARED signal core every *PreProc_main runs after assembly.
%
%   outDat = runSharedCore(outDat, P, EEGLOC)
%
%   1. downsample_data     resample to P.fs_target (500 Hz) + 0.03 Hz HP / LP
%   2. preprocess_eeg      only if P.hasEEG (EEGLOC = readtable(L.eegLocCsv))
%   3. preprocess_macros   only if P.hasMacros (bipolar macBP* + spikeCleanVec)
%
%   applyParams sets P.hasMacros for every task: sheet-driven for the
%   breath-type tasks, always true for cueTask / threshTask / O15 (which
%   always ran the macro stage). The order is fixed; a fix here reaches every
%   task. breathingTasks_separate calls it once per condition recording.

    outDat = downsample_data(outDat, P.fs_target);
    if P.hasEEG, outDat = preprocess_eeg(outDat, EEGLOC, P); end
    if P.hasMacros, outDat = preprocess_macros(outDat, P); end
end

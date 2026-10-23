function behDat = build_behavior_table_detectNoOdor(sniffs, rawBeh, inh, TTL, fs)
% Integrate detectNoOdor behavioral data with the detected sniff onsets.
% Shared front matter (first 6 columns) comes from behDatFromSniffs; the loop
% below is the TASK-SPECIFIC broadcast of the trial's fields onto its sniff:
%   odor         the cuelist's planned code (1 / 2) - never delivered (no odor
%                is ever presented in this task; loadBeh_detectNoOdor)
%   trialType    screen layout of the Yes/No boxes (1: Yes left, 2: Yes right)
%   response     the key pressed (1 left / 2 right; NaN = no answer)
%   respString   the answer, "Yes" / "No" ("SKIP" = no answer) - authoritative
%   respLatency  s from the SNIFF cue to the response pulse (DAQ; NaN = no answer)
%   nInhales     inhale peaks between the cue and the answer (countInhales_detectNoOdor)

    behDat = behDatFromSniffs(sniffs, {"cued"});
    nR = height(behDat);
    behDat.odor        = nan(nR, 1);
    behDat.trialType   = nan(nR, 1);
    behDat.response    = nan(nR, 1);
    behDat.respString  = repmat("SKIP", nR, 1);
    behDat.respLatency = nan(nR, 1);
    behDat.nInhales    = nan(nR, 1);
    for ii = 1:height(rawBeh)
        idx = find(behDat.n == ii);
        for jj = 1:length(idx)
            behDat.odor(idx(jj))      = rawBeh.odor(ii);
            behDat.trialType(idx(jj)) = rawBeh.trialType(ii);
            behDat.response(idx(jj))  = rawBeh.response(ii);
            if ~isempty(rawBeh.response_str{ii})
                behDat.respString(idx(jj)) = string(rawBeh.response_str{ii});
            end
            behDat.respLatency(idx(jj)) = (TTL.response(ii) - TTL.sniff(ii)) / fs;
            behDat.nInhales(idx(jj))    = inh.nInhales(ii);
        end
    end
end

function behDat = build_behavior_table_threshTask(sniffs, rawBeh, design)
% Integrate threshTask (PEA) behavioral data with the detected sniff onsets.
% Shared front matter (first 6 columns) comes from behDatFromSniffs; the loop
% below is the TASK-SPECIFIC broadcast of thresh raw-behavior fields onto each sniff.
%
% design (optional, 2026-10-15): the intermediate's threshDesign struct of a
% multi-run session (loadBeh_multiRun_threshTask). Its odorCodes / odorLabels
% map the odor code (olfactometer line, 1 / 2 / 3 / 12) to type air / low /
% med / high, and rawBeh then carries a run column, broadcast as behDat.run.
% Without it (every legacy session) the legacy mapping, odor 1 / 2 / 3 =
% air / low / med by index, and no run column - unchanged.
% Detection build (2026-10-20, 261012_INR_NWU_VC_1): rawBeh also carries
% detect (the Yes/No "odor?" answer, 1 / 0 / NaN = no click) and detectRT (s),
% broadcast as behDat.detect / behDat.detectRT after run. Sessions without
% these columns are unchanged.

    trialTypes = {'air', 'low', 'med'};
    hasDesign = nargin >= 3 && ~isempty(design);
    hasRun = ismember('run', rawBeh.Properties.VariableNames);
    hasDetect = all(ismember({'detect', 'detectRT'}, rawBeh.Properties.VariableNames));
    behDat = behDatFromSniffs(sniffs, {"cued"});

    for ii = 1:length(rawBeh.trialNum)
        idx = find(behDat.n == ii);
        if hasDesign
            ci = find(design.odorCodes == rawBeh.Odor(ii));
            if ~isscalar(ci)
                error('build_behavior_table_threshTask: odor code %g of trial %d is not in the design.', ...
                    rawBeh.Odor(ii), ii);
            end
            typeStr = string(design.odorLabels{ci});
        end
        for jj = 1:length(idx)
            behDat.odor(idx(jj))         = rawBeh.Odor(ii);
            behDat.pleasantness(idx(jj)) = rawBeh.pleasantness(ii);
            behDat.intensity(idx(jj))    = rawBeh.intensity(ii);
            if hasDesign
                behDat.type(idx(jj))     = typeStr;
            else
                behDat.type(idx(jj))     = string(trialTypes{rawBeh.Odor(ii)});
            end
            if hasRun
                behDat.run(idx(jj))      = rawBeh.run(ii);
            end
            if hasDetect
                behDat.detect(idx(jj))   = rawBeh.detect(ii);
                behDat.detectRT(idx(jj)) = rawBeh.detectRT(ii);
            end
        end
    end
end

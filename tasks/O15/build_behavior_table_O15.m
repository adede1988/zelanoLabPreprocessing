function behDat = build_behavior_table_O15(sniffs, rawBeh, heldButton)
% Integrate O15 behavioral data with the detected sniff onsets.
% Shared front matter (first 6 columns) comes from behDatFromSniffs; the loop
% below is the TASK-SPECIFIC broadcast of O15 raw-behavior fields onto each sniff.
% heldButton (optional, default false; true when outDat.buttonDown exists -
% the held-button protocol, tasks_261014 task 10) appends buttonWindow: the
% outDat.buttonDown row a free sniff came from (NaN for start / confirm).

    if nargin < 3, heldButton = false; end
    % detect_sniffs_from_TTLs preallocates 30 rows: with fewer sniffs than that
    % drop the unfilled rows
    sniffs = sniffs(sniffs(:,6) > 0, :);
    behDat = behDatFromSniffs(sniffs, {"start", "free", "confirm"});

    for ii = 1:length(rawBeh.target)
        idx = find(behDat.n == ii);
        for jj = 1:length(idx)
            behDat.target(idx(jj))   = string(rawBeh.target{ii});
            behDat.response(idx(jj)) = string(rawBeh.response{ii});
            behDat.expScore(idx(jj)) = rawBeh.expScore(ii);
        end
    end
    if heldButton
        bw = sniffs(:,5);
        bw(bw == 0) = NaN;
        behDat.buttonWindow = bw;
    end
end

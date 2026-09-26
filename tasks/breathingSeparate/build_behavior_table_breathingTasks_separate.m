function outDat = build_behavior_table_breathingTasks_separate(outDat)
%BUILD_BEHAVIOR_TABLE_BREATHINGTASKS_SEPARATE  Per-breath behDat (Task 9 / D12c).
%
%   Breathing-layout columns from the concatenated bmObj; task = the
%   section's canonical condition label, condition = section index;
%   shadowFile/warp/noseMouth kept and filled with NA/NaN; no rating columns
%   and no baseEmotion (dropped by design); bm_* feature columns appended.

    bmObj = outDat.bmObj;
    sec = outDat.sections;

    behDat = behDatFromBreaths(bmObj, size(outDat.data, 2), outDat.fs);   % shared 14 base columns
    behDat.task       = cellstr(sec.label(bmObj(:, 12)));
    n = height(behDat);
    behDat.noseMouth  = repmat("NA", n, 1);
    behDat.shadowFile = repmat("NA", n, 1);
    behDat.warp       = nan(n, 1);

    outDat.behDat = behDat;

    % ---- bm_* columns (shared convention, D8e) ----
    outDat = appendBmFeatureCols(outDat, 'build_behavior_table_breathingTasks_separate');
end

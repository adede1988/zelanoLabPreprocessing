function outDat = process_respiration_breathing(outDat, P)

    % respiration
    idx = cellfun(@(x) contains(x, 'rsp'), outDat.labels);
    rspDat = outDat.data(idx,:);
    rspDat = rspDat(P.rspIDX,:);
    rspDat = rspDat .* P.rspFlip;

    % cyclicSigh block span (samples) from the original behavior + TTL: the
    % locked engine merges the paced double inhale at the SEGMENTATION level
    % (keep-first-within-5s peak rule inside the span), which replaces the
    % legacy post-hoc bmObj row merge that used to live in this function.
    cySpan = [];
    if ismember('cndName', outDat.behDat.Properties.VariableNames)
        orderIdx = arrayfun(@(x) find(outDat.behDat.order == x, 1), ...
                            unique(outDat.behDat.order));
        orderIdx(1) = [];             % drop the pre/baseline ratings
        if length(orderIdx) == length(outDat.TTL)
            for ii = 1:length(orderIdx)
                if ismember('cyclicSigh', outDat.behDat.cndName(orderIdx(ii)))
                    startIdx = outDat.TTL(outDat.behDat.order(orderIdx(ii)));
                    if startIdx == 0, startIdx = 1; end
                    if ii == length(orderIdx)
                        endIdx = length(rspDat);
                    else
                        endIdx = outDat.TTL(outDat.behDat.order(orderIdx(ii+1)));
                    end
                    cySpan = [startIdx endIdx];
                    break
                end
            end
        end
    end

    % LOCKED per-breath engine (QC round 4, rev12b 2026-08-28): conservative
    % prep x kneeBacktrack; breathMetrics computes the per-breath features
    % from our landmarks. Legacy engines kept in the repo for comparison:
    %   bmObj = breathTemplates4(rspDat, outDat.fs);
    %   [bmObj, bmFeatures] = segmentBreaths_breathMetrics(rspDat, outDat.fs);
    [bmObj, bmFeatures] = segmentBreaths_zlp(rspDat, outDat.fs, [], [], cySpan);
    %col 1: onset Y value        col 8: amp (peak Y - avg of two ends)
    %col 2: onset tim            col 9: idx of peak
    %col 3: peak Y value         col10: exhale peak Y value
    %col 4: peak tim             col11: exhale peak tim
    %col 5: end Y value          col12: condition
    %col 6: end tim              col13: empty
    %col 7: length               col14: index

    bmObj(:, 14) = 1:size(bmObj, 1);
    outDat.bmObj = bmObj;
    outDat.bmFeatures = bmFeatures;
end

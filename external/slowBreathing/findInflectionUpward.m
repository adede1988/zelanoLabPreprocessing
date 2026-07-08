function [bestIdx, scores] = findInflectionUpward(sig, padVal, ...
                                        searchRange, guess, sigRaw)
    % sig: input signal vector
    % padVal: half-window size
    % searchRange: range of indices to evaluate (e.g., padVal+1 : length(sig)-padVal)
    % figure
    % subplot 221
    % plot(sig)
    % hold on 
    % plot(sigRaw)
    % xline(guess)
    scores = zeros(size(sig));
    goodSlopes = scores; 
    slopes = linspace(-.5,.5, 1000); 
    xWin = -padVal:padVal; 
    for i = searchRange

        yLines = arrayfun(@(s) xWin .* s + sig(i), slopes, ...
                                    'uniformoutput', false); 
        yLines = cat(1, yLines{:});

        res = yLines - sig(i+xWin);

        %how many slopes yielded all underestimates of the signal
        posPoints = sum(res<0, 2) == padVal*2; 
        if sum(posPoints) > 0
            [scores(i), slopei] = min(sum(res(posPoints,:), 2));
            tmpidx = find(posPoints);
            goodSlopes(i) = slopes(tmpidx(slopei)); 
        end

    end
    % subplot 222
    % plot(scores)

    %pad it so that looking right will always work! 
    sigRaw(end:end+8) = sigRaw(end); 

    if min(scores) < 0
            [minVals, minLocs] = findpeaks(-scores);
            % xline(minLocs, 'color', 'red', 'linestyle', '--')
            % subplot 221
            % xline(minLocs, 'color', 'red', 'linestyle', '--')
            tmpWin = -padVal*2:padVal*2;
            % for jj = 1:length(minLocs)
            %     hold on 
            %     plot(tmpWin+minLocs(jj), tmpWin .* goodSlopes(minLocs(jj)) +...
            %                     sig(minLocs(jj)), 'color', 'green')
            % 
            % end
            if isscalar(minLocs)
                bestIdx = minLocs; 
                % subplot 221
                % xline(bestIdx, 'color', 'k', 'linewidth', 2)
            else
                sigPeaks = sigRaw(minLocs); 
                sigLeft = sigRaw(minLocs - 8); 
                sigRight = sigRaw(minLocs +8); 

                % subplot 223
                % scatter(sigLeft - sigPeaks, sigRight - sigPeaks, ...
                %     30, 'filled')
                % xlabel('fall off to left')
                % ylabel('rise to right')
                
%% NOTE: could think about using a ratio measure. That is, the expectation
%is that to the left will be basically flat, so change should be
%small--negative, but small. To the right, it should always be positive and
%large. SO: ratio = right rise / abs(leftFall) should be big for a good
%detection. Can add in a penalty value for positive left fall offs? 

                %looking for candidate points to be positive in rise right
                %and negative in fall off left
                %zero out values that are in the wrong direction:
                sigLeft = sigLeft - sigPeaks;
                sigRight = sigRight - sigPeaks;

                %new index measure 
                minVals = minVals - min(minVals); 
                minVals = minVals / max(minVals); 

                d = max(sigRight)/2 .* minVals + ...
                    sigRight - ...
                    sigLeft.^2 - ...
                    max(sign(sigLeft), 0) .* min(abs(sigRight));

                %old distance measure
                % % sigLeft(sigLeft>0) = 0; 
                % % sigRight(sigRight<0) = 0; 
                % % %apply pythagorean theorem to get distance from origin:
                % % d = sqrt(sigLeft.^2 + sigRight.^2); 
                %choose point farthest from origin
                [~, bestIdx] = max(d); 
                bestIdx = minLocs(bestIdx); 
                % subplot 221
                % xline(bestIdx, 'color', 'k', 'linewidth', 2)
                % if all(sigLeft - sigPeaks < 0) 
                % %if they're all good candidates, then take the biggest peak
                %     [~, bestIdx] = min(-minVals);
                %     bestIdx = minLocs(bestIdx); 
                % elseif any(sigLeft - sigPeaks < 0)
                % %if any are all good candidates, then take the biggest peak   
                %     minVals = minVals(sigLeft - sigPeaks < 0); 
                %     minLocs = minLocs(sigLeft - sigPeaks < 0); 
                %     [~, bestIdx] = min(-minVals);
                %     bestIdx = minLocs(bestIdx); 
                % else
                % %otherwise just take the closest to good candidate
                %     [~, choiceIDX] =  min(sigLeft - sigPeaks);
                %     bestIdx = minLocs(choiceIDX); 
                % end
            end
       
    else
        'uh oh'
    end
end

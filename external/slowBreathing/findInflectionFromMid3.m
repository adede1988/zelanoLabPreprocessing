function [inflection] = findInflectionFromMid3(sig, midIDX, plotPos, fs, ...
                                                    sigRaw)

%Sig      1Xtime timeseries vector 
%midIDX   index of candidate inflection from the END

%inflection   integer index value specifying the nearest major inflection
%             point in the data from the END
padLen = 5;




N = length(sig); 

starti = N - midIDX+1 - round(fs/5); 

% if padLen + starti > N
%     internalAdj = (padLen + starti) - N; 
%     midIDX = midIDX + internalAdj; 
%     starti = N - midIDX+1; 
% else
%     internalAdj = 0; 
% end


tmp = linspace(sig(starti), sig(end - round(fs/5)), midIDX);





%Find fit residuals
%look at residuals in the +- 3 positions around the candidate inflection
%point: 
endi = N - padLen; 
% if starti + 15 > N
%     endi = N;
% else
%     endi = round((starti + N) / 2);
% end
% subplot(3, 4, 2 + plotPos) 
% hold off
% plot(sig, 'color', 'green', 'linewidth', 2)
% xline(starti, 'red')
% hold on 
% plot(starti:N- round(fs/5), tmp)
% xline([starti-20, endi])



[bestIdx, scores] = findInflectionUpward(sig, padLen, starti-20:endi, ...
                                    starti, sigRaw);


outIDX = bestIdx; 

% xline(starti - 20 + outIDX - 1)
inflection = outIDX - starti; 


% 
% subplot(3, 4, 5 + plotPos) 
% plot(scores, 'color', 'green', 'linewidth', 2)
% xline(starti)
% xline(starti + inflection, 'linewidth', 2)


% inflection = inflection - internalAdj; 





%BREATH 111 is hard because it's concave

%take the minimum negDist and use it to index into posi to get the
%inflection

%If there's no zero to the left of any positive, then just don't adjust
%inflection







end
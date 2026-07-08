function [inflection, SSDer] = findInflection(sig, slopeBased, ...
                                    plotIT, tim)

%Sig      1Xtime timeseries vector 

%inflection   integer index value specifying the nearest major inflection
%point in the data from the end

% sig = normalize(sig); 

SS = zeros(length(sig), 1); 
slopes = SS; 

fittedVals = cell(length(sig), 1); %store the fitted vals for plotting

for jj = 1:length(sig)
  
    if jj < length(sig)-1
    x = tim(jj:length(sig));
    y = sig(jj:end);
    p = polyfit(x, y, 1);         % fit line y = p(1)*x + p(2)
    slopes(jj) = p(1); 
    yfit = polyval(p, x);
    fittedVals{jj} = [x; yfit]; 

    SS(jj) = mean((y - yfit).^2); % MSE
    end
end



if slopeBased
    slopes = normalize(smoothdata(slopes, 'gaussian', 5));
    [~, inflection] = max(flip(slopes));
    SSDer = flip(slopes); 
else
    SS = flip(SS); %flip to look from the end
    SSDer = diff(smoothdata(SS, 'gaussian', 3));
    SSDerDer = diff(SSDer); 
    
    inflection = find(SSDerDer(2:length(SSDerDer))>0 & ...
         SSDerDer(1:length(SSDerDer)-1)<0, 1) + 2;
end









end



%     plot(jj:length(sig), yfit)
%     if jj>16 && jj<22
%         if jj == 19
%             plot(jj:length(sig), yfit, 'color', 'red', 'linestyle', '--', 'linewidth', 3)
%         else
%             plot(jj:length(sig), yfit)
%         end
%     end

% % 
% % 
% % if plotIT
% % %     plotSlopes = smoothdata(slopes, 'gaussian', 5); 
% % % 
% % % % plot(1:length(sig), sig, 'linewidth', 2)
% % % hold on 
% % % % Normalize slopes for colormap mapping
% % % minSlope = min(plotSlopes);
% % % maxSlope = max(plotSlopes);
% % % normSlopes = (plotSlopes - minSlope) / (maxSlope - minSlope);
% % % [~, maxidx] = max(normSlopes); 
% % % % Colormap (e.g., jet or parula)
% % % cmap = jet(256);
% % % 
% % % 
% % % for i = 1:length(fittedVals)
% % %     xy = fittedVals{i};  % [2 x timepoints]
% % %     x = xy(1, :);
% % %     y = xy(2, :);
% % % 
% % %     % Skip if invalid
% % %     if any(isnan(x)) || any(isnan(y))
% % %         continue
% % %     end
% % % 
% % %     % Color and alpha based on slope
% % %     % colorIdx = round(normSlopes(i) * (size(cmap, 1) - 1)) + 1;
% % %     % colorIdx = min(max(colorIdx, 1), size(cmap,1));
% % %     % thisColor = cmap(colorIdx, :);
% % %     % thisAlpha = normSlopes(i) ^4;  % Higher slope → more opaque
% % %     % if normSlopes(i) > .3
% % %     % % Use patch to simulate a transparent line
% % %     % for j = 1:(length(x)-1)
% % %     %     patch(...
% % %     %         [x(j), x(j+1)], ...
% % %     %         [y(j), y(j+1)], ...
% % %     %         thisColor, ...
% % %     %         'EdgeColor', [1, 68, 33] ./255, ... %thisColor, ...
% % %     %         'LineWidth', 2, ...
% % %     %         'FaceAlpha', 0, ...
% % %     %         'EdgeAlpha', thisAlpha ...
% % %     %     );
% % %     % end
% % % 
% % %     if i == maxidx %plot the start and end points for the max slope
% % % 
% % %         scatter(x([1,end]), y([1,end]), 30, 'magenta', 'filled')
% % % 
% % %     end
% % % 
% % %     % end
% % % end
% % % 
% % % plot(tim, sig, 'linewidth', 2, 'linestyle', '--', ...
% % %             'Color', [204,85,0]./255    )
% % 
% % end
function [outMap]  = breathTemplates4(rspSig, fs)

oldTim = 1/fs:1/fs:(length(rspSig)/fs); 

newTim = 1/50:1/50:max(oldTim); 
 rspSig2 = interp1(oldTim,rspSig, newTim, 'linear');
rspSig2 = (rspSig2 - mean(rspSig2)) ./ std(rspSig2); %z-scored units!
oldfs = fs; 
fs = 50; 

%median kernal .125s mean kernal of .05s ecog resp filt 

analytic = hilbert(rspSig2); 
analytic = smoothdata(analytic, 1, 'gaussian', 50);
analytic = lowpass(analytic, 1, fs); 
rspPhase = angle(analytic);


peaks = arrayfun(@(x,y) rspPhase(x)<0 & ...
                rspPhase(y)>0 & ...
                rspPhase(x)>-.3 & ...
                rspPhase(y)<.3, ...
                1:length(rspPhase)-1, 2:length(rspPhase));

idx = find(peaks);

idx(idx<70) = []; 
idx(idx>length(rspSig2)-70) = []; 
%move twice to allow hill climbing: 
idx = arrayfun(@(x) x-6 + find(rspSig2(x-10:x+10) == ...
                  max(rspSig2(x-10:x+10)), 1), idx);
idx = arrayfun(@(x) x-6 + find(rspSig2(x-5:x+5) == ...
                  max(rspSig2(x-5:x+5)), 1), idx);

idx(idx<70) = []; 
idx(idx>length(rspSig2)-70) = []; 

% figure;
% plot(rspSig2)
% hold on 
% scatter(idx, zeros(length(idx),1), 5, 'red', 'filled')

smoothRsp = smoothdata(rspPhase, 'gaussian', 50); 
%check for peaks that are spurious (small deviations in the pause)
[test, test2, test3] = arrayfun(@(x) ...
    monoCheck(smoothRsp(x-70:x+70), rspSig2(x-70:x+70), 71), idx);

check = 1 + .005*test<test2;
% figure
% scatter3(test(check), test2(check), test3(check))
% hold on 
% scatter3(test(~check), test2(~check), test3(~check))
% 
% figure
% plot(rspSig2)
% hold on 
% scatter(idx(check), zeros(sum(check),1))
% plot(smoothRsp)
% plot(rspPhase)

idx(~check) =[]; 



%try to fit the 12 param model working out from the peak
breaths = cell(length(idx), 1); 
breathParams = cell(length(idx), 1); 
%col 1: onset Y value
%col 2: onset tim
%col 3: peak Y value
%col 4: peak tim
%col 5: end Y value
%col 6: end tim
%col 7: length (end tim - onset tim)
%col 8: amp (peak Y - avg of two ends)
%col 9: idx of peak in rspSig2
%col10: exhale peak Y value
%col11: exhale peak tim
% breathSS = zeros(length(idx), 1); 
% wi = 1; %working index
parfor ii = 1:length(idx)-1 
    

    curSet = zeros(13, 1); 
%     bStart = wi; 
    try
    
    % figure
    %what is the available range: 

    
    searchPad = [round(fs/4), round(fs/4)]; 

    curidx = idx(ii); %to be adjusted back to inhale onset
    nexidx = idx(ii+1); %to be adjusted back to inhale onset
    
    %bound breath in time from inhale onset to inhale onset: 

    %find this inhale onset: 
    %seek in the prior 3 seconds 
    inSig = smoothdata(rspSig2(curidx-fs*3:curidx), ...
        'gaussian', round(fs )); 

    % subplot 341
    % hold off
    [adj, SSDer] = findInflection(inSig, true, true, ...
        newTim(curidx-fs*3:curidx) ); 
    % title([num2str(ii) ' large win'])
    bStartTmp = curidx - adj + 1; 
    %look at the less smoothed tighter window around the inhale guess:

    % 
    % subplot 342
    % inSig = rspSig2(curidx-fs*3:curidx);  
    % [adj2] = findInflectionFromMid(inSig, adj, 0); 

    %pass 2
    inSig = rspSig2(curidx-fs*3:curidx+round(fs/5));
    inSigRaw = inSig; 
    inSig = smoothdata(inSig, 'gaussian', round(fs/2)); 
    [adj2] = findInflectionFromMid3(inSig, adj, 0, fs, inSigRaw); 
    title(ii)
    bStartTmp = bStartTmp + adj2;

    %pass 3
    % adj = adj - adj2; 
    % inSig = rspSig2(curidx-fs*3:curidx+round(fs/5));
    % inSig = smoothdata(inSig, 'gaussian', round(fs/5)); 
    % [adj2] = findInflectionFromMid3(inSig, adj, 0, fs); 
    adj2 = 0; 
    bStart = bStartTmp + adj2 ;

    

    %find next inhale onset: 
    inSig = smoothdata(rspSig2(nexidx-fs*3:nexidx), 'gaussian', round(fs )); 

    % subplot 343
    % hold off
    [adj, SSDer] = findInflection(inSig,  true, true, ...
        newTim(nexidx-fs*3:nexidx) );
    % title('next inhale')
    nexINHALEtmp = nexidx - adj + 1; %next inhale not to be overstepped! 
    
    %pass 2
    inSig = rspSig2(nexidx-fs*3:nexidx+round(fs/5));
    inSigRaw = inSig; 
    inSig = smoothdata(inSig, 'gaussian', round(fs/2)); 
    [adj2] = findInflectionFromMid3(inSig, adj, 2, fs, inSigRaw); 
    % title(ii+1)
    nexINHALEtmp = nexINHALEtmp + adj2 ;

      %pass 3
    % adj = adj - adj2; 
    % inSig = rspSig2(nexidx-fs*3:nexidx+round(fs/5));
    % inSig = smoothdata(inSig, 'gaussian', round(fs/5)); 
    % [adj2] = findInflectionFromMid2(inSig, adj, 2, fs); 
    adj2 = 0; 
    nexINHALE = nexINHALEtmp + adj2;


% % % 
% % % 
% % %     %record total SS for the breath starting with inhale rise
% % % %     tmp = linspace(rspSig2(bStart), rspSig2(curidx), curidx - bStart+1);
% % % %     SS = sum((tmp - rspSig2(bStart:curidx)).^2);
% % % 
%     subplot(3,4,[9:12])
%     plot(newTim(bStart-fs:nexINHALE+fs), ...
%         rspSig2(bStart-fs:nexINHALE+fs) - rspSig2(bStart))
%     title(['current breath: ' num2str(ii)])
% % % %     hold on 
% % % %     scatter(newTim(curidx), rspSig2(curidx) - rspSig2(bStart), ...
% % % %                     30, 'red', 'filled')
%     xline([newTim(bStart), newTim(nexINHALE)])
%     ylim([-2, 2])

%col 1: onset Y value
curSet( 1) = rspSig2(bStart); 
%col 2: onset tim
curSet( 2) = newTim(bStart); 
%col 3: peak Y value
curSet( 3) = rspSig2(curidx); 
%col 4: peak tim
curSet( 4) = newTim(curidx);
%col 5: end Y value
curSet( 5) = rspSig2(nexINHALE); 
%col 6: end tim
curSet( 6) = newTim(nexINHALE);
%col 7: length (end tim - onset tim)
curSet( 7) = curSet( 6) - curSet( 2); 
%col 8: amp (peak Y - avg of two ends)
curSet( 8) = curSet( 3) - mean([...
                curSet(1), curSet(5)]); 

%col 9: idx of peak in rspSig2
curSet( 9) = idx(ii);
%col10: exhale peak Y value
curSet(10) = min(rspSig2(curidx:nexINHALE));
%col11: exhale peak tim
[~, mini] = min(rspSig2(curidx:nexINHALE));
curSet(11) = newTim(mini + curidx); 



%     plot(newTim(bStart-fs:curidx+fs), tmp - rspSig2(bStart), 'color', ...
%         'blue', 'LineStyle','--', 'LineWidth',3)

  %parameters 1:6 are length parameters for 6 segments
  %          7:12 are slope parameters for 6 segments
  %1: inhale rise
  %2: inhale fall
  %3: inhale pause
  %4: exhale rise
  %5: exhale fall
  %6: exhale pause
% % %     beta0 = [0.2 0.2 0.1 0.2 0.2 0.1, 2.5 -2.5 0 -2.5 2.5 0];  
% % %     lb = [ -5,  -5,  -5,  -5,  -5,  -5,  ...
% % %         2,   -Inf, -1, -Inf,   2, -1];
% % %     ub = [5, 5, 5, 5, 5, 5, ...
% % %         Inf,    -2,  1,    -2, Inf,  1];
% % %     curBreath = rspSig2(bStart:nexINHALE);
% % % 
% % %     curBreath = curBreath - curBreath(1); 
% % % 
% % %     lossFun = @(b) breathModPenaltyWrap(b, ...
% % %         linspace(0,1,length(curBreath)), curBreath, [.1, .01]);
% % %     opts = optimoptions('lsqnonlin', 'Display', 'off');
% % %     [bFit, resnorm] = lsqnonlin(lossFun, beta0, lb, ub, opts);
% % %     breathModPlotter(bFit, linspace(0,1,length(curBreath)), ...
% % %                             newTim(bStart:nexINHALE));
% % %     
% % % 
% % %     
% % %     d = bFit(1:6);   % durations
% % %     d = exp(d);
% % %     d = d / sum(d);
% % %     d = d*length(curBreath) / fs; 
% % % 
% % %     s = bFit(7:12) / (length(curBreath)/fs);
% % %     
% % %     breathParams(ii,1:6) = d; 
% % %     breathParams(ii,7:12) = s;
% % %     
% % %     %breath prominence 
% % % %     breathParams(ii, 13) = 
% % %     
% % % 
% % %     breathIDX(bStart:nexINHALE-1) = ii; 
% % %     breaths{ii} = rspSig(bStart:nexINHALE); 
%     breathSS(ii) = SS / (wi - bStart-1);
    

    catch
        %"breath" likely not prominent enough, not real breath 
        curSet(:) = NaN; 
%         wi = bStart; %keep working from the same point 



    end
    breathParams{ii} = curSet; 

end

test = cat(2, breathParams{:})';


%lastCol: breath count idx
test(:,end+1) = 1:size(test,1); 

% figure; scatter(test(:,7), test(:,8))
% xlabel('length')
% ylabel('amplitude')
lenVals = linspace(-1, 3, 100); 

divideLine = lenVals * -1.3 + 2; 
% hold on 
% plot(lenVals, divideLine)

ampThresh = test(:,7) * -1.2 + 2; 
outTest = test; 
outTest(test(:,8) < ampThresh, :) = []; 
outTest(isnan(outTest(:,1)), :) = [];
% outTest(outTest(:,8) < .5, :) = []; 
outMap = outTest; 
% 
% for ii = 1:size(outTest,1)
%     ii
%     startidx = find(newTim>=outTest(ii,2), 1); 
%     endidx = find(newTim>=outTest(ii,6), 1); 
% 
% 
%     figure
%     plot(newTim(startidx-fs:endidx+fs), rspSig2(startidx-fs:endidx+fs))
%     xline(newTim([startidx, endidx]))
% 
%     title([num2str(ii) 'amplitude: ' num2str(outTest(ii,8))])
% 
% 
% end


% rspPhaseDer = arrayfun(@(x,y) angle(exp(1i*(x-y))), ...
%                 rspPhase(2:length(rspPhase)), ... 
%                 rspPhase(1:length(rspPhase)-1)); 
% rspPhaseUnwrapped = unwrap(rspPhase);
% rspPhaseDer = diff(rspPhaseUnwrapped);

% % % % rspPhaseDer = angle(exp(1i * diff(rspPhase)));
% % % % rspPhaseDerDer = diff(rspPhaseDer); 
% % % % rspPhaseDerDerDer = diff(rspPhaseDerDer); 
% % % % rspPhaseDerDerDerDer = diff(rspPhaseDerDerDer); 
% % % % 
% % % % 
% % % % inOn = find(rspPhaseDerDerDer(2:end) < 0 & rspPhaseDerDerDer(1:end-1)>0);
% % % % 
% % % % figure
% % % % plot(newTim(2:end), rspPhaseDer ./ .1, 'color', 'green')
% % % % hold on 
% % % % plot(newTim(3:end),rspPhaseDerDer ./ .01, 'color', 'blue')
% % % % plot(newTim(4:end),rspPhaseDerDerDer ./ .001, 'color', 'magenta')
% % % % plot(newTim(5:end),rspPhaseDerDerDerDer ./ .0001, 'color', 'cyan')
% % % % plot(newTim, rspSig2, 'color', 'k', 'linewidth', 3)
% % % % plot(newTim, rspPhase, 'color', 'red', 'linewidth', 2)
% % % % scatter(newTim(idx), rspSig2(idx), 30, 'red', 'filled')
% % % % scatter(newTim(inOn+3), rspSig2(inOn+3), 30, 'green', 'filled')
% % % % yline(0)
% % % % 
% % % % 
% % % % idx(idx<200) = []; 
% % % % 
% % % % %some of the peaks identified are heart blips, these can be identified
% % % % %because the min and max values of phase before and after don't make it all
% % % % %the way to -pi to +pi
% % % % 
% % % % negBefore = arrayfun(@(x) x-200 + find(rspPhaseDer(x-200:x)<0, 1, 'last'),...
% % % %                                 idx); 
% % % % 
% % % % 
% % % % 
% % % % 
% % % % 
% % % % figure
% % % % plot(rspPhaseDer) 
% % % % ylim([-1,1])
% % % % hold on 
% % % % plot(rspSig2)
% % % % 
% % % % bigIDX = find(abs(rspPhaseDer) > .2); 
% % % % rspPhaseDer(bigIDX) = arrayfun(@(x) (rspPhaseDer(x-2) + ...
% % % %                                      rspPhaseDer(x+2)) / 2, ... 
% % % %                                      bigIDX);
% % % % 
% % % % 
% % % % 
% % % % 
% % % % 
% % % % 
% % % % figure
% % % % plot(newTim, rspSig2)
% % % % hold on 
% % % % scatter(newTim(negBefore), rspSig2(negBefore), 5, 'green', 'filled')
% % % % 
% % % % 
% % % % %find the peaks in respiration with high precision: 
% % % % peakTims = newTim(idx);
% % % % 
% % % % oldPeakIDX = arrayfun(@(x) find(oldTim>=x, 1), peakTims);
% % % % 
% % % % oldPeakIDX = arrayfun(@(x) x-100 + find(rspSig(x-100:x+100) == ...
% % % %                   max(rspSig(x-100:x+100)), 1), oldPeakIDX);
% % % % 
% % % % 
% % % % figure
% % % % plot(oldTim, rspSig)
% % % % hold on 
% % % % scatter(oldTim(oldPeakIDX), rspSig(oldPeakIDX), 5, 'red', 'filled')
% % % % scatter(newTim(negBefore), rspSig2(negBefore), 5, 'green', 'filled')
% % % % yyaxis right
% % % % plot(newTim, rspPhase)
% % % % plot(newTim(2:end), rspPhaseDer, 'linestyle', '-', 'linewidth', 2)
% % % % ylim([-.1 .1])
% % % % 
% % % % 
% % % % figure
% % % % plot(newTim, rspSig2)
% % % % hold on 
% % % % plot(newTim, rspPhase)
% % % % scatter(newTim(idx), ones(length(idx),1), 3, 'k', 'filled')
% % % % 
% % % % 
% % % % 
% % % % 
% % % % 
% % % % 
% % % % 
% % % % 
% % % % 
% % % % 
% % % % 
% % % % 
% % % % 
% % % % nSamples = 1000;
% % % % paramRanges = [
% % % %     0.1 2.0;  % d1 inhale rise
% % % %      50 500;  % s1
% % % %     0.1 2.0;  % d2 inhale fall
% % % %     -50 -500;  % s2
% % % %     0.0 5.0;  % d3 inhale pause
% % % %      -100 100;  % s3
% % % %     0.1 2.0;  % d4 exhale rise
% % % %     -50 -500;  % s4
% % % %     0.1 2.0;  % d5 exhale fall
% % % %      50 500;  % s5
% % % %     0.0 5.0;  % d6 exhale pause
% % % %     -100 100;  % s6
% % % % ];  % 12 rows total
% % % % 
% % % % % Generate random samples in each parameter range
% % % % params = zeros(nSamples, 12);
% % % % for ii = 1:12
% % % %     lo = paramRanges(ii,1);
% % % %     hi = paramRanges(ii,2);
% % % %     params(:,ii) = lo + (hi - lo) * rand(nSamples,1);
% % % % end
% % % % 
% % % % waveforms = cell(nSamples,1); 
% % % % % wavLengths = zeros(nSamples, 1); 
% % % % for jj = 1:nSamples
% % % % 
% % % %     waveform = [];
% % % %     for ii = 1:6
% % % %         d = round(params(jj, 2*(ii-1)+1) * fs);
% % % %         s = params(jj, 2*(ii-1) + 2) / fs;
% % % %         if ii == 1
% % % %             start_val = 0;
% % % %             end_val = start_val + s*d; 
% % % %         elseif ii ==6
% % % %             end_val = 0; 
% % % %             start_val = waveform(end);
% % % %         else
% % % %             start_val = waveform(end);
% % % %             end_val = start_val + s*d;
% % % %         end
% % % %         segment = linspace(start_val, end_val, d);
% % % %         waveform = [waveform segment];
% % % %     end
% % % % %     leftPad = floor((fs*20 - length(waveform)) / 2);
% % % % %     wavLengths(jj) = length(waveform); 
% % % %     waveforms{jj} = waveform  ; 
% % % % 
% % % % end
% % % % 
% % % % % [~, order] = sort(wavLengths); 
% % % % % figure
% % % % % imagesc(waveforms(order,:))
% % % % 
% % % % 
% % % % nTemplates = length(waveforms);  % waveforms is a cell array
% % % % maxLen = max(cellfun(@length, waveforms));
% % % % nResp = length(rspSig2);
% % % % 
% % % % convLen = 2^nextpow2(nResp + maxLen - 1);
% % % % 
% % % % fftResp = fft(rspSig2, convLen);
% % % % convs = cell(nTemplates, 1);
% % % % 
% % % % % parfor i = 1:nTemplates
% % % % %     tic
% % % % %     wf = waveforms{i}; 
% % % % %     tmp = conv(rspSig2, wf, "same");
% % % % %     convs{i} = tmp; 
% % % % %     toc
% % % % % end
% % % % 
% % % % 
% % % % parfor i = 1:nTemplates
% % % %     wf = waveforms{i};  % A 1×Lw waveform
% % % %     fftWf = fft(wf, convLen);  % MATLAB zero-pads automatically
% % % %     tmp = ifft(fftWf .* fftResp);
% % % %     convs{i} = abs(tmp(maxLen:length(rspSig2)).^2 );
% % % % end
% % % % 
% % % % convs = cat(1, convs{:}); 
% % % % convTim = newTim(maxLen:length(rspSig2)); 
% % % % 
% % % % convs = (convs - mean(convs, 1)) ./ std(convs, [], 1);
% % % % 
% % % % % convs = convs - min(convs,1);
% % % % % convs = convs ./ max(convs,1); 
% % % % figure
% % % % imagesc(convs)
% % % % 
% % % % 
% % % %   % Subtract across templates
% % % % 
% % % % 
% % % % figure
% % % % plot(sum(convs, 2))































end

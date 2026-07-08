function [span, maxPhase, rangVal] = monoCheck(vecIn,vecIn2, peakidx) 
    pos = 0; 
    curi = peakidx; 
    while true 
        if curi == length(vecIn); 
            pos = pos+1; 
            break
        end
        if vecIn(curi+1) > vecIn(curi)
            curi = curi +1;
            pos = pos+1; 
        else
            break
        end
    end
    maxPhase = vecIn(curi); 

    neg = 0; 
    curi = peakidx; 
    while true 
        if curi == 1 
            neg = neg - 1; 
            break
        end
        if vecIn(curi-1) < vecIn(curi)
            curi = curi -1;
            neg = neg+1; 
        else
            break
        end
    end

    span = pos + neg; 

    rangVal = vecIn2(peakidx) - ...
        min(vecIn2(peakidx-5:peakidx+5));

end
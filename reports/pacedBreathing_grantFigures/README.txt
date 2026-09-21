Grant-ready figures - pacedBreathing (KG 260915 + JW 260917)
============================================================
300 dpi, white background, large bold fonts and thick axes so each panel reads when shown small.

JW_breathRate_time.png     JW breath rate over the whole recording, one dot per breath:
                           grey = baseline (first recording file), black = pacing, blue = ATB (final 10 min focused).
KG_JW_RSA_by_length.png    respHRV (within-breath RR max-min) by breath-length bin (medians only, no IQR bars), KG (orange) and JW (blue),
                           dots connected within participant; each participant's ATB mean as a same-colour
                           diamond with no error bars. Bins shown only where n >= 8 good paced breaths.
                           KG uses its published 8-min opening boundary, JW its 6-min (first-file) boundary.
JW_RSA_surface.png         JW length x inhale-volume respHRV surface (local-linear fit on good paced breaths),
                           inhale-volume axis zoomed to 60k-225k; grey = paced breaths, blue = ATB, diamond = ATB mean.
                           inhale-volume axis limited to 50k-250k; grey = paced breaths, blue = ATB, diamond = ATB mean.
JW_ATB_error_surface.png   JW ATB observed-minus-predicted respHRV ('Calibrated respHRV') over the same axes/conventions
                           ATB dots coloured by their own error, grey contours = the paced respHRV surface).

Regenerate: grantFigs.m (MATLAB). It reads the 50-Hz analysis packs
  260915_EEG_NWU_KG_pacedBreathing_pack.mat  and  260917_EEG_NWU_JW_pacedBreathing_pack.mat
(export with batch/pacedBreathing_summaryPack.m; on the lab desktop they are in E:\kg260915\pack and E:\jw260917\pack).
Edit the PACK paths at the top of grantFigs.m to point at wherever the packs live, then run it; PNGs are written
next to the output folder set by OUT.

260917_EEG_NWU_JW - paced breathing respHRV summary (built 2026-09-17)
=====================================================================

260917_EEG_NWU_JW_respHRV_report.html
    Self-contained report (figures embedded). Open in any browser; no network needed.
    Same analysis as the KG (260915_EEG_NWU_KG) report; includes a KG-vs-JW comparison table.

figs/
    F1_timecourse.png              breath rate, inhale volume, RSA, heart rate over the recording; three time-defined
                                   periods shaded; red dashed line = seam between the two recording files
    F2_rsa_vs_length_depth.png     RSA vs breath length and vs inhale volume (paced breaths; final 10 min overlaid in violet)
    F3_rsa_heatmap.png             median RSA by length bin x inhale-volume tertile
    F5_final10_vs_rest.png         final 10 min vs first 6 min vs paced: rate, volume, RSA, HR, regularity, sub-peaks
    F6_inhale_locked_RR.png        inhale-locked RR interval (polarity check)
    F8_rsa_surface.png             length x volume local-linear RSA surface fitted on paced breaths
    F9_final10_prediction_error.png  same surface coloured by mean prediction error for the final 10 min

tables/
    *_perBreath_analysis.csv       one row per breath: period, length, inhale volume, amplitude, RSA, quality flags,
                                   nearSeam / nearSeamWide (seam exclusions)
    *_rsa_by_length_depth.csv      binned medians (length bin x volume tertile)
    *_final10_vs_rest.csv          period comparison with quartiles and tests
    *_final10_vs_paced_matchedLength.csv  final 10 vs paced within matched length bins
    *_final10_predictions.csv      per-breath surface / additive predictions and errors for the final 10 min
    *_blocks_summary.csv           inferred block table (descriptive only; periods are defined by clock time)
    *_stats.json                   every number quoted in the report (incl. segments / seam / period settings)
    *_summary.mat                  MATLAB workspace of the analysis
    sensitivity_pre810/            same outputs with the opening period taken to 13.5 min (ZLP_PRE_SEC=810)

Definitions
    Periods by clock time on the stitched recording: first 6.02 min (= the first recording file) = audiobook;
    last 10 min = focused breathing; everything between = paced (incl. ~7 min instructions/practice).
    Two recording files stitched end to end (CSCn.ncs 6.02 min + CSCn_0001.ncs 79.26 min, 55.6 s stop between);
    breaths within 10 s of the seam are excluded from every statistic.
    RSA = within-breath RR max - min (ms), from processECG / flagBadBreaths (good breaths only).
    Depth predictor = breathMetrics inhale volume (bm_inhaleVolumesRaw, raw units); amplitude is a descriptor only.
    Clean breath = good QC, one flow peak (nSubPeaks <= 1) and local period CV < 0.20.

Regenerate
    zelanoLabPreprocessing (commit 7fa8a24): batch/pacedBreathing_summaryPack.m (pack from the final preproc .mat,
    env ZLP_PACK_ID=260917_EEG_NWU_JW), then batch/pacedBreathing_respHRV_summary.m with env ZLP_PACK=<pack.mat>,
    ZLP_SUMOUT=<output folder>, ZLP_PRE_SEC=361, ZLP_FINAL_SEC=600.
    Preprocessed final: <session>\preProc\260917_EEG_NWU_JW_pacedBreathingpreproc.mat  (pipelines/pacedBreathingPreProc_main.m)

Copies
    GitHub  zelanoLabPreprocessing/reports/260917_EEG_NWU_JW_respHRV/   (this bundle minus the .mat files)
    Lab desktop  E:\jw260917\report\
    Lab server   R:\Neurology\Zelano_Lab\Lab_Common\Adam\Dupi_processing\260917_EEG_NWU_JW\pacedBreathing\respHRV_report\

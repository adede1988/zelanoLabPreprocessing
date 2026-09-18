260915_EEG_NWU_KG - paced breathing respHRV summary (built 2026-09-15, report version 5)
=======================================================================================

260915_EEG_NWU_KG_respHRV_report.html
    Self-contained report (figures embedded). Open in any browser; no network needed.
    Same content as the claude.ai artifact "KG Paced Breathing RSA" (version 5).

figs/
    F1_timecourse.png              breath rate, inhale volume, RSA over the recording; three time-defined periods shaded
    F2_rsa_vs_length_depth.png     RSA vs breath length and vs inhale volume (paced breaths; final 10 min overlaid in violet)
    F3_rsa_heatmap.png             median RSA by length bin x inhale-volume tertile
    F5_final10_vs_rest.png         final 10 min vs first 8 min vs paced: rate, volume, RSA
    F6_inhale_locked_RR.png        inhale-locked RR interval (polarity check)
    F8_rsa_surface.png             length x volume local-linear RSA surface fitted on paced breaths
    F9_final10_prediction_error.png  same surface coloured by mean prediction error for the final 10 min

tables/
    *_perBreath_analysis.csv       one row per breath: period, length, inhale volume, amplitude, RSA, quality flags
    *_rsa_by_length_depth.csv      binned medians (length bin x volume tertile)
    *_final10_vs_rest.csv          period comparison with quartiles and tests
    *_final10_vs_paced_matchedLength.csv  final 10 vs paced within matched length bins
    *_final10_predictions.csv      per-breath surface predictions and errors for the final 10 min
    *_blocks_summary.csv           inferred block table (descriptive only; periods are defined by clock time)
    *_stats.json                   every number quoted in the report
    *_summary.mat                  MATLAB workspace of the analysis

Definitions
    Periods by clock time: first 8 min = audiobook + instructions; last 10 min = focused breathing; everything between = paced.
    RSA = within-breath RR max - min (ms), from processECG / flagBadBreaths (good breaths only).
    Depth predictor = breathMetrics inhale volume (bm_inhaleVolumesRaw, raw trace units); amplitude is reported only as a descriptor.

Regenerate
    zelanoLabPreprocessing: batch/pacedBreathing_summaryPack.m (pack from the final preproc .mat; named
    kg260915_summaryPack.m when this report was built at commit 277bbb8), then
    batch/pacedBreathing_respHRV_summary.m (was kg260915_respHRV_summary.m) with env ZLP_PACK=<pack.mat>,
    ZLP_SUMOUT=<output folder>, ZLP_PRE_SEC=480, ZLP_FINAL_SEC=600.
    Preprocessed final: <session>\preProc\260915_EEG_NWU_KG_pacedBreathingpreproc.mat  (pipelines/pacedBreathingPreProc_main.m)

Copies
    GitHub  zelanoLabPreprocessing/reports/260915_EEG_NWU_KG_respHRV/   (this bundle minus the .mat)
    Lab desktop  E:\kg260915\report\
    Lab server   R:\Neurology\Zelano_Lab\Lab_Common\Adam\Dupi_processing\260915_EEG_NWU_KG\pacedBreathing\respHRV_report\
    Web  https://claude.ai/artifact/1oKEZAPPow4gBUwff65s11  (sign-in required)

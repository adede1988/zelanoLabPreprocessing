# respiratorySweepAnalysis

Analysis and figures for the Zelano Lab respiratory pace × depth sweep sessions. It ingests
preprocessed finals from the `zelanoLabPreprocessing` pipeline (task `pacedBreathing`) and produces the
respiratory-HRV statistics, per-session reports and grant figures. See `CLAUDE.md` for the full guide.

## Layout

| Path | What |
|---|---|
| `exportPack.m` | preprocessed final → compact 50 Hz analysis pack (the only step that reads a final) |
| `respHRV_summary.m` | one pack → stats JSON, per-breath/comparison CSVs, figures F1–F9 |
| `grantFigures.m` | KG + JW packs → the four grant-ready PNGs |
| `reports/<id>_respHRV/` | self-contained HTML report + figures + tables per session |
| `reports/grantFigures/` | the grant PNGs + README |

## Run

```matlab
% 1) make a pack from a preprocessed final (set the path or run inside zelanoLabPreprocessing)
setenv('ZLP_FINAL', 'R:\...\260917_EEG_NWU_JW\preProc\260917_EEG_NWU_JW_pacedBreathingpreproc.mat');
setenv('ZLP_PACK_OUT', 'pack'); run exportPack.m

% 2) build the per-session summary + figures
setenv('ZLP_PACK', 'pack/260917_EEG_NWU_JW_pacedBreathing_pack.mat');
setenv('ZLP_SUMOUT', 'reports/260917_EEG_NWU_JW_respHRV');
setenv('ZLP_PRE_SEC', '361'); setenv('ZLP_FINAL_SEC', '600'); run respHRV_summary.m

% 3) grant figures from both packs
setenv('ZLP_PACK_KG', 'pack/260915_EEG_NWU_KG_pacedBreathing_pack.mat');
setenv('ZLP_PACK_JW', 'pack/260917_EEG_NWU_JW_pacedBreathing_pack.mat');
setenv('ZLP_GRANT_OUT', 'reports/grantFigures'); run grantFigures.m
```

Requires MATLAB with the Statistics and Signal Processing toolboxes. Packs and other `*.mat` are
git-ignored (regenerable); report figures and tables are committed.

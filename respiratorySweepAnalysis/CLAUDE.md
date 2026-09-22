# CLAUDE.md — `respiratorySweepAnalysis`

## What this repo is

Analysis and figures for the Zelano Lab's **respiratory pace × depth sweep** sessions: a single
continuous EEG_breathing recording per participant made of an opening audiobook/baseline period, a long
stretch of paced breathing swept across a range of paces and depths, and a closing focused-breathing
("attention-to-breath", ATB) period. The scientific question is how **respiratory HRV (respHRV)** — the
within-breath swing of the heart's RR interval — depends on breath length and inhale volume, and whether
the focused-breathing period carries more respHRV than the breathing pattern alone predicts.

This repo does **not** preprocess raw data. It **ingests preprocessed finals** produced by the
`zelanoLabPreprocessing` pipeline (task `pacedBreathing`), reduces each to a compact pack, and builds the
statistics, per-session report and grant figures from the packs. It is self-contained: given a pack (or a
final's path via `ZLP_FINAL`) it runs without the preprocessing repo on the path.

Requirements: MATLAB (developed on R2024b/R2026a) with the **Statistics and Machine Learning** and
**Signal Processing** toolboxes. No Python.

---

## Pipeline

```
preprocessed final  (<id>_pacedBreathingpreproc.mat, ~1.5 GB, from zelanoLabPreprocessing)
  │   exportPack.m            READ-ONLY on the final; decimates to a 50 Hz pack (+ behDat/blocks CSVs)
  ▼
<id>_pacedBreathing_pack.mat   (~18 MB; the unit every analysis below runs on)
  │   respHRV_summary.m       one session -> stats JSON, per-breath CSV, tables, figures F1..F9
  │   grantFigures.m          KG + JW packs -> the four grant-ready PNGs
  ▼
reports/<id>_respHRV/          self-contained HTML report + figures/tables (built by hand from F1..F9)
reports/grantFigures/          the grant PNGs + their README
```

### `exportPack.m` — final → pack (the only step that touches a preprocessed final)
- Locate the final: set **`ZLP_FINAL`** to its full path (preferred, keeps this repo independent), or run
  inside `zelanoLabPreprocessing` where `applyParams('pacedBreathing','main')` + **`ZLP_PACK_ID`** resolve it.
- **`ZLP_PACK_OUT`** = output folder (default `<pwd>/pack`).
- Writes `<id>_pacedBreathing_pack.mat` (v7.3) with: `fsPack` (50), `t`, `rsp` (chosen trace, rspIDX/rspFlip
  applied), `RRint`, `heartBeats`, `bmObj`, `blocks`, `blockInference`, `segments` (recording seams, if any),
  `behDat` (table), `labels`, `sessID`, `fs` (500), `nSamples`, `durMin`, and QC scalars
  (`ecgSkipped`, `badChans`, `blinkRemoval`, `rspIDX`, `rspFlip`, `bmConditioning`). Also `<id>_…_behDat.csv`
  and `<id>_…_blocks.csv`.

### `respHRV_summary.m` — pack → stats + figures (no EEG needed)
- **`ZLP_PACK`** = path to the pack; **`ZLP_SUMOUT`** = output folder (default `<packdir>/summary`).
- **`ZLP_PRE_SEC`** / **`ZLP_FINAL_SEC`** = the opening and closing period lengths in seconds (defaults
  480 / 600). Non-numeric values error; the two periods must fit inside the recording.
- Writes `F1_timecourse.png` … `F9_final10_prediction_error.png`, `<id>_stats.json`,
  `<id>_perBreath_analysis.csv`, and the binned/comparison/prediction CSVs, plus `<id>_summary.mat`.

### `grantFigures.m` — KG + JW packs → grant PNGs
- **`ZLP_PACK_KG`** / **`ZLP_PACK_JW`** = the two pack paths (default `<pwd>/pack/…`); **`ZLP_GRANT_OUT`** =
  output folder (default `<pwd>/reports/grantFigures`). Writes the four PNGs (see `reports/grantFigures/`).

The two per-session HTML reports under `reports/` were assembled by hand from the F1..F9 PNGs; the report
templates and the base64 image-injection helper are not in this repo (they lived in the build session's
scratchpad). Regenerating the figures is the reproducible part; re-embedding them into the HTML is manual.

---

## Definitions (used across all scripts)

- **respHRV (ms)** — per breath, the maximum minus the minimum interpolated RR interval inside the breath
  (inhale onset → next inhale onset). This is `RR_max_min` from the preprocessing pipeline's `flagBadBreaths`,
  in ms. It rises with breath length by construction (a longer breath samples more of the cardiac cycle);
  that is the intended physiological quantity, not an artifact. Earlier drafts called it RSA.
- **breath length (s)** — the inhale-to-inhale period (`bmObj` col 7).
- **depth = inhale volume** — the breathMetrics inhale volume on the raw respiration trace
  (`bm_inhaleVolumesRaw`, raw sensor units), the integral of inspiratory flow over the inhale. Proportional
  to volume only if the sensor is linear; fine for within-session comparisons, **not comparable in absolute
  units across participants** (different belts/gains). Peak-to-trough **amplitude** (`bmObj` col 8) is kept
  in the tables as a descriptor only. `respHRV_summary.m` falls back to amplitude if the volume column is
  absent.
- **periods (by clock time, not the pipeline's inferred blocks)** — `pre` (opening `ZLP_PRE_SEC` =
  audiobook/baseline, "Base"), `final10` (closing `ZLP_FINAL_SEC` = focused breathing, "ATB"), `paced`
  (everything between). The inferred `blocks` table is carried in the pack for reference but is **not** used
  to group anything.
- **good breath** — `goodBreath == 1` from `flagBadBreaths`, additionally excluding breaths flagged
  `nearSeam` and any within 10 s of a recording seam (multi-file acquisitions).
- **clean breath** — good, single-peaked (`nSubPeaks <= 1`) and regular (`localPeriodCV < 0.20`).

## Methods

- Robust linear models (`fitlm`, bisquare) of respHRV on centred log length and log depth: additive,
  interaction, length-only, depth-only, clean-subset, all-paced.
- A **local-linear kernel surface** (Gaussian kernel, bandwidth 0.35 SD in standardised log length / log
  depth) of respHRV over the paced breaths, and the kernel-weighted mean **prediction error** of the ATB
  breaths against that paced-fitted surface ("Calibrated respHRV").
- Period comparisons: Wilcoxon rank-sum / sign-rank, Cliff's delta, matched-length contrasts, Spearman
  correlations, inhale-locked RR (polarity + shape check).

---

## Input data contract (what a preprocessed final / pack provides)

The pack mirrors the fields `respHRV_summary` and `grantFigures` read; a final has these plus the full EEG.

- `behDat` (table, one row per detected breath): `finalOnset` (sample @ `fs`), `length` (s), `amp`,
  `bm_inhaleVolumesRaw`, `goodBreath`, `RR_max_min` (s), `nSubPeaks`, `localPeriodCV`, `condition`,
  `nearSeam`, and the other `bm_*` breathMetrics columns.
- `RRint` — interpolated RR-interval channel (in the pack, decimated to 50 Hz as `RRint`); `fs` = 500.
- `bmObj` `[nBreaths × 14]`, `blocks` / `blockInference` (inferred pace blocks, reference only),
  `segments` (recording-seam table, present only for multi-file acquisitions), `sessID`, `nSamples`.

If the upstream field layout changes, update the readers here — this repo assumes the layout above.

---

## Sessions and where the data live

| id | recording | notes |
|---|---|---|
| `260915_EEG_NWU_KG` | 126.7 min, one file | first sweep participant; opening period 8 min |
| `260917_EEG_NWU_JW` | 85.3 min, two files (56-s stop at 6.0 min) | opening period = first file (6.0 min); segments/seam handled |

Preprocessed finals and packs are lab data, not in this repo. On the lab desktop the packs are at
`E:\kg260915\pack\` and `E:\jw260917\pack\`; the finals are on the server under
`R:\…\AllStudyData\EEGbreathing\<id>\preProc\`. Reports here are committed (self-contained HTML + PNG +
CSV/JSON); packs and `*.mat`/`*.summary.mat` are git-ignored (regenerable, large).

---

## Provenance

Built inside `zelanoLabPreprocessing` (task `pacedBreathing`) and split out here as an independent repo.
The preprocessing that produces the finals lives in that repo: `tasks/pacedBreathing/`,
`pipelines/pacedBreathingPreProc_main.m`, and the shared signal core.

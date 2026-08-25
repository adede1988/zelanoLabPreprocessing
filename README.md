# zelanoLabPreprocessing

MATLAB preprocessing pipelines for the Zelano Lab's respiration + scalp‑EEG / intracranial‑EEG
(+ ECG) experiments. One shared signal‑processing core serves **four tasks** —
`breathingTask`, `cueTask`, `threshTask`, and `O15` — differing only in how the raw data
are laid out and how events (photodiode/TTL) and behavior are parsed.

This repository is a **self‑contained copy of the preprocessing code**: every function the
four pipelines depend on, including the handful pulled in from the lab's `slowBreathing`
repo, is vendored here (see [`external/`](external/)). It does **not** contain data. The
session list and all per‑session parameters live in `dataTracking.xlsx` (the lab's source of
truth), which you supply locally — it is intentionally git‑ignored.

---

## What a pipeline produces

```
RAW  (Neuralynx .mat + behavioral .mat/.csv)
  │   <task>_makeOutDat.m         (breathing / cue / thresh — parse photodiode → TTLs,
  │                                load behavior, stitch runs)   [O15 skips this step]
  ▼
<root>/<id>/preProc/<id>_<task>PreProc.mat     ← intermediate ("raw" outDat)
  │   <task>PreProc_main.m        (applyParams → shared pipeline → task‑specific onsets/behavior)
  ▼
<root>/<id>/preProc/<id>_<task>preproc.mat     ← FINAL (the file you analyse)
```

The final `.mat` holds one struct (`outDat`, or `chanDat` for older breathing files) with:

- `data` `[nChan × nSamp]` at **`fs = 500 Hz`**, addressed by `labels` (index channels **by label
  string**, never by fixed position — except the 32‑channel scalp‑EEG montage, which occupies
  rows 1–32 when `hasEEG`).
- Derived channels appended by the pipeline: bipolar macro pairs `macBP1..N`, `blinkIndicator`,
  `badTS`, `interpChan`, `spikeCleanVec`, and (breathing) `targTrace` / `RRint`.
- `behDat` — a per‑sniff (cue/thresh/O15) or per‑breath (breathing) **table**; EEG coords
  (`eegLocs`), surface Laplacian (`dataLap`), and breathing extras (`bmObj`, `heartBeats`,
  `baseEmotion`) as applicable.

### Signal‑processing core (shared, identical across all four tasks)

1. **`downsample_data`** — resample to 500 Hz; 4th‑order IIR high‑pass 0.03 Hz + low‑pass ≈Nyquist.
   *Line‑noise notch filtering (60/120/180 Hz) is intentionally NOT applied — downstream
   analyses handle line noise themselves.*
2. **`preprocess_eeg`** *(if `hasEEG`)* — validate the 32‑ch montage, attach coordinates,
   detect/interpolate noisy channels, remove eye‑blinks (ICA), compute a Perrin surface Laplacian.
3. **`preprocess_macros`** — bipolar re‑reference adjacent depth/strip contacts → `macBP*`,
   optional targeted‑ICA spike cleaning.
4. **Respiration / onsets** — whole‑trace respiration features, sniff detection from TTLs,
   phase‑refined onsets (`finalOnset`); breathing additionally derives per‑breath `bmObj`,
   aligns paced target traces, and computes ECG beats / HRV (`RRint`).

`behDat` carries a `manOnset` column (NaN placeholder) reserved for later manual‑onset QC.

---

## Repository layout

| Folder | Contents |
|---|---|
| `config/` | `labPaths.m` (all machine‑specific paths), `applyParams.m` / `writeParams.m` / `writePreProcX.m` (read/write the tracking sheet), `eegLocs_standard_coords.csv` |
| `pipelines/` | the deliverable entry points: `preprocessAll.m` + the four `*PreProc_main.m` |
| `pipelines/makeOutDat/` | the raw→intermediate ingestion scripts (breathing / cue / thresh) |
| `shared/` | the task‑shared signal core + assembly + EEG/spike/onset helpers |
| `tasks/breathing/` `tasks/cue/` `tasks/thresh/` `tasks/O15/` | each task's raw loader, behavior‑table builder, and task‑specific helpers |
| `external/slowBreathing/` | the five `slowBreathing` functions the breathing pipeline uses (vendored) |
| `external/breathMetrics/` | the BreathMetrics respiration toolbox (vendored from the lab fork `qhyang42/breathmetrics`, commit `9791153`, 2026‑08‑03; BSD-style academic licence per the upstream `zelanolab/breathmetrics` README/publication — Noto et al. 2018, *Chemical Senses*). Used by `shared/segmentBreaths_breathMetrics.m` for per-breath segmentation in every breath-based task. |

---

## Requirements

- **MATLAB** (developed on R2024b–R2026a) with toolboxes: **Signal Processing**, **DSP System**,
  **Statistics and Machine Learning**, **Parallel Computing**.
- **EEGLAB** on the path (used for `runica` during blink/spike ICA). Point `labPaths().eeglab`
  at your install.
- The four `slowBreathing` functions are vendored under `external/` — no separate clone needed.

`closed-loop-respiration` is **not** a code dependency; the breathing pipeline only *writes* a
per‑breath CSV, which this repo directs to a local `processedBehavior/` folder.

---

## Setup & running

1. **Point `config/labPaths.m` at your machine.** It auto‑detects by Windows `USERNAME`; to add a
   machine, add a `case` to the switch (or drop an untracked `labPaths_local.m` returning the four
   base fields: `codePre`, `eeglab`, `labCommon`, `gdrive`). Unknown machines error with a
   copy‑pasteable template. All repo‑internal code paths (repo root, `eegLocs` csv, vendored
   `slowBreathing`) are derived automatically from this file's location.

2. **Provide `dataTracking.xlsx`** (header row 2, data from row 3). `applyParams` reads it as the
   single source of truth for the session list and every per‑session parameter (respiration
   channel/polarity, `hasEEG`, spike‑clean settings, sniff windows, ECG beat spec, …). Put it at
   `labPaths().adminXlsx` or a repo‑local copy.

3. **Run.**
   ```matlab
   preprocessAll                                 % REPORT only: what's pending
   setenv('PREPROCESS_RUN','1'); preprocessAll   % run every pending task
   ```
   or run one task's pipeline directly, e.g. `cueTask_makeOutDat` then `cueTaskPreProc_main`.

   Sessions whose `paramSource` is `guess` deliberately halt for interactive verification
   (`paramCheck` figures + an onset gate); once you've inspected the figures, set the row to
   `curated` and re‑run.

---

## Adding a new task

See **[`TUTORIAL_adding_a_task.md`](TUTORIAL_adding_a_task.md)** for a step‑by‑step guide to
standing up a fifth task by writing only the task‑specific pieces and reusing the shared core.

## License / attribution

Zelano Lab, Northwestern University. Research code shared for transparency and reuse.

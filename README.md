# zelanoLabPreprocessing

MATLAB preprocessing pipelines for the Zelano Lab's respiration + scalp‑EEG / intracranial‑EEG
(+ ECG) experiments. One shared signal‑processing core serves **eight tasks** —
`breathingTask`, `cueTask`, `threshTask`, `O15`, `pacedBreathing`, `EmotionalMovieTask`,
`alternating6Blocks`, and `breathingTasks_separate` — differing only in how the raw data
are laid out and how events (photodiode/TTL) and behavior are parsed.

This repository is a **self‑contained copy of the preprocessing code**: every function the
pipelines depend on, including the BreathMetrics toolbox (a pinned fork), is vendored here
(see [`external/`](external/)). It does **not** contain data. The
session list and all per‑session parameters live in `dataTracking.xlsx` (the lab's source of
truth), which you supply locally — it is intentionally git‑ignored.

---

## What a pipeline produces

```
RAW  (Neuralynx .mat + behavioral .mat/.csv)
  │   <task>_makeOutDat.m         (breathing / cue / thresh / movie / alt6 — parse photodiode → TTLs,
  │                                load behavior, stitch runs)   [O15 / paced / sep skip this step]
  ▼
<root>/<id>/preProc/<id>_<task>PreProc.mat     ← intermediate ("raw" outDat)
  │   <task>PreProc_main.m        (applyParams → shared pipeline → task‑specific onsets/behavior)
  ▼
<root>/<id>/preProc/<id>_<task>preproc.mat     ← FINAL (the file you analyse)
```

The final `.mat` holds one struct (`outDat`, or `chanDat` for breathingTask finals) with:

- `data` `[nChan × nSamp]` at **`fs = 500 Hz`**, addressed by `labels` (index channels **by label
  string**, never by fixed position — except the 32‑channel scalp‑EEG montage, which occupies
  rows 1–32 when `hasEEG`).
- Derived channels appended by the pipeline: bipolar macro pairs `macBP1..N`, `blinkIndicator`,
  `badTS`, `interpChan`, `spikeCleanVec`, `targTrace` (breathingTask) and `RRint` (breath‑based
  tasks with ECG).
- `behDat` — a per‑sniff (cue/thresh/O15) or per‑breath (breath‑based tasks) **table**; EEG coords
  (`eegLocs`), surface Laplacian (`dataLap`), and breath extras (`bmObj`, `bmFeatures`,
  `heartBeats`, `baseEmotion`) as applicable.

### Signal‑processing core (shared across all tasks — `shared/runSharedCore.m`)

1. **`downsample_data`** — resample to 500 Hz; 4th‑order IIR high‑pass 0.03 Hz + low‑pass ≈Nyquist.
   *Line‑noise notch filtering (60/120/180 Hz) is intentionally NOT applied — downstream
   analyses handle line noise themselves.*
2. **`preprocess_eeg`** *(if `hasEEG`)* — validate the 32‑ch montage, attach coordinates,
   detect/interpolate noisy channels, remove eye‑blinks (ICA), compute a Perrin surface Laplacian.
3. **`preprocess_macros`** *(if `hasMacros`)* — bipolar re‑reference adjacent depth/strip contacts
   → `macBP*`, optional targeted‑ICA spike cleaning.
4. **Respiration / onsets** (after the core, per task) — whole‑trace respiration features, sniff
   detection from TTLs, phase‑refined onsets (`finalOnset`); the breath‑based tasks instead segment
   every breath with the LOCKED `shared/segmentBreaths_zlp.m` engine (spec:
   [`customBreathMetrics.md`](customBreathMetrics.md)) into `bmObj` / `bmFeatures`, and compute ECG
   beats / HRV (`RRint`); breathingTask also aligns paced target traces.

`behDat` carries a `manOnset` column (NaN placeholder) reserved for later manual‑onset QC.

---

## Repository layout

| Folder | Contents |
|---|---|
| `config/` | `labPaths.m` (all machine‑specific paths), `applyParams.m` / `writeParams.m` / `setPreProcX.m` (+ wrappers `writePreProcX.m` / `clearPreProcX.m`) / `writeSheetSep.m` (read/write the tracking sheet), `sepConditionInfo.m`, `eegLocs_standard_coords.csv` |
| `pipelines/` | the deliverable entry points: `preprocessAll.m` + one `*PreProc_main.m` per task |
| `pipelines/makeOutDat/` | the raw→intermediate ingestion scripts (breathing / cue / thresh / emotionalMovie / alternating6Blocks) |
| `shared/` | the task‑shared signal core (`runSharedCore`) + assembly + EEG/spike/onset helpers, the breath engine (`segmentBreaths_zlp`) and the breath‑type stage helpers (per‑breath table, ECG/HRV) |
| `tasks/breathing/` `tasks/cue/` `tasks/thresh/` `tasks/O15/` `tasks/pacedBreathing/` `tasks/emotionalMovie/` `tasks/alternating6Blocks/` `tasks/breathingSeparate/` | each task's raw loader, behavior‑table builder, and task‑specific helpers |
| `batch/` | reusable QC / maintenance tools (e.g. `probeMontage.m` to verify a new LoadData channel map) — not pipeline steps |
| `external/breathMetrics/` | the BreathMetrics respiration toolbox (vendored from the lab fork `qhyang42/breathmetrics`, commit `9791153`, 2026‑08‑03; BSD-style academic licence per the upstream `zelanolab/breathmetrics` README/publication — Noto et al. 2018, *Chemical Senses*). Driven, unmodified, by `shared/segmentBreaths_zlp.m`, which computes every breath‑based task's per‑breath features with it. |

---

## Requirements

- **MATLAB** (developed on R2024b–R2026a) with toolboxes: **Signal Processing**, **DSP System**,
  **Statistics and Machine Learning**, **Parallel Computing**.
- **EEGLAB** on the path (used for `runica` during blink/spike ICA). Point `labPaths().eeglab`
  at your install.
- The BreathMetrics toolbox is vendored under `external/` — no separate clone needed.

`closed-loop-respiration` / `experiment_EEGsync` are **not** code dependencies, but
`breathingTask_makeOutDat` reads each session's behavioral CSV from their `processedBehavior\`
folders under `labPaths().codePre` (written by `tasks/breathing/tidyImport_waveExp_matlab.m` from the
psychopy `mindfulBreathing` CSV). The pipelines *write* their own per‑breath CSVs to a local
`processedBehavior/` folder.

---

## Setup & running

1. **Point `config/labPaths.m` at your machine.** It auto‑detects by Windows `USERNAME`; to add a
   machine, add a `case` to the switch (or drop an untracked `labPaths_local.m` returning the four
   base fields: `codePre`, `eeglab`, `labCommon`, `gdrive`, plus optionally `fieldtrip` and an
   `adminXlsx` override to relocate the tracking sheet). Unknown machines error with a
   copy‑pasteable template. All repo‑internal code paths (repo root, `eegLocs` csv) are derived
   automatically from this file's location.

2. **Provide `dataTracking.xlsx`** (header row 2, data from row 3). `applyParams` reads it as the
   single source of truth for the session list and every per‑session parameter (respiration
   channel/polarity, `hasEEG`, spike‑clean settings, sniff windows, ECG beat spec, …). Put it at
   `labPaths().adminXlsx` (the lab master under `Admin\Data\`). A copy at the repo root
   (`<repo>\dataTracking.xlsx`, git‑ignored) is only a fallback and always raises a
   `<caller>:localFallback` warning.

3. **Run.**
   ```matlab
   preprocessAll                                 % REPORT only: what's pending
   setenv('PREPROCESS_RUN','1'); preprocessAll   % run every pending task
   ```
   or run one task's pipeline directly, e.g. `cueTask_makeOutDat` then `cueTaskPreProc_main`.
   `preprocessAll` runs breathingTask / cueTask / threshTask / O15 / pacedBreathing; run the
   EmotionalMovieTask, alternating6Blocks and breathingTasks_separate pipelines directly.

   Sessions whose `paramSource` is `guess` deliberately halt for interactive verification
   (`paramCheck` figures + an onset gate); once you've inspected the figures, set the row to
   `curated` and re‑run.

---

## Adding a new task

The newest example is `pacedBreathing` (2026-09-15): a marker-free EEG_breathing recording whose block
structure is inferred from the breaths themselves (`tasks/pacedBreathing/inferBlocks_pacedBreathing.m`) — see
`CLAUDE.md` section 1 and 6.5 for what it stores.

See **[`TUTORIAL_adding_a_task.md`](TUTORIAL_adding_a_task.md)** for a step‑by‑step guide to
standing up a new task by writing only the task‑specific pieces and reusing the shared core.

## License / attribution

Zelano Lab, Northwestern University. Research code shared for transparency and reuse.

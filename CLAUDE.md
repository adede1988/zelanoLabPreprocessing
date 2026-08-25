# CLAUDE.md — `zelanoLabPreprocessing`

## What this repo is

MATLAB preprocessing pipelines for the Zelano Lab's respiration + scalp‑EEG / intracranial‑EEG (+ ECG)
experiments. One shared signal‑processing core serves every task; tasks differ only in how raw data are laid
out and how events (photodiode/TTL) and behavior are parsed. The repo is **self‑contained** (the
`slowBreathing` functions it needs are vendored under `external/`) and contains **no data**. The session list
and every per‑session parameter live in **`dataTracking.xlsx`** (git‑ignored) — nothing is hard‑coded in
scripts.

Companion documents:
- `README.md` — what the pipelines produce, repo layout, requirements, how to run.
- `TUTORIAL_adding_a_task.md` — the recipe for adding a task while leaving the shared core untouched.
- `currentState.md` — the authoritative record of the **July 2026 full reprocessing run**: what was and
  wasn't reprocessed and why, and where the pre‑edit backups live (`E:\reprocBackup\`).
- `Tasks_<date>.md` — the current work order; `guessSessions.md`, `runReport_<date>.md`,
  `inventory_<date>.csv` are its running outputs.

---

## 1. Tasks

| canon name (`P.task`) | sheet `Task` values (matched case‑ and whitespace‑insensitively) | what's unique |
|---|---|---|
| `breathingTask` | `breathing tasks`, `breathingTasks`, `waveBreathing` | breathing blocks; **per‑breath table**, **ECG/HRV**, **paced target‑trace alignment**, **emotion ratings**. The richest task and the template for every new breath‑based task. |
| `cueTask` | `odor cue task` | odor cue / sniff / response TTLs; hit/miss/cr/fa behavior |
| `threshTask` | `threshold` | PEA threshold; 45 single‑sniff trials |
| `O15` | `O15` | loads raw directly (no `makeOutDat`); photodiode TTLs via `detect_ttls_O15`. `O15_noTTLs_skip` / `O15_corrupted` are deliberately unmatched. |

Being added (see the current task file): `EmotionalMovieTask`, `alternating6Blocks`, and
`breathingTasks_separate` (one session = several sheet rows/recordings whose `Task` is a condition name:
`audioBook`/`audiobook`, `distractedBreathing`, `focusedBreathing`, `sleep`, `sleepWithOdor`, `restingBaseline`).

The name mappings live in `config/applyParams.m` (`taskKey` caller → canon, `canonTask` sheet → canon,
`taskCallerKey` canon → `P.task`) and are mirrored in `pipelines/preprocessAll.m`.

---

## 2. Data flow, filenames, session folders

```
RAW  (Neuralynx/Atlas export + behavioral .mat/.csv)
  │   <root>\<id>\*LoadData*.m         (per session × task: raw export → extracted raw .mat)
  ▼
<root>\<id>\raw\raw_<task>\...                      ← EXTRACTED RAW
  │   <task>_makeOutDat.m               (breathing / cue / thresh — parse photodiode → TTLs,
  │                                      load behavior, stitch runs)   [O15 skips this step]
  ▼
<root>\<id>\preProc\<id>_<task>PreProc.mat           ← INTERMEDIATE ("raw" outDat)
  │   <task>PreProc_main.m              (applyParams → assembleOutDat → shared core → task onsets/behavior)
  ▼
<root>\<id>\preProc\<id>_<task>preproc.mat           ← FINAL (the file that gets analysed)
```

- **Session folder layout** (`<root>\<id>\`): `AtlasData\` (raw export), the `*LoadData*.m` script(s),
  `raw\raw_<task>\`, `preProc\`, and a figure folder under `labPaths().figPath`. When adding a participant,
  copy the layout of an already‑extracted participant of the same `Type` — never invent a new one.
- **Windows / case‑insensitive quirk (intentional, don't "fix").** The intermediate (`…PreProc.mat`) and the
  final (`…preproc.mat`) differ only in case, so they are the **same file** — `_main` overwrites the
  intermediate in place and a fully processed session has one file. Take the exact per‑task strings from the
  `save(...)` line of each `*PreProc_main.m` (legacy names exist, e.g. thresh `<id>_PEA_threshold_preproc.mat`).
- O15 loads `<id>\raw\raw_O15\raw_O15.mat` directly.
- **Top‑level variable** is `outDat`; older breathing finals used `chanDat` or `out`. Load robustly:
  ```matlab
  s = load(finalPath); fn = fieldnames(s); outDat = s.(fn{1});
  ```
- A file is **fully processed** iff `outDat.moreThan1` exists (and, since July 2026, `behDat.manOnset`;
  breathing additionally `bmObj` / `baseEmotion`).
- The breathing pipeline also writes a per‑breath **processed‑behavior CSV** to a local `processedBehavior\`
  folder (`labPaths`); the `closed-loop-respiration` repo consumes it but is not a code dependency.

---

## 3. `dataTracking.xlsx` — the source of truth

`R:\Neurology\Zelano_Lab\Lab_Common\Admin\Data\dataTracking.xlsx` (`labPaths().adminXlsx`, or a repo‑local
copy; canonical location since 2026‑08‑25 — the old `Admin\dataTracking.xlsx` is no longer read),
`Sheet1`, **header row = 2, data from row 3**. Read it only through **`config/applyParams.m`**:

```matlab
cfg = applyParams(task, 'makeOutDat'|'main')   % Mode A: session list (+ roots) for a loop
P   = applyParams(task, sessID)                % Mode B: one session's parameter struct
```

- A row is identified by **`Subject ID` + `Task`**; one session usually has many rows (one per task /
  recording). Rows are deduped by `Subject ID` within a task (first wins, sheet order).
- A row is used only if its `Task` maps to a pipeline **and** `Raw Data Extracted` is non‑blank
  (`Data On Server` may also read `INCOMPLETE` for stub rows — skip those).
- `Type` values as they appear: `OBE_Dupi` / `OBE_dupi` (→ Dupi), `OBEControl` / `OBECONTROL`, `OBE_PD`,
  `EEG_breathing` (→ EEG). `dataType`: `ephys`, `ephys_echem`, `echem`. Only `ephys` rows are pipeline
  inputs for now: `ephys_echem` recordings will need different processing later (skip them, but list them
  so they aren't lost); `echem` rows and `*_echem` tasks are electrochemistry recordings, not ephys inputs.
- Sheet snapshot 2026‑08‑24 (extracted sessions): breathing 57 (41 curated / 15 guess / 1 blank), cue 41
  (36 / 2 / 3), thresh 35 (29 / 2 / 4), O15 40 (37 / 1 / 2), EmotionalMovieTask 3 (0 / 0 / 3).
- **`Data Preprocessed` must mirror the disk.** It is set to `X` by `writePreProcX` when a final is saved and
  is being brought into line with the disk in the 2026‑08‑24 work order (it had drifted: blank for the July
  breathing reruns, `X` for a few sessions with no valid final). When in doubt, the disk wins: a session is
  preprocessed iff its final loads with `moreThan1` (breathing‑type: plus `bmObj`/`baseEmotion`), and current
  iff it also has `behDat.manOnset`. Correct the column whenever you find it wrong — never leave it drifted.

### Parameter columns (read by `applyParams`, written by `writeParams`)

| Column | Tasks | Meaning / default |
|---|---|---|
| `datPre` | all | per‑session data root (blank → Type→root default; canonical `R:\…\Lab_Common\` prefix is rebased onto this machine's `labCommon`) |
| `rspIDX` / `rspFlip` | all | which respiration channel (among labels containing `rsp`), and ±1 polarity (inhale positive). Defaults `1` / `1`. |
| `hasEEG` | all | run `preprocess_eeg` (default true; O15 false) |
| `spikeClean` | all | targeted‑ICA spike clean of macros (default true; O15 false; EEG_breathing false) |
| `spikeThresh` / `spikeWin` | all | spike detector params (default `20` / `11`) |
| `macroRemove` | all | macro channels to drop before bipolar (`""` = none → `[]`) |
| `hasMacros` | breathing | run `preprocess_macros` (cue/thresh/O15 always run it; EEG_breathing false) |
| `respThresh` / `cuedBackBuff` / `adjWin` | cue/thresh/O15 | sniff‑detection windows (default `500` / `150` / `500`) |
| `beatSpec` | breathing | ECG beat‑detection spec for `detectBeats`, e.g. `1,0,gt,3.5` or `1,0,gt,2.5 & 3,10,gt,1` |
| `ttlRemoveIdx` / `ttlNote` | O15 | aberrant photodiode TTL indices to drop / note |
| `isNewStd` | breathing/cue/thresh | selects the "new standard" ingestion branch |
| `paramSource` | target rows | `curated` (trusted, runs unattended) / `guess` (unverified → interactive verification before any save) / blank (no parameters yet) |
| `Data Preprocessed` | all | set to `X` by `writePreProcX` when a final is saved; must mirror the disk (see above) |

`P` (Mode B) always carries `task, type ('Dupi'|'OBE'|'EEG'), fs_target=500, debug, computeResp, rspIDX,
rspFlip, hasEEG, spikeClean, spikeThresh, spikeWin, macroRemove, paramSource` + task extras (breathing:
`hasMacros, beatSpec, getBeats`; cue/thresh/O15: `respThresh, cuedBackBuff, adjWin` + `ttlMap`; O15 also
`pd`, `ttl`).

**`guess` rows** halt for interactive verification before any save: `paramCheck` (rsp + macro choices),
`paramCheckECG` (breathing ECG beats), and a deliberate onset‑gate `error` so a human inspects the figures,
promotes the row to `curated`, and re‑runs. A batch driver may bypass the gate only with an explicit
override flag, and must then leave `paramSource=guess` and save every QC figure.

---

## 4. Machine‑specific paths — `config/labPaths.m`

Every machine‑specific path comes from `labPaths.m`, which auto‑detects the machine by Windows `USERNAME`
(`adam` = home desktop, `dtf8829` = lab desktop) and returns the four base fields `codePre`, `eeglab`,
`labCommon`, `gdrive`; everything else (repo root, `eegLocs` CSV, vendored `slowBreathing`, Admin sheet,
behavioral dirs, figure dir, target‑trace dir, `processedBehavior`) is derived. **New machine = add one
`case`** or drop an untracked `labPaths_local.m`; unknown machines error with a copy‑paste template.

Lab data roots under `labCommon`: Dupi → `Dupi\` · OBEControl → `OBEControl\` · EEGbreathing →
`AllStudyData\EEGbreathing\` · figures → `Adam\Dupi_processing\<id>\`. Breathing behavioral files (target
traces, the alternating6Blocks `mindfulBreathing` / `sniffLogicLog` CSVs) are on Google Drive under
`cZelano\breathingDataFiles\` via `labPaths().gdrive`.

---

## 5. What the pipeline computes (stage by stage)

`assembleRaw_<task>` → `assembleOutDat(raw, S, P)` builds the initial `outDat` (§6), then `_main` runs:

**Shared (byte‑identical across all tasks — never edit per task):**

1. **`downsample_data(outDat, 500)`** — `resample` to **`fs_target = 500 Hz`**, then per channel a 4th‑order
   IIR **high‑pass 0.03 Hz** and 4th‑order IIR **low‑pass ≈ Nyquist**. **No line‑noise notch** (the
   60/120/180 Hz `iirnotch` was removed in July 2026; downstream analyses handle line noise). Sets `fs=500,
   origFS, downsampled=1`.
2. **`preprocess_eeg(outDat, EEGLOC, P)`** *(only if `P.hasEEG`)* — validates the **first 32 channels**
   against `config/eegLocs_standard_coords.csv`, attaches coords, detects + interpolates noisy channels
   (`removeNoiseChansVolt`), removes blinks on the good channels via ICA (`blinkRemoveWrapper`; blink‑IC
   auto‑selection with a manual fallback) when > 10 survive, and computes a Perrin surface Laplacian.
   Appends QC channels and EEG fields (§6.3).
3. **`preprocess_macros(outDat, P)`** *(breathing only if `P.hasMacros`; others always)* — finds `macro`
   channels, drops `macroRemove`, **bipolar re‑references adjacent pairs → `macBP1..N`**; if `P.spikeClean`,
   removes spike artifacts via targeted ICA. If there are too few spikes to train the ICA it **falls back to
   bipolar‑only with `spikeCleanVec = ones`** (July 2026 fix). Appends `macBP*` + `spikeCleanVec`.

**Respiration / onsets:**

- **cue / thresh / O15:** `preprocess_respiration_wholetrace` → `R` (chosen `rsp` channel, smoothed, Hilbert
  phase, deflection metric); `detect_sniffs_from_TTLs(R,P,outDat)` finds a sniff onset near each TTL
  (windows `respThresh/cuedBackBuff/adjWin`); `refine_onsets_with_phase` snaps onsets to a respiration‑phase
  zero‑crossing and appends `adjust`, `finalOnset`, and a NaN **`manOnset`** placeholder for manual QC.
- **breathing:** per‑breath segmentation over the whole recording → **`bmObj`** (the engine is being switched
  from `process_respiration_breathing` to **breathMetrics** — see the task file); `alignTargetBreathingTraceSimplify`
  aligns each paced block to its target trace and appends a `targTrace` channel (a block whose `shadowFile`
  is `NA` / whose CSV has no `target` column gets a zero target, like the audio/pre conditions);
  `processECG` band‑passes the `ECG` channels 5–40 Hz, z‑scores (`buildECGz`), detects beats (`detectBeats`
  per `beatSpec`, min separation `fs/20`), filters inter‑beat intervals physiologically, and appends an
  interpolated **`RRint`** channel; `flagBadBreaths` adds per‑breath QC.

**Behavior table:** `build_behavior_table_<task>` joins raw behavior to detected onsets (§6.4).
**Save** (§2) + `writeParams` + `writePreProcX`.

---

## 6. THE PREPROCESSED DATA STRUCTURE (what's in the final `.mat`)

New tasks must produce this same structure. The final variable (`outDat`) is a **struct**; the signal lives
in `outDat.data` (rows = channels, addressed by `outDat.labels`); everything else is metadata / behavior.
**`fs = 500 Hz`** for all final signals.

### 6.1 Common fields (every task)

| Field | Type | Meaning |
|---|---|---|
| `data` | `double [nChan × nSamp]` | all channels; row *i* ↔ `labels{i}` (continuous, not epoched) |
| `labels` | cell of char/string | channel labels parallel to `data` rows. **Index channels by label string, never by fixed position** (except the EEG block, 6.2) |
| `fs` | `500` | sample rate (Hz). Also `origFS`, `downsampled=1` |
| `sessID` | char | e.g. `250623_Dupi_NMH_KS_2` (= raw session folder name) |
| `task` | char | `breathingTask` / `cueTask` / `threshTask` / `O15` (legacy breathing files: `breathing`) |
| `type` | char | `Dupi` / `OBE` / `EEG` |
| `figs` | char | this session's figure folder |
| `rspIDX`, `rspFlip` | int, ±1 | which `rsp` channel is the respiration trace, and its polarity (inhale ↑) |
| `TTL` | table or vector | task‑specific event markers in **fs=500 samples** (6.5) |
| `moreThan1` | 0/1 | "more than one sniff per trial"; **also the done‑sentinel** (1 = breathing/O15, 0 = cue/thresh) |

O15‑only extras: `CSClist`, `OGdataDir`, `loadFile` (the `*LoadData*.m` used), `preProcScript`.

### 6.2 Channel taxonomy in `outDat.data` (find rows by label)

| Channel(s) | Label match | Present when | Added by |
|---|---|---|---|
| 32‑ch scalp EEG | exact 10‑20 names, **rows 1–32** | `hasEEG` | raw load; validated in `preprocess_eeg` |
| macro (raw depth/strip) | `contains('macro')` | recorded | raw load |
| respiration | `contains('rsp')` | always | raw load (select with `rspIDX`, flip with `rspFlip`) |
| ECG (≈3 ch) | `contains('ECG')` | breathing‑type tasks | raw load (→ `buildECGz`) |
| photodiode / events | `contains('event')` | O15, movie task (others vary) | raw load |
| `blinkIndicator` | `=="blinkIndicator"` | `hasEEG` and > 10 good EEG ch | `preprocess_eeg` |
| `badTS`, `interpChan` | exact | `hasEEG` | `preprocess_eeg` (bad‑sample mask, interpolation mask) |
| `macBP1..N` | `contains('macBP')` | macros run | `preprocess_macros` (bipolar pairs, N = nMacro − 1) |
| `spikeCleanVec` | `=="spikeCleanVec"` | macros run | `preprocess_macros` (all‑ones ⇒ no spikes removed) |
| `targTrace` | `=="targTrace"` | breathing | `alignTargetBreathingTraceSimplify` |
| `RRint` | `contains('RRint')` | breathing‑type tasks | `processECG` (interpolated RR‑interval series, s) |

EEG montage order (rows 1–32): `Fp1 Fz F3 F7 FT9 FC5 FC1 C3 T7 TP9 CP5 CP1 Pz P3 P7 O1 Oz O2 P4 P8 TP10 CP6
CP2 Cz C4 T8 FT10 FC6 FC2 F4 F8 Fp2`. The non‑EEG channel set varies by session/montage — always locate
channels with `cellfun(@(x) contains(x,'…'), outDat.labels)`.

### 6.3 EEG‑derived fields (only if `hasEEG`)

`eegLocs` (table `[32×8]`: `labels, X, Y, Z, theta, phi, X_flat, Y_flat`), `dataLap` (`[32×nSamp]` surface
Laplacian, `[]` if ≤ 10 good channels), `dataLapFromInterp` (0/1 — Laplacian computed on an interpolated
copy; mask `badChans` for per‑channel Laplacian analysis), `badChans` (cell of labels; broadband `data(1:32)`
keeps their real values), `EEGInterpolation`, `EEGCleaning`, `blinkRemoval` (0/1).

### 6.4 `behDat` — the behavior table (task‑specific)

`behDat` is a MATLAB **`table`**. Access by **named column**, never numeric index.

**cue / thresh / O15 — per‑sniff.** Shared first six columns from `behDatFromSniffs`: `sniffOnset` (coarse
onset, samples), `n` (trial), `wiTriali` (sniff index within trial), `TTLoffSet`, `sniffType`, `sniffLabel`
(cue/thresh `cued`; O15 `start`/`free`/`confirm`). Then the task columns —
cue: `cue` (1–10; `0` = no‑cue condition, being added), `odor`, `response`, `respString`, `type`
(`hit`/`miss`/`cr`/`fa`); thresh: `odor` (1–3), `pleasantness`, `intensity`, `type` (`air`/`low`/`med`);
O15: `target`, `response`, `expScore`. Finally `refine_onsets_with_phase` appends **`adjust`**,
**`finalOnset`** (phase‑refined onset — *use this for epoching*) and **`manOnset`** (NaN placeholder for
manual QC). Sanity sizes from real Dupi files: cue ≈ `[40 × 14]`, thresh ≈ `[45 × 13]`, O15 ≈ `[81 × 12]`
(one more column than before July 2026 because of `manOnset`); cue/thresh are one sniff per trial.

**breathing — per‑breath** (`build_behavior_table_breathingTask`, one row per detected breath):

| Column | Meaning |
|---|---|
| `sniffOnset`, `finalOnset`, `manOnset` | inhale‑onset sample (`finalOnset` is the one to align on; `manOnset` NaN placeholder) |
| `condition` | block/condition id (from `bmObj` col 12) |
| `Yonset`, `inhaleMax`, `Yend`, `exhaleMin` | respiration amplitudes at onset / inhale peak / breath end / exhale trough |
| `inMaxTim`, `endTim`, `exMinTim` | corresponding sample indices |
| `length` (s), `amp`, `index` | breath duration, amplitude, breath index |
| `task`, `noseMouth`, `shadowFile`, `warp` | per‑block stimulus metadata (block‑type label, e.g. `task='audio'`) |
| `<question>_<category>` | one column per emotion question × rating category (e.g. `calm_affective`, `emoAware_mindfulness`), the block's rating broadcast to every breath in it |
| `goodBreath` | 1/0 quality flag (`flagBadBreaths`) |
| `maxRR`, `minRR`, `RR_max_min` | within‑breath HRV (s) |
| `bm_*` | (being added) breathMetrics per‑breath features, appended after the columns above |

Breathing also stores `baseEmotion` (1‑row table of the baseline `order==0` ratings plus
`task/noseMouth/shadowFile/warp`), `bmObj`, `heartBeats` (6.6), and — once the breathMetrics switch lands —
`bmFeatures` (plain struct, never the class object). Empirically a 32‑ch‑EEG Dupi breathing session gives
`behDat` ≈ `[389 breaths × 34 vars]`; the emotion column set varies with the questions asked.

### 6.5 `TTL` conventions (samples @ 500 Hz)

- **O15** — table `[15 × 20]`: `trialStart, buttonPress, confirmSniff, free1 … free17` (NaN‑padded), built by
  `detect_ttls_O15` from the z‑scored `event` channel (30 trial marks expected; `ttlRemoveIdx` drops
  aberrant ones).
- **thresh** — table `[45 × 3]`: `start (= sniff − 1000)`, `trial`, `sniff`.
- **cue** — table `[nTrial × 3]`: `trialStart, response, sniff`.
- **breathing** — **vector** of block‑boundary samples (or a 5‑min fallback `0:600000:end`). New breath‑based
  tasks keep this vector and may add a descriptive table (`blocks` / `sections` / clip table) alongside it.

### 6.6 Breathing‑only structures

- `bmObj` `[nBreaths × 14]`: `1`=onset Y, `2`=onset time (s), `3`=inhale‑peak Y, `4`=peak time, `5`=end Y,
  `6`=end time, `7`=length (s), `8`=amplitude, `9`=peak idx, `10`=exhale‑peak Y, `11`=exhale‑peak time,
  `12`=**condition/block**, `13` unused, `14`=index. This layout is load‑bearing for `flagBadBreaths`,
  `build_behavior_table_breathingTask`, and downstream code — keep it whatever engine produces it.
- `heartBeats` — ECG beat sample indices (`detectBeats` / `beatSpec`).

---

## 7. Conventions & gotchas

- **Canonical respiration idiom** (used everywhere):
  ```matlab
  isRsp = cellfun(@(x) contains(x,'rsp'), outDat.labels);
  rsp   = outDat.data(isRsp,:); rsp = rsp(outDat.rspIDX,:) .* outDat.rspFlip;
  ```
- **Index `behDat` by name.** Legacy analysis did `behDat(:,13)==0` assuming a numeric matrix; in the table
  col 13 is `index` and the quality flag is `behDat.goodBreath`. Never rely on positions.
- **`task` value drift:** new files `breathingTask`; some older finals `breathing`. Top‑level var name varies
  (`outDat` vs `chanDat`/`out`) — load via `fieldnames` (§2).
- **EEG channels are exactly rows 1–32** and only when `hasEEG`; everything else is label‑addressed.
- **`spikeRemoval` reads 1 in both `preprocess_macros` branches** — inspect `spikeCleanVec` (all‑ones ⇒
  nothing removed) to know what actually happened.
- **Naming quirks left intentionally:** `_breathingPreProc` vs `_breathingPreproc`; raw folder
  `250904_OBE_NWU_TI` vs sheet `…_TI_1`; `250811_Dupi_NMH_TPB_1` is remapped to `…_TB_1` downstream and skips
  target‑trace alignment. (The sheet ID `2607802_OBE_NWU_SP_2` was a typo for `260702_OBE_NWU_SP_2` and is
  corrected in the 2026‑08‑24 work order — the folder name is the correct one.)
- **`datPrei` order is load‑bearing:** the `*_makeOutDat.m` scripts branch on `datPrei==1/2/3` to set
  `outDat.type` (`1=Dupi, 2=OBEControl, 3=EEGbreathing`); `applyParams` returns roots in that order with
  extras appended. Don't reorder.
- **"Unchanged after assemble."** In every `_main.m`, everything from the first `downsample_data(...)` onward is
  the shared core — keep it byte‑for‑byte identical across tasks so a fix in one propagates to all. New
  capability goes into shared functions that every relevant main calls.
- **Prefer strict over flexible:** if the data aren't the expected shape, let it error — a loud failure
  surfaces a real data problem. Keep per‑session photodiode special cases explicit (`switch sessID` blocks).
- **Memory:** a single raw session is multi‑GB. Process one session per iteration and clear big variables;
  one task per MATLAB process. Finals are `-v7.3` (HDF5) — use `matfile`/`h5info` to inspect without loading
  `data`.

---

## 8. Running a batch (what worked in July 2026 — see `currentState.md` §5)

- Run on the **lab desktop** (raw data are on `R:`; the home VPN link is too slow for multi‑GB reads), one
  task at a time, session lists and parameters from the sheet via `applyParams`.
- Per‑session `try/catch`; resumable done‑markers; a per‑task run log; back up every final you are about to
  overwrite (`E:\reprocBackup<...>\<task>\`) — those backups are the only copies of superseded finals.
- Verify every new final (`whos -file` integrity, `fs==500`, `moreThan1`, `manOnset`, breathing extras)
  before `writePreProcX`.
- A VPN blip can leave a running MATLAB's `R:` mapping stale (process hangs on a network read); kill and
  resume from the done‑markers.
- Validate any pipeline change on one session first (TUTORIAL §6): `moreThan1`, `finalOnset`, `manOnset`,
  respiration findable by label; for breathing, compare breath counts against the previous final.

---

## 9. File map

| Folder | Contents |
|---|---|
| `config/` | `labPaths.m`, `applyParams.m` / `writeParams.m` / `writePreProcX.m`, `eegLocs_standard_coords.csv` |
| `pipelines/` | `preprocessAll.m` + the `*PreProc_main.m` entry points |
| `pipelines/makeOutDat/` | raw → intermediate ingestion (`breathing` / `cue` / `thresh` …) |
| `shared/` | the shared signal core (`assembleOutDat`, `downsample_data`, `preprocess_eeg`, `preprocess_macros`, `preprocess_respiration_wholetrace`, `detect_sniffs_from_TTLs`, `refine_onsets_with_phase`, `behDatFromSniffs`, `paramCheck`, EEG/spike/onset helpers) |
| `tasks/<task>/` | each task's `assembleRaw_<task>.m`, `build_behavior_table_<task>.m`, task helpers (breathing: `process_respiration_breathing`, `alignTargetBreathingTraceSimplify`, `processECG`/`buildECGz`/`paramCheckECG`, `detectBeats`, `flagBadBreaths`; O15: `detect_ttls_O15`) |
| `external/` | vendored dependencies (`slowBreathing/` — five functions; `breathMetrics/` once added) |

Adding a participant is a sheet edit plus its load‑data script; adding a task follows the tutorial —
`applyParams` + `preprocessAll` registration, `assembleRaw_*`, optional `*_makeOutDat`,
`build_behavior_table_*`, a `_main` whose shared body is untouched.

---

## Remote compute (lab desktop)

Batch preprocessing runs on the Windows lab desktop over SSH — the raw data are on `R:` and the home
machine's VPN link is too slow to stream them.

### Prerequisite — VPN
All remote access requires Northwestern **GlobalProtect VPN** connected (`vpn-connect.northwestern.edu`;
NetID + Duo). The local machine is off‑domain, so without the VPN every remote connection times out. The
user connects the VPN (Duo is interactive). If remote commands suddenly start timing out, assume the tunnel
dropped and ask the user to reconnect — jobs already running on the remote keep going.

### Running commands — `ssh labdesktop`
- `ssh labdesktop "<command>"` runs non‑interactively and returns real stdout/stderr + exit code. Key‑based
  auth (`~/.ssh/config`); no password prompt.
- Hardware: 8‑core Intel i7‑10700, ~96 GB RAM, **no usable GPU**.
- **Default remote shell is cmd.exe.** Plain cmd tools (`net use`, `robocopy`, …) run directly. For
  non‑trivial **PowerShell**, base64‑encode the script:
  ```powershell
  $script = @'
  $ProgressPreference = "SilentlyContinue"   # avoids CLIXML stderr noise
  # ... your PowerShell here ...
  '@
  $enc = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($script))
  ssh labdesktop "powershell -NoProfile -NonInteractive -EncodedCommand $enc"
  ```
- **MATLAB batch jobs:** `matlab -batch "<script or expression>" -logfile E:\<...>\<task>_run.log`, one task
  per process, launched inside the same single `ssh` invocation that maps `R:` (below). Redirect output to
  `E:` and poll the log; the SSH session is a separate logon from any RDP session, so mapped drives and
  profile state differ.

### Storage — where to read/write
- **`E:\` is the workspace.** ~880 GB free, read/write from SSH. Scratch, intermediates, backups, logs go here.
  Keep preproc data files and the mirrored folder structure on `E:` for future jobs.
- **`C:\` has only ~4 GB free — never use it for job I/O.**
- **Lab server (`R:` → `\\fsmresfiles.fsm.northwestern.edu\fsmresfiles`)** is not reachable by default from an
  SSH session (key‑based logons carry no network credentials). `cmdkey` / Credential Manager does **not**
  work over key‑based SSH (tested — don't retry). The verified pattern is **explicit credentials inline, in a
  single `ssh` invocation** (the mapping lives only in that session):
  ```
  ssh labdesktop "net use R: /delete /y 2>nul & net use R: \\fsmresfiles.fsm.northwestern.edu\fsmresfiles /user:fsm\dtf8829 <NetID pw> & <job that uses R:\...> & net use R: /delete /y"
  ```
  For heavy or repeated I/O, `robocopy` a working set to `E:` first, crunch there, write back — same
  single‑invocation rule. Transfer updated preproc files back to `R:` and overwrite the old versions in place
  (after backing them up). Clean temporary files from `E:` at the end of all jobs.
- **Credential** = `fsm\dtf8829` + NetID/SSO password (sensitive, rotates). Never type it in chat or write it
  here. Stash it once as a DPAPI blob on the client
  (`Read-Host -AsSecureString | ConvertFrom-SecureString | Set-Content $env:USERPROFILE\.fsmcreds\netid.sec`);
  at runtime decrypt it locally and interpolate via base64 `-EncodedCommand` so the literal never appears in
  chat or a tracked file.
- `E:` is BitLocker‑encrypted but normally unlocked. If it shows **Locked**, ask the user for the E:
  BitLocker password (a local secret — never write it here) and unlock with `Unlock-BitLocker`.

### Code
- Home machine: `C:\Users\Adam\Documents\GitHub\`. Lab desktop: `E:\GitHub\` (preferred; edit here, git points
  here). `G:\My Drive\GitHub` is the older copy — use it only for a repo that has no copy on `E:`.
- Move code between machines with git. Other lab repos referenced by the current tasks: `breathMetrics`
  (to be vendored under `external/`), `ZelanoLabScripts` (legacy task code, read‑only reference).

> **Do not commit secrets.** This file is tracked in git. Never paste the NetID password, BitLocker
> password, or any credential here — supply them at runtime and keep them in a password manager or an
> untracked location.

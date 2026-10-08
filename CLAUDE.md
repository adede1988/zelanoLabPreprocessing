# CLAUDE.md — `zelanoLabPreprocessing`

## What this repo is

MATLAB preprocessing pipelines for the Zelano Lab's respiration + scalp‑EEG / intracranial‑EEG (+ ECG)
experiments. One shared signal‑processing core serves every task; tasks differ only in how raw data are laid
out and how events (photodiode/TTL) and behavior are parsed. The repo is **self‑contained** (the
breathMetrics fork it needs is vendored under `external/`) and contains **no data**. The session list
and every per‑session parameter live in **`dataTracking.xlsx`** (git‑ignored) — nothing is hard‑coded in
scripts.

Companion documents:
- `README.md` — what the pipelines produce, repo layout, requirements, how to run.
- `TUTORIAL_adding_a_task.md` — the recipe for adding a task while leaving the shared core untouched.
- `currentState.md` — the authoritative record of the **July 2026 full reprocessing run**: what was and
  wasn't reprocessed and why, and where the pre‑edit backups live (`E:\reprocBackup\`).
- `Tasks_260824.md` — the finished Aug‑2026 work order; its D1–D13 decisions are cited from code (keep it).
  `guessSessions.md` is the living ledger of guess sessions.
- `customBreathMetrics.md` — the spec of the LOCKED breath‑segmentation engine (`shared/segmentBreaths_zlp`)
  and how it drives the vendored breathMetrics.

---

## 1. Tasks

| canon name (`P.task`) | sheet `Task` values (matched case‑ and whitespace‑insensitively) | what's unique |
|---|---|---|
| `breathingTask` | `breathing tasks`, `breathingTasks`, `waveBreathing` | breathing blocks; **per‑breath table**, **ECG/HRV**, **paced target‑trace alignment**, **emotion ratings**. The richest task and the template for every new breath‑based task. |
| `cueTask` | `odor cue task` | odor cue / sniff / response TTLs; hit/miss/cr/fa behavior |
| `threshTask` | `threshold` | PEA threshold; 45 single‑sniff trials |
| `O15` | `O15` | loads raw directly (no `makeOutDat`); photodiode TTLs via `detect_ttls_O15`. `O15_noTTLs_skip` / `O15_corrupted` are deliberately unmatched. |
| `pacedBreathing` | `pacedBreathing` | **marker-free** single EEG_breathing recording (added 2026-09-15 with `260915_EEG_NWU_KG`): ~7 min audiobook/survey, ~90 min paced breathing at a sweep of paces x depths with brief breaks, ~10 min focused breathing. Loads raw directly (no `makeOutDat`, no behavioral file); **blocks are inferred from the segmented breaths** (`inferBlocks_pacedBreathing`, positional labels `pre`/`paced`/`final`, stored in `outDat.blocks` + `blockInference`, `TTL` = block starts); per-breath table adds `rateBPM`, `localPeriodCV`, `localAmpCV`, `nSubPeaks` (raggedness). ECG/HRV via the breathing path. Multi-file recordings (an acquisition stop/restart) are stitched end to end by the LoadData script; the seam is carried to the final (`outDat.segments`) and breaths near it flagged (`behDat.nearSeam`). |
| `EmotionalMovieTask` | `EmotionalMovieTask` | emotional film clips, **no behavioral file**: `emotionalMovieTask_makeOutDat` parses the photodiode (`detect_ttls_emotionalMovieTask`: 1 / 2 / 3 pulses = neutral / happy / sad) into a **clip table** that is `outDat.TTL` (`clipOnset, clipEnd, nPulses, valence`). **PsychoPy cross‑check (2026‑10‑08):** when the session's PsychoPy clip log (`<id>_emotionalMovieTask_*.csv`) is in `<id>\behavioralData\`, `matchClipsToPsychoPy` aligns its photodiode times to the detected pulse groups, picks the z threshold by agreement, drops detections with no played clip, takes valence from the log and records `outDat.clipCheck` (the default threshold over‑counted badly on noisy event channels: 248 / 241 clips for 180 played in RC / IS; the curated 260806_EEG_NWU_JH final, made before the check, has 192 clips incl. 12 spurious and 10 with the wrong pulse‑count valence). The per‑breath table keeps **only in‑clip breaths** (`condition` = valence code 1/2/3; the final clip has no defined end, so its breaths are dropped). ECG/HRV via `runECGStage` (NaN‑HRV fallback, `ecgSkipped`). |
| `alternating6Blocks` | `alternating6Blocks` | alternating breathing blocks (EEG_breathing) with ratings from the Google‑Drive behavioral files: `alternating6Blocks_makeOutDat` matches the `mindfulBreathing` ratings file (carries the participant ID) and the `sniffLogicLog` (matched by date + start time) and aligns the log to the raw respiration (`alignLogToRaw`) → `outDat.blocks` (`label, order, startSample, endSample`) + block‑start `TTL`. The per‑breath table keeps in‑block breaths (`task` = block label, `condition` = block order) with the block's ratings broadcast + `baseEmotion`. ECG/HRV via `runECGStage`. |
| `breathingTasks_separate` | one row **per condition recording**, `Task` = a condition name — the one vocabulary is `config/sepConditionInfo.m`: `audioBook`/`audiobook`/`distractedBreathing`, `focusedBreathing`, `sleep`, `sleepWithOdor`, `restingBaseline`, `focusedBreathing_button` (+ `…_button1`/`…_button2`, `…_button_mouth`), and `<condition>_run<N>` | a session = the Subject ID's eligible condition rows (`dataType` = `ephys` only). No `makeOutDat`: each condition's `raw\raw_<condition>\` file (folder rules in `sepConditionInfo`) is loaded directly, run through the shared core + segmentation + ECG **separately**, then concatenated in recording order (`concatSections` → `outDat.sections`, `TTL` = `[start_1 end_1 start_2 end_2 …]`). Per‑breath `task` = section label, `condition` = section index; no ratings / `baseEmotion`. Sheet writes go through `config/writeSheetSep` (every condition row), not `writeParams`/`writePreProcX`. |
| `vipassana` | `vipassana` | single continuous **BrainVision Recorder (actiCHamp)** session per participant (added 2026‑09‑26 with three `EEG_NWU` sessions AS/CC/DD): raw lives under `<id>\brainProductsDat\` (not Neuralynx/Atlas), and `Cz` — the recording reference — is reinserted as an all‑zero channel. Hand‑press event markers exist but are shaky/incomplete; treated only as hints. Loads raw directly (no `makeOutDat`); the fixed period sequence (`audiobook1`, `anapana`, `questionnaire1`, `vipassana`, `questionnaire2`, `metta`, `questionnaire3`, `audiobook2`, optional `pre`/`post`) is **inferred from an EEG artifact index by a duration‑constrained dynamic programme** (`inferBlocks_vipassana`), stored in `outDat.blocks` + `blockInference` (`TTL` = block starts). Respiration is optional per session: a viability probe (`probeRespViability_vipassana`) gates breath segmentation — when it fails (e.g. CC, no usable respiration channel), `respSkipped=2` and `outDat.respProbe` records why, no `bmObj`. ECG via `runECGStage`. **Line‑noise notch at ingestion** (2026‑09‑27): `assembleRaw_vipassana` notches the 32 scalp rows (ECG/rsp/event untouched; the Cz zero row stays zero) at 60/120/180 Hz (`designfilt` `bandstopiir`, order 2, f±1 Hz, `filtfilt`) and records `outDat.notchHz` / `notchNote` — the actiCHamp dry electrodes carry heavy 60‑Hz pickup and, un‑notched, the shared bad‑channel detector (`removeNoiseChansVolt`, amplitude rules on unfiltered data) flagged 22 of DD's 32 channels and nearly all of its first audiobook in `badTS` for line noise rather than bad contact; the shared core keeps no notch by design (§5), so this task notches before it. The block‑inference evidence (`artifactIndex`) is computed by the loader on the **un‑notched** rows before the notch, so the segmentation is unchanged (on notched evidence DD's audiobook1/anapana boundaries moved by 3.6–5.4 min). **No blink removal** (eyes closed throughout): `applyParams` sets `P.blinkRemoval = false` (§3), so `preprocess_eeg` skips `blinkRemoveWrapper` (`blinkRemoval = 0`, no `blinkIndicator` row). Current finals = the **2026‑09‑27 re‑run** with both changes: `badChans` AS `O1 Oz O2 Cz`, CC `FC5 TP9 P7 O1 Oz O2 TP10 Cz`, DD `Cz` only (was 22 channels, so DD has a `dataLap` again); still‑block `badTS` 2.6 / 6.3 / 0.2 % (was 3.0 / 19.1 / 10.4 %); blocks, breaths, beats and RSA check unchanged; the pre‑notch finals are in `…\AllStudyData\Vipassana\_backup_260927_preNotch\` (numbers: `guessSessions.md`). |
| `respiratorySweep` | `respiratorySweep` | **new experiment** (added 2026‑10‑08 with `261006_EEG_NWU_RC` / `_IS`; more participants to come): one continuous EEG_breathing Atlas recording — baseline ratings, a 6‑min audiobook (natural breathing), then **18 paced blocks of 150 s** (3 passes at depth 1.00 / 0.85 / 1.15 × the participant's calibrated breath size through the paces 15, 13, 10, 8, 6, 4 breaths/min, tracing a target trace on screen), post‑sweep ratings, and in the first sessions **2 × 6‑min focused breathing + 2 × 6‑min audiobook run off‑script with a stopwatch** (the lab plans to log those in SniffLogic later); the EmotionalMovieTask follows as a second recording. The Atlas recording has **no event marks**: the session's `LoadData_<id>_claude.m` calls `buildSweepTTL`, which aligns each SniffLogic log (`<id>\behavioralData\<id>_sniffLogicLog_*.csv`, events + respiration on the log clock) to the raw respiration (`shared/alignLogToRaw`: lag, drift, polarity), maps the log events onto raw samples, adds the stopwatch blocks hard‑coded from the session notes (start = the notes' Atlas recording time, exactly 6 min), cross‑checks other note times against the logs, and stores the **event table in the raw file** (`curDat.TTL` + `TTLinfo` + `logTrace`) — so there is no `makeOutDat`. The main converts it to `outDat.blocks` (500 Hz; `TTL` = block starts), adds a `targTrace` channel (the traced target, 0 outside sweep blocks), keeps **all** breaths with block columns (`blockType`, `cpm`, `depth`, `sweepNum`, `inBlock`) + the pacedBreathing regularity measures, stores the PsychoPy ratings (`ratings`, `baseEmotion`, `postSweepEmotion`); ECG via `runECGStage`. |

The name mappings live in `config/applyParams.m` (`taskKey` caller → canon, `canonTask` sheet → canon,
`taskCallerKey` canon → `P.task`) and are mirrored in `pipelines/preprocessAll.m` for every task except
`breathingTasks_separate`, which `preprocessAll` does not handle yet (it also reports but does not run
`EmotionalMovieTask` / `alternating6Blocks` — run those mains directly).

Adding a participant or recording to an existing task = sheet rows + its extraction script. When Claude
writes that script it is `LoadData_<id>_claude.m`, next to the lab's own `*LoadData*.m`, and its channel map
is verified with `batch/probeMontage.m` first (§2; BrainVision‑sourced sessions — currently only
`vipassana` — use `batch/probeMontageBV.m` instead). Adding a task follows `TUTORIAL_adding_a_task.md`.

---

## 2. Data flow, filenames, session folders

```
RAW  (Neuralynx/Atlas export + behavioral .mat/.csv)
  │   <root>\<id>\*LoadData*.m         (per session × task: raw export → extracted raw .mat)
  ▼
<root>\<id>\raw\raw_<task>\...                      ← EXTRACTED RAW
  │   <task>_makeOutDat.m               (breathing / cue / thresh / movie / alt6 — parse photodiode → TTLs,
  │                                      load behavior, stitch runs)   [O15 / paced / sep / vipassana /
  │                                      respiratorySweep skip this step]
  ▼
<root>\<id>\preProc\<id>_<task>PreProc.mat           ← INTERMEDIATE ("raw" outDat)
  │   <task>PreProc_main.m              (applyParams → assembleOutDat → shared core → task onsets/behavior)
  ▼
<root>\<id>\preProc\<id>_<task>preproc.mat           ← FINAL (the file that gets analysed)
```

- **Session folder layout** (`<root>\<id>\`): `AtlasData\` (raw export), the `*LoadData*.m` script(s),
  `raw\raw_<task>\`, `preProc\`, and a figure folder under `labPaths().figPath`. When adding a participant,
  copy the layout of an already‑extracted participant of the same `Type` — never invent a new one.
  EEGbreathing participant folders (since 2026‑10‑08) also hold **`behavioralData\`**: the session's
  PsychoPy / SniffLogic / emotionalMovieTask files, which used to sit loose in the EEGbreathing root — keep
  that root free of loose files (the pipelines read behavior from Google Drive or from
  `<id>\behavioralData\`, never from the root).
- **LoadData scripts.** The lab's own extraction scripts are `<root>\<id>\*LoadData*.m`; one written by Claude
  goes next to them as **`LoadData_<id>_claude.m`** (never edit or replace the lab's script). Each should store
  `curDat.loadFile = [mfilename '.m']` in every raw `.mat` it writes: `shared/findLoadDataScript` reads that
  provenance first, then falls back to the only `*LoadData*.m`, the unique `*_claude.m`, a per‑task tie‑break,
  else `''` with a warning (never fatal). Before extracting, verify the script's channel map against the data
  with **`batch/probeMontage.m`** (`probeMontage(atlasDir, suffix, outDir)` scores every `CSC*.ncs` channel for
  the respiration / ECG / event / scalp‑EEG / macro roles and writes a CSV + two figures; montages differ
  between OBE eras and sometimes between recordings).
- **BrainVision sources (`vipassana`).** Not every session is Neuralynx/Atlas: `vipassana`'s raw data is a
  single BrainVision Recorder (actiCHamp) recording per participant under
  `<root>\<id>\brainProductsDat\<id>.{vhdr,vmrk,eeg}`. The shared reader is **`batch/readBrainVision.m`**
  (parses the `.vhdr`/`.vmrk`/`.eeg` triplet and applies each channel's resolution to get µV); each
  session's `LoadData_<id>_claude.m` pastes the same reader in as local functions — the repo holds no
  per‑session scripts, so the loader must stand alone — to build the lab's raw‑channel layout (including
  reinserting the all‑zero `Cz` reference row) before saving `raw\raw_vipassana\raw_vipassana.mat`. Verify
  the channel map with **`batch/probeMontageBV.m`** (`probeMontage.m`'s BrainVision counterpart) instead of
  `probeMontage.m`. The raw `.mat`'s `curDat` carries the usual fields plus `curDat.markers` (every `.vmrk`
  marker as a table), `curDat.header` (the parsed `.vhdr`), and `curDat.refChan` (`'Cz'`).
- **Windows / case‑insensitive quirk (intentional, don't "fix").** The intermediate (`…PreProc.mat`) and the
  final (`…preproc.mat`) differ only in case, so they are the **same file** — `_main` overwrites the
  intermediate in place and a fully processed session has one file. Take the exact per‑task strings from the
  `save(...)` line of each `*PreProc_main.m` (legacy names exist, e.g. thresh `<id>_PEA_threshold_preproc.mat`).
- O15 loads `<id>\raw\raw_O15\raw_O15.mat` directly.
- **Top‑level variable** is `outDat`, except breathingTask finals — current ones included — which store
  `chanDat` (written by `parSave`; some older ones `out`). Load robustly:
  ```matlab
  s = load(finalPath); fn = fieldnames(s); outDat = s.(fn{1});
  ```
- A file is **fully processed** iff `outDat.moreThan1` exists (and, since July 2026, `behDat.manOnset`;
  breathing additionally `bmObj` / `baseEmotion`; the movie / alt6 / paced / sep mains check `moreThan1` +
  `bmFeatures` via `isSessionDone`).
- Every breath‑type pipeline also writes a per‑breath **processed‑behavior CSV** to a local
  `processedBehavior\` folder (`labPaths`): `<id>_processedBreathing.csv` for breathingTask,
  `<id>_<task>_processedBreathing.csv` for the others; the `closed-loop-respiration` repo consumes the
  breathingTask one but is not a code dependency.

---

## 3. `dataTracking.xlsx` — the source of truth

The sheet is `labPaths().adminXlsx` = `R:\Neurology\Zelano_Lab\Lab_Common\Admin\Data\dataTracking.xlsx`
(`Sheet1`, **header row = 2, data from row 3**). If the master is unreachable — or, for `applyParams` /
`writeParams` / `preprocessAll`, reachable but missing the `datPre` parameter columns — those three plus
`writePreProcX` / `clearPreProcX` fall back to a copy at the repo root (`<repo>\dataTracking.xlsx`,
git‑ignored) and emit a `<caller>:localFallback` warning on every call (e.g. `applyParams:localFallback`),
so a stale copy is never used silently. `writeSheetSep` and the `batch/` scripts only ever use the master
and error if it is unreachable. Read it only through **`config/applyParams.m`**:

```matlab
cfg = applyParams(task, 'makeOutDat'|'main')   % Mode A: session list (+ roots) for a loop
P   = applyParams(task, sessID)                % Mode B: one session's parameter struct
```

- A row is identified by **`Subject ID` + `Task`**; one session usually has many rows (one per task /
  recording). Rows are deduped by `Subject ID` within a task (first wins, sheet order).
- A row is used only if its `Task` maps to a pipeline **and** `Raw Data Extracted` is non‑blank
  (`Data On Server` may also read `INCOMPLETE` for stub rows — skip those).
- `Type` values as they appear: `OBE_Dupi` / `OBE_dupi` (→ Dupi), `OBEControl` / `OBECONTROL`, `OBE_PD`,
  `EEG_breathing` (→ EEG), `EEG_vipassana` (→ EEG; the BrainVision `vipassana` sessions — no Type→root
  default exists for it yet, so those rows set `datPre` explicitly to the Vipassana root,
  `R:\…\Lab_Common\AllStudyData\Vipassana\`). `dataType`: `ephys`, `ephys_echem`, `echem`. Only `ephys` rows
  are pipeline inputs for now: `ephys_echem` recordings will need different processing later (skip them, but
  list them so they aren't lost); `echem` rows and `*_echem` tasks are electrochemistry recordings, not
  ephys inputs.
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
| `hasMacros` | breath‑type tasks | run `preprocess_macros` (blank → true for breathingTask / breathingTasks_separate, false for alternating6Blocks / pacedBreathing and EEG‑type EmotionalMovieTask). cue/thresh/O15 do not read the cell: `applyParams` sets `P.hasMacros = true` (they always run it), which a curated run writes back via `writeParams` |
| `respThresh` / `cuedBackBuff` / `adjWin` | cue/thresh/O15 | sniff‑detection windows (default `500` / `150` / `500`) |
| `beatSpec` | breath‑type tasks | ECG beat‑detection spec for `detectBeats`, e.g. `1,0,gt,3.5` or `1,0,gt,2.5 & 3,10,gt,1` (blank → `1,0,gt,3` for breathingTask, `1,0,gt,3.5` for the others) |
| `ttlRemoveIdx` / `ttlNote` | O15 | aberrant photodiode TTL indices to drop / note |
| `isNewStd` | breathing/cue/thresh | selects the "new standard" ingestion branch |
| `paramSource` | target rows | `curated` (trusted, runs unattended) / `guess` (unverified → interactive verification before any save) / blank (no parameters yet) |
| `Data Preprocessed` | all | set to `X` by `writePreProcX` when a final is saved; must mirror the disk (see above) |

`P` (Mode B) always carries `task, type ('Dupi'|'OBE'|'EEG'), fs_target=500, rspIDX, rspFlip, hasEEG,
spikeClean, spikeThresh, spikeWin, macroRemove, paramSource, hasMacros` + task extras (breath‑type tasks:
`beatSpec, getBeats`; cue/thresh/O15: `respThresh, cuedBackBuff, adjWin`; O15 also `pd`, `ttl`;
EmotionalMovieTask `pd`; pacedBreathing `pacedOpts`; breathingTasks_separate `conditions`; vipassana
`vipOpts`, `blinkRemoval`). The mains add `allowGuessRun` and `figDir` (the session's task figure subfolder).

Task‑level `P` fields (set in `applyParams`, **not** sheet columns, not written by `writeParams`):
`blinkRemoval` — optional; absent or `true` = `preprocess_eeg` runs blink removal (every task's default);
`false` = the task has no blinks to remove, so blink removal is skipped (currently only `vipassana`, eyes
closed throughout; §5).

**`guess` rows** halt for interactive verification before any save: `paramCheck` (rsp + macro choices),
`paramCheckECG` (breath‑type ECG beats), and a deliberate onset‑gate `error` so a human inspects the figures,
promotes the row to `curated`, and re‑runs. A batch driver may bypass the gate only with an explicit
override flag, and must then leave `paramSource=guess` and save every QC figure.

---

## 4. Machine‑specific paths — `config/labPaths.m`

Every machine‑specific path comes from `labPaths.m`, which auto‑detects the machine by Windows `USERNAME`
(`adam` = home desktop, `dtf8829` = lab desktop) and returns the four base fields `codePre`, `eeglab`,
`labCommon`, `gdrive`; everything else (repo root, `eegLocs` CSV, Admin sheet,
behavioral dirs, figure dir, target‑trace dir, `processedBehavior`) is derived. **New machine = add one
`case`** or drop an untracked `labPaths_local.m`; unknown machines error with a copy‑paste template.

Lab data roots under `labCommon`: Dupi → `Dupi\` · OBEControl → `OBEControl\` · EEGbreathing →
`AllStudyData\EEGbreathing\` · figures → `Adam\Dupi_processing\<id>\`. Breathing behavioral files (target
traces, the alternating6Blocks `mindfulBreathing` / `sniffLogicLog` CSVs) are on Google Drive under
`cZelano\breathingDataFiles\` via `labPaths().gdrive`. `codePre` must also hold the sibling repos
`closed-loop-respiration\` and `experiment_EEGsync\`: `breathingTask_makeOutDat` reads each session's
behavioral CSV from their `processedBehavior\` folders, which `tasks/breathing/tidyImport_waveExp_matlab.m`
writes from the psychopy `mindfulBreathing` CSV (all three locations come from `labPaths`).

---

## 5. What the pipeline computes (stage by stage)

`assembleRaw_<task>` → `assembleOutDat(raw, S, P)` builds the initial `outDat` (§6), then `_main` runs:

**Shared (`shared/runSharedCore(outDat, P, EEGLOC)` — every main calls it right after assembly, per
condition recording for breathingTasks_separate; never edit per task):**

1. **`downsample_data(outDat, 500)`** — `resample` to **`fs_target = 500 Hz`**, then per channel a 4th‑order
   IIR **high‑pass 0.03 Hz** and 4th‑order IIR **low‑pass ≈ Nyquist**. **No line‑noise notch** (the
   60/120/180 Hz `iirnotch` was removed in July 2026; downstream analyses handle line noise). Sets `fs=500,
   origFS, downsampled=1`. A task whose rig needs a notch applies it at ingestion in its own
   `assembleRaw_<task>` instead (currently only `vipassana`, §1) — the shared core stays notch‑free.
2. **`preprocess_eeg(outDat, EEGLOC, P)`** *(only if `P.hasEEG`)* — validates the **first 32 channels**
   against `config/eegLocs_standard_coords.csv`, attaches coords, detects + interpolates noisy channels
   (`removeNoiseChansVolt`), removes blinks on the good channels via ICA (`blinkRemoveWrapper`; blink‑IC
   auto‑selection with a manual fallback) when > 10 survive, and computes a Perrin surface Laplacian.
   Appends QC channels and EEG fields (§6.3). Blink removal is skipped — the same degrade path as when both
   blink channels are bad: data unchanged, `blinkRemoval = 0`, no `blinkIndicator` row, bad‑channel
   handling / `badTS` / `interpChan` / Laplacian as usual — when `P.blinkRemoval` is `false` (task‑level flag,
   §3; `vipassana` only, eyes closed throughout).
3. **`preprocess_macros(outDat, P)`** *(only if `P.hasMacros`; always true for cue/thresh/O15)* — finds `macro`
   channels (any number ≥ 2), drops `macroRemove`, **bipolar re‑references adjacent pairs → `macBP1..N`**; if `P.spikeClean`,
   removes spike artifacts via targeted ICA. If there are too few spikes to train the ICA it **falls back to
   bipolar‑only with `spikeCleanVec = ones`** (July 2026 fix). Appends `macBP*` + `spikeCleanVec`.

**Respiration / onsets:**

- **cue / thresh / O15:** `preprocess_respiration_wholetrace` → `R` (chosen `rsp` channel, smoothed, Hilbert
  phase, deflection metric); `detect_sniffs_from_TTLs(R,P,outDat)` finds a sniff onset near each TTL
  (windows `respThresh/cuedBackBuff/adjWin`); `refine_onsets_with_phase` snaps onsets to a respiration‑phase
  zero‑crossing and appends `adjust`, `finalOnset`, and a NaN **`manOnset`** placeholder for manual QC.
- **breathing:** per‑breath segmentation over the whole recording → **`bmObj`** via `shared/segmentBreaths_zlp`
  (LOCKED rev13; spec `customBreathMetrics.md`; called by `process_respiration_breathing`, which derives the
  cyclicSigh span); `alignTargetBreathingTraceSimplify`
  aligns each paced block to its target trace and appends a `targTrace` channel (a block whose `shadowFile`
  is `NA` / whose CSV has no `target` column gets a zero target, like the audio/pre conditions);
  `processECG` band‑passes the `ECG` channels 5–40 Hz, z‑scores (`buildECGz`), detects beats (`detectBeats`
  per `beatSpec`, min separation `fs/20`), filters inter‑beat intervals physiologically, and appends an
  interpolated **`RRint`** channel; `flagBadBreaths` adds per‑breath QC.
- **other breath‑type tasks** (movie / alt6 / paced / sep / vipassana / respiratorySweep) call `segmentBreaths_zlp` from their
  mains — vipassana only when its respiration viability probe passes (`probeRespViability_vipassana`;
  otherwise `respSkipped=2`, no `bmObj`) — and vipassana's block boundaries come from an artifact‑index +
  dynamic‑programme step (`artifactIndex_vipassana` on the raw scalp rows, 60‑Hz‑dominated rows left out of
  its channel median → `inferBlocks_vipassana`) whose evidence is computed **before** `runSharedCore`, not
  after, since it needs the pre‑cleaning EEG — and before the task's ingestion notch too: `assembleRaw_vipassana`
  computes it on the un‑notched rows, then notches (notched evidence moved DD's audiobook1 by minutes); the main re‑zeroes the inserted `Cz` row after the core (§6.1); ECG goes through
  `shared/runECGStage` (movie / alt6 / paced / vipassana / respiratorySweep: on failure NaN HRV via
  `fillNaNHRV` + `ecgSkipped`, where breathingTask stays strict and errors); sep probes ECG once per session
  and runs `processECG` per section. **SniffLogic log alignment** (`shared/alignLogToRaw`, alt6 makeOutDat and
  respiratorySweep's `buildSweepTTL`): 20‑Hz cross‑correlation of the log's `pressure_pa` with the raw `rsp1`
  (coarse lag), 100‑Hz refinement, 120‑s‑window drift fit, polarity from the peak sign (the log's pressure is
  inhale‑positive); the quality gate is the |r| over the log/raw **overlap** (`rLocal` ≥ 0.40, REVIEW below
  0.60) — the global normalized peak is low by construction for a log covering only part of the recording.

**Behavior table:** `build_behavior_table_<task>` joins raw behavior to detected onsets (§6.4); the breath‑type
builders share `behDatFromBreaths` (the 14 base columns) and `appendBmFeatureCols` (`bm_*`).
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
| `task` | char | `P.task`: `breathingTask` / `cueTask` / `threshTask` / `O15` / … (§1; legacy breathing files: `breathing`) |
| `type` | char | `Dupi` / `OBE` / `EEG` |
| `figs` | char | this session's figure folder |
| `rspIDX`, `rspFlip` | int, ±1 | which `rsp` channel is the respiration trace, and its polarity (inhale ↑) |
| `TTL` | table or vector | task‑specific event markers in **fs=500 samples** (6.5) |
| `moreThan1` | 0/1 | "more than one sniff per trial"; **also the done‑sentinel** (1 = breathing/O15, 0 = cue/thresh) |

O15‑only extras: `CSClist`, `OGdataDir`, `loadFile` (the `*LoadData*.m` used), `preProcScript`.

vipassana‑only extras: `markers` (table of hand‑press event markers + the recording‑start marker,
`description/sampleRaw/sample/minutes`), `artifactIndex` (the 1‑s EEG evidence trace `inferBlocks_vipassana`
segments), `blocks` + `blockInference` (inferred period boundaries and the DP's cost/margin diagnostics;
§6.5), `refChan` (`'Cz'`, the inserted zero‑row reference), `czRezeroed` (`true`: the shared EEG stage's
`removeNoiseChansVolt` flags the flat Cz row bad and overwrites it trial by trial with a spline interpolation
of its neighbours, so the main forces `data` row 24 back to exact 0 after `runSharedCore`; `'Cz'` stays in
`badChans` and `dataLap` keeps its interpolated estimate), `respSkipped` (`0` respiration processed / `2`
skipped — no usable channel, e.g. `260918_EEG_NWU_CC`) + `respProbe` (the viability‑probe result struct),
`rspPolarityRSA` (inhale‑locked RR sanity check `deltaRRms / nBreaths / consistent`; always present, and
`NaN / 0 / false` = not checked because respiration or ECG was skipped), `notchHz` (`[60 120 180]`) +
`notchNote` (the ingestion notch of the 32 scalp rows, §1; absent in finals made before 2026‑09‑27).

respiratorySweep‑only extras: `blocks` (the event table at 500 Hz, §6.5), `TTLinfo` (how the raw file's event
table was built: per‑log alignment `logAlign` — file, `lagSec`, `r` / `rLocal`, drift, polarity, raw coverage —,
`aborted` block starts, `skippedLogs` (event‑less logs, not aligned), `flags` (checks that need a look), the
`stopwatch` spec, `noteCheck` = note times vs log‑derived times, `rspFlip`
measured from the log, `alignedChannel`), `ratings` (long table of the PsychoPy state ratings: `set`
`baseline` / `postSweep`, `file, Q_short, type, question, rsp, t`), `baseEmotion` / `postSweepEmotion`
(one‑row tables in the alternating6Blocks layout), plus the O15‑style provenance `CSClist, OGdataDir, loadFile,
preProcScript`. The raw file (`raw_respiratorySweep.mat`) carries `curDat.TTL` (same table in **raw** samples),
`curDat.TTLinfo` and `curDat.logTrace` (SniffLogic pressure / target at 50 Hz on the raw clock).

### 6.2 Channel taxonomy in `outDat.data` (find rows by label)

| Channel(s) | Label match | Present when | Added by |
|---|---|---|---|
| 32‑ch scalp EEG | exact 10‑20 names, **rows 1–32** | `hasEEG` | raw load; validated in `preprocess_eeg` |
| macro (raw depth/strip) | `contains('macro')` | recorded | raw load |
| respiration | `contains('rsp')` | always | raw load (select with `rspIDX`, flip with `rspFlip`) |
| ECG (≈3 ch) | `contains('ECG')` | breathing‑type tasks | raw load (→ `buildECGz`) |
| photodiode / events | `contains('event')` | O15, movie task (others vary) | raw load |
| `blinkIndicator` | `=="blinkIndicator"` | `hasEEG`, > 10 good EEG ch and blink removal ran (`blinkRemoval==1`) | `preprocess_eeg` |
| `badTS`, `interpChan` | exact | `hasEEG` | `preprocess_eeg` (bad‑sample mask, interpolation mask) |
| `macBP1..N` | `contains('macBP')` | macros run | `preprocess_macros` (bipolar pairs, N = nMacro − 1) |
| `spikeCleanVec` | `=="spikeCleanVec"` | macros run | `preprocess_macros` (all‑ones ⇒ no spikes removed) |
| `targTrace` | `=="targTrace"` | breathing, respiratorySweep | `alignTargetBreathingTraceSimplify` (breathing); respiratorySweep main from the SniffLogic `target_pa` (log units, 0 outside sweep blocks) |
| `RRint` | `contains('RRint')` | breathing‑type tasks | `processECG` (interpolated RR‑interval series, s) |

EEG montage order (rows 1–32): `Fp1 Fz F3 F7 FT9 FC5 FC1 C3 T7 TP9 CP5 CP1 Pz P3 P7 O1 Oz O2 P4 P8 TP10 CP6
CP2 Cz C4 T8 FT10 FC6 FC2 F4 F8 Fp2`. The non‑EEG channel set varies by session/montage — always locate
channels with `cellfun(@(x) contains(x,'…'), outDat.labels)`.

### 6.3 EEG‑derived fields (only if `hasEEG`)

`eegLocs` (table `[32×8]`: `labels, X, Y, Z, theta, phi, X_flat, Y_flat`), `dataLap` (`[32×nSamp]` surface
Laplacian, `[]` if ≤ 10 good channels), `dataLapFromInterp` (0/1 — Laplacian computed on an interpolated
copy; mask `badChans` for per‑channel Laplacian analysis), `badChans` (cell of labels; broadband `data(1:32)`
keeps their real values), `EEGInterpolation`, `EEGCleaning`, `blinkRemoval` (0/1).

> **KNOWN ISSUE (found 2026‑09‑27, not yet fixed):** `dataLap` is currently a common‑mode artefact, not a Laplacian.
> `preprocess_eeg` feeds `laplacian_perrinX` (a spherical‑spline Laplacian that assumes electrodes on a sphere) the
> realistic head coordinates of `eegLocs_standard_coords.csv` (radii 0.081–0.114 m). On a vipassana final, 60 s at
> 1–40 Hz, the stored `dataLap` has 97 % of its variance in the channel mean (median row SD 345 µV, inter‑channel
> |r| 0.98); the same call with the coordinates projected onto the unit sphere (`x./r, y./r, z./r`) gives a proper
> Laplacian (4.5 % common mode, 47 µV, |r| 0.09). Until the shared stage is fixed and `dataLap` recomputed in the
> finals, do not use `dataLap` for analysis (the Vipassana_analysis folder uses FieldTrip's `ft_scalpcurrentdensity`
> instead). Test scripts: `DataForClaude/vipassana/probe/lapTest.m` and `lapTest2.m` on the home machine.

### 6.4 `behDat` — the behavior table (task‑specific)

`behDat` is a MATLAB **`table`**. Access by **named column**, never numeric index.

**cue / thresh / O15 — per‑sniff.** Shared first six columns from `behDatFromSniffs`: `sniffOnset` (coarse
onset, samples), `n` (trial), `wiTriali` (sniff index within trial), `TTLoffSet`, `sniffType`, `sniffLabel`
(cue/thresh `cued`; O15 `start`/`free`/`confirm`). Then the task columns —
cue: `cue` (1–10; `0` = no‑cue condition), `odor`, `response`, `respString`, `type`
(`hit`/`miss`/`cr`/`fa`; `noCue` on `cue==0` trials); thresh: `odor` (1–3), `pleasantness`, `intensity`, `type` (`air`/`low`/`med`);
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
| `bm_*` | breathMetrics per‑breath features (`appendBmFeatureCols`), appended after the columns above |

Breathing also stores `baseEmotion` (1‑row table of the baseline `order==0` ratings plus
`task/noseMouth/shadowFile/warp`), `bmObj`, `heartBeats` (6.6), and `bmFeatures` (plain struct, never the
class object). Empirically a 32‑ch‑EEG Dupi breathing session gives
`behDat` ≈ `[389 breaths × 34 vars]`; the emotion column set varies with the questions asked.

Other breath‑based tasks build their own `build_behavior_table_*` on the same shared base (§5) with their
own extra columns instead of ratings — e.g. pacedBreathing's `rateBPM, localPeriodCV, localAmpCV, nSubPeaks`
(§1); **vipassana**'s adds `task` (the breath's inferred block label), `still` (copied from the block),
`noseMouth`/`shadowFile`/`warp` as `NA`/`NaN` (no stimulus metadata), and the same `rateBPM, localPeriodCV,
localAmpCV, nSubPeaks` raggedness measures — only populated when `respSkipped==0` (else `behDat` has the
columns but zero rows). **respiratorySweep** keeps **every** breath of the recording (rests / instructions /
ratings included; `condition` = block order, 0 between blocks) and adds `task` (block label or `none`),
`blockType` (`audiobook` / `sweep` / `focusedBreathing` / `other` / `none`), `phase` (`pre` / `sweep` / `mid` / `post` /
`none`),
`inBlock`, `cpm`, `depth`, `sweepNum` (NaN off‑sweep), `noseMouth`/`shadowFile`/`warp` as `NA`/`NaN`, and the
pacedBreathing `rateBPM, localPeriodCV, localAmpCV, nSubPeaks` (local windows never straddle a block edge);
ratings are not broadcast per breath (only a baseline and a post‑sweep set exist) — see `ratings` /
`baseEmotion` / `postSweepEmotion` (§6.1).

### 6.5 `TTL` conventions (samples @ 500 Hz)

- **O15** — table `[15 × 20]`: `trialStart, buttonPress, confirmSniff, free1 … free17` (NaN‑padded), built by
  `detect_ttls_O15` from the z‑scored `event` channel (30 trial marks expected; `ttlRemoveIdx` drops
  aberrant ones).
- **thresh** — table `[45 × 3]`: `start (= sniff − 1000)`, `trial`, `sniff`.
- **cue** — table `[nTrial × 3]`: `trialStart, response, sniff`.
- **breathing** — **vector** of block‑boundary samples (or a 5‑min fallback `0:600000:end`). New breath‑based
  tasks keep this vector and may add a descriptive table alongside it (alternating6Blocks: block starts +
  `blocks`; breathingTasks_separate: `[start_1 end_1 start_2 end_2 …]` + `sections`).
- **EmotionalMovieTask** — the exception: `TTL` is the clip table itself (`clipOnset, clipEnd, nPulses,
  valence`; `clipEnd` is NaN for the final clip).
- **pacedBreathing** — vector of INFERRED block starts (no markers exist); the `blocks` table (`label, order,
  startSample, endSample, durationSec, nBreaths, medRateBPM, medPeriodSec, medAmp, periodCV, ampCV, regularity,
  gapSplit`) and `blockInference` (parameters, raw changepoints, merge history, per‑breath block index) sit
  alongside. Review `blocks_inferred.jpg` in the session figure folder before trusting the labels.
- **vipassana** — vector of INFERRED block starts, but anchored (loosely) by shaky hand‑press markers rather
  than marker‑free: a duration‑constrained dynamic‑programme segmentation of an EEG artifact index
  (`inferBlocks_vipassana`) fits the fixed period sequence `pre, audiobook1, anapana, questionnaire1,
  vipassana, questionnaire2, metta, questionnaire3, audiobook2, post` (zero‑length `pre`/`post` dropped). The
  `blocks` table is `label, order (protocol index 0–9), still, startSample, endSample, durationSec,
  nominalSec, meanEvid, markerDistSec (nearest hand‑press marker, NaN if none within 120 s),
  boundaryMarginStart`; `blockInference` carries the DP options, the per‑second evidence trace, the cost
  breakdown, and each boundary's alternative position/margin. Review `blocks_inferred.jpg` in the session
  figure folder before trusting the labels.
- **respiratorySweep** — vector of block starts; the blocks are **recorded, not inferred** (SniffLogic log
  events aligned to the raw respiration, plus stopwatch blocks hard‑coded from the session notes). The
  `blocks` table: `order, label` (`audiobook_pre`, `Sweep_b<NN>_cpm<rate>_depth<scale>` as the log names it,
  `focusedBreathing_post<k>`, `audiobook_post<k>`; any other logged block keeps its log name), `blockType`
  (`audiobook` / `sweep` / `focusedBreathing` / `other`), `phase` (`pre` / `sweep` / `mid` / `post`, by time relative to
  the sweep), `sweepNum, blockIdx` (log block number),
  `cpm, depth, cndNum, targetP2T` (Pa), `startSample, endSample` (inclusive), `startSec, endSec, durationSec`
  (raw time), `source` (`sniffLogicLog` / `notes_stopwatch`), `logFile`. QC: `<id>_sweepTTL.png` (written by the
  LoadData script) + `blocks_TTL.jpg` / `sweepBlocks_zoom.jpg` / `breathOverlay.jpg` in the session's
  `respiratorySweep` figure folder.

### 6.6 Breathing‑only structures

- `bmObj` `[nBreaths × 14]`: `1`=onset Y, `2`=onset time (s), `3`=inhale‑peak Y, `4`=peak time, `5`=end Y,
  `6`=end time, `7`=length (s), `8`=amplitude, `9`=peak idx, `10`=exhale‑peak Y, `11`=exhale‑peak time,
  `12`=**condition/block**, `13` unused, `14`=index. This layout is load‑bearing for `flagBadBreaths`,
  `behDatFromBreaths` / the `build_behavior_table_*` builders, and downstream code — keep it whatever engine
  produces it (full column doc: the `shared/segmentBreaths_zlp.m` header).
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
  (`outDat`; breathingTask finals, current ones included, `chanDat` via `parSave`; some older `out`) — load
  via `fieldnames` (§2).
- **EEG channels are exactly rows 1–32** and only when `hasEEG`; everything else is label‑addressed.
- **`spikeRemoval` reads 1 in both `preprocess_macros` branches** — inspect `spikeCleanVec` (all‑ones ⇒
  nothing removed) to know what actually happened.
- **Naming quirks left intentionally:** `_breathingPreProc` vs `_breathingPreproc`; raw folder
  `250904_OBE_NWU_TI` vs sheet `…_TI_1`; `250811_Dupi_NMH_TPB_1` is remapped to `…_TB_1` downstream and skips
  target‑trace alignment. (The sheet ID `2607802_OBE_NWU_SP_2` was a typo for `260702_OBE_NWU_SP_2` and is
  corrected in the 2026‑08‑24 work order — the folder name is the correct one.)
- **`datPrei` order is load‑bearing:** `applyParams` returns roots in the order `1=Dupi, 2=OBEControl,
  3=EEGbreathing` with extras (e.g. `OBEControl\anosmics\`) appended, and the `*_makeOutDat.m` scripts
  index `datPre{datPrei}` and branch on `datPrei==1/2/3` to set the intermediate's `outDat.type`. That type is
  informational only — the final's `type` comes from the sheet (`P.type` in `assembleOutDat`) — and an extra
  root no longer stops a session (thresh used to error). Don't reorder.
- **Shared stages stay shared.** Every `_main.m` calls `runSharedCore` right after assembly and uses the
  shared stage helpers (`runECGStage`, `fillNaNHRV`, `behDatFromBreaths`, `appendBmFeatureCols`,
  `isSessionDone`, …) instead of inline copies; task logic lives in `tasks/<task>/`. A fix
  goes into the shared function so it reaches every task — never patch one main's copy. New capability goes
  into shared functions that every relevant main calls.
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
| `config/` | `labPaths.m`, `applyParams.m` / `writeParams.m` / `setPreProcX.m` (+ its thin wrappers `writePreProcX.m` / `clearPreProcX.m`), `writeSheetSep.m` (breathingTasks_separate sheet writer), `sepConditionInfo.m` (the sep condition vocabulary), `eegLocs_standard_coords.csv` |
| `pipelines/` | `preprocessAll.m` + the `*PreProc_main.m` entry points (one per task) |
| `pipelines/makeOutDat/` | raw → intermediate ingestion (`breathing` / `cue` / `thresh` / `emotionalMovie` / `alternating6Blocks`) |
| `shared/` | the shared signal core: `runSharedCore` (`downsample_data` → `preprocess_eeg` → `preprocess_macros`), `assembleOutDat`, `preprocess_respiration_wholetrace`, `detect_sniffs_from_TTLs`, `refine_onsets_with_phase`, `behDatFromSniffs`, `paramCheck` / `guessFigDir`, EEG/spike/onset helpers; the breath engine `segmentBreaths_zlp` (+ `prepBreathTrace_zlp`, `findInhaleOnsets_zlp`); the breath‑type stage helpers `behDatFromBreaths`, `appendBmFeatureCols`, `runECGStage`, `fillNaNHRV`, `isSessionDone` and the ECG/QC helpers `processECG` / `buildECGz` / `detectBeats` / `paramCheckECG` / `flagBadBreaths`; `findLoadDataScript` (LoadData provenance), `toTargetSamples` (raw → 500 Hz sample indices), `alignLogToRaw` (SniffLogic log → raw clock; alternating6Blocks + respiratorySweep) |
| `tasks/<task>/` | each task's `assembleRaw_<task>.m`, `build_behavior_table_<task>.m`, task helpers (breathing: `process_respiration_breathing`, `alignTargetBreathingTraceSimplify`, `plotBreathLengths`, `tidyImport_waveExp_matlab` (writes the processedBehavior CSV the breathing makeOutDat reads); cue: `outMat_to_table`; O15: `detect_ttls_O15`, `assembleOutDat_O15extras`; emotionalMovie: `detect_ttls_emotionalMovieTask`; alternating6Blocks: `parse_mindfulBreathing`, `parse_sniffLogicLog`; respiratorySweep: `buildSweepTTL` (called by the session LoadData scripts), `parse_sweepLog`, `parse_sweepRatings`, `plotBlocks_respiratorySweep`; breathingSeparate: `concatSections`; pacedBreathing: `inferBlocks_pacedBreathing`, `plotBlocks_pacedBreathing`; vipassana: `assembleRaw_vipassana`, `artifactIndex_vipassana`, `inferBlocks_vipassana`, `probeRespViability_vipassana`, `checkRspPolarityRSA`, `plotBlocks_vipassana`, `build_behavior_table_vipassana`) |
| `batch/` | reusable QC / maintenance tools (not pipeline steps): `probeMontage` (verify a new LoadData channel map against the data), `readBrainVision` / `probeMontageBV` (the BrainVision‑source counterparts of the raw reader / `probeMontage`, used by `vipassana`), `probeSessionParams` / `probeECGpolarity` (measure guess parameters), `qc4`–`qc8` audits and figure generators, `qualityCheckOverlays`, `resegmentAll_zlp`, `reconstructPacedBlocks`, `guessParamsFromRaw` (measured guess parameters from extracted raw files), `buildGuessReview.ps1` (guess-QC report from qc8 output; env `ZLP_QC8_OUT`, params `-IntroHtml -NewIds`; the report lives on R: under `Adam\Dupi_processing\guessReview_<date>\`, not in the repo) |
| `external/` | vendored dependencies: `breathMetrics/` (fork qhyang42 @9791153; unmodified) |

The pace × depth sweep analysis (`respiratorySweepAnalysis/`) now lives in its own repo, `../calibratedHRV`.

Adding a participant is a sheet edit plus its load‑data script (`LoadData_<id>_claude.m` when Claude writes it,
channel map checked with `batch/probeMontage.m`); adding a task follows the tutorial —
`applyParams` + `preprocessAll` registration, `assembleRaw_*`, optional `*_makeOutDat`,
`build_behavior_table_*`, a `_main` that calls `runSharedCore` and the shared helpers (no inline copies).

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

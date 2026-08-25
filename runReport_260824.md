# Run report — 2026‑08‑24 work order

One section per task (Tasks_260824.md). Scripts live in `batch/`; raw outputs, logs and
backups in `E:\reprocBackup_260824\` on the lab desktop.

---

## Task 1 — Inventory + sheet sync (run 2026‑08‑24 → 25)

### What ran

1. **Backups** (before any write): the live master
   `R:\…\Admin\dataTracking.xlsx` → `E:\reprocBackup_260824\dataTracking_before.xlsx`,
   and the stale copy `R:\…\Admin\Data\dataTracking.xlsx` →
   `E:\reprocBackup_260824\dataTracking_AdminData_before.xlsx`.
2. **Sheet-location conflict found and resolved.** `config/labPaths.m` (commit `genUpdate`,
   2026‑07‑28) pointed the code at `Admin\Data\dataTracking.xlsx`, which is a **stale
   2026‑07‑28 snapshot** (279 rows; none of the new task rows). The live master is
   `Admin\dataTracking.xlsx` (330 rows, edited 2026‑08‑24, has alternating6Blocks /
   EmotionalMovieTask / condition rows and the SP_2 typo rows at exactly rows 280–290).
   `labPaths`/`applyParams` now point back at `Admin\`. The `Admin\Data\` copy was left in
   place untouched — **consider deleting or archiving it to avoid future drift.**
3. **SP_2 ID fix (D12e)** — `batch/task1_fixSP2.m`: 11 cells A280:A290
   `2607802_OBE_NWU_SP_2` → `260702_OBE_NWU_SP_2`, each write verified; session folder on
   R: confirmed to carry the corrected name (typo-named folder does not exist).
4. **Inventory** — `batch/task1_inventory.m` → `inventory_260824.csv` (repo root; also
   `E:\reprocBackup_260824\inventory_260824.{csv,mat}`), 225 in-scope-task rows.
   Final validity read structurally (h5info on the ‑v7.3 finals: `moreThan1`, breathing +
   `bmObj`/`baseEmotion`); *current* = valid ∧ mtime ≥ 2026‑07‑01, spot-verified by fully
   loading 2 current + 2 stale finals and checking `behDat.manOnset` — 4/4 agreed.
5. **`Data Preprocessed` sync (D2)** — `batch/task1_syncPreProcX.m`: **41 cells SET, 0
   cleared, 174 unchanged, 0 unreadable-skipped.** All sets were the July breathing /
   waveBreathing reruns whose flag had drifted blank, plus the two valid-but-stale
   pre-July `EmotionalMovieTask` finals (`250225_OBE_NWU_AS_4`, `251009_OBE_NWU_CP_1` —
   old-pipeline outputs, `moreThan1` present). The INCOMPLETE stub row 66
   (`251009_EEG_NWU_SM`) was deliberately left blank; its real row 81 got the X.
   From now on only `writePreProcX` / the new `config/clearPreProcX.m` touch this column.

### Inventory headlines (in-scope rows)

| group | rows | raw on disk | file present | valid final | current |
|---|---:|---:|---:|---:|---:|
| breathing | 60 | 57 | 43 | 41 | 40 |
| cue | 43 | 39 | 37 | 35 | 35 |
| thresh | 37 | 34 | 29 | 29 | 29 |
| O15 | 40 | 39 | 36 | 36 | 35 |
| EmotionalMovieTask | 10 | 3 | 2 | 2 | 0 |
| alternating6Blocks | 8 | 0 | 0 | 0 | 0 |
| breathingTasks_separate | 17 | 16 | 0 | 0 | 0 |

dataType: 215 `ephys`, 5 `echem`, 5 `ephys_echem` (no blanks among real rows except the
PD_MP stub below). Out-of-scope (D1) rows listed in the CSV: PD_MP (echem ×2), KS_1/KS_2
`focused breathing`/`sleep` (echem), JH_1 `focused breathing` (echem), RY_1 `sleep`
(ephys_echem), `260326_OBE_NWU_AD_2` O15+cue (ephys_echem — finals left untouched),
KA_2 restingBaseline+threshold (ephys_echem duplicates).

### Changes on the ground since July's `currentState.md` (found by this inventory)

- **`250904_OBE_NWU_TI_1` breathing is now a valid, current final** (the July "target CSV
  missing" failure was evidently fixed by the alignTarget zero-trace fallback). No clear
  needed. The sheet/folder quirk (folder `250904_OBE_NWU_TI`) did not bite — the final
  lives under the sheet-named path checked first.
- **`250929_Dupi_NMH_GH_2` O15 is valid + current** — the July TTL-mismatch failure was
  evidently resolved; only `260316_Dupi_NMH_PD_1` O15 remains stale (one D6 attempt in
  Task 4).
- **`260608_OBE_NWU_RX_1`**: cue raw was extracted post-July, its cue row is `curated`,
  and a **valid current cue final exists** (matches the `genUpdate` RX_1 photodiode
  special-case). Thresh and O15 raw are also on disk now (rows blank → guesses in
  Tasks 4/5); breathing raw is still absent.
- **`250623_Dupi_NMH_KS_3`** — a breathing session not in the work order's lists: `guess`
  row, bare intermediate (2026‑06‑09) only. Guess-listed in Task 3, not run (Dupi).
- **`251120_Dupi_NMH_JL_1` breathing**: file on disk is a **bare intermediate**
  (2026‑06‑09, no `bmObj`/`baseEmotion`) — the "original restored" in July was evidently
  the intermediate. Gets its one D6 attempt in Task 3.
- **`250623_Dupi_NMH_KS_2` breathing**: valid but **stale** final (2026‑06‑10, pre-manOnset)
  — D6 attempt in Task 3.

### Discrepancies / oddities (report-only)

- **`260316_Dupi_NMH_PD_2` breathingTasks** says extracted but has **no breathing raw**
  on disk (its `raw\` holds `raw_` (bare/empty name), O15, thresh, cue, memoryTask
  folders). `guess` row → listed, not run; flagged for the lab.
- **`260720_OBE_NWU_KA_2`** cue/thresh raw folders use **non-standard names**
  (`raw_cueTask`, `raw_threshTask` instead of `raw_cueTaskOdor*` /
  `raw_PEAintensityPleasantness*`) — the existing makeOutDat globs would not find them.
  Rows are blank→guess (not run), but Task 5/6 guess notes must record this.
- **PD_MP row 19** (`250403_OBE_NMH_PD_MP`, `focused breathing`, blank dataType) is a
  stub duplicate of the echem row 20; not extracted, no session folder → excluded from
  Task 9 (needs ≥1 *extracted* ephys condition row).
- `251009_EEG_NWU_SM` rows 66/81: stub row 66 left blank (see above).
- Not on server yet (expected): `251030_Dupi_NMH_DB_3` (+ `251110_Dupi_NMH_PC_3`).
- `260227_EEG_NWU_HW` waveBreathing: on server, not extracted → Task 2.

### Task routing snapshot (verified against disk)

- **Task 2**: 9 EEG_breathing subjects to extract (HW waveBreathing; CA alternating only;
  JH/MM combined recordings; GP/IS/AL/MS/HK alternating+movie as separate recordings —
  raw folder listings confirm one big recording for JH/MM and two for the other five).
- **Task 3**: 60 breathing rows; 41 curated with valid finals (all rerun from raw), KS_2
  (stale), JL_1/KS_3 (intermediates), TI_1/RX_1/PD_2/DB_3 cases as above, HW after Task 2.
- **Task 4 (O15)**: no curated pending; stale PD_1 (one attempt); guesses JA_2 (has
  intermediate-era raw), RX_1, SP_2.
- **Task 5 (thresh)**: no curated pending; guesses PD_2, JA_2, RX_1, HM_2, SP_2, KA_2.
- **Task 6 (cue)**: no curated pending; guesses PD_2, JA_2 (intermediates exist), SP_2,
  RC_1, KA_2. RX_1 cue is already done.
- **Task 7**: old OBEControl sessions AS_4/TI_1/CP_1 extracted (AS_4/CP_1 carry valid
  stale old-format finals; left in place); 7 EEG subjects after Task 2.
- **Task 9**: in-scope condition rows match D12a's 8 sessions exactly (17 rows: HM_2 ×4,
  SP_2 ×3, RC_1 ×4, KA_2 ×1, GH_1, DL_1, RY_1, ZF_1 sleep/focusedBreathing).

Sheet cells changed in Task 1: 11 Subject ID cells (A280:A290) + 41 `Data Preprocessed`
cells (K column; list in `E:\reprocBackup_260824\task1_syncX_run.log` and above in
this section's sync output).

Open questions for the lab: none blocking; the `Admin\Data\` stale sheet copy and the
KA_2 raw-folder naming should be tidied at some point.

---

## Task 2 — EEG_breathing extraction (run 2026‑08‑25)

### Template (step 1)

From `260109_EEG_NWU_AA` / `251208_EEG_NWU_ZA`: layout `<id>\AtlasData\<datetime>\`,
`raw\raw_<task>\raw_<task>.mat`, `preProc\`; script `LoadData_<id>.m` in the subject
folder; `ReadNCS` (fieldtrip) reads the named CSC channels and the script saves
`curDat` (`ncslabels`, `rawData` = fieldtrip struct, `outLabs`) as `-v7.3`. Channel
map: **CSC33:64 = EEG** (10‑20 order, rows 1–32), **CSC25/26/27 = ECG1‑3**,
**CSC270 = rsp1**, **CSC269 = event** (photodiode). Sheet after extraction:
`Raw Data Extracted = X`, `datPre` = the EEGbreathing root.

### Channel probe (`batch/task2_probeChannels.m`, figures in `E:\reprocBackup_260824\task2_probe\`)

All recordings fs = 2000 Hz. For the eight 2026‑08 subjects **respiration moved to
CSC31** (respiration-band power fraction 0.53–0.83; CSC270 is a dead noise band).
`260227_EEG_NWU_HW` uses the old wiring (CSC270 respiration, no CSC31 data), so its
script is the unmodified template. Recording structure:

| subject | recordings | assignment |
|---|---|---|
| HW | 1 × 56.1 min | waveBreathing |
| CA | 1 × 68.1 min | alternating6Blocks (no movie recording — matches the sheet; 1 stray pulse @ 4075 s noted) |
| JH | 1 × 92.0 min combined | split: pulses 3525.0–5434.4 s → split sample 6,810,000 (3405.0 s = first pulse − 120 s) |
| MM | 1 × 93.7 min combined | split: pulses 3685.3–5599.8 s → split sample 7,130,600 (3565.3 s) |
| GP | 54.9 + 32.7 min | alternating = main, movie = `_0001` (180 pulses) |
| IS | 56.5 + 32.7 min | alternating = main, movie = `_0002` (`_0001` is a 16‑s false start) |
| AL | 56.5 + 32.3 min | alternating = main, movie = `_0001` |
| MS | 53.4 + 32.5 min | alternating = main, movie = `_0001` (2 stray… none; nanFrac 0.001 noted) |
| HK | 58.7 + 32.7 min | alternating = main (2 stray pulses @ 144 s), movie = `_0001` |

D7 check: JH/MM show exactly "no strong pulses, then a ~32‑min block of pulses"
(the weak early activity on CSC269 is screen luminance from the breathing display,
well below the |z|>3 pulse threshold). The other five dual-task subjects have two
separate recordings, no combined pattern. Split figures with the split marked are in
each session's figure folder and `E:\reprocBackup_260824\task2_probe\` (D7).

### Folder moves (step 2, all logged in the Task 2 payload output)

For each of the 9 subjects the Neuralynx `<datetime>` folder was **moved** into
`AtlasData\` (nothing deleted) and `raw\` / `preProc\` created. 9 moves total, e.g.
`…\260806_EEG_NWU_JH\2026-08-06_09-23-06` → `…\260806_EEG_NWU_JH\AtlasData\2026-08-06_09-23-06`.

### Scripts, extraction, verification (steps 3–5)

`batch/task2_writeLoadScripts.m` generated the **16 LoadData scripts** (one per
session × task, template-conformant; JH/MM scripts hard-code the split sample with a
derivation comment). All 16 ran green (`task2_runAll`, logs
`E:\reprocBackup_260824\task2_load_*.log`): waveBreathing 753 MB; alternating 654–798 MB;
movie 401–458 MB. `batch/task2_verifyRaw.m` checked every file: exact 37-label set
(`…, ECG1, ECG2, ECG3, rsp1, event`), fs 2000, durations in range, rsp/event carrying
signal — see `E:\reprocBackup_260824\task2_verify.log`.

### Sheet (step 6)

`batch/task2_writeSheet.m` set `Raw Data Extracted = X` and `datPre` on the 16
extracted rows via `writeParams` (new `AllowUnextracted`/`SetRawExtracted` options —
the sanctioned way to mark an extraction). CA has no movie row and none was invented.

---

## Task 3 — breathMetrics engine (Part A run 2026‑08‑25; **batch BLOCKED on a D8d stop‑and‑ask**)

### Integration (steps 1–2, 4)

breathmetrics vendored into `external/breathMetrics/` (lab fork
`qhyang42/breathmetrics` @ `9791153`, 2026‑08‑03; note + licence in README).
`shared/segmentBreaths_breathMetrics.m` returns the exact legacy 14‑column `bmObj`
(times in seconds; col 9 now the fs‑sample inhale‑peak index — the legacy internal
50‑Hz index had no consumers) plus `bmFeatures` (plain struct: every per‑breath
feature, shape/secondary features, conditioning record, `bmObjBreathIdx` row map).
`process_respiration_breathing` calls it (legacy `breathTemplates4` kept, not
called); cyclic‑sigh merging keeps the feature map aligned;
`build_behavior_table_breathingTask` appends `bm_*` columns (D8e; note: they land
before `goodBreath`/HRV, which `flagBadBreaths` appends later — access by name).
Run‑on‑guess (D4): `ZLP_ALLOW_GUESS_RUN=1` + EEG‑type check; `paramCheck` /
`paramCheckECG` save QC figures non‑interactively; guess rows are never promoted.
The whole Task 3 change set went through two adversarial review passes; the
confirmed findings (blank‑paramSource promotion, backup verify/delete holes,
one‑way sheet reconciliation, NaN input, figure leaks) are fixed and committed.

### Validation (step 3) — D8c/D8d

Old engine vs breathMetrics on the same trace, one‑to‑one matching within ±250 ms:

| session | Type | old breaths | new breaths | old→new | new→old | med \|dt\| | result |
|---|---|---:|---:|---:|---:|---:|---|
| 251008_EEG_NWU_GM | EEG | 1335 | 1352 | 98.8% | 97.6% | 12 ms | **PASS** |
| 251030_Dupi_NMH_DB_1 | Dupi | 121 | 183 | 96.7% | 63.9% | 26 ms | FAIL |
| 250908_OBE_NWU_AS | OBE | 485 | 484 | 80.6% | 80.8% | 40 ms | FAIL |

Every mandated conditioning fallback (100/250 ms smoothing, mean‑centering,
z‑scoring, `simple` baseline, combinations — `batch/task3_validateConditioning.m`)
moves these numbers by ≤ 1.5 points: the disagreement is structural.

**Evidence that the LEGACY engine is the main source of disagreement**
(overlay figures in `E:\reprocBackup_260824\bmValidation\`):

- DB_1 is a 14.7‑min recording; 183 breaths = 12.4/min (normal), legacy's 121 =
  8.2/min. In the zooms, long stretches show red (new) markers on unmistakable
  real breath cycles with no blue (legacy) marker — legacy skipped ~⅓ of real
  breaths, and the July final was built on those 121.
- AS: counts agree (485/484) and clean stretches match tightly; the ~19%
  disagreement concentrates in artifact/flat segments (legacy marks "breaths" on a
  flat line; breathMetrics is conservative) and ragged shallow‑breathing stretches
  (both detect, placement > 250 ms apart).

Per the work order ("stop and ask if any test session stays below 90 % after
that") the run was **halted and the decision escalated with the overlay figures.
Decision (2026‑08‑25): accept breathMetrics** — the evidence shows legacy
under‑detection (DB_1) and artifact-segment false breaths (AS), not breathMetrics
failure. Consequence: the ±10 % breath‑count check vs July finals is a
review‑flag (SOFT in `task3_verifyFinals`), not a failure; sessions like DB_1
will legitimately exceed it.

### Part B — the batch

Guesses written (`task3_writeGuesses`): HW = EEG standard set (rspFlip −1 =
modal of curated EEG rows, 14:7); RX_1 = OBEControl modal values (raw missing —
recorded for completeness). Batch launched 2026‑08‑25
(`E:\reprocBackup_260824\scripts\task3_run.ps1`): stage 1 backup+delete of every
eligible breathing final (tmp+rename verified backups, `task3_backupDelete`),
stage 2 `breathingTask_makeOutDat`, stage 3 `breathingTaskPreProc_main` with
`ZLP_ALLOW_GUESS_RUN=1` (HW runs on guess; all other guess rows skip early),
stage 4 `task3_verifyFinals` (structural failures clear the sheet X, soft
flags reported). Logs: `E:\reprocBackup_260824\task3_*.log`. *(Results section
to follow when the batch completes.)*

---

## Task 4 — O15 (run 2026‑08‑25)

Verified from disk (Task 1 inventory): **no curated O15 session pending**; GH_2's
July failure had already been fixed on disk (current final). The one stale
session, `260316_Dupi_NMH_PD_1`, got its single D6 attempt via
`batch/task4_runPD1.m` (scoped driver — the O15 main script is still in July's
REDO‑ALL configuration): **failed with the same documented error**
(`detect_ttls_O15: wrong trial count!`). The pre‑July final was backed up to
`E:\reprocBackup_260824\O15\` beforehand and remains on disk (valid but stale;
`Data Preprocessed` stays X per D2 disk truth).

Guesses written (`batch/task456_writeGuesses.m`), not run: RX_1 (inherited from
its curated cue row; O15 raw is on disk), SP_2 (OBE modal). JA_2 already carried
guess parameters. All appended to `guessSessions.md`. Files written: none
(PD_1's failed attempt saves only on success). Sheet rows changed: the guess
parameter cells listed in the task456 log.

---

## Task 5 — threshold (run 2026‑08‑25)

Verified from disk: **no curated threshold session pending**. No runs. Guesses
written for the blank rows RX_1 (inherited from its curated cue row), HM_2,
SP_2, KA_2 (OBE modal: respThresh 5000, cuedBackBuff 350, adjWin 500 — modal
pool is a single curated OBE thresh row; flagged in `guessSessions.md`); PD_2
and JA_2 already carried guesses. **KA_2 note:** its raw folders are named
`raw_threshTask` / `raw_cueTask`, which the existing makeOutDat globs
(`raw_PEAintensityPleasantness*` / `raw_cueTaskOdor*`) will not find — must be
resolved (rename on R: needs approval, or glob widening) before KA_2 can ever
run. Sheet rows changed: guess cells only.

---

## Task 6 — odor cue task (run 2026‑08‑25)

### Part A — no‑cue support (D9)

1. **Format documented.** Raw behavioral files
   (`R:\…\olf_cuetask_results\<id>\<id>_run{1,2}_cuelist_odor_results.{mat,txt}`)
   carry `n, cue, odor, trialtype, response, response_str, iti, trl_start,
   rsp_end`; `outMat_to_table` parses the .mat (`response==999` = missed).
   `cue` is numeric with **0 = no cue** (recent sessions: 60 trials, 20 no‑cue);
   `odor` runs 2–11 and is recoded −1 by the existing makeOutDat;
   `trialtype` is response‑key counterbalancing (1: 1=Yes, 2: 2=Yes) — not
   signal‑detection identity. `behDat` columns after makeOutDat:
   `n, cue, odor, trialtype, response, response_str, iti, trl_start, rsp_end,
   type`; the final per‑sniff table adds the `behDatFromSniffs` six + `adjust`,
   `finalOnset`, `manOnset`.
2. **Photodiode on no‑cue trials is UNCHANGED** (`batch/task6_probeNoCueTTL.m`
   on SP_2/RC_1/KA_2): every trial emits the trial‑start (cue‑length), sniff and
   response pulses — 60/60/60−missed observed against both count models. No TTL
   parse changes needed. (RX_1, already curated + current, has **no** cue==0
   trials — checked — so its final is unaffected by D9.)
3. **Change:** `cueTask_makeOutDat` types `cue==0` trials as `"noCue"`
   (hit/miss/cr/fa undefined there; `cue` column keeps 0; all other columns and
   names unchanged). **Backward compatibility proven**: `230611_OBE_NMH_AZ`
   rerun from raw with the new code — all 14 behDat columns identical to the
   July final (`batch/task6_diffAZ.m`, PASS; old final in
   `E:\reprocBackup_260824\cue\`).
4. **No‑cue validation up to the gate** (`batch/task6_validateNoCue.m`, SP_2):
   makeOutDat intermediate has 60 trials (20 noCue / 20 cr / 17 hit / 2 miss /
   1 skip, cue ∈ 0–10, odor recode applied); through the full shared pipeline
   58/60 trials got detected sniffs (the 2 drop‑outs are sniff‑detection QC for
   this guess session, not a coding issue), all surviving no‑cue rows typed
   `noCue`, `finalOnset` finite, `manOnset` NaN. **No final saved** (guess row).
   QC figures: `E:\reprocBackup_260824\task6_probe\SP2_QC`.

### Part B

Verified from disk: **no curated cue session pending**. Guesses written for
SP_2, RC_1, KA_2 (OBE modal; KA_2 has the raw‑folder naming issue above); PD_2
and JA_2 already carried guesses. makeOutDat also created the SP_2 and RC_1
intermediates in passing (normal guess‑session state; PD_2/JA_2 already had
theirs). No finals written; `Data Preprocessed` untouched.

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
recorded for completeness). Batch run 2026‑08‑25
(`E:\reprocBackup_260824\scripts\task3_run.ps1`): 42 finals backed up
(tmp+rename verified) to `E:\reprocBackup_260824\breathing\` and removed;
`breathingTask_makeOutDat` re-parsed every session from raw;
`breathingTaskPreProc_main` with `ZLP_ALLOW_GUESS_RUN=1`;
`task3_verifyFinals` reconciled the sheet from disk truth.
Logs: `E:\reprocBackup_260824\task3_*.log`.

### Part B results

**39 sessions reprocessed from raw and saved** (58 attempted). Verification:
**ok=19, soft-flag=20, bad=2, missing=17**. The soft flags are review items
(breath-count drift vs the July finals — expected under the accepted
breathMetrics engine, DB_1-style — and/or heart rates outside 45–110 bpm);
their finals are structurally complete and their X stands. The 2 bad =
`250623_Dupi_NMH_KS_3` (guess row; bare re-created intermediate, as before)
and `251120_Dupi_NMH_JL_1` (curated; failed with its **documented D6 error**
mid-pipeline — intermediate on disk, X cleared). The 17 missing are the
guess/not-run rows plus the documented failures:
`250623_Dupi_NMH_KS_2` (makeOutDat fails with its documented indexing error →
no file on R:; July stale final preserved at `E:\reprocBackup_260824\breathing\`;
X cleared) and `260227_EEG_NWU_HW` (**cannot run**: its closed-loop behavioral
CSV `experiment_EEGsync\processedBehavior\260227_EEG_NWU_HW.csv` was never
generated — generate it with `tidyDataImport_waveExp.R` and rerun; raw, guesses
and pipeline are all in place).

The 20 soft‑flagged sessions (breathMetrics breath count vs the July final;
finals kept, X kept — review):

| session | breaths (new vs July) | Δ |
|---|---|---|
| 250723_EEG_NWU_BK | 734 vs 625 | +17.4% |
| 250725_EEG_NWU_BN | 511 vs 430 | +18.8% |
| 250815_EEG_NWU_PP | 543 vs 476 | +14.1% |
| 250818_Dupi_NMH_JH_1 | 404 vs 334 | +21.0% |
| 250819_EEG_NWU_ZL | 599 vs 535 | +12.0% |
| 250912_EEG_NWU_JN | 501 vs 430 | +16.5% |
| 250811_Dupi_NMH_TPB_1 | 37 vs 32 | +15.6% |
| 251008_EEG_NWU_JC | 778 vs 1096 | **−29.0%** |
| 251009_EEG_NWU_JM | 1299 vs 897 | **+44.8%** |
| 250811_Dupi_NMH_TB_2 | 345 vs 302 | +14.2% |
| 250929_Dupi_NMH_GH_1 | 504 vs 330 | **+52.7%** |
| 251027_EEG_NWU_AS | 872 vs 791 | +10.2% |
| 251110_EEG_NWU_GA | 632 vs 858 | **−26.3%** |
| 251111_EEG_NWU_VW | 275 vs 802 | **−65.7%** |
| 251113_EEG_NWU_GH | 319 vs 480 | **−33.5%** |
| 251027_Dupi_NMH_DL_1 | 333 vs 299 | +11.4% |
| 250929_Dupi_NMH_GH_2 | 126 vs 86 | **+46.5%** |
| 251002_Dupi_NMH_AB_2 | 106 vs 144 | **−26.4%** |
| 251030_Dupi_NMH_DB_1 | 183 vs 121 | **+51.2%** |
| 251030_Dupi_NMH_DB_2 | 196 vs 149 | +31.5% |

(Bolded rows moved more than 25% — start the review there, especially VW at
−65.7%.)

**Segmentation QC (2026‑08‑25, `batch/task3_segQCfigs.m`; figures in
`E:\reprocBackup_260824\segQC\` and delivered in chat).** Six seeded 1‑min
overlay segments per >25% session show the two drift directions are different
animals. The *increases* (JM, GH_1, GH_2, DB_1, DB_2) are well segmented —
onsets on essentially every visible cycle — confirming July under‑counted.
The *decreases* (**VW, AB_2, JC, GA**) share a systematic miss pattern:
breaths in lower‑amplitude stretches go undetected when the recording also
contains much larger‑amplitude stretches (belt gain shifts / sniff bursts),
i.e. breathMetrics' global amplitude criterion rejects real breaths in quiet
epochs — VW is severe (whole minutes of clean breathing with zero onsets).
GH (−33.5%) is the one defensible decrease (burst‑and‑flat data).

**Resolution (round 9, 2026‑08‑26).** The engine now runs its detection on a
windowed‑amplitude‑normalized copy of the trace (60‑s moving std, floored at
0.05 × its median; raw data and `bmObj` amplitude units untouched —
`shared/segmentBreaths_breathMetrics.m`). VW, AB_2, JC, GA and GH were rebuilt
under it: VW 275→**895** (July 802), AB_2 106→**143**, JC 778→**975**, GA
632→**991**, GH 319→**475**. Validation showed no regression on well‑segmented
sessions (DB_1 183→184). The remaining 34 breathing finals and the 8
breathingTasks_separate finals still carry global‑amplitude detection (their
counts were plausible); every final records its own mode in
`bmFeatures.conditioning`, and the `breathingQualityCheck\` overlay folder
(one figure per breathMetrics final, mode in the title) is the review surface.

**Incident:** the Admin master workbook became unreadable (corrupt) during the
verification stage's write burst (VPN/SMB + rapid `writecell` full-rewrites).
The corrupt file is preserved at
`E:\reprocBackup_260824\dataTracking_corrupt_copy.xlsx`. The sheet was rebuilt
deterministically (`batch/rebuildSheet_260825.m`) from the pre-run backup +
replay of every logged mutation (11+41+16+9+2 cells — all counts exact), then
verification re-ran to rebuild the breathing flags from disk. Snapshots are now
taken after every write-heavy stage (`E:\reprocBackup_260824\dataTracking_*_snapshot.xlsx`).
The batch's SSH wrapper also died once mid-run (VPN blip); the MATLAB process
survived and completed — only stage sequencing needed manual resumption.

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

## Task 7 — EmotionalMovieTask pipeline (run 2026‑08‑25)

### Build (D10)

New task registered end‑to‑end (`applyParams` 'movie' keys, `preprocessAll`,
`writeParams`/`writePreProcX`): `emotionalMovieTask_makeOutDat.m` (photodiode →
clip table; process‑then‑check pulse grouping; 1/2/3 pulses = neutral/positive/
negative; clip end = next onset − 1.6 s), `assembleRaw_emotionalMovieTask.m`
(refuses to ingest an old final as an intermediate), a `_main` whose shared body
is byte‑identical to the other mains, and
`build_behavior_table_emotionalMovieTask.m` (per‑breath rows filtered to
in‑clip, `clipIndex`/`clipValence`/`clipOnset`, `task`=valence, `bm_*` columns).
**The final clip of each session has no end marker (old task code); its breaths
are dropped — confirmed acceptable.** ECG failure degrades to NaN‑HRV +
`ecgSkipped=2` instead of losing the session.

### Validation

AS_4 (old OBEControl) ran in memory up to the guess gate — no save, old final
untouched. TI_1's new‑format intermediate was saved (180 clips; 59/61/60 by
valence). Verifier bounds: clip count 150–210, valence balance, breaths > 0.

### Results — 7/7 EEG subjects saved + verified

All seven ran run‑on‑guess with **`rspFlip=+1`** (no flip — see the Task 8
polarity correction below) and **measured `beatSpec=1,0,lt,-3.5`** (the
2026‑08 rigs record ECG lead 1 inverted — discovered when the default spec gave
82 bpm of *negative* crossings on JH and ~2 bpm positive). Final counts after
the round‑9 rebuild (windowed‑amplitude engine, correct polarity):

| session | clips | in‑clip breaths | bpm |
|---|---|---|---|
| 260806_EEG_NWU_JH | 192 | 355 | 81 |
| 260806_EEG_NWU_MM | 189 | 443 | 73 |
| 260807_EEG_NWU_GP | 196 | 263 | 66 |
| 260810_EEG_NWU_IS | 190 | 373 | 55 |
| 260810_EEG_NWU_AL | 188 | 432 | 74 |
| 260811_EEG_NWU_MS | 192 | 376 | 80 |
| 260811_EEG_NWU_HK | 185 | 379 | 62 |

Two earlier generations of these finals (round 3: wrong beatSpec; round 3.5:
default `rspFlip=+1`, i.e. inverted respiration) are backed up at
`E:\reprocBackup_260824\movie\*_badECG*.mat` / `*_badFlip_r3.mat` — the current
finals supersede them. AS_4 / TI_1 / CP_1 stay not‑run (guess, non‑EEG, D4).

## Task 8 — alternating6Blocks pipeline (run 2026‑08‑25)

### Build (D11)

`parse_sniffLogicLog.m` (event column forced to char via `detectImportOptions`
— `readtable` silently coerces sparse text columns to numeric; event times
sorted; 30 s block‑gap tolerance; 1+3+3 structure assert),
`parse_mindfulBreathing.m` (12 questions × 8 sets split on >120 s gaps;
`order = set − 1`), `alignLogToRaw.m` (zero‑padded normalized xcorr at 20 Hz →
100 Hz refinement → 120 s sliding‑window drift fit; **the sign of the
correlation gives the empirical `rspFlip`** since SniffLogic pressure is
inhale‑negative; hard fail below \|r\|=0.40 or on an ambiguous peak, review
band 0.40–0.60), `alternating6Blocks_makeOutDat.m` (log↔subject matching ±3 h
unique), `assembleRaw_…`, `build_behavior_table_…` (NaN‑prefilled rating
columns), and a `_main` that errors if the sheet `rspFlip` contradicts the
log‑derived polarity.

### Alignment results (all 8 subjects) — and a polarity correction

All eight aligned with corrSign +1, \|r\| = 0.81–0.92 except **MS at 0.47**
(unique peak — its cannula tube was partially unplugged for ~23% of the
recording, attenuating the trace; accepted with a REVIEW flag). Clock drift
−13…+161 ppm (MS −390 ppm). All eight logs parse to the perfect 7 × 6.0‑min
block structure. **Polarity correction (2026‑08‑26):** the first pass mapped
corrSign +1 to `rspFlip=−1` on the assumption that SniffLogic logs pressure
inhale‑negative; lab inspection showed detections landing on *exhale* onsets —
the log's pressure column is inhale‑POSITIVE, so corrSign +1 means **no flip
(`rspFlip=+1`) for the entire August cohort**. `alignLogToRaw` now maps the
sign directly and every August final was rebuilt at +1 in round 9.

### Results — 8/8 saved + verified (round‑9 rebuild)

JH 749 / MM 542 / GP 510 / IS 541 / AL 478 / MS 389 / HK 423 breaths across 7
blocks each, HRV 58–87 bpm (beatSpec `1,0,lt,-3.5`, same measured basis as Task
7). MS runs with an amplitude‑norm floor of 0.02 (vs the 0.05 default) to
recover its leak‑attenuated section — validated by overlay before the rebuild.
**CA: 397 in‑block breaths, HRV 62 bpm, blink removal skipped — REVIEW.** CA's first pass failed because *both* blink channels flunked
`blinkRemoveWrapper`'s quality criteria; `shared/preprocess_eeg` now degrades
that specific condition to the already‑defined `blinkRemoval=0` state (warning
+ REVIEW) instead of losing the session. CA's ECG initially probed as "no
cardiac signal" (~10 bpm symmetric), but that was the *global z‑score being
swamped by intermittent noise bursts* (~5% of 10‑s windows at 10–100×
amplitude): with the bursts blanked (per‑session special case in `buildECGz`,
see `batch/task8_probeCA2.m` / `task89_probeBlankSim.m`), a clear 62‑bpm
rhythm emerges and the final carries real HRV under the standard
`1,0,lt,-3.5` spec (ch3⁻ is the cleanest lead — 62.0 vs 2.9 bpm asymmetry —
if review wants a respec). An ECG viability probe (<20 bpm ⇒ NaN HRV,
mirroring Task 9's) now guards the movie and alternating mains; RY_1 remains
the only genuinely signal‑free session (0% noisy windows, ≤14 bpm robust).
CA's three superseded generations sit in `E:\reprocBackup_260824\alt6\`. (The
rebuilds also tripped the §2 case‑insensitivity quirk — deleting the "final"
deletes the intermediate too; makeOutDat regenerates it, alignment
bit‑identical. One transient sheet‑lock error required rewriting CA's X flag
afterwards.)

## Task 9 — breathingTasks_separate pipeline (run 2026‑08‑25)

### Build (D12)

One session = several sheet rows whose `Task` is a condition name; each
condition recording goes through the **entire shared core separately** (filters,
ICA, breath segmentation never straddle a file boundary), then
`concatSections.m` stitches data/bmObj/bmFeatures/heartBeats with sample
offsets, per‑section EEG QC, a `sections` table and a breathing‑style
`TTL = [start end …]` vector. Chronological ordering of condition files uses
the Neuralynx channel‑suffix (`''`/`_000N`) plus the acquisition‑folder
datetime recovered from the fieldtrip `cfg.previous` provenance chain.
`writeSheetSep.m` writes params/X to **every** in‑scope condition row.
Breaths whose QC window crosses a section boundary get `goodBreath=0`.

### Results — 8/8 sessions saved + verified

Single‑file: GH_1 (99 breaths, 62 bpm), DL_1 (323, 61), ZF_1 (195, 46), RY_1
(42, HRV NaN — **no cardiac signal on any lead**, probe ≤6.5 bpm both
polarities). Multi‑file: HM_2 (4 sections, 159 breaths, 68 bpm), SP_2 (3
sections, 257 breaths, 67 bpm), RC_1 (4 sections, 610 breaths, 51 bpm), KA_2
(1 section, 88 breaths, 61 bpm) — their first‑pass HRV used default specs
and came out implausible, so `batch/task9_probeECGpolarity.m` measured beat
rate per channel × polarity on the saved finals and `batch/task9_respecs.m`
wrote the winners (HM_2 `3,0,lt,-3.5` 67.9 bpm; SP_2 `2,0,gt,3.5` 67.7; RC_1
`1,0,lt,-3.5` 51.0; KA_2 `1,0,lt,-3.5` 61.1) before a rerun; the superseded
finals are at `E:\reprocBackup_260824\sep\*_badECG_r4.mat`.
**HM_2's sleep section has only 5 detected breaths in 18.8 min — inspect the
respiration trace.**

### Debugging record (rounds 2→5, for future maintainers)

The three new pipelines went through five batch rounds; root causes fixed along
the way, all committed: `readtable` numeric‑coercion of the SniffLogic event
column; unsorted log event times; three separate unequal‑length `'normalized'`
`xcorr` calls (coarse, refine, drift window); a MATLAB regexp quirk (a capture
group inside an optional non‑capturing group returns empty `tokens` even on a
match); `struct('f', cellArray)` building struct arrays; **`assert` evaluates
its message arguments eagerly** (a `strjoin` in a passing assert's message
crashed every multi‑file session — labels contain string objects from
`preprocess_eeg`'s `"blinkIndicator"`/`"badTS"` appends, which `strjoin`
rejects); the inverted ECG lead on all 2026 summer rigs; and the blink‑channel
degrade above. Full stack traces (`getReport`) now print in every main's catch.

## QC round 2 — breath-detection review fixes + engine v3b + full re-detection (2026‑08‑26 → 27)

### The review (breath_detection_qc_notes.md) and the fixes

The manual review of the first `breathingQualityCheck` set found four systematic
problems. Fixes, all in `shared/segmentBreaths_breathMetrics.m` (engine **v3b**,
stamped in every final's `bmFeatures.conditioning.engineVersion`):

1. **Whole‑minute dropouts** (SM, AK, GJ, AS, HM_2, DL_1 — all pre‑windowed
   finals) → every final now uses the windowed normalization; window shortened
   60 s → **30 s** (faster adaptation at loud↔quiet transitions).
2. **Trough/peak‑placed onsets (1–3 s bias)** → **middle‑50% band correction**:
   any onset outside the local 25–75th percentile band relocates to the nearest
   upward p25 crossing (±3 s, never past a neighboring onset; engine originals
   kept in `bmFeatures.engineInhaleOnsets`).
3. **Double‑peak midpoints / ragged over‑detection** → **150 ms detection
   smoothing** before normalization.
4. **MS's leak section** (partially unplugged cannula tube) → **excluded**
   (`blankBelowFrac=0.10` zeroes sub‑floor stretches in the detection copy),
   per the review, instead of amplified.

Validation ran against the notes' exact flagged minutes before any rerun
(`batch/task10_validateV3.m`, figures `E:\reprocBackup_260824\v3check\`):
dropout minutes recovered, onsets moved to the rising edge, double peaks
merged, controls stable (DB_1 183→184, ZL 599→597, AB_1 244→242). Two
engineering dead‑ends are recorded for posterity: a robust moving‑MAD scale
collapsed sparse sharp breathing (MAD tracks the noise floor; peaks are
outliers it ignores) and was replaced by moving std; and helper‑function
arguments evaluate eagerly in MATLAB (the onset relocation crashed at the
first/last onset until the neighbor limits used explicit branches).

### Round 10 — every breathMetrics final re‑detected

All 62 finals were backed up (`E:\reprocBackup_260824\r10\`), deleted, and
rebuilt from raw under v3b. (First attempt deleted nothing: v7.3 files hide a
`#refs#` group that sorts first, so the variable group must be found by name —
`batch/task11_backupDelete.m`. Two breathing sessions, GH and ADtest, lost
their first rebuild to parfor‑load artifacts — a spurious SMB "file not found"
and an out‑of‑memory — and were rebuilt in a light repair pass.)

Verification: **breathing ok=20 soft=19 bad=2 missing=17** (the 2 bad are the
documented KS_3/JL_1 bare intermediates; the 17 missing are all documented
blockers — see Part 2); **movie 7/7, alternating 8/8, separate 8/8 OK**.
Alt6/movie final counts are *in‑task‑window* (alt6 keeps in‑block breaths,
movie in‑clip): e.g. JH alt6 stores 748 of 925 whole‑recording breaths — the
windowed engine's recoveries live mostly in between‑block rests, correctly
excluded. Verified explicitly for JH movie: whole‑recording 421, in‑clip 359,
stored 359. **The `breathingQualityCheck` overlays now shade out‑of‑window
time gray** so intentionally empty minutes cannot read as detection dropout.

### Part 2 — Dupi/OBE guessed breathingTask sessions

`batch/task12_probeParams.m` measures per session: beatSpec (channel ×
polarity × threshold sweep, side‑margin scored), macroRemove (railing ≥2% of
samples or a ≥5 s pinned run), spikeClean (|z|>10 events >2/min), hasEEG=true.
The breathing main accepts non‑EEG guess runs under `ZLP_ALLOW_GUESS_RUN_ALL=1`.

Outcome: **no Dupi/OBE guess session could be fully preprocessed** —
- **12 sessions missing their closed‑loop behavioral CSV**
  (`experiment_EEGsync\processedBehavior\<id>.csv` — generate with
  `tidyDataImport_waveExp.R`, then rerun): JL_2, TB_3, GH_3, AB_3, JN_3,
  BS_1, AD_1, AD_2, PD_1, JA_1, JA_2, BW_1. (HW has the same blocker.)
- **PC_2**: makeOutDat "load file not identified uniquely" (ambiguous
  LoadData script) — needs a human look at its session folder.
- **PD_2**: no breathing raw on disk (sheet says extracted).
- **KS_3**: parameters were successfully measured (beatSpec `1,0,gt,3.5`,
  61 bpm at 12× margin; 6 macros, none railing; spikeClean=0 — written to its
  sheet row) but the main still fails mid‑pipeline with its documented
  "Index must not exceed 2" error — same class as JL_1's. Both remain bare
  intermediates, sheet flags clear.

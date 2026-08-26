# Summary — 2026‑08‑24 work order (all 9 tasks complete)

Everything in `Tasks_260824.md` is done. Full detail: [runReport_260824.md](runReport_260824.md)
(per‑task record), [guessSessions.md](guessSessions.md) (every guessed parameter set),
[inventory_260824.csv](inventory_260824.csv) (disk↔sheet inventory). This file is the
need‑to‑know digest plus your **manual‑checking list**.

## Headline results

| Task | Outcome |
|---|---|
| 1 Inventory + sheet sync | `Data Preprocessed` now mirrors the disk everywhere; discrepancies documented |
| 2 EEG extraction | 16/16 new raw recordings extracted + verified (9 subjects; JH/MM shared-folder splits verified against movie pulse times) |
| 3 breathMetrics engine | **39 breathing finals rebuilt** on breathMetrics (19 clean, 20 soft‑flags for review, list below); legacy engine retired after validation showed its errors |
| 4 O15 | No curated session was actually pending (sheet drift); PD_1 re‑attempt fails with its documented "wrong trial count!" — original final intact |
| 5 threshold | Same story — sheet drift, no valid pending curated session |
| 6 cue no‑cue | `type='noCue'` support landed (cue==0); validated on SP_2 to the guess gate; no curated session pending |
| 7 EmotionalMovieTask | **New pipeline; 7/7 EEG subjects preprocessed + verified** (185–196 clips, 55–81 bpm) |
| 8 alternating6Blocks | **New pipeline; 8/8 subjects preprocessed + verified** (7 blocks each; SniffLogic log alignment gives each subject's empirical rspFlip) |
| 9 breathingTasks_separate | **New pipeline; 8/8 sessions preprocessed + verified** (per‑condition-file processing, then concatenation) |

The tracking sheet now lives at **`Admin\Data\dataTracking.xlsx`** (the old stale copy
there was overwritten with the up‑to‑date master and `labPaths` now points at it — the
copy at `Admin\dataTracking.xlsx` is no longer read by the code).

## Your manual‑checking list

Everything below ran **on guessed parameters** (paramSource stays `guess`) or carries a
specific review flag. QC figures: `R:\…\Lab_Common\Adam\Dupi_processing\<id>\`.

### Highest priority — specific anomalies

| Session | Task | What to check |
|---|---|---|
| 260805_EEG_NWU_CA | alternating6Blocks | **Blink removal skipped** (both blink channels failed QC). ECG first probed as signal‑free, but noise bursts were swamping the z‑score — with the bursts blanked (per‑session special case in `buildECGz`) a clean **62 bpm** rhythm emerged and the final has real HRV. Check the ECG/blink QC figures. |
| 251006_OBE_NWU_RY_1 | breathingTasks_separate | **No cardiac signal on any ECG lead** (≤14 bpm even robust‑normalized, 0% noisy windows — genuinely absent, not masked) → HRV = NaN. |
| 251111_EEG_NWU_VW + 251002_Dupi_NMH_AB_2, 251008_EEG_NWU_JC, 251110_EEG_NWU_GA | breathingTask | **Segmentation QC (overlay figures) shows systematic breath under‑detection** in lower‑amplitude stretches (breathMetrics' global amplitude criterion vs. non‑stationary belt amplitude). VW is severe (−65.7%; whole minutes of clean breathing, zero onsets). **Don't analyze these four breath tables as‑is.** Figures: `E:\reprocBackup_260824\segQC\`. |
| 260811_EEG_NWU_MS | alternating6Blocks + EmotionalMovieTask | **Weak SniffLogic alignment** (\|r\|=0.47 vs 0.81–0.92 for everyone else) and −390 ppm clock drift; rspFlip=−1 was applied — eyeball the respiration trace to confirm polarity. Low breath count (272). |
| 260625_OBE_NWU_HM_2 | breathingTasks_separate | Sleep section: **only 5 detected breaths in 18.8 min** — inspect the respiration trace for that section. |
| 260227_EEG_NWU_HW | breathingTask | **Could not run**: its processedBehavior CSV was never generated (run `tidyDataImport_waveExp.R` in `experiment_EEGsync`, then rerun). |
| 260316_Dupi_NMH_PD_1 | O15 | Re‑attempt reproduces the documented "wrong trial count!" — photodiode needs human inspection; July final intact. |

### Run‑on‑guess sessions (verify parameters from the QC figures, promote to `curated`)

- **EmotionalMovieTask (7):** JH, MM, GP, IS, AL, MS, HK (all 2608xx_EEG_NWU). All used
  empirical rspFlip=−1 + measured beatSpec `1,0,lt,-3.5`.
- **alternating6Blocks (8):** CA + the same seven.
- **breathingTasks_separate (8):** HM_2, SP_2, RC_1, KA_2, GH_1, DL_1, RY_1, ZF_1.
  HM_2/SP_2/RC_1/KA_2 use **measured** beatSpecs (see guessSessions.md).
- **breathingTask:** the July‑era EEG run‑on‑guess sessions from Task 3 (see below).

### Task 3 soft‑flags (20 breathing finals — saved, but review breath counts)

These finals verified structurally but their breathMetrics breath count differs >10%
from the July final. The list with per‑session counts is in
[runReport_260824.md](runReport_260824.md) §Task 3 Part B. **Overlay QC on the ten
>25% movers** (six random 1‑min segments each; figures in
`E:\reprocBackup_260824\segQC\`) split them cleanly: the count *increases* (JM,
GH_1, GH_2, DB_1, DB_2) are correctly segmented — July under‑counted; the count
*decreases* (VW, AB_2, JC, GA — GH excepted, odd burst‑like data) are **real
under‑detection** in low‑amplitude epochs and should not be analyzed as‑is (see
the priority table above). The ≤25% movers remain ordinary review items.

### Not run (guess rows waiting for you; parameters already on the sheet)

Full tables in [guessSessions.md](guessSessions.md): 18 breathingTask rows, 3 O15,
6 threshold, 5 cue, and the 3 old OBEControl movie sessions (AS_4, TI_1, CP_1 — TI_1's
new‑format intermediate with 180 clips is already saved, so its main will run once you
promote its row).

## Issues that need your attention (beyond the checklist)

1. **The 2026 rigs record ECG lead 1 inverted.** Measured on JH (2 884 R‑peaks below
   −3.5 σ vs 108 above). Every Aug‑2026 EEG subject uses beatSpec `1,0,lt,-3.5`; the
   summer OBE sessions needed per‑session measurement (HM_2 `3,0,lt,-3.5`, SP_2
   `2,0,gt,3.5`, RC_1/KA_2 `1,0,lt,-3.5` — probe: `batch/task9_probeECGpolarity.m`).
   Worth fixing the lead wiring before the next cohort.
2. **RY_1 has no cardiac signal at all** (verified with robust normalization) —
   electrode contact. CA initially looked the same but its rhythm was recoverable
   (noise bursts were masking it — see the checklist); worth a look at what caused
   CA's bursts regardless.
2b. **breathMetrics under‑detects breaths when belt amplitude is non‑stationary**
   (VW/AB_2/JC/GA): its amplitude criterion is global, so quiet‑epoch breaths
   drop out when the same recording contains large bursts or gain shifts. If you
   want these four rescued, a sliding‑window amplitude normalization ahead of
   segmentation (per‑session or as an engine option) is the obvious candidate —
   prototype offered, not built.
3. **Missing raw data vs sheet**: PD_2 breathing (sheet says extracted, no raw on
   disk), RX_1 breathing (same), DB_3 breathing (raw not on server yet).
4. **KA_2's cue/thresh raw folders** are named `raw_cueTask`/`raw_threshTask` —
   the makeOutDat glob won't find them; rename or special‑case before running.
5. **Sheet corruption incident (2026‑08‑25):** the Admin master corrupted during a
   write burst; it was rebuilt deterministically (`batch/rebuildSheet_260825.m`) and
   verified; per‑stage snapshots now live at `E:\reprocBackup_260824\dataTracking_*_snapshot.xlsx`.
   Nothing was lost, but keep an eye out for anything odd in the sheet.
6. **Pre‑existing `flagBadBreaths` quirk** (shared code, unchanged): rows with
   `goodBreath==0` still get `maxRR/minRR` from a window that may be invalid — mask by
   `goodBreath` before using HRV columns.
7. **Movie task: the final clip of each session has no end marker** (old task code) —
   its breaths are dropped (you confirmed this is fine; it costs ~1 clip in ~190).
8. **250811_Dupi_NMH_TPB_1→TB_1 remap and the other naming quirks** are unchanged and
   still documented in CLAUDE.md §7.

## Where things are

- **Superseded finals** (every file that was overwritten or replaced this run):
  `E:\reprocBackup_260824\` — `breathing\` (July finals), `movie\`, `alt6\`, `sep\`
  (intermediate bad‑parameter generations), plus all run logs (`task*_*.log`) and
  sheet snapshots. **These are the only copies — don't clean E: without checking.**
- **New finals**: written directly to `R:` in each session's `preProc\` folder;
  every one verified (`fs=500`, `moreThan1`, `manOnset`/task equivalents, breathing
  extras) before its sheet `X` was set.
- **Run‑on‑guess QC figures**: `R:\…\Adam\Dupi_processing\<id>\` (fallback
  `E:\reprocBackup_260824\guessQC\<id>\`).
- **Per‑breath CSVs**: the lab‑desktop `processedBehavior\` folder (per `labPaths`),
  one per new breathing‑type final.

## Decisions made while you were away (per your "decide and log" instruction)

1. **MS's weak alignment (\|r\|=0.47) was accepted** with a REVIEW flag rather than
   failing the session: the peak is unique (runner‑up 0.26) and the lag sits in the
   same family as every other subject. Hard‑fail threshold is now \|r\|<0.40.
2. **RY_1's HRV set to NaN** (no cardiac signal on any lead, confirmed robustly)
   rather than saving implausible RRint; a viability probe (<20 bpm ⇒ NaN) now
   guards all three new mains. **CA's HRV was recovered** after your mid‑run
   correction: its "absent" rhythm was the global z‑score being swamped by noise
   bursts; `buildECGz` now blanks CA's noisy windows (per‑session special case)
   and the final carries a real 62 bpm. CA's sheet spec stays `1,0,lt,-3.5`
   (what the final was built with; ch3⁻ is the cleaner lead if review prefers).
3. **CA's blink removal skipped** (both blink channels failed wrapper QC) via a narrow
   degrade in `shared/preprocess_eeg` to the already‑defined `blinkRemoval=0` state.
4. **Beat specs for HM_2/SP_2/RC_1/KA_2 were measured, not guessed** (per‑channel ×
   polarity probe on the saved finals), and the sessions rerun with the winners.
5. **The three old OBEControl movie sessions were not run** (D4: only EEG‑type guess
   rows run unattended); their guess rows are written and TI_1's intermediate is saved.
6. **`batch/` scripts stay in the repo** — they are the executable record of this work
   order (probes, guess writers, verifiers, the sheet rebuild). Nothing else was left
   behind; scratch lived on E: and in the session scratchpad, not in the repo.
7. **Two earlier generations of the 7 movie finals were replaced** (wrong beatSpec,
   then wrong rspFlip) — both generations are in the E: backup, the sheet was never
   left pointing at a bad final.

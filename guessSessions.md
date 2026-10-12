# Guess sessions — running list (Tasks_260824.md D5)

One row per session × task. `basis`: inherited from `<task>` / Type default / inspected.
`status`: not run / run-on-guess. Appended by each task as it executes; QC figure
folder = `R:\…\Lab_Common\Adam\Dupi_processing\<id>\` unless noted (run-on-guess
fallback: `E:\reprocBackup_260824\guessQC\<id>\`).

## breathingTask (Task 3)

Pre-existing `guess` rows (parameters already on the sheet; per D4 only
`EEG_breathing` guess rows run — none of these are EEG, so all are **not run**):

| Subject ID | Task | Type | sheet row | guessed columns | basis | status | notes |
|---|---|---|---|---|---|---|---|
| 250623_Dupi_NMH_KS_3 | breathingTasks | OBE_Dupi | 137 | (existing sheet values) | pre-existing guess | not run | bare intermediate (2026-06-09) on disk |
| 251110_Dupi_NMH_PC_2 | breathingTasks | OBE_Dupi | 173 | (existing) | pre-existing guess | not run | |
| 251120_Dupi_NMH_JL_2 | breathingTasks | OBE_Dupi | 178 | (existing) | pre-existing guess | not run | |
| 250811_Dupi_NMH_TB_3 | breathingTasks | OBE_Dupi | 182 | (existing) | pre-existing guess | not run | |
| 250929_Dupi_NMH_GH_3 | breathing tasks | OBE_Dupi | 186 | (existing) | pre-existing guess | not run | |
| 251002_Dupi_NMH_AB_3 | breathing tasks | OBE_Dupi | 190 | (existing) | pre-existing guess | not run | |
| 260326_OBE_NWU_AD_1 | breathingTasks | OBEControl | 195 | (existing) | pre-existing guess | not run | |
| 251013_Dupi_NMH_JN_3 | breathing tasks | OBE_Dupi | 204 | (existing) | pre-existing guess | not run | |
| 260406_Dupi_NMH_BS_1 | breathing tasks | OBE_Dupi | 208 | (existing) | pre-existing guess | not run | |
| 260326_OBE_NWU_AD_2 | breathingTasks | OBEControl | 213 | (existing) | pre-existing guess | not run | |
| 260316_Dupi_NMH_PD_1 | breathingTasks | OBE_Dupi | 223 | (existing) | pre-existing guess | not run | |
| 260504_Dupi_NMH_JA_1 | breathingTasks | OBE_Dupi | 228 | (existing) | pre-existing guess | not run | |
| 260514_OBE_NWU_BW_1 | breathingTasks | OBEControl | 236 | (existing) | pre-existing guess | not run | |
| 260316_Dupi_NMH_PD_2 | breathingTasks | OBE_Dupi | 258 | (existing) | pre-existing guess | not run | **no breathing raw on disk** despite sheet X |
| 260504_Dupi_NMH_JA_2 | breathingTasks | OBE_Dupi | 275 | (existing) | pre-existing guess | not run | |
| 251030_Dupi_NMH_DB_3 | breathingTasks | OBE_Dupi | 301 | (existing) | pre-existing guess | not run | raw not on server yet |

New guesses written by `batch/task3_writeGuesses.m` (2026-08-25):

| Subject ID | Task | Type | sheet row | guessed columns = values | basis | status | notes |
|---|---|---|---|---|---|---|---|
| 260227_EEG_NWU_HW | waveBreathing | EEG_breathing | 177 | rspIDX=1, rspFlip=−1 (modal of 21 curated EEG rows, 14:−1/7:+1), hasEEG=true, hasMacros=false, spikeClean=false, spikeThresh=20, spikeWin=11, macroRemove=[], beatSpec=1,0,gt,3.5, isNewStd=true | Type default (EEG standard set, §0 D3.3) | run-on-guess (D4) | extracted in Task 2; rsp = CSC270 (old wiring) |
| 260608_OBE_NWU_RX_1 | breathingTasks | OBEControl | 250 | rspIDX=3, rspFlip=1, hasEEG=true, hasMacros=true, spikeClean=true, spikeThresh=20, spikeWin=11, beatSpec=`1,0,lt,-2 & 2,1,gt,3 & 3,2,lt,0`, isNewStd=true | Type default (modal of 3 curated OBEControl breathing rows) | not run | breathing raw missing on disk; sheet says extracted |

(The `251009_EEG_NWU_SM` row 66 stub is a duplicate of curated row 81 — not a guess session.)

## O15 (Task 4)

| Subject ID | Task | Type | sheet row | guessed columns = values | basis | status | notes |
|---|---|---|---|---|---|---|---|
| 260504_Dupi_NMH_JA_2 | O15 | OBE_Dupi | 276 | (existing sheet values) | pre-existing guess | not run | |
| 260608_OBE_NWU_RX_1 | O15 | OBEControl | 248 | rspIDX=1, rspFlip=1, hasEEG=false, spikeClean=true, spikeThresh=20, spikeWin=11, respThresh=3000, cuedBackBuff=150, adjWin=500, isNewStd=true | inherited from same-session curated cue row (252) | not run | O15 raw on disk |
| 260702_OBE_NWU_SP_2 | O15 | OBEControl | 286 | same values as RX_1 O15 | Type default (modal of 9 curated OBE O15 rows) | not run | |

## threshold (Task 5)

| Subject ID | Task | Type | sheet row | guessed columns = values | basis | status | notes |
|---|---|---|---|---|---|---|---|
| 260316_Dupi_NMH_PD_2 | threshold | OBE_Dupi | 261 | (existing) | pre-existing guess | not run | |
| 260504_Dupi_NMH_JA_2 | threshold | OBE_Dupi | 278 | (existing) | pre-existing guess | not run | |
| 260608_OBE_NWU_RX_1 | threshold | OBEControl | 253 | rspIDX=1, rspFlip=1, hasEEG=true, spikeClean=true, spikeThresh=20, spikeWin=11, respThresh=5000, cuedBackBuff=350, adjWin=500, isNewStd=true | inherited from same-session curated cue row (252); windows = modal curated OBE threshold values | not run | thresh raw on disk |
| 260625_OBE_NWU_HM_2 | threshold | OBEControl | 266 | same values | Type default (modal; pool = 1 curated OBE thresh row) | not run | |
| 260702_OBE_NWU_SP_2 | threshold | OBEControl | 287 | same values | Type default | not run | |
| 260720_OBE_NWU_KA_2 | threshold | OBEControl | 313 | same values | Type default | not run | **raw folder named `raw_threshTask` — makeOutDat glob will not find it** |

## odor cue task (Task 6)

| Subject ID | Task | Type | sheet row | guessed columns = values | basis | status | notes |
|---|---|---|---|---|---|---|---|
| 260316_Dupi_NMH_PD_2 | odor cue task | OBE_Dupi | 260 | (existing) | pre-existing guess | not run | intermediate exists |
| 260504_Dupi_NMH_JA_2 | odor cue task | OBE_Dupi | 277 | (existing) | pre-existing guess | not run | intermediate exists |
| 260702_OBE_NWU_SP_2 | odor cue task | OBEControl | 281 | rspIDX=1, rspFlip=1, hasEEG=true, spikeClean=true, spikeThresh=20, spikeWin=11, respThresh=3000, cuedBackBuff=150, adjWin=500, isNewStd=true | Type default (modal of 8 curated OBE cue rows) | not run (validated up to gate) | 20/60 no-cue trials; QC figs `E:\reprocBackup_260824\task6_probe\SP2_QC` |
| 260622_OBE_NWU_RC_1 | odor cue task | OBEControl | 292 | same values | Type default | not run | 20/60 no-cue trials |
| 260720_OBE_NWU_KA_2 | odor cue task | OBEControl | 307 | same values | Type default | not run | **raw folder named `raw_cueTask` — makeOutDat glob will not find it**; 20/60 no-cue |

## EmotionalMovieTask (Task 7)

EEG subjects (all run-on-guess, D4): EEG standard set — rspIDX=1, hasEEG=true,
hasMacros=false, spikeClean=false, spikeThresh=20, spikeWin=11, macroRemove=[],
isNewStd=true — plus **empirical rspFlip=+1, i.e. no flip** (each subject's
SniffLogic log-alignment polarity; the log pressure column is inhale-positive —
an earlier −1 inference was corrected 2026-08-26 and all finals rebuilt) and
**beatSpec=`1,0,lt,-3.5`** (2026‑08 rigs record ECG lead 1 inverted; measured
80.8 bpm on JH vs 3.1 with the default). QC figures per session under
`R:\…\Adam\Dupi_processing\<id>\`.

| Subject ID | Task | Type | guessed columns = values | basis | status | notes |
|---|---|---|---|---|---|---|
| 260806_EEG_NWU_JH | EmotionalMovieTask | EEG_breathing | EEG standard + rspFlip=+1 (no flip), beatSpec=1,0,lt,-3.5 | empirical (log align \|r\|=0.92) | run-on-guess | 192 clips, 355 breaths, 81 bpm |
| 260806_EEG_NWU_MM | EmotionalMovieTask | EEG_breathing | same | empirical (\|r\|=0.86) | run-on-guess | 189 clips, 443 breaths, 73 bpm |
| 260807_EEG_NWU_GP | EmotionalMovieTask | EEG_breathing | same | empirical (\|r\|=0.83) | run-on-guess | 196 clips, 263 breaths, 66 bpm |
| 260810_EEG_NWU_IS | EmotionalMovieTask | EEG_breathing | same | empirical (\|r\|=0.91) | run-on-guess | 190 clips, 373 breaths, 55 bpm |
| 260810_EEG_NWU_AL | EmotionalMovieTask | EEG_breathing | same | empirical (\|r\|=0.81) | run-on-guess | 188 clips, 432 breaths, 74 bpm |
| 260811_EEG_NWU_MS | EmotionalMovieTask | EEG_breathing | same | empirical (**\|r\|=0.47 — weak, REVIEW**) | run-on-guess | 192 clips, 376 breaths, 80 bpm; alignment weak (NaN-gap recording) |
| 260811_EEG_NWU_HK | EmotionalMovieTask | EEG_breathing | same | empirical (\|r\|=0.81) | run-on-guess | 185 clips, 379 breaths, 62 bpm |
| 250225_OBE_NWU_AS_4 | EmotionalMovieTask | OBEControl | rspIDX=1, rspFlip=+1 (curated row 12), hasEEG=**false** (no cap), hasMacros=true, spikeClean=false, beatSpec=1,0,gt,3.5 | inherited + old getSessionParams_emotionTask | not run (validated up to gate in memory) | old final left untouched |
| 250904_OBE_NWU_TI_1 | EmotionalMovieTask | OBEControl | rspIDX=3, rspFlip=+1 (curated row 49), hasEEG=true, spikeClean=true, spikeThresh=**50**, beatSpec=`1,0,lt,-2 & 2,1,gt,3 & 3,2,lt,0` | inherited + old script values | not run | new-format intermediate saved (180 clips, 59/61/60 by valence) |
| 251009_OBE_NWU_CP_1 | EmotionalMovieTask | OBEControl | rspIDX=1, rspFlip=+1 (curated row 77), hasEEG=true, spikeClean=true, spikeThresh=**15**, spikeWin=**7**, macroRemove=**6**, beatSpec=`3,0,lt,-3` | inherited + old script values | not run | old final left untouched |

**Clip norms reprocess (2026-10-12, branch `respiratorySweep-261008` @ ef9e943, lab desktop).** Every EEG movie
session with a PsychoPy clip log was rebuilt (makeOutDat + main) so that `TTL` carries `fileName`, `vidLenSec`,
`normValence/Arousal/Impact` (DEVO2 per-clip means, not participant ratings), `movieStart/movieStop`, and each
breath its clip's title and norms. The pre-rebuild finals, their figures and processed-behavior CSVs are in
`E:\reprocBackup_261012_movie\<id>\` on the lab desktop. All 10 passed verification (fs, `moreThan1`, `manOnset`,
new columns finite, behDat joins TTL, norms equal the CSV, heart beats and badChans unchanged):

| Subject ID | clips kept / played (before) | dropped detections | valences corrected | clock segments | in-clip breaths (before) |
|---|---|---|---|---|---|
| 260806_EEG_NWU_JH | 180 / 180 (192) | 12 | 10 | 1 | 342 (363) |
| 260806_EEG_NWU_MM | 180 / 180 (189) | 64 | 7 | **2** (offset +0.80 s from clip 44) | 403 (435) |
| 260807_EEG_NWU_GP | 180 / 180 (196) | 16 | 10 | **2** (offset +0.36 s from clip 135) | 257 (255) |
| 260810_EEG_NWU_IS | 180 / 180 (190) | 10 | 12 | 1 | 356 (356) |
| 260810_EEG_NWU_AL | 179 / 180 (188) | 62 | 11 | 1 (median residual 41 ms) | 429 (430) |
| 260811_EEG_NWU_MS | 180 / 180 (192) | 63 | 13 | 1 (median residual 33 ms; PsychoPy stall in clips 54–55) | 379 (379) |
| 260811_EEG_NWU_HK | 180 / 180 (185) | 60 | 2 | 1 | 378 (382) |
| 261006_EEG_NWU_RC | 180 / 180 (180) | 2 | 0 | 1 | 340 (337) |
| 261006_EEG_NWU_IS | 180 / 180 (180) | 2 | 0 | 1 | 549 (548) |
| 261007_EEG_NWU_AL | 180 / 180 (180) | 4 | 0 | 1 | 180 (180) |

"Before" = the photodiode-only finals of 2026-09-03 (Aug sessions) or the 2026-10-08/09 PsychoPy-checked finals.
MM and GP first failed the cross-check (153 / 134 of 180 matched): their PsychoPy-to-recording mapping steps once
between two clips (no gap in the recordings), which the piecewise clock fit now handles. The OBE movie sessions
(AS_4, TI_1, CP_1) have no PsychoPy log and were not part of this run. Sheet: the 2026-08-10 IS, 260811 MS and HK
movie rows were promoted to curated by another session earlier on 2026-10-12.

## alternating6Blocks (Task 8)

Same EEG standard set + empirical rspFlip=+1 (no flip) + beatSpec=`1,0,lt,-3.5`
for all eight subjects (identical basis to the movie rows above; the alignment
runs on this task's own recording). Counts below are the round-9 rebuilds
(windowed-amplitude engine, corrected polarity).

| Subject ID | Task | Type | guessed columns = values | basis | status | notes |
|---|---|---|---|---|---|---|
| 260805_EEG_NWU_CA | alternating6Blocks | EEG_breathing | EEG standard + rspFlip=+1 (no flip), beatSpec=1,0,lt,-3.5 (+ per-session noise-blank in buildECGz) | empirical (\|r\|=0.85) | run-on-guess | 7 blocks, 397 breaths, 62 bpm; **blink removal skipped — both blink channels bad (REVIEW)**; ECG noise bursts blanked before z-scoring (ch3⁻ cleanest lead if respec wanted) |
| 260806_EEG_NWU_JH | alternating6Blocks | EEG_breathing | same | empirical (\|r\|=0.92) | run-on-guess | 7 blocks, 749 breaths, 87 bpm |
| 260806_EEG_NWU_MM | alternating6Blocks | EEG_breathing | same | empirical (\|r\|=0.86) | run-on-guess | 7 blocks, 542 breaths, 76 bpm |
| 260807_EEG_NWU_GP | alternating6Blocks | EEG_breathing | same | empirical (\|r\|=0.83) | run-on-guess | 7 blocks, 510 breaths, 72 bpm |
| 260810_EEG_NWU_IS | alternating6Blocks | EEG_breathing | same | empirical (\|r\|=0.91) | run-on-guess | 7 blocks, 541 breaths, 58 bpm |
| 260810_EEG_NWU_AL | alternating6Blocks | EEG_breathing | same | empirical (\|r\|=0.81) | run-on-guess | 7 blocks, 478 breaths, 73 bpm |
| 260811_EEG_NWU_MS | alternating6Blocks | EEG_breathing | same | empirical (**\|r\|=0.47 weak** + drift −390 ppm — REVIEW) | run-on-guess | 7 blocks, 389 breaths, 85 bpm (leak section recovered, floor 0.02) |
| 260811_EEG_NWU_HK | alternating6Blocks | EEG_breathing | same | empirical (\|r\|=0.81) | run-on-guess | 7 blocks, 423 breaths, 65 bpm |

## breathingTasks_separate (Task 9)

All 8 sessions run-on-guess (D4 exception for this task). Bases: OBE sessions
inherit rsp/spike settings from a curated same-session row where one exists,
else Type modal; beatSpec for HM_2/SP_2/RC_1/KA_2 was **measured** by
`batch/task9_probeECGpolarity.m` (bpm per channel×polarity on the round‑4
finals) after the defaults produced implausible rates.

| Subject ID | conditions | Type | guessed columns = values | basis | status | notes |
|---|---|---|---|---|---|---|
| 260625_OBE_NWU_HM_2 | restingBaseline→distractedBreathing→focusedBreathing→sleep | OBEControl | inherited rsp/spike; beatSpec=**3,0,lt,-3.5 (measured 67.9 bpm)** | inherited + measured | run-on-guess | sleep section: only 5 breaths in 18.8 min — REVIEW respiration trace |
| 260702_OBE_NWU_SP_2 | restingBaseline→audioBook→focusedBreathing | OBEControl | inherited; beatSpec=**2,0,gt,3.5 (measured 67.7 bpm)** | inherited + measured | run-on-guess | |
| 260622_OBE_NWU_RC_1 | sleep→restingBaseline→sleepWithOdor→audiobook | OBEControl | inherited; beatSpec=**1,0,lt,-3.5 (measured 51.0 bpm)** | inherited + measured | run-on-guess | |
| 260720_OBE_NWU_KA_2 | restingBaseline | OBEControl | inherited; beatSpec=**1,0,lt,-3.5 (measured 61.1 bpm)** | inherited + measured | run-on-guess | |
| 250929_Dupi_NMH_GH_1 | sleep | OBE_Dupi | inherited from curated GH_1 rows | inherited | run-on-guess | 99 breaths, 62 bpm |
| 251027_Dupi_NMH_DL_1 | sleep | OBE_Dupi | inherited from curated DL_1 rows | inherited | run-on-guess | 323 breaths, 61 bpm |
| 251006_OBE_NWU_RY_1 | focusedBreathing | OBEControl | inherited | inherited | run-on-guess | **no cardiac signal on any ECG lead (≤6.5 bpm both polarities) — HRV NaN, REVIEW** |
| 260105_OBE_NWU_ZF_1 | sleep | OBEControl | inherited | inherited | run-on-guess | 195 breaths, 46 bpm |

## vipassana (2026-09-26)

Three new BrainVision actiCHamp sessions (design spec sections 3e/3f; CLAUDE.md §1, §3). Sheet rows are
staged on `C:\Users\Adam\Documents\DataForClaude\vipassana\sheet\dataTracking_staging_260926.xlsx` (the
master was locked open by another user; rows 620–622 to be merged in when it's free — see that folder's
`masterMerge_260926.tsv` / `README_sheetMerge.md`). All guessed parameters were **measured directly from
the recordings** by `batch/probeMontageBV.m` (respiration polarity/viability, ECG polarity, line noise) —
there is no prior curated `vipassana` row to inherit from.

| Subject ID | Task | Type | sheet row (staging) | guessed columns = values | basis | status | notes |
|---|---|---|---|---|---|---|---|
| 260918_EEG_NWU_AS | vipassana | EEG_vipassana | 620 | rspIDX=1, rspFlip=1, hasEEG=TRUE, spikeClean=FALSE, spikeThresh=20, spikeWin=11, hasMacros=FALSE, beatSpec=`1,0,gt,3.5`, isNewStd=TRUE | probeMontageBV measurements (resp clean, ~18 /min in meditation; ECG R‑peaks positive, ~70 bpm). **rspFlip resolved 2026‑09‑26:** a first visual read called the inhale a downward deflection (rspFlip=−1), and the review run of the main then found `checkRspPolarityRSA` inconsistent (deltaRRms = +18.6 ms over 831 breaths). A direct RR‑vs‑respiration‑phase test (probe/rrPhaseTest.m: RR interval binned by the Hilbert phase of the unflipped 0.05–1 Hz trace over the meditation windows) puts the heart‑rate maximum at the trace PEAK in AS (phase 0.20 rad) and in DD (0.59 rad) alike, so the peak is peak‑inspiration and inhale is the rising phase → rspFlip=1 for both sessions (same belt convention) | run-on-guess (D4) | resp saturates at 0 µV at the top of some breaths (documented, not fixed); check `inhaleLockedRR.jpg` (expect RR falling after inhale onset) before promoting to curated |
| 260918_EEG_NWU_CC | vipassana | EEG_vipassana | 621 | rspIDX=1, rspFlip=1, hasEEG=TRUE, spikeClean=FALSE, spikeThresh=20, spikeWin=11, hasMacros=FALSE, beatSpec=`1,0,lt,-3.5`, isNewStd=TRUE | probeMontageBV measurements (ECG R‑peaks negative, ~67 bpm); rspFlip is a placeholder — respiration fails the viability probe (60‑Hz noise only, autocorr peak 0.21) | run-on-guess (D4) | **no usable respiration — `respSkipped=2`**; FC5 dead, Fp1/Fp2 noisy |
| 260918_EEG_NWU_DD | vipassana | EEG_vipassana | 622 | rspIDX=1, rspFlip=1, hasEEG=TRUE, spikeClean=FALSE, spikeThresh=20, spikeWin=11, hasMacros=FALSE, beatSpec=`1,0,gt,3.5`, isNewStd=TRUE | probeMontageBV measurements (resp clean, inhale = upward deflection; ECG R‑peaks positive, ~65 bpm) | run-on-guess (D4) | many high‑impedance channels with heavy 60 Hz; double marker press at 40.59/40.60 min |

Run outcome, v1 (pre-notch; **superseded by the 2026-09-27 re-run below**, finals kept in
`R:\Neurology\Zelano_Lab\Lab_Common\AllStudyData\Vipassana\_backup_260927_preNotch\`) (2026-09-26 23:41-00:11, home machine, `ZLP_ALLOW_GUESS_RUN=1`, staging sheet via `ZLP_ADMIN_XLSX`; finals on R: under `AllStudyDataVipassana<id>preProc`, verified with `whos -file` + contract checks, `Data Preprocessed = X` staged at K620-K622):

| Subject ID | final | breaths (good) | beats / HR | RSA check | pipeline badChans | blocks (boundary-to-marker) | notes |
|---|---|---|---|---|---|---|---|
| 260918_EEG_NWU_AS | 933 MB, `[39 x 1799060]` | 1105 (1086) | 4183 / 69.8 bpm | −23.2 ms, consistent (n=924) | T7 O1 Oz O2 TP10 Cz (the occipital flags are large eyes‑closed alpha tripping the amplitude rule, not noise - leave the disposition to the analysis) | all 8 within 7 s of its markers; margins 45-194 | blink removal on, Laplacian on |
| 260918_EEG_NWU_CC | 1057 MB, `[39 x 2034830]` | 0 (`respSkipped=2`) | 4436 / 65.4 bpm | n/a | FT9 FC5 TP9 P7 O1 Oz O2 P8 TP10 Cz T8 FT10 | pre 14.7 min, audiobook1 4.0 min (unmarked, low margin 6), anapana from the 18.67 press, vipassana/metta/audiobook2 within 22 s of the other presses | **review `blocks_inferred.jpg`**: the 14.7-min pre and the 4-min audiobook1 are the DP's reading of a busy first 19 min; treat CC audiobook1 with caution |
| 260918_EEG_NWU_DD | 489 MB, `[38 x 1782170]` | 1156 (1119) | 3935 / 66.2 bpm | −17.4 ms, consistent (n=933) | 22 channels (F7 FT9 FC5 C3 T7 TP9 CP5 Pz O1 Oz O2 P8 TP10 CP6 CP2 Cz T8 FT10 FC6 FC2 F4 F8) → only 10 good, so `preprocess_eeg` took its ≤10-channel branch: **no blink removal, `dataLap = []`** | marked boundaries within 5 s; 11.60 press unused; 40.59/40.60 double press merged | high-impedance dry electrodes with heavy 60 Hz; `artifactIndex` used 8 of 31 rows (23 line-dominated rows dropped) |

Re-run, v2 = **current finals** (2026-09-27 16:48-17:14, home machine, same env and staging sheet; `Data Preprocessed = X`
re-staged at K620-K622). Two task changes: the 32 scalp rows are notched at 60/120/180 Hz at ingestion
(`assembleRaw_vipassana`) and `P.blinkRemoval = false` (eyes closed throughout, so `preprocess_eeg` skips blink
removal). The block evidence is still computed on the **un-notched** rows (notched evidence moved DD's
audiobook1/anapana boundaries by 3.6-5.4 min in a test), so blocks, breaths, beats and the RSA check are identical
to v1; only the EEG stage changed. Still-block badTS = fraction of each still block's samples with `badTS == 1`
(`DataForClaude\vipassana\v3work\prepro\verifyExtra_v3.log`).

| Subject ID | final | pipeline badChans (v1 → v2) | blinkRemoval | dataLap | still-block badTS, v1 → v2 (audiobook1 / anapana / vipassana / metta / audiobook2) | breaths (good) | beats / HR | RSA check | run time |
|---|---|---|---|---|---|---|---|---|---|
| 260918_EEG_NWU_AS | 932 MB, `[38 x 1799060]` | T7 O1 Oz O2 TP10 Cz → **O1 Oz O2 Cz** | 1 → 0 | `[32 x 1799060]` | 3.0 % → 2.6 % (5.6 / 2.4 / 0.8 / 2.0 / 5.2 %) | 1105 (1086) | 4183 / 69.8 bpm | −23.2 ms, consistent (n=924) | 8.0 min |
| 260918_EEG_NWU_CC | 1056 MB, `[38 x 2034830]` | FT9 FC5 TP9 P7 O1 Oz O2 P8 TP10 Cz T8 FT10 → **FC5 TP9 P7 O1 Oz O2 TP10 Cz** | 1 → 0 | `[32 x 2034830]` | 19.1 % → 6.3 % (14.0 / 4.3 / 5.5 / 4.9 / 11.2 %) | 0 (`respSkipped=2`) | 4436 / 65.4 bpm | n/a | 8.7 min |
| 260918_EEG_NWU_DD | 920 MB, `[38 x 1782170]` (v1 489 MB: no dataLap) | 22 channels → **Cz only** | 0 → 0 (v1: ≤10-channel branch; v2: task flag) | `[]` → `[32 x 1782170]` | 10.4 % → 0.2 % (audiobook1 87.6 → 0.0; 0.0 / 0.2 / 0.0 / 0.4 / 0.6 %) | 1156 (1119) | 3935 / 66.2 bpm | −17.4 ms, consistent (n=933) | 9.5 min |

`dataLap` is present again for DD but is still subject to the CLAUDE.md §6.3 known issue (off-sphere coordinates).

## respiratorySweep + EmotionalMovieTask (2026-10-08)

First sessions of the new respiration-sweep experiment (CLAUDE.md §1). Atlas data copied from the lab's external
drive (`H:\breathingEEG`) to `R:\…\AllStudyData\EEGbreathing\<id>\AtlasData\`; behavioral files in
`<id>\behavioralData\`; raw files written by `LoadData_<id>_claude.m` (event table in `curDat.TTL`). Master sheet
rows 645–648 (appended 2026-10-08, backup `Admin\Data\dataTracking_backup_261008_1459.xlsx`). Guessed parameters
were **measured**: channel map by `batch/probeMontage.m` (2026 rig: EEG CSC33–64, ECG CSC25–27, rsp CSC31, CSC32 =
inverted copy of CSC31, event CSC269), respiration polarity by the SniffLogic log alignment (log pressure is
inhale-positive; corr sign +1 on every log), ECG polarity from the probe traces (negative R on lead 1).

| Subject ID | Task | Type | sheet row | guessed columns = values | basis | status | notes |
|---|---|---|---|---|---|---|---|
| 261006_EEG_NWU_RC | respiratorySweep | EEG_breathing | 645 | rspIDX=1, rspFlip=1, hasEEG=TRUE, spikeClean=FALSE, spikeThresh=20, spikeWin=11, hasMacros=FALSE, beatSpec=`1,0,lt,-3.5`, isNewStd=TRUE | probeMontage + log alignment (r 0.93 / 0.89, +1) | run-on-guess (D4) | 2 SniffLogic logs (tracing restarted; the aborted first block start is excluded); stopwatch FB 1:22:15, AB 1:29:27, FB 1:37:34, AB 1:44:04 |
| 261006_EEG_NWU_RC | EmotionalMovieTask | EEG_breathing | 646 | same | same | run-on-guess (D4) | 180/180 clips matched to PsychoPy (zthresh −4); ~15 s flat respiration near 19 min |
| 261006_EEG_NWU_IS | respiratorySweep | EEG_breathing | 647 | same | probeMontage + log alignment (r 0.90, +1) | run-on-guess (D4) | stopwatch AB 1:01:00, FB 1:08:20 (eyes closed), AB 1:15:10, FB 1:21:57; CSC37 (FT9) dead — the notes call it "scalp #6, FC5" |
| 261006_EEG_NWU_IS | EmotionalMovieTask | EEG_breathing | 648 | same | same | run-on-guess (D4) | 180/180 clips matched to PsychoPy (zthresh −3) |

Run outcome (2026-10-08 15:46–16:24, lab desktop, `ZLP_ALLOW_GUESS_RUN=1`, branch `respiratorySweep-261008`; finals
verified by `qcNew.m`: fs 500, `moreThan1`, `manOnset`, `bmObj`/`bmFeatures`, rsp findable; `Data Preprocessed = X`).
QC page: https://claude.ai/artifact/JaAv8wnnYN6FB8x976FcjN (figures also in `R:\…\Adam\Dupi_processing\<id>\<task>\`).

| Subject ID | Task | final | breaths (good) | in blocks / clips | beats / HR | badChans | badTS | notes |
|---|---|---|---|---|---|---|---|---|
| 261006_EEG_NWU_RC | respiratorySweep | 1.85 GB, `[43 x 3343616]` | 1277 (1102) | 869 in 23 blocks | 6102 / 54.7 bpm | F7 FC5 T7 FC6 F8 | 13.8 % | slow paces over-segmented (b05 target 6 → median 10.9 /min, b06 4 → 6.2); FB post2 median 29.7 /min (notes: nodding off, head moving) |
| 261006_EEG_NWU_IS | respiratorySweep | 1.49 GB, `[43 x 2687104]` | 1148 (1053) | 892 in 23 blocks | 5035 / 56.2 bpm | FT9 T7 TP9 TP10 | 6.8 % | b06 (target 4) median 9.0 /min; later 4 /min blocks followed (4.1) |
| 261006_EEG_NWU_RC | EmotionalMovieTask | 0.55 GB, `[42 x 1002528]` | 337 (317) | 179 bounded clips | 1650 / 49.4 bpm | F7 FT9 FC5 F8 | 15.8 % | |
| 261006_EEG_NWU_IS | EmotionalMovieTask | 0.54 GB, `[42 x 971758]` | 548 (539) | 179 bounded clips | 1823 / 56.3 bpm | FT9 T7 TP9 | 2.1 % | |

RC and IS (rows 645–648) promoted to `paramSource = curated` on 2026-10-09 after QC review; the finals were not re-run.

### 261007_EEG_NWU_AL (2026-10-09)

Session notes filed 2026-10-09 (`IRB\STU00201748_Respiratory Oscillations (EEG)\2026 Participant Documentation\`);
stopwatch block times read independently three times, all agreeing. Loader `LoadData_261007_EEG_NWU_AL_claude.m`,
same rig channel map as RC/IS (probeMontage). Sheet rows 649–650 (parameters written 2026-10-09).

| Subject ID | Task | Type | sheet row | guessed columns = values | basis | status | notes |
|---|---|---|---|---|---|---|---|
| 261007_EEG_NWU_AL | respiratorySweep | EEG_breathing | 649 | same as RC/IS | probeMontage + log alignment (r 0.88, +1) | run-on-guess (D4) | 1 SniffLogic log; stopwatch FB 1:05:10, AB 1:13:19, FB 1:20:30, AB 1:27:10; note checkpoints (AB 2:02, sweeps 10:20 / 28:40 / 44:50) land 2–20 s from the log events; RSITT not done (notes) |
| 261007_EEG_NWU_AL | EmotionalMovieTask | EEG_breathing | 650 | same | same | run-on-guess (D4) | recording `_0001`; 180/180 clips matched to PsychoPy (zthresh −3.5, 4 detections dropped, residual median 4 ms) |

Run outcome (2026-10-09 14:20–14:35, lab desktop, same settings; finals verified by `qcAL.m`; `Data Preprocessed = X`).
QC page: https://claude.ai/artifact/5eqnCBnzNLkM5nhEPNPRHJ.

| Subject ID | Task | final | breaths (good) | in blocks / clips | beats / HR | badChans | badTS | notes |
|---|---|---|---|---|---|---|---|---|
| 261007_EEG_NWU_AL | respiratorySweep | 1.58 GB, `[43 x 2869504]` | 974 (771) | 786 in 23 blocks | 6679 / 69.8 bpm | Oz O2 | 18.4 % | slow paces over-segmented (b12 / b18, target 4 → medians 7.5 / 7.4 /min); sparse nasal airflow from the post-sweep blocks on (SniffLogic sees it too; notes: 5 h sleep, tired 6/10) |
| 261007_EEG_NWU_AL | EmotionalMovieTask | 0.53 GB, `[42 x 972476]` | 180 in-clip rows (88 good) | 179 bounded clips | 2155 / 66.5 bpm | F3 F7 FT9 FC5 T7 TP9 P7 O1 Oz O2 P8 TP10 T8 FT10 FC6 F4 F8 Fp1 | 33.5 % | respiration sparse throughout; EEG much worse than the sweep recording |

Rows 651–658: four older sessions found only on the external drive (`260828_EEG_NWU_CC`, `260901_EEG_NWU_ES`,
`260902_EEG_NWU_YW`, `260908_EEG_NWU_MC`), copied to R:, nothing extracted. Their session notes (read 2026-10-09)
show the first recording was the **alternating6Blocks** task, the second the emotional videos (CC's movie is in
`_0002`).
Sheet Task set to `alternating6Blocks` (rows 651/653/655/657). Not extractable yet: their `mindfulBreathing` /
`sniffLogicLog` files are not on R:, the external drive or Google Drive (`breathingDataFiles` logs stop on 2026-08-11).
Their movie recordings (rows 652/654/656/658) need no behavioral file beyond the PsychoPy CSV already in `behavioralData`.

## Dupi/OBE breathingTask guess sessions — Part-2 probe pass (2026-08-27)

Instruction: run these with critically-evaluated parameters (measured ECG
beatSpec, railing-based macroRemove, spike-rate-based spikeClean, hasEEG=true).
Probe: `batch/task12_probeParams.m` (needs the makeOutDat intermediate).

| Subject ID | probe result | run outcome |
|---|---|---|
| 250623_Dupi_NMH_KS_3 | beatSpec=`1,0,gt,3.5` (61 bpm, 12.1× side margin); 6 macros, none railing; spikeClean=false; hasEEG=true — written to sheet | main still fails with its documented "Index must not exceed 2" mid-pipeline error (bare intermediate remains) |
| JL_2, TB_3, GH_3, AB_3, JN_3, BS_1, AD_1, AD_2, PD_1, JA_1, JA_2, BW_1 | not probed — makeOutDat fails first | **blocked: `experiment_EEGsync\processedBehavior\<id>.csv` missing** (generate with `tidyDataImport_waveExp.R`, rerun makeOutDat → probe → main) |
| 251110_Dupi_NMH_PC_2 | not probed | blocked: makeOutDat "load file not identified uniquely" — inspect the session folder's LoadData scripts |
| 260316_Dupi_NMH_PD_2 | not probed | blocked: no breathing raw on disk (sheet says extracted) |

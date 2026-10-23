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
`R:\Neurology\Zelano_Lab\Lab_Common\AllStudyData\Vipassana\_backup_260927_preNotch\`; moved 2026-10-21 to the lab desktop, `E:\reprocBackup_260927_preNotch\vipassana\`) (2026-09-26 23:41-00:11, home machine, `ZLP_ALLOW_GUESS_RUN=1`, staging sheet via `ZLP_ADMIN_XLSX`; finals on R: under `AllStudyDataVipassana<id>preProc`, verified with `whos -file` + contract checks, `Data Preprocessed = X` staged at K620-K622):

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

`dataLap` is present again for DD; like every final made before 2026-10-22 it is the old common-mode `dataLap` (CLAUDE.md §6.3: fixed in the code since 2026-10-22, a rerun replaces it).

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
| 261006_EEG_NWU_IS | respiratorySweep | EEG_breathing | 647 | same | probeMontage + log alignment (r 0.90, +1) | run-on-guess (D4) | stopwatch AB 1:01:00, FB 1:08:20, AB 1:15:10, FB 1:21:57; CSC37 (FT9) dead (the note sheet labels this electrode FC5) |
| 261006_EEG_NWU_IS | EmotionalMovieTask | EEG_breathing | 648 | same | same | run-on-guess (D4) | 180/180 clips matched to PsychoPy (zthresh −3) |

Run outcome (2026-10-08 15:46–16:24, lab desktop, `ZLP_ALLOW_GUESS_RUN=1`, branch `respiratorySweep-261008`; finals
verified by `qcNew.m`: fs 500, `moreThan1`, `manOnset`, `bmObj`/`bmFeatures`, rsp findable; `Data Preprocessed = X`).
QC page: https://claude.ai/artifact/JaAv8wnnYN6FB8x976FcjN (figures also in `R:\…\Adam\Dupi_processing\<id>\<task>\`).

| Subject ID | Task | final | breaths (good) | in blocks / clips | beats / HR | badChans | badTS | notes |
|---|---|---|---|---|---|---|---|---|
| 261006_EEG_NWU_RC | respiratorySweep | 1.85 GB, `[43 x 3343616]` | 1277 (1102) | 869 in 23 blocks | 6102 / 54.7 bpm | F7 FC5 T7 FC6 F8 | 13.8 % | slow paces over-segmented (b05 target 6 → median 10.9 /min, b06 4 → 6.2); FB post2 median 29.7 /min |
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
| 261007_EEG_NWU_AL | respiratorySweep | 1.58 GB, `[43 x 2869504]` | 974 (771) | 786 in 23 blocks | 6679 / 69.8 bpm | Oz O2 | 18.4 % | slow paces over-segmented (b12 / b18, target 4 → medians 7.5 / 7.4 /min); sparse nasal airflow from the post-sweep blocks on (SniffLogic sees it too) |
| 261007_EEG_NWU_AL | EmotionalMovieTask | 0.53 GB, `[42 x 972476]` | 180 in-clip rows (88 good) | 179 bounded clips | 2155 / 66.5 bpm | F3 F7 FT9 FC5 T7 TP9 P7 O1 Oz O2 P8 TP10 T8 FT10 FC6 F4 F8 Fp1 | 33.5 % | respiration sparse throughout; EEG much worse than the sweep recording |

Rows 651–658: four older sessions found only on the external drive (`260828_EEG_NWU_CC`, `260901_EEG_NWU_ES`,
`260902_EEG_NWU_YW`, `260908_EEG_NWU_MC`), copied to R:, nothing extracted. Their session notes (read 2026-10-09)
show the first recording was the **alternating6Blocks** task, the second the emotional videos (CC's movie is in
`_0002`).
Sheet Task set to `alternating6Blocks` (rows 651/653/655/657). Not extractable yet: their `mindfulBreathing` /
`sniffLogicLog` files are not on R:, the external drive or Google Drive (`breathingDataFiles` logs stop on 2026-08-11).
Their movie recordings (rows 652/654/656/658) need no behavioral file beyond the PsychoPy CSV already in `behavioralData`.

### 261014_EEG_NWU_ZL (2026-10-15)

A new participant (not 250819_EEG_NWU_ZL). Folder organised on R: (the Atlas folder was loose in `<id>\` → `AtlasData\`;
27 of ZL's behavioral files moved from the EEGbreathing root → `behavioralData\`). Loader `LoadData_261014_EEG_NWU_ZL_claude.m`,
same rig channel map as RC/IS/AL (probeMontage). No session notes were used: the four end-block start times were given by
the user (AB 1:02:08, FB 1:09:20, AB 1:16:05, FB 1:22:40; exactly 6 min each). The SniffLogic log ran ~5 min past the
Atlas stop; `buildSweepTTL` now checks the log's events (all inside) instead of its full span. Sheet rows 659–660 appended.

| Subject ID | Task | Type | sheet row | guessed columns = values | basis | status | notes |
|---|---|---|---|---|---|---|---|
| 261014_EEG_NWU_ZL | respiratorySweep | EEG_breathing | 659 | same as RC/IS/AL | probeMontage + log alignment (overlap r 0.82, +1, lag 48.4 s, drift 47 ppm) | run-on-guess (D4) | first recording (no suffix), 88.8 min; 1 SniffLogic log |
| 261014_EEG_NWU_ZL | EmotionalMovieTask | EEG_breathing | 660 | same | same | run-on-guess (D4) | recording `_0001`; 180/180 clips matched to PsychoPy (zthresh −3, 4 detections dropped, 1 clock segment, residual median 5 ms) |

Run outcome (2026-10-15, lab desktop, `ZLP_ALLOW_GUESS_RUN=1`, branch `respiratorySweep-261008`; the sweep final as re-run
under the breath-merge rule at 5d40ada; ZL has no lead bumps, so the final rule (40a645e) gives the same result; verified by
`verify1015b.m` / `verify1015.m`; `Data Preprocessed = X`). QC page: https://claude.ai/artifact/V1vir9QyKFR8uyvxKLm8RV.

| Subject ID | Task | final | breaths (good) | in blocks / clips | beats / HR | badChans | badTS | notes |
|---|---|---|---|---|---|---|---|---|
| 261014_EEG_NWU_ZL | respiratorySweep | 1.37 GB, `[43 x 2664576]` | 806 (741); engine 825, 1 blip + 18 inhales merged | 667 in 23 blocks | 5325 / 60.0 bpm | TP9 O1 TP10 CP6 T8 FT10 FC6 F8 | 10.7 % | every sweep block's median rate within 0.2 /min of its target |
| 261014_EEG_NWU_ZL | EmotionalMovieTask | 0.50 GB, 32.4 min | 414 in-clip (402) | 173 of 180 clips | 1800 / 55.5 bpm | TP9 T8 FT10 FC6 F8 | 5.3 % | |

### Breath-merge rule + AL changes (2026-10-15)

- **AL movie (row 650) set back to `guess` on purpose** (user: respiration not carried by the nasal cannula through most of the movie; ttlNote "do not
  use downstream"). Never promote it; the final is unchanged.
- **Breath-merge rule (user):** an inhale is not a new breath unless there has been an exhale with ≥ 20 % of the inhale's
  volume since the last one — `shared/mergeIncompleteExhales` after the locked engine, every respiratorySweep session from
  now on (CLAUDE.md §1: pause blips, lead bumps, per-inhale 20 % test, zero flow = max(dwell level, 60-s mean)). Validated
  on synthetic regressions and on the share of SniffLogic target cycles holding exactly one onset: AL 83.5 → 87.5 %,
  ZL 96.9 → 97.9 %, RC 83.2 → 85.6 %, IS 91.7 → 93.9 % (engine → rule). Known limit: an engine onset placed partway up
  an inhale leaves that inhale's start in the previous window (AL 1557.4 s: the breath starts at 1551.2 s).
- **AL sweep re-run** with the rule (40a645e): engine 974 → 932 breaths (742 good; 13 blips incl. 4 lead bumps, 29 inhales merged; 751 in blocks; 29 breaths hold 2 inhales, none > 20 s; b18 median 7.4 → 4.6 /min). EEG (Oz O2, badTS 17.6 % — the 'fixed' detector since the
  vipassana merge) and ECG (6679 beats) unchanged. Backups (lab) `E:\reprocBackup_261015_sweep\261007_EEG_NWU_AL\`:
  pre-rule original (974 breaths), `v1rule\` (first rule version, 938), `interim5d40ada\` and `interim494548c\` (932 each, onsets differ).
- **RC / IS not re-run** (curated 2026-10-09, before the rule existed): the rule would take RC 1277 → 1237 and IS
  1148 → 1131 breaths (target-cycle score RC 83.2 → 85.6 %). Offered to the user.

## ADmeditation (2026-10-08) — promoted to curated 2026-10-09

Adam's 14 repeated meditation recordings (`AllStudyData\AD_repeatRecordings`; own sheet
`Admin\Data\dataTracking_AD_meditation.xlsx`, CLAUDE.md §1/§3). One parameter set for every session, measured on all
14 recordings: `rspIDX 1, rspFlip +1` (CSC31 inhale up, the rig's polarity — a −1 guess from an RR-window test was
wrong, see CLAUDE.md §1), `beatSpec 3,0,lt,-3.5` (ECG3 negative R in every session; ECG1 flips between sessions),
`hasEEG` true, no macros / spike cleaning, `P.blinkRemoval = false` (eyes closed, blink rate ~0/min). Run on guess
(D4) 2026-10-08, QC page `AD_repeatRecordings\preProc\ADmeditation_QC_261008.html` reviewed by the user, all 14 rows
promoted to `curated` 2026-10-09 (finals unchanged by the promotion). Outcome: 694–935 breaths / session (97–99 %
good), HR 53–68 bpm, 58 button presses in the analysis windows + 4 in trimmed stretches (3 in the first 3 min; 260709
press 7 at 62.63 min, 23 s before the end), every paired press 5.00 ± 0.02 s; 260825 has no presses; 260831's
respiration amplitude is ~10x smaller than the others (detection unaffected). Empty stub recordings 260615_ADmed_0920
and 260707_ADmed_1017 are listed in the sheet, not extracted.

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

## OBE update 2026-10-08 (DW_1, EZ_1 new; BW_2 rebuilt)

Run on the lab desktop against the master sheet, `ZLP_ALLOW_GUESS_RUN=1` + `ZLP_ALLOW_GUESS_RUN_ALL=1`, scoped with
`ZLP_MAKEOUTDAT_ONLY` / `ZLP_MAIN_ONLY`; paramSource stays `guess`. Parameters measured with `batch/guessParamsFromRaw.m`
(cue/threshold on binaps1 as for the rest of the cohort: the sniff thresholds are in binaps units). Finals verified
(`whos`, fs 500, moreThan1, manOnset, forehead labels).

| Subject ID | task | guessed columns = values | outcome |
|---|---|---|---|
| 260820_OBE_NWU_DW_1 | odor cue task | rspIDX=1, rspFlip=1, hasEEG=TRUE, spikeClean=FALSE, respThresh/cuedBackBuff/adjWin=4000/500/500, isNewStd=TRUE | 60 trials; 7 bad EEG channels (spiky EEG) |
| 260820_OBE_NWU_DW_1 | threshold | rspIDX=1, rspFlip=1, hasEEG=TRUE, spikeClean=FALSE, 5000/350/500, isNewStd=TRUE | 45 trials |
| 260820_OBE_NWU_DW_1 | focusedBreathing_button + restingBaseline (sep) | rspIDX=1, rspFlip=1 (binaps1; the riseFall vote said -1 on these slow-breathing recordings but +1 on threshold, and the cannula's polarity cannot change), beatSpec=`2,0,gt,3.5`, hasMacros=TRUE, spikeClean=FALSE | 90 breaths, 1274 beats / 82 bpm; polarity confirmed by the inhale-locked RR check (RR falls 36 / 29 ms after inhale onset in the two sections; EZ_1 -11/-16/-20 ms, BW_2 -31..-48 ms) |
| 260824_OBE_NWU_EZ_1 | odor cue task | as DW_1 cue | 60 trials; **SURROGATE markers** (`outDat.surrogateTTL`): the DAQ input was dead, markers rebuilt from the result files, trial 1 cue marker at 32.30 s +-0.05 s (EEG-aligned within the cued-sniff window; method `reports\obeUpdate_261008\cueSurrogate\`) |
| 260824_OBE_NWU_EZ_1 | threshold | as DW_1 threshold | 45 trials |
| 260824_OBE_NWU_EZ_1 | focusedBreathing_button + restingBaseline + focusedBreathing_button_mouth (sep) | rspIDX=1, rspFlip=1 (binaps1: the only channel with respiration in all three; the mask was off in the nose-clip run), beatSpec=`2,0,gt,2.5` | 235 breaths, 1906 beats / 72 bpm; the nose-clip section rests on the cannula alone |
| 260921_OBE_NWU_BW_2 | cue, threshold, sep | unchanged (rebuilt from the 49-channel re-extraction with the forehead electrodes) | 54 sniffs / 45 trials / 346 breaths, 66 bpm, as before; superseded finals in `preProc\superseded_261008\` and `E:\reprocBackup_261008\` |

## Guess review 261008 — reviewer response executed 2026-10-12

Reviewer verdicts: `reportResponse.md` (2026-10-12). Sheet edits via a row-keyed, Subject-ID+Task-checked writer under a lab
`sheet.lock` (backups `Admin\Data\sheetBackups\dataTracking_backup_261012_*.xlsx`); superseded finals in each session's
`preProc\superseded_261012\` and `E:\reprocBackup_261012\<task>\<id>\`; new review figures under
`R:\…\Adam\Dupi_processing\guessReview_261012\` (blinkAudit, BW_2, HW, PC_2_ecgWindows, sepResegment, spikeAudit, hrSpotCheck).

**Promoted to curated:** breathing TB_3 GH_3 JL_2 PD_1 PD_2 BS_1 JA_1 JA_2 AD_2 (no change needed: TTL 0/300 s are the
measured raw windows 30–330 / 690–990 s in concatenated time); movie 260810_IS HK MS, CP_1 (beats pruned with a 0.7-s
refractory, `P.minIBI`, 2301→2026 beats); alt6 JH HK; sep AZ FM HRM BG AS(241017) RY_1 SP_2 KA_2 DW_1 RA_1 EZ_1 RC_2;
paced KG JW; cue CC_1 DW_1 CS_2; thresh PD_2 DW_1 BW_2 SP_2 (blink skipped because only 10 good EEG channels remain);
O15 RX_1 SP_2 (26 bad channels).

**Recorded reviewer notes (accepted, not fixable):** 251006_OBE_NWU_RY_1 — ECG unusable (badly recorded); the empty
`heartBeats` is expected. 240923_OBE_NMH_HRM — macro data extremely noisy (high-amplitude, random): treat this dataset as
noisy/different. **(Superseded 2026-10-14: those were the wrong channels — CSC195–200 are unconnected inputs; with the
corrected map the HRM macros are clean, see "Task list 261014".)** 260824_OBE_NWU_EZ_1 sep — rhythmic artifact in the macros that standard methods cannot remove.
ZF_1 / ZF_2 sep heart-rate estimates (≈41 / 44 bpm) verified (no missed beats). Spike-clean "% altered" (up to 52 %, JA_2) =
fraction of samples inside 0.2-s notch windows; the actual change is ~1 µV RMS — intended.

**Rerun, still guess:**

| Session | task | change | outcome |
|---|---|---|---|
| 251002_Dupi_NMH_AB_3 | breathing | macroRemove none | 5 macBP; all else identical |
| 260514_OBE_NWU_BW_1 | breathing | rspIDX 1 | 204→211 breaths |
| 251110_Dupi_NMH_PC_2 | breathing | macroRemove 6→2 (macro2 13 % railing) | ECG noise is one ~90-s movement burst (210–300 s), beatSpec kept |
| 260227_EEG_NWU_HW | breathing | cyclicSigh refractory (0.65 × cycle period, task level) | cond 4 31→25 breaths; target-trace misalignment = linear stretch + unknown start offset (not fixed) |
| 251013_Dupi_NMH_JN_3 | breathing | new blink IC rule | removes Fp2 IC r 0.94 |
| 251030_Dupi_NMH_DB_3 | breathing / cue / thresh / O15 | first processing (measured windows 142.7/621.0/1323.8 s; O15 zthresh −1 + confirmAfterPress) | 175 breaths; 38/40 cue; 44/45 thresh; 15 O15 trials |
| 250904_OBE_NWU_TI_1 | movie | rspIDX 1 | 731→416 in-clip breaths (old median length implausible) |
| 250225_OBE_NWU_AS_4 | movie | rebuilt from the old-format file through the current pipeline | no ECG recorded (CSC25–27 unconnected); 461 in-clip breaths |
| 260805_EEG_NWU_CA | alt6 | flat-test ignores all-channel gaps | blink removal now runs (Fp1 IC r 0.92) |
| 241010_OBE_NMH_SJ | sep | macroRemove 3,5 | 3 macBP |
| 251218_OBE_NWU_SM_1 | sep | beatSpec `1,0,lt,-1.25`, rspIDX 1 | 183 beats / 66 bpm (was none) |
| 260824_OBE_NWU_ZF_2 | sep | macroRemove 5 (clips in sleep) | 4 macBP |
| 260827_OBE_NWU_RX_2 | sep | rspIDX 1, resegment only | 311→298 breaths |
| 260817_OBE_NWU_CC_1 | sep | rspIDX 1, resegment only | 64→63 breaths |
| 260105_OBE_NWU_ZF_1 | sep | new blink IC rule | nothing removed (no blink IC) |
| 260625_OBE_NWU_HM_2 | sep | new blink IC rule | sleep: nothing removed; end noise from 1893 s (not truncated) |
| 260831_OBE_NWU_CS_2 | sep | beatSpec `3,0,lt,-2.75` + new blink rule | 1820→2083 beats; sleep section still no beats |
| 260921_OBE_NWU_BW_2 | sep | per-condition rspIDX (1,1,1,3; `rspSelected` row) | section 3 binaps1 is noise (86→237 breaths) — reviewer decision |
| cue BG RA_1 EZ_1 ZF_2 RX_2 RC_2 BW_2 | cue | respThresh / cuedBackBuff per verdict; ZF_2 macroRemove 4,5 | BG 34→38 trials, RA_1 trial 50 fixed, BW_2 54→60, RX_2 loses trial 7, RC_2/EZ_1 unchanged onsets |
| thresh RX_1 EZ_1 JA_2 | thresh | cuedBackBuff 150; EZ_1 macroRemove 2 etc.; JA_2 hasEEG TRUE | RX_1 tail: EEG/macro overload from ~851 s, zeros from 897 s (after last trial) |

| 260820_OBE_NWU_DW_1 | sep (curated) | rerun with the new blink IC rule (user request) | section 1 now removes an Fp2 IC (r 0.86; the old rule's pick scored 0.60); section 2 unchanged; 90 breaths, 1273 beats unchanged |

D1a-f promoted to curated 2026-10-13 (user): cue BG, RA_1, EZ_1, BW_2; thresh EZ_1; sep CC_1.

Still blocked (user decision 2026-10-12): 260504_Dupi_NMH_JA_2 O15 stays without a final until the user supplies the answers (`O15_responses_260504_Dupi_NMH_JA_2.csv`; they exist only in the session video). Open decisions: `guessReview_261012.html`.

## Task list 261014 (user, `tasks_261014.md`) — executed 2026-10-14/15

Run as three orchestrated workflows (Fable audits on every change); backups `E:\reprocBackup_261014\<task>\<id>\`, superseded
finals in `preProc\superseded_261014\`, review figures `R:\…\Adam\Dupi_processing\guessReview_261014\<topic>\`.

**Promoted to curated:** cue ZF_2 (row 584: macroRemove 4,5 + cuedBackBuff 150 — trials 25/43/54/60 moved onto the main sniff,
all 60 epochs judged aligned), cue RX_2 (598, trial 7 lost — accepted), cue RC_2 (624, trial 23 dropped via `P.dropTrials` →
`outDat.droppedTrials`), breathing PC_2 (346: macroRemove 1,2, spikeClean off, HRV excluded where the ECG is unreadable —
`P.ecgExcludeSec` = [25.2 30.2; 209.3 300.8; 335.0 336.3; 459.5 473.9] s from `batch/ecgUnreadableWindows.m`, 29 breaths with NaN
HRV), sep HM_2 (456/458/460/462: sleep cut at 916 s via `P.condTrimSec`, noise starts 921.1 s; 319 breaths / 2129 beats),
sep CS_2 (608/609/612/614: sleep ECG noise windows blanked in buildECGz (NOISYECG list) → 1961 sleep beats / 90 bpm with the
same beatSpec, `P.condMinIBI` 0.5 s for sleep, no blink removal in sleep via `P.condBlinkRemoval`). D1a-f re-verified: correct.

**Reprocessed, still as before on the sheet:**

| Session | task | change | outcome |
|---|---|---|---|
| 240923_OBE_NMH_HRM | cue (62) + sep sleep (64), curated | channel map fixed: macros CSC3–8, micros CSC33–42, scalp CSC9–12 (labels O2 Cz C4 F4 = user's guess), event CSC269, rsp CSC270 (rspFlip +1 confirmed from sniff timing); proven against `Preproc_CueTask\preproc_cueTask_odor_HRM.mat` (2-kHz rows identical, macros r ≥ 0.9994; old CSC195–200 map |r| ≤ 0.03); new `LoadData_240923_OBE_NMH_HRM_claude.m`; all 12 raws re-extracted (old in `raw\superseded_261014\`) | respiration / sniffs / breaths unchanged; macBP now real (4–13 µV rms vs 98–143); cue spikeClean ICA now removes components. Siblings AZ/FM/SJ/AS/BG maps OK (SJ's own lab reference files use wrong macro channels) |
| 260921_OBE_NWU_BW_2 | sep (guess) | section 3 (focusedBreathing_button2, recorded during echem) split out: row 639 dataType → ephys_echem, rspIDX 3; main file = button1 / restingBaseline / mouth with rspIDX 1/1/3; echem file via `ZLP_SEP_ECHEM=1` | main 259 breaths (102/61/96); `260921_OBE_NWU_BW_2_breathingTasks_echem_separatepreproc.mat` 86 spirometer breaths (recovered: ECG-derived-respiration coherence 0.98, RSA 0.65; binaps dead), echem macro spikes left in |
| 251030_Dupi_NMH_DB_3 | O15 (guess) | held-button protocol (`P.ttl.protocol = 'heldButton'`, `parse_O15_events`, `heldButtonFreeSniffs_O15`, `outDat.buttonDown`); the 10-12 parse was one event out of phase | 15 trials, start 15 / free 105 / confirm 15 (was 0 free); EEG with the fixed detector: 24 bad (was 30) |

**EEG cleaning fix (deployed 2026-10-15, default `P.eegClean` mode 'fixed', 'legacy' reproduces the old detector):**
`removeNoiseChansVolt` trial purges were written into every channel's record, so ≥ 60 % purged trials flagged all channels
(the 13 all-30 finals); purged trials read as flat; R5 divided by all trials; recording gaps counted per channel. Fixed in
removeNoiseChansVolt / preprocess_eeg / blinkRemoveWrapper (+ concatSections). Existing finals are NOT reprocessed: 24 change
certainly, ~45–65 of 219 estimated. Open policy: 'band' mode (1–40 Hz statistic) would leave most sessions with 0–3 bad channels.
Survey + deep dives: `guessReview_261014\eegAudit\`.

**Protocol change found:** O15 moved to the held-button protocol between 2026-07-02 and 2026-07-09 (DB_3 2026-07-09, RC_2
2026-09-17; RC_2's O15 row 622 has no behaviour file and no parameters — not run).

**Next review:** `R:\…\Adam\Dupi_processing\guessReview_261015\guessReview_261015.html` (2026-10-15): every open decision
(G1–G10 pipeline-wide, S1–S20 processed sessions, U1–U7 unprocessed rows) and all 36 guess rows of the sheet.

## New participant 261008_INR_NWU_SS_1 (recorded 2026-10-15, processed 2026-10-15/16)

Loader `LoadData_261008_INR_NWU_SS_1_claude.m` (session folder), 17 raw files; sheet rows 661-678 (Type OBEControl, no INR
Type). Segment map from the Pegasus log + DAQ patterns (evidence `guessReview_261015\SS_1\segmentMap\`): _0013 = unlisted
oddball_echem2, _0014 = restingBaseline_echem (FSCV comb), _0015+_0016 = one threshold_echem recording (Atlas 4-h rotation),
_0001 = unusable detectNoOdor attempt (row 662, not extracted). All runs on guess, each audited by Fable:

| row | task | outcome |
|---|---|---|
| 667/668/670/678 | breathingTasks_separate (resting, sleep, focused button, nose clip; spirometer for the nose clip) | 466 breaths, 2472 beats; macroRemove 4,5,6 (macros 4-6 rail with nasal airflow) |
| 669 | odor cue task (Cue Task 1) | 40/40 trials, hit 20 / cr 19 / fa 1 |
| 664 | threshold (new design: lines 1/2/3/12 = air/low/med/high, 2 runs x 40) | 80/80 trials; pipeline extended (`threshDesign`, `run` column), old sessions bit-identical |
| 663 | detectNoOdor (NEW pipeline) | 40/40 trials, 24 Yes / 16 No, nInhales (3 double sniffs at promFrac 0.25) |
| 666 | cueTask3 (NEW pipeline, opt-in shared `P.sniffTrain`) | 40 x 3 sniffs; trial 2 flagged noOdorDelivered |
| 677 | airPuff (NEW pipeline) | 28 puffs in 7 holds (5 cued, 2 blind); 1 lead pulse recorded (not 3) |

Open decisions: `guessReview_261015.html` Part 2b (N1-N7).

## New participant 261012_INR_NWU_VC_1 (recorded 2026-10-19, processed 2026-10-20)

Loader `LoadData_261012_INR_NWU_VC_1_claude.m` (session folder), 5 raw files; sheet rows 679-683 (Type OBEControl, as SS_1).
Atlas export directly under `AtlasData\2026-10-19_13-02-59\`; the five segments = the Pegasus log's five recordings ('' threshold,
_0001 sleep, _0002 eating, _0003 / _0004 discrimination runs 1 / 2; _0005 header-only, not extracted). No forehead cups (CSC21-24
unconnected); CSC29 connected but unmapped (tracks Fp1/Fp2). Evidence `guessReview_261015\VC_1\` (extraction, threshold, sleep).
All runs on guess, each audited by Fable (pass with minor):

| row | task | outcome |
|---|---|---|
| 679 | threshold (SS_1's 2 x 40 design + a new Yes/No detection screen, `threshold_task_det.m`; `<id>_det` result files, 10 columns) | loader extended (`detect` / `detectRT`, empty rating NaN; other sessions identical); behDat 71 x 16 (9 run-2 trials without a crossing); sniff-onset check: 56 plausible / 3 questionable / 12 on the next breath (9 of them high PEA) / 9 missed; EEG 20/32 bad, badTS 45 % (muscle artifact) |
| 680 | breathingTasks_separate (sleep only; beatSpec `2,0,gt,3.5`, ECG1 unusable in sleep) | first final under G2b (no blink ICA; single section, so no `blinkIndicator` row); 321 breaths (311 good), 1444 beats / 68.6 bpm; badChans FC5 TP9 TP10, badTS 11.3 %; cardiac pulse artefact on macBP4/5 |
| 681 | eating | extract only (no DAQ pulses; spirometer flat for ~10 min, mask off) |
| 682 / 683 | discrimination_run1 / _run2 | extract only (no pipeline); 30 / 16 trials (run 2 stopped in trial 17); ttlNotes corrected 2026-10-21 (3-pulse start code, 8 pulses per trial, 3-pulse end code) |

Open decisions: `guessReview_261015.html` Part 2c (V1-V4), and G2d (sleep-only sep finals have no `blinkIndicator` row).


## vipassana protocol v2 — seven new sessions (2026-10-20)

User request 2026-10-20: organize the new files in `R:\...\AllStudyData\Vipassana\` into participant folders
(`brainProductsDat\`, `behavioralDat\`, `raw\`, `preProc\`), write LoadData scripts, and preprocess with the
SniffLogic logs / photodiode identifying the blocks (protocol audiobook 5 · paced 8 · audiobook 5 · anapana 15 ·
vipassana 15 · metta 8 · paced 8; paced2 not run for three participants). No blink removal (eyes closed), no notch
unless necessary, respiration filtered (60-Hz pickup), ECG + breath segmentation + EEG cleaning, block identity in
behDat. CLAUDE.md §1 (vipassana row, "Protocol v2") documents the design.

Files: the 7 recordings were loose in the study root; every `<id>.{eeg,vhdr,vmrk}` → `<id>\brainProductsDat\`, every
other `<id>_*` file → `<id>\behavioralDat\` (BM/RM/NE: SniffLogic log, PsychoPy mindfulBreathing csv/log/psydat,
audioResp_recording, sweep1_cycles/framelog, template_breath — 8 files each). **JO/KW/L/VL came with no behavioral
files** (not on Google Drive either; latest there is 2026-09-17): their blocks come from the photodiode alone, labels
from the protocol order, and they have no paced target. Loaders `<id>\LoadData_<id>_claude.m` (standalone,
readBrainVision pasted; v2 montage photoDiode/Resp/ECG = Ch32/33/34; VL's 19.4-s setup segment before a restart
dropped). Channel maps confirmed with `batch/probeMontageBV` (outputs in each session's figure folder,
`vipassana\probeMontageBV\`).

Parameters (all guess, measured 2026-10-20): rspIDX 1, **rspFlip −1** for all seven (BV Resp is an inverted copy of
the inhale-positive SniffLogic pressure: window r −0.99…−0.999 in BM/RM/NE; the unlogged four share the logged
sessions' waveform asymmetry, and probeMontageBV calls their inhale downward too), hasEEG TRUE, spikeClean FALSE,
hasMacros FALSE, beatSpec `1,0,gt,3.5` (BM, RM, VL) / `1,0,lt,-3.5` (NE, JO, KW, L) — the shared 5–40 Hz ECG stage
finds regular beats without any line-noise filter (probe: ≥ 96 % regular IBIs in every session).

Decisions taken with evidence (probes in the session scratchpad `probe\`):
- **No notch.** The v2 EEG has a flat broadband noise floor (~1–5 µV²/Hz to the 140-Hz amplifier cutoff, AS
  ~0.1–0.5), so the shared detector flags every channel notched or not (`'fixed'` mode, probe3: 30/30 channels,
  badTS 44–99 % un-notched, 13–75 % notched). A notch cannot rescue that, so none is applied.
- **EEG detector `'fixed'`** (lab default; the user rejected `'band'` as too lenient the same day). For comparison,
  `'band'` (1–40 Hz statistics) would flag (incl. Cz) BM 11 / RM 13 / JO 10 / KW 12 / L 11 channels with badTS
  13.5 / 23.9 / 0.4 / 2.3 / 11.2 %, and NE 29 / VL 30 channels (NE's 1–40 Hz SD rises from ~11 to ~18 µV after
  25 min; VL is 20–40 µV throughout).
- **Respiration viability gate without its autocorrelation rule for v2** (`P.vipOpts.respProbe.acMin = 0`): VL
  (0.30), JO (0.23) and L (0.28) fail the v1 AC ≥ 0.40 rule although every block shows clean breaths (slow,
  irregular meditation breathing with long pauses); band fraction ≥ 0.85 and the spectral-peak range stay — CC's
  unusable v1 channel fails both (0.73, 0.043 Hz).
- **ECG notched (60/120/180 Hz, ECG1 row only).** A first run without it passed every check, but a figure reviewer
  spotted BM's IBI histogram peaking at multiples of 1/60 s: the ripple the shared 5–40 Hz band-pass leaves on the
  heavily 60-Hz-contaminated ECG input locks beat times to the line cycle (IBI phase concentration at 1/60 s
  0.17–0.58 in 6 of 7 sessions vs ≤ 0.03 notched; beat-time shifts 1.5–3 ms SD; BM RMSSD 82 → 20 ms, RM 31 → 27).
  So the notch is necessary for the ECG; the EEG stays un-notched. Beat counts are unchanged by it (probe7).

Run (2026-10-20, lab desktop `E:\claudeWork\vip1020\`, R2024b, `ZLP_ALLOW_GUESS_RUN=1`, staging copies of the sheet;
finals on R: `<id>\preProc\<id>_vipassanapreproc.mat`, all verified with `verifyFinals_vip2.m`: whos, fs 500, moreThan1,
tiling, TTL = period starts, Cz row zero, ECG notch present, rspFlip = log sign, behDat columns). Master
`dataTracking.xlsx` rows **684–693** added 2026-10-20 14:06 under the lab sheet lock (backup
`sheetBackups\dataTracking_backup_261020_140600.xlsx`): AS/CC/DD (staged since 2026-09-26, never merged) + the seven new
ones, all `paramSource = guess`, `Data Preprocessed = X`. QC page: https://claude.ai/artifact/QAauecLbwDqUjYDWRNPxAB .

| Subject ID | row | task blocks (source) | breaths (good) | median rate /min | HR bpm | RMSSD ms | RSA ΔRR | EEG `'fixed'`: bad ch / badTS | `'band'` alternative | notes |
|---|---|---|---|---|---|---|---|---|---|---|
| 260927_EEG_NWU_BM | 687 | 6, photodiode+log (no paced2) | 1032 (1012) | 18.4 | 70.0 | 20 | −15.3 ms ✓ | 30 / 99.6 % | 11 / 13.5 % | log r 0.996, 0.64 ms; 68/68 paced breaths on target cycles |
| 260927_EEG_NWU_RM | 688 | 6, photodiode+log (no paced2) | 1461 (1414) | 20.5 | 83.6 | 28 | −9.6 ms ✓ | 30 / 86.8 % | 13 / 23.9 % | log r 0.999, 0.65 ms; anapana 25–35 /min (real); TP10 pops |
| 261016_EEG_NWU_NE | 689 | 6, photodiode+log (no paced2) | 854 (828) | 15.2 | 61.9 | 39 | −28.1 ms ✓ | 30 / 72.2 % | 29 / 5.1 % | log r 0.990, 2.5 ms; Resp 60-Hz dominated; EEG worsens after 25 min |
| 261018_EEG_NWU_JO | 690 | 7, photodiode | 688 (634) | 10.2 | 65.6 | 42 | −20.8 ms ✓ | 30 / 44.1 % | 10 / 0.4 % | no behavioral files; first paced sweep starts low |
| 261018_EEG_NWU_KW | 691 | 7, photodiode | 702 (665) | 10.3 | 41.5 | 97 | −78.9 ms ✓ | 30 / 14.7 % | 12 / 2.3 % | no behavioral files; HR verified against unimodal IBIs; F7 pops |
| 261018_EEG_NWU_L | 692 | 7, photodiode | 734 (682) | 10.9 | 60.1 | 36 | −33.9 ms ✓ | 30 / 60.2 % | 11 / 11.2 % | no behavioral files; ~12–15 % off-sweep paced breaths |
| 261018_EEG_NWU_VL | 693 | 7, photodiode | 782 (588) | 12.2 | 70.5 | 104 | −12.8 ms ✓ | 30 / 96.6 % | 30 / 34.6 % | no behavioral files; 19-s setup segment dropped; **metta breaths over-segmented** (noisy Resp); TP10 flat from ~26 min; `P.ecgEctopic` on (CLAUDE.md §3) |

Figure review (7 agents, one per session; workflow `wf_65fbaeaa-320` + `wf_12e4a50a-73c`): promote BM, RM, NE, JO, KW, L;
VL "review" (metta breaths). Superseded intermediate finals of the day (band-mode EEG; un-notched ECG) were kept only
on the lab E: drive for the comparisons above.

Open for the user: (1) `'fixed'` vs `'band'` for these BrainVision sessions; (2) behavioral files of JO/KW/L/VL, if
they exist (copy into `behavioralDat\` and rerun → log identities + paced targets); (3) promote guess → curated after
the figure review.

### 2026-10-21 follow-up: behavioral files, respiration source, broadband noise, average reference

User 2026-10-21: the behavioral files of JO/KW/L/VL were dropped into the study root → moved into each
`<id>\behavioralDat\` (10 files each: SniffLogic log with both sweeps, PsychoPy mindfulBreathing csv/log/psydat,
audioResp_recording, sweep1/sweep2 cycles + framelogs, template_breath; VL's false start — a 0.6-s log and a PsychoPy
set from 19h00 — in `behavioralDat\falseStart\`, out of the pipeline's reach). The Mac copy also left 68 hidden
AppleDouble stubs (`._<file>`, 4 KB, macOS metadata only) in the root; the user asked for a clean root, so they were
moved off R: to the lab desktop (`E:\reprocBackup_261021\vipassana\_appleDouble_root\`) — never into `behavioralDat\`,
where `._…sniffLogicLog….csv` would trip the one-log check — and the 2026-09-27 pre-notch finals folder went to
`E:\reprocBackup_260927_preNotch\vipassana\`. The study root holds only the 10 subject folders.

- **Blocks**: all 47 log blocks match a photodiode onset (+22–93 ms) and a PsychoPy white-square routine (±44 ms); the
  protocol-order labels JO/KW/L/VL had been given were all right. With the logs they now also carry paced targets.
- **Respiration source** (`respSeg_vip`: both traces prepared as the pipeline prepares them, segmented with the locked
  engine): **JO, L, VL → `rspIDX 2` (`rspSniffLogic`) / `rspFlip 1`** — the BrainVision Resp has transients (L, VL) and, in
  VL, a ~1.5-Hz ripple the log lacks; split breaths in the still blocks BV / log JO 1.1 / 0.2 %, L 2.7 / 0.4 %, VL 0.9 /
  0.4 % (VL metta 121 vs 82 breaths). BM, RM, NE, KW segment alike (onsets matched 90–98 %) and keep `rsp1` / −1. Master
  sheet written with `writeParams` under the sheet lock (backup `sheetBackups\dataTracking_backup_261021_114102.xlsx`).
- **Broadband EEG noise** (user asked what it is; probes `noiseProbe_vip` / `noiseImp_vip`, 60 s mid-vipassana): a flat
  white floor from ~20 Hz to the 140-Hz hardware low-pass in every v2 session — 70–110 Hz median channel 1.6–6.3 µV²/Hz as
  recorded vs 0.06–0.09 in AS/CC/DD. Not the electrodes: per-channel floor vs impedance ρ −0.25…0.26 in all 10 sessions
  (DD, 200–400 kΩ, is the quietest); NE was recorded in the lab with good impedances. The ECG aux input's 70–110 Hz SD rose
  too (2.5 µV in September, 4.4–5.5 BM/RM, 10–13 the rest). Same amplifier serials, firmware, 500 Hz and DC / 140-Hz
  settings; the recorded differences are `Active Shielding: On` in every v2 `.vmrk` (none in September — the user had
  deliberately left it off before AS/CC/DD), the aux inputs re-cabled (Resp → 66, ECG → 67) and an electrode-position file
  in the header (a different Recorder workspace). The user considers Active Shielding the cause; a short on/off bench
  recording would confirm it. After the average reference the floor is stationary over each recording (minute-by-minute
  probe), so within-session block contrasts are not biased by drift; 1–40 Hz SD of BM/RM/NE/JO/KW/L matches AS/CC
  (11–17 vs 12–13 µV; VL 22), beta carries a 3–10× higher floor, gamma is not recoverable in v2.
- **Average reference** (user: the EEG should be average-referenced before cleaning; Cz, the recording reference, is
  recoverable): `shared/robustAvgRef` at ingestion (`assembleRaw_vipassana`, after the artifact index and the v1 notch,
  both protocols); design and parameters in CLAUDE.md §1. Recovered Cz is a real channel (SD 0.5–2.1× the median channel;
  NE's Cz is its noisiest channel — much of NE's as-recorded common-mode noise was the Cz electrode itself).
  Development: the first rerun crashed after the shared core (the main read `raw.avgRef` after `clear raw`); a 10-agent
  adversarial code review then found that the first design let a dead electrode pass as good (CC FC5 reads 0 from 4 to 68
  min; after re-referencing it became −ref and the detector stopped flagging it), took the provisional median before
  removing DC offsets, and leaked brief rail swings into every channel; a windowed z > 5 rule then excluded 8–11 rows for
  eyes-closed alpha / eye movements. Final rule excludes 0–4 rows per session.

Final re-run 2026-10-21 (lab desktop, `payload_avgref3.ps1`; superseded finals in `E:\reprocBackup_261021\vipassana\<id>\`,
today's interim first-design finals in `E:\claudeWork\vip1020\avgRefV1Finals\`), all 10 verified (`verifyFinals_vip3.m`:
fields incl. `avgRef` / `dataRef`, `czRezeroed = false`, Cz not flat, TTL = block starts, rspFlip rule, blocks unchanged,
beats unchanged, breaths unchanged except the three sessions on the log trace). Detector `'band'` probe on the same data
(`bandProbe_vip.m`; no final uses it):

| Subject ID | left out of the average | `'fixed'` bad ch old → new | `'fixed'` badTS old → new | `'band'` bad channels | `'band'` badTS | breaths old → new | resp |
|---|---|---|---|---|---|---|---|
| 260918_EEG_NWU_AS | O1 | 4 → 2 (O1 Oz) | — → 4.8 % | 0 | 0.1 % | 1105 | rsp1 |
| 260918_EEG_NWU_CC | FC5 (flat) | 8 → 3 (FC5 O1 TP10) | — → 3.7 % | FC5 | 0.0 % | — (no usable resp) | — |
| 260918_EEG_NWU_DD | none | 1 → 0 | — → 0.6 % | 0 | 0.2 % | 1156 | rsp1 |
| 260927_EEG_NWU_BM | TP10 Fp2 | 30 → 30 | 99.6 → 14.3 % | F7 FT9 CP1 P7 O1 TP10 FC2 | 0.1 % | 1032 | rsp1 |
| 260927_EEG_NWU_RM | FT9 TP9 TP10 | 30 → 30 | 86.8 → 11.9 % | FT9 TP9 CP1 TP10 FT10 FC6 | 0.4 % | 1461 | rsp1 |
| 261016_EEG_NWU_NE | FT9 TP9 CP1 FT10 | 30 → 27 | 72.2 → 1.5 % | FT9 TP9 CP1 FT10 | 0.0 % | 854 | rsp1 |
| 261018_EEG_NWU_JO | Pz P7 FC2 | 30 → 30 | 44.1 → 2.5 % | F3 F7 CP5 Pz P7 O1 TP10 FT10 FC2 | 0.3 % | 688 → 666 | log |
| 261018_EEG_NWU_KW | F7 Pz P8 TP10 | 30 → 30 | 14.7 → 5.1 % | F7 FT9 FC5 FC1 Pz O2 P4 P8 TP10 | 1.4 % | 702 | rsp1 |
| 261018_EEG_NWU_L | FC6 | 30 → 30 | 60.2 → 10.8 % | T7 P8 CP6 FC6 F8 | 0.4 % | 734 → 700 | log |
| 261018_EEG_NWU_VL | P3, TP10 (flat from 26 min) | 30 → 30 | 96.6 → 33.0 % | F7 TP9 CP1 P3 P7 O1 P4 TP10 Cz | 7.0 % | 782 → 758 | log |

Figure review (10 Sonnet reviewers, problems re-checked by Haiku; workflow `wf_cc5cddab-1c2`): promote AS, BM, RM, JO, KW,
L; review — CC (ECG beat times line-locked, see below; weak pre|audiobook1 boundary, margin 6 vs 15–123), DD (60 spurious
beats in movement-artifact periods inflate raw-heartBeats HRV; ~3 % of shallow breaths after deep breaths unsegmented, gaps up to
14.6 s in vipassana / metta), NE (the recovered Cz is the noisy electrode, 2× its neighbours, in `badChans`), VL (badTS 33 %). The log trace fixed VL's metta over-segmentation (now 8–14 breaths/min).
**v1 ECG notch** (same day): the review found CC's beat times locked to the line cycle (IBI phase concentration at 1/60 s
0.38), so `ecgNotchHz = [60 120 180]` for v1 too and AS / CC / DD re-run: phase concentration 0.016–0.017 in all three;
beats AS 4183, CC 4447 (was 4436), DD 3933 (3935); EEG, breaths and blocks unchanged. CC's raw-heartBeats RMSSD stays
~122 ms because of short-IBI bursts in movement stretches, not line locking.

**`'band'` finals for the seven Active-Shielding sessions** (user, same day: "move the bad recordings to the band version to
recover as much as possible ... keep the default at fixed"): `applyParams` case for BM RM NE JO KW L VL sets
`P.eegClean.mode = 'band'`; `'fixed'` stays the default (the recording configuration is being changed). Re-run + verified
(`verify_band.csv`): bad channels BM 7, RM 6, NE 4, JO 9, KW 9, L 5, VL 9 (lists in the table above), badTS 0–1.4 % (VL
7.0 %), `dataLap` present again; beats, breaths and blocks unchanged. The `'fixed'` + average-reference finals of these
seven are kept on the lab desktop in `E:\claudeWork\vip1020\fixedAvgRefFinals\`.

**VL `P.ecgEctopic`** (new optional `processECG` stage, VL only; CLAUDE.md §3 / §5): `outDat.ecgEctopic` records the
corrected RR intervals; `heartBeats` keeps every beat.

Figures: https://claude.ai/artifact/UFxafckJDpXhotpiKo4iLc . Downstream: `vipassanaAnalysis` (`vip01_epochs.m:40`
asserts the Cz row is zero; `pop_reref`, `interpMap`, `vip04` Cz handling) needs updating for average-referenced finals.
`'band'` decided (above). The user fixes `vipassanaAnalysis` downstream in that repo. Open for the user: promote guess → curated.

## G2 / G3 round — guess sessions reprocessed 2026-10-21 / 22 (user decisions of 2026-10-20)

User 2026-10-20 (guess review `guessReview_261015`): detector stays `'fixed'` (`'band'` rejected as too lenient); G2a keep the frontal blink
rule, G2b no blink removal in `sleep` / `sleepWithOdor` sections (`config/sepConditionInfo.m`, `sepSectionP.m`), G2c zero `blinkIndicator` row
for every skip (`concatSections.m`; these three files are deployed but **not committed**), and "reprocess any sessions where this will have
caused an impact". The EEG survey (227 finals; `R:\…\Adam\Dupi_processing\eegReprocList_261020\`) turned that into a 31-row plan
(`reprocPlan_G2.csv`: 22 G2a finals, 8 G2b only, TB_2 threshold whose final is corrupt). Every rerun also applies the fixed detector and every
code change since the final was made. Mechanics: lab desktop, `ZLP_MAIN_ONLY=<id>` (+ `ZLP_ALLOW_GUESS_RUN=1` on guess rows; the sep main reads no
`_ALL`), under the sheet lock; backup `E:\reprocBackup_261021\<task>\<id>\` (size + SHA-256 verified), old final moved to
`preProc\superseded_261021\`; `paramSource` untouched (the guess rows stay guess), no sheet cell changed (RC_2 sep: nine type-only cells).
The lab desktop and R: became unreachable at about 19:10 on 2026-10-21 (VPN) with 15 of 31 rows finished; two more finished on their own (AD_1 breathing 19:16, TB_3 cue 19:19), and
the rest ran on 2026-10-22 10:34–11:19 after the VPN came back. **The plan is finished: 28 new finals live, 3 reverted (VW, ADtest, MS), none failed**; four independent lab-side audits of
2026-10-22 passed with minor findings (below).

Guess rows that were in the plan:

| Subject ID | task (sheet rows) | basis | outcome |
|---|---|---|---|
| 251218_OBE_NWU_SM_1 | sep, sleep (393) | G2b + fixed detector (plan: G2b, detector class 3) | rerun 2026-10-21 17:26, final 53,772,473 B (old 2026-10-12 15:28). Sleep: blink ICA off. Bad FC1 TP9 (same); badTS 7.21 → 3.61 %; interpolated 93.75 → 97.36 % = the survey's prediction; EEG rows changed by 0.396 of the old norm (95.5 % of the squared difference in badTS samples). Breaths 35, beats 183, behDat identical. Sleep-only: no `blinkIndicator` row (G2d) |
| 260105_OBE_NWU_ZF_1 | sep, sleep (337) | G2b + fixed detector | rerun 17:40, 257,469,092 B (old 2026-10-12 16:09). Sleep: blink ICA off (old stage had found no IC, rc 0.47, but still projected: its good-channel block had rank 30 of 31). Bad F7 (same); badTS 8.86 % (same); interpolated 95.70 → 95.69 %; EEG rows 0.031 (one principal component, share ≥ 0.9999: the end of that projection). 193 breaths, 483 beats identical. No `blinkIndicator` row (G2d) |
| 260824_OBE_NWU_ZF_2 | sep, sleep + restingBaseline (582, 585) | G2b (no detector change) | rerun 18:10, 484,513,991 B (old 2026-10-12 15:38). Sleep: blink ICA off, zero `blinkIndicator` over it; resting: IC1 Fp2 (rc 0.99, same under both rules). Detector unchanged. EEG rows 0.600 (sleep) / 0.002 (resting). 427 behDat rows identical |
| 260827_OBE_NWU_RX_2 | sep, focusedBreathing_button + audiobook + restingBaseline (595, 596, 599) | G2a (legacy IC2 / IC1 → frontal IC6 / IC9 in the survey) + detector | rerun 18:19, 411,464,822 B (old 2026-10-12 14:00). Frontal ICs: button IC12 (Fp2, rc 0.85), audiobook IC4 (Fp2, 0.94), resting IC3 (Fp2, 0.89). The survey's audiobook difference was not reproduced (both rules picked IC4 in this draw; the ICA is unseeded). P8 bad in all three (same). EEG rows 0.629 / 0.724 / 0.079. 298 behDat rows identical |
| 261008_INR_NWU_SS_1 | sep, resting + sleep + focused button + nose clip (667, 668, 670, 678) | G2b (detector already fixed) | rerun 18:47, 797,220,072 B (old 2026-10-15 22:10). Sleep: blink ICA off (old stage: none, rc 0.34; the audit found old and new differ by at most 1.3e-12 µV, so the old stage applied no projection there); resting IC8 Fp1 (0.68), button IC12 (0.72), nose clip IC13 (0.62), as before; EEG rows 0.0035 / < 0.0001 / 0.0022 / 0.0083. 466 behDat rows, 2472 beats identical |
| 250904_OBE_NWU_TI_1 | EmotionalMovieTask (197) | G2a (legacy IC2 → frontal IC1, Fp2 r 0.87) + detector (badTS 14.26 → 14.84 %) | rerun 2026-10-22 10:55 (`ZLP_ALLOW_GUESS_RUN=1` + `_ALL=1`, `paramSource` stays guess), final 669,894,176 B (old 2026-10-12 13:54, backup SHA-256 `0262097F…D736`). Frontal IC1 (Fp2, r 0.871, front ratio 4.04; legacy pick IC2, r 0.505); 11 bad channels (same); badTS 14.264 → 14.842 %; interpolated 82.308 → 79.127 %. EEG rows 0.741 (good rows 0.919), dataLap 0.417. behDat (416 × 50), 180 clips (valence code 1 / 2 / 3 = neutral / happy / sad: 59 / 61 / 60; in-clip breaths neutral 132, happy 129, sad 155), bmObj, beats, CSV identical; macBP 0.16–0.52 % (unseeded spike ICA). No PsychoPy clip log exists for TI_1 (nor CP_1; lab listing 2026-10-22), so the clip codes cannot be cross-checked as the respiratorySweep code does for MS (60 / 60 / 60); AS_4's log is in `BehaviorResults\emotionClips\`, not `behavioralData\`. Audit minor findings: Fp1 residual in blinks worse (272 → 541 µV), Fp2 better (465 → 233 µV); good-channel block rank 20 (old) → 13 of 21 (G2j) |

Effects common to the ten separate-conditions reruns (five guess, five curated): detector numbers equal the survey's prediction; all 10 sleep /
sleepWithOdor sections skipped the blink ICA; six zero `blinkIndicator` rows over skipped sections (RC_1 ×2, HM_2, ZF_2, RC_2, SS_1); the four
sleep-only finals (GH_1, DL_1, SM_1, ZF_1) have no row (open question G2d, VC_1 too); blink-cleaned rows of old-rule sections changed by 0.08–0.93 of
the old norm (the frontal mode trains on a window without the badTS epochs; the ICA is unseeded); one DL_1 breath moved 4 ms (rev13 onset floor);
RC_1 macros differ at ≤ 3.5 µV (unseeded spike ICA). Curated rows of the same plan (all finished): breathing TB_3, AB_2, DL_1, DB_2, PD_2 (2026-10-21), AD_1 (19:16, finished
unattended) and AD_2 (2026-10-22 10:40) live; VW and ADtest breathing rerun then **reverted** (the rerun loses `outDat.reconstructedBlocks`, G2e); cue TB_3 (19:19, finished by the
first attempt's queued job, verified, not rerun), AB_1, AB_3, JN_3, JL_1, AD_2 (`noCue` recode of 20 trials), threshold TB_2 (corrupt final regenerated: 22 bad channels, no blink ICA, no
dataLap, G2h), O15 CP_1 and JL_1 (TTL and behDat identical to the July finals), alternating 6 AL live; movie MS rerun then **reverted** (the deployed code lacks the
`respiratorySweep-261008` movie commits: the rerun gave 192 instead of 180 clips and lost the clip cross-check, G2g; six more EEG movie finals of that branch would regress alike).
Evidence: the four lab-side audits of 2026-10-22 (`g2recAudit_breath` 432 checks 0 fail; `g2recAudit_sep` 346 pass, 2 explained fails; `g2recAudit_cto` 256 pass 0 fail; `g2recAudit_movie` 190 pass,
2 fails = the MS clip table) re-loaded every new final, re-hashed backups and superseded copies (equal), diffed the sheet (12 changed cells in all: nine RC_2 type-only, three `hasMacros`
blanks filled) and found no file touched outside the plan. Minor audit findings: lost rank in blink-cleaned sections (HM_2 focusedBreathing 7 of 18, TI_1 13 of 21, G2j); RC_1 resting blink
residual mixed; AB_2 / AD_1 / DL_1 sep / AL breath onsets moved to the rev13 floor (4–344 ms); spike-ICA macBP differences up to 13.6 µV in TB_3 cue. The sep reports' "G2e" (the blink
stage's rank-k reconstruction, applied in every blink-cleaned section even when nothing is removed) is not the review's G2e (VW / ADtest). Other finals of the 2026-09-03
raw-volume backfill that are not in the plan may carry pre-rev13 breath onsets and move by a few ms on any rerun.
Reports: `job1020\reports\g2rep_*.md`, `g2rec*.md`, `g2recAudit_*.md`, `g2recReport.md`, `g2report.md`, `g2reportFix.md`.

Guess rows reprocessed or first processed in the O15 work of the same round (G3; not G2):

| Subject ID | task (sheet row) | outcome |
|---|---|---|
| 260917_OBE_NWU_RC_2 | O15 (622), held-button | first final 2026-10-20; 9 free-sniff pairs shared a `finalOnset`; regenerated 2026-10-21 11:31 with the new `tasks/O15/resolveHeldButtonSniffs_O15.m` (one free sniff per inhale; `mergeDropFrac` 0.35): 15 trials, 15 start / 92 free / 15 confirm, no onsets closer than 0.59 s; verified 26 / 26, Fable audit pass with minor. Params rspIDX 1 / +1, hasEEG TRUE, spikeClean FALSE, 5000 / 150 / 500. Backup `E:\reprocBackup_261021\O15\260917_OBE_NWU_RC_2\` |
| 250225_OBE_NMH_AS_5 | O15 (157), oldTTL | re-extracted (`LoadData_250225_OBE_NMH_AS_5_claude.m`; old raw in `raw\raw_O15\superseded_261020\`), first final 2026-10-20 14:38: 15 trials, 15 start / 52 free / 15 confirm; verified 0 failures; current code reproduces it (not rerun). Params rspIDX 2 / +1, hasEEG FALSE, macroRemove 6, 5000 / 150 / 500. Audit note: a partial Atlas record at 172.3 s makes absolute times after it ~86.5 ms late |

Curated GH_2 / PD_1 O15 (not guess): the parser cases are deployed (`P.ttl.confirmRule = 'pairs'`; `P.pd.zthresh = -0.23`), Fable audit pass; the stored
pre-July finals were **not** rerun (decision G3f). Sheet: new column `ttlProtocol` (AD) on all 47 O15 rows (44 oldTTL, 3 heldButton).
Open for the user: `guessReview_261015.html` G1c, G2d, G2e, G2f, G2g, G2h, G2i, G2j, G3f, G8a and the seven S21 decisions. The vipassana guess finals (rows 684–693) in the sheet's final column were
replaced the evening of 2026-10-21 (17:27–18:20; the seven v2 sessions cleaned in `'band'` by explicit case, see the vipassana sections above); the review's Part 4 was re-dumped 2026-10-22.

## Code decisions of the 2026-10-22 full EEG rerun (branch `fullRerun-261022`)

Reviewer decisions from `guessReview_261015` that are now code, and facts found while building the rerun (CLAUDE.md §1, §5, §6, §8):

| item | outcome |
|---|---|
| G2d (sleep-only separate sessions) | yes: `concatSections` inserts the all-zero `blinkIndicator` row in every section of a sleep-only session (GH_1, DL_1, SM_1, ZF_1 get it when rerun); proven on DL_1 sleep, 53 of 53 other rows bit-identical |
| G2f (`251027_Dupi_NMH_DL_1` breathingTask) | no blink removal: explicit `applyParams` case (`P.blinkRemoval = false`, reason in `outDat.blinkRemovalNote`); the unseeded ICA had removed IC 2 in one draw and none in the survey draws (best frontal r 0.5977 / 0.56 against 0.60) |
| G2g (`260811_EEG_NWU_MS` movie) | explained: the lab's deployed code lacked the `respiratorySweep-261008` movie commits; with this tree the rerun gives the 180-clip PsychoPy-checked table again (TTL identical to the 2026-10-12 final), as do the other 10 logged EEG movie sessions |
| G2e (VW, ADtest breathingTask) | no redo of the reconstruction: the respiration carry keeps the reconstructed `rsp` rows, `targTrace` and `reconstructedBlocks`, the rerun supplies the new EEG |
| `dataLap` | fixed (electrodes projected onto the unit sphere around their least-squares centre, CLAUDE.md §6.3); every final made before 2026-10-22, DD included, carries the old common-mode `dataLap` until it is rerun |
| ICAs | reproducible: `runica` started from its fixed state, spike-ICA draws seeded from the session ID (CLAUDE.md §5) |
| movie clip logs | `250225_OBE_NWU_AS_4`: log found in `BehaviorResults\emotionClips\`, 174 of 180 played clips matched (175 unchecked photodiode clips before); `250904_OBE_NWU_TI_1`, `251009_OBE_NWU_CP_1`: no log on the server, photodiode parse kept (CP_1: 186 clips, at least 4 spurious) |
| `noCue` audit | 13 cue sessions have cue == 0 trials (60-trial files, 20 each); every final codes them `noCue` (CLAUDE.md §1) |

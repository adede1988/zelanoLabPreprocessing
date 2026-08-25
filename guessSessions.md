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
isNewStd=true — plus **empirical rspFlip=−1** (each subject's SniffLogic
log-alignment polarity from its alternating6Blocks intermediate) and
**beatSpec=`1,0,lt,-3.5`** (2026‑08 rigs record ECG lead 1 inverted; measured
80.8 bpm on JH vs 3.1 with the default). QC figures per session under
`R:\…\Adam\Dupi_processing\<id>\`.

| Subject ID | Task | Type | guessed columns = values | basis | status | notes |
|---|---|---|---|---|---|---|
| 260806_EEG_NWU_JH | EmotionalMovieTask | EEG_breathing | EEG standard + rspFlip=−1, beatSpec=1,0,lt,-3.5 | empirical (log align \|r\|=0.92) | run-on-guess | 192 clips, 356 breaths, 81 bpm |
| 260806_EEG_NWU_MM | EmotionalMovieTask | EEG_breathing | same | empirical (\|r\|=0.86) | run-on-guess | 189 clips, 441 breaths, 73 bpm |
| 260807_EEG_NWU_GP | EmotionalMovieTask | EEG_breathing | same | empirical (\|r\|=0.83) | run-on-guess | 196 clips, 266 breaths, 66 bpm |
| 260810_EEG_NWU_IS | EmotionalMovieTask | EEG_breathing | same | empirical (\|r\|=0.91) | run-on-guess | 190 clips, 377 breaths, 55 bpm |
| 260810_EEG_NWU_AL | EmotionalMovieTask | EEG_breathing | same | empirical (\|r\|=0.81) | run-on-guess | 188 clips, 437 breaths, 74 bpm |
| 260811_EEG_NWU_MS | EmotionalMovieTask | EEG_breathing | same | empirical (**\|r\|=0.47 — weak, REVIEW**) | run-on-guess | 192 clips, 376 breaths, 80 bpm; alignment weak (NaN-gap recording) |
| 260811_EEG_NWU_HK | EmotionalMovieTask | EEG_breathing | same | empirical (\|r\|=0.81) | run-on-guess | 185 clips, 392 breaths, 62 bpm |
| 250225_OBE_NWU_AS_4 | EmotionalMovieTask | OBEControl | rspIDX=1, rspFlip=+1 (curated row 12), hasEEG=**false** (no cap), hasMacros=true, spikeClean=false, beatSpec=1,0,gt,3.5 | inherited + old getSessionParams_emotionTask | not run (validated up to gate in memory) | old final left untouched |
| 250904_OBE_NWU_TI_1 | EmotionalMovieTask | OBEControl | rspIDX=3, rspFlip=+1 (curated row 49), hasEEG=true, spikeClean=true, spikeThresh=**50**, beatSpec=`1,0,lt,-2 & 2,1,gt,3 & 3,2,lt,0` | inherited + old script values | not run | new-format intermediate saved (180 clips, 59/61/60 by valence) |
| 251009_OBE_NWU_CP_1 | EmotionalMovieTask | OBEControl | rspIDX=1, rspFlip=+1 (curated row 77), hasEEG=true, spikeClean=true, spikeThresh=**15**, spikeWin=**7**, macroRemove=**6**, beatSpec=`3,0,lt,-3` | inherited + old script values | not run | old final left untouched |

## alternating6Blocks (Task 8)

Same EEG standard set + empirical rspFlip=−1 + beatSpec=`1,0,lt,-3.5` for all
eight subjects (identical basis to the movie rows above; the alignment runs on
this task's own recording).

| Subject ID | Task | Type | guessed columns = values | basis | status | notes |
|---|---|---|---|---|---|---|
| 260805_EEG_NWU_CA | alternating6Blocks | EEG_breathing | EEG standard + rspFlip=−1, beatSpec=1,0,lt,-3.5 | empirical (\|r\|=0.85) | run-on-guess | **blink removal skipped — both blink channels bad (REVIEW)** |
| 260806_EEG_NWU_JH | alternating6Blocks | EEG_breathing | same | empirical (\|r\|=0.92) | run-on-guess | 7 blocks, 723 breaths, 87 bpm |
| 260806_EEG_NWU_MM | alternating6Blocks | EEG_breathing | same | empirical (\|r\|=0.86) | run-on-guess | 7 blocks, 533 breaths, 76 bpm |
| 260807_EEG_NWU_GP | alternating6Blocks | EEG_breathing | same | empirical (\|r\|=0.83) | run-on-guess | 7 blocks, 511 breaths, 72 bpm |
| 260810_EEG_NWU_IS | alternating6Blocks | EEG_breathing | same | empirical (\|r\|=0.91) | run-on-guess | 7 blocks, 537 breaths, 58 bpm |
| 260810_EEG_NWU_AL | alternating6Blocks | EEG_breathing | same | empirical (\|r\|=0.81) | run-on-guess | 7 blocks, 426 breaths, 73 bpm |
| 260811_EEG_NWU_MS | alternating6Blocks | EEG_breathing | same | empirical (**\|r\|=0.47 weak** + drift −390 ppm — REVIEW) | run-on-guess | 7 blocks, 272 breaths, 85 bpm; low breath count |
| 260811_EEG_NWU_HK | alternating6Blocks | EEG_breathing | same | empirical (\|r\|=0.81) | run-on-guess | 7 blocks, 413 breaths, 65 bpm |

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

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

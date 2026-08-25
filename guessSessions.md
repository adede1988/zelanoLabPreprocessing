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
| 260227_EEG_NWU_HW | waveBreathing | EEG_breathing | 177 | rspIDX=1, rspFlip=(modal curated EEG value), hasEEG=true, hasMacros=false, spikeClean=false, spikeThresh=20, spikeWin=11, macroRemove=[], beatSpec=1,0,gt,3.5, isNewStd=true | Type default (EEG standard set, §0 D3.3) | run-on-guess (D4) | extracted in Task 2; rsp = CSC270 (old wiring) |
| 260608_OBE_NWU_RX_1 | breathingTasks | OBEControl | 250 | modal curated OBEControl values (see task3_writeGuesses output) | Type default | not run | breathing raw missing on disk; sheet says extracted |

(The `251009_EEG_NWU_SM` row 66 stub is a duplicate of curated row 81 — not a guess session.)

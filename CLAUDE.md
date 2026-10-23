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
- `batch/fullRerun/README.md` — the lab-side driver of the 2026-10-22 full EEG rerun (§8).

---

## 1. Tasks

| canon name (`P.task`) | sheet `Task` values (matched case‑ and whitespace‑insensitively) | what's unique |
|---|---|---|
| `breathingTask` | `breathing tasks`, `breathingTasks`, `waveBreathing` | breathing blocks; **per‑breath table**, **ECG/HRV**, **paced target‑trace alignment**, **emotion ratings**. The richest task and the template for every new breath‑based task. |
| `cueTask` | `odor cue task` | odor cue / sniff / response TTLs; hit/miss/cr/fa behavior. **No-cue trials** (`cue == 0`, coded `type = noCue` by `tasks/cue/cueTrialType`) come with the 60-trial result files (2 runs × 30 trials, exactly 20 of them no-cue); every other cue session is the 40-trial design (2 × 20, cue 1–10 only), so the design belongs to the result file, not to a recording date. Audit 2026-10-22 of all 55 cue sessions (result files vs finals, by Atlas recording date): 13 sessions have no-cue trials — `260326_OBE_NWU_AD_2` (recorded 2026-05-18), `260702_OBE_NWU_SP_2`, `260622_OBE_NWU_RC_1` (recorded 2026-07-06), `260720_OBE_NWU_KA_2`, and 9 of the 10 sessions recorded on or after 2026-08-01 (`260817_OBE_NWU_CC_1`, `260820_OBE_NWU_RA_1`, `260824_OBE_NWU_ZF_2`, `260827_OBE_NWU_RX_2`, `260831_OBE_NWU_CS_2`, `260917_OBE_NWU_RC_2`, `260921_OBE_NWU_BW_2`, `260820_OBE_NWU_DW_1`, `260824_OBE_NWU_EZ_1`; the tenth, `261008_INR_NWU_SS_1`, is the 40-trial design). All 13 finals code every one of them `noCue` and nothing else (`260702_OBE_NWU_SP_2` trial 9 and `260827_OBE_NWU_RX_2` trial 7 have no detected sniff row, so 19 of 20). |
| `cueTask3` | `cueTask3` | the odor‑matching cue task with **three sniffs per trial** (added 2026‑10‑16 with `261008_INR_NWU_SS_1`; task code `OBE_task_backup\tasks\olf_cuetask\src\olf_cuetask_3sniff.m`): per trial a 0.3‑s pulse at the cue word, ~5.5 s later three 0.5‑s SNIFF pulses **1.1 s apart** (the odor line open across them), a 0.7‑s pulse at the Yes/No key; per run a 6 × 0.3‑s start and a 2 × 0.3‑s end code; 2 runs × 20 trials in ONE recording (`raw_cueTask3`), one result file per run (the cue format) in `labPaths().behCue\<id>_3sniffs\`. `cueTask3_makeOutDat` parses the event channel strictly (`parseEvents_cueTask3`: the exact pulse grammar, response pulses vs the answers, trial‑start intervals vs the laptop clock) and reuses the cue pieces (`outMat_to_table`, the odor‑line recode, `tasks/cue/cueTrialType`); the main reuses `assembleRaw_cueTask(S, 'cueTask3')` and `build_behavior_table_cueTask`. Sniffs 1.1 s apart defeat the legacy `testSig`‑threshold search (the metric stays above threshold between them), so `P.sniffTrain` (§3) switches the shared `detect_sniffs_from_TTLs` / `refine_onsets_with_phase` to their **train mode**: each SNIFF cue's own inhale peak (max of `smoothR` from cue − 0.2 s to the next cue − 0.1 s, the last cue + 1.2 s) and trough (min since the previous peak), coarse onset at 10 % of the rise, `finalOnset` = the legacy steepest‑rise rule between that trough and peak (`respThresh` unused); every other task runs the legacy code unchanged (proven identical on 3 cue finals 2026‑10‑16). `moreThan1 = 1`. Per‑session `P.noOdorTrials` flags trials whose odor never arrived (`behDat.noOdorDelivered`; SS_1 trial 2 = the first PEA trial, line not connected). QC: `cueTask3_events.png`, `allSniffs_bySniffIndex.jpg`, `sniffTrains_allTrials.jpg`, `epochs_sniff1..3.jpg`, `allSniffs.jpg`, `sniffsTrial<n>.jpg`. |
| `threshTask` | `threshold` | PEA threshold; 45 single‑sniff trials (1 run, odor 1/2/3 = air/low/med, one result file). **Multi‑run design** (from `261008_INR_NWU_SS_1`, 2026‑10‑15; task code `make_cuelist_thr_3odors`): air + PEA low / med / **high** (pure PEA, olfactometer line 12), 10 trials per condition per run, **2 runs of 40 in ONE recording** (each run: 3 × 0.3‑s start code + 40 × 0.5‑s sniff pulses), one `<id>_run<k>_results.mat` per run. Detected from the behaviour files (> 1 `.mat` in the session's results folder, which must then be exactly a `run1..K` set — `tasks/thresh/loadBeh_multiRun_threshTask`); the makeOutDat splits the pulses at every start code (`splitRuns_threshTask`, strict per‑run counts) and stores `outDat.threshDesign`; every single‑file session runs the legacy code unchanged. **Detection build** (from `261012_INR_NWU_VC_1`, 2026‑10‑20; task code `threshold_task_det.m`, same 2 × 40 design): a Yes/No "Was there an odor?" screen (2.5 s, mouse click) before the intensity and pleasantness ratings; the task appends `_det` to the ID, so the files are `<id>_det_run<k>_results.mat` in `results\results\<id>_det\` with a 10‑cell `outMat` (+ `detection` = the answer 1 Yes / 0 No / NaN no click, the screen side already decoded; `detection_rt` s). The makeOutDat finds the build from that folder (error if a standard folder also holds files) and always reads it with the run‑set loader, which checks the names, the 10 columns and the `.txt` twin's header / trial / odor / detection columns; `behDat` gains `detect`, `detectRT`; an empty rating is NaN there (not 735; `threshDesign.emptyRatings`). |
| `O15` | `O15` | loads raw directly (no `makeOutDat`); photodiode TTLs via `detect_ttls_O15`. `O15_noTTLs_skip` / `O15_corrupted` are deliberately unmatched. Trial motif on the (AC‑coupled, rail‑clipped) event channel: short start pulse → 0.5‑s start cue 7.78 s later → free events → press pair (2 short, 0.41 s apart) → confirm pair (2 × 0.5 s, 0.61 s apart). **Two free‑sniff protocols** = the sheet column **`ttlProtocol`** (§3; read by `applyParams` into `P.ttl.protocol`, written back by `writeParams`; strict: blank / any other value errors; tasks_261014 task 10, made a sheet parameter 2026‑10‑20): `oldTTL` — one fixed 0.5‑s pulse per sniff the experimenter saw, legacy z‑score parse (named `pressPulse` in the code until 2026‑10‑20; that spelling is still accepted and read as `oldTTL`); `heldButton` — the experimenter **holds** the button while the bottle is under the nose — the lab's protocol since July 2026. Every O15 row carries it by its Atlas **recording** date (≤ 2026‑07‑02 `oldTTL`, last `260702_OBE_NWU_SP_2`; ≥ 2026‑07‑09 `heldButton`: `251030_Dupi_NMH_DB_3` 2026‑07‑09, `251120_Dupi_NMH_JL_3` 2026‑07‑16 (not extracted), `260917_OBE_NWU_RC_2` 2026‑09‑17; the ID date is the enrollment date, not the recording date), so every new O15 row needs `ttlProtocol = heldButton`. Two `oldTTL` sessions keep explicit `applyParams` `switch` cases that restore how their curated pre‑July finals were parsed (G3d, 2026‑10‑21; with them the current code regenerates each final's `TTL` table exactly): `250929_Dupi_NMH_GH_2` `P.ttl.confirmRule = 'pairs'` (the task restart left a lone sniff‑width pulse between trial 13's press and trial 14's start, so the default `'window'` confirm rule finds 14 confirm pairs) and `260316_Dupi_NMH_PD_1` `P.pd.zthresh = -0.23` (AC coupling shortens every 2nd confirm pulse below `trialSplitSamp` at z = −2 → 45 trial marks; every z from −0.250 to −0.205 reproduces the final, −0.23 = mid‑window). In a `heldButton` session `parse_O15_events` parses the channel on median/rail‑referenced levels (the holds put ~25 % of samples on the rail, so the z‑score threshold fails), the button‑down periods go to `outDat.buttonDown`, and `heldButtonFreeSniffs_O15` makes every inhale inside a period a `free` sniff. One free sniff per inhale (2026‑10‑21): where `refine_onsets_with_phase` puts two rows of a trial on the same `finalOnset` (its 1‑Hz phase has one cycle for a quick double sniff or an end‑exhale pause before the inhale; RC_2: 9 pairs), `resolveHeldButtonSniffs_O15` splits the seeds into inhales (two inhales when smoothR drops between them by ≥ 0.35 of the pair's excursion, i.e. an exhale), keeps the seed nearest the shared onset for the inhale that holds it, drops the other seeds of that inhale and re‑refines every other inhale between its own trough and peak (the train‑mode rule); rows without a collision are untouched (DB_3 regenerates identically); record `outDat.ttlInfo.heldResolve`. |
| `pacedBreathing` | `pacedBreathing` | **marker-free** single EEG_breathing recording (added 2026-09-15 with `260915_EEG_NWU_KG`): ~7 min audiobook/survey, ~90 min paced breathing at a sweep of paces x depths with brief breaks, ~10 min focused breathing. Loads raw directly (no `makeOutDat`, no behavioral file); **blocks are inferred from the segmented breaths** (`inferBlocks_pacedBreathing`, positional labels `pre`/`paced`/`final`, stored in `outDat.blocks` + `blockInference`, `TTL` = block starts); per-breath table adds `rateBPM`, `localPeriodCV`, `localAmpCV`, `nSubPeaks` (raggedness). ECG/HRV via the breathing path. Multi-file recordings (an acquisition stop/restart) are stitched end to end by the LoadData script; the seam is carried to the final (`outDat.segments`) and breaths near it flagged (`behDat.nearSeam`). **Blocks and the breath merge (user decision 2026-10-23):** the blocks are inferred from the ENGINE's breaths, BEFORE the shared breath merge (§5), exactly as in every final made before the merge rule; the merge changes only the per-breath table. (Inferring them from the merged breaths changed the blocks in the validation rerun — `260915_EEG_NWU_KG` 31 → 29 blocks, `260917_EEG_NWU_JW` 23 → 24, boundaries, labels and per-breath `task` / `condition` moved — so the order is fixed.) Proven on the lab (scratch rerun of both finals with the respiration carry, 2026-10-23): `outDat.blocks` (`isequaln`, every column), `TTL`, the block labels and `blockInference.blkOfBreath` equal the previous finals' for KG (31 blocks) and JW (23 blocks; JW's whole `blockInference` is equal, KG's previous one carries the 2026-09-15 `patched` note and lacks the later default option `opts.natPooled`). `behDat` has one row per merged breath (KG 1472 → 1439, JW 970 → 967) whose `task` / `condition` are those of the block of its first engine breath (the same as in the previous final for every breath that survives the merge); `blocks.nBreaths` and the per-block medians are engine-breath statistics; `outDat.blockMergeInfo` holds both counts per block (`nBreathsEngine`, `nBreathsMerged`, `nStraddling` = merged breaths whose engine breaths lie in two blocks — 0 in both —, `nEmptyBlocks`). `blocks_inferred.jpg` plots the engine breaths the blocks came from. |
| `EmotionalMovieTask` | `EmotionalMovieTask` | emotional film clips (the 180 DEVO2 clips of the task's conditions file, 60 neutral / 60 happy / 60 sad, random order). `emotionalMovieTask_makeOutDat` parses the photodiode (`detect_ttls_emotionalMovieTask`: 1 / 2 / 3 pulses = neutral / happy / sad) into a **clip table** that is `outDat.TTL` (`clipOnset, clipEnd, nPulses, valence`). The **behavioral file** is the PsychoPy clip log `<id>\behavioralData\<id>_emotionalMovieTask_*.csv` – optional, but without it the clip table is not cross‑checked and has no titles or norms, so copy it in with every session. `tasks/emotionalMovie/findPsychoPyClipLog_emotionalMovie` finds it: `behavioralData\` first, then the 2025 OBE layout's `BehaviorResults\emotionClips\` (which also holds other sessions' logs, so only files named `<id>_emotionalMovieTask_*.csv` count, the largest wins — an aborted start leaves a near-empty one). **Photodiode parse only — no log anywhere on the server (searched 2026-10-22):** `250904_OBE_NWU_TI_1` (180 clips, 59 / 61 / 60 by pulse count) and `251009_OBE_NWU_CP_1` (186 clips, 61 / 64 / 61, at least 4 of them onsets 0.8–1.0 s after a 3-pulse onset); they have no titles, norms or `movieStart` / `movieStop`, and their counts cannot be verified. `250225_OBE_NWU_AS_4` has its log in `BehaviorResults\emotionClips\` (found since 2026-10-22): 174 of the 180 played clips matched (the first six were played 17–71 s before the recording started), where the photodiode parse alone gave 175 unchecked clips. Rerunning the 11 EEG sessions that have a log through the current code reproduces their 2026-10-12 clip tables exactly (TI_1 and CP_1 their photodiode tables): the 2026-10-22 regression of `260811_EEG_NWU_MS` (192 clips) came from the lab's deployed code, which lacked these commits. **PsychoPy cross‑check (2026‑10‑08):** with the log, `matchClipsToPsychoPy` aligns its photodiode times to the detected pulse groups (piecewise: the PsychoPy‑to‑recording mapping can step between two clips – 260806_EEG_NWU_MM +0.80 s from clip 44, 260807_EEG_NWU_GP +0.36 s from clip 135, with no gap in the recordings – so each run of clips gets its own linear fit, `clipCheck.clockSegments`), picks the z threshold by agreement, drops detections with no played clip, takes valence from the log, adds `nPulsesDetected`, `psychopyIdx` and `fileName` (the clip title) and records `outDat.clipCheck` (the default threshold over‑counted badly on noisy event channels: 248 / 241 clips for 180 played in RC / IS; the 260806_EEG_NWU_JH final made before the check had 192 clips incl. 12 spurious and 10 with the wrong pulse‑count valence). **Since 2026‑10‑12** it also adds `vidLenSec` (clip length, s) and `normValence`, `normArousal`, `normImpact` – the **DEVO2 per‑clip mean ratings** on 1–9 scales (Davidson et al. 2025, *Behav Res Methods* 57:161) carried by the conditions file, **not the participant's ratings** (the task collects none) – plus each clip's PsychoPy `movie.started` / `movie.stopped` placed on the recording relative to the clip's own photodiode onset (`movieStart`, `movieStop`; the task starts the movie with the trial but the photodiode flash = `clipOnset` 2 s into it, so `clipOnset` is ~1.6–1.9 s after `movieStart`; the clip windows keep the legacy flash‑based definition, `clipEnd` = next flash − 1.6 s ≈ `movieStop` + 0.27 s), and ends at its own `movieStop` the last clip and any clip followed by an unmatched one. The per‑breath table keeps **only in‑clip breaths** (`condition` = valence code 1/2/3; without the log the final clip has no defined end, so its breaths are dropped) and carries the breath's clip as `clipIndex` (row of `TTL`), `clipValence`, `clipOnset`, `clipFile`, `clipVidLenSec`, `clipNormValence`, `clipNormArousal`, `clipNormImpact` (`""` / NaN without the log, or when the intermediate predates 2026‑10‑12 – the norms need a fresh `makeOutDat`: back up and delete the final, which is the intermediate's file). ECG/HRV via `runECGStage` (NaN‑HRV fallback, `ecgSkipped`). |
| `alternating6Blocks` | `alternating6Blocks` | alternating breathing blocks (EEG_breathing) with ratings from the Google‑Drive behavioral files: `alternating6Blocks_makeOutDat` matches the `mindfulBreathing` ratings file (carries the participant ID) and the `sniffLogicLog` (matched by date + start time) and aligns the log to the raw respiration (`alignLogToRaw`) → `outDat.blocks` (`label, order, startSample, endSample`) + block‑start `TTL`. The per‑breath table keeps in‑block breaths (`task` = block label, `condition` = block order) with the block's ratings broadcast + `baseEmotion`. ECG/HRV via `runECGStage`. **Block starts follow the shared `alignLogToRaw` map** (anchored drift line, fixed 2026‑10‑08 on the sweep line; the finals made before that used the older alignment, 7 of the 8 sessions' `TTL` / `blocks` / `logAlign` differ): the 2026‑10‑22/23 validation rerun of all 8 sessions moved the block starts by −1.074 s (`260811_EEG_NWU_MS`), −0.036 s (GP), +0.016 s (IS, JH), +0.024 s (MM), +0.084 s (AL), −0.004 s (HK), 0.000 s (CA) relative to the previous finals; the breaths themselves are unaffected, only the in‑block membership of 2 MS breaths changed. `260811_EEG_NWU_MS` has the weakest alignment (|r| 0.47, drift −390 ppm, REVIEW flag; a residual‑lag test over 25 windows gives a median +0.27 s with the new map against −0.80 s with the old one, but the residual still trends from −1.3 to +1.4 s), so its block boundaries stay uncertain by about ±1.4 s — review them before using the MS block windows. Decision 2026‑10‑23: the shifts from the shared alignment are accepted for the rerun (not reverted to the older alignment). |
| `breathingTasks_separate` | one row **per condition recording**, `Task` = a condition name — the one vocabulary is `config/sepConditionInfo.m`: `audioBook`/`audiobook`/`distractedBreathing`, `focusedBreathing`, `sleep`, `sleepWithOdor`, `restingBaseline`, `focusedBreathing_button` (+ `…_button1`/`…_button2`, `…_button_mouth`), and `<condition>_run<N>` | a session = the Subject ID's eligible condition rows (`dataType` = `ephys` only). No `makeOutDat`: each condition's `raw\raw_<condition>\` file (folder rules in `sepConditionInfo`) is loaded directly, run through the shared core + segmentation + ECG **separately**, then concatenated in recording order (`concatSections` → `outDat.sections`, `TTL` = `[start_1 end_1 start_2 end_2 …]`). Per‑breath `task` = section label, `condition` = section index; no ratings / `baseEmotion`. Sheet writes go through `config/writeSheetSep` (every condition row), not `writeParams`/`writePreProcX`. **Per‑condition respiration channel** (2026‑10‑12, `260921_OBE_NWU_BW_2`: binaps `rspIDX 1` for three recordings, spirometer `3` for the mouth recording): each condition row may carry its own `rspIDX`/`rspFlip`; `applyParams` returns them aligned with `P.conditions` as `P.condRspIDX`/`P.condRspFlip` (`P.rspIDX`/`rspFlip` stay the first row's) and the main segments / ECG‑processes each section with its own (`tasks/breathingSeparate/sepSectionRsp`); `writeSheetSep` writes each row's own value back. Only when the rows differ does `concatSections` append a row `rspSelected` (each section's chosen channel × its flip) and set `outDat.rspIDX` to it with `rspFlip = 1` (the canonical idiom of §7 keeps working), adding `rspIDX`/`rspFlip` columns to `outDat.sections`; sessions with one channel are unchanged. **More per‑condition settings (2026‑10‑14, `tasks_261014`)**, all aligned with `P.conditions` and applied per recording by `tasks/breathingSeparate/sepSectionP` (absent = off; a session without them runs exactly as before): `P.condBeatSpec` — every row's own `beatSpec` (always set; the ECG viability probes and `processECG` use the section's own spec, `writeSheetSep` writes each row's back; `outDat.sections.beatSpec` only when they differ); and, set only in an explicit `applyParams` `switch sessID` case: `P.condTrimSec` (`[start end)` s kept of that raw recording, applied by `assembleRaw_breathingTasks_separate` before any processing — `260625_OBE_NWU_HM_2` sleep `[0 916]`, the end‑of‑session noise starts at 921.09 s), `P.condBlinkRemoval` (false = that recording's EEG stage skips blink removal — `260831_OBE_NWU_CS_2` sleep; an explicit vector wins over the condition default below, `NaN` entries fall back to it), `P.condRespSkip` (true = respiration not recoverable: no segmentation, no breaths from that recording; none configured), `P.condMinIBI` (s, that recording's `P.minIBI` for `processECG`, recorded in `outDat.sections.minIBI` — `260831_OBE_NWU_CS_2` sleep 0.5: its double detections had pushed `processECG`'s IBI acceptance window to the 0.6‑s default, leaving 19 % of the sleep IBIs out of `RRint`). **No blink removal in sleep recordings** (reviewer 2026‑10‑20, `guessReview_261015` G2b): `sepConditionInfo` gives every condition a default `.blinkRemoval` — `false` for `sleep` / `sleepWithOdor` (and their `_run<N>` takes), `true` otherwise — and `sepSectionP` applies it unless `P.condBlinkRemoval` says otherwise (both modes; sessions without a sleep section run exactly as before). **Zero `blinkIndicator` for every skip** (G2c): a section whose EEG stage removed no blinks — switched off (condition default / `P.condBlinkRemoval`), ≤ 10 good channels after the detector, the blink‑stage gate, both blink channels bad — gets an all‑zero `blinkIndicator` row from `concatSections` whether or not another section has one, instead of failing the label check (G2d, 2026‑10‑22: a sleep‑only session gets the zero row in every section; sleep‑only finals made before that date have none); any other label difference still errors. The reason is recorded per section (`outDat.sections.blinkSkipReason`, §6.1). Each recording gets the shared breath merge (`applyBreathMerge`, §5) before `concatSections` joins the per‑breath arrays, and `sepSectionP` sets `P.seedTag` = the condition (part of the spike‑ICA seed key, §5). **Echem mode**: `ZLP_SEP_ECHEM=1` (+ `ZLP_MAIN_ONLY`, required) runs the main on a session's `dataType = ephys_echem` condition rows (`applyParams('breathingTasks_separate_echem', …)`, `P.sepEchem`) into `<id>_breathingTasks_echem_separatepreproc.mat` (`outDat.sepEchem`, figure folder `<fig>\<id>\breathingTasks_echem_separate\`, CSV `<id>_breathingTasks_echem_separate_processedBreathing.csv`; `writeSheetSep` then writes the `ephys_echem` rows) — for `260921_OBE_NWU_BW_2` the `focusedBreathing_button2` recording (made during echem; Task name kept because its raw folder is `raw_focusedBreathing_button2`). The sheet also lists `RY_1` / `RX_2` / `RC_2` `sleep` and `KA_2` `restingBaseline` as `ephys_echem` condition rows: not reviewed for this mode. |
| `vipassana` | `vipassana` | single continuous **BrainVision Recorder (actiCHamp)** session per participant (added 2026‑09‑26 with three `EEG_NWU` sessions AS/CC/DD): raw lives under `<id>\brainProductsDat\` (not Neuralynx/Atlas), and `Cz` — the recording reference — is reinserted as an all‑zero channel. Hand‑press event markers exist but are shaky/incomplete; treated only as hints. Loads raw directly (no `makeOutDat`); the fixed period sequence (`audiobook1`, `anapana`, `questionnaire1`, `vipassana`, `questionnaire2`, `metta`, `questionnaire3`, `audiobook2`, optional `pre`/`post`) is **inferred from an EEG artifact index by a duration‑constrained dynamic programme** (`inferBlocks_vipassana`), stored in `outDat.blocks` + `blockInference` (`TTL` = block starts). Respiration is optional per session: a viability probe (`probeRespViability_vipassana`) gates breath segmentation — when it fails (e.g. CC, no usable respiration channel), `respSkipped=2` and `outDat.respProbe` records why, no `bmObj`. ECG via `runECGStage`. **Line‑noise notch at ingestion** (2026‑09‑27): `assembleRaw_vipassana` notches the 32 scalp rows (ECG/rsp/event untouched; the Cz zero row stays zero) at 60/120/180 Hz (`designfilt` `bandstopiir`, order 2, f±1 Hz, `filtfilt`) and records `outDat.notchHz` / `notchNote` — the actiCHamp dry electrodes carry heavy 60‑Hz pickup and, un‑notched, the shared bad‑channel detector (`removeNoiseChansVolt`, amplitude rules on unfiltered data) flagged 22 of DD's 32 channels and nearly all of its first audiobook in `badTS` for line noise rather than bad contact; the shared core keeps no notch by design (§5), so this task notches before it. The block‑inference evidence (`artifactIndex`) is computed by the loader on the **un‑notched** rows before the notch, so the segmentation is unchanged (on notched evidence DD's audiobook1/anapana boundaries moved by 3.6–5.4 min). **No blink removal** (eyes closed throughout): `applyParams` sets `P.blinkRemoval = false` (§3), so `preprocess_eeg` skips `blinkRemoveWrapper` (`blinkRemoval = 0`, no `blinkIndicator` row). The **2026‑09‑27 re‑run** with both changes gave: `badChans` AS `O1 Oz O2 Cz`, CC `FC5 TP9 P7 O1 Oz O2 TP10 Cz`, DD `Cz` only (was 22 channels, so DD has a `dataLap` again); still‑block `badTS` 2.6 / 6.3 / 0.2 % (was 3.0 / 19.1 / 10.4 %); blocks, breaths, beats and RSA check unchanged; the pre‑notch finals are in `E:\reprocBackup_260927_preNotch\vipassana\` on the lab desktop (moved off the study folder 2026‑10‑21) (numbers: `guessSessions.md`). **Everything above is protocol `v1`** (`P.vipOpts.protocol`, set by an explicit `applyParams` case for AS/CC/DD). **Protocol `v2`** (2026‑10‑20, every later session — BM/RM 260927, NE 261016, JO/KW/L/VL 261018; `Type` `EEG_vipassana`): blocks `audiobook1` (5 min) · `paced1` (8‑min paced‑breathing sweep 15→6 /min, depth 1/1.2, SniffLogic `sweep1`) · `audiobook2` (5) · `anapana` (15) · `vipassana` (15) · `metta` (7.5) · `paced2` (8, `sweep2`; not run in BM/RM/NE), **marked, not inferred**: the PsychoPy script shows a white square under the photodiode for every block (`parsePhotodiode_vipassana` on the unfiltered `event` row, before the shared 0.03‑Hz high‑pass), and the session's SniffLogic log in `<id>\behavioralDat\` (when present; BM/RM/NE) names the blocks (`parseLog_vipassana`) and is aligned to the recording through the respiration trace both systems record (`alignLog_vipassana`: the BrainVision `Resp` input is an inverted analog copy of the SniffLogic sensor — window r 0.99–0.999, ~12 ppm clock drift, < 4 ms residual; the photodiode edges trail the log events by ~37 ms). `blocksFromMarks_vipassana` matches them (boundaries = photodiode edges, labels = the log's; photodiode‑only sessions take the protocol order, 6 or 7 runs, durations checked) and tiles the recording with the gaps `pre`, `instructPaced1`, `instructAudiobook2`, `break`, `questionnaire1`, `questionnaire2`, `instructPaced2`, `post`. v2 ingestion: **no EEG notch**; the **ECG row is notched** at 60/120/180 Hz (`P.vipOpts.ecgNotchHz`, `outDat.ecgNotchHz` / `ecgNotchNote`: the ripple the shared 5–40 Hz band‑pass leaves locked the detected beat times to the line cycle — IBI phase concentration at 1/60 s 0.17–0.58 in 6 of 7 sessions vs ≤ 0.03 notched, BM RMSSD 82 vs 20 ms); `rsp1` low‑passed (4th‑order Butterworth 5 Hz, `filtfilt`; 60‑Hz pickup); with a log, the aligned log pressure is appended as `rspSniffLogic` (rsp index 2, Pa, inhale‑positive — select it with sheet `rspIDX 2`/`rspFlip 1` if a session's BrainVision trace is unusable — chosen 2026‑10‑21 for JO / L / VL, whose BrainVision `Resp` carries transients and, in VL, a ~1.5‑Hz ripple the log lacks: fewer split breaths on the log; BM / RM / NE / KW segment alike on both and keep `rsp1`) and the sweep target as `targTrace` (after the core); the main asserts the sheet `rspFlip` against the log's polarity. The respiration viability gate drops its autocorrelation rule for v2 (`P.vipOpts.respProbe.acMin = 0`): slow, irregular meditation breathing with long pauses scores 0.15–0.45 (VL 0.30) although every block shows clean breaths; the band‑fraction and spectral‑peak rules (which rejected CC) stay. The v2 EEG has a flat broadband noise floor to the 140‑Hz amplifier cutoff (as recorded ~1.6–6 µV²/Hz at 70–110 Hz; after the average reference ~0.7–2, 15–35× v1; it does not follow electrode impedance, and every v2 `.vmrk` — none of v1's — logs `Active Shielding: On`; probes 2026‑10‑21 in `guessSessions.md`) that makes the shared detector's lab‑default `'fixed'` mode flag 27–30 of 30 channels even after the average reference. **These seven sessions are therefore cleaned in `'band'` mode** (an explicit `applyParams` case setting `P.eegClean.mode = 'band'`; user, 2026‑10‑21: recover as much as possible — 4–9 bad channels, badTS ≤ 7 %); `'fixed'` stays the default for every other session and for future recordings (the recording configuration is being changed). Above ~40 Hz these recordings are instrument noise; beta carries a 3–10× higher floor than v1. Numbers in `guessSessions.md`. VL: `P.ecgEctopic` on (§3). LoadData v2 montage: BrainVision `photoDiode`/`Resp`/`ECG` = Ch32/33/34 → rows `event`/`rsp1`/`ECG1`; a recording paused and resumed (`New Segment`) keeps its last segment when the earlier ones are < 120 s (VL: 19‑s setup segment dropped, `curDat.segments`). QC: `blocks_marked.jpg`, `sniffLogicAlign.jpg`. **Average reference, both protocols** (2026‑10‑21; user: the EEG should be average‑referenced before cleaning, with Cz — the recording reference — recovered): after the artifact index and the v1 notch, `assembleRaw_vipassana` re‑references the 32 scalp rows to a robust common average (`shared/robustAvgRef`, `P.vipOpts.avgRef` / optional `avgRefOpts`; after PREP's robust reference): (1) a row whose peak‑to‑peak in the recording reference is < 1 µV in a 2‑s window (dead / railed input) in > 1 % of the non‑gap windows leaves the mean, and its flat windows are left as recorded so the shared detector's flat rule still flags them; (2) rows are de‑meaned and 1‑Hz high‑passed before any cross‑row statistic, provisional reference = their per‑sample median; (3) a row leaves the mean when its robust amplitude against that median has robust z > 5 across rows over the whole recording (PREP's deviation criterion) or z > 20 in > 1 % of its 2‑s windows (extreme events only: rails, an electrode failing partway; a windowed z > 5 rule excluded 8–11 rows for eyes‑closed alpha and eye movements); (4) the mean of the remaining rows (unfiltered) is subtracted from every row outside its flat windows. Cz comes back as a real channel (Cz = −mean of the reference set) and noise common to every row as recorded cancels; `outDat.avgRef`, `outDat.dataRef`, `czRezeroed = false`. Current finals = the **2026‑10‑21 re‑run** of all 10 sessions with it (superseded finals in `E:\reprocBackup_261021\vipassana\` on the lab desktop). |
| `ADmeditation` | `ADmeditation` (rows of its **own sheet**, `dataTracking_AD_meditation.xlsx`, §3) | Adam's repeated ~60‑min seated meditation recordings (added 2026‑10‑08; `Type` `EEG_meditation`), one continuous Atlas recording per session on the EEG_breathing rig (`Zelano_EEGbreathing.cfg`: EEG CSC33–64, ECG CSC25–27, rsp CSC31/32, event CSC269). **Study‑folder layout, not per‑session folders** (§2). No behavioral file, no `makeOutDat`. Every recording is **trimmed** — first 3 min and last 1 min dropped before any processing (`P.adMedOpts`; `outDat.trim` maps final samples back to the raw file). The one marker is a **button pressed at a "good" meditative state**: on the event channel a ~5‑s pulse, AC‑coupled (a ~750 µV step at the press, the opposite step at the release ~5 s later) under heavy 60‑Hz pickup. In the extracted raw the press step is NEGATIVE: CSC269 is recorded with `InputInverted=True`, which the lab's `ReadNCS` does not apply. `detectButtonPresses_ADmeditation` low‑passes (10 Hz), detects both steps on the whole untrimmed trace, takes the press polarity from the data (the first step of each press→release pair) and times each step at its half‑height crossing; presses → `outDat.buttonPresses` (table, incl. ones in the trimmed stretches, `inAnalysisWindow=false`) + `outDat.TTL` (press onsets in the analysis window) + per‑breath `pressInBreath / secSincePress / secToPress`. One parameter set for all sessions (measured 2026‑10‑08 on all 14): `rspIDX 1, rspFlip +1` (CSC31 inhale up, the lab's polarity on this rig, user‑confirmed 2026‑10‑08; an inhale‑locked RR window test pointed to −1 but is timing‑sensitive — `processECG` stamps each RR interval at its first beat — and is not a polarity test here), `beatSpec 3,0,lt,-3.5` (ECG3 = CSC27 has a negative R in every session; ECG1 flips polarity between sessions), eyes closed → `P.blinkRemoval = false`, no macros. ECG via `runECGStage`; `checkRspPolarityRSA` + `QC_ADmeditation.jpg` per session. |
| `respiratorySweep` | `respiratorySweep` | **new experiment** (added 2026‑10‑08 with `261006_EEG_NWU_RC` / `_IS`, then `261007_EEG_NWU_AL`, `261014_EEG_NWU_ZL`; more participants to come): one continuous EEG_breathing Atlas recording — baseline ratings, a 6‑min audiobook (natural breathing), then **18 paced blocks of 150 s** (3 passes at depth 1.00 / 0.85 / 1.15 × the participant's calibrated breath size through the paces 15, 13, 10, 8, 6, 4 breaths/min, tracing a target trace on screen), post‑sweep ratings, and in the first sessions **2 × 6‑min focused breathing + 2 × 6‑min audiobook run off‑script with a stopwatch** (the lab plans to log those in SniffLogic later); the EmotionalMovieTask follows as a second recording. The Atlas recording has **no event marks**: the session's `LoadData_<id>_claude.m` calls `buildSweepTTL`, which aligns each SniffLogic log (`<id>\behavioralData\<id>_sniffLogicLog_*.csv`, events + respiration on the log clock) to the raw respiration (`shared/alignLogToRaw`: lag, drift, polarity), maps the log events onto raw samples, adds the stopwatch blocks hard‑coded from the session notes or from times the user gives (start = Atlas recording time, exactly 6 min), cross‑checks other note times against the logs (a log may run on after the Atlas recording stopped — only its events must fall inside it), and stores the **event table in the raw file** (`curDat.TTL` + `TTLinfo` + `logTrace`) — so there is no `makeOutDat`. The main converts it to `outDat.blocks` (500 Hz; `TTL` = block starts), adds a `targTrace` channel (the traced target, 0 outside sweep blocks), keeps **all** breaths with block columns (`blockType`, `cpm`, `depth`, `sweepNum`, `inBlock`) + the pacedBreathing regularity measures. **Breath merge** (rule of 2026‑10‑15, user; full text in §5): applied by the sweep main from the first sessions on, a shared stage of every breath‑type task since 2026‑10‑22; the first RC / IS finals predate it (no `outDat.breathMerge`). The pipeline also stores the PsychoPy ratings (`ratings`, `baseEmotion`, `postSweepEmotion`); ECG via `runECGStage`. |
| `detectNoOdor` | `detectNoOdor` | **cued sniffs, never an odor** (added 2026‑10‑15 with `261008_INR_NWU_SS_1`; task script `OBE_task_backup\tasks\odor_detection\src\Main_detectiontask_f.m`, which opens the air line only): per trial a 3‑2‑1 countdown, a SNIFF cue (0.5‑s DAQ pulse), then a Yes/No "odor?" answer on the button box (0.3‑s pulse at the key press). Event channel (AC‑coupled, low‑going): start code 4 × 0.3 s → trials → end code 2 × 0.3 s; anything before the start code is preamble. `detectNoOdor_makeOutDat` parses it strictly on median/rail levels (`parse_detectNoOdor_events`) and joins the result file (`loadBeh_detectNoOdor`, under `labPaths().behOdorDetection`: exactly one `.mat`, which must carry `note = 'no odor'`, + the run's cuelist). **`response` = the key (1 left / 2 right); `response_str` = the answer under the cuelist's counterbalanced screen side (`trialtype` 1: Yes left, 2: Yes right) — authoritative**; `odor` = the cuelist's planned code, never delivered. Per‑sniff task on the cue/thresh template (`moreThan1 = 0`, sheet params `respThresh/cuedBackBuff/adjWin`); `countInhales_detectNoOdor` counts the inhale peaks between the cue and the answer as data (`behDat.nInhales`, `outDat.inhaleCount`, options `P.inhaleOpts`, default `promFrac` 0.25 — trials with a shoulder or a shallow notch flip with it). QC: `ttlParse_detectNoOdor.png`, `trials_detectNoOdor.png`, `allSniffs.jpg`, `sniffsTrial<n>.jpg`. |
| `airPuff` | `airPuff` | **breath holds with air puffed up the nose through a tube** (added 2026‑10‑15 with `261008_INR_NWU_SS_1`, Atlas `_0017`). One 0.26‑s DAQ pulse per puff on the event channel (AC‑coupled, rail‑clipped, low‑going). Protocol (user): a lead marker of 3 pulses, then the **cued** run (each puff announced by a "Puff" auditory cue), a 3‑pulse separator 0.52 s apart, then the **blind** run (no cue; the participant cannot know the timing). No behavioral file, no `makeOutDat`. `assembleRaw_airPuff` loads `raw_airPuff.mat` and parses the raw‑rate event channel before the shared high‑pass (`parsePuffEvents_airPuff`): median/rail threshold, onset = half‑height crossing, 0.52‑s marker trains vs single puffs, puffs < 5 s apart = one breath hold. The expected structure in `P.puffOpts.parse` is strict. SS_1 has ONE lead pulse, so its `applyParams` case sets `nLead 1`, `expectedHolds [5 2]` and `puffsPerHold 4`. **Holds come from the respiration** (`detectHolds_airPuff`): quiet = the 0.5‑s moving SD of the < 2 Hz trace is below 0.10 × the median breath amplitude; a hold is the quiet stretch(es) containing its puffs. In SS_1 they are end‑exhale apnoeas of 7.9–13.9 s with all 28 puffs inside. `segmentBreaths_zlp` over the whole recording plus the shared breath merge (§5, before the holds are detected) gives the breath context (`outDat.breaths`, per‑breath HRV); ECG via `runECGStage`. `TTL` = puff onsets; `behDat` has one row per puff (§6.4); `outDat.holds` and `outDat.pulses` (§6.1). QC figures: `airPuff_overview.jpg`, `airPuff_holds.jpg`, `airPuff_locked.jpg`. |

The name mappings live in `config/applyParams.m` (`taskKey` caller → canon, `canonTask` sheet → canon,
`taskCallerKey` canon → `P.task`) and are mirrored in `pipelines/preprocessAll.m` for every task except
`breathingTasks_separate`, which `preprocessAll` does not handle yet (it also reports but does not run
`EmotionalMovieTask` / `alternating6Blocks` — run those mains directly), and `ADmeditation`, whose sessions
are not in the master sheet (run `pipelines/ADmeditationPreProc_main.m` directly).

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
  │                                      respiratorySweep / airPuff skip this step]
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
  marker as a table, with each marker's own `date`), `curDat.header` (the parsed `.vhdr`), and `curDat.refChan`
  (`'Cz'`); v2 loaders (2026‑10‑20) add `curDat.segments` (acquisition segments, which was kept),
  `curDat.markersFile` (the markers in file samples) and `curDat.behavioralFiles`. v2 participant folders are
  `brainProductsDat\`, `behavioralDat\` (every other file of the session: SniffLogic log, PsychoPy
  `mindfulBreathing` csv/log/psydat, `audioResp_recording`, `sweep1_cycles`/`framelog`, `template_breath`),
  `raw\`, `preProc\`.
- **Windows / case‑insensitive quirk (intentional, don't "fix").** The intermediate (`…PreProc.mat`) and the
  final (`…preproc.mat`) differ only in case, so they are the **same file** — `_main` overwrites the
  intermediate in place and a fully processed session has one file. Take the exact per‑task strings from the
  `save(...)` line of each `*PreProc_main.m` (legacy names exist, e.g. thresh `<id>_PEA_threshold_preproc.mat`).
- O15 loads `<id>\raw\raw_O15\raw_O15.mat` directly.
- **ADmeditation is the exception to the per‑session layout.** Its study folder
  `<labCommon>\AllStudyData\AD_repeatRecordings\` (`labPaths().rootADmed`) holds the Atlas date‑stamp
  folders (`yyyy-mm-dd_hh-mm-ss\`) side by side, ONE loader `LoadData_ADmeditation_claude.m` (repo copy in
  `tasks/ADmeditation/`) that extracts every recording not yet imported and adds its sheet row,
  `raw\<id>_raw.mat` and `preProc\<id>_ADmeditationpreproc.mat`. Session ID = `<yymmdd>_ADmed_<hhmm>` from
  the folder stamp. Recordings with no acquisition segment ≥ 60 s are listed in the sheet as empty and not
  extracted.
- **Top‑level variable** is `outDat`, except breathingTask finals — current ones included — which store
  `chanDat` (written by `parSave`; some older ones `out`). Load robustly:
  ```matlab
  s = load(finalPath); fn = fieldnames(s); outDat = s.(fn{1});
  ```
- A file is **fully processed** iff `outDat.moreThan1` exists (and, since July 2026, `behDat.manOnset`;
  breathing additionally `bmObj` / `baseEmotion`; the movie / alt6 / paced / sep mains check `moreThan1` +
  `bmFeatures` via `isSessionDone`, the airPuff main `moreThan1` + `holds`).
- **Id filters and reruns.** Every `*PreProc_main` takes `ZLP_MAIN_ONLY=<comma-separated ids>` (case-insensitive; blank = all) and every `*_makeOutDat` takes `ZLP_MAKEOUTDAT_ONLY`; an id that matches nothing silently does nothing, and the respiration carry needs exactly one id per run (§8). The mains skip a session whose final exists, so a rerun first moves the previous final to `<root>\<id>\preProc\superseded_<yymmdd>\` (the 2026-10-22 rerun's are in `superseded_261022\`, a failed attempt's partial file in `failed_<time>_<file>`).
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
(**ADmeditation is tracked in its own sheet**, `Admin\Data\dataTracking_AD_meditation.xlsx`
= `labPaths().adMedXlsx`, env override `ZLP_ADMED_XLSX`, same layout — title row 1, header row 2, one row per
recording from row 3, keyed by `Subject ID`; no local fallback. `applyParams` / `writeParams` / `setPreProcX`
switch to it for that task only; it carries only the parameter columns the task uses (`datPre rspIDX rspFlip
hasEEG hasMacros spikeClean beatSpec paramSource`) plus recording / summary columns written by the loader and
by `config/writeSheetADmed.m`. These sessions are deliberately NOT in `dataTracking.xlsx`.)

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
| `ttlProtocol` | O15 | free‑sniff protocol (→ `P.ttl.protocol`, §1): `oldTTL` (recorded ≤ 2026‑07‑02) / `heldButton` (recorded ≥ 2026‑07‑09). **Required** on every O15 row (blank / other values → `applyParams` error; `pressPulse` = old name, read as `oldTTL`). Last column of the sheet (added 2026‑10‑20); filled on all 47 rows whose `Task` contains `O15` — incl. the unmatched `O15_noTTLs_skip` / `O15_corrupted` / `O15_practice`, by date, though no pipeline reads them |
| `isNewStd` | breathing/cue/thresh | selects the "new standard" ingestion branch |
| `paramSource` | target rows | `curated` (trusted, runs unattended) / `guess` (unverified → interactive verification before any save) / blank (no parameters yet) |
| `Data Preprocessed` | all | set to `X` by `writePreProcX` when a final is saved; must mirror the disk (see above) |

`P` (Mode B) always carries `task, type ('Dupi'|'OBE'|'EEG'), fs_target=500, rspIDX, rspFlip, hasEEG,
spikeClean, spikeThresh, spikeWin, macroRemove, paramSource, hasMacros` + task extras (breath‑type tasks:
`beatSpec, getBeats`; cue/thresh/O15/detectNoOdor/cueTask3: `respThresh, cuedBackBuff, adjWin`; O15 also `pd`, `ttl`
(`expectedTrialCount, removeTrialMarksIdx, note, protocol` — the last from `ttlProtocol` — + optional `confirmRule`);
detectNoOdor also `inhaleOpts`; cueTask3 also `sniffTrain`, `noOdorTrials`, `noOdorReason`;
airPuff (breath‑type `beatSpec, getBeats`) also `puffOpts` (`parse` / `hold` / `measure`, §1);
EmotionalMovieTask `pd`; pacedBreathing `pacedOpts`; breathingTasks_separate `conditions`, `condRspIDX`,
`condRspFlip`, `condBeatSpec` (+ optional `condTrimSec` / `condBlinkRemoval` / `condRespSkip` / `condMinIBI`, echem mode
`sepEchem`; §1); vipassana `vipOpts` (`protocol` 'v1'/'v2', `notchHz`, `ecgNotchHz`, `rspLowpassHz`, `avgRef` (+ optional `avgRefOpts`;
an applyParams case that replaces `P.vipOpts` without `avgRef` switches the average reference off), v2 `photodiode` /
`logAlign` option structs, v2 `respProbe`), `blinkRemoval`). The mains add `allowGuessRun` and `figDir` (the session's task figure subfolder).

Task‑level `P` fields (set in `applyParams`, **not** sheet columns, not written by `writeParams`):
`blinkRemoval` — optional; absent or `true` = `preprocess_eeg` runs blink removal (every task's default);
`false` = the task has no blinks to remove, so blink removal is skipped (`vipassana` and `ADmeditation`, eyes
closed throughout; breathingTasks_separate sets it per recording in `sepSectionP` — `sleep` / `sleepWithOdor` by
default, `P.condBlinkRemoval` — §1, §5). It is also `false` for `breathingTask` `251027_Dupi_NMH_DL_1` (G2f, 2026‑10‑22, explicit `switch selStr` case: no component passes the frontal rule there — best r 0.5977 < 0.60 — and the unseeded ICA used to flip between removing none and removing one).
`blinkRemovalReason` — optional text with such a case; stored as `outDat.blinkRemovalNote` when `preprocess_eeg` skips blink removal because of `P.blinkRemoval = false` (vipassana / ADmeditation set none, so their finals have no such field).
`seedTag` — breathingTasks_separate only, set by `sepSectionP` (= the condition): part of the macro spike ICA's seed key (§5).
`carryFrom` — optional, any task: the previous final's full path, the same as env `ZLP_CARRY_FROM` and winning over it (respiration carry, §8). `mergeExhaleFrac` / `mergeOpts` — optional, breath‑type tasks: the breath merge's fraction (default 0.20; respiratorySweep keeps its own copy `P.sweepOpts.mergeExhaleFrac`, which `applyBreathMerge` also honours) and the options struct of `mergeIncompleteExhales` (§5).
`dropTrials` / `dropTrialsReason` — cueTask only (default `[]` / `''`); trial numbers (`behDat.n`) whose sniff
rows `cueTaskPreProc_main` removes via `tasks/cue/dropTrials_cueTask` and records in `outDat.droppedTrials`
(§6.4). Set per session in an explicit `switch selStr` case in `applyParams` (currently `260917_OBE_NWU_RC_2`,
trial 23, tasks_261014 task 5); errors if a listed trial has no row in `behDat`.
`ecgExcludeSec` / `ecgExcludeNote` — breathingTask only (absent = off); `[N×2]` seconds of unreadable ECG on the
session's own timeline + the criterion text, set per session in an explicit `switch selStr` case (currently
`251110_Dupi_NMH_PC_2`, tasks_261014 task 7); honoured by `processECG` / `flagBadBreaths`, recorded in
`outDat.ecgExclude` (§5, §6.6).
`ecgEctopic` — any task through `processECG` (absent / empty = off); a struct (`struct()` = the defaults `premFrac 0.2,
winBeats 11, ectSumMin 1.5, extraSumMax 1.25`) that drops both RR intervals touching each premature beat (interval <
(1 − premFrac) × the moving median of winBeats intervals) and interpolates `RRint` across them; `heartBeats` keeps every
beat. Set per session in an explicit `switch selStr` case (currently `261018_EEG_NWU_VL`, 2026‑10‑21); recorded in
`outDat.ecgEctopic` (§6.6).
`sniffTrain` — cueTask3 only (absent / empty = off); a struct (`struct()` = the defaults `peakPreSec 0.2,
nextGuardSec 0.1, lastPostSec 1.2, riseStartFrac 0.1, minRiseFrac 0.2`, documented in `detectSniffTrain` inside
`shared/detect_sniffs_from_TTLs`) that switches `detect_sniffs_from_TTLs` and `refine_onsets_with_phase` to their
train mode (§1); recorded in `outDat.sniffTrain`.
`noOdorTrials` / `noOdorReason` — cueTask3 only (default `[]` / `''`); trials (`behDat.n`, counted across runs) in
which no odor reached the participant although the result file lists one: their rows stay, flagged
`behDat.noOdorDelivered`, recorded in `outDat.noOdorTrials` (table `trial, reason`). Set per session in an explicit
`switch selStr` case (currently `261008_INR_NWU_SS_1`, trial 2).
`ttl.confirmRule` / `pd.zthresh` — O15 `oldTTL` parse only (`detect_ttls_O15`; defaults `'window'` / `-2`):
`'window'` = the confirm pair is exactly two sniff marks < 1 s apart between consecutive trial marks, `'pairs'` =
every two consecutive sniff marks < 1 s apart wherever they are (the lab's rule until late June 2026). Set per
session in an explicit `switch selStr` case (currently `250929_Dupi_NMH_GH_2` `'pairs'` and
`260316_Dupi_NMH_PD_1` `zthresh -0.23`, G3d; §1).

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
   `assembleRaw_<task>` instead (currently only `vipassana`, §1) — the shared core stays notch‑free. The core
   does not re‑reference the EEG either; `vipassana` average‑references at ingestion (`shared/robustAvgRef`, §1).
2. **`preprocess_eeg(outDat, EEGLOC, P)`** *(only if `P.hasEEG`)* — validates the **first 32 channels**
   against `config/eegLocs_standard_coords.csv`, attaches coords, detects + interpolates noisy channels
   (`removeNoiseChansVolt`), removes blinks on the good channels via ICA (`blinkRemoveWrapper`; blink‑IC
   auto‑selection with a manual fallback) when > 10 survive, and computes a Perrin surface Laplacian (`dataLap`; on the unit‑sphere‑projected electrodes since 2026‑10‑22, §6.3).
   **Bad‑channel / bad‑time detector** (`removeNoiseChansVolt`; 2‑s trials; amplitude rules: 10‑ms (6‑sample)
   p2p > 50 µV "noisy" or < 5 µV "flat" in ≥ 3 of a sliding 6‑trial block → interpolate that trial's flagged
   channels when < 16; 80‑ms (41‑sample) p2p > 100 µV in > 50 % of trials → bad channel; trials with > 24 / > 8
   channels over 100 µV and recording gaps (every channel flat) → `badTS`; a channel is bad when flagged in ≥ 60 %
   of the judged trials or by the block rule in > 50 %). Mode `P.eegClean.mode` (optional, not a sheet column):
   **`'fixed'` (default since 2026‑10‑14, tasks_261014 task 10)** — purged and gap trials go to `badTS` only, are
   skipped by the block rule (each block = 6 consecutive *judged* trials, reaching past purges; with no purge the
   legacy blocks) and excluded from every channel denominator; nothing is repaired inside gap / pass‑1‑purged trials
   (so it removes no‑evidence flags; because the denominators and blocks are now the judged trials it can, in
   principle, flag a channel bad in most of the judged trials that legacy missed, a single all‑flat trial is now
   `badTS`, and a judged trial next to purges that collects ≥ 16 flags is no longer rebuilt by interpolation, so the
   > 8‑channel purge can take it — 19‑session validation 2026‑10‑15: no channel added vs legacy, `badTS` up by
   0.25–0.6 points in 2 sessions; the 35‑final validation rerun of 2026‑10‑22/23 added or removed a bad channel in 3 sessions — +F4 `250929_Dupi_NMH_GH_2`, +F8 `251111_EEG_NWU_VW`, −F8 −P7 `260805_EEG_NWU_CA` alternating6Blocks — so "no channel added" does not hold in general; the `badTS` fraction moved wherever the previous final came from the legacy detector, most in thresh JH_2 .448 → .344 and cue SP_2 .306 → .281); when fewer than max(6, 10 %) of the trials are judged (rule U; 6 = one block, so a recording < 12 s is
   always unjudgeable) every channel is returned bad, the legacy outcome for such recordings
   (`EEGCleaningInfo.unjudgeable`); EEG with NaN/Inf errors (`removeNoiseChansVolt:nonFinite`); and the blink stage
   follows the same rule — `blinkRemoveWrapper`'s own channel tests (≥ 700 µV range in ≥ 15 % of 2‑s epochs; ≥ 30 s
   flat) ignore `badTS` epochs, and when they leave ≤ 10 good channels no ICA is run and the session gets the ≤ 10
   outputs (`blinkRemoval = 0`, `dataLap = []`, `EEGCleaningInfo.blinkGate`; 2026‑10‑15, also in `'band'`);
   **`'legacy'`** — the pre‑2026‑10‑14 rules verbatim, blink stage included (`removeNoiseChansVolt_legacy`): purges were written into
   every channel's record, so a recording with ≥ 60 % purged trials lost all 30 channels (DB_3 O15, KS_2/KS_3,
   BK/IN, …), and purged trials read as "flat"; **`'band'`** — `'fixed'` with the amplitude statistics computed on
   a 1–40 Hz copy (flat / gap tests broadband; the data are not filtered), i.e. "bad in the analysis band" rather
   than "carries EMG / line noise" — a policy option, not the default (user, 2026‑10‑20: too lenient — `'fixed'` only;
   2026‑10‑21: used for the seven vipassana v2 sessions recorded with Active Shielding, by explicit `applyParams` case);
   each trial is judged on its own band content
   (a neighbouring trial over a threshold is bridged out of the filter input, so a burst's filter ringing is not
   counted next to it). Finals made before the change used the legacy rules (they have no `EEGCleaningInfo`); the
   decision is recorded in `outDat.EEGCleaningInfo` (§6.3). **Deploy together:** `shared/removeNoiseChansVolt.m`,
   `shared/removeNoiseChansVolt_legacy.m`, `shared/preprocess_eeg.m`, `shared/blinkRemoveWrapper.m`,
   `tasks/breathingSeparate/concatSections.m` (`preprocess_eeg` errors on a stale detector or blink wrapper; the
   detector warns when called without its `info` output).
   Blink‑IC rule since 2026‑10‑12 (`selectMode 'frontal'`): a candidate's average‑referenced map must peak at
   Fp1/Fp2 (≥ 2× its mean weight) and its time course must track mean(Fp1,Fp2) − common average below 10 Hz with
   |r| ≥ 0.6, else **no IC is removed** (blinkRemoval stays 1; sleep / eyes‑closed sections typically remove
   nothing). The ICA training window avoids `badTS`; the flat‑channel test ignores stretches where every channel
   is flat (recording gaps). The decision is stored in `outDat.blinkICA` (sep: per section) with the legacy
   pick for comparison; `P.blinkSelect = struct('selectMode','legacy')` restores the old max‑corr‑with‑Fp1 rule.
   The reviewer kept the frontal rule as the default on 2026‑10‑20 (`guessReview_261015` G2a; finals made before
   2026‑10‑12 used the legacy pick).
   Appends QC channels and EEG fields (§6.3). Blink removal is skipped — the same degrade path as when both
   blink channels are bad: data unchanged, `blinkRemoval = 0`, no `blinkIndicator` row, bad‑channel
   handling / `badTS` / `interpChan` / Laplacian as usual — when `P.blinkRemoval` is `false` (task‑level flag,
   §3: `vipassana` / `ADmeditation`, eyes closed throughout; per recording in breathingTasks_separate via
   `sepSectionP`: every `sleep` / `sleepWithOdor` section by default since 2026‑10‑20 (G2b) and
   `P.condBlinkRemoval`, §1), and for `251027_Dupi_NMH_DL_1` breathingTask (explicit `applyParams` case, G2f 2026‑10‑22; `P.blinkRemovalReason` → `outDat.blinkRemovalNote`, §3). In breathingTasks_separate a section whose blink removal did not run gets an all‑zero `blinkIndicator` row from `concatSections` whatever the reason and whether or not another section has one (G2c / G2d, §1).
3. **`preprocess_macros(outDat, P)`** *(only if `P.hasMacros`; always true for cue/thresh/O15)* — finds `macro`
   channels (any number ≥ 2), drops `macroRemove`, **bipolar re‑references adjacent pairs → `macBP1..N`**; if `P.spikeClean`,
   removes spike artifacts via targeted ICA. If there are too few spikes to train the ICA it **falls back to
   bipolar‑only with `spikeCleanVec = ones`** (July 2026 fix). Appends `macBP*` + `spikeCleanVec`.
   **Reproducible ICAs (2026-10-22; steps 2 and 3).** EEGLAB's `runica` seeds its generator from the clock by default
   (EEGLAB 2025.0.0 and 2026.0.0), so every run drew a new decomposition. `ica_blinks` now calls
   `runica(..., 'rndreset', 'no')` (the lab's EEGLAB 2025.0.0 takes 'yes'/'no' or 0/1, not 'on'/'off'): the legacy
   generator state 0, i.e. the decomposition is a function of the data alone — the **blink ICA has no per-session seed**
   (`outDat.blinkICA.rng`: `seed 0`) — and the caller's global generator is restored afterwards. The macro spike ICA
   (`ica_flag_spikes_targeted`) also seeds its own draws (non-spike snippet centres, shuffle) with
   `rng(seed,'twister')`, `seed = zlpSeed(sessID|macroSpikeICA|P.seedTag)` (`shared/zlpSeed`: 32-bit FNV-1a of the key
   text, identical on every machine and release; `P.seedTag` = the condition in breathingTasks_separate); the seed is
   recorded in `outDat.spikeCleanInfo`. The same data now give bit-identical EEG / macro rows (proven on the lab,
   R2024b, `maxNumCompThreads(4)` as the rerun driver sets it: two sessions, same and fresh process; then the validation rerun
   made four finals twice from the same R: original — cue SP_2, breathingTask JN_2, mixed‑channel sep BW_2, airPuff SS_1 —
   and every data row, `dataLap`, `blinkICA`, `bmObj`, `bmFeatures`, `behDat` and `TTL` came out `isequaln`; other thread counts,
   machines and releases untested, BLAS reductions can change the last bits). Finals made earlier were not
   reproducible (§7).

**Respiration / onsets:**

- **cue / thresh / O15:** `preprocess_respiration_wholetrace` → `R` (chosen `rsp` channel, smoothed, Hilbert
  phase, deflection metric); `detect_sniffs_from_TTLs(R,P,outDat)` finds a sniff onset near each TTL
  (windows `respThresh/cuedBackBuff/adjWin`); `refine_onsets_with_phase` snaps onsets to a respiration‑phase
  zero‑crossing and appends `adjust`, `finalOnset`, and a NaN **`manOnset`** placeholder for manual QC.
  **Train mode** (`P.sniffTrain`, cueTask3 only, §1/§3): both functions locate each cue's own inhale (trough → peak
  on `smoothR`) instead, and `finalOnset` is the steepest rise between them; without `P.sniffTrain` they run the
  legacy code unchanged.
- **breathing:** per‑breath segmentation over the whole recording → **`bmObj`** via `shared/segmentBreaths_zlp`
  (LOCKED rev13; spec `customBreathMetrics.md`; called by `process_respiration_breathing`, which derives the
  cyclicSigh span); `alignTargetBreathingTraceSimplify`
  aligns each paced block to its target trace and appends a `targTrace` channel (a block whose `shadowFile`
  is `NA` / whose CSV has no `target` column gets a zero target, like the audio/pre conditions; skipped when a respiration carry brings the previous final's `targTrace`, §8);
  `processECG` band‑passes the `ECG` channels 5–40 Hz, z‑scores (`buildECGz`), detects beats (`detectBeats`
  per `beatSpec`, min separation `fs/20`), filters inter‑beat intervals physiologically, and appends an
  interpolated **`RRint`** channel (optional per‑session `P.minIBI`, set in an `applyParams` `switch sessID` case —
  currently only `251009_OBE_NWU_CP_1`, 0.7 s (its breathingTask final of 2026‑09‑03 predates the case, so its rerun moves `heartBeats` 684 → 672 and `RRint`; the ECG rows are identical), plus `260831_OBE_NWU_CS_2` sleep 0.5 s via the sep per‑condition
  `P.condMinIBI` — prunes beats closer than that to the last kept beat and floors the
  RR series; optional per‑session `P.ecgExcludeSec` ([N×2] s, same `switch sessID` mechanism — currently only
  `251110_Dupi_NMH_PC_2`, tasks_261014 task 7 — marks stretches with **unreadable ECG** (no readable regular beat pair for ≥ 4 s, or a burst of ≥ 4 consecutive sub-physiological beat intervals; currently 4 windows, whose edges stop just short of the neighbouring readable beats so those stay in the data): `processECG` drops the
  beats inside them and leaves `RRint` NaN from the last kept RR stamp before a window to the first after it,
  never interpolated across; `batch/ecgUnreadableWindows` is the measurement tool); optional per‑session `P.ecgEctopic` (§3; currently `261018_EEG_NWU_VL`) drops both RR intervals
  touching each premature beat and interpolates `RRint` across them (normal‑to‑normal intervals only; `outDat.ecgEctopic`); `flagBadBreaths` adds
  per‑breath QC and, for the breaths overlapping those windows, sets `maxRR`/`minRR`/`RR_max_min` to NaN
  (`goodBreath` untouched).
- **Breath merge (every breath‑type task but vipassana / ADmeditation: respiratorySweep since 2026‑10‑15, all others since 2026‑10‑22 — user):** an inhale is not a new breath unless there has been an exhale since the last one. After the locked engine, `shared/applyBreathMerge` → `shared/mergeIncompleteExhales` (fraction `P.mergeExhaleFrac` / `P.sweepOpts.mergeExhaleFrac`, default 0.20; options `P.mergeOpts`; record `outDat.breathMerge`, §6.1) works in three steps. (1) **Pause blips:** an engine onset whose own window holds neither an inhale nor an exhale (each < 10 % of the local median area, beyond a ±5 %‑of‑swing noise band) joins the breath before as part of its pause. (2) **Lead bumps:** a small pulse (peak < ½ the next inhale's) with no exhale after it and ≥ 3 s near zero flow before the next inhale is the overshoot of an exhale's recovery, not the next breath's start; it also joins the breath before (`261007_EEG_NWU_AL` 2529.6 s, and the 2544.4‑s blip before the 2551‑s double inhale the user flagged — the SniffLogic target is still in its recovery at both). (3) Each remaining inhale *k* joins the breath of inhale *k*−1 when, over [onset *k*−1, onset *k*), the trace's area below zero flow is < 20 % of its area above it (signal areas of the 200‑ms‑smoothed nasal‑pressure trace, not litres; each inhale is judged on its own window, so a later complete exhale always ends the breath). Zero flow = the higher of the trace's dwell level within ±10 s (its most frequent level, when it holds ≥ 15 % of the samples with ≥ 10 % above and below — the pauses, which the 0.03‑Hz high‑pass lifts 10–20 units after a strong exhale) and the 60‑s moving mean (continuous breathing, where the dwell sits on the slow exhale instead) — not breathMetrics' `exhaleVolumes`, which integrate |trace| and give a dip that stays above zero flow an "exhale". Validated on synthetic traces and on the share of SniffLogic target cycles holding exactly one breath onset (engine → merged: AL 83.5 → 87.5 %, ZL 96.9 → 97.9 %, RC 83.2 → 85.6 %, IS 91.7 → 93.9 %). Double inhales and pulse chains at the slow paces become one breath (keep‑first onset; peak = the highest pulse, trough = the lowest); when breathing does not go through the nose (no nasal exhale) consecutive pulses can chain into long breaths; nasal pressure under‑reads slow flow, so a very slow, shallow exhale after a fast inhale can fall under the 20 % and the next inhale then merges. Per breath `nInhalePulses` (1 = not merged), `breathInhaleArea` / `breathExhaleArea` / `exhaleInhaleRatio` (whole breath) in `behDat` (§6.4); the `bm_*` columns of a merged breath describe its FIRST pulse only (its exhale‑side features describe the dip between the pulses). **Where it runs** (right after the engine, before anything numbers or filters breaths): breathingTask (inside `process_respiration_breathing`, after the cyclicSigh refractory merge — that one is block‑specific, one breath per cycle, and the generic rule then judges what is left), EmotionalMovieTask, alternating6Blocks, pacedBreathing (the blocks are inferred from the engine's breaths BEFORE the merge and the merge never changes them, §1), breathingTasks_separate (per recording, before `concatSections`), respiratorySweep, airPuff (before `detectHolds_airPuff`, so `holds.holdBreath`, `bmObj` and `breaths` use merged breaths). vipassana and ADmeditation call the engine directly and do not merge (their finals are outside the 2026‑10‑22 rerun). Effect on breath counts, measured on the 35 finals of the 2026‑10‑22/23 validation rerun (previous traces re‑segmented, engine breaths → after the merge): breathingTask 0.5 % (JN_2 201 → 200) to 12.5 % (ADtest 911 → 797; VW 968 → 898 = 7.2 %; the Dupi sessions lose 0–2 breaths each, CP_1 96 → 94, PC_2 117 → 115), breathingTasks_separate 0–1.7 % (HM_2 319 → 319, BW_2 259 → 256, SS_1 466 → 458), EmotionalMovieTask 0.9–1.0 % of the whole recording (MS 448 → 444, CP_1 383 → 379; in‑clip `behDat` rows 379 → 376 and 316 → 312), alternating6Blocks 0.2–2.6 % of the whole recording (JH 931 → 929, CA 613 → 599, HK 610 → 594) with 0–10 in‑block rows lost per session (HK 10, CA 9), pacedBreathing 0.3 % (JW 970 → 967) and 2.2 % (KG 1472 → 1439), respiratorySweep ZL 825 → 806 (its previous final was already merged: same onsets), airPuff 4.3 % (47 → 45); sniff tasks have no breaths. Of the 70 (VW) and 114 (ADtest) breaths merged in the two reconstructed‑playback sessions, 5 and 1 lie in the reconstructed blocks. A final without `outDat.breathMerge` was made before the rule. The `breathMerge.jpg` QC figure in the sweep sessions' figure folders is made outside the pipeline code.
- **other breath‑type tasks** (movie / alt6 / paced / sep / vipassana / respiratorySweep) call `segmentBreaths_zlp` (+ the breath merge above, except vipassana) from their
  mains — vipassana only when its respiration viability probe passes (`probeRespViability_vipassana`;
  otherwise `respSkipped=2`, no `bmObj`) — and vipassana's block boundaries come from an artifact‑index +
  dynamic‑programme step (`artifactIndex_vipassana` on the raw scalp rows, 60‑Hz‑dominated rows left out of
  its channel median → `inferBlocks_vipassana`) whose evidence is computed **before** `runSharedCore`, not
  after, since it needs the pre‑cleaning EEG — and before the task's ingestion notch too: `assembleRaw_vipassana`
  computes it on the un‑notched rows, then notches (notched evidence moved DD's audiobook1 by minutes); the 32 scalp rows are then average‑referenced (Cz recovered, `shared/robustAvgRef`; before 2026‑10‑21 the main re‑zeroed the inserted `Cz` row after the core instead, §6.1); ECG goes through
  `shared/runECGStage` (movie / alt6 / paced / vipassana / respiratorySweep: on failure NaN HRV via
  `fillNaNHRV` + `ecgSkipped`, where breathingTask stays strict and errors); sep probes ECG once per session
  and runs `processECG` per section. **SniffLogic log alignment** (`shared/alignLogToRaw`, alt6 makeOutDat and
  respiratorySweep's `buildSweepTTL`): 20‑Hz cross‑correlation of the log's `pressure_pa` with the raw `rsp1`
  (coarse lag), 100‑Hz refinement, 120‑s‑window drift fit, polarity from the peak sign (the log's pressure is
  inhale‑positive); the quality gate is the |r| over the log/raw **overlap** (`rLocal` ≥ 0.40, REVIEW below
  0.60) — the global normalized peak is low by construction for a log covering only part of the recording.

**Behavior table:** `build_behavior_table_<task>` joins raw behavior to detected onsets (§6.4); the breath‑type
builders share `behDatFromBreaths` (the 14 base columns), `appendBreathMergeCols` (the four breath‑merge columns, §6.4) and `appendBmFeatureCols` (`bm_*`).
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
| `rspIDX`, `rspFlip` | int, ±1 | which `rsp` channel is the respiration trace, and its polarity (inhale ↑) (breathingTasks_separate with differing per‑condition channels: `rspIDX` points at the appended `rspSelected` row, `rspFlip = 1`, per‑section choices in `outDat.sections.rspIDX/rspFlip`) |
| `TTL` | table or vector | task‑specific event markers in **fs=500 samples** (6.5) |
| `moreThan1` | 0/1 | "more than one sniff per trial"; **also the done‑sentinel** (1 = breathing/O15, 0 = cue/thresh) |

Fields of finals made by the 2026-10-22 rerun (absent in older finals; read them to tell a final's generation, §8): `breathMerge` (breath-type tasks except vipassana / ADmeditation: the merge rule's record — `rule, exFrac, deadFrac, minorFrac, zeroFlow, zeroFlowFracDwell, nBefore, nAfter, nMinor` (blips + lead bumps), `nLeadBumps`, `nMerged` (inhales joined), per kept breath `nPulses, nRows, inhaleArea, exhaleArea, exInRatio, origRows`, per engine breath `isMinor, isLeadBump, pulseInhaleArea, pairExInRatio, engineOnsetSec, zeroFlowAtOnsets, deadBand`; breathingTasks_separate: at top level only `rule` / `exFrac` (the first segmented section's), the counts summed over the sections (`nBefore, nAfter, nMinor, nLeadBumps, nMerged`) and the per‑kept‑breath arrays `nPulses, nRows, inhaleArea, exhaleArea, exInRatio` concatenated in `bmObj` order — `deadFrac, minorFrac, zeroFlow, zeroFlowFracDwell, origRows` and the per‑engine‑breath fields exist only in each section's own record, `.perSection{b}` (`[]` = section not segmented); respiratorySweep finals made from 2026-10-15 on have it too), `carry` (the respiration carry's record, §8: `source` (the previous final), `sha256`, `bytes`, `modified`, `sourceVar`, `date`, `made` (its engine version / EEG cleaning mode / `moreThan1` / breath merge), `rowsCarried`, `targTraceCarried`, `reconstructedCarried`, `rspIDX`, `rspFlip`, `checks` (`nSamp, sessIDMatch, labelsMatch, rspMatch`; per rsp row `r` = Pearson r with the rerun's own row on the respiration band (< 5 Hz, outside `reconstructedBlocks`), `rBroad` = the broadband r, `selected` = the row `rspIDX` selects (only that row is held to r ≥ 0.90), `auxLow` = indices of auxiliary rows under 0.90 (a warning, `carryRespFromFinal:auxRow`), `maxAbsDiff, nDiff, nExcluded, nNonFinite`), `rowsVerified`, `postHocFields` + `postHocNote`, `stageFieldsNotCarried` + `stageFieldsNote` (names of previous‑final fields the pipeline can produce but this run did not — e.g. the old `blinkICA` of a session whose blink removal is now off; NOT carried), `previous` (the record of an earlier carry), `note`; breathingTasks_separate: section 1's record + `perSection`), `carriedFromPrevFinal` (struct, field name → value, only for fields the pipeline cannot produce in any configuration — `shared/carryPipelineFields` is the list — i.e. post‑hoc additions of the previous final; they describe the PREVIOUS data and are not recomputed), `blockMergeInfo` (pacedBreathing: the block accounting across the merge, §1) and the EEG-stage fields of §6.3 (`dataLapGeometry`, `spikeCleanInfo`, `blinkICA.rng`, `blinkRemovalNote`).

O15‑only extras: `CSClist`, `OGdataDir`, `loadFile` (the `*LoadData*.m` used), `preProcScript`.
Held‑button O15 sessions (§1; sheet `ttlProtocol = heldButton`; `oldTTL` finals have neither field and record no
protocol name) add `buttonDown` (table, one row per button‑down period: `trial, window, onset,
offset` (500‑Hz samples), `durSec, onsetRaw, offsetRaw` (raw samples), `nFree`) and `ttlInfo` (the event‑channel
parse: levels, threshold, rail fractions, `pulses` = every pulse with its role, `heldSniff` = the free‑sniff rule, and, in finals from 2026‑10‑21, `heldResolve` = the one‑sniff‑per‑inhale step: options `mergeDropFrac 0.35, baseSec 1, peakMaxSec 1.5`, `rule`, `nGroups / nDropped / nRerefined`, `actions` (one row per row of a collision: `trial, sniffOnset, buttonWindow, label, group, inhale, dropFrac, action` kept / dropped / rerefined, `finalBefore, finalAfter, inhaleTrough, inhalePeak, rowBefore`)).

threshTask multi‑run sessions only (§1): `threshDesign` (`name 'multiRun', nRuns, trialsPerRun, nTrials,
odorCodes [1 2 3 12], odorLabels {air low med high}, nPerCode, behFiles, note, startCodeSample` (500‑Hz sample of
each run's start code), `ttlParse` (the run split: start‑code onsets/ends in raw samples, pulse widths, pre‑start
pulses dropped)). The detection build (§1) adds `build 'detection', resultID '<id>_det', taskCode, behColumns` (the
`.txt` header), `behTxtFiles, emptyRatingFill NaN, emptyRatings` (table `run, trialNum, column`), `nYesPerCode, nNoClick`;
the standard build has none of these fields.

detectNoOdor extras: `ttlInfo` (the event parse: `pulses` with roles `preamble/startCode/sniff/response/endCode`,
`parse` = levels / threshold / preamble, `sniffRaw` / `responseRaw` (raw samples), `alignResidSec` (DAQ cue‑to‑cue
minus result‑file `trl_start` intervals), `latencyResidSec`, `nanRuns` (the raw file's all‑channel NaN runs, filled),
`trialStartNote`), `behSource` (result + cuelist file, `note`, `responseCoding`), `inhaleCount` (`opts, method,
window, nInhales, amp, peaks` — every candidate peak with its height / prominence fractions and `counted`, so the
count can be redone at another threshold).

cueTask3 extras: `ttlInfo` (the event parse, `parseEvents_cueTask3`: `pulses` (`onsetRaw, durSec, cls, role` =
`start/cue/sniff1/sniff2/sniff3/response/end`, `run, trial`), `nPulses`, `nIgnored`, `nPerRun`, `sniffGapSec` /
`cueToSniff1Sec` (min / median / max), `clockResidualMaxSec` (trial‑start pulse intervals minus the result files'
`trl_start` intervals), `nNaNFilled`, `behFiles`, `rule`), `sniffTrain` (the train‑detector options used) and,
only when `P.noOdorTrials` is set, `noOdorTrials` (table `trial, reason`).

airPuff extras (§1):
- `pulses`: every DAQ pulse, one row each. Columns `pulse, onsetRaw, offsetRaw` (raw samples), `durSec, tSec`,
  `role` (`lead` / `puff` / `separator`), `train, puff, hold, holdInRun, puffNum`, `run` (1 cued / 2 blind),
  `condition`, and `sample, offsetSample` (500 Hz).
- `puffInfo`: the parse (levels, threshold, rail fractions, train lengths, counts, options). `puffOpts`: the
  `P.puffOpts` used.
- `holds`: one row per breath hold. Columns `hold, run, condition, holdInRun, nPuffs, nPuffsQuiet,
  nQuietRuns, interrupted`; `onset, offset` (500‑Hz samples; NaN when no puff fell in a quiet stretch);
  `onsetSec, offsetSec, durSec, firstPuffSec, lastPuffSec, onsetToFirstPuffSec, lastPuffToOffsetSec`;
  `holdBreath` (the `bmObj` row spanning the hold) and `lastInhaleSec, exhaleTroughSec, nextInhaleSec,
  lastPuffToInhaleSec`; `preAmp, preLenSec` (median of the 3 breaths before) and `recoveryAmp,
  recoveryLenSec`; `rrPre, rrHold, rrRecovery` (mean `RRint` in s over the 10 s before, the hold, and the
  10 s after).
- `holdInfo`: the quiet threshold, the median breath amplitude and the options.
- `breaths`: the per‑breath table of the whole recording — the 14 base columns, `task` `hold`/`breath`,
  `condition` = hold index (0 = none), HRV and `bm_*`. Plus `bmObj` / `bmFeatures` (col 12 = hold index).
- Provenance and ECG: `atlasSegments, CSClist, OGdataDir, loadFile, preProcScript, beatSpec, heartBeats,
  ecgSkipped`.

vipassana‑only extras: `markers` (table of hand‑press event markers + the recording‑start marker,
`description/sampleRaw/sample/minutes`), `artifactIndex` (the 1‑s EEG evidence trace `inferBlocks_vipassana`
segments), `blocks` + `blockInference` (inferred period boundaries and the DP's cost/margin diagnostics;
§6.5), `refChan` (`'Cz'`, the RECORDING reference, inserted as a zero row in the raw file), `avgRef` (the ingestion re‑reference, since 2026‑10‑21: `applied`, `recordingRef`, `method`, `labels`, `refChans` / `excluded` labels + `excludedWhy` (`flat` / `deviation`), per‑row `flatFrac` / `badWinFrac` / `robustAmpUV` / `robustZ` parallel to `labels`, `nWin`, `nGapWin`, `opts`, `note`), `dataRef` (the reference rows 1–32 are stored in: `'robust common average (outDat.avgRef)'`, or `'Cz'` without it), `czRezeroed` (`false` when average‑referenced — Cz is then a real channel; `true` in finals made before 2026‑10‑21: the shared EEG stage's
`removeNoiseChansVolt` flags the flat Cz row bad and overwrites it trial by trial with a spline interpolation
of its neighbours, so the main forces `data` row 24 back to exact 0 after `runSharedCore`; `'Cz'` stays in
`badChans` and `dataLap` keeps its interpolated estimate), `respSkipped` (`0` respiration processed / `2`
skipped — no usable channel, e.g. `260918_EEG_NWU_CC`) + `respProbe` (the viability‑probe result struct),
`rspPolarityRSA` (inhale‑locked RR sanity check `deltaRRms / nBreaths / consistent`; always present, and
`NaN / 0 / false` = not checked because respiration or ECG was skipped), `notchHz` (`[60 120 180]`) +
`notchNote` (the ingestion notch of the 32 scalp rows, §1; absent in finals made before 2026‑09‑27; v2: `notchHz = []`),
`ecgNotchHz` + `ecgNotchNote` (`[60 120 180]`, the ECG1 row notched at ingestion: v2 since 2026‑10‑20, v1 since 2026‑10‑21
after CC's beat times were found line‑locked — IBI phase concentration at 1/60 s 0.38, RMSSD 128 ms; `[]` in older v1 finals).
vipassana v2 adds (2026‑10‑20, §1): `protocol` (`'v1'`/`'v2'`), `photodiode` (the block runs `on, off, onSec, offSec,
durSec` in samples / s, `flickers`, levels `lo/hi/thr/noise`, a 10‑Hz QC `trace`), `sniffLogic` (`[]` without a log;
else `file`, `log` (`blocks` = `name, params, tStart, tEnd, complete, rawStartSec, rawEndSec`; `sweepBreaths` = one row
per target cycle `block, breath, half, periodSec, depth, amp, gain, center, t, sample`; `events`), `align` (the clock map
raw s = `intercept` + (1 + `slope`) log s, `driftPPM`, `sign` (= rsp1's polarity vs the inhale‑positive log), `win`,
`medianR`, `residRmsMs`, `gainPerPa`), `coverage` / `coverageNote` (samples the `rspSniffLogic` row covers)),
`behFiles`, `psychopyFiles`, `rspFilterHz` (5) + `rspFilterNote`, `acqSegments` (the LoadData script's acquisition
segments in `.eeg` file samples, kept + dropped — deliberately not `segments`, which other tasks use for seams inside the
final) and `blockInference` (= the `blocksFromMarks_vipassana` info: `hasLog`, `hasPhotodiode`, `nTask`,
`missingTask`, `durDevSec`, `unmatchedLogBlocks`, `flickers`, `opts`).

respiratorySweep‑only extras: `blocks` (the event table at 500 Hz, §6.5), `TTLinfo` (how the raw file's event
table was built: per‑log alignment `logAlign` — file, `lagSec`, `r` / `rLocal`, drift, polarity, raw coverage —,
`aborted` block starts, `skippedLogs` (event‑less logs, not aligned), `flags` (checks that need a look), the
`stopwatch` spec, `noteCheck` = note times vs log‑derived times, `rspFlip`
measured from the log, `alignedChannel`), `ratings` (long table of the PsychoPy state ratings: `set`
`baseline` / `postSweep`, `file, Q_short, type, question, rsp, t`), `baseEmotion` / `postSweepEmotion`
(one‑row tables in the alternating6Blocks layout), plus the O15‑style provenance `CSClist, OGdataDir, loadFile,
preProcScript`, and `breathMerge` (§6.1). The raw file (`raw_respiratorySweep.mat`) carries `curDat.TTL` (same table in **raw** samples),
`curDat.TTLinfo` and `curDat.logTrace` (SniffLogic pressure / target at 50 Hz on the raw clock).

ADmeditation‑only extras: `atlasFolder`, `trim` (`trimStartSec 180, trimEndSec 60, rawSamples, rawDurSec,
fsRaw, firstRawSample, lastRawSample, keptDurSec`: final sample *s* ↔ raw sample `(s−1)·origFS/fs +
firstRawSample`), `buttonPresses` (table `press, onsetRaw, releaseRaw, durationSec, ampOnUV, ampOffUV, tRecSec,
inAnalysisWindow, onsetTrim, releaseTrim, sample, releaseSample, timeSec`; `*Raw` = untrimmed raw samples,
`*Trim` = trimmed raw samples, `sample` = final 500‑Hz sample, NaN outside the analysis window), `pressInfo`
(detector threshold / noise / unpaired releases), `segments`, `beatSpec`, `rspPolarityRSA`.

breathingTasks_separate extras: `sections` (table `label, sourceFile, startSample, endSample` in final samples;
plus, only when the session uses them (§1): `rspIDX, rspFlip` (channels differ), `beatSpec` (specs differ),
`trimStartSec, trimEndSec, rawFirstSample, rawLastSample, rawSamples` (`P.condTrimSec`; final sample *s* of section
*b* ↔ raw sample `(s − startSample(b))·origFS/fs + rawFirstSample(b)`, `trimNote`), `blinkRemoval, blinkSkipped,
blinkSkipReason, blinkFilled` (when a section's blink removal was switched off — the sleep / sleepWithOdor default or
`P.condBlinkRemoval` — a zero `blinkIndicator` row was inserted, or `P.condBlinkRemoval` is set: `blinkRemoval` 0/1 =
whether the blink ICA ran, `blinkSkipped` = switched off by a setting, `blinkSkipReason` = why a section has
`blinkRemoval` 0 (`""` = it ran), `blinkFilled` = its `blinkIndicator` row is the inserted all‑zero one; `blinkNote`),
`respSkipped` (0/2, `P.condRespSkip`; top‑level `respSkipped` 0 none / 1 some
/ 2 all sections, mirroring vipassana's 2 = skipped, + `respNote`; a skipped section has no breaths, so with every
section skipped `behDat` keeps its columns with zero rows), `minIBI` (s, NaN = not set; `P.condMinIBI`)), `eegQCPerSection` (per‑section `badChans`,
`blinkRemoval`, `blinkICA`, `EEGCleaningInfo`, `spikeCleanInfo`, …; the top‑level EEG fields describe section 1, except
`EEGCleaningInfo`, which is a session summary, §6.3; so in a session whose first section is `sleep` / `sleepWithOdor`
the top‑level `blinkRemoval` is 0 although later sections may have been blink‑cleaned — read `sections.blinkRemoval`; a
sleep‑only final made since 2026‑10‑22 has the all‑zero `blinkIndicator` row in every section (G2d); the four made before it — GH_1, DL_1, SM_1, ZF_1 as of the 10‑21 reruns — have none), `rspSelectedNote` (rsp channels
differ), `sepEchem` + `echemNote` (echem‑mode finals only).

### 6.2 Channel taxonomy in `outDat.data` (find rows by label)

| Channel(s) | Label match | Present when | Added by |
|---|---|---|---|
| 32‑ch scalp EEG | exact 10‑20 names, **rows 1–32** | `hasEEG` | raw load; validated in `preprocess_eeg` |
| macro (raw depth/strip) | `contains('macro')` | recorded | raw load |
| respiration | `contains('rsp')` | always | raw load (select with `rspIDX`, flip with `rspFlip`) |
| ECG (≈3 ch) | `contains('ECG')` | breathing‑type tasks | raw load (→ `buildECGz`) |
| photodiode / events | `contains('event')` | O15, movie task (others vary) | raw load |
| `blinkIndicator` | `=="blinkIndicator"` | `hasEEG`, > 10 good EEG ch and blink removal ran (`blinkRemoval==1`); breathingTasks_separate: all zero over a section whose blink removal did not run (`sections.blinkFilled`), in every section of a sleep‑only session since 2026‑10‑22 | `preprocess_eeg` (`concatSections` for the zero fill) |
| `badTS`, `interpChan` | exact | `hasEEG` | `preprocess_eeg` (bad‑sample mask, interpolation mask) |
| `macBP1..N` | `contains('macBP')` | macros run | `preprocess_macros` (bipolar pairs, N = nMacro − 1) |
| `spikeCleanVec` | `=="spikeCleanVec"` | macros run | `preprocess_macros` (all‑ones ⇒ no spikes removed) |
| `targTrace` | `=="targTrace"` | breathing, respiratorySweep; vipassana v2 with a SniffLogic log | `alignTargetBreathingTraceSimplify` (breathing); respiratorySweep main from the SniffLogic `target_pa` (log units, 0 outside sweep blocks); vipassana: the log's `target_pa` (Pa) mapped onto the recording, 0 outside the sweeps (main, after the core) |
| `rspSniffLogic` | `=="rspSniffLogic"` (also `contains('rsp')`: rsp index 2) | vipassana v2 with a SniffLogic log | `assembleRaw_vipassana`: the aligned log pressure (Pa, inhale‑positive, 0 outside the log's coverage) |
| `RRint` | `contains('RRint')` | breathing‑type tasks | `processECG` (interpolated RR‑interval series, s) |
| `forehead_left`, `forehead_midleft`, `forehead_midright`, `forehead_right` | `contains('forehead')` | OBE sessions with forehead cup electrodes (so far AD_1, AD_2, RX_1, BW_2, DW_1, EZ_1) | raw load (Atlas CSC21–24, appended after the standard channels) |

**Forehead cup electrodes (Atlas CSC21–24).** Lab convention from 2026‑10‑08 on: **CSC21 = left‑left,
CSC22 = left‑middle, CSC23 = right‑middle, CSC24 = right‑right**, in the *participant's* frame, labelled
`forehead_left`, `forehead_midleft`, `forehead_midright`, `forehead_right`. New LoadData scripts use this
order. Sessions before the convention were plugged either way, so their labels follow what the recordings
show (cardiac far‑field + horizontal‑saccade tests, 2026‑10‑05, `reports\obeUpdate_261005\forehead\`):
BW_2 and EZ_1 are left→right like the convention; AD_1, AD_2, RX_1 and DW_1 are right→left (their loaders
label CSC21 `forehead_right` … CSC24 `forehead_left`, which matches the data). The tests resolve the two
pairs (CSC21/22 vs CSC23/24) but not the order within a pair, so in the older sessions `midleft`/`left`
and `midright`/`right` are nominal. Always find these channels by label, never by CSC number or row. In
sessions without forehead cups CSC21–24 are unconnected inputs and are not extracted.

EEG montage order (rows 1–32): `Fp1 Fz F3 F7 FT9 FC5 FC1 C3 T7 TP9 CP5 CP1 Pz P3 P7 O1 Oz O2 P4 P8 TP10 CP6
CP2 Cz C4 T8 FT10 FC6 FC2 F4 F8 Fp2`. The non‑EEG channel set varies by session/montage — always locate
channels with `cellfun(@(x) contains(x,'…'), outDat.labels)`.

### 6.3 EEG‑derived fields (only if `hasEEG`)

`eegLocs` (table `[32×8]`: `labels, X, Y, Z, theta, phi, X_flat, Y_flat`), `dataLap` (`[32×nSamp]` surface
Laplacian, `[]` if ≤ 10 good channels), `dataLapFromInterp` (0/1 — Laplacian computed on an interpolated
copy; mask `badChans` for per‑channel Laplacian analysis), `badChans` (cell of labels; broadband `data(1:32)`
keeps their real values — except that in every 2‑s trial where the detector flagged < 16 channels it REPLACED
those channels by a spline interpolation (`interpChan` = how many, not which; 2026‑10‑14 audit: 50–96 % of
samples in many finals; `'fixed'` / `'band'` never repair inside gap / pass‑1‑purged trials)), `EEGInterpolation`, `EEGCleaning` (scalar 1), `blinkRemoval` (0/1),
`EEGCleaningInfo` (since 2026‑10‑14, §5: `mode`, `version`, `unjudgeable` (rule U fired: fewer than max(6, 10 %)
of trials judged, every channel bad), `detectorBad` / `exemptIgnored` (flagged Fp1/Fp2) / `blinkStageBad` (labels
per stage), `nBad`, `nGoodForBlink`, `nGoodAfterBlinkStage`, `blinkGate` (fixed / band: the blink stage's tests
left ≤ 10 good channels → no ICA, no `dataLap`), `fracBadTS`, `fracInterp`, and `detector` = the rule record —
thresholds, per‑2‑s‑trial `trialCode` (0 judged, 1 gap, 2 / 3 / 4 purge), `nChanOverP2`, purge fractions,
`nJudged` / `minJudged` / `nBlocksP1`,
`bandRedo` (band: share of channel‑trials re‑judged without their over‑threshold neighbours), `outBad` /
`chanRuleBad` / `p2ChanInitial` / `p2ChanFinal` labels, per‑channel flag fractions; breathingTasks_separate: the
full record per section in `eegQCPerSection{b}.EEGCleaningInfo`, and the top‑level `EEGCleaningInfo` is a session
summary — `mode`, `version`, `perSection = true`, `unjudgeable` (any section), `nBadPerSection`,
`fracBadTSPerSection`, `note` — not section 1's record). Since 2026-10-22 also: `dataLapGeometry` (the sphere `dataLap` was computed on: `method`, `centre` (m), `radiusM`, `radiusCV`, `radiusMinMax`, `note`; absent = the old common-mode `dataLap`, see below), `spikeCleanInfo` (macro spike ICA, sessions with macros and `spikeClean`: `ran` (false = too few spike snippets, bipolar data kept as they are), `seed`, `seedKey` (`sessID|macroSpikeICA|<condition>`), `reason`, `badICs`, `rng`; breathingTasks_separate: `eegQCPerSection{b}.spikeCleanInfo`), `blinkICA.rng` (how `runica`'s randomness was fixed: `'rndreset no (legacy rand state 0)'`, `seed 0`, `globalRngRestored`, `note`; sep: per section) and `blinkRemovalNote` (§3).

> **`dataLap` (fixed 2026-10-22):** `laplacian_perrinX` is a spherical-spline method, but until 2026-10-22 `preprocess_eeg` fed it the head coordinates of `eegLocs_standard_coords.csv` (radii 0.081–0.114 m from the coordinate origin, which lies ~1.65 cm in front of the head centre), and the stored `dataLap` was a common-mode artefact (found 2026-09-27: 96–99 % of its variance in the channel mean, median inter-channel |r| 0.97–0.99). Now `preprocess_eeg` projects the 32 electrodes onto the unit sphere around the least-squares sphere centre (`lapSphereCoords`; centre ~[−0.0165 −0.0008 0.0004] m, radius 0.095 m, CV 0.06) before `laplacian_perrinX`; bad channels are still interpolated first with the electrodes' own geometry (it predicts held-out channels better: relative error 0.31–0.34 vs 0.43–0.65 on three sessions; the detector's interpolation in `removeNoiseChansVolt` likewise keeps it). The result equals FieldTrip's spline `ft_scalpcurrentdensity` (per-sample spatial r 0.999–1.000 on three stored finals); common-mode share of the variance 0.01–0.025, median inter-channel |r| 0.1–0.24. Units: µV per unit-sphere² (divide by `dataLapGeometry.radiusM^2` for per m²). **Finals made before 2026-10-22 have no `dataLapGeometry` field and carry the old common-mode `dataLap`: do not use it** — the 2026-10-22 full EEG rerun replaces them (§8).

### 6.4 `behDat` — the behavior table (task‑specific)

`behDat` is a MATLAB **`table`**. Access by **named column**, never numeric index.

**cue / thresh / O15 / detectNoOdor / cueTask3 — per‑sniff.** Shared first six columns from `behDatFromSniffs`: `sniffOnset` (coarse
onset, samples), `n` (trial), `wiTriali` (sniff index within trial), `TTLoffSet`, `sniffType`, `sniffLabel`
(cue/thresh/detectNoOdor/cueTask3 `cued`; O15 `start`/`free`/`confirm`). Then the task columns —
cue: `cue` (1–10; `0` = no‑cue condition, 60‑trial files only, §1), `odor`, `response`, `respString`, `type`
(`hit`/`miss`/`cr`/`fa`; `noCue` on `cue==0` trials); thresh: `odor` (1–3), `pleasantness`, `intensity`, `type` (`air`/`low`/`med`)
— multi‑run sessions (§1): `odor` 1/2/3/12 (the olfactometer line), `type` `air`/`low`/`med`/`high`, plus `run` (`n` counts
trials across both runs, 1–80; in the task build with the "No Odor" button, `intensity` −1 = that button, 735 = no response)
— detection build (§1) also `detect` (1 Yes / 0 No / NaN no click) and `detectRT` (s), and NaN for a missing rating;
detectNoOdor: `odor` (planned cuelist code 1/2 — never delivered), `trialType` (1 Yes‑left / 2 Yes‑right), `response`
(the key: 1 left / 2 right, NaN = none), `respString` (`Yes`/`No`/`SKIP`, authoritative), `respLatency` (s, cue → key‑press
pulse), `nInhales` (inhale peaks cue → answer, §1);
cueTask3: **three rows per trial** — `wiTriali` = the SNIFF cue number 1–3 (kept when another sniff of the trial is
undetected), `sniffLabel` `cued`, `TTLoffSet` = coarse onset − its SNIFF pulse; the cue columns above (`cue`, `odor`,
`response`, `respString`, `type`) on all three, then `run`, `noOdorDelivered` (§3) and `inhaleTrough` / `inhalePeak`
(500‑Hz samples of the train detector's bounds; `finalOnset` lies between them);
O15: `target`, `response`, `expScore` (+ `buttonWindow` in held‑button sessions: the `outDat.buttonDown` row a
free sniff came from, NaN for start/confirm; its `TTLoffSet` = onset − period onset; one row per inhale: no two rows of a trial share a `finalOnset`, `ttlInfo.heldResolve`). Finally `refine_onsets_with_phase` appends **`adjust`**,
**`finalOnset`** (phase‑refined onset — *use this for epoching*) and **`manOnset`** (NaN placeholder for
manual QC). Sanity sizes from real Dupi files: cue ≈ `[40 × 14]`, thresh ≈ `[45 × 13]` (multi‑run `[80 × 14]`, detection build `[nSniffs × 16]`), O15 ≈ `[81 × 12]`
(one more column than before July 2026 because of `manOnset`), detectNoOdor `[40 × 15]` (SS_1), cueTask3 `[120 × 18]`
(SS_1); cue/thresh/detectNoOdor are one sniff per trial, cueTask3 three.
A trial the reviewer dropped from a cue session (`P.dropTrials`, §3) is simply absent from `behDat` (like an
undetected trial) and listed in `outDat.droppedTrials` (table `trial, reason`); `outDat.TTL` keeps every trial
row, so `behDat.n` still indexes it. The field exists only on sessions with a drop.

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
| `nInhalePulses`, `breathInhaleArea`, `breathExhaleArea`, `exhaleInhaleRatio` | breath‑merge columns (`appendBreathMergeCols`, finals since the 2026‑10‑22 rerun; below) |
| `bm_*` | breathMetrics per‑breath features (`appendBmFeatureCols`), appended after the columns above |

Breathing also stores `baseEmotion` (1‑row table of the baseline `order==0` ratings plus
`task/noseMouth/shadowFile/warp`), `bmObj`, `heartBeats` (6.6), and `bmFeatures` (plain struct, never the
class object). Empirically a 32‑ch‑EEG Dupi breathing session gives
`behDat` ≈ `[389 breaths × 34 vars]` (+4 merge columns since the 2026‑10‑22 rerun); the emotion column set varies with the questions asked.

Other breath‑based tasks build their own `build_behavior_table_*` on the same shared base (§5) with their
own extra columns instead of ratings — e.g. pacedBreathing's `rateBPM, localPeriodCV, localAmpCV, nSubPeaks`
(§1); **vipassana**'s adds `task` (the breath's inferred block label), `still` (copied from the block),
`noseMouth`/`shadowFile`/`warp` as `NA`/`NaN` (no stimulus metadata), and the same `rateBPM, localPeriodCV,
localAmpCV, nSubPeaks` raggedness measures — only populated when `respSkipped==0` (else `behDat` has the
columns but zero rows) — v2 sessions' `task` is the marked period's label (`audiobook1`, `paced1`, …, gaps
`instructPaced1` / `break` / `questionnaire1` / …, `still` 0) and they add `targetBreath, targetHalf, targetPeriodSec,
targetCPM, targetDepth` (the SniffLogic sweep cycle the breath starts in; NaN outside the sweeps and without a log);
**ADmeditation**'s adds `task='meditation'` (`condition` 1), the same raggedness
measures, `pressInBreath` (presses whose onset falls in this breath), `secSincePress` / `secToPress` (s from
the previous / to the next press onset, NaN beyond the first / last) and `nearSeam`.
**respiratorySweep** keeps **every** breath of the recording (rests / instructions /
ratings included; `condition` = block order, 0 between blocks) and adds `task` (block label or `none`),
`blockType` (`audiobook` / `sweep` / `focusedBreathing` / `other` / `none`), `phase` (`pre` / `sweep` / `mid` / `post` /
`none`),
`inBlock`, `cpm`, `depth`, `sweepNum` (NaN off‑sweep), `noseMouth`/`shadowFile`/`warp` as `NA`/`NaN`, and the
pacedBreathing `rateBPM, localPeriodCV, localAmpCV, nSubPeaks` (local windows never straddle a block edge), then
`nInhalePulses`, `breathInhaleArea`, `breathExhaleArea`, `exhaleInhaleRatio` (breath‑merge rule, §5; `bm_*` of a merged breath = its first pulse);
ratings are not broadcast per breath (only a baseline and a post‑sweep set exist) — see `ratings` /
`baseEmotion` / `postSweepEmotion` (§6.1).

Every breath-type per-breath table of a final from the 2026-10-22 rerun carries the four breath-merge columns (`appendBreathMergeCols`, before `bm_*`): `nInhalePulses` (inhale pulses joined into the breath, 1 = not merged), `breathInhaleArea` / `breathExhaleArea` (the whole breath's signal area above / below zero flow, sensor units × ms) and `exhaleInhaleRatio`; the `bm_*` columns of a merged breath (`nInhalePulses > 1`) describe its FIRST pulse only. A table that keeps a subset of the breaths (EmotionalMovieTask in-clip, alternating6Blocks in-block) takes the rows of the kept merged breaths; airPuff has them in `outDat.breaths` (its per-puff `behDat` is unchanged). Column counts quoted in this section grow by 4.

**airPuff — per‑puff** (`build_behavior_table_airPuff`, one row per puff; SS_1 `[28 × 25]`). The per‑breath
table of the recording is `outDat.breaths` (§6.1).

| Column(s) | Meaning |
|---|---|
| `puff`, `onset` | puff index; onset sample (= `TTL`) |
| `finalOnset`, `manOnset` | `finalOnset` = `onset` (align on it); `manOnset` NaN placeholder |
| `tSec`, `run`, `condition`, `cued` | time (s); run 1 `cued` / 2 `blind` |
| `hold`, `holdInRun`, `puffNum` | which hold, its index in the run, the puff's index in the hold |
| `quietAtPuff` | breath held at the puff |
| `tSinceHoldOnset`, `tToHoldOffset`, `tToNextInhale` | s |
| `windowsInHold` | both respiration windows lie inside the hold |
| `rspPre`, `rspPost`, `rspChange` | mean respiration in [−1, 0) / [0, 1) s (the cannula reads ~airflow), and the change |
| `slopePre`, `slopePost` | µV/s of the < 2 Hz trace |
| `sdPre`, `sdPost` | SD of the < 2 Hz trace |
| `rrPre`, `rrPost` | mean `RRint` in [−2, 0) / [0, 2) s |

### 6.5 `TTL` conventions (samples @ 500 Hz)

- **O15** — table `[15 × 20]`: `trialStart, buttonPress, confirmSniff, free1 … free17` (NaN‑padded), built by
  `detect_ttls_O15` from the z‑scored `event` channel (30 trial marks expected; `ttlRemoveIdx` drops
  aberrant ones). `buttonPress` = 2nd pulse of the press pair, `confirmSniff` = 1st pulse of the confirm pair,
  `free1` = the start cue (its sniff is labelled `start`), `free2…` = the experimenter's sniff marks (`oldTTL`
  sessions). Held‑button (`ttlProtocol = heldButton`) sessions keep the same columns, parsed by `parse_O15_events`
  on median/rail levels, but `free2…` stay NaN: their free events are periods, in `outDat.buttonDown` (§6.1).
- **thresh** — table `[45 × 3]` (multi‑run design: `[80 × 3]`, all runs in recording order; the run of each trial is
  `behDat.run`, the start codes are in `outDat.threshDesign`): `start (= sniff − 1000)`, `trial`, `sniff`.
- **cue** — table `[nTrial × 3]`: `trialStart, response, sniff`.
- **detectNoOdor** — table `[nTrial × 3]` in the cue layout (the shared `detect_sniffs_from_TTLs` reads the sniff
  target from column 3 on): `trialStart` (= sniff − 3 s, the nominal onset of the 3‑2‑1 countdown — no pulse marks
  it), `response` (key‑press pulse; NaN = no answer), `sniff` (SNIFF‑cue pulse).
- **cueTask3** — table `[nTrial × 5]` (SS_1 `[40 × 5]`, both runs in recording order; `behDat.run` gives the run):
  `trialStart` (cue‑word pulse), `response` (key‑press pulse; NaN = no answer), `sniff1`, `sniff2`, `sniff3`
  (SNIFF‑cue pulses, 1.1 s apart; the shared detector reads its targets from column 3 on).
- **breathing** — **vector** of block‑boundary samples (or a 5‑min fallback `0:600000:end`). New breath‑based
  tasks keep this vector and may add a descriptive table alongside it (alternating6Blocks: block starts +
  `blocks`; breathingTasks_separate: `[start_1 end_1 start_2 end_2 …]` + `sections` (§6.1; a trimmed section's
  bounds are those of its kept raw stretch, `sections.rawFirstSample/rawLastSample`)).
- **EmotionalMovieTask** — the exception: `TTL` is the clip table itself (`clipOnset, clipEnd, nPulses,
  valence`; `clipEnd` is NaN for the final clip). With a PsychoPy clip log (`matchClipsToPsychoPy`) it adds
  `nPulsesDetected, psychopyIdx, fileName, vidLenSec` (clip length, s) and, since 2026‑10‑12, `normValence,
  normArousal, normImpact` (DEVO2 clip norms, not participant ratings) and `movieStart, movieStop` (the clip's PsychoPy start / stop in samples;
  `clipOnset` is the photodiode flash ~1.6–1.9 s after `movieStart`); the final clip's `clipEnd`, and that of any
  clip followed by an unmatched one, is its `movieStop`.
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
  **v2** sessions (§1): the starts of the MARKED periods (`blocksFromMarks_vipassana`); `blocks` = `label, order (0–14:
  pre, audiobook1, instructPaced1, paced1, instructAudiobook2, audiobook2, break, anapana, questionnaire1, vipassana,
  questionnaire2, metta, instructPaced2, paced2, post), kind ('task'/'gap'), still, startSample, endSample, durationSec,
  nominalSec, source ('photodiode+log'/'photodiode'/'log'/'gap'), logName, logStartSample, logEndSample,
  pdMinusLogStartSec, pdMinusLogEndSec`. Review `blocks_marked.jpg` / `sniffLogicAlign.jpg`.
- **airPuff** — column vector of **puff onsets** (the DAQ pulses' half‑height crossings). The lead and
  separator markers and the hold of each puff are in `outDat.pulses`; the holds are in `outDat.holds`.
- **ADmeditation** — column vector of **button‑press onsets** in the analysis window (the key analytic
  anchors); the full press table (releases, presses in the trimmed stretches) is `outDat.buttonPresses`.
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
- `ecgExclude` — only when the session has `P.ecgExcludeSec` (§5): `windowsSec` (the unreadable‑ECG windows,
  s), `rrNaNSec` (the `RRint` NaN stretches, a bit wider), `nBeatsDropped`, `note` (the criterion),
  `nBreathsAffected` / `breathIdx` (breaths whose `maxRR`/`minRR`/`RR_max_min` are NaN because of it).
  Absent for every other session; `heartBeats` then already excludes the dropped beats.
- `reconstructedBlocks` — only in breathingTask finals that went through `batch/reconstructPacedBlocks` (QC round 3,
  2026‑08; sessions with `slowBreath` / `slowRec` / `cyclicSigh` SniffLogic playback blocks — of the 2026‑10‑21 G2
  plan rows `251111_EEG_NWU_VW` and `251118_EEG_NWU_ADtest`): table `shadowFile, srcFile, i0, i1, lagSec, r, sgn,
  scale, status, strategy` (`i0` / `i1` = block span in final samples; `status` `reconstructed`,
  `reconstructed-signfixed` (`batch/qc5_reconSignFix`), `no-file` or `weak-alignment-SKIPPED-REVIEW`). In those
  blocks the stored `rsp` row of the `rspIDX` channel is the SniffLogic playback recording rescaled to the
  session's breathing amplitude, not the acquired sensor trace (the acquisition low‑cut filter distorts slow
  breathing), and `bmObj` / `behDat` were re‑segmented from it. **The edit exists only in the final:** `breathingTask_makeOutDat` + `breathingTaskPreProc_main` do not reproduce it, so a plain rerun brings the raw sensor trace back (VW 968 → 1038 breaths, ADtest 911 → 1011, G2 rerun 2026‑10‑21); a rerun with the respiration carry (§8) keeps the repaired `rsp` rows and `targTrace` and copies this table into the new final (VW and ADtest: old respiration and target traces, new EEG; VW 968 → 898 breaths with the merge). See §7.
- `ecgEctopic` — only when the session has `P.ecgEctopic` (§3): one entry per premature beat — `beat` (index into
  `heartBeats`, 0 = inside an ECG exclusion window), `sample`, `timeSec`, `class` (`ectopic` = the two intervals add up
  to ≥ 1.5 × the local median, a compensatory / reset pause; `extraDetection` = < 1.25 ×, one interval split in two;
  `ambiguous`), `couplingRatio`, `pairSumRatio` — plus `nPremature`, `nEctopic`, `nExtraDetection`, `ectopicPerHour`,
  `burdenPct`, `nIntervalsDropped`, `opts`, `note`. The counts include movement artifacts.

---

## 7. Conventions & gotchas

- **Canonical respiration idiom** (used everywhere):
  ```matlab
  isRsp = cellfun(@(x) contains(x,'rsp'), outDat.labels);
  rsp   = outDat.data(isRsp,:); rsp = rsp(outDat.rspIDX,:) .* outDat.rspFlip;
  ```
- **Index `behDat` by name.** Legacy analysis did `behDat(:,13)==0` assuming a numeric matrix; in the table
  col 13 is `index` and the quality flag is `behDat.goodBreath`. Never rely on positions — the column ORDER also
  differs between finals: the raw‑volume twins `bm_inhaleVolumesRaw` / `bm_exhaleVolumesRaw` are the last two
  columns in finals whose volumes were backfilled in place (commit `864b740`, 2026‑09‑03; e.g. the pre‑G2
  GH_1 / DL_1 / RC_1 sep finals) and sit with the other `bm_*` columns in finals made since (same names, same
  values; so do the processed‑behavior CSVs — read them by column name).
- **`task` value drift:** new files `breathingTask`; some older finals `breathing`. Top‑level var name varies
  (`outDat`; breathingTask finals, current ones included, `chanDat` via `parSave`; some older `out`) — load
  via `fieldnames` (§2).
- **EEG channels are exactly rows 1–32** and only when `hasEEG`; everything else is label‑addressed.
- **`spikeRemoval` reads 1 in both `preprocess_macros` branches** — inspect `spikeCleanVec` (all‑ones ⇒
  nothing removed) to know what actually happened.
- **Reruns reproduce the ICA results since 2026‑10‑22** (§5 step 3): `runica` runs with `'rndreset','no'` and the macro spike ICA's draws are seeded from `zlpSeed(sessID|macroSpikeICA|P.seedTag)`, so the same data give bit‑identical EEG / macro rows (lab R2024b; other machines / releases untested). **Finals made earlier were not reproducible** (found in the 2026‑10‑21 G2 reruns, where the unseeded `runica` and the non‑spike snippet draw `sample_nonspike_onsets` gave a new decomposition each time): `macBP*` differed at ~1e‑4 relative (RC_1: ≤ 3.5 µV) and `spikeCleanVec` in ~0.1 % of samples (GH_1 / DL_1 / ZF_1: ~1e‑13 µV, rounding); in blink‑cleaned sections the IC numbers changed and EEG rows 1–32 moved by 0.0004–0.044 (relative norm over the section) where the old final already used the current rules (HM_2, SS_1) and by 0.08–0.93 elsewhere (RX_2, RC_1, RC_2: the frontal pick and the badTS‑free training window also changed). Everything not downstream of an ICA (respiration, ECG, events, `bmObj`, `heartBeats`, `RRint`, behavior rows) reproduced exactly except where the engine itself changed (the rev13 onset floor moved one DL_1 onset by 4 ms, commit `e8c1925`) — and, since 2026‑10‑22, where the breath merge joins breaths. The validation rerun (R2024b on the lab) also found 12 `bm_*` columns (flows, volumes, smoothness, curvature) differing at ~1e‑16 relative from finals made on another machine / release in the sweep, sep, echem and HM_2 sessions although `bmObj`, the breath counts and the carried rows were identical: compare `bm_*` columns with a tolerance.
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
  `applyBreathMerge`, `appendBreathMergeCols`, `carryRespFromFinal` / `carryFinishFromFinal`, `isSessionDone`, …) instead of inline copies; task logic lives in `tasks/<task>/`. A fix
  goes into the shared function so it reaches every task — never patch one main's copy. New capability goes
  into shared functions that every relevant main calls.
- **Prefer strict over flexible:** if the data aren't the expected shape, let it error — a loud failure
  surfaces a real data problem. Keep per‑session photodiode special cases explicit (`switch sessID` blocks).
- **Post‑hoc edits that live only in a final — a rerun from raw drops them** (found in the G2 reprocessing,
  2026‑10‑21). Three batch tools change finals in place after the pipeline: `reconstructPacedBlocks`
  (+ `qc5_reconSignFix`) overwrite the `rsp` row of the `slowBreath` / `slowRec` / `cyclicSigh` playback blocks of
  breathingTask finals (`outDat.reconstructedBlocks`, §6.6), and `resegmentAll_zlp` re‑segments breathingTask /
  EmotionalMovieTask / alternating6Blocks / breathingTasks_separate finals from the stored trace (its
  `ZLP_FLIPFIX` / `ZLP_RSPIDXFIX` write a decided `rspFlip` / `rspIDX` into the final — the sheet must carry the
  same value or a rerun reverts it). cue / thresh / O15 finals are not touched by any of them. Before rerunning a
  breathingTask session from raw, look for the field (`h5info(f, '/outDat/reconstructedBlocks')` or
  `'/chanDat/reconstructedBlocks'`, or `fieldnames`, §2). `reconstructPacedBlocks` is not a safe redo as it
  stands: it has no session filter and, for a final without the field, first copies the pristine pre‑reconstruction
  backup `E:\reprocBackup_260824\recon\<id>_breathingPreproc.mat` over the live final, i.e. over a fresh rerun.
  **The rerun path for such finals is the respiration carry (§8, 2026-10-22):** with `ZLP_CARRY_FROM` set the main takes every `rsp*` row, `targTrace` and `reconstructedBlocks` from the previous final instead of rebuilding them (VW and ADtest: old respiration and target traces + new EEG), then re-segments the carried trace with the engine and the merge rule. Rules: only respiration rows, `targTrace` and `reconstructedBlocks` are carried — a re-segmentation done by `resegmentAll_zlp` is not (the rerun segments the carried trace again), and a `ZLP_FLIPFIX` / `ZLP_RSPIDXFIX` decision must be in the sheet before the rerun (the carry errors `rspMismatch` when the final and the sheet disagree; no automatic override). Fields only the previous final has and the pipeline cannot produce (post-hoc analysis fields such as `bestMac`, `ridgeInfo`) are kept in `outDat.carriedFromPrevFinal` and describe the previous data; a field the pipeline can produce but did not in this run (the old `blinkICA` when blink removal is now off, ...) is not carried, only named in `outDat.carry.stageFieldsNotCarried` (`shared/carryPipelineFields`, §8). A post-hoc tool that changes anything else in a final loses it to a rerun.
- **processedBehavior CSV column order** follows `behDat`; reruns after the 2026‑09‑02 raw‑volume backfill put
  `bm_inhaleVolumesRaw` / `bm_exhaleVolumesRaw` next to the other `bm_*` columns (49–50) and `goodBreath … RR_max_min`
  last, where the in‑place backfilled finals had the two volume columns at the end. Same names and values — address
  columns by name (the `closed-loop-respiration` scripts do; `HRV_resid` is joined on session + row in file, so keep
  row order). Finals from the 2026‑10‑22 rerun on have four more columns (`nInhalePulses`, `breathInhaleArea`, `breathExhaleArea`, `exhaleInhaleRatio`, before `bm_*`) and fewer rows wherever breaths merged: anything joined by row position (`HRV_resid`) must be recomputed for them.
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

### Full EEG rerun (2026-10-22; `batch/fullRerun/`, branch `fullRerun-261022`)

**What and why.** User, 2026-10-22: rerun the EEG preprocessing of every EEG final with the fixed detector (`'fixed'`) for standardisation, keep the repaired respiratory traces, and re-segment the breaths with the current engine plus the merge rule (§5). Out of scope: the vipassana study and the ADmeditation sessions (handled separately), all finals of `260917_OBE_NWU_RC_2`, `261019_INR_NWU_DD_1` (never processed), and the 32 sniff‑task finals without an EEG stage (13 O15, 12 thresh, 7 cue: nothing to rerun). **The 8 breath‑type finals without an EEG stage are in the rerun** (user, 2026‑10‑23: 1 breathingTask, 6 breathingTasks_separate, 1 EmotionalMovieTask): they get the respiration carry and the breath re‑segmentation with the current engine plus the merge rule (and the four merge columns in `behDat`) but have no EEG stage to rerun — they are in the manifest beside the 210 EEG finals below (`E:\claudeWork\rerun1022\manifest.csv`, rebuilt 2026-10-23: 218 rows, `hasEEG = 0` on the 8; sets validation 21 / sniff 96 / breath 101). Manifest of 2026-10-22, the 210 EEG finals, 102 GB — cue 45, thresh 29, O15 28, detectNoOdor 1, cueTask3 1, breathingTask 58, breathingTasks_separate 19 + 1 echem, EmotionalMovieTask 13, alternating6Blocks 8, pacedBreathing 2, respiratorySweep 4, airPuff 1; 29 are guess rows (run with `ZLP_ALLOW_GUESS_RUN=1;ZLP_ALLOW_GUESS_RUN_ALL=1`, `paramSource` untouched). Order: a validation set (19 finals on 2026-10-22, 22 rows in the 2026-10-23 manifest (the 19 EEG finals + 3 non-EEG breath finals): the shortest EEG final of each task kind + the rule cases: held-button O15, GH_2 O15, DL_1 breathing and sep, BW_2 sep, VW, SS_1 thresh and sep), a gate, then cue / thresh / O15 / detectNoOdor / cueTask3, then the breath-type tasks. Progress lives on the lab (`fr_status.ps1`), not in this file.

**Respiration carry** (`ZLP_CARRY_FROM=<full path of the previous final>` or `P.carryFrom`; optional `ZLP_CARRY_SHA256`). A rerun from raw cannot reproduce a respiration trace repaired after the pipeline (§7), so every main calls `[outDat, CS] = carryRespFromFinal(outDat, P)` right after `runSharedCore` and `outDat = carryFinishFromFinal(outDat, CS)` before the guess gate / save (breathingTasks_separate: one `carryRespFromFinal` per condition recording with its section, then `carryFinishFromFinal(outDat, CS, secRecords)`); without the variable both return at once and the main runs exactly as before. With it, strictly (any mismatch errors `carryOpenFinal:*` / `carryRespFromFinal:*` / `carryFinishFromFinal:*`, nothing is saved): same `fs`, sample count (a section: its span in the old `sections` table, same label and position), session id and `rsp*` labels in the same order; the old final's `rspIDX` / `rspFlip` equal the sheet's; the SELECTED respiration channel (`rspIDX`) of the pipeline's own run correlates r ≥ 0.90 with the carried one, taken on the respiration band (< 5 Hz, 4th‑order Butterworth, zero phase) and outside `reconstructedBlocks` (another or shifted recording fails; the self‑test rejects a selected row shifted by 2 s); the other `rsp` rows are carried too and only warn (`carryRespFromFinal:auxRow`, `carry.checks.auxLow`) below 0.90, and `carry.checks.rBroad` keeps every row's broadband r — an auxiliary channel with strong 60 Hz pickup, which the 60/120/180 Hz notch of finals made before July 2026 had removed, correlates only ~0.4 broadband although it is the same recording (validation: `250929_Dupi_NMH_GH_2` rsp2 0.41 broadband, 0.98 below 5 Hz; the old gate failed that final); the file's SHA-256 equals `ZLP_CARRY_SHA256`. Then every `rsp*` row is REPLACED by the previous final's, its `targTrace` row is appended (breathingTask then skips `alignTargetBreathingTraceSimplify` — its `shadowResp<n>.jpg` figures are not regenerated; respiratorySweep skips building the row from the log) and `reconstructedBlocks` is copied; breaths are then segmented (engine + merge) and sniffs detected on the carried trace. At the end every carried row must still be sample-identical to the previous final's (`rowChanged`; sep: the rebuilt `rspSelected` too). The previous final's other fields that the new run lacks are sorted by `shared/carryPipelineFields`, the list of every top-level `outDat` field the pipeline can produce in any task or configuration (EEG / blink / macro / ECG / segmentation / task records; `batch/testCarryRespFromFinal` rescans the code and fails when a written field is missing from it): fields on the list are stage outputs of the previous run — e.g. the old `blinkICA` of `251027_Dupi_NMH_DL_1`, whose blink removal is now off (likewise `EEGCleaningInfo`, `dataLap`, ... in a run without an EEG stage) — and are NOT carried (they would present the previous run's results as this run's; only their names go to `outDat.carry.stageFieldsNotCarried` — scratch rerun of the DL_1 breathingTask final, 2026‑10‑23: no `blinkICA` and no `carriedFromPrevFinal` in the new final, `stageFieldsNotCarried = {blinkICA}`); fields not on the list are post‑hoc additions and go to `outDat.carriedFromPrevFinal` (in the 252 finals surveyed on 2026‑10‑22 these are `bestMac`, `bestMacMethod`, `powerPhaseContinuity`, `ridgeInfo` of the O15 finals GH_2 / PD_1, and `reconstructedBlocks`, which the carry copies itself for a single recording and keeps here only for a sep final). The source must not be the live final (the main saves there); one id per run. Records: `outDat.carry`, `outDat.carriedFromPrevFinal` (§6.1). A final made before July 2026 went through the then‑applied 60/120/180 Hz notch: with the carry its respiration rows keep that state while every other row (EEG, macros, ECG, event) is rebuilt un‑notched, and the finals' generation cannot be read from the file date (a post‑hoc edit updates it) — compare `carry.checks.rBroad` with `carry.checks.r` (a large gap = line pickup in the new run's own row, the old one notched). Self-tests: `batch/testCarryRespFromFinal.m` (41 checks: every strict error, the < 5 Hz gate, sep sections, the stage‑field exclusion on the DL_1 case, the repo scan against `carryPipelineFields`) and `batch/testBlocksOfMergedBreaths_pacedBreathing.m` (9).

**The driver** (`batch/fullRerun/`, own README): `fr_driver.ps1` runs on the lab, started detached through WMI `Win32_Process.Create` (`fr_launch.ps1`: survives the ssh session and VPN drops; below-normal priority; one MATLAB at a time, in a kill-on-close job object) and works through `manifest.csv` with a persistent per-final state machine in `E:\claudeWork\rerun1022\state\`: `pending → backedUp → moved → running → verified → done`, `failed` after two attempts, or `needsDecision` after a deterministic failure (the carry refuses the previous final, or the carry gate — not retried, not counted by the circuit breaker); the original is restored in both. Per final: back up to `E:\reprocBackup_261022\<task>\<sessID>\` with SHA-256; take the machine‑wide MATLAB lock and the sheet lock (the lab's `withSheetLock.ps1`, held for the whole run, BEFORE the move) and copy the master sheet to `Admin\Data\sheetBackups\dataTracking_backup_<yyMMdd_HHmmss>_rerun1022.xlsx`; move the final to `<root>\<id>\preProc\superseded_261022\` (the carry source); run the makeOutDat (breathing / cue / thresh / movie / alt6 / detectNoOdor / cueTask3) and the main with `ZLP_MAKEOUTDAT_ONLY` / `ZLP_MAIN_ONLY` = the id, `ZLP_CARRY_FROM`, `ZLP_CARRY_SHA256`; `fr_verify.m` then checks the new final (the checks above — `fs==500`, `moreThan1`, `manOnset`, breathing extras — plus `EEGCleaningInfo.mode 'fixed'` in every section, blink ICs by the frontal rule, carried rows sample-identical, the carry gate on the recorded same-recording evidence (finite correlation of the selected channel; thresholds in `batch/fullRerun/README.md`), `dataLapGeometry` present and `dataLap` not common-mode, `breathMerge` for breath-type tasks, no `paramSource` change in the master sheet) and writes the old-vs-new comparison (`compare\<key>.json`, `compare\summary.csv`); any failure restores the previous final. A final found `moved` / `running` at (re)start is restored (a partial new file is moved aside to `failed_<time>_<file>`, never deleted; the original is hash-checked against the backup) and redone from the move step. Safeguards: pause on low disk (< 40 GB free after a backup; E: backups are pruned only for hash-verified superseded copies), on a changed repo HEAD or dirty tracked files (the lab worktree must hold the final commit before the first start), on low memory, or when `git` cannot be run (the code‑freeze guard); a PERSISTENT validation gate (nothing after the validation set starts — also not after a restart or a reboot — until `control\GATE_OPEN` exists); circuit breaker after 4 failed finals in a row (8 `needsDecision` in a row also stop it); stall watchdog (a MATLAB is killed only when idle past `timeoutMin`, or at 4×); R: probed every 45 s while MATLAB runs and re-mapped by the driver itself with `WNetAddConnection2` from a user-scope DPAPI blob that was delivered through ssh stdin (`fr_receiveCred.ps1`; the password is never on a command line, in a log or a file; the driver deletes the blob when the batch finishes). A reboot of the lab desktop stops the driver (`fr_status` says NOT RUNNING; `fr_start` resumes).

**Commands** (home machine, VPN up; in `batch\fullRerun\home\`): `.\fr_start.ps1 -PlanOnly [-Set validation]` (show the plan), `.\fr_start.ps1` (deliver the credential if the lab has none, start detached; the real universe arms the validation gate by itself — `-HonorGates` is the same, `-NoGate` the deliberate bypass), `.\fr_status.ps1 [-Watch 60]`, `.\fr_start.ps1 -Continue` (open the gate; `-CloseGate` re‑arms it), `.\fr_stop.ps1 [-Wait 90 | -Now | -Pause | -Resume | -ClearCred]`, `.\fr_start.ps1 -Restart | -RetryFailed | -RefreshCred`, `.\fr_start.ps1 -Scratch -Set validation` (the same loop on E: copies and a staging sheet).

**Scratch validation (2026-10-22/23).** Before the real start the whole state machine (backup + SHA-256, move, makeOutDat + main with the carry, `fr_verify.m`, restore) ran in the scratch universe — copies on E: and a staging sheet, R: read-only, no master-sheet write, no sheet lock — on 35 distinct finals covering every task kind and rule case (`.\fr_start.ps1 -Scratch -Keys <comma list> -GapSec 5`, status `.\fr_status.ps1 -Scratch`; a scratch final costs about 3 GB on E: — mirror, backup and two finals — so delete `scratch\lc` and `scratch\backup` afterwards). 34 passed first time; 1 failed on the carry's same‑recording gate (O15 GH_2: an auxiliary channel with 60 Hz pickup, fixed — gate wording above) and passed after the fix. All 35 verify ok: carried `rsp*` / `targTrace` rows sample‑identical to the previous final in 35/35; `EEGCleaningInfo.mode 'fixed'` and the frontal blink rule everywhere; `dataLap` common‑mode share 0.001–0.029 (previous finals 0.68–0.98); four finals made twice from the same R: original are identical (§5, §7); bad‑channel lists changed in 3 of 35 (§5); `finalOnset`, `TTL` and the task columns of `behDat` identical in every sniff‑task final; blocks, `TTL` and labels of both pacedBreathing finals changed under the merge‑first order and are identical to the previous finals since the blocks are inferred before the merge (§1; re‑proven 2026‑10‑23). Time: MATLAB 52–361 s per final (ADtest 791 s while the lab was shared); fit over 33 timed finals 98 s + 2.6 s per recording minute, i.e. about 10 h of MATLAB for the 210‑final manifest (5972 recording minutes); with the backups (102 GB at 57 MB/s, ~30 min), the verifier (~10 s) and the 45‑s gap per final, 14–17 h on an idle lab — the driver runs at below‑normal priority, so another job's MATLAB slows it considerably. Not exercised in the scratch universe: file moves on R:, the real sheet lock, `writeParams` against the master sheet, an R: / VPN drop in mid‑run (the driver's dummy‑row tests cover them), O15 `260316_Dupi_NMH_PD_1`, a cyclicSigh session, `dropTrials`, a held‑button session with resolved collisions, the TI_1 movie. Expected scratch‑only differences: `OGdataDir`, `threshDesign.behFiles`, `behSource`, `clipCheck.csvFile` paths.

**Generation of a final — read the fields, not the date.** No `EEGCleaningInfo` = the legacy detector (before 2026-10-14); `EEGCleaningInfo.mode` `'fixed'` / `'band'`; `blinkICA` with the frontal rule (2026-10-12 on); `dataLapGeometry` = Laplacian on the sphere (2026-10-22 on; otherwise a common-mode `dataLap`); `blinkICA.rng` / `spikeCleanInfo` = reproducible ICAs; `breathMerge` = the incomplete-exhale merge was applied; `carry` = made by the rerun with the respiration carry.

---

## 9. File map

| Folder | Contents |
|---|---|
| `config/` | `labPaths.m`, `applyParams.m` / `writeParams.m` / `setPreProcX.m` (+ its thin wrappers `writePreProcX.m` / `clearPreProcX.m`), `writeSheetSep.m` (breathingTasks_separate sheet writer), `writeSheetADmed.m` (ADmeditation summary cells in its own sheet), `sepConditionInfo.m` (the sep condition vocabulary), `eegLocs_standard_coords.csv` |
| `pipelines/` | `preprocessAll.m` + the `*PreProc_main.m` entry points (one per task) |
| `pipelines/makeOutDat/` | raw → intermediate ingestion (`breathing` / `cue` / `thresh` / `emotionalMovie` / `alternating6Blocks` / `detectNoOdor` / `cueTask3`) |
| `shared/` | the shared signal core: `runSharedCore` (`downsample_data` → `preprocess_eeg` → `preprocess_macros`), `assembleOutDat`, `preprocess_respiration_wholetrace`, `detect_sniffs_from_TTLs`, `refine_onsets_with_phase`, `behDatFromSniffs`, `paramCheck` / `guessFigDir`, EEG/spike/onset helpers (the EEG detector `removeNoiseChansVolt` + `removeNoiseChansVolt_legacy`, deployed together with `preprocess_eeg` and `concatSections`, §5); the breath engine `segmentBreaths_zlp` (+ `prepBreathTrace_zlp`, `findInhaleOnsets_zlp`); the breath‑type stage helpers `behDatFromBreaths`, `appendBmFeatureCols`, `runECGStage`, `fillNaNHRV`, `isSessionDone` and the ECG/QC helpers `processECG` / `buildECGz` / `detectBeats` / `paramCheckECG` / `flagBadBreaths`; the breath merge `mergeIncompleteExhales` (rule) ← `applyBreathMerge` (stage) + `appendBreathMergeCols` (`behDat` columns); the respiration carry `carryOpenFinal` / `carryRespFromFinal` / `carryFinishFromFinal` (§8) with `carryPipelineFields` (every top‑level `outDat` field the pipeline can produce: the fields a carry never copies); `zlpSeed` (stable FNV‑1a seed from a text key); `findLoadDataScript` (LoadData provenance), `toTargetSamples` (raw → 500 Hz sample indices), `alignLogToRaw` (SniffLogic log → raw clock; alternating6Blocks + respiratorySweep), `robustAvgRef` (robust common‑average reference of the scalp rows; used by `vipassana` at ingestion) |
| `tasks/<task>/` | each task's `assembleRaw_<task>.m`, `build_behavior_table_<task>.m`, task helpers (breathing: `process_respiration_breathing`, `alignTargetBreathingTraceSimplify`, `plotBreathLengths`, `mergeCyclicSighBreaths` (cyclicSigh refractory merge), `tidyImport_waveExp_matlab` (writes the processedBehavior CSV the breathing makeOutDat reads); cue: `outMat_to_table`, `cueTrialType` (hit / miss / cr / fa / skip / noCue, shared with cueTask3); cueTask3: `parseEvents_cueTask3`, `build_behavior_table_cueTask3`, `plotSniffTrains_cueTask3` (its loader is the cue one, `assembleRaw_cueTask(S, 'cueTask3')`); thresh: `loadBeh_multiRun_threshTask`, `splitRuns_threshTask` (the multi‑run design); O15: `detect_ttls_O15`, `assembleOutDat_O15extras`, `parse_O15_events` (rail‑referenced event parse), `heldButtonFreeSniffs_O15` (held‑button free sniffs), `resolveHeldButtonSniffs_O15` (held‑button: one free sniff per inhale after the refinement + the per‑trial figures); emotionalMovie: `detect_ttls_emotionalMovieTask`, `matchClipsToPsychoPy` (PsychoPy clip log cross-check, norms, clock segments), `findPsychoPyClipLog_emotionalMovie` (locates the clip log); alternating6Blocks: `parse_mindfulBreathing`, `parse_sniffLogicLog`; respiratorySweep: `buildSweepTTL` (called by the session LoadData scripts), `parse_sweepLog`, `parse_sweepRatings`, `plotBlocks_respiratorySweep`; breathingSeparate: `concatSections`, `sepSectionRsp`, `sepSectionP` (one recording's per‑condition parameters); pacedBreathing: `inferBlocks_pacedBreathing`, `blocksOfMergedBreaths_pacedBreathing` (block of each merged breath), `plotBlocks_pacedBreathing`; vipassana: `assembleRaw_vipassana`, `artifactIndex_vipassana`, `inferBlocks_vipassana` (v1), `parsePhotodiode_vipassana` / `parseLog_vipassana` / `alignLog_vipassana` / `blocksFromMarks_vipassana` (v2 marked blocks), `probeRespViability_vipassana`, `checkRspPolarityRSA`, `plotBlocks_vipassana` (v1), `plotMarkedBlocks_vipassana` (v2), `build_behavior_table_vipassana`; ADmeditation: `LoadData_ADmeditation_claude` (the study loader, deployed to the study folder), `assembleRaw_ADmeditation`, `detectButtonPresses_ADmeditation`, `build_behavior_table_ADmeditation`, `plotQC_ADmeditation`; detectNoOdor: `parse_detectNoOdor_events`, `loadBeh_detectNoOdor`, `countInhales_detectNoOdor`, `plotQC_detectNoOdor`; airPuff: `parsePuffEvents_airPuff`, `detectHolds_airPuff`, `plotQC_airPuff`) |
| `batch/` | reusable QC / maintenance tools (not pipeline steps): `probeMontage` (verify a new LoadData channel map against the data), `readBrainVision` / `probeMontageBV` (the BrainVision‑source counterparts of the raw reader / `probeMontage`, used by `vipassana`), `probeSessionParams` / `probeECGpolarity` (measure guess parameters), `ecgUnreadableWindows` (measure the unreadable‑ECG windows typed into `P.ecgExcludeSec`, §5), `qc4`–`qc8` audits and figure generators, `qualityCheckOverlays`, `resegmentAll_zlp`, `reconstructPacedBlocks`, `guessParamsFromRaw` (measured guess parameters from extracted raw files), `testCarryRespFromFinal` (self-test of the respiration carry), `testBlocksOfMergedBreaths_pacedBreathing` (self-test of the pacedBreathing block carry‑over across the merge), `fullRerun/` (the lab-side driver of the 2026-10-22 full EEG rerun, §8: `fr_driver`, `fr_final`, `fr_lib`, `fr_native.cs`, `fr_scratch`, `fr_runFinal`, `fr_verify.m`, `fr_buildManifest.m/.ps1`, `fr_launch`, `fr_receiveCred`, `fr_withR`, `fr_lockholder`, `fr_statusLab`, `fr_stopLab`, `home/fr_start|fr_status|fr_stop`), `buildGuessReview.ps1` (guess-QC report from qc8 output; env `ZLP_QC8_OUT`, params `-IntroHtml -NewIds`; the report lives on R: under `Adam\Dupi_processing\guessReview_<date>\`, not in the repo) |
| `external/` | vendored dependencies: `breathMetrics/` (fork qhyang42 @9791153; unmodified) |

The pace × depth sweep analysis (`respiratorySweepAnalysis/`) now lives in its own repo, `../calibratedHRV`. The vipassana group analysis (`Vipassana_analysis/`) and the repeat-meditation analysis (`repeatMedSessionAnalysis/`) each live in their own repo too — `../vipassanaAnalysis` (github.com/adede1988/vipassanaAnalysis) and `../repeatMedSessionAnalysis` (github.com/adede1988/repeatMedSessionAnalysis). Both folder names are in `.gitignore` so neither can be re-added here: their results are per-participant files and this repository is public.

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
- **Unattended jobs (2026-10-22).** A process started inside an ssh session ends with it. For multi-day jobs start the process with WMI `Win32_Process.Create` (`batch/fullRerun/fr_launch.ps1`), let it map `R:` itself with `WNetAddConnection2` from a **user-scope DPAPI blob** delivered through ssh stdin (`fr_receiveCred.ps1`; user scope works under the ssh logon and in the detached child) instead of a password in an `-EncodedCommand` / command line, and run ad-hoc lab payloads that need `R:` with `batch/fullRerun/fr_withR.ps1 -Payload` (maps `R:` from the blob). Delete the blob with `fr_stop.ps1 -ClearCred` when no batch needs it (the driver deletes it when its batch finishes).

### Storage — where to read/write
- **`E:\` is the workspace.** ~880 GB free, read/write from SSH. Scratch, intermediates, backups, logs go here.
  Keep preproc data files and the mirrored folder structure on `E:` for future jobs.
- **`C:\` has only ~4 GB free — never use it for job I/O.**
- **Lab server (`R:` → `\\fsmresfiles.fsm.northwestern.edu\fsmresfiles`)** is not reachable by default from an
  SSH session (key‑based logons carry no network credentials). `cmdkey` / Credential Manager does **not**
  work over key‑based SSH (tested — don't retry). The older pattern, now **superseded for every unattended or repeated job** (it puts the password on the ssh command line; use the DPAPI blob and `fr_withR.ps1` of "Unattended jobs" above), was **explicit credentials inline, in a
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
  chat or a tracked file (for a one-off interactive step only: the base64 text is still on the ssh command line;
  batches deliver the password through ssh stdin into the lab's user-scope DPAPI blob, "Unattended jobs" above).
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

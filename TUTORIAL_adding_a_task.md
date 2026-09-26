# Tutorial — adding a new task to the pipeline

This pipeline is built so that a new experiment ("task") reuses the entire signal‑processing
core and only requires you to write the **task‑specific** pieces: how to load that task's raw
data, how to parse its events, and how to turn its behavior into a table. The shared stages are
**functions every main calls** — `shared/runSharedCore.m` right after assembly, then the shared
onset / breath / ECG helpers — never code copied into a main; task logic lives in `tasks/<task>/`.

Below, replace `myTask` with your task's short name (e.g. `odorMemory`).

---

## 0. The mental model

Each task is one row of this table:

| Stage | Shared? | File(s) |
|---|---|---|
| Session list + per‑session params | shared | `config/applyParams.m` (reads `dataTracking.xlsx`) |
| Raw load → `raw` struct | **task‑specific** | `tasks/myTask/assembleRaw_myTask.m` |
| (optional) photodiode/behavior ingestion → intermediate | **task‑specific** | `pipelines/makeOutDat/myTask_makeOutDat.m` |
| `raw` → common `outDat` | shared | `shared/assembleOutDat.m` |
| Downsample + filter → scalp‑EEG cleaning + Laplacian (if `hasEEG`) → macro bipolar + spike clean (if `hasMacros`) | shared | `shared/runSharedCore.m` (calls `downsample_data`, `preprocess_eeg`, `preprocess_macros`) |
| Respiration features + sniff onsets | shared | `shared/preprocess_respiration_wholetrace.m`, `detect_sniffs_from_TTLs.m`, `refine_onsets_with_phase.m` |
| (breath‑based task) per‑breath segmentation + ECG/HRV | shared | `shared/segmentBreaths_zlp.m`, `runECGStage.m`, `behDatFromBreaths.m`, `appendBmFeatureCols.m` |
| Behavior table | **task‑specific** | `tasks/myTask/build_behavior_table_myTask.m` |
| Orchestration (the loop) | **task‑specific header, shared body** | `pipelines/myTaskPreProc_main.m` |

The existing `*PreProc_main.m` scripts mark their `TASK‑SHARED` and `TASK‑SPECIFIC`
sections in comments — read `cueTaskPreProc_main.m` (a per‑sniff task) or
`pacedBreathingPreProc_main.m` (a compact per‑breath task; `breathingTaskPreProc_main.m` is the
richest) as your template.

---

## 1. Register the task in `applyParams` (and `preprocessAll`)

`config/applyParams.m` maps task names in two small `switch` helpers. Add your task to both:

- **`taskKey`** — the *caller* spelling → internal canon, e.g. `case 'mytask', k = 'myTask';`
- **`canonTask`** — the *sheet's* `Task` column value(s) → the same canon, e.g.
  `case {'mytaskodor','mytask'}, k = 'myTask';`
- **`taskCallerKey`** — canon → the `P.task` string written into `outDat`.
- In the **Mode B** section, add a `case 'myTask'` that sets the task‑specific params — at
  least `P.hasMacros`, which `runSharedCore` reads. The local helpers cover the usual cases:
  `sniffParams` (per‑sniff tasks: `hasMacros = true` + the sniff‑detection windows `respThresh` /
  `cuedBackBuff` / `adjWin`) and `ecgParams` (breath‑based tasks: `hasMacros` from the sheet +
  `beatSpec` / `getBeats`). The common params (`fs_target=500`, `rspIDX`, `rspFlip`, `hasEEG`,
  `spikeClean`, …) are set for every task already.

Mirror the same two mappings in `pipelines/preprocessAll.m` (`taskKey` / `canonTask`) and add
your task to the `tasks` list and the run block.

Then add rows for your sessions to `dataTracking.xlsx`: `Subject ID`, `Task` (your sheet value),
`Type` (`Dupi`/`OBEControl`/`EEGbreathing`), `Raw Data Extracted` (non‑blank), plus the parameter
columns you rely on. **No code lists sessions — the sheet is the source of truth.**

---

## 2. Write `assembleRaw_myTask.m`

Return a `raw` struct that the shared assembler understands. `shared/assembleOutDat.m` reads
exactly these fields:

```matlab
function raw = assembleRaw_myTask(S)
%   S.id, S.root, S.fig  provided by the main loop
    raw.data   = ...   % [nChan x nSamp]  (channel-major, time along dim 2)
    raw.labels = ...   % 1xN cell of channel-label strings, parallel to rows of raw.data
    raw.fs_raw = ...   % raw sampling rate (Hz); the shared core resamples to 500
    raw.beh    = ...   % a MATLAB table of raw behavior (becomes outDat.behDat pre-build)
    raw.TTL    = ...   % OPTIONAL: event-sample table/vector; include only if you have it
end
```

Channel‑label conventions the shared core relies on (match these so the shared stages find
your channels): scalp EEG uses exact 10‑20 names in **rows 1–32**; respiration labels contain
`rsp`; macro contacts contain `macro`; photodiode/event channels contain `event`; ECG contains
`ECG`.

If your task can be loaded straight from a single raw file (like `O15` or `pacedBreathing`), you
can skip the `makeOutDat` step entirely and do the load here.

The raw file itself comes from the session's LoadData script (`<root>\<id>\*LoadData*.m`; one
written by Claude is `LoadData_<id>_claude.m`, next to the lab's own). Verify its channel map
against the data with `batch/probeMontage.m` before extracting, and have it store
`curDat.loadFile = [mfilename '.m']` so `shared/findLoadDataScript` can record provenance.

---

## 3. (Optional) Write `myTask_makeOutDat.m`

If your task needs a photodiode/TTL parse and behavior stitching before the main pipeline (like
`cueTask`/`threshTask`), copy `pipelines/makeOutDat/cueTask_makeOutDat.m` as a template. It:

1. bootstraps the repo root + `labPaths`, then `cfg = applyParams('myTask','makeOutDat')`;
2. loops sessions, skipping any that already have an intermediate `.mat`;
3. parses the `event` channel into TTLs, loads + stitches behavior into a table;
4. saves `<id>_myTaskPreProc.mat` (the intermediate).

Keep the per‑session photodiode special‑cases explicit (the existing scripts have a `switch
sessID` block for sessions with unplugged DAQs, extra pulses, etc.). Convert raw‑rate TTL sample
indices to the final 500 Hz with `shared/toTargetSamples(idx, fsRaw, 500)`, never a hard‑coded ratio.

If your task's behavior comes from the psychopy `mindfulBreathing` CSV (like `breathingTask`),
convert it first with `tasks/breathing/tidyImport_waveExp_matlab.m` (set `ZLP_TIDY_IDS` to the
session ids): it writes the processedBehavior CSV that `breathingTask_makeOutDat` reads from
`labPaths().codePre` (`closed-loop-respiration\` or `experiment_EEGsync\processedBehavior\`).

---

## 4. Write `build_behavior_table_myTask.m`

For a **per‑sniff** task, start from the shared six columns and broadcast your behavior onto
each detected sniff:

```matlab
function behDat = build_behavior_table_myTask(sniffs, rawBeh)
    behDat = behDatFromSniffs(sniffs, {"cued"});   % sniffOnset,n,wiTriali,TTLoffSet,sniffType,sniffLabel
    for ii = 1:height(rawBeh)
        idx = find(behDat.n == ii);
        behDat.myVar(idx) = rawBeh.myVar(ii);      % ... one column per behavior field
    end
end
```

`shared/refine_onsets_with_phase.m` later appends `adjust`, `finalOnset` (**use `finalOnset`
for epoching**), and a NaN `manOnset` placeholder for manual QC. A **per‑breath** task instead
builds its table from the shared 14 base columns, `behDatFromBreaths(bmObj, nSamp, fs)`, adds its
own columns, and appends the `bm_*` features with `appendBmFeatureCols(outDat, callerTag)` (see
`tasks/pacedBreathing/build_behavior_table_pacedBreathing.m`).

---

## 5. Write `myTaskPreProc_main.m`

Copy `pipelines/cueTaskPreProc_main.m` and change **only** the `TASK‑SPECIFIC` lines:

```matlab
% ---- bootstrap + labPaths (shared boilerplate) ----
zlpHere=fileparts(mfilename('fullpath')); zlpRoot=zlpHere;
while exist(fullfile(zlpRoot,'config','labPaths.m'),'file')~=2, zlpRoot=fileparts(zlpRoot); end
addpath(genpath(zlpRoot));
L = labPaths(); addpath(genpath(L.eeglab));
EEGLOC = readtable(L.eegLocCsv);

cfg = applyParams('myTask','main');
for s = 1:numel(cfg.sessionIDs)
    S.id = cfg.sessionIDs{s}; S.root = cfg.root{s}; S.fig = fullfile(L.figPath, S.id);
    P = applyParams('myTask', S.id);

    raw    = assembleRaw_myTask(S);        % <-- TASK-SPECIFIC
    outDat = assembleOutDat(raw, S, P);    % shared from here down — DO NOT EDIT

    outDat = runSharedCore(outDat, P, EEGLOC);   % downsample, EEG (hasEEG), macros (hasMacros)
    R = preprocess_respiration_wholetrace(outDat);
    sniffs = detect_sniffs_from_TTLs(R, P, outDat);
    outDat.moreThan1 = 0;                                   % done-sentinel
    outDat.rspIDX = P.rspIDX; outDat.rspFlip = P.rspFlip;

    outDat.behDat = build_behavior_table_myTask(sniffs, raw.beh);   % <-- TASK-SPECIFIC
    outDat = refine_onsets_with_phase(outDat, R, P);

    save(fullfile(S.root, S.id, 'preProc', [S.id '_myTaskpreproc.mat']), 'outDat', '-v7.3');
    writePreProcX(P, S.id);
end
```

**Rules of thumb**
- Call `runSharedCore` right after `assembleOutDat` and reuse the shared stage helpers (for a
  per‑breath task: `segmentBreaths_zlp`, `runECGStage`, `isSessionDone` — see
  `pacedBreathingPreProc_main.m`) instead of copying code into the main, so a bug fix in the shared
  function reaches every task.
- Set `outDat.moreThan1` before saving; the mains treat it as the "already done" sentinel.
- Honor the **guess gate**: when `P.paramSource` is `guess`, call `paramCheck`, save the QC
  figures, and `error(...)` before writing so a human verifies channel/onset choices; promote
  the row to `curated` and re‑run to actually save.

---

## 6. Test on one session, then validate the output

```matlab
raw = assembleRaw_myTask(struct('id',id,'root',root,'fig',fig));   % does it load & label?
% run the main for a single session, then:
s = load(finalPath); fn = fieldnames(s); outDat = s.(fn{1});
assert(isfield(outDat,'moreThan1'));            % pipeline completed
assert(ismember('finalOnset', outDat.behDat.Properties.VariableNames));
assert(ismember('manOnset',   outDat.behDat.Properties.VariableNames));
isRsp = cellfun(@(x) contains(x,'rsp'), outDat.labels);   % respiration is findable
```

A file is **fully processed** iff it has `outDat.moreThan1`. Index channels by label and
`behDat` columns by name (never by numeric position).

---

## Checklist

- [ ] `applyParams`: `taskKey`, `canonTask`, `taskCallerKey`, Mode‑B `case` (sets `P.hasMacros`)
- [ ] `preprocessAll`: `taskKey`, `canonTask`, task in the run list
- [ ] `dataTracking.xlsx`: session rows + parameter columns
- [ ] per‑session LoadData script (Claude's: `LoadData_<id>_claude.m`), channel map checked with `batch/probeMontage.m`
- [ ] `tasks/myTask/assembleRaw_myTask.m` returns `data/labels/fs_raw/beh` (+ optional `TTL`)
- [ ] `pipelines/makeOutDat/myTask_makeOutDat.m` (only if a raw→intermediate parse is needed)
- [ ] `tasks/myTask/build_behavior_table_myTask.m`
- [ ] `pipelines/myTaskPreProc_main.m` — calls `runSharedCore` + the shared helpers (no inline copies)
- [ ] validated on one session (`moreThan1`, `finalOnset`, `manOnset`, channels findable)

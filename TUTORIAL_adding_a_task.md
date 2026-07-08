# Tutorial — adding a new task to the pipeline

This pipeline is built so that a new experiment ("task") reuses the entire signal‑processing
core and only requires you to write the **task‑specific** pieces: how to load that task's raw
data, how to parse its events, and how to turn its behavior into a table. Everything from
`downsample_data` onward is **shared and must stay byte‑for‑byte identical** across tasks.

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
| Downsample + filter | shared | `shared/downsample_data.m` |
| Scalp‑EEG cleaning + Laplacian | shared | `shared/preprocess_eeg.m` |
| Macro bipolar + spike clean | shared | `shared/preprocess_macros.m` |
| Respiration features + sniff onsets | shared | `shared/preprocess_respiration_wholetrace.m`, `detect_sniffs_from_TTLs.m`, `refine_onsets_with_phase.m` |
| Behavior table | **task‑specific** | `tasks/myTask/build_behavior_table_myTask.m` |
| Orchestration (the loop) | **task‑specific header, shared body** | `pipelines/myTaskPreProc_main.m` |

The four existing `*PreProc_main.m` scripts mark their `TASK‑SHARED` and `TASK‑SPECIFIC`
sections in comments — read `cueTaskPreProc_main.m` (a per‑sniff task) or
`breathingTaskPreProc_main.m` (the richest task) as your template.

---

## 1. Register the task in `applyParams` (and `preprocessAll`)

`config/applyParams.m` maps task names in two small `switch` helpers. Add your task to both:

- **`taskKey`** — the *caller* spelling → internal canon, e.g. `case 'mytask', k = 'myTask';`
- **`canonTask`** — the *sheet's* `Task` column value(s) → the same canon, e.g.
  `case {'mytaskodor','mytask'}, k = 'myTask';`
- **`taskCallerKey`** — canon → the `P.task` string written into `outDat`.
- In the **Mode B** section, add a `case 'myTask'` that sets any task‑specific params you need
  (e.g. sniff‑detection windows `respThresh` / `cuedBackBuff` / `adjWin`, or a `ttlMap`).
  The common params (`fs_target=500`, `rspIDX`, `rspFlip`, `hasEEG`, `spikeClean`, …) are set
  for every task already.

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

If your task can be loaded straight from a single raw file (like `O15`), you can skip the
`makeOutDat` step entirely and do the load here.

---

## 3. (Optional) Write `myTask_makeOutDat.m`

If your task needs a photodiode/TTL parse and behavior stitching before the main pipeline (like
`cueTask`/`threshTask`), copy `pipelines/makeOutDat/cueTask_makeOutDat.m` as a template. It:

1. bootstraps the repo root + `labPaths`, then `cfg = applyParams('myTask','makeOutDat')`;
2. loops sessions, skipping any that already have an intermediate `.mat`;
3. parses the `event` channel into TTLs, loads + stitches behavior into a table;
4. saves `<id>_myTaskPreProc.mat` (the intermediate).

Keep the per‑session photodiode special‑cases explicit (the existing scripts have a `switch
sessID` block for sessions with unplugged DAQs, extra pulses, etc.).

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
builds its own table (see `tasks/breathing/build_behavior_table_breathingTask.m`).

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

    outDat = downsample_data(outDat, P.fs_target);
    if P.hasEEG, outDat = preprocess_eeg(outDat, EEGLOC, P); end
    outDat = preprocess_macros(outDat, P);
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
- Everything from `downsample_data(...)` onward is the shared core — keep it identical to the
  other mains so a bug fix in one propagates to all.
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

- [ ] `applyParams`: `taskKey`, `canonTask`, `taskCallerKey`, Mode‑B `case`
- [ ] `preprocessAll`: `taskKey`, `canonTask`, task in the run list
- [ ] `dataTracking.xlsx`: session rows + parameter columns
- [ ] `tasks/myTask/assembleRaw_myTask.m` returns `data/labels/fs_raw/beh` (+ optional `TTL`)
- [ ] `pipelines/makeOutDat/myTask_makeOutDat.m` (only if a raw→intermediate parse is needed)
- [ ] `tasks/myTask/build_behavior_table_myTask.m`
- [ ] `pipelines/myTaskPreProc_main.m` — shared body left untouched
- [ ] validated on one session (`moreThan1`, `finalOnset`, `manOnset`, channels findable)

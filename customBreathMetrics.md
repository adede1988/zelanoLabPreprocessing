# customBreathMetrics.md — the ZLP breath-segmentation engine and its breathMetrics integration

**Status: LOCKED** (rev12b, 2026-08-28; per-breath QC fix 2026-08-29). This is the
segmentation engine behind every breathMetrics-based final in the lab
(breathingTask, emotionalMovieTask, alternating6Blocks, breathingTasks_separate).
It was designed in the August-2026 QC round 4 through ~20 live-reviewed
diagnostic generations and two forensic drill-downs, replacing both the stock
breathMetrics onset detector and the earlier "v3b" engine.

The vendored toolbox is `external/breathMetrics` (fork qhyang42/breathmetrics,
commit 9791153). **The toolbox itself is unmodified** — all customization lives
in this repo's own functions, which drive the unmodified `breathmetrics` class
through its public API.

---

## 1. What changed, in one paragraph

Stock breathMetrics finds inhale onsets as the last sample below a global
pause-band threshold in each trough→peak window (`findRespiratoryOnsetsNew`).
On this lab's recordings (amplitude-non-stationary, drifting baselines, paced
slow breathing reconstructed around a 0.1 Hz acquisition high-pass) that
placed onsets on exhale troughs, on inhale peaks, or mid-rise. The ZLP engine
replaces breathMetrics' **extrema detection** and **inhale-onset placement**
with a purpose-built two-stage algorithm (validity-ruled extrema + a
slope-walk "kneeBacktrack" onset), while keeping breathMetrics as the
**feature computer**: the locked landmarks are injected into an unmodified
`breathmetrics` object and every downstream feature (offsets, pauses,
durations, volumes, shape features, secondary statistics) is recomputed by
the toolbox's own sanctioned post-manual-adjustment path.

---

## 2. The new files

| File | Role | Status |
|---|---|---|
| `shared/segmentBreaths_zlp.m` | **The engine / integration point.** `[bmObj, bmFeatures] = segmentBreaths_zlp(rsp, fs, floorFrac, blankBelowFrac, cySpan)`. Runs the two functions below, then drives the breathMetrics object (§4) and emits the lab's `bmObj` (14-col) + `bmFeatures` (plain struct) contracts. | locked, in production |
| `shared/prepBreathTrace_zlp.m` | Stage 0–1: detection-trace conditioning + peak/trough detection. `[det, peaks, troughs, info] = prepBreathTrace_zlp(rsp, fs, mode, blankBelowFrac, cySpan, floorFrac)`. Three modes exist (`'pwl'`, `'conservative'`, `'twoscale'`); **`'conservative'` is the locked choice**. Outputs are bm-style sample-index vectors, strictly alternating. | locked (`conservative`) |
| `shared/findInhaleOnsets_zlp.m` | Stage 2–3: eligibility rules + one inhale onset per trough→peak pair. `[onsets, peaks, troughs] = findInhaleOnsets_zlp(det, fs, peaks, troughs, method, r2Factor, r3Factor, dipFrac, dipDur)`. Three methods exist (`'slopeGate'`, `'kneeBacktrack'`, `'changepoint'`); **`'kneeBacktrack'` with `(0.4, 1.25, 0.50, 0.10)` is the locked choice.** May *delete* spurious trough/peak pairs (returns the pruned extrema). | locked (`kneeBacktrack`) |
| `shared/segmentBreaths_breathMetrics.m` | The superseded "v3b" engine (bm-native detection + p25 band relocation). Kept for comparison reruns only — no production caller remains. | superseded |
| `shared/findAlternatingExtrema.m` | Round-3 extrema backbone. Dropped from the final flow (prep's own alternation replaced it). | deprecated |
| `batch/resegmentAll_zlp.m` | In-place re-segmentation of existing finals under the locked engine (backs up first; rebuilds behDat from the stored final — never from raw, because reconstructed paced traces live only in finals). | tooling |
| `batch/qc4_onsetDiagnostics.m` | The live-review diagnostic generator used to lock the algorithm (per-condition minute traces + onset-locked overlays + summary CSV). | tooling |
| `batch/qc5_flipAudit.m`, `batch/qc5_reconSignFix.m`, `batch/qc5_hrvRepair.m` | rspFlip A/B audit, reconstruction sign fixes, and the flagBadBreaths HRV repair pass. | tooling |

**Modified files** (call-site switches, no shared-core changes):

- `tasks/breathing/process_respiration_breathing.m` — now calls
  `segmentBreaths_zlp` (with the cyclicSigh span derived from behavior + TTL)
  and **no longer post-merges cyclicSigh bmObj rows** — the engine's
  keep-first peak rule replaces that legacy merge.
- `pipelines/alternating6BlocksPreProc_main.m`,
  `pipelines/emotionalMovieTaskPreProc_main.m`,
  `pipelines/breathingTasks_separatePreProc_main.m` — one-line engine swap.
- `tasks/breathing/flagBadBreaths.m` — 2026-08-29 fix: the `goodBreath==0`
  branch read `rrDat(bonset:boffset)` (the recording's first seconds) instead
  of the breath-local `curRR` window; and breaths whose 20-s QC window falls
  off a recording edge (or length ≥ 18 s) now read NaN instead of a silent 0.

---

## 3. The locked algorithm (all constants)

Detection runs on a normalized copy; **the stored signal is never modified**.
All thresholds below are in normalized units unless marked.

**Stage 0 — detection trace** (`prepBreathTrace_zlp`, common):
1. Linear NaN fill (nearest at edges).
2. 500 ms moving-average smoothing.
3. Amplitude normalization: divide by the 30-s moving std, floored at
   `floorFrac` (default 0.05) × its median.
4. Optional blanking: samples with local scale < `blankBelowFrac` × median are
   zeroed (used for hardware-attenuated stretches, e.g. MS's unplugged cannula).

**Stage 1 — extrema** (`'conservative'` mode):
5. Peaks: prominence ≥ 0.6, min separation 1.0 s; troughs identically on the
   inverted trace.
6. Peak validity: height ≥ 0.5 (floor), **and** some point ≥ 0.5 below the
   peak within the following 1 s (soft descent) — waived for peaks ≥ 1.0.
   Kills exhale-recovery crests before breathing pauses.
7. Strict trough→peak→trough alternation (more extreme of a same-type run wins).
8. Rise filter: trough→peak rise < 40% of half the local 30-s range ⇒ peak
   deleted (bump, not breath).
9. cyclicSigh span only (`cySpan`): peaks within 5 s — keep the FIRST (merges
   the paced double inhale at the segmentation level).

**Stage 2 — onset eligibility** (`findInhaleOnsets_zlp`; slope = derivative
smoothed 120 ms):
10. Rule 1 (not descending): `x(t) − x(t−0.33 s) > −0.2`.
11. Rule 2 (rising ahead): within `max(0.4 s, 25% of the pair duration)`
    ahead, the trace must exceed `x(t)` by > 0.4.
12. Eligible = rule 1 AND rule 2.
13. Spurious-pair pruning: a trough→peak window with no eligible sample is a
    false split — trough and peak deleted, region absorbs into the neighbor.

**Stage 3 — placement (`kneeBacktrack`), one onset per surviving pair:**
14. `dmax` = max slope over the whole window (walk stops); anchor slope scale
    = max slope over the window's SECOND HALF only.
15. Anchor: last point in the second half with slope ≥ 70% of that scale AND
    eligible; fallback: last eligible sample anywhere.
16. Walk back freely until slope < `0.50·dmax` sustained ≥ 0.10 s.
17. Clean sweep (only if the walk reached below trough + 10% of the swing):
    onset = last upward crossing of the trough/peak midpoint; done.
18. Late-landing extension (landing above trough + 35%): keep walking under
    slope < `0.05·dmax` sustained 0.15 s — accept only if that stop fired;
    on an edge run-out, revert to the main walk's landing.
19. Rule-3 refinement: slope contrast over −0.25..+0.5 s must satisfy
    max > 1.25 × max(min, 0.1); a contrast-less landing moves to the nearest
    contrasted sample.
20. Final eligibility snap: a non-eligible landing moves to the nearest
    eligible sample (either direction).

---

## 4. breathMetrics integration (how the pieces slot in)

The signatures were designed bm-style from the start: extrema and onsets are
**sample-index row vectors** with strict trough/peak alternation, exactly what
`breathmetrics` stores in `inhalePeaks` / `exhaleTroughs` / `inhaleOnsets`.

What replaces what:

| breathMetrics step | ZLP replacement |
|---|---|
| `findExtrema` / `findRespiratoryExtrema` | `prepBreathTrace_zlp` (stage 0–1) |
| `findRespiratoryOnsetsNew`'s inhale onsets | `findInhaleOnsets_zlp` (stage 2–3) |
| everything downstream (offsets, pauses, durations, volumes, shape, secondary) | **unchanged breathMetrics**, recomputed from the injected landmarks |

`segmentBreaths_zlp` drives the unmodified class like this (this is the
integration recipe if you want to reproduce it in another codebase):

```matlab
[det, pk0, tr0] = prepBreathTrace_zlp(rsp, fs, 'conservative', blankBelowFrac, cySpan, floorFrac);
[on, pkP, trP]  = findInhaleOnsets_zlp(det, fs, pk0, tr0, 'kneeBacktrack', 0.4, 1.25, 0.50, 0.10);
% pair bm-convention arrays: inhalePeaks(k) = first peak after onset k,
% exhaleTroughs(k) = first trough after that peak; trailing inhales with no
% following trough are dropped (bm's simplify convention)

bm = breathmetrics(det, fs, 'humanAirflow');
bm.correctRespirationToBaseline('sliding', 0, 0);
bm.inhalePeaks   = round(pkA);          % OUR extrema
bm.exhaleTroughs = round(trA);
bm.peakInspiratoryFlows  = respBC(round(pkA));   % respBC = bm.baselineCorrectedRespiration
bm.troughExpiratoryFlows = respBC(round(trA));
bm.findOnsetsAndPauses(0);              % bm derives exhale onsets + pauses from OUR extrema
bm.inhaleOnsets = on;                   % REPLACE inhale onsets with the locked ones
[exP, inP] = findRespiratoryPausesNew(respBC, fs, on, round(trA), round(pkA), nBINS);
% ... apply the same pad/clamp rules findOnsetsAndPauses uses, then:
bm.inhalePauseOnsets = inP;  bm.exhalePauseOnsets = exP;
bm.inhaleTimeToPeak  = (round(pkA) - on) / fs;
bm.manualAdjustPostProcess();           % toolbox recomputes offsets, durations,
                                        % volumes, shape + secondary features
```

`manualAdjustPostProcess` is breathMetrics' own "call this after manually
changing phase onsets" hook — using it means the whole feature set stays
toolbox-native and toolbox-versioned, computed from our segmentation with no
edits inside `external/breathMetrics`.

**Unit conventions carried through:** detection and all `bmFeatures`
flow/volume arrays are in windowed-normalized units (locally comparable
across epochs); the `bmObj` amplitude columns are re-sampled from the RAW
trace (60-s moving-mean baseline removed) at the detected indices, so they
stay in raw signal units. Onsets/peaks/troughs are sample indices at `fs`;
durations and time-to-peak are seconds.

**Outputs** (the lab contracts, unchanged from the previous engine):

- `bmObj` `[nBreaths × 14]` — the legacy layout (onset/peak/end/exhale-trough
  Y and times, length, amplitude, condition, index); breath spans inhale
  onset → next inhale onset; final inhale dropped.
- `bmFeatures` — plain struct (never the class object): the 18 per-breath
  arrays, `shapeFeatures` table, `secondaryFeatures`, plus a full
  `conditioning` provenance record (`engineVersion` = "zlp rev12b LOCKED...")
  and `bmObjBreathIdx` mapping bmObj rows to feature indices.

---

## 5. Caveats for future integrators

- The onset thresholds are calibrated to the **normalized** trace of stage 0;
  feeding raw-unit signals into `findInhaleOnsets_zlp` will not work.
- `findInhaleOnsets_zlp` can DELETE extrema (spurious-pair pruning) — always
  take `peaks`/`troughs` from its outputs, not from prep's.
- `cySpan` must be provided for recordings containing the paced cyclicSigh
  block; without it the double inhale is segmented as two breaths.
- Sessions without a usable ECG keep NaN HRV columns (`goodBreath`,
  `maxRR`, `minRR`, `RR_max_min`); breaths whose QC window falls off a
  recording edge are NaN (not 0) as of 2026-08-29.
- `segmentBreaths_breathMetrics.m` (v3b) and `findAlternatingExtrema.m` are
  kept only for historical comparison — do not build new callers on them.

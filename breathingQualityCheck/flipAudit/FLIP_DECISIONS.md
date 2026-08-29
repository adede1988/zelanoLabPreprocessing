# rspFlip / reconstruction-sign audit — decisions (2026-08-28)

**FOR USER REVIEW.** Method: every session with ≥10% trough-rate onsets in the
locked rev12b diagnostics (+ GA) was re-detected under BOTH the sheet rspFlip
and its inverse. Metrics per flip: n, %trough (Y0 < −0.5), median Y0, and the
correlation of the mean onset-locked waveform with the **EEG ZL audio-block
template** (user-designated textbook). Per-condition correlations were
computed for every audited session. Figures: `flip_<session>.jpg` (A/B rows);
full numbers in `qc5_flipAudit.csv`; raw log `E:\reprocBackup_260824\qc5_flip.log`.

## Decisions applied

| Session × task | Sheet flip | Decision | Evidence |
|---|---|---|---|
| 11 of 12 audited sessions (all tasks) | as sheeted | **keep sheet** | sheet flip wins template corr decisively in every natural block; inverse raises trough rates |
| `251027_Dupi_NMH_DL_1` × breathingTasks_separate (sleep recording) | +1 | **INVERTED → −1** (sheet updated, final resegmented at −1) | trough 23% → 7% under the inverse with equal/better template corr (0.88 → 0.90). NB: DL_1's *breathingTask* session is decisively keep-sheet (+1) — the sep sleep file is a separate physical recording. |
| `251110_EEG_NWU_GA` × breathingTask | −1 | **keep sheet; 7 reconstructed blocks sign-FIXED in the stored trace** | Global flip correct (audio 0.91 vs 0.40, naturalFocus 0.81 vs 0.65, fastFocus 0.90 vs 0.66). The inversion the user saw was per-block **reconstruction sign-resolution errors**: provenance showed mixed `sgn` within the session (impossible — CSV orientation is constant). cyclicSigh1-3, slowBreath1/3, slowRec2/3 (`sgn=−1`, `events-neg`) were stored inverted; slowBreath2/slowRec1 (`sgn=+1`) were correct — exactly reproducing "cyclicSigh upside down, slowResp looks OK" and the ~0 correlations of the mixed conditions. All 7 blocks flipped in place (about their local mean); provenance `sgn` updated, status `reconstructed-signfixed`; pre-fix final backed up at `E:\reprocBackup_260824\reconSignFix\`. **Post-fix verification:** overall trough 24%→12%; cyclicSigh corr −0.23→+0.32 (trough 1%), slowResp 0.01→0.32, slowPlayback 0.04→0.24. |

## Flagged for user review (NOT acted on — evidence too weak)

- **`251105_EEG_NWU_GL` slowBreath1-3**: the CSV `corr(voltage,target)` check
  reads +0.20/+0.20/+0.31 with `sgn=+1` used, which under rspFlip −1 would
  imply all three stored inverted. But the zero-lag corr(voltage,target)
  instrument proved unreliable (see below) and GL showed no display or
  trough-rate anomaly — left untouched.
- **`251009_EEG_NWU_SM` slowBreath2/3**: mixed `sgn` within session (−1 vs +1
  elsewhere) — same signature class as GA, but no corroborating display/audit
  evidence. Left untouched.
- **`260109_EEG_NWU_AA` cyclicSigh**: template corr 0.19 sheet vs 0.32
  inverted — ambiguous (its `sgn` is uniform, so no mixed-sign signature).
  Left untouched.
- **Instrument caveat**: zero-lag `corr(voltage, target)` inside the CSVs is
  systematically ~−0.2 for cyclicSigh in *every* participant (tracking lag
  flips cyclic correlations) and ~0 for slow blocks — it is NOT a reliable
  orientation test on its own. It was used only as corroboration for GA,
  where display evidence, template correlations, and the mixed-sign
  signature all converged. Full per-block dump:
  `E:\reprocBackup_260824\qc5_rsf_dry.log`.

## Downstream

All 62 breathMetrics-based finals re-segmented in place under the locked
engine (`segmentBreaths_zlp`, rev12b) with behDat rebuilt anew; pre-resegment
finals backed up at `E:\reprocBackup_260824\r12\<task>\`.

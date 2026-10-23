# batch/fullRerun - the lab-side batch driver of the full EEG rerun

Reruns the EEG preprocessing of every current EEG final (detector mode `'fixed'`, respiration / target-trace carry, current
breath engine + merge rule) on the lab desktop: **one final at a time, one MATLAB at a time, below normal priority, detached from
any ssh session, resumable, for days**. The pipeline code is untouched: the driver only moves finals, sets environment
variables, runs the existing `*_makeOutDat.m` / `*PreProc_main.m`, and verifies the result. Breath-type finals that have no EEG
stage (1 breathingTask, 6 breathingTasks_separate, 1 EmotionalMovieTask) are in the manifest too (`hasEEG = 0`): they gain the
current engine and the breath merge rule and keep their respiration (carry); their main runs without an EEG stage.

## Files

| file | where | job |
|---|---|---|
| `fr_buildManifest.m` / `.ps1` | lab | fresh listing of the finals + inventory cache -> `manifest.csv`, `manifest_excluded.csv` (the old manifest is kept as `manifest_prev_<time>.csv`) |
| `fr_driver.ps1` | lab | the loop (single instance, heartbeat, controls, circuit breakers, the persistent validation gate, code-freeze guard, backup pruning, `-Scratch`) |
| `fr_final.ps1` | lab | the per-final state machine (backup, sheet backup, move, run, verify, restore), no-op rows for tests |
| `fr_scratch.ps1` | lab | the scratch universe (copies of one session on E:, staging sheet) |
| `fr_runFinal.ps1` | lab | one manifest row, scratch universe (default) or `-Real` |
| `fr_verify.m` | lab | verification + old-vs-new comparison of one final, incl. the carry gate |
| `test_fr_verify.m` | home / lab | self-test of the carry gate on synthetic finals (no data) |
| `fr_lib.ps1`, `fr_native.cs` | lab | config, logging, atomic json, R: mapping, thread-wrapped fs ops, the machine-wide MATLAB lock, MATLAB launcher (kill-on-close job object, watchdogs), sheet-lock holder, git guard |
| `fr_lockholder.ps1` | lab | holds `dataTracking.xlsx`'s write lock through `E:\claudeWork\u1012\withSheetLock.ps1` |
| `fr_launch.ps1` | lab | starts the driver detached (WMI `Win32_Process.Create`), idempotent; looks at the real AND the scratch driver lock |
| `fr_receiveCred.ps1` | lab | stores the credential (ssh stdin) as a user-scope DPAPI blob |
| `fr_withR.ps1` | lab | runs a payload script with R: mapped from the blob (replaces `runRemote.ps1` for this job) |
| `fr_statusLab.ps1`, `fr_stopLab.ps1` | lab | status / stop requests / gate control |
| `home/fr_start.ps1`, `fr_status.ps1`, `fr_stop.ps1` (+ `fr_homelib.ps1`) | home | the three commands |

Lab state lives in `E:\claudeWork\rerun1022\` (manifest, `state\<key>.json`, `state\status.csv`, `failures.csv`, `gate.json`,
`heartbeat.json`, `logs\`, `compare\` (`<key>.json` per final + `summary.csv`), `control\`, `secret\`, `locklib\`, `scratch\`),
backups in `E:\reprocBackup_261022\<task>\<sessID>\`, the superseded finals next to the session:
`<root>\<id>\preProc\superseded_261022\`, the master-sheet backups in `R:\...\Admin\Data\sheetBackups\`.

## Commands (from the home machine, VPN up)

    cd C:\Users\Adam\Documents\GitHub\zlp-main\batch\fullRerun\home
    .\fr_start.ps1                                # credential -> lab (first time), start detached; arms the validation gate
    .\fr_status.ps1                               # one line per state + the last finals + failures + gate + locks   (-Watch 60 repeats)
    .\fr_start.ps1 -Continue                      # OPEN the validation gate (creates control\GATE_OPEN on the lab; the file stays)
    .\fr_stop.ps1 [-Wait 90] [-Now]               # graceful (finishes the current final) / hard (MATLAB killed, final restored at restart)
    .\fr_start.ps1 -Restart                       # stop, wait, start again (idempotent: never two drivers; the gate is still armed)
    .\fr_start.ps1 -RefreshCred                   # after a password change
    .\fr_start.ps1 -RetryFailed                   # failed and needsDecision finals back to pending
    .\fr_start.ps1 -Scratch -Set validation       # the same loop in the scratch universe (validation agent); .\fr_status.ps1 -Scratch

## State machine (see the header of `fr_final.ps1`)

`pending -> backedUp -> moved -> running -> verified -> done`, `failed` after two failed attempts, `needsDecision` after a
deterministic failure (the original is back in place in both). The machine MATLAB lock and the sheet lock are taken before the
final is moved. A final found in `moved` / `running` / `restoring` at (re)start was interrupted: it is **restored** (the newer
partial file is moved aside, never deleted; the original is hash-checked against the backup) and redone from the move step; the
interrupted attempt is given back (`attemptOpen` in the state file), so an interruption never costs one of the two tries.

## Safety rules the driver enforces

* **Validation gate (persistent).** The manifest's last validation row has `gateAfter = 1`. While `control\GATE_OPEN` does not exist
  nothing after that row starts - not in the running driver, not after `-Restart`, not after a reboot of the lab desktop: the gate is
  read from the files (`gate.json` arms it at the first real start, `control\GATE_OPEN` opens it) at every start and before every row.
  Only `fr_start.ps1 -Continue` (or creating `GATE_OPEN` by hand) opens it; `-NoGate` is the deliberate bypass; `-CloseGate` re-arms.
* **One MATLAB at a time on the whole machine.** Every MATLAB the family starts (a final's run and its verification, the scratch
  universe, `fr_runFinal`, the manifest build) runs under one machine-wide lock file (`E:\claudeWork\rerun1022\matlab.lock`, an
  OS-held exclusive handle: released if the holder dies). A real and a scratch driver are never launched together (`fr_launch`
  checks both driver locks); a foreground scratch row fails at once when another MATLAB runs (`-WaitMatlabMin N` waits).
* **The master sheet.** MATLAB runs in the real universe only with the lab's sheet lock held for the WHOLE run: the hold limit is
  4 x the run's stall limit + 45 min (>= the longest run the watchdog allows), the holder's liveness and the lock file's owner are
  checked every 10 s while MATLAB runs (a lost lock kills MATLAB; the final is restored and redone), and the driver refuses to run
  MATLAB without the holder. Before every final's run the master sheet is copied to
  `Admin\Data\sheetBackups\dataTracking_backup_<yyMMdd_HHmmss>_rerun1022.xlsx` (the lab convention; one per final, under the lock;
  without that backup MATLAB does not start); after the run the master must still be a readable xlsx, else it is put back from the
  snapshot. The lock script `E:\claudeWork\u1012\withSheetLock.ps1` is another job's file: a copy is kept in `<Root>\locklib\`, used
  if the original disappears, and the driver refuses to start with neither.
* **Code freeze.** The driver records the lab repo's HEAD at start and pauses (`pausedCode`) when it changes, when tracked files get
  dirty, or when `git` cannot be run; it refuses to start when git cannot be run (`-AllowCodeChange` overrides).
* **Carry gate.** `fr_verify.m` acts on the same-recording evidence the carry recorded: the selected respiration channel needs a
  FINITE correlation, >= 0.90 (>= 0.98 for a previous final saved before the 2026-07-07 22:38 notch removal), and for a previous final
  saved after it at most 0.1 % of the samples may differ; weaker evidence is a warning in `summary.csv`.
* **No pointless retries.** A deterministic failure (the carry refuses the previous final: channel / polarity / sample count /
  sections / not the same recording; the carry gate; the driver's own precondition errors) is not retried: the original is restored,
  the row becomes `needsDecision` (listed in `failures.csv` with `class = needsDecision`) and the driver moves on. Not counted by the
  circuit breaker (4 failed finals in a row); a separate, larger limit (8 in a row) stops a systematic cause.

## Security

The NetID password exists only in the home DPAPI blob (`~\.fsmcreds\netid.sec`), on the ssh stdin pipe (base64), in the lab's
user-scope DPAPI blob `secret\netid.dpapi`, and in process memory while `WNetAddConnection2` runs. Never on a command line, in a log,
in a state file or in the repo. A refused credential is tried at most twice (no account lock-out). The driver deletes the blob
when the batch finishes (`-KeepCredential` keeps it).

No participant data or notes are stored in these files; the manifest holds session ids, file paths, sizes and processing parameters only.

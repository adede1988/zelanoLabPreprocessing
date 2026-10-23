# fr_statusLab.ps1 - lab side.  Prints the state of the full-EEG-rerun driver: is it alive, what it does now, one line per state
# of the manifest, the last N finals, the failures.  Read-only.  Called by home\fr_status.ps1 over ssh (or run it on the lab).
param(
    [int]$Last = 8,
    [string]$Root = 'E:\claudeWork\rerun1022',
    [string]$Manifest = ''
)
$ErrorActionPreference = 'Continue'
if (-not $Manifest) { $Manifest = Join-Path $Root 'manifest.csv'; $pj0 = Join-Path $Root 'driver.pid.json'; if (Test-Path -LiteralPath $pj0) { try { $m0 = (Get-Content -LiteralPath $pj0 -Raw | ConvertFrom-Json).manifest; if ($m0) { $Manifest = $m0 } } catch { } } }
function J([string]$p) {
    if (Test-Path -LiteralPath $p) {
        try {
            $fs = [IO.File]::Open($p, 'Open', 'Read', 'ReadWrite, Delete')       # never blocks the driver's atomic replace
            try { $sr = New-Object IO.StreamReader($fs, [Text.Encoding]::UTF8); $t = $sr.ReadToEnd() } finally { $fs.Dispose() }
            return ($t | ConvertFrom-Json)
        } catch { return $null }
    }
    return $null
}
$now = Get-Date
$hb = J (Join-Path $Root 'heartbeat.json')
$pi = J (Join-Path $Root 'driver.pid.json')

# ---- driver
$alive = $false; $age = $null
if ($pi) {
    $pr = Get-Process -Id ([int]$pi.pid) -ErrorAction SilentlyContinue
    if ($pr -and $pr.StartTime.ToUniversalTime().Ticks -eq [long]$pi.startTicks) { $alive = $true }
}
if ($hb) { $age = [int]($now - [DateTime]::Parse($hb.time)).TotalSeconds }
$lockHeld = $false
$lp = Join-Path $Root 'driver.lock'
if (Test-Path -LiteralPath $lp) { try { $fs = [IO.File]::Open($lp, 'Open', 'ReadWrite', 'None'); $fs.Dispose() } catch { $lockHeld = $true } }
$verdict = if ($alive -and $age -ne $null -and $age -lt 180) { 'RUNNING' } elseif ($alive) { 'ALIVE BUT HEARTBEAT STALE (stuck on a network read?)' } elseif ($lockHeld) { 'LOCK HELD (driver starting or its pid file is stale)' } else { 'NOT RUNNING' }
Write-Output ("== driver: {0}{1}" -f $verdict, $(if ($alive) { " pid $($pi.pid), up since $($pi.start)" } else { '' }))
if ($hb) {
    Write-Output ("   last heartbeat {0} s ago | phase {1} | key {2} | step {3} | MATLAB pid {4} | R: {5}" -f $age, $hb.state, $hb.key, $hb.step, $hb.matlabPid, $(if ($hb.rOk -eq $true) { 'ok' } elseif ($hb.rOk -eq $false) { 'DOWN' } else { '?' }) + $(if ($hb.rChecked) { " (probed {0} s ago)" -f [int]($now - [DateTime]::Parse($hb.rChecked)).TotalSeconds } else { '' }))
    if ($hb.extra) { Write-Output ("   note: {0}" -f $hb.extra) }
    Write-Output ("   code: {0}" -f $hb.repoHead)
}
$ctl = Join-Path $Root 'control'
$flags = @('STOP', 'STOP_NOW', 'PAUSE', 'GATE_WAIT', 'GATE_OPEN', 'FINISHED') | Where-Object { Test-Path -LiteralPath (Join-Path $ctl $_) }
Write-Output ("   control files: {0}" -f $(if ($flags) { $flags -join ' ' } else { '(none)' }))
# the validation gate (persistent: gate.json arms it, control\GATE_OPEN opens it)
$gj = J (Join-Path $Root 'gate.json')
if ($gj) {
    $go = Test-Path -LiteralPath (Join-Path $ctl 'GATE_OPEN')
    Write-Output ("   validation gate: {0} (armed {1} at row order {2} = {3}{4})" -f $(if ($go) { 'OPEN' } else { 'CLOSED - nothing after the validation set starts until fr_start.ps1 -Continue' }), $gj.created, $gj.gateOrder, $gj.gateKey, $(if ($gj.openedAt) { ", opened $($gj.openedAt)" } else { '' }))
} else { Write-Output "   validation gate: not armed in this root (no gate.json)" }
# locks: the machine-wide MATLAB lock (one MATLAB at a time) and the lab's sheet lock
$ml = 'E:\claudeWork\rerun1022\matlab.lock'
$mlHeld = $false
if (Test-Path -LiteralPath $ml) { try { $fs = [IO.File]::Open($ml, 'Open', 'ReadWrite', 'None'); $fs.Dispose() } catch { $mlHeld = $true } }
$mli = J ($ml + '.json')
Write-Output ("   MATLAB lock: {0}" -f $(if ($mlHeld) { "HELD by {0} (pid {1}, since {2})" -f $mli.who, $mli.pid, $mli.since } else { 'free' }))
$sl = 'E:\claudeWork\u1012\sheet.lock'
Write-Output ("   sheet lock: {0}" -f $(if (Test-Path -LiteralPath $sl) { 'HELD: ' + ((Get-Content -LiteralPath $sl -ErrorAction SilentlyContinue | Select-Object -First 1)) } else { 'free' }))
$cred = Get-ChildItem -LiteralPath (Join-Path $Root 'secret') -Filter 'netid*.dpapi' -ErrorAction SilentlyContinue
Write-Output ("   credential blob: {0}" -f $(if ($cred) { ($cred | ForEach-Object { "$($_.Name) (age $([int]($now - $_.LastWriteTime).TotalHours) h)" }) -join ', ' } else { 'none' }))
$e = Get-PSDrive E -ErrorAction SilentlyContinue
Write-Output ("   E: free {0:N0} GB ; free memory {1:N0} GB" -f ($e.Free / 1GB), ((Get-CimInstance Win32_OperatingSystem).FreePhysicalMemory / 1MB))

# ---- one line per state
$rows = @(); if (Test-Path -LiteralPath $Manifest) { $rows = @(Import-Csv -LiteralPath $Manifest | Sort-Object { [double]$_.order }) }
$states = [ordered]@{ pending = 0; backedUp = 0; moved = 0; running = 0; verified = 0; done = 0; failed = 0; needsDecision = 0; restoring = 0; disabled = 0 }
$info = @()
foreach ($r in $rows) {
    $s = J (Join-Path $Root ("state\{0}.json" -f $r.key))
    $n = if ($s) { [string]$s.state } else { 'pending' }
    if ($r.enabled -eq '0' -and $n -eq 'pending') { $n = 'disabled' }
    if ($states.Contains($n)) { $states[$n]++ } else { $states[$n] = 1 }
    if ($s) { $info += [pscustomobject]@{ key = $r.key; state = $n; updated = [string]$s.updated; secs = $s.runSecs; warn = [string]$s.verifyWarnings; err = [string]$s.lastError; att = $s.attempts; intr = $s.interruptions } }
}
Write-Output ("== manifest: {0} rows ({1})" -f $rows.Count, $Manifest)
$bySet = $rows | Group-Object set
foreach ($g in $bySet) {
    $dn = @($g.Group | Where-Object { $x = J (Join-Path $Root ("state\{0}.json" -f $_.key)); $x -and [string]$x.state -eq 'done' }).Count
    Write-Output ("   set {0,-10}: {1} of {2} done" -f $g.Name, $dn, $g.Count)
}
foreach ($k in $states.Keys) { Write-Output ("   {0,-10}: {1}" -f $k, $states[$k]) }
if ($hb -and $hb.key) {
    $cur = J (Join-Path $Root ("state\{0}.json" -f $hb.key))
    if ($cur -and $cur.runStart -and ([string]$cur.state -eq 'running')) { Write-Output ("   now: {0} running since {1} ({2} min)" -f $hb.key, $cur.runStart, [int]($now - [DateTime]::Parse($cur.runStart)).TotalMinutes) }
}

# ---- last finals
Write-Output ("== last {0} finals touched" -f $Last)
$info | Sort-Object { $_.updated } -Descending | Select-Object -First $Last | ForEach-Object {
    $w = if ($_.warn) { " warn: " + $_.warn.Substring(0, [Math]::Min(80, $_.warn.Length)) } else { '' }
    $er = if ($_.err -and $_.state -ne 'done') { " err: " + $_.err.Substring(0, [Math]::Min(110, $_.err.Length)) } else { '' }
    Write-Output ("   {0}  {1,-9} {2,5}s a{3} i{4}  {5}{6}{7}" -f $_.updated, $_.state, $_.secs, $_.att, $_.intr, $_.key, $w, $er)
}
$fail = Join-Path $Root 'failures.csv'
if (Test-Path -LiteralPath $fail) {
    $fl = @(Import-Csv -LiteralPath $fail)
    Write-Output ("== failures.csv: {0} entries" -f $fl.Count)
    $fl | Select-Object -Last 6 | ForEach-Object { Write-Output ("   {0} {1}: {2}" -f $_.time, $_.key, $_.reason.Substring(0, [Math]::Min(150, $_.reason.Length))) }
}
$log = Join-Path $Root 'logs\driver.log'
if (Test-Path -LiteralPath $log) { Write-Output "== driver.log (tail)"; Get-Content -LiteralPath $log -Tail 5 | ForEach-Object { Write-Output ("   " + $_) } }

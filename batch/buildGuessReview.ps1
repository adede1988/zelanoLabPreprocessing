# buildGuessReview.ps1 - assemble guessReview.html from guessReviewFigs\<task>\<id>\
# (qc8_guessReviewFigs.m output pulled into the repo). Windows PowerShell 5.1.
# Usage: powershell -File batch\buildGuessReview.ps1
param(
  [string]$RepoRoot = (Split-Path $PSScriptRoot -Parent),
  [string]$FigDir   = 'guessReviewFigs',
  [string]$OutFile  = 'guessReview.html'
)
$ErrorActionPreference = 'Stop'
$figRoot = Join-Path $RepoRoot $FigDir

function HtmlEnc([string]$s) {
  if ($null -eq $s) { return '' }
  return $s.Replace('&','&amp;').Replace('<','&lt;').Replace('>','&gt;')
}
function AsList($v) {
  if ($null -eq $v) { return @() }
  if ($v -is [System.Array]) { return $v }
  return @($v)
}
function FmtVal($v) {
  if ($null -eq $v) { return '' }
  if ($v -is [System.Array]) { return ($v -join ', ') }
  return [string]$v
}

# preferred display order for figures within a session block
$prefOrder = @(
  '*_qc8_ad2events.png', '*_qc8_ecg.png', 'ECG_beatDetect*', 'interbeatHist*',
  'RespirationHeart*', '*_qc8_rsp.png', 'breathLengths*', 'HeartByBreathLengths*',
  'removedBlink*', 'blinkAmbiguous*', '*paramCheck_rsp*', '*paramCheck_ECG*',
  '*paramCheck_macros*', 'macrosRaw.jpg', 'macrosRaw_zoom*', '*_qc8_macroRaw.png',
  '*_qc8_macroBP.png', 'macroSpikeRemoval*', 'shadowResp*', '*logAlign*',
  '*movieClipTTLs*', 'TTLs.jpg', 'allSniffs*', 'sniffsTrial*')
function FigRank([string]$name) {
  for ($i = 0; $i -lt $prefOrder.Count; $i++) {
    if ($name -like $prefOrder[$i]) { return $i }
  }
  return $prefOrder.Count
}
function SniffNum([string]$name) {
  if ($name -match 'sniffsTrial(\d+)') { return [int]$Matches[1] }
  return 0
}

$taskOrder = @('breathingTask','EmotionalMovieTask','alternating6Blocks',
               'breathingTasks_separate','cueTask','threshTask','O15')
$taskTitles = @{
  'breathingTask'           = 'breathingTask (breathMetrics segmentation + ECG/HRV)'
  'EmotionalMovieTask'      = 'EmotionalMovieTask (breathMetrics segmentation + ECG/HRV)'
  'alternating6Blocks'      = 'alternating6Blocks (breathMetrics segmentation + ECG/HRV)'
  'breathingTasks_separate' = 'breathingTasks_separate (audioBook / focusedBreathing / sleep / etc.)'
  'cueTask'                 = 'cueTask (odor cue; sniff-per-trial)'
  'threshTask'              = 'threshTask (PEA threshold; sniff-per-trial)'
  'O15'                     = 'O15 (sniff-per-trial)'
}

$H = New-Object System.Collections.Generic.List[string]
$H.Add('<!DOCTYPE html><html><head><meta charset="utf-8">')
$H.Add('<title>guessReview - Zelano Lab preprocessing</title>')
$H.Add('<style>
body { font-family: Segoe UI, Arial, sans-serif; margin: 0 auto; max-width: 1500px; padding: 16px; background: #fafafa; color: #222; }
h1 { border-bottom: 3px solid #444; }
h2 { background: #2c3e50; color: #fff; padding: 8px 12px; border-radius: 4px; margin-top: 40px; }
h3 { background: #e8eef4; padding: 6px 10px; border-left: 5px solid #2c3e50; margin-top: 28px; }
.howto { background: #fff8dc; border: 2px solid #d4b106; border-radius: 6px; padding: 12px 16px; }
.flag { color: #b30000; font-weight: bold; }
.ok { color: #0a7a0a; }
.meta { background: #fff; border: 1px solid #ddd; border-radius: 4px; padding: 8px 12px; margin: 8px 0; }
.meta ul { margin: 4px 0; }
img { max-width: 100%; border: 1px solid #ccc; margin: 6px 0; background: #fff; }
table { border-collapse: collapse; background: #fff; }
td, th { border: 1px solid #bbb; padding: 4px 8px; font-size: 13px; }
th { background: #2c3e50; color: #fff; }
.figname { font-size: 12px; color: #666; margin: 0; }
details { margin: 6px 0; }
summary { cursor: pointer; font-weight: bold; }
</style></head><body>')
$H.Add('<h1>guessReview &mdash; all paramSource=guess sessions</h1>')
$H.Add('<p>Generated ' + (Get-Date -Format 'yyyy-MM-dd HH:mm') + '. Every session below ran with unverified (guess) parameters and was never promoted to curated. Review each block; the figures come from the saved finals and the standard pipeline QC output.</p>')

# ---- response instructions (per work order: at the beginning of the report) ----
$H.Add('<div class="howto"><b>How to respond to this report:</b> write your instructions into a new file named <code>reportResponse.md</code> in the repo root.
Either create it directly on the lab machine at <code>E:\GitHub\zelanoLabPreprocessing\reportResponse.md</code>, or commit + push it to origin/main from any machine (it will be pulled to the lab machine automatically).
<b>Claude checks for this file every 15 minutes</b> and will read and execute the instructions it contains.
Useful things to put in it: per-session verdicts (e.g. &quot;promote X to curated&quot;, &quot;re-run Y with rspFlip=-1&quot;, &quot;rspIDX should be 2 for Z&quot;), beatSpec corrections, sessions to re-run or drop, and any follow-up work.</div>')

# ---- collect ----
$all = @()
foreach ($task in $taskOrder) {
  $tdir = Join-Path $figRoot $task
  if (-not (Test-Path $tdir)) { continue }
  $sessDirs = Get-ChildItem $tdir -Directory | Sort-Object Name
  foreach ($sd in $sessDirs) {
    $info = $null
    $ij = Join-Path $sd.FullName 'info.json'
    if (Test-Path $ij) {
      try { $info = Get-Content $ij -Raw | ConvertFrom-Json } catch { $info = $null }
    }
    $all += [pscustomobject]@{ Task = $task; Id = $sd.Name; Dir = $sd.FullName; Info = $info }
  }
}

# ---- AD_2 block answer near the top ----
$ad2 = $all | Where-Object { $_.Id -eq '260326_OBE_NWU_AD_2' -and $_.Task -eq 'breathingTask' } | Select-Object -First 1
if ($ad2 -and $ad2.Info -and $ad2.Info.PSObject.Properties['ad2_nPulseGroups']) {
  $H.Add('<h2>AD_2 breathing: block structure from the event channel</h2>')
  $H.Add('<div class="meta"><ul>')
  $H.Add('<li>Distinct photodiode pulse groups detected across the session: <b>' + (FmtVal $ad2.Info.ad2_nPulseGroups) + '</b> (total pulses: ' + (FmtVal $ad2.Info.ad2_nPulses) + ')</li>')
  foreach ($g in (AsList $ad2.Info.ad2_groups)) { $H.Add('<li>' + (HtmlEnc $g) + '</li>') }
  if ($ad2.Info.PSObject.Properties['ad2_TTLstored']) {
    $H.Add('<li>TTL block boundaries stored in the final (s): ' + (FmtVal $ad2.Info.ad2_TTLstored) + '</li>')
  }
  $H.Add('<li>Known block: audio (measured sliding-correlation window, 30&ndash;330 s). Behavioral ratings stop after the audio block; no later blocks are identifiable in the log.</li>')
  $H.Add('</ul></div>')
  $rel = ($FigDir + '/breathingTask/260326_OBE_NWU_AD_2/260326_OBE_NWU_AD_2_qc8_ad2events.png')
  if (Test-Path (Join-Path $figRoot 'breathingTask/260326_OBE_NWU_AD_2/260326_OBE_NWU_AD_2_qc8_ad2events.png')) {
    $H.Add('<img loading="lazy" src="' + $rel + '">')
  }
}

# ---- summary table ----
$H.Add('<h2>Summary</h2><table><tr><th>task</th><th>session</th><th>status</th><th>blink removal</th><th>spike clean</th><th>beats (bpm)</th><th>breaths / trials</th><th>figs</th></tr>')
foreach ($e in $all) {
  $i = $e.Info
  $status = 'no info.json'; $blink = '?'; $spike = '?'; $beats = '-'; $n = '-'
  $nf = (Get-ChildItem $e.Dir -File | Where-Object { $_.Extension -in '.jpg','.png' }).Count
  if ($i) {
    $status = FmtVal $i.status
    if ($i.PSObject.Properties['blinkRemoval']) {
      if ($i.blinkRemoval -eq 1) { $blink = 'yes' }
      elseif ($i.blinkRemoval -eq 0) { $blink = 'NO' }
      else { $blink = 'no EEG' }
    }
    if ($i.PSObject.Properties['spikeCleanRan']) {
      if ($i.spikeCleanRan -eq 1) {
        if ($i.PSObject.Properties['spikeSamplesAltered'] -and $i.spikeSamplesAltered -gt 0) { $spike = 'yes (removed)' } else { $spike = 'ran, none found' }
      } else { $spike = 'no' }
    }
    if ($i.PSObject.Properties['nBeats']) { $beats = (FmtVal $i.nBeats) + ' (' + (FmtVal $i.bpm) + ')' }
    if ($i.PSObject.Properties['nBreaths']) { $n = FmtVal $i.nBreaths }
    elseif ($i.PSObject.Properties['nTrials']) { $n = FmtVal $i.nTrials }
  }
  $cls = ''
  if ($status -ne 'ok') { $cls = ' class="flag"' }
  $H.Add('<tr><td>' + $e.Task + '</td><td><a href="#' + $e.Task + '_' + $e.Id + '">' + $e.Id + '</a></td><td' + $cls + '>' + (HtmlEnc $status) + '</td><td>' + $blink + '</td><td>' + $spike + '</td><td>' + $beats + '</td><td>' + $n + '</td><td>' + $nf + '</td></tr>')
}
$H.Add('</table>')

# ---- per-task sections ----
foreach ($task in $taskOrder) {
  $entries = $all | Where-Object { $_.Task -eq $task }
  if (-not $entries) { continue }
  $H.Add('<h2>' + (HtmlEnc $taskTitles[$task]) + '</h2>')
  foreach ($e in $entries) {
    $H.Add('<h3 id="' + $e.Task + '_' + $e.Id + '">' + $e.Id + '</h3>')
    $i = $e.Info
    $H.Add('<div class="meta"><ul>')
    if ($i) {
      $st = FmtVal $i.status
      if ($st -eq 'ok') { $H.Add('<li>status: <span class="ok">ok</span></li>') }
      else { $H.Add('<li>status: <span class="flag">' + (HtmlEnc $st) + '</span></li>') }
      if ($i.PSObject.Properties['durMin']) { $H.Add('<li>duration: ' + (FmtVal $i.durMin) + ' min @ ' + (FmtVal $i.fs) + ' Hz</li>') }
      # sheet params
      $sp = @()
      foreach ($p in 'sheet_type','sheet_hasEEG','sheet_hasMacros','sheet_spikeClean','sheet_rspIDX','sheet_rspFlip','sheet_beatSpec','sheet_macroRemove','sheet_respThresh','sheet_cuedBackBuff','sheet_adjWin') {
        if ($i.PSObject.Properties[$p]) { $sp += ($p.Substring(6) + '=' + (FmtVal $i.$p)) }
      }
      if ($sp.Count) { $H.Add('<li>sheet params (guess): ' + (HtmlEnc ($sp -join ' | ')) + '</li>') }
      # blink
      if ($i.PSObject.Properties['blinkRemoval']) {
        if ($i.blinkRemoval -eq 1) { $H.Add('<li>blink removal: <span class="ok">ran</span> (topography figure below)</li>') }
        elseif ($i.blinkRemoval -eq 0) { $H.Add('<li class="flag">blink removal: DID NOT RUN for this session</li>') }
        else { $H.Add('<li class="flag">no EEG preprocessing for this session (no blinkRemoval field)</li>') }
      }
      if ($i.PSObject.Properties['badChans'] -and (AsList $i.badChans).Count) {
        $H.Add('<li>interpolated/bad EEG channels: ' + (HtmlEnc (FmtVal $i.badChans)) + '</li>')
      }
      # macros
      if ($i.PSObject.Properties['nMacro']) {
        $H.Add('<li>macro channels: ' + (FmtVal $i.nMacro) + ' raw, ' + (FmtVal $i.nMacBP) + ' bipolar (macBP)</li>')
      }
      if ($i.PSObject.Properties['spikeCleanRan']) {
        if ($i.spikeCleanRan -eq 1) {
          if ($i.PSObject.Properties['spikeSamplesAltered'] -and $i.spikeSamplesAltered -gt 0) {
            $H.Add('<li>spike removal: ran, altered ' + (FmtVal $i.spikeSamplesAltered) + ' samples</li>')
          } else {
            $H.Add('<li>spike removal: ran, spikeCleanVec all-ones (nothing removed)</li>')
          }
        } else { $H.Add('<li>spike removal: did not run (no spikeCleanVec)</li>') }
      }
      # breathing family numbers
      if ($i.PSObject.Properties['nBreaths']) { $H.Add('<li>breaths segmented: ' + (FmtVal $i.nBreaths) + '</li>') }
      if ($i.PSObject.Properties['nBeats']) { $H.Add('<li>heartbeats stored: ' + (FmtVal $i.nBeats) + ' (~' + (FmtVal $i.bpm) + ' bpm)</li>') }
      if ($i.PSObject.Properties['conditions']) {
        $H.Add('<li>conditions in the final:<ul>')
        foreach ($c in (AsList $i.conditions)) { $H.Add('<li>' + (HtmlEnc $c) + '</li>') }
        $H.Add('</ul></li>')
      }
      if ($i.PSObject.Properties['nTrials']) {
        $tl = 'trials: ' + (FmtVal $i.nTrials)
        if ($i.PSObject.Properties['trialTypes']) { $tl += ' (' + (FmtVal $i.trialTypes) + ')' }
        $H.Add('<li>' + (HtmlEnc $tl) + '</li>')
      }
      foreach ($nte in (AsList $i.notes)) {
        if ($nte -like 'FLAG:*') { $H.Add('<li class="flag">' + (HtmlEnc $nte) + '</li>') }
        else { $H.Add('<li>' + (HtmlEnc $nte) + '</li>') }
      }
    } else {
      $H.Add('<li class="flag">no info.json for this session</li>')
    }
    $H.Add('</ul></div>')

    # figures
    $figs = Get-ChildItem $e.Dir -File | Where-Object { $_.Extension -in '.jpg','.png' }
    $figs = $figs | Sort-Object @{Expression={FigRank $_.Name}}, @{Expression={SniffNum $_.Name}}, Name
    $sniffFigs = @($figs | Where-Object { $_.Name -like 'sniffsTrial*' })
    $mainFigs  = @($figs | Where-Object { $_.Name -notlike 'sniffsTrial*' })
    foreach ($f in $mainFigs) {
      $rel = "$FigDir/$($e.Task)/$($e.Id)/$($f.Name)"
      $H.Add('<p class="figname">' + (HtmlEnc $f.Name) + '</p><img loading="lazy" src="' + $rel + '">')
    }
    if ($sniffFigs.Count) {
      $H.Add('<details open><summary>per-trial sniff figures (' + $sniffFigs.Count + ')</summary>')
      foreach ($f in $sniffFigs) {
        $rel = "$FigDir/$($e.Task)/$($e.Id)/$($f.Name)"
        $H.Add('<p class="figname">' + (HtmlEnc $f.Name) + '</p><img loading="lazy" src="' + $rel + '">')
      }
      $H.Add('</details>')
    }
  }
}
$H.Add('</body></html>')
$outPath = Join-Path $RepoRoot $OutFile
[System.IO.File]::WriteAllLines($outPath, $H, (New-Object System.Text.UTF8Encoding($false)))
Write-Output ("buildGuessReview: wrote {0} ({1} sessions)" -f $outPath, $all.Count)

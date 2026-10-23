# fr_buildManifest.ps1 - lab side payload (run through fr_withR.ps1 -MatlabLock, R: mapped): builds the manifest of the full EEG rerun
# with fr_buildManifest.m.  Read-only on data and sheet.  Output: <OutDir>\manifest.csv, manifest_excluded.csv, manifest_notes.txt.
#   ssh labdesktop "powershell -NoProfile -NonInteractive -ExecutionPolicy Bypass -File E:\GitHub\zlp-main\batch\fullRerun\fr_withR.ps1 -MatlabLock -Payload E:\GitHub\zlp-main\batch\fullRerun\fr_buildManifest.ps1"
# ONE MATLAB at a time: fr_withR -MatlabLock holds the machine-wide MATLAB lock for the build (a payload script cannot take it itself).
param(
    [string]$OutDir = 'E:\claudeWork\rerun1022',
    [string]$RepoRoot = 'E:\GitHub\zlp-main',
    [string]$MatlabOpts = ''          # extra MATLAB code that sets opts, e.g. "opts.noCache=true;"
)
$ErrorActionPreference = 'Continue'
New-Item -ItemType Directory -Force -Path (Join-Path $OutDir 'logs') | Out-Null
$log = Join-Path $OutDir 'logs\buildManifest.log'
$code = "addpath(genpath(pwd)); set(0,'DefaultFigureVisible','off'); opts = struct(); $MatlabOpts fr_buildManifest('$OutDir', opts);"
$p = Start-Process -FilePath 'matlab' -ArgumentList @('-sd', ('"' + $RepoRoot + '"'), '-batch', ('"' + $code + '"'), '-logfile', ('"' + $log + '"')) -PassThru -WindowStyle Hidden
$null = $p.Handle
try { $p.PriorityClass = 'BelowNormal' } catch { }
$p.WaitForExit()
"matlab exit code: $($p.ExitCode)"
Get-Content -LiteralPath $log -Tail 12

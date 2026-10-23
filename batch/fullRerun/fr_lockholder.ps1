# fr_lockholder.ps1 - holds the lab's dataTracking.xlsx write lock (withSheetLock.ps1, the shared protocol) on behalf of the driver.
# The driver starts one holder per MATLAB run; the holder takes the lock through the official script, writes the ack file, and keeps
# the lock until the driver creates the release file, the driver process dies, or MaxHoldMin passes - then the official script's
# finally-block releases the lock.  (The driver itself keeps its heartbeat / STOP handling while the lock is awaited.)
param(
    [Parameter(Mandatory = $true)][string]$LockScript,
    [Parameter(Mandatory = $true)][string]$Owner,
    [Parameter(Mandatory = $true)][int]$WaitMin,
    [Parameter(Mandatory = $true)][string]$Ack,
    [Parameter(Mandatory = $true)][string]$Release,
    [Parameter(Mandatory = $true)][int]$ParentPid,
    [int]$MaxHoldMin = 240
)
# NB: withSheetLock.ps1 uses $lock $t0 $fs $w in the scope this Body runs in - do not reuse those names here.
& $LockScript -Owner $Owner -WaitMin $WaitMin -Body {
    Set-Content -LiteralPath $Ack -Value ('acquired ' + (Get-Date -Format s)) -Encoding ASCII
    $holdStart = Get-Date
    while (-not (Test-Path -LiteralPath $Release)) {
        if (-not (Get-Process -Id $ParentPid -ErrorAction SilentlyContinue)) { break }
        if (((Get-Date) - $holdStart).TotalMinutes -gt $MaxHoldMin) { break }
        Start-Sleep -Seconds 2
    }
}

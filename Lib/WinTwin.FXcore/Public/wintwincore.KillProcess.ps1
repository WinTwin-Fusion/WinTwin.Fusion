function wintwincore.KillProcess {
    <#
    .SYNOPSIS
    Terminates the process currently registered in the framework's central
    process.json and deregisters it.

    .DESCRIPTION
    wintwincore.KillProcess first calls wintwincore.CheckProcess to resolve and verify the
    currently registered process. If a genuinely running process is found, it
    is terminated via Stop-Process and then deregistered (moved into 'lastjob'
    with job-state 'finished'). If nothing is currently registered, or the
    registered process turns out to already be dead, wintwincore.CheckProcess has
    already cleaned up process.json as a side effect, and this function simply
    returns success - the desired end state ("no process is registered/running
    anymore") is already true.

    .PARAMETER FrameworkRoot
    Full path to the WinTwin.Fusion framework root.

    .PARAMETER ProcessId
    Optional. When supplied, the PID currently registered in process.json must
    match this value, unless -Force is also supplied. Use this as a safety
    check when a caller wants to make sure it only ever kills the process it
    believes to be in control of.

    .PARAMETER Force
    When set:
      - a ProcessId mismatch (if -ProcessId was supplied) is ignored,
      - the process lock in process.json is cleared regardless of whether
        Stop-Process actually succeeded (e.g. the process was already gone,
        or access was denied).
    Intended for a future watchdog that needs to forcibly recover from a stuck
    lock even when exact ownership of the running process cannot be confirmed.

    .OUTPUTS
    PSCustomObject from OPSreturn.
    Success .data: the 'running' node as it looked right before the process was
    killed and deregistered.

    .EXAMPLE
    $kill = wintwincore.KillProcess -FrameworkRoot "C:\WinTwin.Fusion"
    if ($kill.code -ne 0) { Write-Warning $kill.msg }

    .EXAMPLE
    # Watchdog-style forced recovery, regardless of PID ownership:
    wintwincore.KillProcess -FrameworkRoot "C:\WinTwin.Fusion" -Force

    .NOTES
    Part of: WinTwin.FXcore
    See also: wintwincore.RegisterProcess, wintwincore.UnregisterProcess, wintwincore.CheckProcess, wintwincore.LoadJSON, wintwincore.WriteJSON
    #>

    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string]$FrameworkRoot,

        [Parameter(Mandatory = $false)]
        [int]$ProcessId = 0,

        [Parameter(Mandatory = $false)]
        [switch]$Force
    )

    if ([string]::IsNullOrEmpty($FrameworkRoot)) {
        return (OPSreturn -Code -1 -Message "Parameter 'FrameworkRoot' is required but was not provided or is empty")
    }

    # wintwincore.CheckProcess resolves process.json, verifies liveness, and already
    # self-heals a stale lock as a side effect - reuse it instead of
    # duplicating that logic here.
    $checkResult = wintwincore.CheckProcess -FrameworkRoot $FrameworkRoot
    if ($checkResult.code -ne 0) {
        return (OPSreturn -Code -1 -Message "Could not verify the current process lock: $($checkResult.msg)" -Exception $checkResult.exception)
    }

    if (-not $checkResult.data.IsRunning) {
        # Nothing genuinely running (either nothing was registered, or
        # wintwincore.CheckProcess just cleaned up a stale lock) - desired end state
        # already reached.
        return (OPSreturn -Code 0 -Message "wintwincore.KillProcess: No running process is currently registered, nothing to kill." -Data $checkResult.data.Running)
    }

    $registeredPid = 0
    try { $registeredPid = [int]$checkResult.data.Running.pid } catch { $registeredPid = 0 }

    if ($ProcessId -gt 0 -and $registeredPid -ne $ProcessId -and -not $Force) {
        return (OPSreturn -Code -1 -Message "Cannot kill: the registered process (PID $registeredPid) does not match the supplied ProcessId ($ProcessId). Use -Force to override.")
    }

    $runningNode = $checkResult.data.Running
    $stopFailed  = $false
    $stopError   = $null

    try {
        Stop-Process -Id $registeredPid -Force -ErrorAction Stop
    }
    catch {
        $stopFailed = $true
        $stopError  = $_.Exception
        if (-not $Force) {
            return (OPSreturn -Code -1 -Message "Could not stop process '$($runningNode.'proc-name')' (PID $registeredPid): $($_.Exception.Message)" -Exception $_.Exception)
        }
        # -Force: continue and still clean up the lock, even though the
        # process itself could not be confirmed stopped (e.g. it exited on its
        # own between the check above and this call, or access was denied).
    }

    $unregResult = wintwincore.UnregisterProcess -FrameworkRoot $FrameworkRoot
    if ($unregResult.code -ne 0) {
        if (-not $Force) {
            return (OPSreturn -Code -1 -Message "Process was stopped but could not be deregistered from process.json: $($unregResult.msg)" -Exception $unregResult.exception)
        }
    }

    if ($stopFailed) {
        return (OPSreturn -Code 0 -Message "wintwincore.KillProcess: Process '$($runningNode.'proc-name')' (PID $registeredPid) could not be confirmed stopped ($($stopError.Message)), but the lock was cleared via -Force." -Data $runningNode)
    }

    return (OPSreturn -Code 0 -Message "Process '$($runningNode.'proc-name')' (PID $registeredPid) was killed and deregistered successfully." -Data $runningNode)
}

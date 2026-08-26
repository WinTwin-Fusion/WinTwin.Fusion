function wtfxCheckProcess {
    <#
    .SYNOPSIS
    Checks whether the framework's central process.json currently holds a
    genuinely active process lock, and automatically clears the lock if it is
    stale (the registered process died without deregistering itself).

    .DESCRIPTION
    A 'running' job-state in process.json alone does not prove that the
    registered process is still alive - it may have crashed, been killed via
    Task Manager, lost power mid-job, or thrown an unhandled exception.
    wtfxCheckProcess resolves the recorded PID via Get-Process and cross-checks
    it against the recorded executable path (proc-path) to guard against PID
    reuse. If the process is gone (or a different process now owns that PID),
    the lock is treated as stale: it is moved into 'lastjob' (job-state
    'crashed') and 'running' is reset - exactly like a normal deregistration,
    just self-triggered by this check instead of an explicit call from the
    original owner.

    This function is the single source of truth every other process-management
    function (wtfxRegisterProcess, wtfxKillProcess) relies on before deciding
    whether a lock is real.

    .PARAMETER FrameworkRoot
    Full path to the WinTwin.Fusion framework root.

    .OUTPUTS
    PSCustomObject from OPSreturn.
    Success .data: IsRunning (bool), WasStale (bool), Running (the 'running'
    node, always reflecting the state AFTER this check has run - i.e. already
    cleaned up if a stale lock was found).

    .EXAMPLE
    $check = wtfxCheckProcess -FrameworkRoot "C:\WinTwin.Fusion"
    if ($check.code -eq 0 -and -not $check.data.IsRunning) {
        # safe to register a new process now
    }

    .NOTES
    Part of: WinTwin.FXcore
    See also: wtfxRegisterProcess, wtfxUnregisterProcess, wtfxKillProcess, wtfxLoadJSON, wtfxWriteJSON
    #>

    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string]$FrameworkRoot
    )

    if ([string]::IsNullOrEmpty($FrameworkRoot)) {
        return (OPSreturn -Code -1 -Message "Parameter 'FrameworkRoot' is required but was not provided or is empty")
    }

    $configPath = Join-Path -Path $FrameworkRoot -ChildPath 'Core\config.json'
    $configResult = wtfxLoadJSON -Path $configPath
    if ($configResult.code -ne 0) {
        return (OPSreturn -Code -1 -Message "Could not load Core\config.json: $($configResult.msg)" -Exception $configResult.exception)
    }
    $config = $configResult.data

    try {
        $relativeProcessPath = $config.path.appdb.process
    }
    catch {
        return (OPSreturn -Code -1 -Message "config.json does not contain the expected 'path.appdb.process' key")
    }
    if ([string]::IsNullOrEmpty($relativeProcessPath)) {
        return (OPSreturn -Code -1 -Message "config.json 'path.appdb.process' value is empty")
    }

    $processDbPath = Join-Path -Path $FrameworkRoot -ChildPath ($relativeProcessPath.TrimStart('\'))

    $processResult = wtfxLoadJSON -Path $processDbPath
    if ($processResult.code -ne 0) {
        return (OPSreturn -Code -1 -Message "Could not load process.json: $($processResult.msg)" -Exception $processResult.exception)
    }
    $db = $processResult.data

    $jobState = ''
    try { $jobState = [string]$db.running.'job-state' } catch { $jobState = '' }

    if ($jobState -ne 'running') {
        $resultData = [pscustomobject]@{
            IsRunning = $false
            WasStale  = $false
            Running   = $db.running
        }
        return (OPSreturn -Code 0 -Message "wtfxCheckProcess: No process is currently registered." -Data $resultData)
    }

    $registeredPid  = 0
    $registeredPath = [string]$db.running.'proc-path'
    try { $registeredPid = [int]$db.running.pid } catch { $registeredPid = 0 }

    $liveProc = $null
    if ($registeredPid -gt 0) {
        $liveProc = Get-Process -Id $registeredPid -ErrorAction SilentlyContinue
    }

    # Guard against PID reuse: the live process at that PID must still point to
    # the exact same executable that originally acquired the lock. Skip this
    # extra check if no path was ever recorded (older process.json data).
    $pidMatchesRecordedPath = $true
    if ($null -ne $liveProc -and -not [string]::IsNullOrWhiteSpace($registeredPath)) {
        try {
            $pidMatchesRecordedPath = ($liveProc.Path -eq $registeredPath)
        }
        catch {
            # Path could not be resolved (e.g. access denied) - do not treat
            # this alone as proof of a stale lock.
            $pidMatchesRecordedPath = $true
        }
    }

    if ($null -ne $liveProc -and $pidMatchesRecordedPath) {
        $resultData = [pscustomobject]@{
            IsRunning = $true
            WasStale  = $false
            Running   = $db.running
        }
        return (OPSreturn -Code 0 -Message "wtfxCheckProcess: Process '$($db.running.'proc-name')' (PID $registeredPid) is still running." -Data $resultData)
    }

    # --- Stale lock: the recorded process is gone (or the PID was recycled) ---
    $staleRunning = $db.running

    try {
        $db.lastjob.'proc-name' = $staleRunning.'proc-name'
        $db.lastjob.'proc-path' = $staleRunning.'proc-path'
        $db.lastjob.'action-id' = $staleRunning.'action-id'
        $db.lastjob.cmdparams   = $staleRunning.cmdparams
        $db.lastjob.'job-start' = $staleRunning.'job-start'
        $db.lastjob.'job-state' = 'crashed'
        $db.lastjob.'job-ended' = (Get-Date -Format 'dd.MM.yyyy ; HH:mm:ss')

        $db.running.'proc-name' = ''
        $db.running.'proc-path' = ''
        $db.running.'action-id' = ''
        $db.running.cmdparams   = ''
        $db.running.'job-start' = ''
        $db.running.'job-state' = ''
        $db.running | Add-Member -MemberType NoteProperty -Name 'pid' -Value 0 -Force
    }
    catch {
        return (OPSreturn -Code -1 -Message "Detected a stale process lock but could not update the in-memory process database: $($_.Exception.Message)" -Exception $_.Exception)
    }

    $writeResult = wtfxWriteJSON -Path $processDbPath -Value $db
    if ($writeResult.code -ne 0) {
        return (OPSreturn -Code -1 -Message "Detected a stale process lock but could not persist the cleanup to process.json: $($writeResult.msg)" -Exception $writeResult.exception)
    }

    $resultData = [pscustomobject]@{
        IsRunning = $false
        WasStale  = $true
        Running   = $db.running
    }

    return (OPSreturn -Code 0 -Message "wtfxCheckProcess: Stale lock detected and cleared (PID $registeredPid no longer exists or was recycled)." -Data $resultData)
}

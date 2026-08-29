function wtfxUnregisterProcess {
    <#
    .SYNOPSIS
    Deregisters the currently registered process from the framework's central
    process.json database.

    .DESCRIPTION
    The wtfxUnregisterProcess function resolves process.json the same way
    wtfxRegisterProcess does, moves the current 'running' node into 'lastjob'
    (stamped with a 'job-ended' timestamp and job-state 'finished') and resets
    'running' back to its empty state. Every tool that previously registered a
    process via wtfxRegisterProcess MUST call this once that process has
    actually finished - including a tool deregistering itself right before
    handing control off to a different process it started (e.g. wim.mounter
    clearing its own lock before WTF.Console takes it over).

    Calling this function while nothing is registered is not an error - it is
    treated as an idempotent no-op, since the desired end state ("nothing is
    registered") is already true.

    .PARAMETER FrameworkRoot
    Full path to the WinTwin.Fusion framework root.

    .PARAMETER ProcessId
    Optional. When supplied, deregistration only happens if the PID currently
    registered in process.json matches this value - protects against a tool
    accidentally clearing a different tool's active lock. Omit (or pass 0) to
    deregister unconditionally.

    .OUTPUTS
    PSCustomObject from OPSreturn. Success .data contains the 'running' node as
    it looked right before it was cleared (i.e. the job that was just
    deregistered).

    .EXAMPLE
    $unreg = wtfxUnregisterProcess -FrameworkRoot "C:\WinTwin.Fusion" -ProcessId $PID
    if ($unreg.code -ne 0) { Write-Warning $unreg.msg }

    .NOTES
    Part of: WinTwin.FXcore
    See also: wtfxRegisterProcess, wtfxCheckProcess, wtfxKillProcess, wtfxLoadJSON, wtfxWriteJSON
    #>

    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string]$FrameworkRoot,

        [Parameter(Mandatory = $false)]
        [int]$ProcessId = 0,

        [Parameter(Mandatory = $false)]
        [int]$ExitCode = -1
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

    $currentState = ''
    try { $currentState = [string]$db.running.'job-state' } catch { $currentState = '' }

    if ($currentState -ne 'running') {
        # Idempotent: nothing was registered in the first place.
        return (OPSreturn -Code 0 -Message "wtfxUnregisterProcess: No process was registered, nothing to do." -Data $db.running)
    }

    if ($ProcessId -gt 0) {
        $registeredPid = 0
        try { $registeredPid = [int]$db.running.pid } catch { $registeredPid = 0 }
        if ($registeredPid -ne $ProcessId) {
            return (OPSreturn -Code -1 -Message "Cannot deregister: the registered process (PID $registeredPid) does not match the supplied ProcessId ($ProcessId).")
        }
    }

    $previousRunning = $db.running

    try {
        $db.lastjob.'proc-name' = $previousRunning.'proc-name'
        $db.lastjob.'proc-path' = $previousRunning.'proc-path'
        $db.lastjob.'action-id' = $previousRunning.'action-id'
        $db.lastjob.processid   = [int]$previousRunning.processid
        $db.lastjob.cmdparams   = $previousRunning.cmdparams
        $db.lastjob.'job-start' = $previousRunning.'job-start'
        $db.lastjob.'job-state' = 'finished'
        $db.lastjob.'job-ended' = (Get-Date -Format 'dd.MM.yyyy ; HH:mm:ss')
        $db.lastjob.exitcode    = [int]$ExitCode

        $db.running.'proc-name' = ''
        $db.running.'proc-path' = ''
        $db.running.'action-id' = ''
        $db.running.processid   = ''
        $db.running.cmdparams   = ''
        $db.running.'job-start' = ''
        $db.running.'job-state' = ''
        $db.running.exitcode    = ''
    }
    catch {
        return (OPSreturn -Code -1 -Message "Could not update the in-memory process database: $($_.Exception.Message)" -Exception $_.Exception)
    }

    $writeResult = wtfxWriteJSON -Path $processDbPath -Value $db
    if ($writeResult.code -ne 0) {
        return (OPSreturn -Code -1 -Message "Process was cleared in memory but could not be persisted to process.json: $($writeResult.msg)" -Exception $writeResult.exception)
    }

    return (OPSreturn -Code 0 -Message "Process '$($previousRunning.'proc-name')' (PID $($previousRunning.pid)) deregistered successfully." -Data $previousRunning)
}

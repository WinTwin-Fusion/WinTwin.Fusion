function wtfxRegisterProcess {
    <#
    .SYNOPSIS
    Registers a running process in the framework's central process.json database.

    .DESCRIPTION
    The wtfxRegisterProcess function resolves the path to Core\db\process.json via
    Core\config.json (path.root + path.appdb.process), loads it with wtfxLoadJSON,
    and writes the given process details into the 'running' node. Before writing,
    it internally calls wtfxCheckProcess so a previously registered lock is either
    confirmed genuinely free, or self-healed if it was left behind by a process
    that died without deregistering itself - a crashed tool must never be able to
    permanently block every other framework tool from starting new work. If a
    different process is still genuinely running, registration is refused.

    .PARAMETER FrameworkRoot
    Full path to the WinTwin.Fusion framework root (the directory that contains
    Core\config.json).

    .PARAMETER ProcName
    Friendly name of the process being registered, e.g. "WTF.Console".

    .PARAMETER ProcPath
    Full path to the executable or script that was started, e.g.
    "C:\WinTwin.Fusion\PS.Tweak.Tools\wtf.console.ps1".

    .PARAMETER ActionId
    The job/action identifier this process belongs to, e.g. "wim-mount". Should
    match a key in jobaction.json where applicable.

    .PARAMETER ProcessId
    The operating system process ID (PID) of the process being registered.
    Required so wtfxCheckProcess / wtfxKillProcess can later verify whether the
    process is still actually alive.

    .PARAMETER CmdParams
    Optional. The full command line the process was started with, kept only for
    diagnostics/logging purposes.

    .OUTPUTS
    PSCustomObject from OPSreturn. Success .data contains the freshly written
    'running' node.

    .EXAMPLE
    $reg = wtfxRegisterProcess -FrameworkRoot "C:\WinTwin.Fusion" -ProcName "WTF.Console" `
                                -ProcPath "C:\WinTwin.Fusion\PS.Tweak.Tools\wtf.console.ps1" `
                                -ActionId "wim-mount" -ProcessId $started.Id -CmdParams $commandLine
    if ($reg.code -ne 0) { throw $reg.msg }

    .NOTES
    Part of: WinTwin.FXcore
    See also: wtfxUnregisterProcess, wtfxCheckProcess, wtfxKillProcess, wtfxLoadJSON, wtfxWriteJSON
    #>

    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string]$FrameworkRoot,

        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string]$ProcName,

        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string]$ProcPath,

        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string]$ActionId,

        [Parameter(Mandatory = $true)]
        [int]$ProcessId,

        [Parameter(Mandatory = $false)]
        [AllowEmptyString()]
        [string]$CmdParams = ""
    )

    if ([string]::IsNullOrEmpty($FrameworkRoot)) {
        return (OPSreturn -Code -1 -Message "Parameter 'FrameworkRoot' is required but was not provided or is empty")
    }
    if ([string]::IsNullOrEmpty($ProcName)) {
        return (OPSreturn -Code -1 -Message "Parameter 'ProcName' is required but was not provided or is empty")
    }
    if ([string]::IsNullOrEmpty($ProcPath)) {
        return (OPSreturn -Code -1 -Message "Parameter 'ProcPath' is required but was not provided or is empty")
    }
    if ([string]::IsNullOrEmpty($ActionId)) {
        return (OPSreturn -Code -1 -Message "Parameter 'ActionId' is required but was not provided or is empty")
    }
    if ($ProcessId -le 0) {
        return (OPSreturn -Code -1 -Message "Parameter 'ProcessId' must be a positive process ID, got: $ProcessId")
    }

    # Self-heal a stale lock (a previously registered process that died without
    # deregistering itself) before deciding whether registration is possible.
    $checkResult = wtfxCheckProcess -FrameworkRoot $FrameworkRoot
    if ($checkResult.code -ne 0) {
        return (OPSreturn -Code -1 -Message "Could not verify the current process lock: $($checkResult.msg)" -Exception $checkResult.exception)
    }
    if ($checkResult.data.IsRunning) {
        return (OPSreturn -Code -1 -Message "Cannot register '$ProcName' (PID $ProcessId): a framework process is already running ('$($checkResult.data.Running.'proc-name')', PID $($checkResult.data.Running.pid)).")
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

    # relativeProcessPath is stored with a leading backslash, e.g. "\Core\db\process.json"
    $processDbPath = Join-Path -Path $FrameworkRoot -ChildPath ($relativeProcessPath.TrimStart('\'))

    $processResult = wtfxLoadJSON -Path $processDbPath
    if ($processResult.code -ne 0) {
        return (OPSreturn -Code -1 -Message "Could not load process.json: $($processResult.msg)" -Exception $processResult.exception)
    }
    $db = $processResult.data

    $timestampNow = Get-Date -Format 'dd.MM.yyyy ; HH:mm:ss'

    try {
        $db.running.'proc-name' = $ProcName
        $db.running.'proc-path' = $ProcPath
        $db.running.'action-id' = $ActionId
        $db.running.processid   = $ProcessId
        $db.running.cmdparams   = $CmdParams
        $db.running.'job-start' = $timestampNow
        $db.running.'job-state' = 'running'
    }
    catch {
        return (OPSreturn -Code -1 -Message "Could not update the in-memory 'running' node: $($_.Exception.Message)" -Exception $_.Exception)
    }

    $writeResult = wtfxWriteJSON -Path $processDbPath -Value $db
    if ($writeResult.code -ne 0) {
        return (OPSreturn -Code -1 -Message "Process was accepted but could not be persisted to process.json: $($writeResult.msg)" -Exception $writeResult.exception)
    }

    return (OPSreturn -Code 0 -Message "Process '$ProcName' (PID $ProcessId) registered successfully for action '$ActionId'." -Data $db.running)
}

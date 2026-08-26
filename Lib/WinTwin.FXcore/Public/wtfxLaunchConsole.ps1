function wtfxLaunchConsole {
    <#
    .SYNOPSIS
        Starts WTF.Console as a detached process for a previously generated script.

    .DESCRIPTION
        wtfxLaunchConsole is the generic, framework-wide replacement for
        Start-WtfConsoleProcess from DISM.UI.CC\wim.mounter.fx.ps1.

        The original helper always launched WTF.Console in framework mode with a
        hard-coded -Action mount contract. This function is mode-aware:

          framework  (default)
            -Action is mandatory and MUST exist as a top-level key in
            Core\db\jobaction.json (for example 'wim-mount'). Job-specific
            logging defaults (whether a log is written and how the file is named)
            are read from that node. Process metadata is written to
            Core\db\process.json (running.*) and the matching jobaction.json
            nodes (the Action node plus the shared 'wtfc' node).

          standalone
            No process/job databases are touched. -Action is optional.
            If -Logging is true, -Logfile becomes mandatory.

        The caller is responsible for deregistering itself from process.json
        BEFORE this function is invoked. Otherwise a still-running job-state
        blocks the hand-off, which is exactly the contract documented for
        wim.mounter -> WTF.Console.

        lastjob and linedup in process.json are intentionally left untouched.

    .PARAMETER Script
        Full path of the script that WTF.Console should execute inside its
        redirected child process. Mapped to WTF.Console's -ScriptPath.

    .PARAMETER Mode
        WTF.Console operating mode. framework (default) or standalone.
        Mapped to WTF.Console's -AppMode.

    .PARAMETER Action
        Job-action identifier. Mandatory in framework mode and must be defined
        in jobaction.json (for example wim-mount, wim-eject, uupd-catch).
        Mapped to WTF.Console's -Action.

    .PARAMETER Size
        Window size in the form WIDTHxHEIGHT (default: 800x600).
        Mapped to WTF.Console's -WinSize.

    .PARAMETER Logging
        Explicit logging switch (true/false, default false). In framework mode
        this only overrides jobaction.json when the caller actually passes the
        parameter. Otherwise the job's logfile[0] flag is used.

    .PARAMETER Logfile
        Full path of the log file. In framework mode a missing value is derived
        from jobaction.json logfile[1], replacing the [DATETIME] token.

    .PARAMETER FrameworkRoot
        Optional full path to the WinTwin.Fusion root (the folder that contains
        Core\config.json). Required for a reliable framework-mode hand-off when
        the function cannot infer the root from -WtfConsolePath.

    .PARAMETER WtfConsolePath
        Optional full path to WTF.Console.ps1. When omitted in framework mode
        the path is resolved from Core\config.json -> path.pstools.console.

    .OUTPUTS
        PSCustomObject from OPSreturn.
        On success (.code = 0) .data contains process id, command line, resolved
        paths, logging state and the action id.

    .EXAMPLE
        # Typical wim.mounter hand-off after the tool has cleared process.json:
        $launch = wtfxLaunchConsole -Script 'C:\WinTwin.Fusion\Core\export\mount.image.ps1' `
                                    -Mode framework `
                                    -Action 'wim-mount' `
                                    -FrameworkRoot 'C:\WinTwin.Fusion'

    .EXAMPLE
        wtfxLaunchConsole -Script 'D:\portable\job.ps1' -Mode standalone -Size '1024x768'

    .NOTES
        Part of: WinTwin.FXcore
        Replaces: Start-WtfConsoleProcess
        Depends on: OPSreturn, wtfxLoadJSON, wtfxWriteJSON, wtfxGetJobAction, wtfxSetJobAction
        See also: wtfConsoleScript
    #>

    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [Alias('ScriptPath')]
        [string]$Script,

        [Parameter(Mandatory = $false)]
        [ValidateSet('framework', 'standalone')]
        [string]$Mode = 'framework',

        [Parameter(Mandatory = $false)]
        [AllowEmptyString()]
        [string]$Action = '',

        [Parameter(Mandatory = $false)]
        [ValidatePattern('^\d{2,5}x\d{2,5}$')]
        [string]$Size = '800x600',

        [Parameter(Mandatory = $false)]
        [bool]$Logging = $false,

        [Parameter(Mandatory = $false)]
        [AllowEmptyString()]
        [Alias('LogFilePath')]
        [string]$Logfile = '',

        [Parameter(Mandatory = $false)]
        [AllowEmptyString()]
        [string]$FrameworkRoot = '',

        [Parameter(Mandatory = $false)]
        [AllowEmptyString()]
        [string]$WtfConsolePath = ''
    )

    $loggingWasBound = $PSBoundParameters.ContainsKey('Logging')
    $logfileWasBound = $PSBoundParameters.ContainsKey('Logfile') -and -not [string]::IsNullOrWhiteSpace($Logfile)

    # --- Shared validation ----------------------------------------------------
    if ([string]::IsNullOrWhiteSpace($Script)) {
        return (OPSreturn -Code fail -Message "wtfxLaunchConsole failed! Parameter 'Script' is required and must not be empty.")
    }
    if (-not (Test-Path -LiteralPath $Script -PathType Leaf)) {
        return (OPSreturn -Code fail -Message "wtfxLaunchConsole failed! Script file not found: '$Script'.")
    }

    try {
        $resolvedScript = (Resolve-Path -LiteralPath $Script).ProviderPath
    }
    catch {
        return (OPSreturn -Code fail -Message "wtfxLaunchConsole failed! Could not resolve Script path '$Script': $($_.Exception.Message)" -Exception $_.Exception)
    }

    $resolvedMode          = $Mode.ToLowerInvariant()
    $resolvedSize          = $Size
    $resolvedConsolePath   = $WtfConsolePath
    $resolvedFrameworkRoot = $FrameworkRoot
    $resolvedLogfile       = $Logfile
    $loggingEnabled        = $Logging
    $jobNode               = $null
    $timestampNow          = Get-Date -Format 'dd.MM.yyyy ; HH:mm:ss'
    $datetimeToken         = Get-Date -Format 'yyyyMMdd-HHmm'

    # =========================================================================
    # FRAMEWORK MODE
    # =========================================================================
    if ($resolvedMode -eq 'framework') {
        if ([string]::IsNullOrWhiteSpace($Action)) {
            return (OPSreturn -Code fail -Message "wtfxLaunchConsole failed! Parameter 'Action' is mandatory in framework mode and must match a jobaction.json key (for example 'wim-mount').")
        }

        # Infer the framework root from the console path when the caller did not pass it.
        if ([string]::IsNullOrWhiteSpace($resolvedFrameworkRoot) -and -not [string]::IsNullOrWhiteSpace($resolvedConsolePath)) {
            $consoleParent = Split-Path -Path $resolvedConsolePath -Parent
            $candidateRoot = Split-Path -Path $consoleParent -Parent
            if (Test-Path -LiteralPath (Join-Path $candidateRoot 'Core\config.json') -PathType Leaf) {
                $resolvedFrameworkRoot = $candidateRoot
            }
        }

        if ([string]::IsNullOrWhiteSpace($resolvedFrameworkRoot)) {
            return (OPSreturn -Code fail -Message "wtfxLaunchConsole failed! FrameworkRoot is required in framework mode (or must be inferable from -WtfConsolePath).")
        }
        if (-not (Test-Path -LiteralPath (Join-Path $resolvedFrameworkRoot 'Core\config.json') -PathType Leaf)) {
            return (OPSreturn -Code fail -Message "wtfxLaunchConsole failed! Core\\config.json was not found under FrameworkRoot '$resolvedFrameworkRoot'.")
        }

        $configResult = wtfxLoadJSON -JSONfile (Join-Path $resolvedFrameworkRoot 'Core\config.json')
        if ($configResult.code -ne 0) {
            return (OPSreturn -Code fail -Message "wtfxLaunchConsole failed! Could not load Core\\config.json: $($configResult.msg)" -Exception $configResult.exception)
        }
        $config = $configResult.data

        # Resolve WTF.Console.ps1 from config.json when the caller did not pass a path.
        if ([string]::IsNullOrWhiteSpace($resolvedConsolePath)) {
            try {
                $relativeConsole = [string]$config.path.pstools.console
            }
            catch {
                $relativeConsole = ''
            }
            if ([string]::IsNullOrWhiteSpace($relativeConsole)) {
                $relativeConsole = '\PS.Tweak.Tools\WTF.Console.ps1'
            }
            $resolvedConsolePath = Join-Path $resolvedFrameworkRoot ($relativeConsole.TrimStart('\'))
        }

        # --- process.json occupancy check ------------------------------------
        # Only one framework job may run at a time. lastjob / linedup stay unused.
        $processDbPath = $null
        try {
            $relativeProcess = [string]$config.path.appdb.process
            if (-not [string]::IsNullOrWhiteSpace($relativeProcess)) {
                $processDbPath = Join-Path $resolvedFrameworkRoot ($relativeProcess.TrimStart('\'))
            }
        }
        catch {
            $processDbPath = $null
        }
        if ([string]::IsNullOrWhiteSpace($processDbPath)) {
            $processDbPath = Join-Path $resolvedFrameworkRoot 'Core\db\process.json'
        }

        $processResult = wtfxLoadJSON -JSONfile $processDbPath
        if ($processResult.code -ne 0) {
            return (OPSreturn -Code fail -Message "wtfxLaunchConsole failed! Could not load process.json: $($processResult.msg)" -Exception $processResult.exception)
        }
        $processDb = $processResult.data

        $currentState = ''
        try { $currentState = [string]$processDb.running.'job-state' } catch { $currentState = '' }
        if ($currentState -eq 'running') {
            $blocker = ''
            try { $blocker = [string]$processDb.running.'proc-name' } catch { $blocker = 'unknown' }
            return (OPSreturn -Code fail -Message "wtfxLaunchConsole failed! A framework process is already running ('$blocker'). The caller must deregister itself from process.json before handing off to WTF.Console.")
        }

        # --- jobaction.json ---------------------------------------------------
        $jobResult = wtfxGetJobAction -FrameworkRoot $resolvedFrameworkRoot -ActionId $Action
        if ($jobResult.code -ne 0) {
            return (OPSreturn -Code fail -Message "wtfxLaunchConsole failed! Action '$Action' is not defined in jobaction.json: $($jobResult.msg)" -Exception $jobResult.exception)
        }
        $jobNode = $jobResult.data

        $jobLogEnabled = $false
        $jobLogPattern = ''
        try {
            if ($null -ne $jobNode.logfile) {
                $logEntry = @($jobNode.logfile)
                if ($logEntry.Count -ge 1) {
                    $jobLogEnabled = [System.Convert]::ToBoolean($logEntry[0])
                }
                if ($logEntry.Count -ge 2) {
                    $jobLogPattern = [string]$logEntry[1]
                }
            }
        }
        catch {
            $jobLogEnabled = $false
            $jobLogPattern = ''
        }

        # Caller-supplied -Logging wins; otherwise the job definition decides.
        if (-not $loggingWasBound) {
            $loggingEnabled = $jobLogEnabled
        }

        if ($logfileWasBound) {
            $resolvedLogfile = $Logfile
            if (-not $loggingWasBound) {
                $loggingEnabled = $true
            }
        }
        elseif ($loggingEnabled) {
            if (-not [string]::IsNullOrWhiteSpace($jobLogPattern)) {
                $resolvedLogfile = $jobLogPattern -replace '\[DATETIME\]', $datetimeToken
            }
            else {
                $logDir = Join-Path $resolvedFrameworkRoot 'Core\logs'
                try {
                    $relativeLogs = [string]$config.path.logs
                    if (-not [string]::IsNullOrWhiteSpace($relativeLogs)) {
                        $logDir = Join-Path $resolvedFrameworkRoot ($relativeLogs.TrimStart('\'))
                    }
                }
                catch { }
                $resolvedLogfile = Join-Path $logDir ("{0}.{1}.log" -f $datetimeToken, $Action)
            }
        }
        else {
            $resolvedLogfile = ''
        }
    }
    # =========================================================================
    # STANDALONE MODE
    # =========================================================================
    else {
        if ([string]::IsNullOrWhiteSpace($resolvedConsolePath)) {
            return (OPSreturn -Code fail -Message "wtfxLaunchConsole failed! Parameter 'WtfConsolePath' is required in standalone mode.")
        }
        if ($loggingEnabled -and [string]::IsNullOrWhiteSpace($resolvedLogfile)) {
            return (OPSreturn -Code fail -Message "wtfxLaunchConsole failed! Parameter 'Logfile' is required when Logging is true in standalone mode.")
        }
        if (-not $loggingEnabled) {
            $resolvedLogfile = ''
        }
    }

    if ([string]::IsNullOrWhiteSpace($resolvedConsolePath) -or -not (Test-Path -LiteralPath $resolvedConsolePath -PathType Leaf)) {
        return (OPSreturn -Code fail -Message "wtfxLaunchConsole failed! WTF.Console.ps1 was not found: '$resolvedConsolePath'.")
    }

    try {
        $resolvedConsolePath = (Resolve-Path -LiteralPath $resolvedConsolePath).ProviderPath
    }
    catch {
        return (OPSreturn -Code fail -Message "wtfxLaunchConsole failed! Could not resolve WtfConsolePath: $($_.Exception.Message)" -Exception $_.Exception)
    }

    if ($loggingEnabled -and -not [string]::IsNullOrWhiteSpace($resolvedLogfile)) {
        try {
            $logDirectory = Split-Path -Path $resolvedLogfile -Parent
            if (-not [string]::IsNullOrWhiteSpace($logDirectory) -and -not (Test-Path -LiteralPath $logDirectory -PathType Container)) {
                New-Item -ItemType Directory -Path $logDirectory -Force -ErrorAction Stop | Out-Null
            }
        }
        catch {
            return (OPSreturn -Code fail -Message "wtfxLaunchConsole failed! Could not create log directory for '$resolvedLogfile': $($_.Exception.Message)" -Exception $_.Exception)
        }
    }

    # --- Build the WTF.Console argument list ---------------------------------
    # Parameter names MUST match WTF.Console.ps1: ScriptPath, AppMode, Action,
    # WinSize, LogFilePath.
    $argList = [System.Collections.Generic.List[string]]::new()
    $argList.AddRange([string[]]@(
        '-NoLogo',
        '-NoProfile',
        '-ExecutionPolicy', 'Bypass',
        '-File', $resolvedConsolePath,
        '-ScriptPath', $resolvedScript,
        '-AppMode', $resolvedMode,
        '-WinSize', $resolvedSize
    ))

    if ($resolvedMode -eq 'framework') {
        $argList.Add('-Action')
        $argList.Add($Action)
    }
    elseif (-not [string]::IsNullOrWhiteSpace($Action)) {
        $argList.Add('-Action')
        $argList.Add($Action)
    }

    if ($loggingEnabled -and -not [string]::IsNullOrWhiteSpace($resolvedLogfile)) {
        $argList.Add('-LogFilePath')
        $argList.Add($resolvedLogfile)
    }

    $commandLine = ($argList | ForEach-Object {
        if ($_ -match '\s') { '"{0}"' -f $_ } else { $_ }
    }) -join ' '

    # --- Persist framework process / job metadata BEFORE the hand-off --------
    if ($resolvedMode -eq 'framework') {
        try {
            $processDb.running.'proc-name' = 'WTF.Console'
            $processDb.running.'proc-path' = $resolvedConsolePath
            $processDb.running.'action-id' = $Action
            $processDb.running.cmdparams   = $commandLine
            $processDb.running.'job-start' = $timestampNow
            $processDb.running.'job-state' = 'running'
        }
        catch {
            return (OPSreturn -Code fail -Message "wtfxLaunchConsole failed! Could not update the in-memory process.json running node: $($_.Exception.Message)" -Exception $_.Exception)
        }

        $writeProcess = wtfxWriteJSON -Path $processDbPath -Value $processDb
        if ($writeProcess.code -ne 0) {
            return (OPSreturn -Code fail -Message "wtfxLaunchConsole failed! Could not persist process.json: $($writeProcess.msg)" -Exception $writeProcess.exception)
        }

        # Action-specific node: mark the job as started and record its logfile flag.
        $null = wtfxSetJobAction -FrameworkRoot $resolvedFrameworkRoot -ActionId $Action -Field 'created' -Value $timestampNow
        $null = wtfxSetJobAction -FrameworkRoot $resolvedFrameworkRoot -ActionId $Action -Field 'state'   -Value $true
        if ($loggingEnabled -and -not [string]::IsNullOrWhiteSpace($resolvedLogfile)) {
            $null = wtfxSetJobAction -FrameworkRoot $resolvedFrameworkRoot -ActionId $Action -Field 'logfile' -Value @($true, $resolvedLogfile)
        }

        # Shared WTF.Console node so other tools can see who launched the console.
        $wtfcExists = wtfxGetJobAction -FrameworkRoot $resolvedFrameworkRoot -ActionId 'wtfc'
        if ($wtfcExists.code -eq 0) {
            $null = wtfxSetJobAction -FrameworkRoot $resolvedFrameworkRoot -ActionId 'wtfc' -Field 'script'    -Value $resolvedScript
            $null = wtfxSetJobAction -FrameworkRoot $resolvedFrameworkRoot -ActionId 'wtfc' -Field 'action-id' -Value $Action
            $null = wtfxSetJobAction -FrameworkRoot $resolvedFrameworkRoot -ActionId 'wtfc' -Field 'created'   -Value $timestampNow
            $null = wtfxSetJobAction -FrameworkRoot $resolvedFrameworkRoot -ActionId 'wtfc' -Field 'state'     -Value $true
            if ($loggingEnabled -and -not [string]::IsNullOrWhiteSpace($resolvedLogfile)) {
                $null = wtfxSetJobAction -FrameworkRoot $resolvedFrameworkRoot -ActionId 'wtfc' -Field 'logfile' -Value @($true, $resolvedLogfile)
            }
        }
    }

    # --- Detached launch ------------------------------------------------------
    # Start-Process is used instead of PSAppCoreLib\RunProcess so FXcore stays
    # free of a hard dependency on that module.
    try {
        $started = Start-Process -FilePath (Join-Path $PSHOME 'powershell.exe') `
                                 -ArgumentList $argList.ToArray() `
                                 -WindowStyle Normal `
                                 -PassThru `
                                 -ErrorAction Stop
    }
    catch {
        return (OPSreturn -Code fail -Message "wtfxLaunchConsole failed! Could not start WTF.Console: $($_.Exception.Message)" -Exception $_.Exception)
    }

    if ($null -eq $started) {
        return (OPSreturn -Code fail -Message "wtfxLaunchConsole failed! Start-Process returned no process object for WTF.Console.")
    }

    $resultData = [pscustomobject]@{
        ProcessId      = $started.Id
        ConsolePath    = $resolvedConsolePath
        Script         = $resolvedScript
        Mode           = $resolvedMode
        Action         = $Action
        Size           = $resolvedSize
        Logging        = $loggingEnabled
        Logfile        = $resolvedLogfile
        FrameworkRoot  = $resolvedFrameworkRoot
        CommandLine    = $commandLine
    }

    return (OPSreturn -Code success -Message "wtfxLaunchConsole: WTF.Console started (PID $($started.Id)) in '$resolvedMode' mode." -Data $resultData)
}

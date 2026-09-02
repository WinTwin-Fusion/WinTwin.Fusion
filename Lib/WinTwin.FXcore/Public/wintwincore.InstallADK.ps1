function wintwincore.InstallADK {
    <#
    .SYNOPSIS
        Installs the Windows ADK silently and completely hidden via adksetup.exe.
    .PARAMETER SetupPath
        Full path to adksetup.exe.
    .PARAMETER Features
        Optional list of ADK features to install. Defaults to the Deployment Tools
        and the USMT feature. Use 'OptionId.All' to install everything.
    .PARAMETER LogFile
        Optional path for the setup log file.
    .PARAMETER TimeoutMinutes
        Maximum time to wait for the setup to finish (default 60 minutes).
        If the timeout is reached the process is killed and $false is returned.
    .OUTPUTS
        [bool] $true only if the setup exited with code 0, otherwise $false.
    .EXAMPLE
    if (-not (CheckWindowsADK)) {
        if (-not (InstallADK -SetupPath 'C:\Sources\ADK\adksetup.exe' -LogFile 'C:\Temp\adk.log')) {
            throw 'ADK installation failed.'
        }
    }
    if (-not (CheckADKPEaddon)) {
        if (-not (InstallPEaddon -SetupPath 'C:\Sources\ADK\adkwinpesetup.exe' -LogFile 'C:\Temp\adkpe.log')) {
            throw 'ADK WinPE add-on installation failed.'
        }
    }
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$SetupPath,

        [Parameter(Mandatory = $false)]
        [string[]]$Features = @('OptionId.DeploymentTools', 'OptionId.UserStateMigrationTool'),

        [Parameter(Mandatory = $false)]
        [string]$LogFile,

        [Parameter(Mandatory = $false)]
        [int]$TimeoutMinutes = 60
    )

    $process = $null

    try {
        # --- Validate input ------------------------------------------------------
        if ([string]::IsNullOrWhiteSpace($SetupPath)) { return $false }
        if (-not (Test-Path -LiteralPath $SetupPath -PathType Leaf)) { return $false }

        # Resolve to an absolute path (Start-Process does not honour the PS location)
        $exePath = (Resolve-Path -LiteralPath $SetupPath -ErrorAction Stop).ProviderPath
        if ([System.IO.Path]::GetExtension($exePath) -ne '.exe') { return $false }

        # --- Build silent command line ------------------------------------------
        # /quiet   -> no UI at all
        # /norestart -> never reboot automatically
        # /ceip off -> disable customer experience improvement program
        $arguments = @('/quiet', '/norestart', '/ceip', 'off')

        if ($Features -and $Features.Count -gt 0) {
            $arguments += '/features'
            $arguments += $Features
        }

        if (-not [string]::IsNullOrWhiteSpace($LogFile)) {
            # Make sure the log directory exists, otherwise setup may fail
            $logDir = Split-Path -Path $LogFile -Parent
            if (-not [string]::IsNullOrWhiteSpace($logDir) -and -not (Test-Path -LiteralPath $logDir)) {
                New-Item -Path $logDir -ItemType Directory -Force -ErrorAction SilentlyContinue | Out-Null
            }
            $arguments += @('/log', $LogFile)
        }

        # --- Start the setup hidden in the background ---------------------------
        $process = Start-Process -FilePath $exePath `
                                 -ArgumentList $arguments `
                                 -WindowStyle Hidden `
                                 -PassThru `
                                 -ErrorAction Stop

        if ($null -eq $process) { return $false }

        # --- Wait with timeout protection ---------------------------------------
        if ($TimeoutMinutes -gt 0) {
            $timeoutMs = $TimeoutMinutes * 60 * 1000
            if (-not $process.WaitForExit($timeoutMs)) {
                # Setup hangs -> terminate and report failure
                try { $process.Kill() } catch { }
                return $false
            }
        }
        else {
            $process.WaitForExit()
        }

        # --- Evaluate exit code --------------------------------------------------
        $exitCode = $process.ExitCode
        if ($exitCode -eq 0) { return $true }

        return $false
    }
    catch {
        return $false
    }
    finally {
        if ($null -ne $process) {
            try { $process.Dispose() } catch { }
        }
    }
}

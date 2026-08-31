function wtfxInstallPEaddon {
    <#
    .SYNOPSIS
        Installs the Windows ADK WinPE add-on silently and hidden via adkwinpesetup.exe.
    .PARAMETER SetupPath
        Full path to adkwinpesetup.exe.
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
        [string]$LogFile,

        [Parameter(Mandatory = $false)]
        [int]$TimeoutMinutes = 60
    )

    $process = $null

    try {
        # --- Validate input ------------------------------------------------------
        if ([string]::IsNullOrWhiteSpace($SetupPath)) { return $false }
        if (-not (Test-Path -LiteralPath $SetupPath -PathType Leaf)) { return $false }

        $exePath = (Resolve-Path -LiteralPath $SetupPath -ErrorAction Stop).ProviderPath
        if ([System.IO.Path]::GetExtension($exePath) -ne '.exe') { return $false }

        # --- Build silent command line ------------------------------------------
        # The WinPE add-on only ships a single feature: OptionId.WindowsPreinstallationEnvironment
        $arguments = @(
            '/quiet',
            '/norestart',
            '/ceip', 'off',
            '/features', 'OptionId.WindowsPreinstallationEnvironment'
        )

        if (-not [string]::IsNullOrWhiteSpace($LogFile)) {
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
                try { $process.Kill() } catch { }
                return $false
            }
        }
        else {
            $process.WaitForExit()
        }

        # --- Evaluate exit code --------------------------------------------------
        if ($process.ExitCode -eq 0) { return $true }

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

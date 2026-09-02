function wintwincore.ConsoleScript {
    <#
    .SYNOPSIS
        Creates a script file that can later be executed by WTF.Console.

    .DESCRIPTION
        wintwincore.ConsoleScript is the generic, framework-wide replacement for tool-local helpers
        such as New-WimMountConsoleScript in DISM.UI.CC\wim.mounter.fx.ps1.

        The original helper both *assembled* a mount-specific here-string and *wrote* it to
        Core\export\mount.image.ps1. This function only owns the second part: it receives
        already prepared script text via -ScriptData (for example the $scriptContent variable
        from a caller) and writes it to -ScriptPath.

        -ScriptType is mandatory so callers already declare whether the payload is a
        PowerShell (ps1) or batch (cmd) script. WTF.Console currently always launches the
        payload with powershell.exe -File, so ScriptType is stored/validated for future use
        but does not change the write behaviour yet.

        Every outcome is returned through the module-internal OPSreturn helper.

    .PARAMETER ScriptPath
        Full destination path of the script file that should be created
        (for example C:\WinTwin.Fusion\Core\export\mount.image.ps1).

    .PARAMETER ScriptType
        Kind of script that is being written. Currently accepted values:
          ps1  - PowerShell script
          cmd  - Windows command script
        Reserved for a future WTF.Console execution mode. The value is validated now so
        existing callers do not have to change later.

    .PARAMETER ScriptData
        The actual script body. Accepts a string (including a here-string such as
        $scriptContent), a string array, or a scriptblock. Arrays are joined with
        Environment.NewLine; scriptblocks are converted via ToString().

    .OUTPUTS
        PSCustomObject from OPSreturn.
        On success (.code = 0) .data contains:
          Path, ScriptType, BytesWritten, Encoding.

    .EXAMPLE
        $scriptContent = @"
        Write-Output 'WIM MOUNT JOB STARTED'
        `$mountResult = MountWIMimage -WIMimage 'D:\images\install.wim' -IndexNo 1 -MountPoint 'C:\Mount'
        if (`$mountResult.code -ne 0) { throw `$mountResult.msg }
        exit 0
        "@

        $result = wintwincore.ConsoleScript -ScriptPath 'C:\WinTwin.Fusion\Core\export\mount.image.ps1' `
                                   -ScriptType ps1 `
                                   -ScriptData $scriptContent
        if ($result.code -eq 0) { $result.data.Path }

    .NOTES
        Part of: WinTwin.FXcore
        Replaces: New-WimMountConsoleScript (write/export part only)
        See also: wtfcLaunchConsole, OPSreturn
    #>

    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        # Full path of the file that will be created for WTF.Console.
        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string]$ScriptPath,

        # Declares the payload type for a future WTF.Console dispatcher.
        [Parameter(Mandatory = $true)]
        [ValidateSet('ps1', 'cmd')]
        [string]$ScriptType,

        # Prepared script body. Typical caller variable: $scriptContent.
        [Parameter(Mandatory = $true)]
        [AllowNull()]
        [AllowEmptyString()]
        [AllowEmptyCollection()]
        $ScriptData
    )

    # --- Parameter validation -------------------------------------------------
    if ([string]::IsNullOrWhiteSpace($ScriptPath)) {
        return (OPSreturn -Code fail -Message "wintwincore.ConsoleScript failed! Parameter 'ScriptPath' is required and must not be empty.")
    }

    if ($null -eq $ScriptData) {
        return (OPSreturn -Code fail -Message "wintwincore.ConsoleScript failed! Parameter 'ScriptData' is required and must not be null.")
    }

    # Normalize ScriptData so callers can pass a here-string, string[], or scriptblock
    # exactly the way New-WimMountConsoleScript built $scriptContent.
    try {
        if ($ScriptData -is [scriptblock]) {
            $normalizedContent = [string]$ScriptData.ToString()
        }
        elseif ($ScriptData -is [System.Collections.IEnumerable] -and $ScriptData -isnot [string]) {
            $normalizedContent = ($ScriptData | ForEach-Object { [string]$_ }) -join [Environment]::NewLine
        }
        else {
            $normalizedContent = [string]$ScriptData
        }
    }
    catch {
        return (OPSreturn -Code fail -Message "wintwincore.ConsoleScript failed! Could not normalize ScriptData: $($_.Exception.Message)" -Exception $_.Exception)
    }

    if ([string]::IsNullOrWhiteSpace($normalizedContent)) {
        return (OPSreturn -Code fail -Message "wintwincore.ConsoleScript failed! Parameter 'ScriptData' resolved to an empty script body.")
    }

    # ScriptType is reserved for WTF.Console, but we still refuse an obvious extension mismatch
    # so a cmd payload is not silently written as .ps1 (or the other way around).
    $declaredExtension = ".$($ScriptType.ToLowerInvariant())"
    $actualExtension   = [System.IO.Path]::GetExtension($ScriptPath)
    if (-not [string]::IsNullOrWhiteSpace($actualExtension) -and
        $actualExtension.ToLowerInvariant() -ne $declaredExtension) {
        return (OPSreturn -Code fail -Message "wintwincore.ConsoleScript failed! ScriptType '$ScriptType' does not match the destination extension '$actualExtension' of '$ScriptPath'.")
    }

    # --- Ensure destination directory -----------------------------------------
    try {
        $targetDirectory = Split-Path -Path $ScriptPath -Parent
        if (-not [string]::IsNullOrWhiteSpace($targetDirectory) -and -not (Test-Path -LiteralPath $targetDirectory -PathType Container)) {
            New-Item -ItemType Directory -Path $targetDirectory -Force -ErrorAction Stop | Out-Null
        }
    }
    catch {
        return (OPSreturn -Code fail -Message "wintwincore.ConsoleScript failed! Could not create destination directory for '$ScriptPath': $($_.Exception.Message)" -Exception $_.Exception)
    }

    # --- Persist the script ---------------------------------------------------
    # UTF8 without forcing a tool-specific BOM policy: Set-Content -Encoding UTF8 is the
    # same encoding New-WimMountConsoleScript already used for mount.image.ps1.
    try {
        Set-Content -LiteralPath $ScriptPath -Value $normalizedContent -Encoding UTF8 -Force -ErrorAction Stop
    }
    catch {
        return (OPSreturn -Code fail -Message "wintwincore.ConsoleScript failed! Could not write script file '$ScriptPath': $($_.Exception.Message)" -Exception $_.Exception)
    }

    if (-not (Test-Path -LiteralPath $ScriptPath -PathType Leaf)) {
        return (OPSreturn -Code fail -Message "wintwincore.ConsoleScript failed! Script file was not present after the write operation: '$ScriptPath'.")
    }

    $writtenItem = Get-Item -LiteralPath $ScriptPath -ErrorAction SilentlyContinue
    $resultData  = [pscustomobject]@{
        Path         = $ScriptPath
        ScriptType   = $ScriptType.ToLowerInvariant()
        BytesWritten = if ($null -ne $writtenItem) { [int64]$writtenItem.Length } else { 0 }
        Encoding     = 'UTF8'
    }

    return (OPSreturn -Code success -Message "wintwincore.ConsoleScript: Script file created successfully: $ScriptPath" -Data $resultData)
}

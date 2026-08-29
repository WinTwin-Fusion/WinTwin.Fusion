function wtfxGetPSExecutable {
    <#
    .SYNOPSIS
        Resolves the full path of the PowerShell executable that is currently running.

    .DESCRIPTION
        wtfxGetPSExecutable is the framework-wide, robust replacement for hard-coding
        'powershell.exe' when a WinTwin.Fusion tool needs to spawn a new PowerShell
        process (e.g. Start-Process). Hard-coding the executable name breaks as soon
        as the framework is run under a PowerShell edition/installation where the
        assumption does not hold - most notably PowerShell 7 (pwsh.exe), whose
        executable is NOT named powershell.exe, and whose $PSHOME can point to very
        different locations depending on how it was installed (MSI/ZIP under
        "Program Files\PowerShell\7", or the Microsoft Store package under
        "...\WindowsApps\Microsoft.PowerShell_...").

        Resolution strategy (in order):
          1. Ask the operating system directly: Get-Process -Id $PID returns the
             exact executable path of the currently running interpreter, regardless
             of PowerShell edition or installation method. This is always correct
             when it succeeds.
          2. Fallback (only used if step 1 fails, e.g. in a restricted host that
             cannot resolve MainModule/Path): derive the expected executable name
             from $PSVersionTable.PSEdition ('pwsh.exe' for Core, 'powershell.exe'
             for Desktop) and join it with $PSHOME.
          3. If neither step produced an existing file, the function fails instead
             of returning a path that does not resolve to a real executable.

        Always returns an OPSreturn object. On success (.code = 0) .data contains
        Path, Edition and Version, so a caller launching a child process can decide
        to keep it consistent with the currently running engine.

    .OUTPUTS
        PSCustomObject from OPSreturn.
        Success .data: Path (string), Edition (string), Version (string).

    .EXAMPLE
        $psExe = wtfxGetPSExecutable
        if ($psExe.code -ne 0) { throw $psExe.msg }
        Start-Process -FilePath $psExe.data.Path -ArgumentList $argList -PassThru

    .NOTES
        Part of: WinTwin.FXcore
        Replaces: hard-coded 'powershell.exe' / 'pwsh.exe' assumptions
        Used by: wtfxLaunchConsole (and recommended for WTF.Console.ps1's own
                  redirected child-process spawn)
        See also: OPSreturn
    #>

    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param()

    # --- Step 1: ask the OS directly for the currently running executable ------
    $resolvedExe = $null
    try {
        $resolvedExe = (Get-Process -Id $PID -ErrorAction Stop).Path
    }
    catch {
        $resolvedExe = $null
    }

    # --- Step 2: fallback derived from edition + $PSHOME ------------------------
    if ([string]::IsNullOrWhiteSpace($resolvedExe) -or -not (Test-Path -LiteralPath $resolvedExe -PathType Leaf)) {
        $exeName = if ($PSVersionTable.PSEdition -eq 'Core') { 'pwsh.exe' } else { 'powershell.exe' }
        try {
            $resolvedExe = Join-Path $PSHOME $exeName
        }
        catch {
            return (OPSreturn -Code fail -Message "wtfxGetPSExecutable failed! Could not build a fallback path from `$PSHOME: $($_.Exception.Message)" -Exception $_.Exception)
        }
    }

    # --- Step 3: final sanity check ----------------------------------------------
    if ([string]::IsNullOrWhiteSpace($resolvedExe) -or -not (Test-Path -LiteralPath $resolvedExe -PathType Leaf)) {
        return (OPSreturn -Code fail -Message "wtfxGetPSExecutable failed! Could not resolve a valid PowerShell executable (looked for: '$resolvedExe').")
    }

    $resultData = [pscustomobject]@{
        Path    = $resolvedExe
        Edition = [string]$PSVersionTable.PSEdition
        Version = [string]$PSVersionTable.PSVersion
    }

    return (OPSreturn -Code success -Message "wtfxGetPSExecutable: Resolved PowerShell executable: '$resolvedExe'." -Data $resultData)
}

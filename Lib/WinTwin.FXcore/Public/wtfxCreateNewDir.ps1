function wtfxCreateNewDir {
    <#
    .SYNOPSIS
        Creates a directory (including any missing parent folders in the chain).

    .DESCRIPTION
        wtfxCreateNewDir is the framework-wide, robust replacement for the previously
        undefined "CreateNewDir" calls scattered across tool-local code (e.g.
        DISM.UI.CC\wim.mounter.ps1). It creates the full directory chain for -Path in
        a single call - PowerShell's own New-Item -ItemType Directory already creates
        every missing intermediate folder, so no manual recursion is required.

        Behaviour:
          - If the target already exists AS A DIRECTORY, nothing is done and the
            function returns success immediately (idempotent - safe to call on every
            startup/job without checking Test-Path first).
          - If the target already exists AS A FILE (not a directory), the function
            fails unless -Force is supplied. With -Force, the file is deleted first
            and the directory chain is created in its place.
          - If the target does not exist at all, the full chain is created.

        Always returns an OPSreturn object. On success (.code = 0) .data contains
        Path and Created (boolean - $false when the directory already existed,
        $true when it was actually created by this call).

    .PARAMETER Path
        Full path of the directory that should exist afterwards. Mandatory.

    .PARAMETER Force
        When set, forcibly attempts to create the target directory even if a file
        with the same name already exists at that path (the file is removed first).
        Without -Force, an existing file at -Path causes the function to fail.

    .OUTPUTS
        PSCustomObject from OPSreturn.

    .EXAMPLE
        $result = wtfxCreateNewDir -Path 'C:\WinTwin.Fusion\Core\logs'
        if ($result.code -ne 0) { throw $result.msg }

    .EXAMPLE
        wtfxCreateNewDir -Path $WinTwin['export'] -Force

    .NOTES
        Part of: WinTwin.FXcore
        Replaces: the previously undefined "CreateNewDir" call sites
        See also: wtfxRemoveFolder, OPSreturn
    #>

    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string]$Path,

        [Parameter(Mandatory = $false)]
        [switch]$Force
    )

    if ([string]::IsNullOrWhiteSpace($Path)) {
        return (OPSreturn -Code fail -Message "wtfxCreateNewDir failed! Parameter 'Path' is required and must not be empty.")
    }

    # --- Already a directory: nothing to do -----------------------------------
    if (Test-Path -LiteralPath $Path -PathType Container) {
        $resultData = [pscustomobject]@{
            Path    = $Path
            Created = $false
        }
        return (OPSreturn -Code success -Message "wtfxCreateNewDir: Target already exists as a directory, nothing to do: '$Path'." -Data $resultData)
    }

    # --- Target exists but is a file, not a directory -------------------------
    if (Test-Path -LiteralPath $Path -PathType Leaf) {
        if (-not $Force) {
            return (OPSreturn -Code fail -Message "wtfxCreateNewDir failed! A file (not a directory) already exists at '$Path'. Use -Force to remove it and create the directory instead.")
        }

        try {
            Remove-Item -LiteralPath $Path -Force -ErrorAction Stop
        }
        catch {
            return (OPSreturn -Code fail -Message "wtfxCreateNewDir failed! Could not remove the existing file at '$Path' before creating the directory: $($_.Exception.Message)" -Exception $_.Exception)
        }
    }

    # --- Create the full directory chain ---------------------------------------
    try {
        New-Item -ItemType Directory -Path $Path -Force -ErrorAction Stop | Out-Null
    }
    catch {
        return (OPSreturn -Code fail -Message "wtfxCreateNewDir failed! Could not create directory '$Path': $($_.Exception.Message)" -Exception $_.Exception)
    }

    if (-not (Test-Path -LiteralPath $Path -PathType Container)) {
        return (OPSreturn -Code fail -Message "wtfxCreateNewDir failed! Directory was not present after the create operation: '$Path'.")
    }

    $resultData = [pscustomobject]@{
        Path    = $Path
        Created = $true
    }

    return (OPSreturn -Code success -Message "wtfxCreateNewDir: Directory created successfully: '$Path'." -Data $resultData)
}

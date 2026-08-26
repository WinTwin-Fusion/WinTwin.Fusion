function wtfxRemoveFolder {
    <#
    .SYNOPSIS
        Removes a directory, optionally including all of its content.

    .DESCRIPTION
        wtfxRemoveFolder is the counterpart to wtfxCreateNewDir and the framework-wide,
        robust replacement for ad-hoc "Remove-Item -Recurse" calls scattered across
        tool-local code.

        Behaviour:
          - If the target does not exist at all, the function is idempotent and
            returns success immediately (the desired end state - "folder is gone" -
            is already true).
          - If the target exists and is EMPTY, it is removed regardless of -Recursive.
          - If the target exists and is NOT EMPTY:
              -> without -Recursive: the function fails and nothing is deleted.
              -> with -Recursive: the target and all of its content are removed.

        Always returns an OPSreturn object. On success (.code = 0) .data contains
        Path and Existed (boolean - $false when there was nothing to remove).

    .PARAMETER Path
        Full path of the directory that should be removed. Mandatory.

    .PARAMETER Recursive
        When set, allows removing a non-empty directory (including all files and
        subfolders). Without this switch, a non-empty directory is left untouched
        and the function returns a failure result.

    .OUTPUTS
        PSCustomObject from OPSreturn.

    .EXAMPLE
        $result = wtfxRemoveFolder -Path 'C:\WinTwin.Fusion\Core\export' -Recursive
        if ($result.code -ne 0) { throw $result.msg }

    .EXAMPLE
        # Fails on purpose if the mount export folder still contains files:
        wtfxRemoveFolder -Path $WinTwin['export']

    .NOTES
        Part of: WinTwin.FXcore
        Counterpart to: wtfxCreateNewDir
        See also: OPSreturn
    #>

    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string]$Path,

        [Parameter(Mandatory = $false)]
        [switch]$Recursive
    )

    if ([string]::IsNullOrWhiteSpace($Path)) {
        return (OPSreturn -Code fail -Message "wtfxRemoveFolder failed! Parameter 'Path' is required and must not be empty.")
    }

    # --- Idempotent: target already gone ---------------------------------------
    if (-not (Test-Path -LiteralPath $Path)) {
        $resultData = [pscustomobject]@{
            Path    = $Path
            Existed = $false
        }
        return (OPSreturn -Code success -Message "wtfxRemoveFolder: Target does not exist, nothing to remove: '$Path'." -Data $resultData)
    }

    if (-not (Test-Path -LiteralPath $Path -PathType Container)) {
        return (OPSreturn -Code fail -Message "wtfxRemoveFolder failed! Target exists but is not a directory: '$Path'.")
    }

    # --- Check whether the directory is actually empty --------------------------
    try {
        $childItems = Get-ChildItem -LiteralPath $Path -Force -ErrorAction Stop
    }
    catch {
        return (OPSreturn -Code fail -Message "wtfxRemoveFolder failed! Could not enumerate the content of '$Path': $($_.Exception.Message)" -Exception $_.Exception)
    }

    $isEmpty = (@($childItems).Count -eq 0)

    if (-not $isEmpty -and -not $Recursive) {
        return (OPSreturn -Code fail -Message "wtfxRemoveFolder failed! Directory '$Path' is not empty. Use -Recursive to remove it including all of its content.")
    }

    # --- Remove the directory (Recurse is harmless on an already-empty folder) --
    try {
        Remove-Item -LiteralPath $Path -Recurse -Force -ErrorAction Stop
    }
    catch {
        return (OPSreturn -Code fail -Message "wtfxRemoveFolder failed! Could not remove directory '$Path': $($_.Exception.Message)" -Exception $_.Exception)
    }

    if (Test-Path -LiteralPath $Path) {
        return (OPSreturn -Code fail -Message "wtfxRemoveFolder failed! Directory '$Path' still exists after the remove operation.")
    }

    $resultData = [pscustomobject]@{
        Path    = $Path
        Existed = $true
    }

    return (OPSreturn -Code success -Message "wtfxRemoveFolder: Directory removed successfully: '$Path'." -Data $resultData)
}

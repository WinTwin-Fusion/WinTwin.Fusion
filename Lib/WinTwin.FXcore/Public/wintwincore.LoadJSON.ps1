function wintwincore.LoadJSON {
    <#
    .SYNOPSIS
    Loads and parses a JSON file into a PowerShell object.

    .DESCRIPTION
    The wintwincore.LoadJSON function reads a plain JSON file from disk, validates that it
    exists and that its content is syntactically valid JSON, and returns the parsed
    object via the standard OPSreturn contract. This function is the generic,
    reusable JSON-loading primitive for the whole WinTwin.Fusion framework - it does
    not know about any specific schema (config.json, jobaction.json, etc.).

    .PARAMETER Path
    Full path to the JSON file to load.

    .PARAMETER Depth
    Maximum depth passed to ConvertFrom-Json. Default is 20, which comfortably
    covers all currently known WinTwin.Fusion JSON schemas.

    .EXAMPLE
    $result = wintwincore.LoadJSON -Path "C:\WinTwin.Fusion\Core\config.json"
    if ($result.code -eq 0) { $config = $result.data }

    .NOTES
    Part of: WinTwin.FXcore
    See also: wintwincore.LoadJSONC, wintwincore.WriteJSON
    #>

    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string]$Path,

        [Parameter(Mandatory = $false)]
        [int]$Depth = 20
    )

    if ([string]::IsNullOrEmpty($Path)) {
        return (OPSreturn -Code -1 -Message "Parameter 'Path' is required but was not provided or is empty")
    }

    if (-not (Test-Path -Path $Path -PathType Leaf)) {
        return (OPSreturn -Code -1 -Message "JSON file not found: $Path")
    }

    try {
        $raw = Get-Content -Path $Path -Raw -Encoding UTF8 -ErrorAction Stop
    }
    catch {
        return (OPSreturn -Code -1 -Message "Could not read file '$Path': $($_.Exception.Message)" -Exception $_.Exception)
    }

    if ([string]::IsNullOrWhiteSpace($raw)) {
        return (OPSreturn -Code -1 -Message "JSON file '$Path' is empty")
    }

    try {
        $obj = $raw | ConvertFrom-Json -Depth $Depth -ErrorAction Stop
    }
    catch {
        return (OPSreturn -Code -1 -Message "File '$Path' does not contain valid JSON: $($_.Exception.Message)" -Exception $_.Exception)
    }

    return (OPSreturn -Code 0 -Message "JSON file loaded successfully: $Path" -Data $obj)
}

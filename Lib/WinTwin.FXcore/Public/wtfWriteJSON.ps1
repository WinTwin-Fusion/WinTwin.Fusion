function wtfWriteJSON {
    <#
    .SYNOPSIS
    Writes a value into a JSON (or JSONC) file, either replacing the whole document
    or a single nested property addressed via a dot-separated key path.

    .DESCRIPTION
    The wtfWriteJSON function is the generic, reusable JSON-writing primitive for the
    WinTwin.Fusion framework. It supports two modes:

      1) Whole-object mode (no -KeyPath given): the -Value parameter is serialized
         and completely replaces the file content. Use this when you already hold a
         fully assembled object in memory (e.g. after modifying the result of
         wtfLoadJSON / wtfLoadJSONC).

      2) Key-path mode (-KeyPath given): only the single nested property addressed
         by a dot-separated path (e.g. "path.root" or "wim-mount.path") is replaced
         inside the existing file; every other value in the document is left
         untouched. The file is read, patched in memory, and written back. This is
         the mode used by InitJobActionDB-style path synchronization logic so that
         unrelated document content is never accidentally altered.

    ‼ BACKWARD COMPATIBILITY: this function is purely additive - it does not replace
    or change any existing FXcore function, and its own contract (return via
    OPSreturn, -Code 0 on success / -1 on failure) matches every other public
    function of this module.

    .PARAMETER Path
    Full path to the target JSON/JSONC file. The file does not need to exist yet
    in whole-object mode (it will be created); in key-path mode the file MUST
    already exist.

    .PARAMETER Value
    The value to write. In whole-object mode this is the entire document; in
    key-path mode this is only the value that will be placed at the given
    -KeyPath.

    .PARAMETER KeyPath
    Optional dot-separated path to a nested property (e.g. "path.root",
    "appdb.actions"). When provided, only this property is updated; all sibling
    data is preserved. Intermediate nodes must already exist as objects.

    .PARAMETER Depth
    Maximum depth passed to ConvertTo-Json. Default is 20.

    .EXAMPLE
    wtfWriteJSON -Path "C:\WinTwin.Fusion\Core\config.json" -Value $config
    Whole-object mode: overwrites config.json with the in-memory $config object.

    .EXAMPLE
    wtfWriteJSON -Path "C:\WinTwin.Fusion\Core\config.json" -KeyPath "path.root" -Value "C:\WinTwin.Fusion"
    Key-path mode: updates only path.root, leaving the rest of config.json intact.

    .NOTES
    Part of: WinTwin.FXcore
    See also: wtfLoadJSON, wtfLoadJSONC
    #>

    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string]$Path,

        [Parameter(Mandatory = $true)]
        [AllowNull()]
        $Value,

        [Parameter(Mandatory = $false)]
        [AllowEmptyString()]
        [string]$KeyPath = "",

        [Parameter(Mandatory = $false)]
        [int]$Depth = 20
    )

    if ([string]::IsNullOrEmpty($Path)) {
        return (OPSreturn -Code -1 -Message "Parameter 'Path' is required but was not provided or is empty")
    }

    try {
        $targetDir = Split-Path -Path $Path -Parent
        if ($targetDir -and -not (Test-Path -Path $targetDir)) {
            New-Item -Path $targetDir -ItemType Directory -Force -ErrorAction Stop | Out-Null
        }
    }
    catch {
        return (OPSreturn -Code -1 -Message "Could not create target directory for '$Path': $($_.Exception.Message)" -Exception $_.Exception)
    }

    # --- Mode 1: whole-object replace ---
    if ([string]::IsNullOrEmpty($KeyPath)) {
        try {
            $json = $Value | ConvertTo-Json -Depth $Depth
            Set-Content -Path $Path -Value $json -Encoding UTF8 -Force -ErrorAction Stop
            return (OPSreturn -Code 0 -Message "JSON file written successfully (whole-object mode): $Path")
        }
        catch {
            return (OPSreturn -Code -1 -Message "Could not write JSON file '$Path': $($_.Exception.Message)" -Exception $_.Exception)
        }
    }

    # --- Mode 2: key-path patch ---
    if (-not (Test-Path -Path $Path -PathType Leaf)) {
        return (OPSreturn -Code -1 -Message "Cannot use -KeyPath: file does not exist: $Path")
    }

    try {
        $raw = Get-Content -Path $Path -Raw -Encoding UTF8 -ErrorAction Stop
        $doc = $raw | ConvertFrom-Json -Depth $Depth -ErrorAction Stop
    }
    catch {
        return (OPSreturn -Code -1 -Message "Could not read/parse existing file '$Path': $($_.Exception.Message)" -Exception $_.Exception)
    }

    $segments = $KeyPath -split '\.'
    if ($segments.Count -eq 0) {
        return (OPSreturn -Code -1 -Message "Parameter 'KeyPath' resolved to an empty path")
    }

    $node = $doc
    for ($i = 0; $i -lt ($segments.Count - 1); $i++) {
        $segment = $segments[$i]
        $prop = $node.PSObject.Properties[$segment]
        if ($null -eq $prop) {
            return (OPSreturn -Code -1 -Message "KeyPath segment '$segment' does not exist in '$Path' (full path: '$KeyPath')")
        }
        $node = $prop.Value
    }

    $finalKey  = $segments[-1]
    $finalProp = $node.PSObject.Properties[$finalKey]

    try {
        if ($null -eq $finalProp) {
            $node | Add-Member -MemberType NoteProperty -Name $finalKey -Value $Value -Force
        }
        else {
            $node.$finalKey = $Value
        }

        $json = $doc | ConvertTo-Json -Depth $Depth
        Set-Content -Path $Path -Value $json -Encoding UTF8 -Force -ErrorAction Stop
        return (OPSreturn -Code 0 -Message "JSON key path '$KeyPath' updated successfully in: $Path")
    }
    catch {
        return (OPSreturn -Code -1 -Message "Could not update key path '$KeyPath' in '$Path': $($_.Exception.Message)" -Exception $_.Exception)
    }
}

function wtfxLoadJSONC {
    <#
    .SYNOPSIS
    Loads and parses a JSONC (JSON with Comments) file into a PowerShell object.

    .DESCRIPTION
    The wtfxLoadJSONC function reads a JSONC file (e.g. jobaction.jsonc), strips
    single-line ('//') and block ('/* ... */') comments using a small state-machine
    based scanner (NOT a naive regex), and then parses the remaining, pure-JSON
    content exactly like wtfLoadJSON. The state machine tracks whether the scanner
    is currently inside a double-quoted string (including escaped quotes) so that
    '//' or '/*' occurring inside actual string values is never mistaken for a
    comment and stripped by accident.

    .PARAMETER Path
    Full path to the JSONC file to load.

    .PARAMETER Depth
    Maximum depth passed to ConvertFrom-Json. Default is 20.

    .EXAMPLE
    $result = wtfxLoadJSONC -Path "C:\WinTwin.Fusion\Core\db\jobaction.jsonc"
    if ($result.code -eq 0) { $jobActions = $result.data }

    .NOTES
    Part of: WinTwin.FXcore
    See also: wtfLoadJSON, wtfWriteJSON
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
        return (OPSreturn -Code -1 -Message "JSONC file not found: $Path")
    }

    try {
        $raw = Get-Content -Path $Path -Raw -Encoding UTF8 -ErrorAction Stop
    }
    catch {
        return (OPSreturn -Code -1 -Message "Could not read file '$Path': $($_.Exception.Message)" -Exception $_.Exception)
    }

    if ([string]::IsNullOrWhiteSpace($raw)) {
        return (OPSreturn -Code -1 -Message "JSONC file '$Path' is empty")
    }

    # --- State-machine based comment stripper ---
    # States: Normal, InString, InLineComment, InBlockComment
    $sb          = [System.Text.StringBuilder]::new()
    $len         = $raw.Length
    $inString    = $false
    $inLineComm  = $false
    $inBlockComm = $false
    $escapeNext  = $false

    for ($i = 0; $i -lt $len; $i++) {
        $ch  = $raw[$i]
        $next = if ($i + 1 -lt $len) { $raw[$i + 1] } else { [char]0 }

        if ($inLineComm) {
            if ($ch -eq "`n") {
                $inLineComm = $false
                [void]$sb.Append($ch)
            }
            continue
        }

        if ($inBlockComm) {
            if ($ch -eq '*' -and $next -eq '/') {
                $inBlockComm = $false
                $i++  # skip the trailing '/'
            }
            continue
        }

        if ($inString) {
            [void]$sb.Append($ch)
            if ($escapeNext) {
                $escapeNext = $false
            }
            elseif ($ch -eq '\') {
                $escapeNext = $true
            }
            elseif ($ch -eq '"') {
                $inString = $false
            }
            continue
        }

        # Normal state
        if ($ch -eq '"') {
            $inString = $true
            [void]$sb.Append($ch)
            continue
        }
        if ($ch -eq '/' -and $next -eq '/') {
            $inLineComm = $true
            $i++
            continue
        }
        if ($ch -eq '/' -and $next -eq '*') {
            $inBlockComm = $true
            $i++
            continue
        }

        [void]$sb.Append($ch)
    }

    $cleaned = $sb.ToString()

    if ([string]::IsNullOrWhiteSpace($cleaned)) {
        return (OPSreturn -Code -1 -Message "JSONC file '$Path' contained no usable JSON content after comment stripping")
    }

    try {
        $obj = $cleaned | ConvertFrom-Json -Depth $Depth -ErrorAction Stop
    }
    catch {
        return (OPSreturn -Code -1 -Message "File '$Path' does not contain valid JSON after comment stripping: $($_.Exception.Message)" -Exception $_.Exception)
    }

    return (OPSreturn -Code 0 -Message "JSONC file loaded successfully: $Path" -Data $obj)
}

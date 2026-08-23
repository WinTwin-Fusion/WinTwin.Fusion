function wtfLoadJSONC {
    <#
    .SYNOPSIS
        Reads a JSONC file, strips comments, and returns its parsed content.

    .DESCRIPTION
        wtfLoadJSONC validates the -JSONfile parameter, ensures the target file exists, reads its
        raw text content, strips both // line comments and /* */ block comments (while respecting
        string literals so that '//' or '/*' occurring inside a JSON string value are preserved),
        and converts the resulting plain JSON via ConvertFrom-Json. On any failure an OPSreturn
        error object is returned.

    .PARAMETER JSONfile
        Full path to the .jsonc file to read.

    .OUTPUTS
        PSCustomObject { .code, .msg, .data }
        .data = the parsed JSON content (PSCustomObject / array) on success.

    .EXAMPLE
        $r = wtfLoadJSONC -JSONfile 'C:\WinTwin.Fusion\Core\db\jobaction.jsonc'

    .NOTES
        Dependencies: OPSreturn.
        Comment-stripping is performed with a small state machine (not a single greedy regex) so
        that '//' or '/* */' sequences that appear inside quoted string values are not stripped.
    #>

    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory = $false)]
        [AllowEmptyString()]
        [string]$JSONfile = ""
    )

    if ([string]::IsNullOrWhiteSpace($JSONfile)) {
        return (OPSreturn -Code fail -Message "wtfLoadJSONC failed! Parameter 'JSONfile' is required and must not be empty.")
    }

    if (-not (Test-Path -Path $JSONfile -PathType Leaf)) {
        return (OPSreturn -Code fail -Message "wtfLoadJSONC failed! File not found: '$JSONfile'.")
    }

    try {
        $RawContent = Get-Content -Path $JSONfile -Raw -Encoding UTF8 -ErrorAction Stop
    }
    catch {
        return (OPSreturn -Code fail -Message "wtfLoadJSONC failed! Could not read file '$JSONfile': $($_.Exception.Message)" -Exception $_.Exception)
    }

    # Strip // and /* */ comments while respecting string literals.
    try {
        $sb          = [System.Text.StringBuilder]::new()
        $len         = $RawContent.Length
        $inString    = $false
        $inLineCmt   = $false
        $inBlockCmt  = $false
        $escapeNext  = $false

        for ($i = 0; $i -lt $len; $i++) {
            $c  = $RawContent[$i]
            $nc = if ($i + 1 -lt $len) { $RawContent[$i + 1] } else { [char]0 }

            if ($inLineCmt) {
                if ($c -eq "`n") { $inLineCmt = $false; [void]$sb.Append($c) }
                continue
            }
            if ($inBlockCmt) {
                if ($c -eq '*' -and $nc -eq '/') { $inBlockCmt = $false; $i++ }
                continue
            }
            if ($inString) {
                [void]$sb.Append($c)
                if ($escapeNext) { $escapeNext = $false }
                elseif ($c -eq '\') { $escapeNext = $true }
                elseif ($c -eq '"') { $inString = $false }
                continue
            }

            if ($c -eq '"') { $inString = $true; [void]$sb.Append($c); continue }
            if ($c -eq '/' -and $nc -eq '/') { $inLineCmt = $true; $i++; continue }
            if ($c -eq '/' -and $nc -eq '*') { $inBlockCmt = $true; $i++; continue }

            [void]$sb.Append($c)
        }

        $CleanJSON = $sb.ToString()
    }
    catch {
        return (OPSreturn -Code fail -Message "wtfLoadJSONC failed! Error while stripping comments from '$JSONfile': $($_.Exception.Message)" -Exception $_.Exception)
    }

    try {
        $ParsedContent = $CleanJSON | ConvertFrom-Json -ErrorAction Stop
    }
    catch {
        return (OPSreturn -Code fail -Message "wtfLoadJSONC failed! File '$JSONfile' does not contain valid JSON after comment-stripping: $($_.Exception.Message)" -Exception $_.Exception)
    }

    return (OPSreturn -Code success -Message "wtfLoadJSONC: File '$JSONfile' loaded and converted successfully." -Data $ParsedContent)
}

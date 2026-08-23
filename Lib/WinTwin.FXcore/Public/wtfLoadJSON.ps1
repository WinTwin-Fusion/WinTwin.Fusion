function wtfLoadJSON {
    <#
    .SYNOPSIS
        Reads a JSON file and returns its parsed content.

    .DESCRIPTION
        wtfLoadJSON validates the -JSONfile parameter, ensures the target file exists, reads its
        raw text content and converts it via ConvertFrom-Json. On any failure (missing/empty
        parameter, missing file, invalid JSON) an OPSreturn error object is returned.

    .PARAMETER JSONfile
        Full path to the .json file to read.

    .OUTPUTS
        PSCustomObject { .code, .msg, .data }
        .data = the parsed JSON content (PSCustomObject / array) on success.

    .EXAMPLE
        $r = wtfLoadJSON -JSONfile 'C:\WinTwin.Fusion\Core\config.json'
        if ($r.code -eq 0) { $r.data.appinfo.name }

    .NOTES
        Dependencies: OPSreturn.
    #>

    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory = $false)]
        [AllowEmptyString()]
        [string]$JSONfile = ""
    )

    if ([string]::IsNullOrWhiteSpace($JSONfile)) {
        return (OPSreturn -Code fail -Message "wtfLoadJSON failed! Parameter 'JSONfile' is required and must not be empty.")
    }

    if (-not (Test-Path -Path $JSONfile -PathType Leaf)) {
        return (OPSreturn -Code fail -Message "wtfLoadJSON failed! File not found: '$JSONfile'.")
    }

    try {
        $RawContent = Get-Content -Path $JSONfile -Raw -Encoding UTF8 -ErrorAction Stop
    }
    catch {
        return (OPSreturn -Code fail -Message "wtfLoadJSON failed! Could not read file '$JSONfile': $($_.Exception.Message)" -Exception $_.Exception)
    }

    try {
        $ParsedContent = $RawContent | ConvertFrom-Json -ErrorAction Stop
    }
    catch {
        return (OPSreturn -Code fail -Message "wtfLoadJSON failed! File '$JSONfile' does not contain valid JSON: $($_.Exception.Message)" -Exception $_.Exception)
    }

    return (OPSreturn -Code success -Message "wtfLoadJSON: File '$JSONfile' loaded successfully." -Data $ParsedContent)
}

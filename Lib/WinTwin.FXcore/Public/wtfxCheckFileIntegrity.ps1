function wtfxCheckFileIntegrity {
    <#
    .SYNOPSIS
    Verifies that a given file exists and matches an expected SHA hash value.

    .DESCRIPTION
    wtfxCheckFileIntegrity performs a reliable two-stage integrity check:
      1. Existence check: the supplied -Path is resolved to an absolute provider path
         and verified to be an existing FILE (not a directory, not a wildcard match).
      2. Hash check: the file hash is calculated with the requested SHA algorithm
         (SHA256 by default, SHA512 optional) and compared case-insensitively against
         the expected value supplied via -Hash.

    The function never throws. Every possible outcome is reported through the
    standardized OPSreturn object.

    .PARAMETER Path
    Full path to the file that has to be verified.

    .PARAMETER Algo
    SHA algorithm used for the hash calculation. Valid values: SHA256 (default), SHA512.

    .PARAMETER Hash
    Expected hash value of the file. Whitespace, dashes and colons are tolerated and
    stripped before comparison (allows pasting of formatted hash strings).

    .OUTPUTS
    [PSCustomObject] created by OPSreturn:
      success  -> file exists and hash matches
      fail     -> file missing / path invalid / hash mismatch
      error    -> unexpected runtime error (hash calculation failed, access denied, ...)

    .EXAMPLE
    $r = wtfxCheckFileIntegrity -Path 'C:\Sources\adksetup.exe' -Hash 'A1B2...'
    if ($r.code -eq 0) { 'File is valid' }

    .EXAMPLE
    wtfxCheckFileIntegrity -Path 'C:\ISO\winpe.wim' -Algo SHA512 -Hash '9F3C...'
    #>

    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Path,

        [Parameter(Mandatory = $false)]
        [ValidateSet('SHA256', 'SHA512')]
        [string]$Algo = 'SHA256',

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Hash
    )

    try {
        # ------------------------------------------------------------------
        # STEP 1: Normalize and validate the expected hash value
        # ------------------------------------------------------------------
        # Remove any formatting characters (spaces, dashes, colons) that are commonly
        # present when hashes are copied from checksum files or web pages.
        $expectedHash = ($Hash -replace '[\s\-:]', '').Trim().ToUpperInvariant()

        if ([string]::IsNullOrWhiteSpace($expectedHash)) {
            return OPSreturn -Code ([OPScode]::fail) -Message "The supplied hash value is empty or invalid."
        }

        # Expected hex length: SHA256 = 64 chars, SHA512 = 128 chars
        $expectedLength = switch ($Algo) {
            'SHA256' { 64 }
            'SHA512' { 128 }
        }

        if ($expectedHash -notmatch '^[0-9A-F]+$' -or $expectedHash.Length -ne $expectedLength) {
            return OPSreturn -Code ([OPScode]::fail) `
                             -Message "The supplied hash value is not a valid $Algo hash (expected $expectedLength hexadecimal characters, got $($expectedHash.Length))." `
                             -Data ([PSCustomObject]@{ Algorithm = $Algo; ExpectedHash = $expectedHash })
        }

        # ------------------------------------------------------------------
        # STEP 2: Resolve the path and make sure the target really is a file
        # ------------------------------------------------------------------
        # -LiteralPath is used everywhere so that special characters ([ ] etc.) in the
        # path are never interpreted as wildcards.
        if (-not (Test-Path -LiteralPath $Path)) {
            return OPSreturn -Code ([OPScode]::fail) -Message "File not found: $Path"
        }

        if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
            return OPSreturn -Code ([OPScode]::fail) -Message "The specified path is not a file: $Path"
        }

        # Convert to a fully qualified filesystem path (handles relative paths / PSDrives)
        $fileItem = Get-Item -LiteralPath $Path -Force -ErrorAction Stop
        $fullPath = $fileItem.FullName

        # Guard against non-filesystem providers
        if ($fileItem.PSProvider.Name -ne 'FileSystem') {
            return OPSreturn -Code ([OPScode]::fail) -Message "The specified path does not point to the file system: $Path"
        }

        # ------------------------------------------------------------------
        # STEP 3: Verify that the file is readable (avoids misleading hash errors)
        # ------------------------------------------------------------------
        try {
            $stream = [System.IO.File]::Open($fullPath,
                                             [System.IO.FileMode]::Open,
                                             [System.IO.FileAccess]::Read,
                                             [System.IO.FileShare]::ReadWrite)
            $stream.Close()
            $stream.Dispose()
        }
        catch {
            return OPSreturn -Code ([OPScode]::error) `
                             -Message "File exists but cannot be opened for reading: $fullPath" `
                             -Exception $_.Exception
        }

        # ------------------------------------------------------------------
        # STEP 4: Calculate the file hash
        # ------------------------------------------------------------------
        $hashResult = Get-FileHash -LiteralPath $fullPath -Algorithm $Algo -ErrorAction Stop

        if ($null -eq $hashResult -or [string]::IsNullOrWhiteSpace($hashResult.Hash)) {
            return OPSreturn -Code ([OPScode]::error) `
                             -Message "Failed to calculate the $Algo hash for: $fullPath"
        }

        $actualHash = $hashResult.Hash.Trim().ToUpperInvariant()

        # ------------------------------------------------------------------
        # STEP 5: Compare the hashes (ordinal, case-insensitive, constant contract)
        # ------------------------------------------------------------------
        $payload = [PSCustomObject]@{
            Path         = $fullPath
            Algorithm    = $Algo
            ExpectedHash = $expectedHash
            ActualHash   = $actualHash
            SizeBytes    = $fileItem.Length
        }

        if ([string]::Equals($actualHash, $expectedHash, [System.StringComparison]::OrdinalIgnoreCase)) {
            return OPSreturn -Code ([OPScode]::success) `
                             -Message "File integrity verified successfully ($Algo): $fullPath" `
                             -Data $payload
        }

        return OPSreturn -Code ([OPScode]::fail) `
                         -Message "File integrity check FAILED ($Algo). Expected '$expectedHash' but found '$actualHash' for: $fullPath" `
                         -Data $payload
    }
    catch {
        # ------------------------------------------------------------------
        # Catch-all: no exception ever leaves this function
        # ------------------------------------------------------------------
        return OPSreturn -Code ([OPScode]::error) `
                         -Message "Unexpected error during file integrity check: $($_.Exception.Message)" `
                         -Exception $_.Exception
    }
}


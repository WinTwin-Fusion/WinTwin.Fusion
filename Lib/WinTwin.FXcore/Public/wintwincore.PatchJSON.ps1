function wintwincore.PatchJSON {
    <#
    .SYNOPSIS
        Replaces a literal substring in every string value of a JSON document.

    .DESCRIPTION
        Loads a JSON file, recursively traverses objects and arrays, and replaces
        every literal occurrence of SearchValue in string values. Property names
        and non-string values are not modified.

        The patched document is written to a temporary file, validated, and then
        used to replace the original file. The function supports WhatIf, optional
        backup creation, case-sensitive matching, and the WinTwin.FXcore OPSreturn
        contract.

        Parsing and serializing the document can change insignificant formatting
        such as indentation and whitespace.

    .PARAMETER Path
        Full path to the JSON file.

    .PARAMETER SearchValue
        Literal text to find inside JSON string values.

    .PARAMETER ReplacementValue
        Literal replacement text. An empty string is allowed.

    .PARAMETER Depth
        Maximum serialization depth. Defaults to 100.

    .PARAMETER CaseSensitive
        Performs ordinal, case-sensitive matching. The default is ordinal,
        case-insensitive matching.

    .PARAMETER CreateBackup
        Creates a backup before replacing the original JSON file.

    .PARAMETER BackupPath
        Optional backup path. The default is "<Path>.bak".

    .EXAMPLE
        $result = wintwincore.PatchJSON `
            -Path 'D:\WinTwin.Fusion\Core\db\jobaction.json' `
            -SearchValue 'C:\WinTwin.Fusion' `
            -ReplacementValue 'D:\WinTwin.Fusion' `
            -CreateBackup

        if ($result.code -lt 0) {
            throw $result.msg
        }

    .EXAMPLE
        wintwincore.PatchJSON `
            -Path $jobActionPath `
            -SearchValue 'C:\WinTwin.Fusion' `
            -ReplacementValue $FrameworkRoot `
            -WhatIf

    .NOTES
        Part of: WinTwin.FXcore
        This function handles standard JSON. JSONC comments would be lost during
        parsing and serialization and are therefore intentionally not supported.
    #>

    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Path,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$SearchValue,

        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string]$ReplacementValue,

        [Parameter(Mandatory = $false)]
        [ValidateRange(2, 100)]
        [int]$Depth = 100,

        [Parameter(Mandatory = $false)]
        [switch]$CaseSensitive,

        [Parameter(Mandatory = $false)]
        [switch]$CreateBackup,

        [Parameter(Mandatory = $false)]
        [AllowEmptyString()]
        [string]$BackupPath = ''
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        return (OPSreturn `
            -Code -1 `
            -Message "JSON file not found: $Path")
    }

    try {
        $resolvedPath = (Resolve-Path -LiteralPath $Path -ErrorAction Stop).ProviderPath
        $raw = [System.IO.File]::ReadAllText(
            $resolvedPath,
            [System.Text.Encoding]::UTF8
        )

        if ([string]::IsNullOrWhiteSpace($raw)) {
            return (OPSreturn `
                -Code -1 `
                -Message "JSON file is empty: $resolvedPath")
        }

        # Windows PowerShell 5.1 has no -Depth parameter on ConvertFrom-Json.
        if ($PSVersionTable.PSVersion.Major -ge 6) {
            $document = $raw | ConvertFrom-Json -Depth $Depth -ErrorAction Stop
        }
        else {
            $document = $raw | ConvertFrom-Json -ErrorAction Stop
        }
    }
    catch {
        return (OPSreturn `
            -Code -1 `
            -Message "Could not read or parse JSON file '$Path': $($_.Exception.Message)" `
            -Exception $_.Exception)
    }

    $comparison = if ($CaseSensitive) {
        [System.StringComparison]::Ordinal
    }
    else {
        [System.StringComparison]::OrdinalIgnoreCase
    }

    $patchContext = [pscustomobject]@{
        MatchedStringValues = 0
        Replacements        = 0
    }

    function ReplaceLiteralString {
        [CmdletBinding()]
        param(
            [Parameter(Mandatory = $true)]
            [AllowEmptyString()]
            [string]$InputString,

            [Parameter(Mandatory = $true)]
            [ValidateNotNull()]
            $Context
        )

        $cursor = 0
        $localCount = 0
        $builder = New-Object System.Text.StringBuilder

        while ($cursor -lt $InputString.Length) {
            $index = $InputString.IndexOf(
                $SearchValue,
                $cursor,
                $comparison
            )

            if ($index -lt 0) {
                [void]$builder.Append($InputString.Substring($cursor))
                break
            }

            [void]$builder.Append(
                $InputString.Substring($cursor, $index - $cursor)
            )
            [void]$builder.Append($ReplacementValue)

            $cursor = $index + $SearchValue.Length
            $localCount++
        }

        if ($localCount -eq 0) {
            return $InputString
        }

        $Context.MatchedStringValues++
        $Context.Replacements += $localCount

        return $builder.ToString()
    }

    function Update-JsonNode {
        [CmdletBinding()]
        param(
            [Parameter(Mandatory = $false)]
            [AllowNull()]
            $Node,

            [Parameter(Mandatory = $true)]
            [ValidateNotNull()]
            $Context
        )

        if ($null -eq $Node) {
            return $null
        }

        if ($Node -is [string]) {
            return (ReplaceLiteralString `
                -InputString $Node `
                -Context $Context)
        }

        if ($Node -is [System.Collections.IDictionary]) {
            foreach ($key in @($Node.Keys)) {
                $Node[$key] = Update-JsonNode `
                    -Node $Node[$key] `
                    -Context $Context
            }

            return $Node
        }

        if ($Node -is [System.Collections.IList]) {
            for ($index = 0; $index -lt $Node.Count; $index++) {
                $Node[$index] = Update-JsonNode `
                    -Node $Node[$index] `
                    -Context $Context
            }

            return $Node
        }

        if ($Node -is [pscustomobject]) {
            foreach ($property in @($Node.PSObject.Properties)) {
                if ($property.IsSettable) {
                    $property.Value = Update-JsonNode `
                        -Node $property.Value `
                        -Context $Context
                }
            }

            return $Node
        }

        return $Node
    }

    try {
        $document = Update-JsonNode `
            -Node $document `
            -Context $patchContext
    }
    catch {
        return (OPSreturn `
            -Code -1 `
            -Message "Could not traverse JSON document '$resolvedPath': $($_.Exception.Message)" `
            -Exception $_.Exception)
    }

    $resultData = [pscustomobject]@{
        Path                = $resolvedPath
        SearchValue         = $SearchValue
        ReplacementValue    = $ReplacementValue
        MatchedStringValues = $patchContext.MatchedStringValues
        Replacements        = $patchContext.Replacements
        Changed             = ($patchContext.Replacements -gt 0)
        BackupPath          = $null
    }

    if ($patchContext.Replacements -eq 0) {
        return (OPSreturn `
            -Code 1 `
            -Message "No matching string value was found. The file was not changed: $resolvedPath" `
            -Data $resultData)
    }

    $operation = 'Replace {0} occurrence(s) in {1} JSON string value(s)' -f `
        $patchContext.Replacements,
        $patchContext.MatchedStringValues

    if (-not $PSCmdlet.ShouldProcess($resolvedPath, $operation)) {
        return (OPSreturn `
            -Code 1 `
            -Message 'Patch operation was not executed.' `
            -Data $resultData)
    }

    $directory = Split-Path -Path $resolvedPath -Parent
    $fileName = Split-Path -Path $resolvedPath -Leaf
    $tempName = '.{0}.{1}.tmp' -f `
        $fileName,
        [guid]::NewGuid().ToString('N')
    $tempPath = Join-Path -Path $directory -ChildPath $tempName

    $replaceBackupPath = $null
    $deleteReplaceBackup = $false
    
    try {
        $json = $document | ConvertTo-Json -Depth $Depth

        # UTF-8 without BOM on Windows PowerShell 5.1 and PowerShell 7+.
        $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
        [System.IO.File]::WriteAllText( $tempPath, $json, $utf8NoBom )

        # Validate generated JSON before modifying the original file.
        $validationRaw = [System.IO.File]::ReadAllText( $tempPath, [System.Text.Encoding]::UTF8 )

        if ($PSVersionTable.PSVersion.Major -ge 6) {
            $null = $validationRaw |
                ConvertFrom-Json -Depth $Depth -ErrorAction Stop
        }
        else {
            $null = $validationRaw |
                ConvertFrom-Json -ErrorAction Stop
        }

        if ($CreateBackup) {
            if (:IsNullOrWhiteSpace($BackupPath)) {
                $replaceBackupPath = "$resolvedPath.bak"
            }
            else {
                $replaceBackupPath =
                    $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath(
                        $BackupPath
                    )
            }

            # Preserves the existing force behavior.
            if (Test-Path -LiteralPath $replaceBackupPath) {
                Remove-Item -LiteralPath $replaceBackupPath -Force -ErrorAction Stop
            }

            $resultData.BackupPath = $replaceBackupPath
        }
        else {
            # Some PowerShell/.NET combinations treat $null as an empty path
            # when calling File.Replace. Therefore, a genuine temporary
            # backup path is used and removed after a successful replacement.
            $replaceBackupPath = Join-Path -Path $directory -ChildPath ('.{0}.{1}.replace.bak' -f $fileName, [System.Guid]::NewGuid().ToString('N'))
            $deleteReplaceBackup = $true
        }

        [System.IO.File]::Replace( $tempPath, $resolvedPath, $replaceBackupPath )

        if ($deleteReplaceBackup -and (Test-Path -LiteralPath $replaceBackupPath)) {
            Remove-Item -LiteralPath $replaceBackupPath -Force -ErrorAction SilentlyContinue
        }

        return (OPSreturn `
            -Code 0 `
            -Message "JSON file patched successfully: $resolvedPath" `
            -Data $resultData)
    }
    catch {
        if (Test-Path -LiteralPath $tempPath) {
            Remove-Item -LiteralPath $tempPath -Force -ErrorAction SilentlyContinue
        }

        return (OPSreturn `
            -Code -1 `
            -Message "Could not persist patched JSON file '$resolvedPath': $($_.Exception.Message)" `
            -Data $resultData `
            -Exception $_.Exception)
    }
}

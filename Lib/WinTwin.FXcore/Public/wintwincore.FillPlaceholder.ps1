function wintwincore.FillPlaceholder {
    <#
    .SYNOPSIS
        wintwincore.FillPlaceholder is a simple function that fills placeholders in a text with predefined values.
    .DESCRIPTION
        The wintwincore.FillPlaceholder function replaces predefined placeholders within a specific text with the
        provided values. The function expects the text containing the placeholders to be passed via the
        -text parameter. The -txtval ​​parameter defines the new values ​​to be inserted in place of the
        placeholders. The function uses OPSreturn to generate a standardized return object. If the number
        of placeholders matches the number of provided replacement values, the placeholders are replaced.
        If the counts do not match, the original text—including the empty placeholders—is returned. If
        errors occur, a corresponding error message is returned. An appropriate OPSreturn object is
        created based on the specific scenario.
    .PARAMETER text
        Mandatory parameter. Must be specified as a string and cannot be null or empty.
        This is the string that should contain at least one placeholder (in the form of {0}).
    .PARAMETER txtval
        Although the parameter is defined as optional, it should always be provided; otherwise,
        the text will be returned with empty placeholders. This parameter must be an array,
        and the number of array elements should match the number of placeholders in the text.
    .EXAMPLE
        $newText = wintwincore.FillPlaceholder -text "{0} Message: Have a {1} day!" -txtval @("Importang","great")
        if ( $newText.code -gt 0 ) { $replaced = $newText.data }
    .EXAMPLE
        $newText = wintwincore.FillPlaceholder -text "{0} Message: Have a {1} day!" -txtval @("Just another", "nice")
        if ( $newText.code -lt 0 ) { Write-Host "$($newText.message)`n$($newText.exception)" }
    #>
    
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$text,
        
        [Parameter(Mandatory = $false)]
        [string[]]$txtval = @()
    )

    try {
    
        $placeholder = [regex]::Matches($text, '\{\d+\}')

        if ( $placeholder.Count -eq 0) {
            # Passed text did not had any placeholders
            return (OPSreturn -Code 0 -Message "No placeholders found in passed text." -Data [string]$text)
        }

        # Don't just consider the number of matches:
        # "{0} {0}" requires only one value but has two matches.
        $requiredIndexes = @(
            $placeholder | ForEach-Object {$_.Value.Trim('{', '}')} | Sort-Object -Unique
        )

        $highestIndex = ($requiredIndexes | Measure-Object -Maximum).Maximum

        if ($txtval.Count -le $highestIndex) {
            return (OPSreturn -Code 1 -Message "Highest placeholder index: $highestIndex; passed arguments: $($txtval.Count)." -Data $text)
        }

        $newText = [string]::Format($text, [object[]]$txtval)
        return (OPSreturn -Code 0 -Message "$($MyInvocation.MyCommand.Name) successfully finished." -Data [string]$newtext)
    }
    catch {
        return (OPSreturn -Code -1 -Message "$($MyInvocation.MyCommand.Name) failed replacing placeholders with given text." -Data $null -Exception [string]$_.Exception.Message)
    }
}
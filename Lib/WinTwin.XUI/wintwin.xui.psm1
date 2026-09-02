<#
.SYNOPSIS
    WinTin.XUI (part of WinTwin.Fusion Framework)
    A PowerShell Library that provides several UI-related functions
.DESCRIPTION
    DESCRIPTION
.EXAMPLE
    ... TO BE DOCUMENTED ...
.REMARKS
    IMPORTANT NOTE: This module follows an Enterprise-Pattern with three simple steps
    → Import the local.httpserver-Module
    → Configure the server via SetCoreConfig
    → Start using the Module    
.NOTES
    Creation Date : 23.08.2026
    Last Update   : 24.08.2026
    Version       : 1.00.03
    Author        : Praetoriani (a.k.a. M.Sczepanski)
    Website       : https://github.com/WinTwin-Fusion/WinTwin.XUI

    REQUIREMENTS:
    - WinTwin.Fusion Framework
    - PowerShell 5.1 or higher

#>

# ____________________________________________________________________________________________________
#  → SECTION 1: MODULE CONFIGURATION
# ‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾
# In this section we're defining the absolute minimum configuration for WinTwin.XUI

$script:root = $PSScriptRoot # ← This is the root directory of the module (needed for internal ressources)

function LoadCoreConfig () {

    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory = $false)]
        [AllowEmptyString()]
        [string]$mode
    )

    # ... to be continued ...
}

# ____________________________________________________________________________________________________
#  → SECTION PLACEHOLDE: 
# ‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾


# ____________________________________________________________________________________________________
#  → SECTION: BOOTSTRAPING/DOT-SOURCING
# ‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾
# The Reason, why we do the dot-sourcing at the beginnging of the module is, that we have access to
# all public and private functions of this module during the runtime of local.httpserver.psm1.

# Get public and private function definition files
$PublicFunctions = @(Get-ChildItem -Path $script:root\Public\*.ps1 -ErrorAction SilentlyContinue)
$PrivateFunctions = @(Get-ChildItem -Path $script:root\Private\*.ps1 -ErrorAction SilentlyContinue)

# Import all functions
foreach ($ImportFile in @($PublicFunctions + $PrivateFunctions)) {
    try {
        Write-Verbose "Importing function from file: $($ImportFile.FullName)"
        . $ImportFile.FullName
    }
    catch {
        Write-Error "Failed to import function $($ImportFile.FullName): $($_.Exception.Message)"
    }
}

# ‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾
# ‼ NOTE: AS A PERSONAL DECISION, EXPORT-MODULEMEMBER ISN'T USED ANYMORE.
# EXPORT OF THE FUNCTIONS WILL FULLY BE HANDLED IN local.httpserver.psd1
# ____________________________________________________________________________________________________

# Export public functions only
#if ($PublicFunctions) {
#    Export-ModuleMember -Function ($PublicFunctions.BaseName)
#}
# Bootstraping finished.
# The code below this line has now access to the public and private functions of this module.
# ____________________________________________________________________________________________________


# Module initialization message
[string] $finalMessage = @(
"‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾"
"WinTwin.XUI library loaded successfully. Available functions:"
"$(($PublicFunctions.BaseName) -join ', ')"
"___________________________________________________________________________"
""
) -join "`n"
Write-Verbose $finalMessage

<#
.SYNOPSIS
    Retrieves detailed information about the installed Windows operating system.

.DESCRIPTION
    GetWinVersion determines the installed Windows product name, feature
    release, build number, update build revision, architecture, and version.
    The function uses information from both of the following sources:
    - Win32_OperatingSystem via CIM
    - HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion

    The CIM operating system caption is preferred for the product name because
    registry values may still report "Windows 10" on Windows 11 systems for
    compatibility reasons.
    The Windows feature release, for example 24H2 or 25H2, is primarily read
    from the DisplayVersion registry value. If DisplayVersion is unavailable,
    ReleaseId and known Windows build numbers are used as fallback sources.
    The function always returns an OPSreturn-style PSCustomObject with the
    following properties:

    code
        0 indicates success.
        1 indicates that the operating system could not be determined.

    message
        Contains a human-readable status or error message.

    data
        Contains the detected Windows version information on success.
        The value is $null if detection fails.

.OUTPUTS
    System.Management.Automation.PSCustomObject
    The returned object has the following structure:
    [pscustomobject]@{
        code    = [int]
        message = [string]
        data    = [object]
    }

    The data property contains:

    osname
        Windows product name, for example "Microsoft Windows 11 Pro".
    osvers
        Windows feature release, for example "24H2" or "25H2".
    build
        Base operating system build number, for example 26100.
    revision
        Update Build Revision, also known as UBR.
    fullbuild
        Complete build number, for example "26100.4946".
    version
        Windows version reported by Win32_OperatingSystem.
    architecture
        Operating system architecture, for example "64-bit".
    iswindowsclient
        Indicates whether the operating system is a Windows client edition.
    iswindowsserver
        Indicates whether the operating system is a Windows Server edition.
    detectionmethod
        Describes how the feature release was determined.

.EXAMPLE
    # Retrieves information about the local Windows installation.
    $result = wintwincore.GetWinVersion
    if ($result.code -eq 0) { $result.data }
    else { Write-Warning $result.message }

.EXAMPLE
    # Checks whether the computer is running Windows 11 version 24H2 or 25H2.
    $result = wintwincore.GetWinVersion
    if ($result.code -eq 0 -and $result.data.osname -like '*Windows 11*' -and $result.data.osvers -in @('24H2', '25H2')) {
        Write-Host 'The operating system is supported.'
    }

.EXAMPLE
    # Produces output similar to: Microsoft Windows 11 Pro 24H2, Build 26100.4946
    $result = wintwincore.GetWinVersion
    if ($result.code -eq 0) {
        '{0} {1}, Build {2}' -f `
            $result.data.osname,
            $result.data.osvers,
            $result.data.fullbuild
    }


.NOTES
    The function is designed for Windows PowerShell 5.1 and PowerShell 7.

    DisplayVersion is preferred over hard-coded build mappings. This makes
    the function more resilient when newer Windows feature releases become
    available.

    The build mapping is only used if DisplayVersion and ReleaseId are
    unavailable or invalid. Future Windows releases that are not yet part of
    the fallback mapping will return "Unknown" as osvers while still returning
    the detected product name and build number.

    This function does not require administrative privileges under normal
    Windows configurations.
#>
function wintwincore.GetWinVersion {

    [CmdletBinding()]
    [OutputType([System.Management.Automation.PSCustomObject])]
    param()

    $registryPath = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion'

    try {
        # Initialize all values so that individual data-source failures can be
        # handled without aborting the entire detection process.
        $currentVersion = $null
        $cimOs = $null
        $registryError = $null
        $cimError = $null

        # Read the CurrentVersion registry key. This source provides values such
        # as DisplayVersion, CurrentBuild, and UBR.
        try {
            $currentVersion = Get-ItemProperty `
                -Path $registryPath `
                -ErrorAction Stop
        }
        catch {
            $registryError = $_.Exception.Message
            Write-Verbose "Unable to read the CurrentVersion registry key: $registryError"
        }

        # Query Win32_OperatingSystem. Its Caption value is generally more
        # reliable than the registry ProductName value on Windows 11.
        try {
            $cimOs = Get-CimInstance `
                -ClassName Win32_OperatingSystem `
                -ErrorAction Stop
        }
        catch {
            $cimError = $_.Exception.Message
            Write-Verbose "Unable to query Win32_OperatingSystem: $cimError"
        }

        # At least one source must be available.
        if ($null -eq $currentVersion -and $null -eq $cimOs) {
            $errorDetails = @(
                if ($registryError) {
                    "Registry: $registryError"
                }

                if ($cimError) {
                    "CIM: $cimError"
                }
            ) -join '; '

            return [pscustomobject]@{
                code    = [int]1
                message = [string]"Failed to retrieve Windows version information. $errorDetails"
                data    = $null
            }
        }

        # ---------------------------------------------------------------------
        # Determine the base build number.
        # ---------------------------------------------------------------------
        $buildNumber = $null

        if (
            $null -ne $currentVersion -and
            $null -ne $currentVersion.CurrentBuild -and
            "$($currentVersion.CurrentBuild)" -match '^\d+$'
        ) {
            $buildNumber = [int]$currentVersion.CurrentBuild
        }
        elseif (
            $null -ne $currentVersion -and
            $null -ne $currentVersion.CurrentBuildNumber -and
            "$($currentVersion.CurrentBuildNumber)" -match '^\d+$'
        ) {
            $buildNumber = [int]$currentVersion.CurrentBuildNumber
        }
        elseif (
            $null -ne $cimOs -and
            $null -ne $cimOs.BuildNumber -and
            "$($cimOs.BuildNumber)" -match '^\d+$'
        ) {
            $buildNumber = [int]$cimOs.BuildNumber
        }

        if ($null -eq $buildNumber) {
            return [pscustomobject]@{
                code    = [int]1
                message = [string]'Failed to determine the Windows build number.'
                data    = $null
            }
        }

        # ---------------------------------------------------------------------
        # Determine the Update Build Revision.
        # ---------------------------------------------------------------------
        $revision = $null

        if ( $null -ne $currentVersion -and $null -ne $currentVersion.UBR -and "$($currentVersion.UBR)" -match '^\d+$') {
            $revision = [int]$currentVersion.UBR
        }
        elseif ($null -ne $cimOs -and $null -ne $cimOs.Version -and "$($cimOs.Version)" -match '^\d+\.\d+\.\d+\.(\d+)$') {
            $revision = [int]$Matches[1]
        }

        if ($null -ne $revision) {
            $fullBuild = '{0}.{1}' -f $buildNumber, $revision
        }
        else {
            $fullBuild = [string]$buildNumber
        }

        # ---------------------------------------------------------------------
        # Determine the Windows product name.
        # ---------------------------------------------------------------------
        $cimProductName = $null
        $registryProductName = $null

        if ($null -ne $cimOs -and $cimOs.Caption) {
            $cimProductName = [string]$cimOs.Caption
        }

        if ($null -ne $currentVersion -and $currentVersion.ProductName) {
            $registryProductName = [string]$currentVersion.ProductName
        }

        if (-not [string]::IsNullOrWhiteSpace($cimProductName)) {
            $osName = $cimProductName.Trim()
        }
        elseif (-not [string]::IsNullOrWhiteSpace($registryProductName)) {
            $osName = $registryProductName.Trim()
        }
        else {
            $osName = 'Unknown Windows'
        }

        # Some systems retain "Windows 10" in ProductName even though the build
        # number identifies Windows 11. Correct this only when CIM did not return
        # a usable caption.
        if ([string]::IsNullOrWhiteSpace($cimProductName) -and $buildNumber -ge 22000 -and $osName -like '*Windows 10*') {
            $osName = $osName -replace 'Windows 10', 'Windows 11'
        }

        # ---------------------------------------------------------------------
        # Determine whether this is a client or server installation.
        #
        # Win32_OperatingSystem.ProductType values:
        #   1 = Workstation
        #   2 = Domain Controller
        #   3 = Server
        # ---------------------------------------------------------------------
        $isWindowsClient = $null
        $isWindowsServer = $null

        if ($null -ne $cimOs -and $null -ne $cimOs.ProductType) {
            $productType = [int]$cimOs.ProductType
            $isWindowsClient = ($productType -eq 1)
            $isWindowsServer = ($productType -in 2, 3)
        }
        else {
            # Use the product name only as a fallback when ProductType is not
            # available.
            $isWindowsServer = ($osName -like '*Server*')
            $isWindowsClient = -not $isWindowsServer
        }

        # ---------------------------------------------------------------------
        # Determine the Windows feature release.
        # ---------------------------------------------------------------------
        $osVersion = $null
        $detectionMethod = $null

        # DisplayVersion is the preferred source on current Windows versions.
        if ($null -ne $currentVersion -and -not [string]::IsNullOrWhiteSpace([string]$currentVersion.DisplayVersion)) {
            $displayVersion = [string]$currentVersion.DisplayVersion

            # Accept values such as 21H2, 22H2, 24H2, 25H2, and 26H1.
            if ($displayVersion.Trim() -match '^\d{2}H[12]$') {
                $osVersion = $displayVersion.Trim().ToUpperInvariant()
                $detectionMethod = 'Registry DisplayVersion'
            }
        }

        # ReleaseId is primarily useful for older Windows 10 releases.
        if ([string]::IsNullOrWhiteSpace($osVersion) -and $null -ne $currentVersion -and -not [string]::IsNullOrWhiteSpace([string]$currentVersion.ReleaseId)) {
            $releaseId = [string]$currentVersion.ReleaseId
            if ($releaseId.Trim() -match '^\d{4}$') {
                $osVersion = $releaseId.Trim()
                $detectionMethod = 'Registry ReleaseId'
            }
        }

        # If the registry values are unavailable, use known base build numbers.
        # Exact base builds are used instead of broad numeric ranges to avoid
        # incorrectly classifying Insider Preview builds.
        if ([string]::IsNullOrWhiteSpace($osVersion)) {
            $osVersion = switch ($buildNumber) {
                # Windows 11 client releases
                22000 { '21H2'; break }
                22621 { '22H2'; break }
                22631 { '23H2'; break }
                26100 { '24H2'; break }
                26200 { '25H2'; break }
                28000 { '26H1'; break }

                # Windows 10 client releases
                10240 { '1507'; break }
                10586 { '1511'; break }
                14393 { '1607'; break }
                15063 { '1703'; break }
                16299 { '1709'; break }
                17134 { '1803'; break }
                17763 { '1809'; break }
                18362 { '1903'; break }
                18363 { '1909'; break }
                19041 { '2004'; break }
                19042 { '20H2'; break }
                19043 { '21H1'; break }
                19044 { '21H2'; break }
                19045 { '22H2'; break }

                default { 'Unknown' }
            }

            if ($osVersion -ne 'Unknown') {
                $detectionMethod = 'Build number fallback'
            }
            else {
                $detectionMethod = 'No matching feature release found'
            }
        }

        # Retrieve additional informational values if they are available.
        $windowsVersion = $null
        $architecture = $null

        if ($null -ne $cimOs -and $cimOs.Version) {
            $windowsVersion = [string]$cimOs.Version
        }
        elseif ($null -ne $currentVersion -and $currentVersion.CurrentVersion) {
            $windowsVersion = [string]$currentVersion.CurrentVersion
        }

        if ($null -ne $cimOs -and $cimOs.OSArchitecture) {
            $architecture = [string]$cimOs.OSArchitecture
        }
        elseif ([System.Environment]::Is64BitOperatingSystem) {
            $architecture = '64-bit'
        }
        else {
            $architecture = '32-bit'
        }

        # Create the data portion separately to keep the OPSreturn structure
        # consistent and easy to consume from other module functions.
        $data = [pscustomobject]@{
            osname          = [string]$osName
            osvers          = [string]$osVersion
            build           = [int]$buildNumber
            revision        = if ($null -ne $revision) {
                [int]$revision
            }
            else {
                $null
            }
            fullbuild        = [string]$fullBuild
            version          = [string]$windowsVersion
            architecture     = [string]$architecture
            iswindowsclient  = [bool]$isWindowsClient
            iswindowsserver  = [bool]$isWindowsServer
            detectionmethod  = [string]$detectionMethod
        }

        return [pscustomobject]@{
            code    = [int]0
            message = [string]'Windows version information was retrieved successfully.'
            data    = $data
        }
    }
    catch {
        return [pscustomobject]@{
            code    = [int]1
            message = 'Failed to retrieve Windows version information: {0}' -f
                $_.Exception.Message
            
            data    = $null
        }
    }
}

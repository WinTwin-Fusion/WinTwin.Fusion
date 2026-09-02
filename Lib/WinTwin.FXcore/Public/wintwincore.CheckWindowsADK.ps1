function wintwincore.CheckWindowsADK {
    <#
    .SYNOPSIS
        Checks reliably whether the Windows ADK is installed on the local system.
    .DESCRIPTION
        Detection is done in three independent stages (any positive hit wins):
          1. Registry: HKLM\SOFTWARE\Microsoft\Windows Kits\Installed Roots -> KitsRoot10
             plus verification that the "Deployment Tools" folder really exists on disk.
          2. Uninstall registry keys (32/64 bit) searched for a "Windows Assessment and
             Deployment Kit" product entry.
          3. File system fallback: look for DISM.exe of the ADK Deployment Tools in the
             default installation locations.
        The function never throws and never writes objects to the pipeline other than
        one single boolean value.
    .OUTPUTS
        [bool] $true if the Windows ADK is installed, otherwise $false.
    .EXAMPLE
    if (-not (CheckWindowsADK)) {
        if (-not (InstallADK -SetupPath 'C:\Sources\ADK\adksetup.exe' -LogFile 'C:\Temp\adk.log')) {
            throw 'ADK installation failed.'
        }
    }
    if (-not (CheckADKPEaddon)) {
        if (-not (InstallPEaddon -SetupPath 'C:\Sources\ADK\adkwinpesetup.exe' -LogFile 'C:\Temp\adkpe.log')) {
            throw 'ADK WinPE add-on installation failed.'
        }
    }
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param()

    try {
        # --- Stage 1: Windows Kits installed roots -------------------------------
        $kitsRootKeys = @(
            'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows Kits\Installed Roots',
            'HKLM:\SOFTWARE\Microsoft\Windows Kits\Installed Roots'
        )

        foreach ($key in $kitsRootKeys) {
            if (-not (Test-Path -LiteralPath $key)) { continue }

            # KitsRoot10 points to the ADK/Windows Kits base directory
            $kitsRoot = (Get-ItemProperty -LiteralPath $key -Name 'KitsRoot10' -ErrorAction SilentlyContinue).KitsRoot10
            if ([string]::IsNullOrWhiteSpace($kitsRoot)) { continue }

            # A pure SDK installation also creates KitsRoot10, therefore we verify
            # that the ADK specific "Deployment Tools" payload is present.
            $deploymentTools = Join-Path -Path $kitsRoot -ChildPath 'Assessment and Deployment Kit\Deployment Tools'
            if (Test-Path -LiteralPath $deploymentTools) { return $true }
        }

        # --- Stage 2: Uninstall entries -----------------------------------------
        $uninstallRoots = @(
            'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall',
            'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall'
        )

        foreach ($root in $uninstallRoots) {
            if (-not (Test-Path -LiteralPath $root)) { continue }

            $hit = Get-ChildItem -LiteralPath $root -ErrorAction SilentlyContinue |
                   ForEach-Object { Get-ItemProperty -LiteralPath $_.PSPath -ErrorAction SilentlyContinue } |
                   Where-Object {
                        $_.DisplayName -and
                        $_.DisplayName -match 'Windows\s+(Assessment\s+and\s+Deployment\s+Kit|ADK)' -and
                        $_.DisplayName -notmatch 'Windows\s+PE|Preinstallation'
                   } |
                   Select-Object -First 1

            if ($null -ne $hit) { return $true }
        }

        # --- Stage 3: File system fallback --------------------------------------
        $candidatePaths = @(
            "${env:ProgramFiles(x86)}\Windows Kits\10\Assessment and Deployment Kit\Deployment Tools",
            "${env:ProgramFiles}\Windows Kits\10\Assessment and Deployment Kit\Deployment Tools"
        ) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }

        foreach ($path in $candidatePaths) {
            if (Test-Path -LiteralPath $path) { return $true }
        }

        # Nothing found -> not installed
        return $false
    }
    catch {
        # Any unexpected error is treated as "not detected" to keep the contract
        return $false
    }
}

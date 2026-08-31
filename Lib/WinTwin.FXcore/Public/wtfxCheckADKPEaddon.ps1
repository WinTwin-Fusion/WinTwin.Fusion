function wtfxCheckADKPEaddon {
    <#
    .SYNOPSIS
        Checks reliably whether the Windows ADK "Windows PE add-on" is installed.
    .DESCRIPTION
        Detection is done in three independent stages (any positive hit wins):
          1. Registry: KitsRoot10 + existence of the
             "Assessment and Deployment Kit\Windows Preinstallation Environment"
             folder including at least one WinPE base image (winpe.wim).
          2. Uninstall registry keys searched for the "Windows PE add-on for the ADK"
             product entry.
          3. File system fallback in the default installation locations.
        The function never throws and returns exactly one boolean value.
    .OUTPUTS
        [bool] $true if the ADK WinPE add-on is installed, otherwise $false.
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

            $kitsRoot = (Get-ItemProperty -LiteralPath $key -Name 'KitsRoot10' -ErrorAction SilentlyContinue).KitsRoot10
            if ([string]::IsNullOrWhiteSpace($kitsRoot)) { continue }

            $peRoot = Join-Path -Path $kitsRoot -ChildPath 'Assessment and Deployment Kit\Windows Preinstallation Environment'
            if (-not (Test-Path -LiteralPath $peRoot)) { continue }

            # Verify the actual payload: a WinPE boot image must be present
            $wim = Get-ChildItem -LiteralPath $peRoot -Filter 'winpe.wim' -Recurse -File -ErrorAction SilentlyContinue |
                   Select-Object -First 1
            if ($null -ne $wim) { return $true }
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
                        $_.DisplayName -match 'Windows\s+(PE|Preinstallation\s+Environment)' -and
                        $_.DisplayName -match 'add[\s\-]?on|ADK'
                   } |
                   Select-Object -First 1

            if ($null -ne $hit) { return $true }
        }

        # --- Stage 3: File system fallback --------------------------------------
        $candidatePaths = @(
            "${env:ProgramFiles(x86)}\Windows Kits\10\Assessment and Deployment Kit\Windows Preinstallation Environment",
            "${env:ProgramFiles}\Windows Kits\10\Assessment and Deployment Kit\Windows Preinstallation Environment"
        ) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }

        foreach ($path in $candidatePaths) {
            if (Test-Path -LiteralPath $path) {
                $wim = Get-ChildItem -LiteralPath $path -Filter 'winpe.wim' -Recurse -File -ErrorAction SilentlyContinue |
                       Select-Object -First 1
                if ($null -ne $wim) { return $true }
            }
        }

        return $false
    }
    catch {
        return $false
    }
}

<#
.SYNOPSIS
    Installs all TrueType fonts from a specified directory system-wide.

.DESCRIPTION
    The wintwincore.InstallRequiredFonts function validates that the path 
    supplied through the Path parameter exists and points to a directory.

    It then reads all files with the .ttf extension from that directory and
    installs them system-wide by copying them to the Windows Fonts directory,
    registering them in the Windows registry, and loading them into the current
    Windows session.

    The function requires an elevated PowerShell session because system-wide
    font installation requires administrative privileges.

    If all discovered fonts are installed successfully, the function returns
    $true. If the path is invalid, no TrueType fonts are found, administrative
    privileges are missing, or any font cannot be installed, the function
    returns $false.

    If an error occurs during installation, the function attempts to roll back
    changes made during the current function call.

.PARAMETER Path
    Specifies the full path to the directory containing the TrueType font files
    to install.

    The directory must exist and must contain at least one file with the .ttf
    extension. Files in subdirectories are not processed.

.EXAMPLE
    wintwincore.InstallRequiredFonts -Path 'C:\Deployment\Fonts'

    Installs all .ttf files located directly in C:\Deployment\Fonts.
    Returns $true if all fonts are installed successfully; otherwise, returns
    $false.

.EXAMPLE
    $result = wintwincore.InstallRequiredFonts -Path 'C:\Deployment\Fonts'
    if ($result) { Write-Host 'All fonts were installed successfully.' }
    else { Write-Host 'Font installation failed.' }

    Stores the Boolean return value and uses it to display an appropriate
    status message.

.NOTES
    The function must be executed in an elevated PowerShell session.

    Only TrueType font files with the .ttf extension are processed.
    Subdirectories are not searched.

    Existing font files are not overwritten when their contents differ from
    the font being installed.

    The function is intended for Windows systems because it uses the Windows
    Fonts directory, the Windows registry, and native Windows API functions.

    Restarting applications may be required before newly installed fonts appear
    in their font selection lists.
#>
function wintwincore.InstallRequiredFonts {
    [CmdletBinding()]
    [OutputType([bool])]
    param (
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Path
    )

    # Constants used by the Windows font and messaging APIs.
    $fontChangeMessage = 0x001D
    $broadcastHandle   = [IntPtr]0xFFFF
    $fontsRegistryPath = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Fonts'
    $windowsFontsPath  = Join-Path -Path $env:WINDIR -ChildPath 'Fonts'

    # Keep track of changes so that they can be rolled back if an error occurs.
    $installedFonts = @()

    try {
        # Verify that the supplied path exists and is a directory.
        if (-not (Test-Path -LiteralPath $Path -PathType Container)) {
            Write-Error "The specified path does not exist or is not a directory: '$Path'"
            return $false
        }

        # Resolve the path to its absolute filesystem path.
        $resolvedPath = (Resolve-Path -LiteralPath $Path -ErrorAction Stop).ProviderPath

        # System-wide font installation requires administrative privileges.
        $currentIdentity = [Security.Principal.WindowsIdentity]::GetCurrent()
        $currentPrincipal = [Security.Principal.WindowsPrincipal]::new($currentIdentity)

        $isAdministrator = $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

        if (-not $isAdministrator) {
            Write-Error 'System-wide font installation requires an elevated PowerShell session.'
            return $false
        }

        # Read all TrueType font files from the supplied directory.
        # Subdirectories are intentionally not included.
        $fontFiles = @(Get-ChildItem -LiteralPath $resolvedPath -Filter '*.ttf' -File -ErrorAction Stop)

        if ($fontFiles.Count -eq 0) {
            Write-Error "No TrueType font files were found in '$resolvedPath'."
            return $false
        }

        # Add the required Windows API declarations only once.
        if (-not ('NativeFontMethods' -as [type])) {
            Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;

public static class NativeFontMethods
{
    [DllImport("gdi32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    public static extern int AddFontResourceEx(
        string fileName,
        uint flags,
        IntPtr reserved
    );

    [DllImport("gdi32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    public static extern bool RemoveFontResourceEx(
        string fileName,
        uint flags,
        IntPtr reserved
    );

    [DllImport("user32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    public static extern IntPtr SendMessage(
        IntPtr windowHandle,
        uint message,
        IntPtr wParam,
        IntPtr lParam
    );
}
'@ -ErrorAction Stop
        }

        foreach ($fontFile in $fontFiles) {
            $destinationPath = Join-Path -Path $windowsFontsPath -ChildPath $fontFile.Name

            # Use a deterministic and unique registry value name.
            $registryValueName = '{0} (TrueType)' -f $fontFile.BaseName

            $destinationAlreadyExisted = Test-Path -LiteralPath $destinationPath -PathType Leaf

            $registryValueAlreadyExisted = $false
            $previousRegistryValue = $null

            # Check whether the corresponding registry value already exists.
            try {
                $previousRegistryValue = Get-ItemPropertyValue -LiteralPath $fontsRegistryPath -Name $registryValueName -ErrorAction Stop
                $registryValueAlreadyExisted = $true
            }
            catch [System.Management.Automation.ItemNotFoundException] {
                $registryValueAlreadyExisted = $false
            }
            catch [System.Management.Automation.PSArgumentException] {
                $registryValueAlreadyExisted = $false
            }

            if ($destinationAlreadyExisted) {
                # Do not overwrite an existing file if its contents differ.
                $sourceHash = Get-FileHash -LiteralPath $fontFile.FullName -Algorithm SHA256 -ErrorAction Stop
                $destinationHash = Get-FileHash -LiteralPath $destinationPath -Algorithm SHA256 -ErrorAction Stop
                if ($sourceHash.Hash -ne $destinationHash.Hash) {
                    throw "A different font file named '$($fontFile.Name)' already exists in '$windowsFontsPath'."
                }
            }
            else {
                # Copy the font into the system-wide Windows Fonts directory.
                Copy-Item -LiteralPath $fontFile.FullName -Destination $destinationPath -Force -ErrorAction Stop
            }

            # Add the font to the current Windows font table.
            $fontsAdded = [NativeFontMethods]::AddFontResourceEx($destinationPath, 0, ([System.IntPtr]::Zero))

            if ($fontsAdded -eq 0) {
                if (-not $destinationAlreadyExisted) {
                    Remove-Item -LiteralPath $destinationPath -Force -ErrorAction SilentlyContinue
                }
                throw "Windows could not load the font '$($fontFile.Name)'."
            }

            # Register the font so that it remains installed after a restart.
            New-ItemProperty -LiteralPath $fontsRegistryPath -Name $registryValueName -Value $fontFile.Name -PropertyType String -Force -ErrorAction Stop | Out-Null

            # Save rollback information after the installation succeeded.
            $installedFonts += [PSCustomObject]@{
                DestinationPath            = $destinationPath
                RegistryValueName          = $registryValueName
                DestinationAlreadyExisted  = $destinationAlreadyExisted
                RegistryValueAlreadyExisted = $registryValueAlreadyExisted
                PreviousRegistryValue      = $previousRegistryValue
            }
        }

        # Notify running applications that the available fonts have changed.
        [NativeFontMethods]::SendMessage($broadcastHandle, $fontChangeMessage, ([System.IntPtr]::Zero), ([System.IntPtr]::Zero))
        return $true
    }
    catch {
        Write-Error "Font installation failed: $($_.Exception.Message)"

        # Roll back fonts installed during this function call.
        foreach ($installedFont in ($installedFonts | Select-Object -Last $installedFonts.Count)) {
            [NativeFontMethods]::RemoveFontResourceEx($installedFont.DestinationPath, 0, ([System.IntPtr]::Zero))

            if (-not $installedFont.DestinationAlreadyExisted) {
                Remove-Item -LiteralPath $installedFont.DestinationPath -Force -ErrorAction SilentlyContinue
            }

            if ($installedFont.RegistryValueAlreadyExisted) {
                New-ItemProperty -LiteralPath $fontsRegistryPath -Name $installedFont.RegistryValueName -Value $installedFont.PreviousRegistryValue -PropertyType String -Force -ErrorAction SilentlyContinue | Out-Null
            }
            else {
                Remove-ItemProperty -LiteralPath $fontsRegistryPath -Name $installedFont.RegistryValueName -Force -ErrorAction SilentlyContinue
            }
        }

        return $false
    }
}
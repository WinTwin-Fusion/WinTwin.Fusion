#Requires -Version 5.1
<#
    .SYNOPSIS
        WinTwin.Fusion - Framework Installer (Console Edition / v0.2.0)

    .DESCRIPTION
        First console-only (non-GUI) version of the WinTwin.Fusion installer.
        The entire WinTwin.Fusion source code base - including this script -
        is written in English, as mandated for the whole framework.

        The script is intentionally self-contained and does NOT depend on any
        other framework module (WinTwin.FXcore, OPSreturn, PSAppCoreLib,
        VPDLX), so it remains runnable even before those modules exist under
        ".\Lib".

        Execution flow:
          1.  Verify the script is running elevated (Administrator). If not,
              print an error message and terminate immediately.
          2.  Determine the framework root (the directory this script lives in).
          3.  Create the complete target folder structure (idempotent).
          4.  Verify LICENSE.md / NOTICE exist in the root and match the
              expected SHA512 checksums (integrity check).
          5.  Verify the system is Windows 11 24H2 or 25H2.
          6.  Verify a functional DISM installation is present.
          7.  Verify the Windows ADK is installed (silently install it from
              ".\AddOns\adksetup.exe" if missing).
          8.  Verify the Windows ADK WinPE Add-on is installed (silently
              install it from ".\AddOns\adkwinpesetup.exe" if missing).
          9.  Install all Google Fonts found under ".\Core\fonts" for all
              users (machine-wide, HKEY_LOCAL_MACHINE).
          10. Create / update the central "Core\config.json".
          11. Print a console checklist summarizing every step.
          12. Wait for a keypress ("Press any key to exit.") before the
              console window actually closes.

    .NOTES
        Project      : WinTwin.Fusion
        File         : wintwin.installer.ps1
        Version      : 0.2.0 (console-only, English source)
        Last change  : 2026-08-20
        Author       : WinTwin-Fusion Team
        License      : See LICENSE.md / NOTICE in the main repository
                       https://github.com/WinTwin-Fusion/WinTwin.Fusion

        Administrator rights are REQUIRED for this script, because both the
        silent ADK/WinPE installation and the machine-wide font installation
        write to protected system locations (Program Files, Windows\Fonts,
        HKEY_LOCAL_MACHINE). The elevation check happens first, before any
        other action is taken.

    .PARAMETER SkipAdkInstall
        Skips the automatic Windows ADK installation, even if it was not
        found (status is still reported).

    .PARAMETER SkipWinPEInstall
        Skips the automatic WinPE Add-on installation, even if it was not
        found (status is still reported).

    .PARAMETER SkipFontInstall
        Skips the Google Fonts installation step entirely.

    .PARAMETER Quiet
        Reduces console output to the essentials (prepared for future
        unattended / autounattend scenarios).

    .PARAMETER NoPause
        Suppresses the final "Press any key to exit." prompt (e.g. for
        automated test runs). Do NOT use in regular interactive operation.

    .EXAMPLE
        .\wintwin.installer.ps1

    .EXAMPLE
        .\wintwin.installer.ps1 -SkipAdkInstall -SkipWinPEInstall
#>

[CmdletBinding()]
param(
    [switch]$SkipAdkInstall,
    [switch]$SkipWinPEInstall,
    [switch]$SkipFontInstall,
    [switch]$Quiet,
    [switch]$NoPause
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# --------------------------------------------------------------------------
#  GLOBAL CONSTANTS
# --------------------------------------------------------------------------

$Script:InstallerVersion       = '0.2.0'
$Script:MinBuildNumber2024H2   = 26100   # Windows 11 24H2 (RTM build)
$Script:ExitCodeSuccess        = 0
$Script:ExitCodeWarning        = 1
$Script:ExitCodeFailure        = 2
$Script:LogFilePath            = $null

# Reference SHA512 checksums for the framework's root-level LICENSE.md / NOTICE files.
# These values are used to verify that the license and notice files present in the
# framework root have not been altered and match the official WinTwin.Fusion originals.
$Script:ExpectedLicenseSha512 = '68B04738B535115BA0C4E8A1B2AB7F8F17890D214BC7D081B9F8A46A439E598A572B85CCC706E40880F89E87F958A5B32751F10901BDE63D8F323F2ABF53874B'
$Script:ExpectedNoticeSha512  = '0EBC8DB2C51A6A9446CAD73CCE8C84A341A4621D80EB5BB20A009EB2FB0263ACE88E26F71BC7AF6226CEEA687E97B0DB9C7B65C4797B264076F420ACE9F47F6E'

# Checklist collector: every step is recorded here together with its status
$Script:StepResults = [System.Collections.Generic.List[object]]::new()

# --------------------------------------------------------------------------
#  HELPER FUNCTIONS: CONSOLE OUTPUT / LOGGING
# --------------------------------------------------------------------------

function Write-InstallerBanner {
    if ($Quiet) { return }
    $line = ('=' * 78)
    Write-Host ''
    Write-Host $line -ForegroundColor Cyan
    Write-Host '   WinTwin.Fusion - Framework Installer (Console Edition)' -ForegroundColor Cyan
    Write-Host "   Version $Script:InstallerVersion" -ForegroundColor Cyan
    Write-Host $line -ForegroundColor Cyan
    Write-Host ''
}

function Write-InstallerLog {
    <#
        .SYNOPSIS
            Writes a status line to the console AND (if possible) to the
            central log file under Core\logs\installer.log
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Message,

        [ValidateSet('INFO', 'OK', 'WARN', 'FAIL', 'STEP')]
        [string]$Level = 'INFO',

        [switch]$NoNewline
    )

    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $prefix = switch ($Level) {
        'OK'   { '[  OK  ]' }
        'WARN' { '[ WARN ]' }
        'FAIL' { '[ FAIL ]' }
        'STEP' { '[ STEP ]' }
        default { '[ INFO ]' }
    }

    $color = switch ($Level) {
        'OK'   { 'Green' }
        'WARN' { 'Yellow' }
        'FAIL' { 'Red' }
        'STEP' { 'Cyan' }
        default { 'Gray' }
    }

    if (-not $Quiet -or $Level -in @('FAIL', 'WARN', 'STEP')) {
        if ($NoNewline) {
            Write-Host "$prefix $Message" -ForegroundColor $color -NoNewline
        }
        else {
            Write-Host "$prefix $Message" -ForegroundColor $color
        }
    }

    # Best-effort log file write - must never abort the installer
    try {
        if ($Script:LogFilePath) {
            $logLine = "$timestamp $prefix $Message"
            Add-Content -Path $Script:LogFilePath -Value $logLine -Encoding UTF8 -ErrorAction Stop
        }
    }
    catch {
        # Logging failures are intentionally swallowed
    }
}

function Add-StepResult {
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][ValidateSet('OK','WARN','FAIL','SKIP')][string]$Status,
        [string]$Detail = ''
    )
    $Script:StepResults.Add([PSCustomObject]@{
        Step   = $Name
        Status = $Status
        Detail = $Detail
    })
}

function Wait-ForKeyPress {
    <#
        .SYNOPSIS
            Displays "Press any key to exit." and waits for a keypress before
            the console is actually closed. Falls back to Read-Host if
            RawUI.ReadKey() is unavailable (e.g. PowerShell ISE or redirected
            streams).
    #>
    if ($NoPause) { return }

    Write-Host ''
    Write-Host 'Press any key to exit.' -ForegroundColor Gray

    try {
        [void]$Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown')
    }
    catch {
        [void](Read-Host)
    }
}

# --------------------------------------------------------------------------
#  STEP 0: ADMINISTRATOR ELEVATION CHECK (MUST RUN FIRST)
# --------------------------------------------------------------------------

function Test-IsAdministrator {
    [CmdletBinding()]
    param()

    $identity  = [System.Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object System.Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([System.Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Assert-AdministratorOrExit {
    <#
        .SYNOPSIS
            Verifies elevated execution. If the current session is not
            running as Administrator, an error message is printed and the
            script terminates immediately (before any other action occurs).
    #>
    [CmdletBinding()]
    param()

    if (Test-IsAdministrator) {
        return
    }

    Write-Host ''
    Write-Host ('=' * 78) -ForegroundColor Red
    Write-Host '  ERROR: Administrator privileges required' -ForegroundColor Red
    Write-Host ('=' * 78) -ForegroundColor Red
    Write-Host ''
    Write-Host '  wintwin.installer.ps1 must be run from an elevated PowerShell' -ForegroundColor Red
    Write-Host '  console (Run as Administrator). This is required because the' -ForegroundColor Red
    Write-Host '  installer writes to protected system locations (Program Files,' -ForegroundColor Red
    Write-Host '  Windows\Fonts, HKEY_LOCAL_MACHINE) and may silently install the' -ForegroundColor Red
    Write-Host '  Windows ADK / WinPE Add-on.' -ForegroundColor Red
    Write-Host ''
    Write-Host '  Please close this window and re-run the script as Administrator.' -ForegroundColor Yellow
    Write-Host ''

    Wait-ForKeyPress
    exit $Script:ExitCodeFailure
}

# --------------------------------------------------------------------------
#  STEP 1: DETERMINE THE FRAMEWORK ROOT
# --------------------------------------------------------------------------

function Get-FrameworkRoot {
    <#
        .SYNOPSIS
            Determines the directory this script itself is located in. This
            directory is treated as the WinTwin.Fusion framework root.
    #>
    [CmdletBinding()]
    param()

    if ($PSScriptRoot) {
        return $PSScriptRoot
    }

    # Fallback for edge cases (e.g. execution via -Command / copy & paste)
    if ($MyInvocation.MyCommand.Path) {
        return Split-Path -Path $MyInvocation.MyCommand.Path -Parent
    }

    return (Get-Location).Path
}

# --------------------------------------------------------------------------
#  STEP 2: TARGET FOLDER STRUCTURE
# --------------------------------------------------------------------------

function Initialize-FrameworkFolderStructure {
    <#
        .SYNOPSIS
            Creates the complete, documented WinTwin.Fusion folder structure
            below the framework root, for every folder that does not yet
            exist. Existing folders are left untouched.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$RootPath
    )

    # Mandatory folders per the concept documentation (installer MUST ensure these)
    $mandatoryFolders = @(
        'AddOns',
        'Core',
        'DISM.UI.CC',
        'Lib',
        'PS.Tweak.Tools',
        'USMT.Composer'
    )

    # Additional runtime / structural folders from the documented overall layout
    $additionalFolders = @(
        'Drivers',
        'Mount',
        'MSStore',
        'Output',
        'Profile.Backup',
        'RawISO',
        'UserData',
        'UUPD',
        (Join-Path 'Core' 'db'),
        (Join-Path 'Core' 'export'),
        (Join-Path 'Core' 'fonts'),
        (Join-Path 'Core' 'lang'),
        (Join-Path 'Core' 'logs'),
        (Join-Path 'Core' 'ui'),
        (Join-Path 'Lib' 'OPSreturn'),
        (Join-Path 'Lib' 'PSAppCoreLib'),
        (Join-Path 'Lib' 'VPDLX'),
        (Join-Path 'Lib' 'WinTwin.FXcore')
    )

    $allFolders = $mandatoryFolders + $additionalFolders
    $created  = [System.Collections.Generic.List[string]]::new()
    $existing = [System.Collections.Generic.List[string]]::new()
    $failed   = [System.Collections.Generic.List[string]]::new()

    foreach ($folder in $allFolders) {
        $fullPath = Join-Path -Path $RootPath -ChildPath $folder
        if (Test-Path -Path $fullPath) {
            $existing.Add($folder)
            continue
        }

        try {
            New-Item -Path $fullPath -ItemType Directory -Force -ErrorAction Stop | Out-Null
            $created.Add($folder)
        }
        catch {
            $failed.Add("$folder ($($_.Exception.Message))")
        }
    }

    return [PSCustomObject]@{
        Created  = $created
        Existing = $existing
        Failed   = $failed
    }
}

# --------------------------------------------------------------------------
#  STEP 3: LICENSE / NOTICE INTEGRITY CHECK (SHA512)
# --------------------------------------------------------------------------

function Test-FrameworkLicenseIntegrity {
    <#
        .SYNOPSIS
            Verifies that LICENSE.md and NOTICE exist in the framework root
            and that their SHA512 checksums match the official WinTwin.Fusion
            originals.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$RootPath
    )

    $filesToCheck = @(
        @{ Name = 'LICENSE.md'; ExpectedHash = $Script:ExpectedLicenseSha512 },
        @{ Name = 'NOTICE';     ExpectedHash = $Script:ExpectedNoticeSha512  }
    )

    $results = [System.Collections.Generic.List[object]]::new()

    foreach ($file in $filesToCheck) {
        $fullPath = Join-Path -Path $RootPath -ChildPath $file.Name

        if (-not (Test-Path -Path $fullPath -PathType Leaf)) {
            $results.Add([PSCustomObject]@{
                FileName = $file.Name
                Status   = 'MISSING'
                Detail   = "File not found at: $fullPath"
            })
            continue
        }

        try {
            $actualHash = (Get-FileHash -Path $fullPath -Algorithm SHA512 -ErrorAction Stop).Hash

            if ($actualHash -ieq $file.ExpectedHash) {
                $results.Add([PSCustomObject]@{
                    FileName = $file.Name
                    Status   = 'VALID'
                    Detail   = 'SHA512 checksum matches the official original.'
                })
            }
            else {
                $results.Add([PSCustomObject]@{
                    FileName = $file.Name
                    Status   = 'MISMATCH'
                    Detail   = "SHA512 checksum does not match. Expected: $($file.ExpectedHash) / Actual: $actualHash"
                })
            }
        }
        catch {
            $results.Add([PSCustomObject]@{
                FileName = $file.Name
                Status   = 'ERROR'
                Detail   = "Could not compute checksum: $($_.Exception.Message)"
            })
        }
    }

    return $results
}

# --------------------------------------------------------------------------
#  STEP 4: WINDOWS VERSION CHECK (11 24H2 / 25H2)
# --------------------------------------------------------------------------

function Get-WindowsVersionInfo {
    <#
        .SYNOPSIS
            Reads ProductName, DisplayVersion and CurrentBuildNumber from the
            registry and evaluates whether the system qualifies as
            Windows 11 24H2/25H2 (build >= 26100).
    #>
    [CmdletBinding()]
    param()

    $regPath = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion'

    $productName    = (Get-ItemProperty -Path $regPath -Name 'ProductName'    -ErrorAction SilentlyContinue).ProductName
    $displayVersion = (Get-ItemProperty -Path $regPath -Name 'DisplayVersion' -ErrorAction SilentlyContinue).DisplayVersion
    $buildNumberRaw = (Get-ItemProperty -Path $regPath -Name 'CurrentBuildNumber' -ErrorAction SilentlyContinue).CurrentBuildNumber

    $buildNumber = 0
    [void][int]::TryParse($buildNumberRaw, [ref]$buildNumber)

    $isWindows11    = ($productName -like '*Windows 11*')
    $isSupportedRel = ($buildNumber -ge $Script:MinBuildNumber2024H2)

    return [PSCustomObject]@{
        ProductName    = $productName
        DisplayVersion = $displayVersion
        BuildNumber    = $buildNumber
        IsWindows11    = $isWindows11
        IsSupported    = ($isWindows11 -and $isSupportedRel)
    }
}

# --------------------------------------------------------------------------
#  STEP 5: DISM FUNCTIONALITY CHECK
# --------------------------------------------------------------------------

function Test-DismAvailable {
    <#
        .SYNOPSIS
            Verifies that dism.exe is present and basically functional.
    #>
    [CmdletBinding()]
    param()

    $dismCommand = Get-Command -Name 'dism.exe' -ErrorAction SilentlyContinue
    if (-not $dismCommand) {
        return [PSCustomObject]@{ Available = $false; Path = $null; Detail = 'dism.exe was not found in PATH.' }
    }

    try {
        $null = & $dismCommand.Source '/English' '/Online' '/Get-CurrentEdition' 2>&1
        $exitCode = $LASTEXITCODE
        $isFunctional = ($exitCode -eq 0)
        return [PSCustomObject]@{
            Available = $isFunctional
            Path      = $dismCommand.Source
            Detail    = if ($isFunctional) { 'DISM responded successfully.' } else { "DISM exit code: $exitCode" }
        }
    }
    catch {
        return [PSCustomObject]@{ Available = $false; Path = $dismCommand.Source; Detail = $_.Exception.Message }
    }
}

# --------------------------------------------------------------------------
#  STEP 6/7: DETECT WINDOWS ADK / WINPE ADD-ON
# --------------------------------------------------------------------------

function Get-AdkInstallInfo {
    <#
        .SYNOPSIS
            Verifies whether the Windows ADK (Deployment Tools) is installed.
    #>
    [CmdletBinding()]
    param()

    $kitsRootKey = 'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows Kits\Installed Roots'
    $kitsRoot10  = (Get-ItemProperty -Path $kitsRootKey -Name 'KitsRoot10' -ErrorAction SilentlyContinue).KitsRoot10

    $adkPath = $null
    $installed = $false

    if ($kitsRoot10) {
        $deploymentToolsPath = Join-Path -Path $kitsRoot10 -ChildPath 'Assessment and Deployment Kit\Deployment Tools'
        if (Test-Path -Path $deploymentToolsPath) {
            $adkPath   = $deploymentToolsPath
            $installed = $true
        }
    }

    return [PSCustomObject]@{
        Installed = $installed
        Path      = $adkPath
        KitsRoot  = $kitsRoot10
    }
}

function Get-WinPEAddonInstallInfo {
    <#
        .SYNOPSIS
            Verifies whether the Windows ADK WinPE Add-on is installed.
    #>
    [CmdletBinding()]
    param(
        [string]$KitsRoot10
    )

    $installed = $false
    $winpePath = $null

    if ($KitsRoot10) {
        $candidate = Join-Path -Path $KitsRoot10 -ChildPath 'Assessment and Deployment Kit\Windows Preinstallation Environment'
        if (Test-Path -Path $candidate) {
            $winpePath = $candidate
            $installed = $true
        }
    }

    return [PSCustomObject]@{
        Installed = $installed
        Path      = $winpePath
    }
}

function Install-AdkComponentSilent {
    <#
        .SYNOPSIS
            Runs an ADK / WinPE Add-on installer (adksetup.exe or
            adkwinpesetup.exe) in silent mode.

        .PARAMETER InstallerPath
            Full path to the installer (from .\AddOns).

        .PARAMETER Features
            List of ADK feature IDs to install (e.g. OptionId.DeploymentTools,
            OptionId.UserStateMigrationTool,
            OptionId.WindowsPreinstallationEnvironment).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$InstallerPath,
        [Parameter(Mandatory)][string[]]$Features,
        [Parameter(Mandatory)][string]$FriendlyName
    )

    if (-not (Test-Path -Path $InstallerPath)) {
        return [PSCustomObject]@{
            Success = $false
            Detail  = "Installer not found at: $InstallerPath"
        }
    }

    $argumentList = @('/quiet', '/features') + $Features + @('/ceip', 'off', '/norestart')

    try {
        Write-InstallerLog -Level 'INFO' -Message "Starting silent installation: $FriendlyName ..."
        $process = Start-Process -FilePath $InstallerPath -ArgumentList $argumentList -Wait -PassThru -ErrorAction Stop

        if ($process.ExitCode -eq 0) {
            return [PSCustomObject]@{ Success = $true; Detail = "$FriendlyName installed successfully." }
        }
        else {
            return [PSCustomObject]@{ Success = $false; Detail = "$FriendlyName installer exited with code $($process.ExitCode)." }
        }
    }
    catch {
        return [PSCustomObject]@{ Success = $false; Detail = "Error while starting the installer: $($_.Exception.Message)" }
    }
}

# --------------------------------------------------------------------------
#  STEP 8: GOOGLE FONTS INSTALLATION (ALL USERS / MACHINE-WIDE)
# --------------------------------------------------------------------------

function Register-NativeFontFunctions {
    <#
        .SYNOPSIS
            Registers the Win32 API functions required to activate newly
            installed fonts for the current session without a reboot.
    #>
    [CmdletBinding()]
    param()

    if (-not ('WinTwin.NativeFonts' -as [type])) {
        Add-Type -Namespace WinTwin -Name NativeFonts -MemberDefinition @'
            [DllImport("gdi32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
            public static extern int AddFontResourceW(string lpFileName);

            [DllImport("user32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
            public static extern IntPtr SendMessageTimeoutW(IntPtr hWnd, uint Msg, UIntPtr wParam, IntPtr lParam, uint fuFlags, uint uTimeout, out UIntPtr lpdwResult);
'@
    }
}

function Get-FontRegistryDisplayName {
    <#
        .SYNOPSIS
            Reads the font family name from a font file and appends the
            Windows-style suffix ("(TrueType)" / "(OpenType)") used as the
            registry value name in the Fonts registry key.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][System.IO.FileInfo]$FontFile
    )

    Add-Type -AssemblyName 'System.Drawing' -ErrorAction SilentlyContinue

    $familyName = $FontFile.BaseName
    $privateFonts = New-Object System.Drawing.Text.PrivateFontCollection

    try {
        $privateFonts.AddFontFile($FontFile.FullName)
        if ($privateFonts.Families.Count -gt 0) {
            $familyName = $privateFonts.Families[0].Name
        }
    }
    catch {
        # Fall back to the file's base name if the family name cannot be read
    }
    finally {
        $privateFonts.Dispose()
    }

    $suffix = switch ($FontFile.Extension.ToLowerInvariant()) {
        '.otf' { '(OpenType)' }
        default { '(TrueType)' }
    }

    return "$familyName $suffix"
}

function Install-FrameworkFonts {
    <#
        .SYNOPSIS
            Installs every font file found under the given source directory
            (typically ".\Core\fonts") machine-wide, i.e. for ALL users, by
            copying the files into the Windows Fonts directory and
            registering them under HKEY_LOCAL_MACHINE.

        .PARAMETER FontsSourcePath
            Directory that contains the font files to install
            (.ttf, .ttc, .otf).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$FontsSourcePath
    )

    $installed = [System.Collections.Generic.List[string]]::new()
    $skipped   = [System.Collections.Generic.List[string]]::new()
    $failed    = [System.Collections.Generic.List[string]]::new()

    if (-not (Test-Path -Path $FontsSourcePath -PathType Container)) {
        return [PSCustomObject]@{
            Installed = $installed
            Skipped   = $skipped
            Failed    = $failed
            Detail    = "Fonts source directory not found: $FontsSourcePath"
        }
    }

    $fontFiles = Get-ChildItem -Path $FontsSourcePath -File -Recurse -ErrorAction SilentlyContinue |
        Where-Object { $_.Extension -match '^\.(ttf|ttc|otf)$' }

    if (-not $fontFiles -or $fontFiles.Count -eq 0) {
        return [PSCustomObject]@{
            Installed = $installed
            Skipped   = $skipped
            Failed    = $failed
            Detail    = "No font files (*.ttf, *.ttc, *.otf) found under: $FontsSourcePath"
        }
    }

    Register-NativeFontFunctions

    $windowsFontsDir = Join-Path -Path $env:WINDIR -ChildPath 'Fonts'
    $fontsRegistryKey = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Fonts'

    foreach ($fontFile in $fontFiles) {
        try {
            $targetPath = Join-Path -Path $windowsFontsDir -ChildPath $fontFile.Name

            if (Test-Path -Path $targetPath) {
                $skipped.Add($fontFile.Name)
                continue
            }

            Copy-Item -Path $fontFile.FullName -Destination $targetPath -Force -ErrorAction Stop

            $registryValueName = Get-FontRegistryDisplayName -FontFile $fontFile
            New-ItemProperty -Path $fontsRegistryKey -Name $registryValueName -Value $fontFile.Name -PropertyType String -Force | Out-Null

            [void][WinTwin.NativeFonts]::AddFontResourceW($targetPath)

            $installed.Add($fontFile.Name)
        }
        catch {
            $failed.Add("$($fontFile.Name) ($($_.Exception.Message))")
        }
    }

    if ($installed.Count -gt 0) {
        # Broadcast WM_FONTCHANGE (0x001D) to all top-level windows so newly
        # installed fonts become available without a reboot / re-login.
        try {
            $HWND_BROADCAST  = [IntPtr]0xffff
            $WM_FONTCHANGE   = 0x001D
            $result = [UIntPtr]::Zero
            [void][WinTwin.NativeFonts]::SendMessageTimeoutW($HWND_BROADCAST, $WM_FONTCHANGE, [UIntPtr]::Zero, [IntPtr]::Zero, 2, 1000, [ref]$result)
        }
        catch {
            # Non-critical: fonts are registered regardless of the broadcast result
        }
    }

    return [PSCustomObject]@{
        Installed = $installed
        Skipped   = $skipped
        Failed    = $failed
        Detail    = "Installed: $($installed.Count) / Already present: $($skipped.Count) / Failed: $($failed.Count)"
    }
}

# --------------------------------------------------------------------------
#  STEP 9: CREATE / UPDATE config.json
# --------------------------------------------------------------------------

function Update-FrameworkConfigJson {
    <#
        .SYNOPSIS
            Creates the central Core\config.json (if not present) or updates
            the path- and system-information in an already existing
            config.json, without discarding unknown/custom keys.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$RootPath,
        [Parameter(Mandatory)][object]$WindowsInfo,
        [Parameter(Mandatory)][object]$DismInfo,
        [Parameter(Mandatory)][object]$AdkInfo,
        [Parameter(Mandatory)][object]$WinPEInfo,
        [Parameter(Mandatory)][object]$FontInfo
    )

    $coreDir    = Join-Path -Path $RootPath -ChildPath 'Core'
    $configPath = Join-Path -Path $coreDir -ChildPath 'config.json'

    if (-not (Test-Path -Path $coreDir)) {
        New-Item -Path $coreDir -ItemType Directory -Force | Out-Null
    }

    # Read an existing config.json (if present) to preserve custom / already
    # set keys. On parse errors, a fresh configuration is created (the broken
    # file is backed up beforehand).
    $config = $null
    if (Test-Path -Path $configPath) {
        try {
            $rawJson = Get-Content -Path $configPath -Raw -Encoding UTF8
            $config  = $rawJson | ConvertFrom-Json -ErrorAction Stop
        }
        catch {
            $backupPath = "$configPath.bak"
            Copy-Item -Path $configPath -Destination $backupPath -Force -ErrorAction SilentlyContinue
            Write-InstallerLog -Level 'WARN' -Message "Existing config.json was invalid and has been backed up to '$backupPath'."
            $config = $null
        }
    }

    if (-not $config) {
        $config = [PSCustomObject]@{
            FrameworkName = 'WinTwin.Fusion'
            Version       = '0.1.0'
            Paths         = [PSCustomObject]@{}
            System        = [PSCustomObject]@{}
            Installer     = [PSCustomObject]@{}
        }
    }

    function Set-JsonProperty {
        param($Object, [string]$Name, $Value)
        if ($Object.PSObject.Properties.Match($Name)) {
            $Object.$Name = $Value
        }
        else {
            $Object | Add-Member -MemberType NoteProperty -Name $Name -Value $Value -Force
        }
    }

    foreach ($section in @('Paths', 'System', 'Installer')) {
        if (-not $config.PSObject.Properties.Match($section)) {
            $config | Add-Member -MemberType NoteProperty -Name $section -Value ([PSCustomObject]@{}) -Force
        }
    }

    # --- Paths ---
    Set-JsonProperty -Object $config.Paths -Name 'Root'          -Value $RootPath
    Set-JsonProperty -Object $config.Paths -Name 'AddOns'        -Value (Join-Path $RootPath 'AddOns')
    Set-JsonProperty -Object $config.Paths -Name 'Core'          -Value (Join-Path $RootPath 'Core')
    Set-JsonProperty -Object $config.Paths -Name 'DismUiCc'      -Value (Join-Path $RootPath 'DISM.UI.CC')
    Set-JsonProperty -Object $config.Paths -Name 'Lib'           -Value (Join-Path $RootPath 'Lib')
    Set-JsonProperty -Object $config.Paths -Name 'PsTweakTools'  -Value (Join-Path $RootPath 'PS.Tweak.Tools')
    Set-JsonProperty -Object $config.Paths -Name 'UsmtComposer'  -Value (Join-Path $RootPath 'USMT.Composer')
    Set-JsonProperty -Object $config.Paths -Name 'Drivers'       -Value (Join-Path $RootPath 'Drivers')
    Set-JsonProperty -Object $config.Paths -Name 'Mount'         -Value (Join-Path $RootPath 'Mount')
    Set-JsonProperty -Object $config.Paths -Name 'MSStore'       -Value (Join-Path $RootPath 'MSStore')
    Set-JsonProperty -Object $config.Paths -Name 'Output'        -Value (Join-Path $RootPath 'Output')
    Set-JsonProperty -Object $config.Paths -Name 'ProfileBackup' -Value (Join-Path $RootPath 'Profile.Backup')
    Set-JsonProperty -Object $config.Paths -Name 'RawISO'        -Value (Join-Path $RootPath 'RawISO')
    Set-JsonProperty -Object $config.Paths -Name 'UserData'      -Value (Join-Path $RootPath 'UserData')
    Set-JsonProperty -Object $config.Paths -Name 'UUPD'          -Value (Join-Path $RootPath 'UUPD')
    Set-JsonProperty -Object $config.Paths -Name 'CoreDb'        -Value (Join-Path $RootPath 'Core\db')
    Set-JsonProperty -Object $config.Paths -Name 'CoreExport'    -Value (Join-Path $RootPath 'Core\export')
    Set-JsonProperty -Object $config.Paths -Name 'CoreFonts'     -Value (Join-Path $RootPath 'Core\fonts')
    Set-JsonProperty -Object $config.Paths -Name 'CoreLang'      -Value (Join-Path $RootPath 'Core\lang')
    Set-JsonProperty -Object $config.Paths -Name 'CoreLogs'      -Value (Join-Path $RootPath 'Core\logs')
    Set-JsonProperty -Object $config.Paths -Name 'CoreUi'        -Value (Join-Path $RootPath 'Core\ui')
    Set-JsonProperty -Object $config.Paths -Name 'PidStore'      -Value (Join-Path $RootPath 'Core\pid.store')

    # --- System information ---
    Set-JsonProperty -Object $config.System -Name 'WindowsProductName'    -Value $WindowsInfo.ProductName
    Set-JsonProperty -Object $config.System -Name 'WindowsDisplayVersion' -Value $WindowsInfo.DisplayVersion
    Set-JsonProperty -Object $config.System -Name 'WindowsBuildNumber'    -Value $WindowsInfo.BuildNumber
    Set-JsonProperty -Object $config.System -Name 'WindowsSupported'      -Value $WindowsInfo.IsSupported
    Set-JsonProperty -Object $config.System -Name 'DismAvailable'         -Value $DismInfo.Available
    Set-JsonProperty -Object $config.System -Name 'AdkInstalled'          -Value $AdkInfo.Installed
    Set-JsonProperty -Object $config.System -Name 'AdkPath'               -Value $AdkInfo.Path
    Set-JsonProperty -Object $config.System -Name 'WinPEAddonInstalled'   -Value $WinPEInfo.Installed
    Set-JsonProperty -Object $config.System -Name 'WinPEAddonPath'        -Value $WinPEInfo.Path
    Set-JsonProperty -Object $config.System -Name 'FontsInstalledCount'   -Value $FontInfo.Installed.Count

    # --- Installer metadata ---
    Set-JsonProperty -Object $config.Installer -Name 'LastRunUtc'        -Value ([DateTime]::UtcNow.ToString('o'))
    Set-JsonProperty -Object $config.Installer -Name 'InstallerVersion'  -Value $Script:InstallerVersion

    try {
        $json = $config | ConvertTo-Json -Depth 10
        Set-Content -Path $configPath -Value $json -Encoding UTF8 -Force
        return [PSCustomObject]@{ Success = $true; Path = $configPath }
    }
    catch {
        return [PSCustomObject]@{ Success = $false; Path = $configPath; Detail = $_.Exception.Message }
    }
}

# --------------------------------------------------------------------------
#  SUMMARY (CONSOLE CHECKLIST)
# --------------------------------------------------------------------------

function Show-InstallerSummary {
    [CmdletBinding()]
    param()

    Write-Host ''
    Write-Host ('-' * 78) -ForegroundColor DarkGray
    Write-Host ' Installation Checklist' -ForegroundColor White
    Write-Host ('-' * 78) -ForegroundColor DarkGray

    foreach ($result in $Script:StepResults) {
        $marker = switch ($result.Status) {
            'OK'   { '[x]' }
            'WARN' { '[!]' }
            'FAIL' { '[ ]' }
            'SKIP' { '[-]' }
        }

        $color = switch ($result.Status) {
            'OK'   { 'Green' }
            'WARN' { 'Yellow' }
            'FAIL' { 'Red' }
            'SKIP' { 'DarkGray' }
        }

        $line = " $marker $($result.Step)"
        if ($result.Detail) { $line += "  -  $($result.Detail)" }
        Write-Host $line -ForegroundColor $color
    }

    Write-Host ('-' * 78) -ForegroundColor DarkGray

    $failCount = ($Script:StepResults | Where-Object { $_.Status -eq 'FAIL' }).Count
    $warnCount = ($Script:StepResults | Where-Object { $_.Status -eq 'WARN' }).Count

    if ($failCount -gt 0) {
        Write-Host " Result: FAILED ($failCount critical error(s), $warnCount warning(s))" -ForegroundColor Red
        return $Script:ExitCodeFailure
    }
    elseif ($warnCount -gt 0) {
        Write-Host " Result: COMPLETED WITH WARNINGS ($warnCount warning(s))" -ForegroundColor Yellow
        return $Script:ExitCodeWarning
    }
    else {
        Write-Host ' Result: SUCCESS' -ForegroundColor Green
        return $Script:ExitCodeSuccess
    }
}

# ==========================================================================
#  MAIN
# ==========================================================================

try {
    Write-InstallerBanner

    # --- Step 0: Elevation check (must be the very first action) ---
    Assert-AdministratorOrExit
    Write-InstallerLog -Level 'OK' -Message 'Running with Administrator privileges.'
    Add-StepResult -Name 'Administrator privilege check' -Status 'OK' -Detail 'Elevated session confirmed.'

    # --- Determine root ---
    $frameworkRoot = Get-FrameworkRoot
    Write-InstallerLog -Level 'STEP' -Message "Detected framework root: $frameworkRoot"
    Add-StepResult -Name 'Determine framework root' -Status 'OK' -Detail $frameworkRoot

    # --- Ensure folder structure (early, so Core\logs becomes available) ---
    Write-InstallerLog -Level 'STEP' -Message 'Checking and creating folder structure ...'
    $folderResult = Initialize-FrameworkFolderStructure -RootPath $frameworkRoot

    $Script:LogFilePath = Join-Path -Path $frameworkRoot -ChildPath 'Core\logs\installer.log'

    if ($folderResult.Failed.Count -eq 0) {
        $detail = "Created: $($folderResult.Created.Count) / Already present: $($folderResult.Existing.Count)"
        Write-InstallerLog -Level 'OK' -Message "Folder structure complete. $detail"
        Add-StepResult -Name 'Ensure folder structure' -Status 'OK' -Detail $detail
    }
    else {
        $detail = "Failed: $($folderResult.Failed -join '; ')"
        Write-InstallerLog -Level 'FAIL' -Message $detail
        Add-StepResult -Name 'Ensure folder structure' -Status 'FAIL' -Detail $detail
    }

    # --- License / Notice integrity check ---
    Write-InstallerLog -Level 'STEP' -Message 'Verifying LICENSE.md / NOTICE integrity (SHA512) ...'
    $licenseResults = Test-FrameworkLicenseIntegrity -RootPath $frameworkRoot

    foreach ($licenseCheck in $licenseResults) {
        switch ($licenseCheck.Status) {
            'VALID' {
                Write-InstallerLog -Level 'OK' -Message "$($licenseCheck.FileName): $($licenseCheck.Detail)"
                Add-StepResult -Name "Integrity check: $($licenseCheck.FileName)" -Status 'OK' -Detail $licenseCheck.Detail
            }
            'MISSING' {
                Write-InstallerLog -Level 'FAIL' -Message "$($licenseCheck.FileName): $($licenseCheck.Detail)"
                Add-StepResult -Name "Integrity check: $($licenseCheck.FileName)" -Status 'FAIL' -Detail $licenseCheck.Detail
            }
            'MISMATCH' {
                Write-InstallerLog -Level 'FAIL' -Message "$($licenseCheck.FileName): $($licenseCheck.Detail)"
                Add-StepResult -Name "Integrity check: $($licenseCheck.FileName)" -Status 'FAIL' -Detail $licenseCheck.Detail
            }
            default {
                Write-InstallerLog -Level 'WARN' -Message "$($licenseCheck.FileName): $($licenseCheck.Detail)"
                Add-StepResult -Name "Integrity check: $($licenseCheck.FileName)" -Status 'WARN' -Detail $licenseCheck.Detail
            }
        }
    }

    # --- Windows version check ---
    Write-InstallerLog -Level 'STEP' -Message 'Checking Windows version (11 24H2 / 25H2) ...'
    $winInfo = Get-WindowsVersionInfo

    if ($winInfo.IsSupported) {
        $detail = "$($winInfo.ProductName) - $($winInfo.DisplayVersion) (Build $($winInfo.BuildNumber))"
        Write-InstallerLog -Level 'OK' -Message "Supported system detected: $detail"
        Add-StepResult -Name 'Check Windows 11 24H2/25H2' -Status 'OK' -Detail $detail
    }
    else {
        $detail = "$($winInfo.ProductName) - $($winInfo.DisplayVersion) (Build $($winInfo.BuildNumber)) - expected: Build >= $Script:MinBuildNumber2024H2"
        Write-InstallerLog -Level 'WARN' -Message "Unsupported system: $detail"
        Add-StepResult -Name 'Check Windows 11 24H2/25H2' -Status 'WARN' -Detail $detail
    }

    # --- DISM check ---
    Write-InstallerLog -Level 'STEP' -Message 'Checking DISM functionality ...'
    $dismInfo = Test-DismAvailable

    if ($dismInfo.Available) {
        Write-InstallerLog -Level 'OK' -Message $dismInfo.Detail
        Add-StepResult -Name 'Check DISM installation' -Status 'OK' -Detail $dismInfo.Path
    }
    else {
        Write-InstallerLog -Level 'FAIL' -Message $dismInfo.Detail
        Add-StepResult -Name 'Check DISM installation' -Status 'FAIL' -Detail $dismInfo.Detail
    }

    # --- ADK check (and install if needed) ---
    Write-InstallerLog -Level 'STEP' -Message 'Checking Windows ADK installation ...'
    $adkInfo = Get-AdkInstallInfo

    if ($adkInfo.Installed) {
        Write-InstallerLog -Level 'OK' -Message "Windows ADK found at: $($adkInfo.Path)"
        Add-StepResult -Name 'Check Windows ADK' -Status 'OK' -Detail $adkInfo.Path
    }
    elseif ($SkipAdkInstall) {
        Write-InstallerLog -Level 'WARN' -Message 'Windows ADK not found - installation skipped via parameter.'
        Add-StepResult -Name 'Check Windows ADK' -Status 'WARN' -Detail 'Not installed (installation skipped)'
    }
    else {
        Write-InstallerLog -Level 'WARN' -Message 'Windows ADK not found - attempting silent installation via .\AddOns\adksetup.exe ...'

        $adkSetupPath = Join-Path -Path $frameworkRoot -ChildPath 'AddOns\adksetup.exe'
        $installResult = Install-AdkComponentSilent -InstallerPath $adkSetupPath `
            -Features @('OptionId.DeploymentTools', 'OptionId.UserStateMigrationTool') `
            -FriendlyName 'Windows ADK (Deployment Tools + USMT)'

        if ($installResult.Success) {
            Write-InstallerLog -Level 'OK' -Message $installResult.Detail
            $adkInfo = Get-AdkInstallInfo
            Add-StepResult -Name 'Check / install Windows ADK' -Status 'OK' -Detail $installResult.Detail
        }
        else {
            Write-InstallerLog -Level 'FAIL' -Message $installResult.Detail
            Add-StepResult -Name 'Check / install Windows ADK' -Status 'FAIL' -Detail $installResult.Detail
        }
    }

    # --- WinPE Add-on check (and install if needed) ---
    Write-InstallerLog -Level 'STEP' -Message 'Checking Windows ADK WinPE Add-on installation ...'
    $winpeInfo = Get-WinPEAddonInstallInfo -KitsRoot10 $adkInfo.KitsRoot

    if ($winpeInfo.Installed) {
        Write-InstallerLog -Level 'OK' -Message "WinPE Add-on found at: $($winpeInfo.Path)"
        Add-StepResult -Name 'Check WinPE Add-on' -Status 'OK' -Detail $winpeInfo.Path
    }
    elseif ($SkipWinPEInstall) {
        Write-InstallerLog -Level 'WARN' -Message 'WinPE Add-on not found - installation skipped via parameter.'
        Add-StepResult -Name 'Check WinPE Add-on' -Status 'WARN' -Detail 'Not installed (installation skipped)'
    }
    else {
        Write-InstallerLog -Level 'WARN' -Message 'WinPE Add-on not found - attempting silent installation via .\AddOns\adkwinpesetup.exe ...'

        $winpeSetupPath = Join-Path -Path $frameworkRoot -ChildPath 'AddOns\adkwinpesetup.exe'
        $installResult = Install-AdkComponentSilent -InstallerPath $winpeSetupPath `
            -Features @('OptionId.WindowsPreinstallationEnvironment') `
            -FriendlyName 'Windows ADK WinPE Add-on'

        if ($installResult.Success) {
            Write-InstallerLog -Level 'OK' -Message $installResult.Detail
            $winpeInfo = Get-WinPEAddonInstallInfo -KitsRoot10 $adkInfo.KitsRoot
            Add-StepResult -Name 'Check / install WinPE Add-on' -Status 'OK' -Detail $installResult.Detail
        }
        else {
            Write-InstallerLog -Level 'FAIL' -Message $installResult.Detail
            Add-StepResult -Name 'Check / install WinPE Add-on' -Status 'FAIL' -Detail $installResult.Detail
        }
    }

    # --- Google Fonts installation (all users) ---
    if ($SkipFontInstall) {
        Write-InstallerLog -Level 'WARN' -Message 'Font installation skipped via parameter.'
        Add-StepResult -Name 'Install Google Fonts (all users)' -Status 'SKIP' -Detail 'Skipped via -SkipFontInstall'
        $fontInfo = [PSCustomObject]@{ Installed = @(); Skipped = @(); Failed = @() }
    }
    else {
        Write-InstallerLog -Level 'STEP' -Message 'Installing Google Fonts for all users ...'
        $coreFontsPath = Join-Path -Path $frameworkRoot -ChildPath 'Core\fonts'
        $fontInfo = Install-FrameworkFonts -FontsSourcePath $coreFontsPath

        if ($fontInfo.Failed.Count -eq 0) {
            Write-InstallerLog -Level 'OK' -Message $fontInfo.Detail
            Add-StepResult -Name 'Install Google Fonts (all users)' -Status 'OK' -Detail $fontInfo.Detail
        }
        else {
            Write-InstallerLog -Level 'WARN' -Message $fontInfo.Detail
            Add-StepResult -Name 'Install Google Fonts (all users)' -Status 'WARN' -Detail $fontInfo.Detail
        }
    }

    # --- Create / update config.json ---
    Write-InstallerLog -Level 'STEP' -Message 'Updating Core\config.json ...'
    $configResult = Update-FrameworkConfigJson -RootPath $frameworkRoot -WindowsInfo $winInfo `
        -DismInfo $dismInfo -AdkInfo $adkInfo -WinPEInfo $winpeInfo -FontInfo $fontInfo

    if ($configResult.Success) {
        Write-InstallerLog -Level 'OK' -Message "config.json updated: $($configResult.Path)"
        Add-StepResult -Name 'Update Core\config.json' -Status 'OK' -Detail $configResult.Path
    }
    else {
        Write-InstallerLog -Level 'FAIL' -Message "config.json could not be written: $($configResult.Detail)"
        Add-StepResult -Name 'Update Core\config.json' -Status 'FAIL' -Detail $configResult.Detail
    }

    # --- Show summary ---
    $exitCode = Show-InstallerSummary
}
catch {
    Write-Host ''
    Write-Host "Unexpected installer error: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host $_.ScriptStackTrace -ForegroundColor DarkRed
    $exitCode = $Script:ExitCodeFailure
}
finally {
    Wait-ForKeyPress
}

exit $exitCode

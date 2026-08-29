#Requires -Version 5.1
<#
    .SYNOPSIS
        WinTwin.Fusion - Framework Installer (Console Edition / v0.3.0)

    .DESCRIPTION
        Console-only (non-GUI) installer / repair tool for the WinTwin.Fusion framework.
        The entire WinTwin.Fusion source code base - including this script - is written
        in English, as mandated for the whole framework.

        The script is intentionally self-contained and does NOT depend on any other
        framework module (WinTwin.FXcore, OPSreturn, PSAppCoreLib, VPDLX, WinTwin.XUI),
        so it remains runnable even before those modules exist under ".\Lib".

        TWO SUPPORTED DEPLOYMENT PATHS:
          A) "Offline ZIP" - the user downloads the official release ZIP from the
             WinTwin.Fusion GitHub repository, extracts it into any target directory,
             and runs this installer from inside that directory. No network access is
             required for a normal (non -CleanInstall) run.
          B) "Git Clone" - the user clones the repository directly
             (git clone https://github.com/WinTwin-Fusion/WinTwin.Fusion.git) and runs
             the installer from the resulting working copy.

        In both cases, the WinTwin.Fusion GitHub repository
        (https://github.com/WinTwin-Fusion/WinTwin.Fusion) is the single, authoritative
        "source of truth" for the framework's directory layout and for the canonical
        content/schema of Core\config.json and Core\db\jobaction.json. This installer
        never invents or guesses a schema; it only ever restores files from - or
        validates the local layout against - that canonical repository.

        Execution flow:
          1.  Verify the script is running elevated (Administrator). If not, print an
              error message and terminate immediately.
          2.  Determine the framework root (the directory this script lives in).
          3.  CoreFrameworkCheck - verify/create the complete target folder structure
              (idempotent). Aborts the installer on unrecoverable failure.
          4.  InitConfigFiles - ensure Core\config.json and Core\db\jobaction.json
              exist. If either file is missing, attempt to fetch the canonical version
              from the WinTwin.Fusion GitHub repository. If that also fails, abort and
              instruct the user to perform a CleanInstall.
          5.  InitJobActionDB - synchronize path.root in config.json and all absolute
              path / logfile references inside jobaction.json against the real
              framework root (idempotent). Non-fatal issues are reported as warnings.
          6.  LicenseIntegrityCheck - verify LICENSE.md / NOTICE exist in the root and
              match the expected SHA512 checksums (integrity check).
          7.  Verify the system is Windows 11 24H2 or 25H2.
          8.  Verify a functional DISM installation is present.
          9.  Verify the Windows ADK is installed (silently install it from
              ".\AddOns\adksetup.exe" if missing).
          10. Verify the Windows ADK WinPE Add-on is installed (silently install it
              from ".\AddOns\adkwinpesetup.exe" if missing).
          11. Install all Google Fonts found under ".\Core\fonts" for all users
              (machine-wide, HKEY_LOCAL_MACHINE).
          12. UpdateFrameworkConfig - update the non-path system-information fields in
              the *real* Core\config.json schema (appinfo / appconfig / path /
              framework / action-id), without touching the path.* tree already handled
              by InitJobActionDB.
          13. Print a console checklist summarizing every step.
          14. Wait for a keypress ("Press any key to exit.") before the console window
              actually closes.

        -CleanInstall REPAIR MODE:
          When "-CleanInstall" is passed, the installer skips the entire normal flow
          above and instead:
            1. Creates ".\_GitClone" under its own root.
            2. Runs "git clone https://github.com/WinTwin-Fusion/WinTwin.Fusion.git
               <root>\_GitClone".
            3. On success, recursively deletes ".\AddOns", ".\Core", ".\DISM.UI.CC",
               ".\Lib", ".\PS.Tweak.Tools" and ".\USMT.Composer" from its own root
               (including the folders themselves).
            4. Copies those same folders back from ".\_GitClone" into the framework
               root.
            5. Deletes ".\_GitClone" again.
            6. Exits. CleanInstall's only job is to re-fetch a pristine copy of the
               framework's core components; it does NOT run the regular installation
               routine afterwards. A normal (non -CleanInstall) installer run MUST be
               performed again afterwards so that config.json / jobaction.json get
               their path information restored.
          Data folders (Drivers, Mount, MSStore, Output, Profile.Backup, RawISO,
          UserData, UUPD, AddOns\*.exe installers, etc.) are intentionally left
          untouched, so downloaded assets and in-progress project data survive a
          CleanInstall.

    .NOTES
        Project      : WinTwin.Fusion
        File         : wintwin.installer.ps1
        Version      : 0.3.0 (console-only, English source, CleanInstall + canonical
                       repo restore support)
        Last change  : 2026-08-23
        Author       : WinTwin-Fusion Team
        License      : See LICENSE.md / NOTICE in the main repository
                       https://github.com/WinTwin-Fusion/WinTwin.Fusion

        Administrator rights are REQUIRED for this script, because both the silent
        ADK/WinPE installation and the machine-wide font installation write to
        protected system locations (Program Files, Windows\Fonts, HKEY_LOCAL_MACHINE).
        The elevation check happens first, before any other action is taken.

    .PARAMETER CleanInstall
        Switches the installer into repair mode: re-clones the WinTwin.Fusion
        repository into ".\_GitClone", replaces ".\AddOns", ".\Core", ".\DISM.UI.CC",
        ".\Lib", ".\PS.Tweak.Tools" and ".\USMT.Composer" with pristine copies from
        that clone, then exits. Requires git.exe to be available on PATH. A regular
        installer run (without -CleanInstall) MUST be performed again afterwards.

    .PARAMETER SkipAdkInstall
        Skips the automatic Windows ADK installation, even if it was not found
        (status is still reported).

    .PARAMETER SkipWinPEInstall
        Skips the automatic WinPE Add-on installation, even if it was not found
        (status is still reported).

    .PARAMETER SkipFontInstall
        Skips the Google Fonts installation step entirely.

    .PARAMETER Quiet
        Reduces console output to the essentials (prepared for future unattended /
        autounattend scenarios).

    .PARAMETER NoPause
        Suppresses the final "Press any key to exit." prompt (e.g. for automated test
        runs). Do NOT use in regular interactive operation.

    .EXAMPLE
        .\wintwin.installer.ps1

    .EXAMPLE
        .\wintwin.installer.ps1 -SkipAdkInstall -SkipWinPEInstall

    .EXAMPLE
        .\wintwin.installer.ps1 -CleanInstall
#>

[CmdletBinding()]
param(
    [switch]$CleanInstall,
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

$Script:InstallerVersion       = '0.3.0'
$Script:MinBuildNumber2024H2   = 26100   # Windows 11 24H2 (RTM build)
$Script:ExitCodeSuccess        = 0
$Script:ExitCodeWarning        = 1
$Script:ExitCodeFailure        = 2
$Script:LogFilePath            = $null

# Canonical WinTwin.Fusion repository - the single source of truth for the
# framework's directory layout, config.json schema and jobaction.json schema.
$Script:RepoOwner        = 'WinTwin-Fusion'
$Script:RepoName         = 'WinTwin.Fusion'
$Script:RepoBranch       = 'main'
$Script:RepoCloneUrl     = "https://github.com/$Script:RepoOwner/$Script:RepoName.git"
$Script:RepoRawBase      = "https://raw.githubusercontent.com/$Script:RepoOwner/$Script:RepoName/$Script:RepoBranch"
$Script:RepoConfigRawUrl = "$Script:RepoRawBase/Core/config.json"
$Script:RepoJobActionRawUrl = "$Script:RepoRawBase/Core/db/jobaction.json"

# Folders replaced wholesale by -CleanInstall (data folders are deliberately excluded)
$Script:CleanInstallFolders = @('AddOns', 'Core', 'DISM.UI.CC', 'Lib', 'PS.Tweak.Tools', 'USMT.Composer')

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
            Writes a status line to the console AND (if possible) to the central log
            file under Core\logs\installer.log
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
            Displays "Press any key to exit." and waits for a keypress before the
            console is actually closed. Falls back to Read-Host if RawUI.ReadKey() is
            unavailable (e.g. PowerShell ISE or redirected streams).
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

function Exit-WithCleanInstallHint {
    <#
        .SYNOPSIS
            Central abort routine for unrecoverable core-component failures. Always
            prints the CleanInstall hint, writes the final log line, waits for a
            keypress (unless -NoPause) and terminates the process immediately.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Reason
    )

    Write-Host ''
    Write-Host ('=' * 78) -ForegroundColor Red
    Write-Host '  FATAL: Unrecoverable core component failure' -ForegroundColor Red
    Write-Host ('=' * 78) -ForegroundColor Red
    Write-Host ''
    Write-Host "  $Reason" -ForegroundColor Red
    Write-Host ''
    Write-Host '  A required core component (folder, module or configuration file) of the' -ForegroundColor Yellow
    Write-Host '  WinTwin.Fusion framework is missing, corrupted, or could not be restored' -ForegroundColor Yellow
    Write-Host '  from the canonical GitHub repository.' -ForegroundColor Yellow
    Write-Host ''
    Write-Host '  Please run a CleanInstall to fetch a fresh, pristine copy of the core' -ForegroundColor Yellow
    Write-Host '  framework components from https://github.com/WinTwin-Fusion/WinTwin.Fusion :' -ForegroundColor Yellow
    Write-Host ''
    Write-Host '      .\wintwin.installer.ps1 -CleanInstall' -ForegroundColor White
    Write-Host ''
    Write-Host '  After CleanInstall finishes, run the regular installer once more (without' -ForegroundColor Yellow
    Write-Host '  -CleanInstall) so that config.json / jobaction.json paths are restored.' -ForegroundColor Yellow
    Write-Host ''

    Write-InstallerLog -Level 'FAIL' -Message "ABORT: $Reason"
    Wait-ForKeyPress
    exit $Script:ExitCodeFailure
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
            Verifies elevated execution. If the current session is not running as
            Administrator, an error message is printed and the script terminates
            immediately (before any other action occurs).
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
    Write-Host '  Windows ADK / WinPE Add-on, or (with -CleanInstall) delete and' -ForegroundColor Red
    Write-Host '  recreate core framework folders.' -ForegroundColor Red
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
            directory is treated as the WinTwin.Fusion framework root, regardless of
            whether it was populated via the offline ZIP release or via "git clone".
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
#  CLEANINSTALL REPAIR MODE
# --------------------------------------------------------------------------

function Invoke-CleanInstall {
    <#
        .SYNOPSIS
            Repair-mode routine: re-clones the canonical WinTwin.Fusion repository
            into ".\_GitClone" and replaces the core framework folders with pristine
            copies. Data folders are intentionally left untouched. Terminates the
            process itself when finished (success or failure) - CleanInstall never
            falls through into the regular installation routine.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$RootPath
    )

    Write-InstallerLog -Level 'STEP' -Message 'CleanInstall requested - repairing core framework components ...'
    Write-Host ''
    Write-Host ('=' * 78) -ForegroundColor Yellow
    Write-Host '  CLEANINSTALL MODE' -ForegroundColor Yellow
    Write-Host ('=' * 78) -ForegroundColor Yellow
    Write-Host ''
    Write-Host "  Repository : $Script:RepoCloneUrl" -ForegroundColor Gray
    Write-Host "  Target     : $RootPath" -ForegroundColor Gray
    Write-Host ''
    Write-Host '  The following folders will be DELETED and replaced with a pristine copy:' -ForegroundColor Gray
    foreach ($f in $Script:CleanInstallFolders) { Write-Host "    - .\$f" -ForegroundColor Gray }
    Write-Host ''
    Write-Host '  Data folders (Drivers, Mount, MSStore, Output, Profile.Backup, RawISO,' -ForegroundColor Gray
    Write-Host '  UserData, UUPD, downloaded AddOns installers) are left untouched.' -ForegroundColor Gray
    Write-Host ''

    # --- Verify git.exe is available ---
    $gitCmd = Get-Command -Name 'git.exe' -ErrorAction SilentlyContinue
    if (-not $gitCmd) {
        Write-InstallerLog -Level 'FAIL' -Message 'git.exe was not found on PATH. CleanInstall requires Git for Windows to be installed.'
        Write-Host '  ERROR: git.exe was not found on PATH.' -ForegroundColor Red
        Write-Host '  Please install Git for Windows (https://git-scm.com/download/win) and retry.' -ForegroundColor Red
        Wait-ForKeyPress
        exit $Script:ExitCodeFailure
    }

    $cloneDir = Join-Path -Path $RootPath -ChildPath '_GitClone'

    # --- Ensure a clean _GitClone directory ---
    try {
        if (Test-Path -Path $cloneDir) {
            Write-InstallerLog -Level 'WARN' -Message "Existing '_GitClone' directory found - removing it before cloning."
            Remove-Item -Path $cloneDir -Recurse -Force -ErrorAction Stop
        }
        New-Item -Path $cloneDir -ItemType Directory -Force -ErrorAction Stop | Out-Null
    }
    catch {
        Write-InstallerLog -Level 'FAIL' -Message "Could not prepare '_GitClone' directory: $($_.Exception.Message)"
        Write-Host "  ERROR: Could not prepare '_GitClone' directory: $($_.Exception.Message)" -ForegroundColor Red
        Wait-ForKeyPress
        exit $Script:ExitCodeFailure
    }

    # --- Clone the repository ---
    Write-InstallerLog -Level 'STEP' -Message "Cloning $Script:RepoCloneUrl into '$cloneDir' ..."
    try {
        $gitOutput = & git.exe clone $Script:RepoCloneUrl $cloneDir 2>&1
        $gitExit = $LASTEXITCODE
        foreach ($line in $gitOutput) { Write-InstallerLog -Level 'INFO' -Message "git: $line" }

        if ($gitExit -ne 0) {
            throw "git clone exited with code $gitExit"
        }
    }
    catch {
        Write-InstallerLog -Level 'FAIL' -Message "Repository clone failed: $($_.Exception.Message)"
        Write-Host "  ERROR: Repository clone failed: $($_.Exception.Message)" -ForegroundColor Red
        Write-Host '  Please verify your internet connection and that the repository is reachable, then retry.' -ForegroundColor Red
        try { Remove-Item -Path $cloneDir -Recurse -Force -ErrorAction SilentlyContinue } catch {}
        Wait-ForKeyPress
        exit $Script:ExitCodeFailure
    }

    Write-InstallerLog -Level 'OK' -Message 'Repository cloned successfully.'

    # --- Verify all expected folders exist in the freshly cloned copy ---
    $missingInClone = @()
    foreach ($folder in $Script:CleanInstallFolders) {
        $clonedFolderPath = Join-Path -Path $cloneDir -ChildPath $folder
        if (-not (Test-Path -Path $clonedFolderPath -PathType Container)) {
            $missingInClone += $folder
        }
    }
    if ($missingInClone.Count -gt 0) {
        Write-InstallerLog -Level 'FAIL' -Message "Cloned repository is missing expected folder(s): $($missingInClone -join ', ')"
        Write-Host "  ERROR: Cloned repository is missing expected folder(s): $($missingInClone -join ', ')" -ForegroundColor Red
        Write-Host '  The remote repository state appears inconsistent. Aborting without touching local files.' -ForegroundColor Red
        try { Remove-Item -Path $cloneDir -Recurse -Force -ErrorAction SilentlyContinue } catch {}
        Wait-ForKeyPress
        exit $Script:ExitCodeFailure
    }

    # --- Remove old core folders, then copy pristine ones from the clone ---
    $replaceFailed = @()
    foreach ($folder in $Script:CleanInstallFolders) {
        $localFolderPath  = Join-Path -Path $RootPath  -ChildPath $folder
        $clonedFolderPath = Join-Path -Path $cloneDir  -ChildPath $folder

        try {
            if (Test-Path -Path $localFolderPath) {
                Remove-Item -Path $localFolderPath -Recurse -Force -ErrorAction Stop
            }
            Copy-Item -Path $clonedFolderPath -Destination $localFolderPath -Recurse -Force -ErrorAction Stop
            Write-InstallerLog -Level 'OK' -Message "Restored '.\$folder' from canonical repository."
        }
        catch {
            $replaceFailed += "$folder ($($_.Exception.Message))"
            Write-InstallerLog -Level 'FAIL' -Message "Could not restore '.\$folder': $($_.Exception.Message)"
        }
    }

    # --- Clean up the clone directory regardless of partial failures ---
    try {
        Remove-Item -Path $cloneDir -Recurse -Force -ErrorAction Stop
        Write-InstallerLog -Level 'OK' -Message "Temporary '_GitClone' directory removed."
    }
    catch {
        Write-InstallerLog -Level 'WARN' -Message "Could not remove temporary '_GitClone' directory: $($_.Exception.Message). Please delete it manually."
    }

    Write-Host ''
    if ($replaceFailed.Count -eq 0) {
        Write-Host ('=' * 78) -ForegroundColor Green
        Write-Host '  CleanInstall completed successfully.' -ForegroundColor Green
        Write-Host ('=' * 78) -ForegroundColor Green
        Write-Host ''
        Write-Host '  IMPORTANT: Core\config.json and Core\db\jobaction.json no longer contain' -ForegroundColor Yellow
        Write-Host '  correct path information after a CleanInstall. You MUST run the regular' -ForegroundColor Yellow
        Write-Host '  installation routine once more so all paths are restored:' -ForegroundColor Yellow
        Write-Host ''
        Write-Host '      .\wintwin.installer.ps1' -ForegroundColor White
        Write-Host ''
        Wait-ForKeyPress
        exit $Script:ExitCodeSuccess
    }
    else {
        Write-Host ('=' * 78) -ForegroundColor Red
        Write-Host '  CleanInstall completed WITH ERRORS.' -ForegroundColor Red
        Write-Host ('=' * 78) -ForegroundColor Red
        Write-Host ''
        Write-Host '  The following folder(s) could not be restored:' -ForegroundColor Red
        foreach ($f in $replaceFailed) { Write-Host "    - $f" -ForegroundColor Red }
        Write-Host ''
        Write-Host '  Please resolve the underlying issue (e.g. file locks, permissions) and' -ForegroundColor Yellow
        Write-Host '  run "-CleanInstall" again.' -ForegroundColor Yellow
        Write-Host ''
        Wait-ForKeyPress
        exit $Script:ExitCodeFailure
    }
}

# --------------------------------------------------------------------------
#  STEP 2: CoreFrameworkCheck - TARGET FOLDER STRUCTURE
# --------------------------------------------------------------------------

function CoreFrameworkCheck {
    <#
        .SYNOPSIS
            Verifies / creates the complete, documented WinTwin.Fusion folder
            structure below the framework root, for every folder that does not yet
            exist. Existing folders are left untouched.

        .DESCRIPTION
            The WinTwin.Fusion GitHub repository is the single source of truth for
            this layout. The folder list below mirrors the actual, current top-level
            and second-level layout of that repository (verified against the live
            repo state on 23.08.2026), including Lib\WinTwin.XUI and the documented
            Profile.Backup / USMT.Composer subfolders that earlier installer versions
            were missing.

            Folders are split into two severity classes:
              - "Critical" folders are strictly required for the framework to operate
                at all (Core and its subfolders, Lib and its module subfolders,
                DISM.UI.CC, PS.Tweak.Tools, USMT.Composer). If any of these cannot be
                created, the installer aborts immediately with the CleanInstall hint.
              - "Optional" folders are convenience / data folders whose absence does
                not prevent the framework core from functioning. Failures here are
                reported as warnings only.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$RootPath
    )

    # Critical: required for the framework core / module system to function at all
    $criticalFolders = @(
        'Core',
        (Join-Path 'Core' 'db'),
        (Join-Path 'Core' 'export'),
        (Join-Path 'Core' 'fonts'),
        (Join-Path 'Core' 'lang'),
        (Join-Path 'Core' 'logs'),
        (Join-Path 'Core' 'ui'),
        'Lib',
        (Join-Path 'Lib' 'OPSreturn'),
        (Join-Path 'Lib' 'PSAppCoreLib'),
        (Join-Path 'Lib' 'VPDLX'),
        (Join-Path 'Lib' 'WinTwin.FXcore'),
        (Join-Path 'Lib' 'WinTwin.XUI'),
        'DISM.UI.CC',
        'PS.Tweak.Tools',
        'USMT.Composer'
    )

    # Optional: convenience / data / runtime folders (non-fatal if creation fails)
    $optionalFolders = @(
        'AddOns',
        'Drivers',
        'Mount',
        'MSStore',
        'Output',
        'RawISO',
        'UserData',
        'UUPD',
        (Join-Path 'Profile.Backup' 'Startmenu'),
        (Join-Path 'Profile.Backup' 'Taskbar'),
        (Join-Path 'USMT.Composer' 'appdata'),
        (Join-Path 'USMT.Composer' 'usrdata')
    )

    $created  = [System.Collections.Generic.List[string]]::new()
    $existing = [System.Collections.Generic.List[string]]::new()
    $failedCritical = [System.Collections.Generic.List[string]]::new()
    $failedOptional = [System.Collections.Generic.List[string]]::new()

    foreach ($folder in $criticalFolders) {
        $fullPath = Join-Path -Path $RootPath -ChildPath $folder
        if (Test-Path -Path $fullPath -PathType Container) {
            $existing.Add($folder)
            continue
        }
        try {
            New-Item -Path $fullPath -ItemType Directory -Force -ErrorAction Stop | Out-Null
            $created.Add($folder)
        }
        catch {
            $failedCritical.Add("$folder ($($_.Exception.Message))")
        }
    }

    foreach ($folder in $optionalFolders) {
        $fullPath = Join-Path -Path $RootPath -ChildPath $folder
        if (Test-Path -Path $fullPath -PathType Container) {
            $existing.Add($folder)
            continue
        }
        try {
            New-Item -Path $fullPath -ItemType Directory -Force -ErrorAction Stop | Out-Null
            $created.Add($folder)
        }
        catch {
            $failedOptional.Add("$folder ($($_.Exception.Message))")
        }
    }

    return [PSCustomObject]@{
        Created         = $created
        Existing        = $existing
        FailedCritical  = $failedCritical
        FailedOptional  = $failedOptional
    }
}

# --------------------------------------------------------------------------
#  InitConfigFiles - ENSURE config.json AND jobaction.json EXIST
# --------------------------------------------------------------------------

function Get-CanonicalFileFromRepo {
    <#
        .SYNOPSIS
            Downloads a single file's raw content from the canonical WinTwin.Fusion
            GitHub repository and writes it to a local destination path. Used as the
            restore mechanism when a required core data file is missing locally.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$SourceUrl,
        [Parameter(Mandatory)][string]$DestinationPath
    )

    try {
        $destDir = Split-Path -Path $DestinationPath -Parent
        if (-not (Test-Path -Path $destDir)) {
            New-Item -Path $destDir -ItemType Directory -Force -ErrorAction Stop | Out-Null
        }

        # Use Invoke-WebRequest so this works even without the 'curl' alias / BITS.
        $ProgressPreference = 'SilentlyContinue'
        Invoke-WebRequest -Uri $SourceUrl -OutFile $DestinationPath -UseBasicParsing -ErrorAction Stop

        if (-not (Test-Path -Path $DestinationPath -PathType Leaf)) {
            throw "Download reported success but destination file '$DestinationPath' does not exist."
        }

        # Sanity check: content must at least be parseable JSON, otherwise treat as a failed restore.
        $raw = Get-Content -Path $DestinationPath -Raw -Encoding UTF8 -ErrorAction Stop
        [void]($raw | ConvertFrom-Json -ErrorAction Stop)

        return [PSCustomObject]@{ Success = $true; Detail = "Restored from $SourceUrl" }
    }
    catch {
        # Clean up a possibly partial/invalid file so a later Test-Path doesn't report a false positive.
        try {
            if (Test-Path -Path $DestinationPath -PathType Leaf) {
                Remove-Item -Path $DestinationPath -Force -ErrorAction SilentlyContinue
            }
        }
        catch {}
        return [PSCustomObject]@{ Success = $false; Detail = $_.Exception.Message }
    }
}

function InitConfigFiles {
    <#
        .SYNOPSIS
            Ensures Core\config.json and Core\db\jobaction.json exist locally. Neither
            file is ever generated from an installer-internal template - the
            WinTwin.Fusion GitHub repository is the only source of truth for their
            schema and default content.

        .DESCRIPTION
            - If a file already exists locally, it is left completely untouched by
              this function (no overwrite). Path-value synchronization happens
              separately, in InitJobActionDB.
            - If a file is missing, this function attempts to fetch the canonical
              version directly from the WinTwin.Fusion GitHub repository (raw file
              download) and writes it to the correct local path.
            - If that restore attempt also fails (e.g. no internet connectivity, repo
              unreachable, unexpected content), this is treated as an unrecoverable
              core-component failure: the installer aborts immediately via
              Exit-WithCleanInstallHint and instructs the user to run -CleanInstall.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$RootPath
    )

    $configPath     = Join-Path -Path $RootPath -ChildPath 'Core\config.json'
    $jobActionPath  = Join-Path -Path $RootPath -ChildPath 'Core\db\jobaction.json'

    $results = [System.Collections.Generic.List[object]]::new()

    # --- Core\config.json ---
    if (Test-Path -Path $configPath -PathType Leaf) {
        $results.Add([PSCustomObject]@{ File = 'Core\config.json'; Status = 'OK'; Detail = 'Already present - left untouched.' })
    }
    else {
        Write-InstallerLog -Level 'WARN' -Message "Core\config.json is missing. Attempting restore from canonical repository ..."
        $restore = Get-CanonicalFileFromRepo -SourceUrl $Script:RepoConfigRawUrl -DestinationPath $configPath
        if ($restore.Success) {
            $results.Add([PSCustomObject]@{ File = 'Core\config.json'; Status = 'RESTORED'; Detail = $restore.Detail })
        }
        else {
            $results.Add([PSCustomObject]@{ File = 'Core\config.json'; Status = 'FAILED'; Detail = $restore.Detail })
        }
    }

    # --- Core\db\jobaction.json ---
    if (Test-Path -Path $jobActionPath -PathType Leaf) {
        $results.Add([PSCustomObject]@{ File = 'Core\db\jobaction.json'; Status = 'OK'; Detail = 'Already present - left untouched.' })
    }
    else {
        Write-InstallerLog -Level 'WARN' -Message "Core\db\jobaction.json is missing. Attempting restore from canonical repository ..."
        $restore = Get-CanonicalFileFromRepo -SourceUrl $Script:RepoJobActionRawUrl -DestinationPath $jobActionPath
        if ($restore.Success) {
            $results.Add([PSCustomObject]@{ File = 'Core\db\jobaction.json'; Status = 'RESTORED'; Detail = $restore.Detail })
        }
        else {
            $results.Add([PSCustomObject]@{ File = 'Core\db\jobaction.json'; Status = 'FAILED'; Detail = $restore.Detail })
        }
    }

    return $results
}

# --------------------------------------------------------------------------
#  InitJobActionDB - SYNCHRONIZE path.root AND jobaction.json PATH VALUES
# --------------------------------------------------------------------------

function Set-JsonRootPathValue {
    <#
        .SYNOPSIS
            Sets config.path.root to the given root path (idempotent) using plain
            Get-Content / ConvertFrom-Json / ConvertTo-Json only - no dependency on
            WinTwin.FXcore, since the installer must remain fully self-contained.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$ConfigPath,
        [Parameter(Mandatory)][string]$RootPath
    )

    try {
        $raw    = Get-Content -Path $ConfigPath -Raw -Encoding UTF8 -ErrorAction Stop
        $config = $raw | ConvertFrom-Json -ErrorAction Stop

        if (-not $config.PSObject.Properties.Match('path')) {
            return [PSCustomObject]@{ Success = $false; Detail = "config.json has no top-level 'path' node - unexpected schema." }
        }

        $config.path.root = $RootPath

        $json = $config | ConvertTo-Json -Depth 20
        Set-Content -Path $ConfigPath -Value $json -Encoding UTF8 -Force -ErrorAction Stop

        return [PSCustomObject]@{ Success = $true; Detail = "path.root set to '$RootPath'." }
    }
    catch {
        return [PSCustomObject]@{ Success = $false; Detail = $_.Exception.Message }
    }
}

function Update-JobActionPathValue {
    <#
        .SYNOPSIS
            Replaces the leading root-prefix of a single string value with the real
            framework root, if - and only if - the value actually starts with a
            recognizable root-style prefix (drive letter + ':\' + first path segment).
            Values that are already correct, empty, or do not look like an absolute
            path belonging to a previous root are left unchanged.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][AllowEmptyString()][string]$Value,
        [Parameter(Mandatory)][string]$RootPath
    )

    if ([string]::IsNullOrWhiteSpace($Value)) { return $Value }
    if ($Value.TrimStart().StartsWith($RootPath, [System.StringComparison]::OrdinalIgnoreCase)) {
        return $Value
    }
    if ($Value -notmatch '^[A-Za-z]:\\') {
        return $Value
    }

    # Strip the old drive-letter root segment (e.g. "C:\WinTwin.Fusion" or "C:\WinISO")
    # and keep everything from the first subfolder onward, then re-prefix with the
    # real, current framework root.
    $match = [System.Text.RegularExpressions.Regex]::Match($Value, '^[A-Za-z]:\\[^\\]+(\\.*)?$')
    if (-not $match.Success) { return $Value }

    $remainder = $match.Groups[1].Value  # includes leading backslash, or empty
    return "$RootPath$remainder"
}

function InitJobActionDB {
    <#
        .SYNOPSIS
            Synchronizes Core\config.json (path.root) and Core\db\jobaction.json
            (all absolute path / logfile references) against the real, current
            framework root. Idempotent - safe to run on every installer execution.

        .DESCRIPTION
            Implemented with plain Get-Content / ConvertFrom-Json / ConvertTo-Json
            only, per the installer's design goal of remaining fully self-contained
            (no dependency on WinTwin.FXcore / OPSreturn).

            Central base-path fields updated in jobaction.json, per the functional
            documentation (22.08.2026):
              uupd-catch.download.location -> framework-internal .\UUPD
              uupd-compose.isopath         -> framework-internal .\UUPD
              uupd-isodump.output          -> framework-internal .\RawISO
              wim-mount.path               -> framework-internal .\Mount
              wim-eject.path               -> framework-internal .\Mount
              every *.logfile[1] entry     -> re-rooted the same way

            A partial failure here (e.g. a single unexpected node shape) does NOT
            abort the installer - it is reported as a WARN, because the framework
            core remains structurally intact even if one path value could not be
            re-rooted; only that specific tool would need a manual path correction.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$RootPath
    )

    $configPath    = Join-Path -Path $RootPath -ChildPath 'Core\config.json'
    $jobActionPath = Join-Path -Path $RootPath -ChildPath 'Core\db\jobaction.json'

    $results = [System.Collections.Generic.List[object]]::new()

    # --- 1) config.json -> path.root ---
    if (-not (Test-Path -Path $configPath -PathType Leaf)) {
        $results.Add([PSCustomObject]@{ Target = 'config.json (path.root)'; Status = 'SKIPPED'; Detail = 'File does not exist.' })
    }
    else {
        $r = Set-JsonRootPathValue -ConfigPath $configPath -RootPath $RootPath
        if ($r.Success) { $results.Add([PSCustomObject]@{ Target = 'config.json (path.root)'; Status = 'OK'; Detail = $r.Detail }) }
        else { $results.Add([PSCustomObject]@{ Target = 'config.json (path.root)'; Status = 'WARN'; Detail = $r.Detail }) }
    }

    # --- 2) jobaction.json -> re-root all known absolute path fields + logfile entries ---
    if (-not (Test-Path -Path $jobActionPath -PathType Leaf)) {
        $results.Add([PSCustomObject]@{ Target = 'jobaction.json (paths)'; Status = 'SKIPPED'; Detail = 'File does not exist.' })
        return $results
    }

    try {
        $raw = Get-Content -Path $jobActionPath -Raw -Encoding UTF8 -ErrorAction Stop
        $db  = $raw | ConvertFrom-Json -ErrorAction Stop
    }
    catch {
        $results.Add([PSCustomObject]@{ Target = 'jobaction.json (paths)'; Status = 'WARN'; Detail = "Could not parse jobaction.json: $($_.Exception.Message)" })
        return $results
    }

    # Field-per-action-id map, per the functional documentation.
    $pathFieldMap = @{
        'uupd-catch'    = @('download.location')
        'uupd-compose'  = @('isopath', 'zipfile')
        'uupd-isodump'  = @('output', 'isofile')
        'wim-mount'     = @('path', 'imgfile')
        'wim-eject'     = @('path', 'imgfile')
        'eject'         = @('path', 'imgfile')   # legacy node name still present in some files
    }

    $updatedFields = [System.Collections.Generic.List[string]]::new()
    $warnFields    = [System.Collections.Generic.List[string]]::new()

    foreach ($actionId in $pathFieldMap.Keys) {
        $actionProp = $db.PSObject.Properties[$actionId]
        if ($null -eq $actionProp) { continue }
        $actionNode = $actionProp.Value

        foreach ($fieldPath in $pathFieldMap[$actionId]) {
            $segments = $fieldPath -split '\.'
            $node = $actionNode
            $ok = $true
            for ($i = 0; $i -lt ($segments.Count - 1); $i++) {
                $prop = $node.PSObject.Properties[$segments[$i]]
                if ($null -eq $prop) { $ok = $false; break }
                $node = $prop.Value
            }
            if (-not $ok) { continue }

            $finalKey = $segments[-1]
            $finalProp = $node.PSObject.Properties[$finalKey]
            if ($null -eq $finalProp) { continue }

            try {
                $oldValue = [string]$finalProp.Value
                $newValue = Update-JobActionPathValue -Value $oldValue -RootPath $RootPath
                if ($newValue -ne $oldValue) {
                    $node.$finalKey = $newValue
                    $updatedFields.Add("$actionId.$fieldPath")
                }
            }
            catch {
                $warnFields.Add("$actionId.$fieldPath ($($_.Exception.Message))")
            }
        }

        # logfile is always [ <bool>, <path-string> ]
        $logfileProp = $actionNode.PSObject.Properties['logfile']
        if ($null -ne $logfileProp -and $logfileProp.Value -is [System.Array] -and $logfileProp.Value.Count -ge 2) {
            try {
                $oldValue = [string]$logfileProp.Value[1]
                $newValue = Update-JobActionPathValue -Value $oldValue -RootPath $RootPath
                if ($newValue -ne $oldValue) {
                    $logfileProp.Value[1] = $newValue
                    $updatedFields.Add("$actionId.logfile[1]")
                }
            }
            catch {
                $warnFields.Add("$actionId.logfile[1] ($($_.Exception.Message))")
            }
        }
    }

    try {
        $json = $db | ConvertTo-Json -Depth 20
        Set-Content -Path $jobActionPath -Value $json -Encoding UTF8 -Force -ErrorAction Stop

        $detail = "Updated fields: $($updatedFields.Count)"
        if ($warnFields.Count -gt 0) { $detail += " / Issues: $($warnFields -join '; ')" }
        $status = if ($warnFields.Count -gt 0) { 'WARN' } else { 'OK' }
        $results.Add([PSCustomObject]@{ Target = 'jobaction.json (paths)'; Status = $status; Detail = $detail })
    }
    catch {
        $results.Add([PSCustomObject]@{ Target = 'jobaction.json (paths)'; Status = 'WARN'; Detail = "Could not write jobaction.json: $($_.Exception.Message)" })
    }

    return $results
}

# --------------------------------------------------------------------------
#  LicenseIntegrityCheck (formerly: Test-FrameworkLicenseIntegrity)
# --------------------------------------------------------------------------

function LicenseIntegrityCheck {
    <#
        .SYNOPSIS
            Verifies that LICENSE.md and NOTICE exist in the framework root and that
            their SHA512 checksums match the official WinTwin.Fusion originals.
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

#  UpdateFrameworkConfig (formerly: Update-FrameworkConfigJson)
# --------------------------------------------------------------------------

function UpdateFrameworkConfig {
    <#
        .SYNOPSIS
            Updates the non-path system/installer information inside the *real*
            Core\config.json schema (appinfo / appconfig / path / framework /
            action-id), as defined by the canonical WinTwin.Fusion repository.

        .DESCRIPTION
            This function intentionally does NOT touch the "path" tree - that is
            exclusively owned by InitJobActionDB (path.root) and by the canonical
            file content restored via InitConfigFiles. UpdateFrameworkConfig only
            adds/refreshes informational fields that describe the current system and
            installer run, using the existing "appinfo" node (dateupdate) and a new,
            additive "installer" sub-node under "appinfo" for run diagnostics, so the
            documented schema (appinfo/appconfig/path/framework/action-id) is
            preserved rather than replaced with an incompatible ad-hoc structure.

            If config.json cannot be read/parsed at this point, this is treated as
            non-fatal for this specific step (InitConfigFiles / InitJobActionDB
            already handled the fatal cases earlier in the flow) and reported as a
            WARN instead of aborting the whole installer a second time.
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

    $configPath = Join-Path -Path $RootPath -ChildPath 'Core\config.json'

    if (-not (Test-Path -Path $configPath -PathType Leaf)) {
        return [PSCustomObject]@{ Success = $false; Path = $configPath; Detail = 'Core\config.json does not exist at this point.' }
    }

    try {
        $raw    = Get-Content -Path $configPath -Raw -Encoding UTF8 -ErrorAction Stop
        $config = $raw | ConvertFrom-Json -ErrorAction Stop
    }
    catch {
        return [PSCustomObject]@{ Success = $false; Path = $configPath; Detail = "Could not parse config.json: $($_.Exception.Message)" }
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

    # --- appinfo.dateupdate: refresh to today, per the documented schema ---
    if ($config.PSObject.Properties.Match('appinfo')) {
        Set-JsonProperty -Object $config.appinfo -Name 'dateupdate' -Value (Get-Date -Format 'dd.MM.yyyy')
    }

    # --- Additive diagnostics node: appinfo.installer (does not exist in the
    #     original schema yet, but is purely additive and does not alter path/
    #     appdb/action-id, so it cannot break any consumer that reads those). ---
    if ($config.PSObject.Properties.Match('appinfo')) {
        if (-not $config.appinfo.PSObject.Properties.Match('installer')) {
            $config.appinfo | Add-Member -MemberType NoteProperty -Name 'installer' -Value ([PSCustomObject]@{}) -Force
        }
        $installerNode = $config.appinfo.installer
        Set-JsonProperty -Object $installerNode -Name 'installerVersion'       -Value $Script:InstallerVersion
        Set-JsonProperty -Object $installerNode -Name 'lastRunUtc'             -Value ([DateTime]::UtcNow.ToString('o'))
        Set-JsonProperty -Object $installerNode -Name 'windowsProductName'     -Value $WindowsInfo.ProductName
        Set-JsonProperty -Object $installerNode -Name 'windowsDisplayVersion'  -Value $WindowsInfo.DisplayVersion
        Set-JsonProperty -Object $installerNode -Name 'windowsBuildNumber'     -Value $WindowsInfo.BuildNumber
        Set-JsonProperty -Object $installerNode -Name 'windowsSupported'       -Value $WindowsInfo.IsSupported
        Set-JsonProperty -Object $installerNode -Name 'dismAvailable'          -Value $DismInfo.Available
        Set-JsonProperty -Object $installerNode -Name 'adkInstalled'           -Value $AdkInfo.Installed
        Set-JsonProperty -Object $installerNode -Name 'adkPath'                -Value $AdkInfo.Path
        Set-JsonProperty -Object $installerNode -Name 'winPEAddonInstalled'    -Value $WinPEInfo.Installed
        Set-JsonProperty -Object $installerNode -Name 'winPEAddonPath'         -Value $WinPEInfo.Path
        Set-JsonProperty -Object $installerNode -Name 'fontsInstalledCount'    -Value $FontInfo.Installed.Count
    }

    try {
        $json = $config | ConvertTo-Json -Depth 20
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
        Write-Host " Result: FAILED  ($failCount failed step(s), $warnCount warning(s))" -ForegroundColor Red
        return $Script:ExitCodeFailure
    }
    elseif ($warnCount -gt 0) {
        Write-Host " Result: COMPLETED WITH WARNINGS  ($warnCount warning(s))" -ForegroundColor Yellow
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

    # --- Step 0: Elevation check (must be the very first action, even for -CleanInstall) ---
    Assert-AdministratorOrExit
    Write-InstallerLog -Level 'OK' -Message 'Running with Administrator privileges.'
    Add-StepResult -Name 'Administrator privilege check' -Status 'OK' -Detail 'Elevated session confirmed.'

    # --- Determine root (needed both for -CleanInstall and the regular flow) ---
    $frameworkRoot = Get-FrameworkRoot
    Write-InstallerLog -Level 'STEP' -Message "Detected framework root: $frameworkRoot"
    Add-StepResult -Name 'Determine framework root' -Status 'OK' -Detail $frameworkRoot

    # --- CleanInstall branch: repair mode, exits internally, never falls through ---
    if ($CleanInstall) {
        Invoke-CleanInstall -RootPath $frameworkRoot
        # Invoke-CleanInstall always calls exit itself; this line is unreachable
        # but kept for defensive clarity.
        exit $Script:ExitCodeSuccess
    }

    # ----------------------------------------------------------------------
    # REGULAR INSTALLATION / VALIDATION FLOW
    # ----------------------------------------------------------------------

    # --- 1) CoreFrameworkCheck: folder structure (critical failures abort immediately) ---
    Write-InstallerLog -Level 'STEP' -Message 'Running CoreFrameworkCheck (folder structure) ...'
    $folderResult = CoreFrameworkCheck -RootPath $frameworkRoot

    $Script:LogFilePath = Join-Path -Path $frameworkRoot -ChildPath 'Core\logs\installer.log'

    if ($folderResult.FailedCritical.Count -gt 0) {
        Write-InstallerLog -Level 'FAIL' -Message "Critical folder(s) could not be created: $($folderResult.FailedCritical -join '; ')"
        Exit-WithCleanInstallHint -Reason "One or more critical framework folders could not be created: $($folderResult.FailedCritical -join '; ')"
    }

    $detail = "Created: $($folderResult.Created.Count) / Already present: $($folderResult.Existing.Count)"
    if ($folderResult.FailedOptional.Count -gt 0) {
        $detail += " / Optional folder issues: $($folderResult.FailedOptional -join '; ')"
        Write-InstallerLog -Level 'WARN' -Message $detail
        Add-StepResult -Name 'CoreFrameworkCheck (folder structure)' -Status 'WARN' -Detail $detail
    }
    else {
        Write-InstallerLog -Level 'OK' -Message "CoreFrameworkCheck complete. $detail"
        Add-StepResult -Name 'CoreFrameworkCheck (folder structure)' -Status 'OK' -Detail $detail
    }

    # --- 2) InitConfigFiles: ensure config.json + jobaction.json exist (fatal on failure) ---
    Write-InstallerLog -Level 'STEP' -Message 'Running InitConfigFiles (config.json / jobaction.json presence) ...'
    $initConfigResults = InitConfigFiles -RootPath $frameworkRoot

    $fatalConfigFailures = @()
    foreach ($r in $initConfigResults) {
        switch ($r.Status) {
            'OK'       { Write-InstallerLog -Level 'OK'   -Message "$($r.File): $($r.Detail)"; Add-StepResult -Name "InitConfigFiles: $($r.File)" -Status 'OK' -Detail $r.Detail }
            'RESTORED' { Write-InstallerLog -Level 'WARN' -Message "$($r.File): $($r.Detail)"; Add-StepResult -Name "InitConfigFiles: $($r.File)" -Status 'WARN' -Detail $r.Detail }
            'FAILED'   {
                Write-InstallerLog -Level 'FAIL' -Message "$($r.File): $($r.Detail)"
                Add-StepResult -Name "InitConfigFiles: $($r.File)" -Status 'FAIL' -Detail $r.Detail
                $fatalConfigFailures += "$($r.File): $($r.Detail)"
            }
        }
    }

    if ($fatalConfigFailures.Count -gt 0) {
        Exit-WithCleanInstallHint -Reason "Required core data file(s) are missing and could not be restored from the canonical repository: $($fatalConfigFailures -join ' | ')"
    }

    # --- 3) InitJobActionDB: synchronize path.root + jobaction.json path values (non-fatal) ---
    Write-InstallerLog -Level 'STEP' -Message 'Running InitJobActionDB (path synchronization) ...'
    $jobActionResults = InitJobActionDB -RootPath $frameworkRoot

    foreach ($r in $jobActionResults) {
        switch ($r.Status) {
            'OK'      { Write-InstallerLog -Level 'OK'   -Message "$($r.Target): $($r.Detail)"; Add-StepResult -Name "InitJobActionDB: $($r.Target)" -Status 'OK' -Detail $r.Detail }
            'WARN'    { Write-InstallerLog -Level 'WARN' -Message "$($r.Target): $($r.Detail)"; Add-StepResult -Name "InitJobActionDB: $($r.Target)" -Status 'WARN' -Detail $r.Detail }
            'SKIPPED' { Write-InstallerLog -Level 'WARN' -Message "$($r.Target): $($r.Detail)"; Add-StepResult -Name "InitJobActionDB: $($r.Target)" -Status 'WARN' -Detail $r.Detail }
        }
    }

    # --- 4) LicenseIntegrityCheck ---
    Write-InstallerLog -Level 'STEP' -Message 'Running LicenseIntegrityCheck (SHA512) ...'
    $licenseResults = LicenseIntegrityCheck -RootPath $frameworkRoot

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

    # --- 5) Rest of the existing flow: Windows version, DISM, ADK, WinPE, Fonts ---
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

    Write-InstallerLog -Level 'STEP' -Message 'Checking DISM functionality ...'
    $dismInfo = Test-DismAvailable
    if ($dismInfo.Available) {
        Write-InstallerLog -Level 'OK' -Message "DISM is functional: $($dismInfo.Detail)"
        Add-StepResult -Name 'Check DISM functionality' -Status 'OK' -Detail $dismInfo.Detail
    }
    else {
        Write-InstallerLog -Level 'FAIL' -Message "DISM check failed: $($dismInfo.Detail)"
        Add-StepResult -Name 'Check DISM functionality' -Status 'FAIL' -Detail $dismInfo.Detail
    }

    Write-InstallerLog -Level 'STEP' -Message 'Checking Windows ADK installation ...'
    $adkInfo = Get-AdkInstallInfo
    if ($adkInfo.Installed) {
        Write-InstallerLog -Level 'OK' -Message "Windows ADK found: $($adkInfo.Path)"
        Add-StepResult -Name 'Check Windows ADK' -Status 'OK' -Detail $adkInfo.Path
    }
    elseif ($SkipAdkInstall) {
        Write-InstallerLog -Level 'WARN' -Message 'Windows ADK not found - skipped by -SkipAdkInstall.'
        Add-StepResult -Name 'Check Windows ADK' -Status 'WARN' -Detail 'Not installed, installation skipped by parameter.'
    }
    else {
        Write-InstallerLog -Level 'WARN' -Message 'Windows ADK not found - attempting silent installation via .\AddOns\adksetup.exe ...'
        $adkSetupPath = Join-Path -Path $frameworkRoot -ChildPath 'AddOns\adksetup.exe'
        $adkInstallResult = Install-AdkComponentSilent -InstallerPath $adkSetupPath `
            -Features @('OptionId.DeploymentTools', 'OptionId.UserStateMigrationTool') `
            -FriendlyName 'Windows ADK (Deployment Tools + USMT)'
        if ($adkInstallResult.Success) {
            Write-InstallerLog -Level 'OK' -Message $adkInstallResult.Detail
            Add-StepResult -Name 'Install Windows ADK' -Status 'OK' -Detail $adkInstallResult.Detail
            $adkInfo = Get-AdkInstallInfo
        }
        else {
            Write-InstallerLog -Level 'FAIL' -Message $adkInstallResult.Detail
            Add-StepResult -Name 'Install Windows ADK' -Status 'FAIL' -Detail $adkInstallResult.Detail
        }
    }

    Write-InstallerLog -Level 'STEP' -Message 'Checking Windows ADK WinPE Add-on installation ...'
    $winpeInfo = Get-WinPEAddonInstallInfo -KitsRoot10 $adkInfo.KitsRoot
    if ($winpeInfo.Installed) {
        Write-InstallerLog -Level 'OK' -Message "WinPE Add-on found: $($winpeInfo.Path)"
        Add-StepResult -Name 'Check WinPE Add-on' -Status 'OK' -Detail $winpeInfo.Path
    }
    elseif ($SkipWinPEInstall) {
        Write-InstallerLog -Level 'WARN' -Message 'WinPE Add-on not found - skipped by -SkipWinPEInstall.'
        Add-StepResult -Name 'Check WinPE Add-on' -Status 'WARN' -Detail 'Not installed, installation skipped by parameter.'
    }
    else {
        Write-InstallerLog -Level 'WARN' -Message 'WinPE Add-on not found - attempting silent installation via .\AddOns\adkwinpesetup.exe ...'
        $winpeSetupPath = Join-Path -Path $frameworkRoot -ChildPath 'AddOns\adkwinpesetup.exe'
        $winpeInstallResult = Install-AdkComponentSilent -InstallerPath $winpeSetupPath `
            -Features @('OptionId.WindowsPreinstallationEnvironment') `
            -FriendlyName 'Windows ADK WinPE Add-on'
        if ($winpeInstallResult.Success) {
            Write-InstallerLog -Level 'OK' -Message $winpeInstallResult.Detail
            Add-StepResult -Name 'Install WinPE Add-on' -Status 'OK' -Detail $winpeInstallResult.Detail
            $winpeInfo = Get-WinPEAddonInstallInfo -KitsRoot10 $adkInfo.KitsRoot
        }
        else {
            Write-InstallerLog -Level 'FAIL' -Message $winpeInstallResult.Detail
            Add-StepResult -Name 'Install WinPE Add-on' -Status 'FAIL' -Detail $winpeInstallResult.Detail
        }
    }

    if ($SkipFontInstall) {
        Write-InstallerLog -Level 'WARN' -Message 'Google Fonts installation skipped by -SkipFontInstall.'
        Add-StepResult -Name 'Install Google Fonts' -Status 'SKIP' -Detail 'Skipped by parameter.'
        $fontInfo = [PSCustomObject]@{ Installed = @(); Skipped = @(); Failed = @(); Detail = 'Skipped by parameter.' }
    }
    else {
        Write-InstallerLog -Level 'STEP' -Message 'Installing Google Fonts for all users ...'
        $fontsSourcePath = Join-Path -Path $frameworkRoot -ChildPath 'Core\fonts'
        $fontInfo = Install-FrameworkFonts -FontsSourcePath $fontsSourcePath
        if ($fontInfo.Failed.Count -eq 0) {
            Write-InstallerLog -Level 'OK' -Message $fontInfo.Detail
            Add-StepResult -Name 'Install Google Fonts' -Status 'OK' -Detail $fontInfo.Detail
        }
        else {
            Write-InstallerLog -Level 'WARN' -Message $fontInfo.Detail
            Add-StepResult -Name 'Install Google Fonts' -Status 'WARN' -Detail $fontInfo.Detail
        }
    }

    # --- 6) UpdateFrameworkConfig: refresh system/installer info, using the REAL schema ---
    Write-InstallerLog -Level 'STEP' -Message 'Running UpdateFrameworkConfig (appinfo/appconfig/path/framework/action-id schema) ...'
    $configResult = UpdateFrameworkConfig -RootPath $frameworkRoot -WindowsInfo $winInfo `
        -DismInfo $dismInfo -AdkInfo $adkInfo -WinPEInfo $winpeInfo -FontInfo $fontInfo

    if ($configResult.Success) {
        Write-InstallerLog -Level 'OK' -Message "config.json updated: $($configResult.Path)"
        Add-StepResult -Name 'UpdateFrameworkConfig' -Status 'OK' -Detail $configResult.Path
    }
    else {
        Write-InstallerLog -Level 'WARN' -Message "config.json system-info update failed: $($configResult.Detail)"
        Add-StepResult -Name 'UpdateFrameworkConfig' -Status 'WARN' -Detail $configResult.Detail
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

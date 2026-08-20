<#
    ============================================================================
     WTF.Console.ps1  (WTF = WinTwin.Fusion)
     Part of PS.Tweak.Tools within the WinTwin Fusion Framework
    ============================================================================

    PURPOSE
    -------
    WTF.Console is a graphical wrapper around the Windows console / terminal.
    It starts a hidden child PowerShell process and redirects its standard input,
    output and error streams into its own WPF UI, and allows the running
    process to be observed and driven interactively - without ever showing a
    native console window. This makes it possible to fully supervise and
    control long-running DISM/USMT/aria2/etc. console operations from within
    the WinTwin.Fusion ecosystem instead of relying on the OS console host.

    OPERATING MODES
    ----------------
    -AppMode framework   (default)
        Uses the shared framework resources directly from the WinTwin.Fusion
        root (Core\ui, Core\lang, Core\db, Lib\...). Loads the OPSreturn,
        WinTwin.FXcore, PSAppCoreLib and (optionally) VPDLX modules straight
        from the framework's own .\Lib folder. Honors console.logging /
        VPDLX-based logging as configured in the global Core\config.json.
        Window has Close + Minimize buttons only and can be resized only via
        -WinSize.

    -AppMode standalone (a.k.a. "portable mode")
        Runs as a fully self-contained, portable copy of WTF.Console that does
        NOT require the rest of the WinTwin.Fusion framework to be installed
        on the target machine. It still uses the very same shared PowerShell
        modules (OPSreturn, WinTwin.FXcore, PSAppCoreLib, VPDLX) - they are
        simply expected to live in a local ".\wtf.data" folder instead of the
        framework root. In other words: ".\wtf.data" is a self-contained
        mirror of exactly the slice of the WinTwin.Fusion root that
        WTF.Console needs (its own UI/lang/config resources, PLUS the shared
        Lib\ modules), copied next to WTF.Console.ps1. See wtf.readme.md for
        the exact recommended folder layout of a portable copy. No output
        watching / process-database updates happen in this mode, since there
        is no framework-wide "Core\db" to write into.

    MANDATORY PARAMETER
    --------------------
    -ScriptPath   Full path to the PowerShell script that should be executed
                  inside the redirected console process. Required in BOTH
                  operating modes. The file's existence is validated before
                  the process is started.

    EXAMPLES
    --------
    .\WTF.Console.ps1 -ScriptPath "C:\WinTwin\Core\db\temp.mount.ps1" -Action mount
    .\WTF.Console.ps1 -ScriptPath ".\myscript.ps1" -AppMode standalone

    Author:   praetoriani
    Version:  1.00.00   Date: 20.08.2026
    ============================================================================
#>

[CmdletBinding()]
param(
    # Mandatory in both modes. This is the script that will actually be
    # executed inside the hidden, redirected child process - WTF.Console
    # itself never runs any workload code, it purely hosts and supervises it.
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$ScriptPath,

    # 'framework'  -> resource paths are resolved against the WinTwin.Fusion
    #                 root (one level above PS.Tweak.Tools).
    # 'standalone' -> resource paths are resolved against a local ".\wtf.data"
    #                 folder placed next to this script (portable mode).
    [Parameter(Mandatory = $false)]
    [ValidateSet('framework', 'standalone')]
    [string]$AppMode = 'framework',

    # Optional fixed window size "WIDTHxHEIGHT", e.g. "640x480".
    # Framework mode only - standalone mode is always resizable and always
    # starts at 800x600 regardless of this parameter.
    [Parameter(Mandatory = $false)]
    [ValidatePattern('^\d{2,5}x\d{2,5}$')]
    [string]$WinSize,

    # Free-form tag (e.g. "mount", "unmount") written into the framework's
    # process database (Core\db\dbprocess.json) so other framework tools can
    # see what WTF.Console is currently doing. Framework mode only; ignored
    # in standalone mode since there is no shared process database there.
    [Parameter(Mandatory = $false)]
    [string]$Action,

    # Overrides the default UI language ("en-us" / "de-de") that would
    # otherwise be taken from wtf.config.json's appconfig.defaultlanguage.
    [Parameter(Mandatory = $false)]
    [string]$Language
)

# ────────────────────────────────────────────────────────────────────────────
#  0) BASIC ENVIRONMENT SETUP
#     Load the WPF assemblies that XamlReader / Window / TextBox etc. need.
#     These ship with Windows itself, so no external dependency is required.
# ────────────────────────────────────────────────────────────────────────────
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName PresentationCore
Add-Type -AssemblyName WindowsBase

# Folder that contains THIS script (PS.Tweak.Tools\ in framework mode, or the
# root of the portable copy in standalone mode).
$ScriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path

# ────────────────────────────────────────────────────────────────────────────
#  1) RESOLVE RUNTIME PATHS (framework vs. standalone)
#
#     This function is the single place that decides where WTF.Console loads
#     its UI (XAML), language files, config and shared PowerShell modules
#     from, depending on -AppMode. Everything downstream just uses $Paths.*
#     and never needs to branch on $AppMode again for path questions.
# ────────────────────────────────────────────────────────────────────────────
function Resolve-WtfPaths {
    param([string]$Mode, [string]$Root)

    $result = [ordered]@{
        Mode           = $Mode
        UiXaml         = $null   # full path to wtf.console.main.xml
        LangDir        = $null   # folder containing the wtf.console.*.json language files
        ConfigJson     = $null   # full path to wtf.config.json
        LogDir         = $null   # folder VPDLX-style log files get written to
        FrameworkRoot  = $null   # WinTwin.Fusion root (framework mode only, used for Core\db)
        ModulesDir     = $null   # folder containing OPSreturn / WinTwin.FXcore / PSAppCoreLib / VPDLX
    }

    if ($Mode -eq 'standalone') {
        # Portable mode: everything lives under ".\wtf.data" next to this
        # script. This folder is expected to be a self-contained mirror of
        # the relevant slice of the WinTwin.Fusion root - see wtf.readme.md
        # for the recommended layout (wtf.data\ui, wtf.data\lang,
        # wtf.data\wtf.config.json, and importantly wtf.data\Lib\... for the
        # shared modules). This is what makes a standalone copy of
        # WTF.Console fully portable: copy the folder, run the script,
        # nothing else needs to be installed.
        $appData = Join-Path $Root 'wtf.data'
        if (-not (Test-Path -LiteralPath $appData)) {
            throw "Standalone mode requires a '.\wtf.data' folder next to WTF.Console.ps1, but it was not found at: $appData"
        }
        $result.UiXaml     = Join-Path $appData 'ui\wtf.console.main.xml'
        $result.LangDir    = Join-Path $appData 'lang'
        $result.ConfigJson = Join-Path $appData 'wtf.config.json'
        $result.LogDir     = Join-Path $appData 'logs'
        # Standalone mode also uses the shared PowerShell modules - they are
        # simply expected to have been copied into ".\wtf.data\Lib" instead
        # of being loaded from a full framework installation.
        $result.ModulesDir = Join-Path $appData 'Lib'
    }
    else {
        # Framework mode: PS.Tweak.Tools\WTF.Console.ps1 -> ..\ is the
        # WinTwin.Fusion root, so every shared resource is resolved relative
        # to that root instead of a local copy.
        $frameworkRoot = Split-Path -Parent $Root
        $result.FrameworkRoot = $frameworkRoot
        $result.UiXaml        = Join-Path $frameworkRoot 'Core\ui\wtf.console.main.xml'
        $result.LangDir       = Join-Path $frameworkRoot 'Core\lang'
        $result.ConfigJson    = Join-Path $frameworkRoot 'Core\wtf.config.json'
        $result.LogDir        = Join-Path $frameworkRoot 'Core\logs'
        $result.ModulesDir    = Join-Path $frameworkRoot 'Lib'
    }
    return $result
}

$Paths = Resolve-WtfPaths -Mode $AppMode -Root $ScriptRoot

# ────────────────────────────────────────────────────────────────────────────
#  2) VALIDATE MANDATORY SCRIPT PARAMETER
#     Fail fast, with a friendly message box, before any UI is built at all,
#     if the target script does not exist. Resolve-Path afterwards turns a
#     relative path into an absolute one, since the child process will be
#     started with its own working directory context.
# ────────────────────────────────────────────────────────────────────────────
if (-not (Test-Path -LiteralPath $ScriptPath -PathType Leaf)) {
    [System.Windows.MessageBox]::Show(
        "The specified script file could not be found:`n$ScriptPath",
        'WTF.Console - Fatal Error',
        [System.Windows.MessageBoxButton]::OK,
        [System.Windows.MessageBoxImage]::Error
    ) | Out-Null
    exit 1
}
$ScriptPath = (Resolve-Path -LiteralPath $ScriptPath).ProviderPath

# ────────────────────────────────────────────────────────────────────────────
#  3) LOAD SHARED POWERSHELL MODULES
#     Identical logic for both modes: $Paths.ModulesDir already points to
#     either "<FrameworkRoot>\Lib" (framework mode) or ".\wtf.data\Lib"
#     (standalone mode) - see Resolve-WtfPaths above. WTF.Console does not
#     hard-fail if a module is missing; it just falls back to writing plain
#     text log lines instead of using Write-VpdlxLog (see Write-WtfLog below).
# ────────────────────────────────────────────────────────────────────────────
$UseFrameworkModules = $false
if ($Paths.ModulesDir -and (Test-Path -LiteralPath $Paths.ModulesDir)) {
    $moduleNames = @('OPSreturn', 'WinTwin.FXcore', 'PSAppCoreLib', 'VPDLX')
    foreach ($mod in $moduleNames) {
        $modPath = Join-Path $Paths.ModulesDir $mod
        if (Test-Path -LiteralPath $modPath) {
            try {
                Import-Module $modPath -Force -ErrorAction Stop
                $UseFrameworkModules = $true
            }
            catch {
                Write-Warning "WTF.Console: could not import module '$mod': $($_.Exception.Message)"
            }
        }
    }
}

# ────────────────────────────────────────────────────────────────────────────
#  4) LOAD CONFIGURATION (wtf.config.json)
#     Read the program's own config (version/author/website/defaults). This
#     is intentionally tolerant: if the file is missing or malformed, we warn
#     and continue with sensible hard-coded defaults further down instead of
#     aborting the whole tool.
# ────────────────────────────────────────────────────────────────────────────
$Config = $null
if (Test-Path -LiteralPath $Paths.ConfigJson) {
    try {
        $Config = Get-Content -LiteralPath $Paths.ConfigJson -Raw | ConvertFrom-Json
    }
    catch {
        Write-Warning "WTF.Console: failed to parse wtf.config.json: $($_.Exception.Message)"
    }
}

$DefaultLanguage = if ($Config -and $Config.appconfig.defaultlanguage) { $Config.appconfig.defaultlanguage } else { 'en-us' }
$SelectedLanguage = if ($Language) { $Language } else { $DefaultLanguage }

# Logging is an explicit opt-in via wtf.config.json (console.logging) and is
# only ever consulted in framework mode - a portable standalone copy has no
# guarantee that its "wtf.data\logs" location is desired/writable, so we
# deliberately keep standalone mode silent by default.
$LoggingEnabled = $false
if ($AppMode -eq 'framework' -and $Config -and $Config.PSObject.Properties.Name -contains 'console') {
    $LoggingEnabled = [bool]$Config.console.logging
}

# ────────────────────────────────────────────────────────────────────────────
#  5) LOAD LANGUAGE FILE
# ────────────────────────────────────────────────────────────────────────────
function Get-WtfLangStrings {
    param([string]$LangDir, [string]$LangCode)

    $langFile = Join-Path $LangDir "wtf.console.$LangCode.json"
    if (-not (Test-Path -LiteralPath $langFile)) {
        # Fallback / safety net: if $LangCode does not resolve to an existing
        # file - e.g. because wtf.config.json's "defaultlanguage" contains a
        # typo, an unsupported language code, or -Language was passed a
        # value for which no language file exists at all - we always fall
        # back to English (en-us) as the guaranteed-to-exist baseline
        # language, rather than failing to start the UI entirely.
        $langFile = Join-Path $LangDir 'wtf.console.en-us.json'
    }
    if (Test-Path -LiteralPath $langFile) {
        return (Get-Content -LiteralPath $langFile -Raw | ConvertFrom-Json)
    }
    # Even the en-us fallback is missing - Get-WtfString below is written to
    # tolerate $Lang being $null by returning the raw lookup key untranslated.
    return $null
}

$Lang = Get-WtfLangStrings -LangDir $Paths.LangDir -LangCode $SelectedLanguage

# Small helper that resolves a dotted key path (e.g. "status.finishedOk")
# against the loaded language object and optionally applies
# [string]::Format-style {0}/{1} placeholders. If the key or the whole
# language file is missing, it degrades gracefully by returning $Path itself
# so the UI never shows a blank string - just an unlocalized fallback token.
function Get-WtfString {
    param([string]$Path, [object[]]$FormatArgs)
    $segments = $Path.Split('.')
    $node = $Lang
    foreach ($seg in $segments) {
        if ($null -eq $node) { return $Path }
        $node = $node.$seg
    }
    if ($null -eq $node) { return $Path }
    if ($FormatArgs -and $FormatArgs.Count -gt 0) {
        return [string]::Format($node, $FormatArgs)
    }
    return $node
}

# ────────────────────────────────────────────────────────────────────────────
#  6) INITIALIZE LOGGING (VPDLX, framework mode only)
#     Builds the log file name from console.defaultlog in wtf.config.json,
#     replacing the "[DATETIME]" placeholder with the current timestamp, and
#     writes an initial "session started" line either via the framework's
#     own VPDLX module (if it was imported successfully above) or via a
#     plain Add-Content fallback.
# ────────────────────────────────────────────────────────────────────────────
$LogFilePath = $null
if ($AppMode -eq 'framework' -and $LoggingEnabled) {
    try {
        if (-not (Test-Path -LiteralPath $Paths.LogDir)) {
            New-Item -ItemType Directory -Path $Paths.LogDir -Force | Out-Null
        }
        $stamp = Get-Date -Format 'yyyyMMdd-HHmm'
        $logNamePattern = if ($Config -and $Config.console.defaultlog) { $Config.console.defaultlog } else { '[DATETIME].wtf.console.log' }
        $logFileName = $logNamePattern -replace '\[DATETIME\]', $stamp
        $LogFilePath = Join-Path $Paths.LogDir $logFileName

        if (Get-Command -Name 'Write-VpdlxLog' -ErrorAction SilentlyContinue) {
            Write-VpdlxLog -Path $LogFilePath -Message 'WTF.Console session started.' -Level 'Info'
        }
        else {
            Add-Content -LiteralPath $LogFilePath -Value "[$(Get-Date -Format 'u')] [INFO] WTF.Console session started."
        }
    }
    catch {
        Write-Warning (Get-WtfString -Path 'messages.logfileInitFailed' -FormatArgs @($_.Exception.Message))
    }
}

# Thin wrapper used everywhere else in this script instead of calling
# Write-VpdlxLog / Add-Content directly. Silently does nothing if logging
# was never initialized above (e.g. disabled, or standalone mode).
function Write-WtfLog {
    param([string]$Message, [string]$Level = 'Info')
    if (-not $LogFilePath) { return }
    try {
        if (Get-Command -Name 'Write-VpdlxLog' -ErrorAction SilentlyContinue) {
            Write-VpdlxLog -Path $LogFilePath -Message $Message -Level $Level
        }
        else {
            Add-Content -LiteralPath $LogFilePath -Value "[$(Get-Date -Format 'u')] [$Level] $Message"
        }
    }
    catch { }
}

# ────────────────────────────────────────────────────────────────────────────
#  7) LOAD XAML UI
#     WTF.Console never defines its UI inline in PowerShell - the entire
#     window is described in wtf.console.main.xml and loaded here via
#     XamlReader. FindName() then pulls out every named control we need to
#     wire up event handlers for further down.
# ────────────────────────────────────────────────────────────────────────────
if (-not (Test-Path -LiteralPath $Paths.UiXaml)) {
    [System.Windows.MessageBox]::Show(
        "The required UI definition file could not be found:`n$($Paths.UiXaml)",
        'WTF.Console - Fatal Error',
        [System.Windows.MessageBoxButton]::OK,
        [System.Windows.MessageBoxImage]::Error
    ) | Out-Null
    exit 1
}

[xml]$xamlDoc = Get-Content -LiteralPath $Paths.UiXaml -Raw
$reader = New-Object System.Xml.XmlNodeReader $xamlDoc
$Window = [Windows.Markup.XamlReader]::Load($reader)

$TitleBarPanel   = $Window.FindName('TitleBarPanel')
$TitleBarText    = $Window.FindName('TitleBarText')
$BtnMinimize     = $Window.FindName('BtnMinimize')
$BtnMaximize     = $Window.FindName('BtnMaximize')
$BtnClose        = $Window.FindName('BtnClose')
$TerminalOutput  = $Window.FindName('TerminalOutput')
$InputBox        = $Window.FindName('InputBox')
$LblPrompt       = $Window.FindName('LblPrompt')
$BtnSend         = $Window.FindName('BtnSend')
$BtnClear        = $Window.FindName('BtnClear')
$StatusText      = $Window.FindName('StatusText')
$StatusInfo      = $Window.FindName('StatusInfo')

# ────────────────────────────────────────────────────────────────────────────
#  8) APPLY LOCALIZATION + MODE-SPECIFIC UI ADJUSTMENTS
#     Push every localized string from the loaded language file into the
#     corresponding control, then adjust window chrome/size based on
#     -AppMode: framework mode is Close+Minimize-only and fixed-size unless
#     -WinSize was passed; standalone mode always gets a resizable
#     Close+Minimize+Maximize window starting at 800x600.
# ────────────────────────────────────────────────────────────────────────────
$Window.Title            = Get-WtfString -Path 'window.title'
$TitleBarText.Text       = Get-WtfString -Path 'window.title'
$LblPrompt.Text          = Get-WtfString -Path 'labels.prompt'
$BtnSend.Content         = Get-WtfString -Path 'buttons.send'
$BtnClear.Content        = Get-WtfString -Path 'buttons.clear'
$BtnMinimize.ToolTip     = Get-WtfString -Path 'buttons.minimizeTooltip'
$BtnMaximize.ToolTip     = Get-WtfString -Path 'buttons.maximizeTooltip'
$BtnClose.ToolTip        = Get-WtfString -Path 'buttons.closeTooltip'
$StatusText.Text         = Get-WtfString -Path 'status.ready'
$appVersion = if ($Config -and $Config.appinfo.version) { $Config.appinfo.version } else { 'v1.00.00' }
$StatusInfo.Text         = "WTF.Console $appVersion"

if ($AppMode -eq 'framework') {
    # Framework mode: no Maximize button, fixed size unless -WinSize is given
    $BtnMaximize.Visibility = [System.Windows.Visibility]::Collapsed
    $Window.ResizeMode      = [System.Windows.ResizeMode]::CanMinimize

    if ($WinSize) {
        $parts = $WinSize.Split('x')
        $Window.Width  = [double]$parts[0]
        $Window.Height = [double]$parts[1]
    }
    else {
        $defaultSize = if ($Config -and $Config.appconfig.defaultwinsize) { $Config.appconfig.defaultwinsize } else { '800x600' }
        $parts = $defaultSize.Split('x')
        $Window.Width  = [double]$parts[0]
        $Window.Height = [double]$parts[1]
    }
}
else {
    # Standalone mode: always resizable, always starts at 800x600
    $Window.Width  = 800
    $Window.Height = 600
    $Window.ResizeMode = [System.Windows.ResizeMode]::CanResize
}

# ────────────────────────────────────────────────────────────────────────────
#  9) WINDOW CHROME BEHAVIOR (drag, minimize, maximize, close)
#     Because WindowStyle="None" is used in the XAML (frameless window), we
#     have to implement drag-to-move and double-click-to-maximize ourselves
#     on the custom title bar panel.
# ────────────────────────────────────────────────────────────────────────────
$TitleBarPanel.Add_MouseLeftButtonDown({
    param($sender, $e)
    if ($e.ClickCount -eq 2 -and $AppMode -eq 'standalone') {
        # Double-click on the title bar toggles maximize/restore - only
        # meaningful in standalone mode, since framework mode has no
        # Maximize button/state to toggle in the first place.
        if ($Window.WindowState -eq [System.Windows.WindowState]::Maximized) {
            $Window.WindowState = [System.Windows.WindowState]::Normal
        }
        else {
            $Window.WindowState = [System.Windows.WindowState]::Maximized
        }
    }
    else {
        $Window.DragMove()
    }
})

$BtnMinimize.Add_Click({ $Window.WindowState = [System.Windows.WindowState]::Minimized })

$BtnMaximize.Add_Click({
    if ($Window.WindowState -eq [System.Windows.WindowState]::Maximized) {
        $Window.WindowState = [System.Windows.WindowState]::Normal
    }
    else {
        $Window.WindowState = [System.Windows.WindowState]::Maximized
    }
})

# ────────────────────────────────────────────────────────────────────────────
#  10) OUTPUT WATCHING (framework mode only) - reacts to defined patterns
#      Standalone mode intentionally skips all of this: there is no shared
#      Core\db\dbprocess.json to report state into when running as a
#      portable, framework-independent copy.
# ────────────────────────────────────────────────────────────────────────────
$ProcessDbPath = $null
if ($AppMode -eq 'framework' -and $Paths.FrameworkRoot) {
    $ProcessDbPath = Join-Path $Paths.FrameworkRoot 'Core\db\dbprocess.json'
}

# Inspects a single line of console output and classifies it as a trigger
# event ('error' / 'success' / $null = no match). This is currently a simple
# placeholder pattern set - extend it once the exact console signatures of
# the watched operations (aria2 progress lines, DISM completion markers,
# USMT exit banners, etc.) have been finalized for each calling tool.
function Test-WtfWatchTriggers {
    param([string]$Line)
    if ($Line -match '(?i)error') { return 'error' }
    if ($Line -match '(?i)^100%|completed successfully') { return 'success' }
    return $null
}

# Persists the current state of the supervised process into the framework's
# shared process database (Core\db\dbprocess.json) as a small JSON document,
# so other framework tools/UIs can poll what WTF.Console is currently doing.
function Write-WtfProcessState {
    param([string]$State, [int]$ExitCode = -1)
    if (-not $ProcessDbPath) { return }
    try {
        $dbDir = Split-Path -Parent $ProcessDbPath
        if (-not (Test-Path -LiteralPath $dbDir)) {
            New-Item -ItemType Directory -Path $dbDir -Force | Out-Null
        }
        $entry = [ordered]@{
            action    = $Action
            script    = $ScriptPath
            state     = $State
            exitcode  = $ExitCode
            timestamp = (Get-Date -Format 'u')
        }
        $entry | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $ProcessDbPath -Encoding UTF8
    }
    catch {
        Write-WtfLog -Message "Failed to update process database: $($_.Exception.Message)" -Level 'Warn'
    }
}

# ────────────────────────────────────────────────────────────────────────────
#  11) START REDIRECTED CONSOLE PROCESS
#      This is the heart of WTF.Console: a hidden powershell.exe child
#      process running -ScriptPath, with all three standard streams
#      redirected so we can pump its output into the UI and forward user
#      input back into it, instead of ever showing a native console window.
# ────────────────────────────────────────────────────────────────────────────
$psi = New-Object System.Diagnostics.ProcessStartInfo
$psi.FileName               = 'powershell.exe'
$psi.Arguments              = "-NoLogo -NoProfile -ExecutionPolicy Bypass -File `"$ScriptPath`""
$psi.RedirectStandardInput  = $true
$psi.RedirectStandardOutput = $true
$psi.RedirectStandardError  = $true
$psi.UseShellExecute        = $false
$psi.CreateNoWindow         = $true

$Proc = New-Object System.Diagnostics.Process
$Proc.StartInfo = $psi
$Proc.EnableRaisingEvents = $true

# Appends a single line of text to the terminal output box on the UI thread
# and scrolls it into view. All process event handlers below run on
# background threads, so every UI touch must go through $Window.Dispatcher.
function Append-TerminalLine {
    param([string]$Text)
    $Window.Dispatcher.Invoke({
        $TerminalOutput.AppendText($Text + "`r`n")
        $TerminalOutput.ScrollToEnd()
    })
}

$Proc.add_OutputDataReceived({
    param($sender, $evt)
    if ($null -ne $evt.Data) {
        Append-TerminalLine -Text $evt.Data
        Write-WtfLog -Message $evt.Data -Level 'Output'

        if ($AppMode -eq 'framework') {
            $trigger = Test-WtfWatchTriggers -Line $evt.Data
            if ($trigger) { Write-WtfProcessState -State $trigger }
        }
    }
})

$Proc.add_ErrorDataReceived({
    param($sender, $evt)
    if ($null -ne $evt.Data) {
        $prefix = Get-WtfString -Path 'console.errorPrefix'
        Append-TerminalLine -Text "$prefix$($evt.Data)"
        Write-WtfLog -Message $evt.Data -Level 'Error'
    }
})

$Proc.add_Exited({
    # Fires once the child process terminates on its own (i.e. the wrapped
    # script finished). Disables further input, since sending commands to a
    # dead process would be meaningless.
    $exitCode = $Proc.ExitCode
    $Window.Dispatcher.Invoke({
        $msgKey = if ($exitCode -eq 0) { 'status.finishedOk' } else { 'status.finishedFail' }
        $StatusText.Text = Get-WtfString -Path $msgKey -FormatArgs @($exitCode)
        $InputBox.IsEnabled = $false
        $BtnSend.IsEnabled  = $false
    })
    Write-WtfLog -Message "Process exited with code $exitCode." -Level 'Info'
    if ($AppMode -eq 'framework') {
        Write-WtfProcessState -State 'finished' -ExitCode $exitCode
    }
})

try {
    $StatusText.Text = Get-WtfString -Path 'status.starting'
    $Proc.Start() | Out-Null
    # BeginOutputReadLine/BeginErrorReadLine switch the redirected streams
    # into asynchronous line-based reading, which is what triggers the
    # OutputDataReceived/ErrorDataReceived events registered above.
    $Proc.BeginOutputReadLine()
    $Proc.BeginErrorReadLine()
    $StatusText.Text = Get-WtfString -Path 'status.running' -FormatArgs @($Proc.Id)
    Write-WtfLog -Message (Get-WtfString -Path 'console.processStarted' -FormatArgs @($Proc.Id, $ScriptPath)) -Level 'Info'
    if ($AppMode -eq 'framework') { Write-WtfProcessState -State 'running' }
}
catch {
    [System.Windows.MessageBox]::Show(
        (Get-WtfString -Path 'messages.processStartFailed' -FormatArgs @($_.Exception.Message)),
        'WTF.Console - Fatal Error',
        [System.Windows.MessageBoxButton]::OK,
        [System.Windows.MessageBoxImage]::Error
    ) | Out-Null
    exit 1
}

# ────────────────────────────────────────────────────────────────────────────
#  12) INPUT HANDLING (send commands to redirected StandardInput)
#      The $SendCommand scriptblock is shared between the Send button click
#      and the Enter key inside the input box, so both paths behave
#      identically.
# ────────────────────────────────────────────────────────────────────────────
$SendCommand = {
    if (-not $Proc.HasExited -and $InputBox.Text.Length -gt 0) {
        $cmdText = $InputBox.Text
        $InputBox.Clear()
        Append-TerminalLine -Text (Get-WtfString -Path 'console.userInputEcho' -FormatArgs @($cmdText))
        $StatusText.Text = Get-WtfString -Path 'status.sending'
        try {
            $Proc.StandardInput.WriteLine($cmdText)
            Write-WtfLog -Message "User input: $cmdText" -Level 'Input'
        }
        catch {
            Write-WtfLog -Message "Failed to write to StandardInput: $($_.Exception.Message)" -Level 'Warn'
        }
        $StatusText.Text = Get-WtfString -Path 'status.running' -FormatArgs @($Proc.Id)
    }
}

$BtnSend.Add_Click($SendCommand)

$InputBox.Add_KeyDown({
    param($sender, $e)
    if ($e.Key -eq [System.Windows.Input.Key]::Enter) {
        & $SendCommand
    }
})

$BtnClear.Add_Click({
    # Only clears the visible terminal textbox - has no effect on the
    # running process itself (see wtf.readme.md / clearTooltip string).
    $TerminalOutput.Clear()
})

# ────────────────────────────────────────────────────────────────────────────
#  13) CLOSE HANDLING - terminate child process cleanly, close log
#      Closing the window while the child process is still running prompts
#      for confirmation first, since closing implies killing that process.
# ────────────────────────────────────────────────────────────────────────────
$BtnClose.Add_Click({ $Window.Close() })

$Window.Add_Closing({
    param($sender, $e)
    if (-not $Proc.HasExited) {
        $result = [System.Windows.MessageBox]::Show(
            (Get-WtfString -Path 'messages.confirmCloseRunning'),
            'WTF.Console',
            [System.Windows.MessageBoxButton]::YesNo,
            [System.Windows.MessageBoxImage]::Warning
        )
        if ($result -eq [System.Windows.MessageBoxResult]::No) {
            $e.Cancel = $true
            return
        }
        try {
            if (-not $Proc.HasExited) { $Proc.Kill() }
        }
        catch { }
        Write-WtfLog -Message (Get-WtfString -Path 'status.terminated') -Level 'Warn'
    }
})

# ────────────────────────────────────────────────────────────────────────────
#  14) SHOW WINDOW
#      ShowDialog() blocks this script until the window is closed, which is
#      exactly what we want since WTF.Console is meant to be launched as its
#      own process/window and not embedded into another UI.
# ────────────────────────────────────────────────────────────────────────────
[void]$Window.ShowDialog()

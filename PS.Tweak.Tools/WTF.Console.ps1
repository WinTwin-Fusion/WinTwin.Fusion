<#
    ============================================================================
     WTF.Console.ps1  (WTF = WinTwin.Fusion)
     Part of PS.Tweak.Tools within the WinTwin Fusion Framework
    ============================================================================

    PURPOSE
    -------
    WTF.Console is a graphical wrapper around the Windows console / terminal.
    It starts a hidden child PowerShell process, redirects its standard input,
    output and error streams into its own WPF UI, and allows the running
    process to be observed and driven interactively - without ever showing a
    native console window. This makes it possible to fully supervise and
    control long-running DISM/USMT/aria2/etc. console operations from within
    the WinTwin.Fusion ecosystem instead of relying on the OS console host.

    OPERATING MODES
    ----------------
    -AppMode framework   (default)
        Uses the shared framework resources under the WinTwin.Fusion root
        (Core\ui, Core\lang, Core\db, Lib\...). Loads the OPSreturn,
        WinTwin.FXcore, PSAppCoreLib and (optionally) VPDLX modules. Honors
        console.logging / VPDLX-based logging as configured in the global
        Core\config.json. Window has Close + Minimize buttons only and can be
        resized only via -WinSize.

    -AppMode standalone
        Runs fully self-contained. Looks for a ".\wtf.data" folder next to
        this script for wtf.console.main.xml, language files and
        wtf.config.json. Does not load any framework modules, does not watch
        or react to output, and does not use Google Fonts. Window always has
        Close + Minimize + Maximize buttons, starts at 800x600 and is freely
        resizable.

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
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$ScriptPath,

    [Parameter(Mandatory = $false)]
    [ValidateSet('framework', 'standalone')]
    [string]$AppMode = 'framework',

    [Parameter(Mandatory = $false)]
    [ValidatePattern('^\d{2,5}x\d{2,5}$')]
    [string]$WinSize,

    [Parameter(Mandatory = $false)]
    [string]$Action,

    [Parameter(Mandatory = $false)]
    [string]$Language
)

# ────────────────────────────────────────────────────────────────────────────
#  0) BASIC ENVIRONMENT SETUP
# ────────────────────────────────────────────────────────────────────────────
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName PresentationCore
Add-Type -AssemblyName WindowsBase

$ScriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path

# ────────────────────────────────────────────────────────────────────────────
#  1) RESOLVE RUNTIME PATHS (framework vs. standalone)
# ────────────────────────────────────────────────────────────────────────────
function Resolve-WtfPaths {
    param([string]$Mode, [string]$Root)

    $result = [ordered]@{
        Mode           = $Mode
        UiXaml         = $null
        LangDir        = $null
        ConfigJson     = $null
        LogDir         = $null
        FrameworkRoot  = $null
        ModulesDir     = $null
    }

    if ($Mode -eq 'standalone') {
        $appData = Join-Path $Root 'wtf.data'
        if (-not (Test-Path -LiteralPath $appData)) {
            throw "Standalone mode requires a '.\wtf.data' folder next to WTF.Console.ps1, but it was not found at: $appData"
        }
        $result.UiXaml     = Join-Path $appData 'wtf.console.main.xml'
        $result.LangDir    = $appData
        $result.ConfigJson = Join-Path $appData 'wtf.config.json'
        $result.LogDir     = Join-Path $appData 'logs'
    }
    else {
        # Framework mode: PS.Tweak.Tools\WTF.Console.ps1 -> ..\Core\...
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
#  3) LOAD FRAMEWORK MODULES (framework mode only)
# ────────────────────────────────────────────────────────────────────────────
$UseFrameworkModules = $false
if ($AppMode -eq 'framework' -and $Paths.ModulesDir -and (Test-Path -LiteralPath $Paths.ModulesDir)) {
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
        $langFile = Join-Path $LangDir 'wtf.console.en-us.json'
    }
    if (Test-Path -LiteralPath $langFile) {
        return (Get-Content -LiteralPath $langFile -Raw | ConvertFrom-Json)
    }
    return $null
}

$Lang = Get-WtfLangStrings -LangDir $Paths.LangDir -LangCode $SelectedLanguage

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
# ────────────────────────────────────────────────────────────────────────────
$TitleBarPanel.Add_MouseLeftButtonDown({
    param($sender, $e)
    if ($e.ClickCount -eq 2 -and $AppMode -eq 'standalone') {
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
# ────────────────────────────────────────────────────────────────────────────
$ProcessDbPath = $null
if ($AppMode -eq 'framework' -and $Paths.FrameworkRoot) {
    $ProcessDbPath = Join-Path $Paths.FrameworkRoot 'Core\db\dbprocess.json'
}

function Test-WtfWatchTriggers {
    param([string]$Line)
    # Placeholder hook: extend with real pattern matching (e.g. aria2 progress,
    # DISM completion markers, error strings) once the watched processes and
    # their exact console signatures have been finalized.
    if ($Line -match '(?i)error') { return 'error' }
    if ($Line -match '(?i)^100%|completed successfully') { return 'success' }
    return $null
}

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
    $TerminalOutput.Clear()
})

# ────────────────────────────────────────────────────────────────────────────
#  13) CLOSE HANDLING - terminate child process cleanly, close log
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
# ────────────────────────────────────────────────────────────────────────────
[void]$Window.ShowDialog()

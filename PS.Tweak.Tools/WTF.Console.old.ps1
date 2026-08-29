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
    [string]$Language,

    [Parameter(Mandatory = $false)]
    [string]$LogFilePath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName PresentationCore
Add-Type -AssemblyName WindowsBase

$ScriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
# Make the params global available for the isolated scopes
$global:ScriptPath    = $ScriptPath
$global:AppMode       = $AppMode
$global:WinSize       = $WinSize
$global:Action        = $Action
$global:Language      = $Language
$global:LogFilePath   = $LogFilePath


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
        $result.UiXaml     = Join-Path $appData 'ui\wtf.console.main.xml'
        $result.LangDir    = Join-Path $appData 'lang'
        $result.ConfigJson = Join-Path $appData 'wtf.config.json'
        $result.LogDir     = Join-Path $appData 'logs'
        $result.ModulesDir = Join-Path $appData 'Lib'
    }
    else {
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
if ($LogFilePath) {
    $LoggingEnabled = $true
}
elseif ($AppMode -eq 'framework' -and $Config -and $Config.PSObject.Properties.Name -contains 'console') {
    $LoggingEnabled = [bool]::Parse([string]$Config.console.logging)
}

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

if (-not $LogFilePath -and $AppMode -eq 'framework' -and $LoggingEnabled) {
    try {
        if (-not (Test-Path -LiteralPath $Paths.LogDir)) {
            New-Item -ItemType Directory -Path $Paths.LogDir -Force | Out-Null
        }
        $stamp = Get-Date -Format 'yyyyMMdd-HHmm'
        $logNamePattern = if ($Config -and $Config.console.defaultlog) { $Config.console.defaultlog } else { '[DATETIME].wtf.console.log' }
        if ($Action -and $Config -and $Config.console.logfile -and $Config.console.logfile.PSObject.Properties.Name -contains $Action) {
            $logNamePattern = $Config.console.logfile.$Action
        }
        $logFileName = $logNamePattern -replace '\[DATETIME\]', $stamp
        $LogFilePath = Join-Path $Paths.LogDir $logFileName
    }
    catch {
        Write-Warning (Get-WtfString -Path 'messages.logfileInitFailed' -FormatArgs @($_.Exception.Message))
    }
}

if ($LogFilePath) {
    try {
        $logDir = Split-Path -Parent $LogFilePath
        if ($logDir -and -not (Test-Path -LiteralPath $logDir)) {
            New-Item -ItemType Directory -Path $logDir -Force | Out-Null
        }
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

function global:Write-WtfLog {
    param([string]$Message, [string]$Level = 'Info')
    if (-not $global:LogFilePath) { return }
    try {
        if (Get-Command -Name 'Write-VpdlxLog' -ErrorAction SilentlyContinue) {
            Write-VpdlxLog -Path $global:LogFilePath -Message $Message -Level $Level
        }
        else {
            Add-Content -LiteralPath $global:LogFilePath -Value "[$(Get-Date -Format 'u')] [$Level] $Message"
        }
    }
    catch { }
}

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
$global:Window = $Window   # ← Make it global available for the isolated scopes

$global:TitleBarPanel   = $Window.FindName('TitleBarPanel')
$global:TitleBarText    = $Window.FindName('TitleBarText')
$global:BtnMinimize     = $Window.FindName('BtnMinimize')
$global:BtnMaximize     = $Window.FindName('BtnMaximize')
$global:BtnClose        = $Window.FindName('BtnClose')
$global:TerminalOutput  = $Window.FindName('TerminalOutput')
$global:InputBox        = $Window.FindName('InputBox')
$global:LblPrompt       = $Window.FindName('LblPrompt')
$global:BtnSend         = $Window.FindName('BtnSend')
$global:BtnClear        = $Window.FindName('BtnClear')
$global:StatusText      = $Window.FindName('StatusText')
$global:StatusInfo      = $Window.FindName('StatusInfo')

$Window.Title            = Get-WtfString -Path 'window.title'
$TitleBarText.Text       = Get-WtfString -Path 'window.title'
$LblPrompt.Text          = Get-WtfString -Path 'labels.prompt'
$BtnSend.Content         = Get-WtfString -Path 'buttons.send'
$BtnClear.Content        = Get-WtfString -Path 'buttons.clear'
$BtnMinimize.ToolTip     = Get-WtfString -Path 'buttons.minimizeTooltip'
$BtnMaximize.ToolTip     = Get-WtfString -Path 'buttons.maximizeTooltip'
$BtnClose.ToolTip        = Get-WtfString -Path 'buttons.closeTooltip'
$StatusText.Text         = Get-WtfString -Path 'status.ready'
$global:appVersion = if ($Config -and $Config.appinfo.version) { $Config.appinfo.version } else { 'v1.00.00' }
$StatusInfo.Text         = "WTF.Console $appVersion"

if ($AppMode -eq 'framework') {
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
    $Window.Width  = 800
    $Window.Height = 600
    $Window.ResizeMode = [System.Windows.ResizeMode]::CanResize
}

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

$ProcessDbPath = $null
if ($AppMode -eq 'framework' -and $Paths.FrameworkRoot) {
    $ProcessDbPath = Join-Path $Paths.FrameworkRoot 'Core\db\dbprocess.json'
}
# Make it global available for the isloated scopes
$global:ProcessDbPath = $ProcessDbPath

function global:Test-WtfWatchTriggers {
    param([string]$Line, [string]$ActionCode)
    switch ($ActionCode) {
        'mount' {
            if ($Line -match '(?i)error' -or $Line -match '(?i)failed' -or $Line -match '(?i)fehler') { return 'error' }
            if ($Line -match '(?i)the operation completed successfully' -or $Line -match '(?i)der vorgang wurde erfolgreich beendet') { return 'success' }
            if ($Line -match '(?i)mounting image' -or $Line -match '(?i)abbild wird bereitgestellt') { return 'running' }
            return $null
        }
        default {
            if ($Line -match '(?i)error') { return 'error' }
            if ($Line -match '(?i)^100%|completed successfully') { return 'success' }
            return $null
        }
    }
}

$psi = New-Object System.Diagnostics.ProcessStartInfo
$psi.FileName               = (wtfxGetPSExecutable).data.Path
$psi.Arguments              = "-NoLogo -NoProfile -ExecutionPolicy Bypass -File `"$ScriptPath`""
$psi.RedirectStandardInput  = $true
$psi.RedirectStandardOutput = $true
$psi.RedirectStandardError  = $true
$psi.UseShellExecute        = $false
$psi.CreateNoWindow         = $true
$psi.WorkingDirectory       = Split-Path -Parent $ScriptPath

$Proc = New-Object System.Diagnostics.Process
$Proc.StartInfo = $psi
$Proc.EnableRaisingEvents = $true

function global:Write-WtfProcessState {
    param([string]$State, [int]$ExitCode = -1)
    if (-not $global:ProcessDbPath) { return }
    try {
        $dbDir = Split-Path -Parent $global:ProcessDbPath
        if (-not (Test-Path -LiteralPath $dbDir)) {
            New-Item -ItemType Directory -Path $dbDir -Force | Out-Null
        }
        $entry = [ordered]@{
            action    = $global:Action
            script    = $ScriptPath
            logfile   = $global:LogFilePath
            state     = $State
            exitcode  = $ExitCode
            timestamp = (Get-Date -Format 'u')
        }
        $entry | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $global:ProcessDbPath -Encoding UTF8
    }
    catch {
        Write-WtfLog -Message "Failed to update process database: $($_.Exception.Message)" -Level 'Warn'
    }
}

function global:Append-TerminalLine {
    param([string]$Text)
    $global:Window.Dispatcher.Invoke({
        $global:TerminalOutput.AppendText($Text + "`r`n")
        $global:TerminalOutput.ScrollToEnd()
    })
}

# --- Event-Registration: Register-ObjectEvent instead of add_OutputDataReceived ---
$null = Register-ObjectEvent -InputObject $Proc -EventName 'OutputDataReceived' -Action {
    if ($null -ne $EventArgs.Data) {
        Append-TerminalLine -Text $EventArgs.Data
        Write-WtfLog -Message $EventArgs.Data -Level 'Output'
        if ($global:AppMode -eq 'framework') {
            $trigger = Test-WtfWatchTriggers -Line $EventArgs.Data -ActionCode $global:Action
            if ($trigger) { Write-WtfProcessState -State $trigger }
        }
    }
}

$null = Register-ObjectEvent -InputObject $Proc -EventName 'ErrorDataReceived' -Action {
    if ($null -ne $EventArgs.Data) {
        Append-TerminalLine -Text "[ERROR] $($EventArgs.Data)"
        Write-WtfLog -Message $EventArgs.Data -Level 'Error'
        if ($global:AppMode -eq 'framework') {
            Write-WtfProcessState -State 'error'
        }
    }
}

$null = Register-ObjectEvent -InputObject $Proc -EventName 'Exited' -Action {
    $exitCode = $Sender.ExitCode
    $global:Window.Dispatcher.Invoke({
        $msgKey = if ($exitCode -eq 0) { 'status.finishedOk' } else { 'status.finishedFail' }
        $global:StatusText.Text = Get-WtfString -Path $msgKey -FormatArgs @($exitCode)
        $global:InputBox.IsEnabled = $false
        $global:BtnSend.IsEnabled  = $false
    })
    Write-WtfLog -Message "Process exited with code $exitCode." -Level 'Info'
    if ($global:AppMode -eq 'framework') {
        Write-WtfProcessState -State 'finished' -ExitCode $exitCode
    }
}

try {
    $StatusText.Text = Get-WtfString -Path 'status.starting'
    $Proc.Start() | Out-Null
    $Proc.BeginOutputReadLine()
    $Proc.BeginErrorReadLine()
    $StatusText.Text = Get-WtfString -Path 'status.running' -FormatArgs @($Proc.Id)
    Write-WtfLog -Message (Get-WtfString -Path 'console.processStarted' -FormatArgs @($Proc.Id, $ScriptPath)) -Level 'Info'
    if ($LogFilePath) {
        Write-WtfLog -Message (Get-WtfString -Path 'console.logFileInUse' -FormatArgs @($LogFilePath)) -Level 'Info'
    }
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

$BtnClear.Add_Click({ $TerminalOutput.Clear() })
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

[void]$Window.ShowDialog()
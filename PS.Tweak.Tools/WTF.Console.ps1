<#
.SYNOPSIS
     WTF.Console.ps1  (WTF = WinTwin.Fusion)
     Part of PS.Tweak.Tools within the WinTwin Fusion Framework

.DESCRIPTION
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

.PARAMETER ScriptPath (Mandatory)
    Full path to the PowerShell script that should be executed inside the
    redirected console process. Required in BOTH operating modes. The file's
    existence is validated before the process is started.

.NOTES
    Creation Date: 24.03.2026 
    Last Update:   29.08.2026
    Version:       1.00.10
    Author:        Praetoriani (a.k.a. M.Sczepanski)
    Website:       https://github.com/WinTwin-Fusion/PS.Tweak.Tools

    REQUIREMENTS & DEPENDENCIES:
    - PowerShell 5.1 or higher
    - .NET Framework 4.7.2 or higher (for Windows PowerShell)
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
    [ValidatePattern('^\xd{2,5}x\d{2,5}$')]
    [string]$WinSize = "640x480",

    [Parameter(Mandatory = $false)]
    [string]$Action = "unknown",

    [Parameter(Mandatory = $false)]
    [string]$Language = "unknown",

    [Parameter(Mandatory = $false)]
    [string]$LogFilePath = "unknown"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

#--------------------------------------------------------------------------------
# Catch the Params and make them global available for the isolated scopes
# $global:framework   ->  Stores the content of config.json
# $global:jobaction   ->  Stores the content of jobaction.json
# $global:psttconfig  ->  Stores the content of pstt.config.json
# $global:wtfconsole  ->  Stores the content of wtf.console.json
#--------------------------------------------------------------------------------
$global:ScriptPath    = $ScriptPath
$global:AppMode       = $AppMode.ToString().ToLower()
$global:WinSize       = $WinSize
$global:Action        = $Action.ToString().ToLower()
$global:Language      = $Language.ToString().ToLower()
$global:LogFilePath   = $LogFilePath

#--------------------------------------------------------------------------------
# Load additional Libraries (Required to build the UI)
#--------------------------------------------------------------------------------
try {    
    Add-Type -AssemblyName PresentationFramework -ErrorAction Stop
    Add-Type -AssemblyName PresentationCore -ErrorAction Stop
    Add-Type -AssemblyName WindowsBase -ErrorAction Stop
    Add-Type -AssemblyName System.Xml -ErrorAction Stop
    Add-Type -AssemblyName System.Windows.Forms -ErrorAction Stop
}
catch {
    [System.Windows.MessageBox]::Show(
        "Required assemblies could not be loaded!`n$($_.Exception.Message)",
        "Runtime-Error!",
        [System.Windows.MessageBoxButton]::OK,
        [System.Windows.MessageBoxImage]::Error
    ) | Out-Null
    exit 1
}

#--------------------------------------------------------------------------------
# Basic Config (only needed in Framework-Mode)
#--------------------------------------------------------------------------------
$global:config = [pscustomobject]@{
    framework  = "..\core\config.json"
    pstttools  = Join-Path $PSScriptRoot "pstt.config.json"
    wtfconsole = Join-Path $PSScriptRoot "wtf.console.json"
    homepath   = $null
    jobaction  = $null
    processdb  = $null
    workflows  = $null
    app = [pscustomobject]@{
        xmlui      = $null
        langpack   = $null
        logfile    = $null
    }
}
$script:apperror = [pscustomobject]@{
    title = "WTF.Console (PS.Tweak.Tools)"
}
#--------------------------------------------------------------------------------
# Internal Helper-Function to display Error-Messages
# We have to do this, because we cannot use wtfxSystemMessageBox
# untill the Framework libraries have been loaded successfully.
#--------------------------------------------------------------------------------
function Show-ErrorMsg {
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$message
    )
    [System.Windows.MessageBox]::Show(
        "$($message)",
        "$($script:apperror.title)",
        [System.Windows.MessageBoxButton]::OK,
        [System.Windows.MessageBoxImage]::Error
    ) | Out-Null
}

#--------------------------------------------------------------------------------
# Make sure that we have a Script to run
#--------------------------------------------------------------------------------
if (-not (Test-Path -LiteralPath $global:ScriptPath -PathType Leaf)) {
    Show-ErrorMsg -message "The specified script file could not be found:`n$global:ScriptPath"
    exit 1
}

#--------------------------------------------------------------------------------
# Load pstt.config.json and wtf.console.json
# -> Can always be loaded cause they must be in the same directory
#--------------------------------------------------------------------------------
if (-not (Test-Path -LiteralPath "$($global:config.pstttools)")) {
    Show-ErrorMsg -message "Configuration file not found:`n$($global:config.pstttools)"
    exit 1
}
if (-not (Test-Path -LiteralPath "$($global:config.wtfconsole)")) {
    Show-ErrorMsg -message "Configuration file not found:`n$($global:config.wtfconsole)"
    exit 1
}
try { $global:psttconfig = Get-Content -LiteralPath $global:config.pstttools -Raw | ConvertFrom-Json -ErrorAction Stop }
catch {
    Show-ErrorMsg -message "Failed to parse JSON-File:`n$($global:config.pstttools)"
    exit 1
}
try { $global:wtfconsole = Get-Content -LiteralPath $global:config.wtfconsole -Raw | ConvertFrom-Json -ErrorAction Stop }
catch {
    Show-ErrorMsg -message "Failed to parse JSON-File:`n$($global:config.wtfconsole)"
    exit 1
}

#--------------------------------------------------------------------------------
# WTF.Console Pre-Loadong based on which mode we're running on
#--------------------------------------------------------------------------------
# ADDITIONAL INFORMATIONS:
# The key difference between framework mode and standalone mode is that paths
# must be referenced differently. Since both `pstt.config.json` and `wtf.console.json`
# are available in the same location in both modes (in the same directory as
# WTF.Console), this information is always accessible.
# In standalone mode, WTF.Console looks for a `.\wtf.console.data` directory
# within its own path. This directory contains the entire contents of the
# framework's `.\Core` directory. Consequently, in standalone mode, all internal
# paths pointing to libraries, the UI, etc., must be updated to reference
# the `.\wtf.console.data\Core` directory.
#--------------------------------------------------------------------------------

switch ($global:AppMode) {
    # WTF.Console is running in Framework-Mode :)
    "framework"  {
        # 1st Step: Let's try to load the config.json
        if (-not (Test-Path -LiteralPath "$($global:config.framework)")) {
            Show-ErrorMsg -message "Configuration file not found:`n$($global:config.framework)"
            exit 1
        }        
        # Store the content of .\core\config.json in $global:framework
        try { $global:framework = Get-Content -LiteralPath $global:config.framework -Raw | ConvertFrom-Json -ErrorAction Stop }
        catch {
            Show-ErrorMsg -message "Failed parsing JSON-File:`n$($global:config.framework)"
            exit 1
        }
        # Root for WTF.Console is the Root of the framework
        $global:config.homepath = $global:framework.path.root
    }
    # WTF.Console is running in Standalone-Mode :)
    "standalone" {
        # Root for WTF.Console is the Standalone-Data-Folder (in the same directory with WTF.Console)
        $global:config.homepath = Join-Path $PSScriptRoot "$($global:wtfconsole.path.standalone)"

        if (-not (Test-Path -LiteralPath "$($global:config.homepath)")) {
            # The Standalone-Data-Folder is not there
            Show-ErrorMsg -message "Data-Directory for standalone mode not found:`n$($global:config.homepath)"
            exit 1
        }
        # Re-Build the config.json in $global:framework with the new homepath
        # This is ONLY the core from the original config.json. The Reason is
        # quite simple. In Standalone Mode, we do not need other tools like
        # DISM UI Control Center. We just need the '.\Core' and '.\Lib'-Directory
        # from the original WinTwin.Fusion Framework
        $global:framework = [pscustomobject]@{
            appconfig = [pscustomobject]@{
                defaultlanguage  = "en-us"
                allowedlanguages = @("en-us","de-de")
            }
            path = [pscustomobject]@{
                lib    = "\Lib"
                lang   = "\Core\lang"
                logs   = "\Core\logs"
                appui  = "\Core\ui"
                fonts  = "\Core\fonts"
                export = "\Core\exports"
                appdb  = [pscustomobject]@{
                    process = "\Core\db\process.json"
                    actions = "\Core\db\jobaction.json"
                    appflow = "\Core\db\workflow.json"
                }
            }
            lib = [pscustomobject]@{
                OPSreturn     = "\OPSreturn\OPSreturn.psd1"
                PSAppCoreLib  = "\PSAppCoreLib\PSAppCoreLib.psd1"
                VPDLX         = "\VPDLX\VPDLX.psd1"
                WinTwinFXcore = "\WinTwin.FXcore\WinTwin.FXcore.psd1"
                WinTwinXUI    = "\WinTwin.XUI\wintwin.xui.psd1"
            }
        }
    }
    Default {
        Show-ErrorMsg -message "Error in $($script:apperror.title)`n'$($global:AppMode)' is an invalid value!`nOnly 'standalone' or 'framework' allowed!"
        exit 1
    }
}

# BREAKPOINT:
# At this point in the script, we can be certain that—in both modes—we have all the necessary information
# to proceed with loading the required data (such as libraries, language files, UI components, etc.),
# regardless of the operating mode. What we naturally don't know (this also applies to both modes) is
# whether all the files are actually where we need them.
# PLEASE NOTE:
# Once all necessary libraries (such as OPSreturn, WinTwin.FXcore, WinTwin.XUI, etc.) have been loaded,
# the actual pre-initialization phase is complete. From this point on, the actual loading process for
# the WTF.Console begins.

#--------------------------------------------------------------------------------
# Try to load required Libraries from the WinTwin.Fusion Framework
#--------------------------------------------------------------------------------
$script:LibDirectory = Join-Path "$($global:config.homepath)" "$($global:framework.path.lib)"
$global:LibOPSR  = Join-Path "$($script:LibDirectory)" "$($global:framework.lib.OPSreturn)"
$global:LibPSACL = Join-Path "$($script:LibDirectory)" "$($global:framework.lib.PSAppCoreLib)"
$global:LibWTFXC = Join-Path "$($script:LibDirectory)" "$($global:framework.lib.WinTwinFXcore)"
$global:LibWTXUI = Join-Path "$($script:LibDirectory)" "$($global:framework.lib.WinTwinXUI)"

foreach ($requiredModulePath in @($global:LibOPSR, $global:LibPSACL, $global:LibWTFXC)) {
    if (-not (Test-Path -LiteralPath $requiredModulePath -PathType Leaf)) {
        Show-ErrorMsg -message "Error in $($script:apperror.title)`nRequired module manifest not found:`n$($requiredModulePath)"
        exit 1
    }
}

try {
    Import-Module $global:LibOPSR -Force -ErrorAction Stop
    Import-Module $global:LibPSACL -Force -ErrorAction Stop
    Import-Module $global:LibWTFXC -Force -ErrorAction Stop
    Import-Module $global:LibWTXUI -Force -ErrorAction Stop
}
catch {
    Show-ErrorMsg -message "Error in $($script:apperror.title)`nFailed to import required framework modules.`n$($_.Exception.Message)"
    exit 1
}

#--------------------------------------------------------------------------------
# Hide Console Window -> Using Function from WinTwin.FXcore
# -> We can use wtfxSystemMessageBox to display Error-Messages!
#--------------------------------------------------------------------------------
#wtfxSetCMDstate -State Hide

#--------------------------------------------------------------------------------
# Prepare Logging for the script-process (not the wtf.console process)
# PLEASE NOTE:
# At this stage, we prepare both log files (for the script to be executed and for
# WTF.Console itself), but initially write only to the WTF.Console log, since the
# actual script process is not yet running
#--------------------------------------------------------------------------------
# Create a Date/Time-Code
$script:timecode = Get-Date -Format 'yyyyMMdd-HHmmss'
if ( -not (Test-Path -LiteralPath $global:LogFilePath -PathType Leaf) -or $global:LogFilePath -eq "unknown") {
    # Either the LogFilePath-Param wasn't used or the passed file doesn't exsist.
    # In both cases, we need to re-build it from scratch as a fallback so the 
    # process of the script can be logged properly.
    # First we're re-building the correct path to the '.\Core\logs'-directory
    $script:newlogpath = Join-Path "$($global:config.homepath)" "$($global:framework.path.logs)"

    # Next we're going to use the Action-Param to re-build a filename for the logfile
    if ( $global:Action -eq "unknown" ) {
        # Due to the Action-Param wasn't used as well, we re-build it based on the filename of the script
        $global:Action = (Split-Path -Leaf $global:ScriptPath) -replace '\.[^.]+$'
    }
    
    # Re-Build the full filename (including date/time-code)
    $script:newlogfile = "$($script:timecode).$($global:Action).log"

    # Store the whole re-build inside global:LogFilePath
    $global:LogFilePath = Join-Path $script:newlogpath $script:newlogfile
}
# Prepare the Logfile for WTF.Console itself
$script:newlogpath = Join-Path "$($global:config.homepath)" "$($global:framework.path.logs)"
$script:newlogfile = $global:wtfconsole.console.defaultlog -replace '\[DATETIME\]', $script:timecode
$global:config.app.logfile = Join-Path $script:newlogpath $script:newlogfile

# Time to create the WTF.Consle Logfile and write some lines in it. We are
# to use override-Option here, just to be sure its a fresh logfile (should not 
# be necessary at all because of the date-time-code included in the file name)
$null = wtfxWriteLogmsg -Logfile $global:config.app.logfile `
-Message "$($global:wtfconsole.appinfo.name) $($global:wtfconsole.appinfo.version) pre-initialization phase is complete." `
-Flag "INFO" -Override 1

$null = wtfxWriteLogmsg -Logfile $global:config.app.logfile `
-Message "- Configuration successfully loaded for $($global:AppMode) mode`n- All required libraries loaded`n- $($global:ScriptPath) exists." -Flag "INFO"

#--------------------------------------------------------------------------------
# Store a reference on process.json , jobaction.json and workflow.json
# These files are only important if we're running in Framework-Mode because
# Standalone-Mode doesn't use process-recording
#--------------------------------------------------------------------------------
$global:config.jobaction = Join-Path "$($global:config.homepath)" "$($global:framework.path.appdb.actions)"
$global:config.processdb = Join-Path "$($global:config.homepath)" "$($global:framework.path.appdb.process)"
$global:config.workflows = Join-Path "$($global:config.homepath)" "$($global:framework.path.appdb.appflow)"

#--------------------------------------------------------------------------------
# Process-Registration -> Framework Mode only
# PLEASE NOTE:
# In framework mode, WTF.Console is launched via wtfxLaunchConsole function. In
# this context, the function handles registering WTF.Console as an active process
# within process.json. The process initiated by executing the script is only
# indirectly a framework-native process. While it was initialized somewhere
# (by another application within the framework), the execution of the process was
# delegated to WTF.Console (via the script provided). If the script process were
# to attempt to register itself in process.json as a framework-native process,
# WTF.Console would be unable to successfully execute any scripts, as WTF.Console
# itself is already registered as the running process. Consequently, the script
# process can only run as an independent process at the WTF.Console level rather
# than the framework level. Although WTF.Console does register the script process
# in process.json, it does so in a different location.
#--------------------------------------------------------------------------------
<# FOLLOWING CODE IS NOT NEEDED, BECAUSE WTF.CONSLE IS REGISTERED THROUGH wtfxLaunchConsole
if ( $global:AppMode -eq "framework" ) {
    $processCheck = wtfxCheckProcess -FrameworkRoot $wintwin.root
    if ($processCheck.code -ne 0) {
        $null = wtfxSystemMessageBox -smbTitle "WTF.Consle (PS.Tweak.Tools)" `
        -smbText "Could not verify the framework process lock.`n$($processCheck.msg)" `
        -smbIcon Error -smbButtons OK
        exit 1
    }
    # Running Process detected
    if ($processCheck.data.IsRunning) {
        $null = wtfxSystemMessageBox -smbTitle 'WTF.Consle (PS.Tweak.Tools)' `
        -smbText "Another framework process is currently running:`n$($processCheck.data.Running.'proc-name')`n`nPlease wait until it has finished." `
        -smbIcon Warning -smbButtons OK
        exit 0
    }

    $selfRegister = wtfxRegisterProcess -FrameworkRoot $global:config.homepath `
                                        -ProcName "$($global:psttconfig.apptool.wtfc.appname)" `
                                        -ProcPath $PSCommandPath `
                                        -ActionId "$($global:psttconfig.apptool.wtfc."action-id")" `
                                        -ProcessId $PID
    if ($selfRegister.code -ne 0) {
        $null = wtfxSystemMessageBox -smbTitle "WTF.Consle (PS.Tweak.Tools)" `
        -smbText "Could not register as the active framework process.`n$($selfRegister.msg)"
        -smbIcon Error -smbButtons OK
        exit 1
    }
}
#>

#--------------------------------------------------------------------------------
# Load the Language Package for WTF.Console
#--------------------------------------------------------------------------------
$script:validLanguages = $global:framework.appconfig.allowedlanguages
if ($global:Language -notin $script:validLanguages) {
    $global:Language = "$($global:framework.appconfig.defaultlanguage)"
    $global:Language = $global:Language.ToString().ToLower()
}
switch ($global:Language) {
    'en-us' { $global:config.app.langpack  = Join-Path "$($global:config.homepath)" "$($global:psttconfig.apptool.wtfc.langfile."en-us")" }
    'de-de' { $global:config.app.langpack  = Join-Path "$($global:config.homepath)" "$($global:psttconfig.apptool.wtfc.langfile."de-de")" }
    default { $global:config.app.langpack  = Join-Path "$($global:config.homepath)" "$($global:psttconfig.apptool.wtfc.langfile."en-us")" }
}
$script:result = wtfxLoadJSON -Path $global:config.app.langpack
if ($script:result.code -ne 0) {
    $null = wtfxSystemMessageBox -smbTitle "WTF.Consle (PS.Tweak.Tools)" `
    -smbText "Faild loading language package:`n$($global:config.app.langpack)`n$($script:result.message)"
    -smbIcon Error -smbButtons OK
    exit 1
}
$global:apptxt = $script:result.data

#--------------------------------------------------------------------------------
# Load the WTF.Console UI from the XML-File
#--------------------------------------------------------------------------------
$global:config.app.xmlui = Join-Path "$($global:config.homepath)" "$($global:psttconfig.apptool.wtfc.xmlui)"
$script:LoadXML = xuiLoadWindow -XMLfile $global:config.app.xmlui
if ($script:LoadXML.code -ne 0) {
    $null = wtfxSystemMessageBox -smbTitle "DISM UI Control Center (wim.mounter)" `
    -smbText "Faild loading User Interface:`n$($global:config.app.xmlui)`n$($script:LoadXML.message)"
    -smbIcon Error -smbButtons OK
    exit 1
}
$global:Window = $script:LoadXML.data.Window

#--------------------------------------------------------------------------------
# Get a reference on the UI-Elements insid the XML-Code
#--------------------------------------------------------------------------------
$global:TitleBarPanel   = $global:Window.FindName('TitleBarPanel')
$global:TitleBarText    = $global:Window.FindName('TitleBarText')
$global:BtnMinimize     = $global:Window.FindName('BtnMinimize')
$global:BtnMaximize     = $global:Window.FindName('BtnMaximize')
$global:BtnClose        = $global:Window.FindName('BtnClose')
$global:TerminalOutput  = $global:Window.FindName('TerminalOutput')
$global:InputBox        = $global:Window.FindName('InputBox')
$global:LblPrompt       = $global:Window.FindName('LblPrompt')
$global:BtnSend         = $global:Window.FindName('BtnSend')
$global:BtnClear        = $global:Window.FindName('BtnClear')
$global:StatusText      = $global:Window.FindName('StatusText')
$global:StatusInfo      = $global:Window.FindName('StatusInfo')

#--------------------------------------------------------------------------------
# Applying loaded language file to the interface
#--------------------------------------------------------------------------------
$global:Window.Title            = $global:apptxt.window.title
$global:TitleBarText.Text       = $global:apptxt.window.title
$global:LblPrompt.Text          = $global:apptxt.labels.prompt
$global:BtnSend.Content         = $global:apptxt.buttons.send
$global:BtnClear.Content        = $global:apptxt.buttons.clear
$global:BtnMinimize.ToolTip     = $global:apptxt.buttons.minimizeTooltip
$global:BtnMaximize.ToolTip     = $global:apptxt.buttons.maximizeTooltip
$global:BtnClose.ToolTip        = $global:apptxt.buttons.closeTooltip
$global:StatusText.Text         = $global:apptxt.status.ready
$global:StatusInfo.Text         = "$($global:wtfconsole.appinfo.name) $($global:wtfconsole.appinfo.version)"

#--------------------------------------------------------------------------------
# Window-Configuration
#--------------------------------------------------------------------------------
if ($global:AppMode -eq 'framework') {
    $global:BtnMaximize.Visibility = [System.Windows.Visibility]::Collapsed
    $global:Window.ResizeMode      = [System.Windows.ResizeMode]::CanMinimize
} else {
    $global:Window.ResizeMode = [System.Windows.ResizeMode]::CanResize
}
if ($global:WinSize -and $global:WinSize -match '^\d+x\d+$') {
    $script:parts = $global:WinSize.Split('x')
    $global:Window.Width  = [double]$script:parts[0]
    $global:Window.Height = [double]$script:parts[1]
}
else {
    if($global:wtfconsole.appconfig.defaultwinsize -match '^\d+x\d+$') {
        $script:parts = $global:wtfconsole.appconfig.defaultwinsize.Split('x')
        $global:Window.Width  = [double]$script:parts[0]
        $global:Window.Height = [double]$script:parts[1]
    }
    else {
        $global:Window.Width  = 800
        $global:Window.Height = 600
    }
}

# Action-Functions for the Title-Bar and its Buttons
$global:TitleBarPanel.Add_MouseLeftButtonDown({
    param($senderObj, $e)
    if ($e.ClickCount -eq 2 -and $global:AppMode -eq 'standalone') {
        if ($global:Window.WindowState -eq [System.Windows.WindowState]::Maximized) {
            $global:Window.WindowState = [System.Windows.WindowState]::Normal
        }
        else {
            $global:Window.WindowState = [System.Windows.WindowState]::Maximized
        }
    }
    else {
        $global:Window.DragMove()
    }
})

$global:BtnMinimize.Add_Click({ $global:Window.WindowState = [System.Windows.WindowState]::Minimized })
$global:BtnMaximize.Add_Click({
    if ($global:Window.WindowState -eq [System.Windows.WindowState]::Maximized) {
        $global:Window.WindowState = [System.Windows.WindowState]::Normal
    }
    else {
        $global:Window.WindowState = [System.Windows.WindowState]::Maximized
    }
})

#--------------------------------------------------------------------------------
# Hidden Console with I/O-Rediretion
# Following code defines a console process with a hidden console window. This
# hidden window supports I/O-Redirection so we can take over with WTC.Console
#--------------------------------------------------------------------------------
$global:psi = New-Object System.Diagnostics.ProcessStartInfo
$global:psi.FileName               = (wtfxGetPSExecutable).data.Path
$global:psi.Arguments              = "-NoLogo -NoProfile -ExecutionPolicy Bypass -File `"$global:ScriptPath`""
$global:psi.RedirectStandardInput  = $true
$global:psi.RedirectStandardOutput = $true
$global:psi.RedirectStandardError  = $true
$global:psi.UseShellExecute        = $false
$global:psi.CreateNoWindow         = $true
$global:psi.WorkingDirectory       = Split-Path -Parent $global:ScriptPath
# RCP = Registered Console Process
$global:RCP = New-Object System.Diagnostics.Process
$global:RCP.StartInfo = $global:psi
$global:RCP.EnableRaisingEvents = $true

<#
The RegisterConsoleProcess function manages the process of the script being executed by WTF.Console.
Ideally, one would first check process.json to see whether a script is currently being executed by
WTF.Console. However, since WTF.Console runs as a framework process - and can therefore only be
executed a single time - there is no risk of WTF.Console executing a script in two parallel processes.
And in standalone mode is also no need because we do not track processes in that mode.
#>
function global:RegisterConsoleProcess {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$jobstate,
        
        [Parameter(Mandatory = $false)]
        [int]$processid = 0,
        
        [Parameter(Mandatory = $false)]
        [int]$exitcode = -1,
        
        [Parameter(Mandatory = $false)]
        [switch]$jobstart,
        
        [Parameter(Mandatory = $false)]
        [switch]$jobupdate,
        
        [Parameter(Mandatory = $false)]
        [switch]$jobended
    )

    $actionmode = ""

    # Get the current values from the process.json
    $script:result = wtfxLoadJSON -Path $global:config.processdb
    if ($script:result.code -eq 0) { $processJSON = $script:result.data }

    # Create an object that stores all the current and stored informations
    $processdata = [pscustomobject]@{
        processname = "$(Split-Path -Leaf $global:ScriptPath)"
        processpath = "$(Split-Path -Parent $global:ScriptPath)"
        actionid    = "$($global:Action)"
        processid   = [int]$processJSON.console.processid
        script      = "$($global:ScriptPath)"
        logfile     = "$($global:LogFilePath)"
        jobstart    = "$($processJSON.console."job-start")"
        jobstate    = "$($processJSON.console."job-state")"
        jobended    = "$($processJSON.console."job-ended")"
        exitcode    = [int]$processJSON.console.exitcode
    }

    # Register that the script-process has started
    if ($jobstart.IsPresent) {
        $actionmode = "register"
        $processdata.jobstart  = "$(Get-Date -Format 'dd.MM.yyyy ; HH:mm:ss')"
        $processdata.processid = "$($processid)"
        $processdata.jobstate  = "$($jobstate)"
    }
    
    # Register an update to the script-process
    if ($jobupdate.IsPresent) {
        $actionmode = "update"
        $processdata.jobstate = "$($jobstate)"
    }
    
    # Register that the script-process has ended
    if ($jobended.IsPresent) {
        $actionmode = "unregister"
        $processdata.jobended = "$(Get-Date -Format 'dd.MM.yyyy ; HH:mm:ss')"
        $processdata.jobstate = "$($jobstate)"
        $processdata.exitcode = [int]$exitcode
    }

    # Update the JSON-Entries and write the content back to process.json
    $processJSON.console."proc-name" = $processdata.processname
    $processJSON.console."proc-path" = $processdata.processpath
    $processJSON.console."action-id" = $processdata.actionid
    $processJSON.console.processid   = $processdata.processid
    $processJSON.console.script      = $processdata.script
    $processJSON.console.logfile     = $processdata.logfile
    $processJSON.console."job-start" = $processdata.jobstart
    $processJSON.console."job-state" = $processdata.jobstate
    $processJSON.console."job-ended" = $processdata.jobended
    $processJSON.console.exitcode    = $processdata.exitcode
    
    $writeResult = wtfxWriteJSON -Path $global:config.processdb -Value $processJSON
    if ($writeResult.code -ne 0) {
        #return (OPSreturn -Code -1 -Message "Process was cleared in memory but could not be persisted to process.json: $($writeResult.msg)" -Exception $writeResult.exception)
        # Something went wront -> write it down in the WTF.Console log!
        $null = wtfxWriteLogmsg -Logfile $global:config.app.logfile `
        -Message "An error occured while trying to $($actionmode) the script process!`n$($writeResult.msg)" -Flag "ERROR"
    }
    else {
        # looks like we could update the process.json
        switch ($actionmode) {
            "register" {
                $null = wtfxWriteLogmsg -Logfile $global:LogFilePath `
                -Message "$($processdata.processname) was started by WTF.Console." -Flag "INFO"
                $null = wtfxWriteLogmsg -Logfile $global:config.app.logfile `
                -Message "The process for $($processdata.processname) was successfully registered with state '$($processdata.jobstate)' in the process database." -Flag "INFO"
            }
            "update" {
                $null = wtfxWriteLogmsg -Logfile $global:LogFilePath `
                -Message "Current state of $($processdata.processname) was updated to '$($processdata.jobstate)'." -Flag "INFO"
                $null = wtfxWriteLogmsg -Logfile $global:config.app.logfile `
                -Message "The process for $($processdata.processname) was successfully updated to '$($processdata.jobstate)' in the process database." -Flag "INFO"
            }
            "unregister" {
                $null = wtfxWriteLogmsg -Logfile $global:LogFilePath `
                -Message "Current state of $($processdata.processname) was updated to '$($processdata.jobstate)'." -Flag "INFO"
                $null = wtfxWriteLogmsg -Logfile $global:config.app.logfile `
                -Message "The process for $($processdata.processname) was successfully updated to '$($processdata.jobstate)' in the process database." -Flag "INFO"
                $null = wtfxWriteLogmsg -Logfile $global:config.app.logfile `
                -Message "$($processdata.processname) was unregistered from the process database." -Flag "INFO"
            }
        }
    }
}

# This is a simple Helper-Function to redirect the output to our console window
function global:AddTerminalLine {
    param([string]$Text)
    $global:Window.Dispatcher.Invoke({
        $global:TerminalOutput.AppendText($Text + "`r`n")
        $global:TerminalOutput.ScrollToEnd()
    })
}

# These are helper functions to handle the input to the WTF.Console
$global:SendCommand = {
    if (-not $global:RCP.HasExited -and $global:InputBox.Text.Length -gt 0) {
        $script:cmdText = $global:InputBox.Text
        $global:InputBox.Clear()
        # Append the user input to the console output
        $script:textReplace = wtfxFillPlaceholder -text $global:apptxt.console.userInputEcho -txtval @("$($script:cmdText)")
        if ($script:textReplace -ge 0) { $script:newStatus = $script:textReplace.data }
        global:Append-TerminalLine -Text $script:newStatus
        # UI-Update for WTF.Console
        $global:Window.Dispatcher.Invoke({
            # Update the Status Text of WTF.Console
            $global:StatusText.Text = "$($global:apptxt.status.sending)"
        })
        try {
            $global:RCP.StandardInput.WriteLine($script:cmdText)
            $null = wtfxWriteLogmsg -Logfile $global:config.app.logfile `
            -Message "User made following input:`n$($script:cmdText)" -Flag "INFO"
        }
        catch {
            $null = wtfxWriteLogmsg -Logfile $global:config.app.logfile `
            -Message "WTF.Console failed to write to StandardInput:`n$($_.Exception.Message)" -Flag "WARN"
        }
        # UI-Update for WTF.Console
        $script:textReplace = wtfxFillPlaceholder -text $global:apptxt.status.scriptrunning -txtval @("[$($script:timecode)]","$(Split-Path -Leaf $global:ScriptPath)")
        if ($script:textReplace -ge 0) { $script:newStatus = $script:textReplace.data }
        $global:Window.Dispatcher.Invoke({
            # Update the Status Text of WTF.Console
            $global:StatusText.Text = "$($script:newStatus)"
        })
    }
}
$global:BtnSend.Add_Click($global:SendCommand)
$global:InputBox.Add_KeyDown({
    param($senderObj, $e)
    if ($e.Key -eq [System.Windows.Input.Key]::Enter) {
        & $global:SendCommand
    }
})

$global:BtnClear.Add_Click({ $global:TerminalOutput.Clear() })
$global:BtnClose.Add_Click({ $global:Window.Close() })

#--------------------------------------------------------------------------------
# Event-Registration: Register-ObjectEvent instead of add_OutputDataReceived [!!]
# PLEASE NOTE:
# The following code block defines specific events (such as 'OutputDataReceived'
# or 'ErrorDataReceived') and specifies what should happen when these events
# occur. The actual process for the script has not yet been started.
#--------------------------------------------------------------------------------
$global:RCPeventData = Register-ObjectEvent -InputObject $Proc -EventName 'OutputDataReceived' -Action {
    if ($null -ne $EventArgs.Data) {
        # Get the current time
        $script:timecode = "$(Get-Date -Format 'HH:mm:ss')"
        # Output received -> Redirect it to WTF.Console
        global:AddTerminalLine -Text $EventArgs.Data
        # UI-Update for WTF.Console
        $script:textReplace = wtfxFillPlaceholder -text $global:apptxt.status.scriptrunning -txtval @("[$($script:timecode)]","$(Split-Path -Leaf $global:ScriptPath)")
        if ($script:textReplace -ge 0) { $script:newStatus = $script:textReplace.data }
        $global:Window.Dispatcher.Invoke({
            # Update the Status Text of WTF.Console
            $global:StatusText.Text = "$($script:newStatus)"
        })
        # Write something to the logfile
        $null = wtfxWriteLogmsg -Logfile $global:config.app.logfile `
        -Message "Output received:`n$($EventArgs.Data)" -Flag "INFO"
        # Framework-Mode only!
        if ($global:AppMode -eq 'framework') {
            global:RegisterConsoleProcess -jobstate "running" -jobupdate
            # The following code block would examine the output of the currently running job action
            # for predefined keywords. This method is intended, for example, to determine when a
            # specific process has finished. This section is currently not used/implemented
            #$trigger = Test-WtfWatchTriggers -Line $EventArgs.Data -ActionCode $global:Action
            #if ($trigger) { Write-WtfProcessState -State $trigger }
        }
    }
}

$global:RCPeventFail = Register-ObjectEvent -InputObject $Proc -EventName 'ErrorDataReceived' -Action {
    if ($null -ne $EventArgs.Data) {
        # Get the current time
        $script:timecode = "$(Get-Date -Format 'HH:mm:ss')"
        # Error received -> Redirect it to WTF.Console
        global:AddTerminalLine -Text "[$($script:timecode)]  RUNTIME ERROR!"
        global:AddTerminalLine -Text "$($EventArgs.Data)"
        # UI-Update for WTF.Console
        $script:textReplace = wtfxFillPlaceholder -text $global:apptxt.status.scripterror -txtval @("[$($script:timecode)]","$(Split-Path -Leaf $global:ScriptPath)")
        if ($script:textReplace -ge 0) { $script:newStatus = $script:textReplace.data }
        $global:Window.Dispatcher.Invoke({
            # Update the Status Text of WTF.Console
            $global:StatusText.Text = "$($script:newStatus)"
        })
        # Write something to the logfile
        $null = wtfxWriteLogmsg -Logfile $global:config.app.logfile `
        -Message "Script '$(Split-Path -Leaf $global:ScriptPath)' caused an error during runtime:`nDetails: $($EventArgs.Data)" -Flag "ERROR"
        # Framework-Mode only!
        if ($global:AppMode -eq 'framework') {
            global:RegisterConsoleProcess -jobstate "error" -jobupdate
        }
    }
}

$global:RCPeventExit = Register-ObjectEvent -InputObject $Proc -EventName 'Exited' -Action {
    # Get the current exit code
    $script:exitCode = $Sender.ExitCode
    # Get the current time
    $script:timecode = "$(Get-Date -Format 'HH:mm:ss')"
    # UI-Update for WTF.Console (generate the status-message based on the exit code)
    if ( $script:exitCode -eq 0 ) {
        $script:textReplace = wtfxFillPlaceholder -text $global:apptxt.status.finishedOkay `
        -txtval @("[$($script:timecode)]","$(Split-Path -Leaf $global:ScriptPath)","$($script:exitCode)")
    } else {
        $script:textReplace = wtfxFillPlaceholder -text $global:apptxt.status.finishedFail `
        -txtval @("[$($script:timecode)]","$(Split-Path -Leaf $global:ScriptPath)","$($script:exitCode)")
    }
    if ($script:textReplace -ge 0) { $script:newStatus = $script:textReplace.data }
    # UI-Update for WTF.Console (set the status-message)
    $global:Window.Dispatcher.Invoke({
        # Update the Status Text of WTF.Console
        $global:StatusText.Text = "$($script:newStatus)"
        # Disable Input
        $global:InputBox.IsEnabled = $false
        $global:BtnSend.IsEnabled  = $false
    })
    # Write something to the logfile
    $null = wtfxWriteLogmsg -Logfile $global:config.app.logfile `
    -Message "WTF.Consle received an exit-signal from the script.`nScript '$(Split-Path -Leaf $global:ScriptPath)' has finished with exitcode: $($script:exitCode)" -Flag "INFO"
    # Framework-Mode only!
    if ($global:AppMode -eq 'framework') {
        global:RegisterConsoleProcess -jobstate "finished" -exitcode $script:exitCode -jobended
    }
}

#--------------------------------------------------------------------------------
# Run the given script in WTF.Console
#--------------------------------------------------------------------------------
# Get the current time
$script:timecode = "$(Get-Date -Format 'HH:mm:ss')"
try {
    # UI-Update for WTF.Console (set the status-message)
    $global:Window.Dispatcher.Invoke({
        # Update the Status Text of WTF.Console
        $global:StatusText.Text = $global:apptxt.status.starting
    })
    # Try launching the script process
    $script:LaunchWTFCprocess = $global:RCP.Start()
    if ($script:LaunchWTFCprocess) {
        # Process could be startet
        $global:RCP.BeginOutputReadLine()
        $global:RCP.BeginErrorReadLine()
        # UI-Update for WTF.Console (set the status-message)
        $script:textReplace = wtfxFillPlaceholder -text $global:apptxt.status.scriptstarted `
        -txtval @("[$($script:timecode)]","$(Split-Path -Leaf $global:ScriptPath)","$($global:RCP.Id)")
        if ($script:textReplace -ge 0) { $script:newStatus = $script:textReplace.data }
        $global:Window.Dispatcher.Invoke({
            # Update the Status Text of WTF.Console
            $global:StatusText.Text = $script:newStatus
        })
        # Write something to the logfile
        $null = wtfxWriteLogmsg -Logfile $global:config.app.logfile `
        -Message "WTF.Consle successfully started script '$(Split-Path -Leaf $global:ScriptPath)' in new (hidden) process (pid: $($global:RCP.Id))" -Flag "INFO"
        # Framework-Mode only!
        if ($global:AppMode -eq 'framework') {
            global:RegisterConsoleProcess -jobstate "started" -processid $global:RCP.Id -jobstart
        }
    } else {
        # Something went wrong -> Process did not start
        # UI-Update for WTF.Console (set the status-message)
        $script:textReplace = wtfxFillPlaceholder -text $global:apptxt.status.startfailed `
        -txtval @("[$($script:timecode)]","$(Split-Path -Leaf $global:ScriptPath)")
        if ($script:textReplace -ge 0) { $script:newStatus = $script:textReplace.data }
        $global:Window.Dispatcher.Invoke({
            # Update the Status Text of WTF.Console
            $global:StatusText.Text = $script:newStatus
        })
        # Write something to the logfile
        $null = wtfxWriteLogmsg -Logfile $global:config.app.logfile `
        -Message "WTF.Console failed starting script '$(Split-Path -Leaf $global:ScriptPath)' in new process.`nExitcode: $($global:RCP.ExitCode)`nError: $($global:RCP.StandardError)" -Flag "ERROR"
        # Framework-Mode only!
        if ($global:AppMode -eq 'framework') {
            global:RegisterConsoleProcess -jobstate "crashed" -exitcode $global:RCP.ExitCode -jobended
        }
    }
}
catch {
    # UI-Update for WTF.Console (set the status-message)
    $script:textReplace = wtfxFillPlaceholder -text $global:apptxt.status.startfailed `
    -txtval @("[$($script:timecode)]","$(Split-Path -Leaf $global:ScriptPath)")
    if ($script:textReplace -ge 0) { $script:newStatus = $script:textReplace.data }
    $global:Window.Dispatcher.Invoke({
        # Update the Status Text of WTF.Console
        $global:StatusText.Text = $script:newStatus
    })

    # Write something to the logfile
    $null = wtfxWriteLogmsg -Logfile $global:config.app.logfile `
    -Message "WTF.Console failed starting script '$(Split-Path -Leaf $global:ScriptPath)' in new process.`nExitcode: $($global:RCP.ExitCode)`nError: $($global:RCP.StandardError)`nException: $($_.Exception.Message)" -Flag "ERROR"
    # Framework-Mode only!
    if ($global:AppMode -eq 'framework') {
        global:RegisterConsoleProcess -jobstate "crashed" -exitcode $global:RCP.ExitCode -jobended
    }
    # Create the text for the warning dialog
    $script:textReplace = wtfxFillPlaceholder -text $global:apptxt.messages.scriptstartfailed `
    -txtval @("$(Split-Path -Leaf $global:ScriptPath)")
    if ($script:textReplace -ge 0) { $script:newStatus = $script:textReplace.data }
    # Throw a dialog with the formatted text
    $script:result = wtfxSystemMessageBox -smbTitle "$($script:apperror.title)" `
    -smbText "$($script:newStatus)" `
    -smbIcon Warning -smbButtons OKCancel
    if ($script:result.code -eq 0 -and $script:result.data -eq 'OK') { exit 1 }
}

#--------------------------------------------------------------------------------
# Let's add a final closing function to the window
#--------------------------------------------------------------------------------

$global:Window.Add_Closing({
    param($senderObj, $e)
    # There is still a running process
    if (-not $global:RCP.HasExited) {
        # Show a warning wialog
        $script:result = wtfxSystemMessageBox -smbTitle "$($script:apperror.title)" `
        -smbText "$($global:apptxt.message.confirmCloseRunning)" `
        -smbIcon Warning -smbButtons YesNo
        # User declined exiting
        if ($script:result.code -eq 0 -and $script:result.data -eq 'No') {
            $e.Cancel = $true
            return
        }
        # User still wants to exit
        if ($script:result.code -eq 0 -and $script:result.data -eq 'Yes') {
            # Let's try to terminate the currently running process
            try {
                if (-not $global:RCP.HasExited) { $global:RCP.Kill() }
                # Write a final note to the logfile
                $null = wtfxWriteLogmsg -Logfile $global:config.app.logfile `
                -Message "WTF.Console was terminated by the user. The process (currently running at that time) was killed!" -Flag "INFO"
                $null = wtfxWriteLogmsg -Logfile $global:config.app.logfile `
                -Message "Process StartTime: $($global:RCP.StartTime)" -Flag "DEBUG"
                $null = wtfxWriteLogmsg -Logfile $global:config.app.logfile `
                -Message "Process HasExited: $($global:RCP.HasExited)" -Flag "DEBUG"
                $null = wtfxWriteLogmsg -Logfile $global:config.app.logfile `
                -Message "Process ExitCode: $($global:RCP.ExitCode)" -Flag "DEBUG"
            }
            catch {
                # Write a note to the logfile
                $null = wtfxWriteLogmsg -Logfile $global:config.app.logfile `
                -Message "Failed terminating script process (pid: $($global:RCP.Id)). The process is still running ... " -Flag "WARN"
                $null = wtfxWriteLogmsg -Logfile $global:config.app.logfile `
                -Message "Process Error: $($global:RCP.StandardError)`nExceptional Error: $($_.Exception.Message)" -Flag "DEBUG"
                # Looks like killing the process failed
                $null = wtfxSystemMessageBox -smbTitle "$($script:apperror.title)" `
                -smbText "$($global:apptxt.message.killprocessfailed)" `
                -smbIcon Warning -smbButtons OK
            }
        }
    }
})

#--------------------------------------------------------------------------------
# Launch the UI and show the window
#--------------------------------------------------------------------------------
$global:Window.Topmost = $true
$global:Window.Add_Loaded({
    $global:Window.Activate()
    $global:Window.Focus()
    $global:Window.Topmost = $false
})

$global:Window.ShowDialog() | Out-Null
#--------------------------------------------------------------------------------
# Cleanup Section after WTF.Console has been closed

# Unregister registered object evets
Unregister-Event $global:RCPeventData.Name
Unregister-Event $global:RCPeventFail.Name
Unregister-Event $global:RCPeventExit.Name
# Release the process object
$global:RCP.Dispose()
# Unregister from process.json before final exit
$null = wtfxUnregisterProcess -FrameworkRoot $global:config.homepath -ProcessId $PID
# Show the console again
wtfxSetCMDstate -State Show
# Clean exit of WTF.Console
exit 0


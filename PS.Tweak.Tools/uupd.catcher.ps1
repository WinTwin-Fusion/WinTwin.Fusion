<#
.SYNOPSIS
    UUPD.Catcher - UI Frontend for downloading ZIP-Files from uupdump.net
.DESCRIPTION
    The UUPD.Catcher provides a graphical interface that makes it possible
    to easily create a download-request for uupdump.net and download a ZIP-File
.NOTES
    CREATOR:    Praetoriani (a.k.a M.Sczepanski)
    WEBSITE:    https://github.com/WinTwin-Fusion/PS.Tweak.Tools
    VERSION:    v1.00.00
    CREATED:    03.09.2026
    UPDATED:    03.09.2026

    REQUIREMENTS & DEPENDENCIES:
    - PowerShell 5.1 or higher
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [ValidateSet("en-us","de-de")]
    [string]$Language = "en-us"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

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


# --------------------------------------------------------------------------
# ERROR HANDLING
# Using the script:Add-Error function, the installer collects information
# about errors that occurred during the process.
# --------------------------------------------------------------------------
$Script:errorlist = @()
$Script:errorhead = "UUPD.Catcher"
function script:Add-Error {
    # Small Helper-Function to add an error to script:errorlist
    # Usage: Add-Error "config.json is missing"
    [CmdletBinding()]
    param(
        [string]$errortext
    )
    $Script:errorlist += $errortext
}
function script:Show-RuntimeError {
    # Small Helper-Function to show error dialogs
    # Usage: Show-RuntimeError "Something went wrong."
    # Usage: Show-RuntimeError "Core configuration not found" -exitapp
    [CmdletBinding()]
    param(
        [string]$errortext,
        [switch]$exitapp
    )
    [System.Windows.MessageBox]::Show(
        $errortext,
        "Runtime-Error!",
        [System.Windows.MessageBoxButton]::OK,
        [System.Windows.MessageBoxImage]::Error
    ) | Out-Null
    if ($exitapp.IsPresent) { exit 1 }
    return
}

# --------------------------------------------------------------------------
# Required Vars for UUPD.Catcher to work
# --------------------------------------------------------------------------

$Script:configfile = [PSCustomObject]@{
    framework = "..\core\config.json"
    processdb = "process.json"
    jobaction = "jobaction.json"
}

$Script:app = [PSCustomObject]@{
    name     = $null
    version  = $null
    langfile = $null
    xmlui    = $null
    actionid = $null
    config = [PSCustomObject]@{
        self = "uupd.catcher.json"
        pstt = "pstt.config.json"
    }
    window  = $null
    control = $null
}

$Script:config = [PSCustomObject]@{
    framework = $null
    processdb = $null
    jobaction = $null
}

# --------------------------------------------------------------------------
# Load the config.json from the WinTwin.Fusion Framework
# --------------------------------------------------------------------------
# 1st Step: We're going to check that the file exists
if (-not (Test-Path -LiteralPath "$($Script:configfile.framework)")) {
    script:Show-RuntimeError -errortext "Configuration file not found:`n$($Script:configfile.framework)" -exitapp
}

# 2nd Step: We're trying to load the content from the config.json
try {
    $Script:config.framework = Get-Content -LiteralPath $Script:configfile.framework -Raw | ConvertFrom-Json -ErrorAction Stop
}
catch {
    script:Show-RuntimeError -errortext "Failed parsing configuration file:`n$($Script:configfile.framework)`n$($_.Exception.Message)" -exitapp
}

# 3rd Step: Assign important values from the global config.json
$Script:wintwin = [pscustomobject]@{
    root    = $Script:config.framework.path.root
    lib     = Join-Path "$($Script:config.framework.path.root)" "$($Script:config.framework.path.lib)"
    lang    = Join-Path "$($Script:config.framework.path.root)" "$($Script:config.framework.path.lang)"
    logs    = Join-Path "$($Script:config.framework.path.root)" "$($Script:config.framework.path.logs)"
    xmlui   = Join-Path "$($Script:config.framework.path.root)" "$($Script:config.framework.path.appui)"
    fonts   = Join-Path "$($Script:config.framework.path.root)" "$($Script:config.framework.path.fonts)"
    export  = Join-Path "$($Script:config.framework.path.root)" "$($Script:config.framework.path.export)"
    console = Join-Path "$($Script:config.framework.path.root)" "$($Script:config.framework.path.pstools.console)"
    pstt    = Join-Path "$($Script:config.framework.path.root)" "$($Script:config.framework.path.pstools.root)"
}

# Set the real/full paths to the process.json and jobaction.json
$Script:configfile.processdb = Join-Path "$($Script:wintwin.root)" "$($Script:config.framework.path.appdb.process)"
$Script:configfile.jobaction = Join-Path "$($Script:wintwin.root)" "$($Script:config.framework.path.appdb.actions)"
# Set the real/full paths to the app-internal json files
$Script:app.config.self = Join-Path "$($Script:wintwin.pstt)" "$($Script:app.config.self)"
$Script:app.config.pstt = Join-Path "$($Script:wintwin.pstt)" "$($Script:app.config.pstt)"

#--------------------------------------------------------------------------------
# Try to load required Libraries from the WinTwin.Fusion Framework
#--------------------------------------------------------------------------------
$script:LibOPSR  = Join-Path "$($Script:wintwin.lib)" "$($Script:config.framework.lib.OPSreturn)"
$script:LibPSACL = Join-Path "$($Script:wintwin.lib)" "$($Script:config.framework.lib.PSAppCoreLib)"
$script:LibWTFXC = Join-Path "$($Script:wintwin.lib)" "$($Script:config.framework.lib.WinTwinFXcore)"
$script:LibWTXUI = Join-Path "$($Script:wintwin.lib)" "$($Script:config.framework.lib.WinTwinXUI)"

foreach ($requiredModulePath in @($script:LibOPSR, $script:LibPSACL, $script:LibWTFXC)) {
    if (-not (Test-Path -LiteralPath $requiredModulePath -PathType Leaf)) {
        script:Show-RuntimeError -errortext "Required module manifest not found:`n$($requiredModulePath)" -exitapp
    }
}

try {
    Import-Module $script:LibOPSR -Force -ErrorAction Stop
    Import-Module $script:LibPSACL -Force -ErrorAction Stop
    Import-Module $script:LibWTFXC -Force -ErrorAction Stop
    Import-Module $script:LibWTXUI -Force -ErrorAction Stop
}
catch {
    script:Show-RuntimeError -errortext "Failed to import required framework modules.`n$($_.Exception.Message)" -exitapp
}

#--------------------------------------------------------------------------------
# Hide Console Window -> Using Function from WinTwin.FXcore
# -> We can use wintwincore.SystemMessageBox to display Error-Messages!
#--------------------------------------------------------------------------------
#wintwincore.SetCMDstate -State Hide

#--------------------------------------------------------------------------------
# Load the other JSON-Files
#--------------------------------------------------------------------------------
# Load the jobaction.json
$script:JSONresult = wintwincore.LoadJSON -Path $Script:configfile.jobaction
if ( $script:JSONresult.code -ne 0) { script:Show-RuntimeError -errortext "Failed loading following json file:`n$($Script:configfile.jobaction)`n$($script:JSONresult.msg)" -exitapp }
$Script:config.jobaction = $script:JSONresult.data
# Load the process.json
$script:JSONresult = wintwincore.LoadJSON -Path $Script:configfile.processdb
if ( $script:JSONresult.code -ne 0) { script:Show-RuntimeError -errortext "Failed loading following json file:`n$($Script:configfile.processdb)`n$($script:JSONresult.msg)" -exitapp }
$Script:config.processdb = $script:JSONresult.data
# Load the pstt.config.json
$script:JSONresult = wintwincore.LoadJSON -Path $script:app.config.pstt
if ( $script:JSONresult.code -ne 0) { script:Show-RuntimeError -errortext "Failed loading following json file:`n$($script:app.config.pstt)`n$($script:JSONresult.msg)" -exitapp }
# Store the required values from the pstt.config.json
$script:app.name     = "$($script:JSONresult.data.apptool."uupd-catch".appname)"
$script:app.version  = "$($script:JSONresult.data.appinfo.version)"
$script:app.actionid = "$($script:JSONresult.data.apptool."uupd-catch"."action-id")"
$script:app.xmlui    = Join-Path "$($Script:wintwin.root)" "$($script:JSONresult.data.apptool."uupd-catch".xmlui)"
# Set the correct language file
switch ($Script:config.framework.appconfig.defaultlanguage) {
    'en-us' { $script:app.langfile = Join-Path "$($Script:wintwin.root)" "$($script:JSONresult.data.apptool."uupd-catch".langfile."en-us")" }
    'de-de' { $script:app.langfile = Join-Path "$($Script:wintwin.root)" "$($script:JSONresult.data.apptool."uupd-catch".langfile."de-de")" }
    default { $script:app.langfile = Join-Path "$($Script:wintwin.root)" "$($script:JSONresult.data.apptool."uupd-catch".langfile."en-us")" }
}
# Load the language file and store the results
$script:JSONresult = wintwincore.LoadJSON -Path $script:app.langfile
if ( $script:JSONresult.code -ne 0) { script:Show-RuntimeError -errortext "Failed loading following json file:`n$($script:app.langfile)`n$($script:JSONresult.msg)" -exitapp }
$Script:apptxt = $script:JSONresult.data

#--------------------------------------------------------------------------------
# Load/Create the Window
# In this section, the UI is loaded from the XML file, the window is created,
# and all UI elements are referenced. Everything will be stored in $script:app
#--------------------------------------------------------------------------------
# The -extended switch returns the window object including the referenced controls
$script:LoadXML = xuiLoadWindow -XMLfile $script:app.xmlui -extended
if ( $script:LoadXML.code -ne 0) { script:Show-RuntimeError -errortext "Faild loading User Interface:`n$($script:setupconfig.xmlui)`n$($script:LoadXML.message)" -exitapp }
# Store the window and all controls inside the window
$script:app.window  = $script:LoadXML.data.Window
$script:app.control = $script:LoadXML.data.Controls

#--------------------------------------------------------------------------------
# Applying loaded language file to the interface
#--------------------------------------------------------------------------------
$script:app.control.LblInstruction.Text      = $Script:apptxt.ui.LblInstruction
$script:app.control.LblInfotmation.Text      = $Script:apptxt.ui.LblInfotmation
$script:app.control.LblWinConfig.Text        = $Script:apptxt.ui.LblWinConfig
$script:app.control.LblWinVersion.Text       = $Script:apptxt.ui.LblWinVersion
$script:app.control.RadioWin24H2.Content     = $Script:apptxt.ui.RadioWin24H2
$script:app.control.RadioWin25H2.Content     = $Script:apptxt.ui.RadioWin25H2
$script:app.control.LblEditions.Text         = $Script:apptxt.ui.LblEditions
$script:app.control.RadioHome.Content        = $Script:apptxt.ui.RadioHome
$script:app.control.RadioPro.Content         = $Script:apptxt.ui.RadioPro
$script:app.control.LblArch.Text             = $Script:apptxt.ui.LblArch
$script:app.control.RadioArchAmd64.Content   = $Script:apptxt.ui.RadioArchAmd64
$script:app.control.RadioArchArm64.Content   = $Script:apptxt.ui.RadioArchArm64
$script:app.control.LblLanguage.Text         = $Script:apptxt.ui.LblLanguage
$script:app.control.RadioLangENUS.Content    = $Script:apptxt.ui.RadioLangENUS
$script:app.control.RadioLangDEDE.Content    = $Script:apptxt.ui.RadioLangDEDE
$script:app.control.LblConverter.Text        = $Script:apptxt.ui.LblConverter
$script:app.control.ChkAddUpdates.Content    = $Script:apptxt.ui.ChkAddUpdates
$script:app.control.ChkCleanup.Content       = $Script:apptxt.ui.ChkCleanup
$script:app.control.ChkNetFx35.Content       = $Script:apptxt.ui.ChkNetFx35
$script:app.control.LblDownloadConfig.Text   = $Script:apptxt.ui.LblDownloadConfig
$script:app.control.LblZIPLocation.Text      = $Script:apptxt.ui.LblZIPLocation
#$script:app.control.TxtZIPLocation
$script:app.control.LblFilename.Text         = $Script:apptxt.ui.LblFilename
#$script:app.control.TxtFilename.Text
$script:app.control.ChkCloseWhenDone.Content = $Script:apptxt.ui.ChkCloseWhenDone
$script:app.control.BtnDownload.Content      = $Script:apptxt.ui.BtnDownload
$script:app.control.BtnCancel.Content        = $Script:apptxt.ui.BtnCancel
$script:app.control.BtnExit.Content          = $Script:apptxt.ui.BtnExit
$script:app.control.StatusText.Text          = $Script:apptxt.status.isready
$script:app.control.StatusInfo.Text          = "$($script:app.name) ($($script:app.version))"


if (Test-Path -LiteralPath $global:appicon) {
    try {
        $titleBarLogo.Source = [System.Windows.Media.Imaging.BitmapImage]::new([System.Uri]::new($global:appicon))
    }
    catch {
        Write-Verbose "DISM UI Control Center (wim.mounter):  Could not set title bar logo: $($_.Exception.Message)"
    }
}

#--------------------------------------------------------------------------------
# Internal Functions for UUPD.Catcher
#--------------------------------------------------------------------------------
function script:uiEvent {
    <#
    .SYNOPSIS
        Pumps the WPF dispatcher so that pending UI updates are rendered
        immediately instead of being deferred until the current handler
        returns.

    .DESCRIPTION
        While a synchronous handler (e.g. the BtnInstall click handler) is
        running on the UI thread, WPF queues all visual changes and only
        redraws them once the dispatcher is free again. Calling this
        function in between updates forces the dispatcher to process the
        queued rendering work right away, so the user sees live progress.

    .NOTES
        This is a lightweight "DoEvents" equivalent for WPF. It keeps the
        UI thread busy, so the window cannot be moved/resized while a long
        operation is running. Use it for short checks; for long-running
        work prefer a background thread (e.g. Start-ThreadJob).
    #>
    [CmdletBinding()]
    param()

    $dispatcher = [System.Windows.Threading.Dispatcher]::CurrentDispatcher
    $frame = [System.Windows.Threading.DispatcherFrame]::new($false)
    $callback = [System.Windows.Threading.DispatcherOperationCallback]{
        param($f)
        $f.Continue = $false
        return $null
    }
    $dispatcher.BeginInvoke(
        [System.Windows.Threading.DispatcherPriority]::Background,
        $callback,
        $frame
    ) | Out-Null
    [System.Windows.Threading.Dispatcher]::PushFrame($frame)
    
    Start-Sleep -Milliseconds 500
}

#--------------------------------------------------------------------------------
# UI-Events / Triggers
#--------------------------------------------------------------------------------

# "Minimize Window" was clicked
$script:app.control.BtnMinimize.Add_Click({
    $script:app.window.WindowState = [System.Windows.WindowState]::Minimized
})
# "Close Application" was clicked
$script:app.control.BtnClose.Add_Click({
    $script:app.window.Close()
})

# Adds Drag-n-Drop support (due to we're using a borderless window)
$script:app.control.TitleBarPanel.Add_MouseLeftButtonDown({
    param($senderObj, $eventObj)

    if ($eventObj.ButtonState -eq
        [System.Windows.Input.MouseButtonState]::Pressed) {
        $script:app.window.DragMove()
    }
})
# Download-Button was clicked
$script:app.control.BtnDownload.Add_Click({
    <# STARTS THE DOWNLOAD FROM UUPDUMP.NET #>
})
# Reset-Button was clicked
$script:app.control.BtnReset.Add_Click({
    <# WE NEED TO RESET THE WHOLE FORM #>
})
# Exit was clicked
$script:app.control.BtnExit.Add_Click({
    $script:app.window.Close()
})

#--------------------------------------------------------------------------------
# Launch the UI and show the window
#--------------------------------------------------------------------------------

$script:app.window.Topmost = $true
$script:app.window.Add_Loaded({
    $script:app.window.Activate()
    $script:app.window.Focus()
    $script:app.window.Topmost = $false
})

#$script:logmsg=@("Showing Install Manager Window using 'ShowDialog() | Out-Null'")
#$null = wintwincore.WriteLogmsg -Logfile $script:setupconfig.logfile -Message $script:logmsg -Flag "INFO"

$script:app.window.ShowDialog() | Out-Null
# Cleanup/Exit
#wintwincore.SetCMDstate -State Show
#$script:logmsg=@("WinTwin.Fusion Install Manager Window was closed.","Application will exit now.","Thanks for using WinTwin. Fusion Install Manager :)")
#$null = wintwincore.WriteLogmsg -Logfile $script:setupconfig.logfile -Message $script:logmsg -Flag "INFO"
exit 0

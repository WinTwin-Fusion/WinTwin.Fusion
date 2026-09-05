<#
.SYNOPSIS
    UUPD.Compose - UI Frontend for creating ISO Files from a previous download from uupdump.net
.DESCRIPTION
    The UUPD.Compose provides a graphical interface that helps you creating ISO-Files
    from a ZIP-File that was previously downloaded from uupdump.net
.NOTES
    CREATOR:    Praetoriani (a.k.a M.Sczepanski)
    WEBSITE:    https://github.com/WinTwin-Fusion/PS.Tweak.Tools
    VERSION:    v1.00.01
    CREATED:    05.09.2026
    UPDATED:    05.09.2026

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
    Write-Host "Runtime-Error!" -ForegroundColor DarkRed
    Write-Host "****************" -ForegroundColor DarkRed
    Write-Host "Required assemblies could not be loaded!`n$($_.Exception.Message)" -ForegroundColor DarkRed
    exit 1
}


# --------------------------------------------------------------------------
# ERROR HANDLING
# Using the script:Add-Error function, the installer collects information
# about errors that occurred during the process.
# --------------------------------------------------------------------------
$script:errorlist = @()
$script:errorhead = "UUPD.Compose"
function script:Add-Error {
    # Small Helper-Function to add an error to script:errorlist
    # Usage: Add-Error "config.json is missing"
    [CmdletBinding()]
    param(
        [string]$errortext
    )
    $script:errorlist += $errortext
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
# Required Vars for UUPD.Compose
# --------------------------------------------------------------------------

$script:configfile = [PSCustomObject]@{
    framework = "..\core\config.json"
    processdb = "process.json"
    jobaction = "jobaction.json"
}

$script:config = [PSCustomObject]@{
    framework  = $null
    processdb  = $null
    jobaction  = $null
    psttjson   = $null
}

# --------------------------------------------------------------------------
# Load the config.json from the WinTwin.Fusion Framework
# --------------------------------------------------------------------------
# 1st Step: We're going to check that the file exists
if (-not (Test-Path -LiteralPath "$($script:configfile.framework)")) {
    script:Show-RuntimeError -errortext "Configuration file not found:`n$($script:configfile.framework)" -exitapp
}

# 2nd Step: We're trying to load the content from the config.json
try {
    $script:config.framework = Get-Content -LiteralPath $script:configfile.framework -Raw | ConvertFrom-Json -ErrorAction Stop
}
catch {
    script:Show-RuntimeError -errortext "Failed parsing configuration file:`n$($script:configfile.framework)`n$($_.Exception.Message)" -exitapp
}

# 3rd Step: Assign important values from the global config.json
$script:wintwin = [pscustomobject]@{
    root    = $script:config.framework.path.root
    lib     = Join-Path "$($script:config.framework.path.root)" "$($script:config.framework.path.lib)"
    lang    = Join-Path "$($script:config.framework.path.root)" "$($script:config.framework.path.lang)"
    logs    = Join-Path "$($script:config.framework.path.root)" "$($script:config.framework.path.logs)"
    xmlui   = Join-Path "$($script:config.framework.path.root)" "$($script:config.framework.path.appui)"
    fonts   = Join-Path "$($script:config.framework.path.root)" "$($script:config.framework.path.fonts)"
    export  = Join-Path "$($script:config.framework.path.root)" "$($script:config.framework.path.export)"
    console = Join-Path "$($script:config.framework.path.root)" "$($script:config.framework.path.pstools.console)"
    pstt    = Join-Path "$($script:config.framework.path.root)" "$($script:config.framework.path.pstools.root)"
}

# Set the real/full paths to the process.json and jobaction.json
$script:configfile.processdb = Join-Path "$($script:wintwin.root)" "$($script:config.framework.path.appdb.process)"
$script:configfile.jobaction = Join-Path "$($script:wintwin.root)" "$($script:config.framework.path.appdb.actions)"

#--------------------------------------------------------------------------------
# Try to load required Libraries from the WinTwin.Fusion Framework
#--------------------------------------------------------------------------------
$script:LibOPSR  = Join-Path "$($script:wintwin.lib)" "$($script:config.framework.lib.OPSreturn)"
$script:LibPSACL = Join-Path "$($script:wintwin.lib)" "$($script:config.framework.lib.PSAppCoreLib)"
$script:LibWTFXC = Join-Path "$($script:wintwin.lib)" "$($script:config.framework.lib.WinTwinFXcore)"
$script:LibWTXUI = Join-Path "$($script:wintwin.lib)" "$($script:config.framework.lib.WinTwinXUI)"

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
#$null = wintwincore.SetCMDstate -State Hide

#--------------------------------------------------------------------------------
# Load the other JSON-Files
#--------------------------------------------------------------------------------
# Load the jobaction.json
$script:JSONresult = wintwincore.LoadJSON -Path $script:configfile.jobaction
if ( $script:JSONresult.code -ne 0) { script:Show-RuntimeError -errortext "Failed loading following json file:`n$($script:configfile.jobaction)`n$($script:JSONresult.msg)" -exitapp }
$script:config.jobaction = $script:JSONresult.data

# Load the process.json
$script:JSONresult = wintwincore.LoadJSON -Path $script:configfile.processdb
if ( $script:JSONresult.code -ne 0) { script:Show-RuntimeError -errortext "Failed loading following json file:`n$($script:configfile.processdb)`n$($script:JSONresult.msg)" -exitapp }
$script:config.processdb = $script:JSONresult.data

# Load the pstt.config.json
$script:JSONresult = wintwincore.LoadJSON -Path $script:app.config.pstt
if ( $script:JSONresult.code -ne 0) { script:Show-RuntimeError -errortext "Failed loading following json file:`n$($script:app.config.pstt)`n$($script:JSONresult.msg)" -exitapp }
$script:config.psttjson = $script:JSONresult.data

# --------------------------------------------------------------------------
# Required Application Data for UUPD.Compose
# --------------------------------------------------------------------------
$script:app = [PSCustomObject]@{
    icon     = "ps.tweak.tools.ico"
    name     = $null    # <- Stores the name of the application
    version  = $null    # <- Stores the version of the application
    language = $null    # <- Stores the language code (e.g. en-us or de-de)
    langfile = $null    # <- Stores the path to the language file
    logfile  = $null    # <- Stores the path to the logfile
    xmlui    = $null    # <- Stores the path to the xml ui file
    actionid = $null    # <- Stores the action-id (required for job-registration)
    window   = $null    # <- Stores the window-objekt
    control  = $null    # <- Stores all window controls
    style    = [PSCustomObject]@{ # <- Stores styles of the window
        LabelDefaultText = $null # FindResource('BrushText')
        LabelDefaultBack = $null # FindResource('BrushInputBg')
        LabelDefaultBrdr = $null # FindResource('BrushInputBorder')
        InputErrorBack   = $null # FindResource('BrushInputError')
        InputErrorBrdr   = $null # FindResource('BrushInputErrorBrdr')
    }
}
# Load basic data from the pstt.config.json
$script:app.name     = $script:config.psttjson."uupd-compose".appname
$script:app.version  = $script:config.psttjson."uupd-compose".appvers
$script:app.actionid = $script:config.psttjson."uupd-compose"."action-id"
$script:app.xmlui    = $script:config.psttjson."uupd-compose".xmlui

# Load the language information and assign the language file to load
$script:app.language = $script:config.framework.appconfig.defaultlanguage
switch ($script:app.language.ToString().ToLower()) {
    'en-us' { $script:app.langfile = Join-Path "$($script:wintwin.root)" "$($script:config.psttjson.apptool."uupd-compose".langfile."en-us")" }
    'de-de' { $script:app.langfile = Join-Path "$($script:wintwin.root)" "$($script:config.psttjson.apptool."uupd-compose".langfile."de-de")" }
    default { $script:app.langfile = Join-Path "$($script:wintwin.root)" "$($script:config.psttjson.apptool."uupd-compose".langfile."en-us")" }
}
# Load the language file and store the results
$script:JSONresult = wintwincore.LoadJSON -Path $script:app.langfile
if ( $script:JSONresult.code -ne 0) { script:Show-RuntimeError -errortext "Failed loading following json file:`n$($script:app.langfile)`n$($script:JSONresult.msg)" -exitapp }
$script:apptxt = $script:JSONresult.data

# Initialize the logfile
$Script:timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$script:app.logfile  = $Script:config.jobaction."uupd-catch".logfile[1]
$script:app.logfile  = $script:app.logfile -replace '\[DATETIME\]', $Script:timestamp
$script:logmsg=@("$($script:app.name) $($script:app.version) was launched.")
$null = wintwincore.WriteLogmsg -Logfile $script:app.logfile -Message $script:logmsg -Flag "INFO" -Override 1
$script:logmsg=@("All required Assemblies have been successfully loaded.",`
"The Framework Libraries were all successfully initialized.",`
"Core Configuration has been successfully loaded.",`
"Job Actions and ProcessDB were successfully initialized.",
"Configuration for $($script:app.name) successfully loaded.")
$null = wintwincore.WriteLogmsg -Logfile $script:app.logfile -Message $script:logmsg -Flag "OKAY"

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
# Store required styles
$Script:app.style.InputErrorBack   = $script:app.window.FindResource('BrushInputError')
$Script:app.style.InputErrorBrdr   = $script:app.window.FindResource('BrushInputErrorBrdr')
$Script:app.style.LabelDefaultBack = $script:app.window.FindResource('BrushInputBg')
$Script:app.style.LabelDefaultBrdr = $script:app.window.FindResource('BrushInputBorder')
$Script:app.style.LabelDefaultText = $script:app.window.FindResource('BrushText')

#--------------------------------------------------------------------------------
# Applying loaded language file to the interface
#--------------------------------------------------------------------------------
$script:app.control.LblInstructions.Text         = $Script:apptxt.ui.LblInstructions
$script:app.control.LblComposeInfo.Text          = $Script:apptxt.ui.LblComposeInfo
$script:app.control.LblDownloadSettings.Text     = $Script:apptxt.ui.LblDownloadSettings
$script:app.control.LblZIPlocation.Text          = $Script:apptxt.ui.LblZIPlocation
$script:app.control.LblISOfileSettings.Text      = $Script:apptxt.ui.LblISOfileSettings
$script:app.control.LblISOlocation.Text          = $Script:apptxt.ui.LblISOlocation
$script:app.control.LblFilename.Text             = $Script:apptxt.ui.LblFilename
$script:app.control.LblImportantInformation.Text = $Script:apptxt.ui.LblImportantInformation
$script:app.control.TxtImportantInformation.Text = $Script:apptxt.ui.TxtImportantInformation
$script:app.control.BtnCreateISO.Content         = $Script:apptxt.ui.BtnCreateISO
$script:app.control.BtnExitApp.Content           = $Script:apptxt.ui.BtnExitApp
$script:app.control.StatusText.Text              = $Script:apptxt.status.isready
$script:app.control.StatusInfo.Text              = "$($scrtip:app.name) ($($scrtip:app.version))"


if (Test-Path -LiteralPath $Script:app.icon) {
    try {
        $titleBarLogo.Source = [System.Windows.Media.Imaging.BitmapImage]::new([System.Uri]::new($Script:app.icon))
    }
    catch {
        Write-Verbose "Could not set title bar logo: $($_.Exception.Message)"
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
    
    #Start-Sleep -Milliseconds 50
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

$script:app.window.Add_ContentRendered({
    # Load the current settings (jobaction.json)
    script:LoadUUPDsettings
    # Push the changes to the ui
    script:uiEvent
})

#$script:logmsg=@("Showing Install Manager Window using 'ShowDialog() | Out-Null'")
#$null = wintwincore.WriteLogmsg -Logfile $script:setupconfig.logfile -Message $script:logmsg -Flag "INFO"

$script:app.window.ShowDialog() | Out-Null
# Cleanup/Exit
$null = wintwincore.SetCMDstate -State Show -Focus $false
$script:logmsg=@("$($script:app.name) $($script:app.version) was closed.","Thank you for using UUPD.Catcher (PS.Tweak.Tools)")
$null = wintwincore.WriteLogmsg -Logfile $script:app.logfile -Message $script:logmsg -Flag "INFO"
exit 0


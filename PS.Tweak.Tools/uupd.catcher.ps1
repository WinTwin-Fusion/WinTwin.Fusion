<#
.SYNOPSIS
    UUPD.Catcher - UI Frontend for downloading ZIP-Files from uupdump.net
.DESCRIPTION
    The UUPD.Catcher provides a graphical interface that makes it possible
    to easily create a download-request for uupdump.net and download a ZIP-File
.NOTES
    CREATOR:    Praetoriani (a.k.a M.Sczepanski)
    WEBSITE:    https://github.com/WinTwin-Fusion/PS.Tweak.Tools
    VERSION:    v1.00.05
    CREATED:    03.09.2026
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
    icon     = "ps.tweak.tools.ico"
    name     = $null
    path     = $null
    version  = $null
    langfile = $null
    logfile  = $null
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

# Needed to determine of we have a current background-process running
$Script:bgprocess = $false

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
$Script:app.icon        = Join-Path "$($Script:wintwin.root)" "$($Script:app.icon)"
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
$null = wintwincore.SetCMDstate -State Hide

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
$script:app.path     = Join-Path "$($Script:wintwin.root)" "$($script:JSONresult.data.apptool."uupd-catch".apppath)"
$script:app.xmlui    = Join-Path "$($Script:wintwin.root)" "$($script:JSONresult.data.apptool."uupd-catch".xmlui)"
$script:app.logfile  = $Script:config.jobaction."uupd-catch".logfile[1]
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

# Prepare the Logfile and write the first line
$Script:timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$script:app.logfile = $script:app.logfile -replace '\[DATETIME\]', $Script:timestamp
$script:logmsg=@("$($script:app.name) $($script:app.version) was launched.")
$null = wintwincore.WriteLogmsg -Logfile $script:app.logfile -Message $script:logmsg -Flag "INFO" -Override 1

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

$Script:BrushInputError     = $script:app.window.FindResource('BrushInputError')
$Script:BrushInputErrorBrdr = $script:app.window.FindResource('BrushInputErrorBrdr')
$Script:BrushInputBg        = $script:app.window.FindResource('BrushInputBg')
$Script:BrushInputBorder    = $script:app.window.FindResource('BrushInputBorder')
$Script:BrushText           = $script:app.window.FindResource('BrushText')

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
$script:app.control.BtnReset.Content         = $Script:apptxt.ui.BtnReset
$script:app.control.BtnExit.Content          = $Script:apptxt.ui.BtnExit
$script:app.control.StatusText.Text          = $Script:apptxt.status.isready
$script:app.control.StatusInfo.Text          = "$($script:app.name) ($($script:app.version))"


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

function script:LoadUUPDsettings {
    # Load System-Details from jobaction.json
    $Local:name = $Script:config.jobaction."uupd-catch".system.name
    $Local:type = $Script:config.jobaction."uupd-catch".system.type
    $Local:arch = $Script:config.jobaction."uupd-catch".system.arch[1]
    $Local:vers = $Script:config.jobaction."uupd-catch".system.vers
    $Local:lang = $Script:config.jobaction."uupd-catch".system.lang
    # Get the converter options frmo jobaction.json
    $Local:updates = [bool]$Script:config.jobaction."uupd-catch".config.updates
    $Local:cleanup = [bool]$Script:config.jobaction."uupd-catch".config.cleanup
    $Local:dotnet  = [bool]$Script:config.jobaction."uupd-catch".config.dotnet35
    # Get the download options from jobsction.json
    $Local:location = $Script:config.jobaction."uupd-catch".download.location
    $Local:filename = $Script:config.jobaction."uupd-catch".download.uupdname
    $Local:finished = [bool]$Script:config.jobaction."uupd-catch".download.finished
    # Simulate a click on the "Reset"-Button to reset the form

    $script:app.control.BtnReset.RaiseEvent([System.Windows.RoutedEventArgs]::new(
        [System.Windows.Controls.Primitives.ButtonBase]::ClickEvent
    ))
    
    # Assign the values from the jobaction.json
    if     ($Local:type -eq "24H2") { $script:app.control.RadioWin24H2.IsChecked = $true }
    elseif ($Local:type -eq "25H2") { $script:app.control.RadioWin25H2.IsChecked = $true }
    else   { $script:app.control.RadioWin24H2.IsChecked = $false ; $script:app.control.RadioWin25H2.IsChecked = $false }

    $Local:arch = $Local:arch.ToString().ToLower()
    if     ($Local:arch -eq "amd64") { $script:app.control.RadioArchAmd64.IsChecked = $true }
    elseif ($Local:arch -eq "arm64") { $script:app.control.RadioArchArm64.IsChecked = $true }
    else   { $script:app.control.RadioArchAmd64.IsChecked = $false ; $script:app.control.RadioArchArm64.IsChecked = $false }

    $Local:vers = $Local:vers.ToString().ToLower()
    if     ($Local:vers -eq "home") { $script:app.control.RadioHome.IsChecked = $true }
    elseif ($Local:vers -eq "pro") { $script:app.control.RadioPro.IsChecked = $true }
    else   { $script:app.control.RadioHome.IsChecked = $false ; $script:app.control.RadioPro.IsChecked = $false }

    $Local:lang = $Local:lang.ToString().ToLower()
    if     ($Local:lang -eq "en-us") { $script:app.control.RadioLangENUS.IsChecked = $true }
    elseif ($Local:lang -eq "de-de") { $script:app.control.RadioLangDEDE.IsChecked = $true }
    else   { $script:app.control.RadioLangENUS.IsChecked = $false ; $script:app.control.RadioLangDEDE.IsChecked = $false }

    if     ($Local:updates) { $script:app.control.ChkAddUpdates.IsChecked = $true }
    else   { $script:app.control.ChkAddUpdates.IsChecked = $false }

    if     ($Local:cleanup) { $script:app.control.ChkCleanup.IsChecked = $true }
    else   { $script:app.control.ChkCleanup.IsChecked = $false }

    if     ($Local:dotnet) { $script:app.control.ChkNetFx35.IsChecked = $true }
    else   { $script:app.control.ChkNetFx35.IsChecked = $false }

    $Local:name = $Local:name -replace '\s', ''
    $Local:filename = $Local:filename -f "$($Local:name)-$($Local:vers)-$($Local:type)-$($Local:arch)"
	if ($Local:filename.Substring($Local:filename.Length - 4) -ne ".zip") {
		$Local:filename = "$($Local:filename).zip"
	}
    $script:app.control.TxtZIPLocation.Text = "$($Local:location)"
    $script:app.control.TxtFilename.Text = "$($Local:filename)"

    if     ($Local:finished) { $script:app.control.ChkCloseWhenDone.IsChecked = $true }
    else   { $script:app.control.ChkCloseWhenDone.IsChecked = $false }

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

# The "include updates" checkbox was unchecked
$script:app.control.ChkAddUpdates.Add_Unchecked({
    if ($script:app.control.ChkCleanup.IsChecked -eq $true) {
        $script:app.control.ChkCleanup.IsChecked = $false
    }
})

# "Set a location" was clicked
$script:app.control.BtnBrowseLocation.Add_Click({
    # Keep the old input
    $Local:oldinput = $script:app.control.TxtZIPLocation.Text
    # Clear the input field
    $script:app.control.TxtZIPLocation.Clear()
    # Show the Dialog
    $Local:pickfolder = xuiSelectFolder -Title 'Where to save the ZIP-File?'
    # Set the new/old path to the input field
    if ($Local:pickfolder.code -eq 0) {
        $script:app.control.TxtZIPLocation.Text = $Local:pickfolder.data.Path
    } else {
        $script:app.control.TxtZIPLocation.Text = $Local:oldinput
    }
})

# Download-Button was clicked
$script:app.control.BtnDownload.Add_Click({
    
    $script:logmsg=@("$($script:app.control.BtnDownload.Content)-Button was pressed.")
    $null = wintwincore.WriteLogmsg -Logfile $script:app.logfile -Message $script:logmsg -Flag "INFO"
    
    # 1st Step: We're going to reset the action buttons
    $script:app.control.BtnDownload.IsEnabled = $false
    $script:app.control.BtnReset.IsEnabled    = $false
    $script:app.control.BtnExit.IsEnabled     = $false
    # We have to reset error indicators
    $script:app.control.LblWinVersion.Foreground   = $Script:BrushText
    $script:app.control.LblEditions.Foreground     = $Script:BrushText
    $script:app.control.LblArch.Foreground         = $Script:BrushText
    $script:app.control.LblLanguage.Foreground     = $Script:BrushText
    $script:app.control.TxtZIPLocation.Background  = $Script:BrushInputBg
    $script:app.control.TxtZIPLocation.BorderBrush = $Script:BrushInputBorder
    $script:app.control.TxtFilename.Background     = $Script:BrushInputBg
    $script:app.control.TxtFilename.BorderBrush    = $Script:BrushInputBorder
    script:uiEvent

    $Local:errorcount = 0
    # Initialize the required values
    $Local:osname   = "windows11"
    $Local:osvers   = $null
    $Local:osedit   = $null
    $Local:osarch   = $null
    $Local:oslang   = $null
    $Local:updates  = $null
    $Local:cleanup  = $null
    $Local:dotnet3  = $null
    $Local:location = $null
    $Local:filename = $null
    $Local:fullpath = $null

    if     ($script:app.control.RadioWin24H2.IsChecked) { $Local:osvers = "24H2"}
    elseif ($script:app.control.RadioWin25H2.IsChecked) { $Local:osvers = "25H2"}
    else   { $Local:errorcount++ ; $script:app.control.LblWinVersion.Foreground = $Script:BrushInputError ; script:uiEvent }

    if     ($script:app.control.RadioHome.IsChecked) { $Local:osedit = "home"}
    elseif ($script:app.control.RadioPro.IsChecked) { $Local:osedit = "pro"}
    else   { $Local:errorcount++ ; $script:app.control.LblEditions.Foreground = $Script:BrushInputError ; script:uiEvent }
    
    if     ($script:app.control.RadioArchAmd64.IsChecked) { $Local:osarch = "amd64"}
    elseif ($script:app.control.RadioArchArm64.IsChecked) { $Local:osarch = "arm64"}
    else   { $Local:errorcount++ ; $script:app.control.LblArch.Foreground = $Script:BrushInputError ; script:uiEvent }
    
    if     ($script:app.control.RadioLangENUS.IsChecked) { $Local:oslang = "en-us"}
    elseif ($script:app.control.RadioLangDEDE.IsChecked) { $Local:oslang = "de-de"}
    else   { $Local:errorcount++ ; $script:app.control.LblLanguage.Foreground = $Script:BrushInputError ; script:uiEvent }
    
    if     ($script:app.control.ChkAddUpdates.IsChecked) { $Local:updates = "1" }
    else   { $Local:updates = "0" }
    
    if     ($script:app.control.ChkCleanup.IsChecked) { $Local:cleanup = "1" }
    else   { $Local:cleanup = "0" }
    
    if     ($script:app.control.ChkNetFx35.IsChecked) { $Local:dotnet3 = "1" }
    else   { $Local:dotnet3 = "0" }

    # -or (-not (Test-Path -LiteralPath $script:app.control.TxtZIPLocation.Text -PathType Container))
    if ( [string]::IsNullOrWhiteSpace($script:app.control.TxtZIPLocation.Text) ) {
        $Local:errorcount++
        $script:app.control.TxtZIPLocation.Background  = $Script:BrushInputError
        $script:app.control.TxtZIPLocation.BorderBrush = $Script:BrushInputErrorBrdr
        script:uiEvent
    }
    elseif ( -not (Test-Path -LiteralPath $script:app.control.TxtZIPLocation.Text -PathType Container) ) {
        $Local:errorcount++
        $script:app.control.TxtZIPLocation.Background  = $Script:BrushInputError
        $script:app.control.TxtZIPLocation.BorderBrush = $Script:BrushInputErrorBrdr
        script:uiEvent
    }    
    else {
        $Local:location = $script:app.control.TxtZIPLocation.Text
    }

    if ( [string]::IsNullOrWhiteSpace($script:app.control.TxtFilename.Text) ) {
        $Local:errorcount++
        $script:app.control.TxtFilename.Background  = $Script:BrushInputError
        $script:app.control.TxtFilename.BorderBrush = $Script:BrushInputErrorBrdr
        script:uiEvent
    }
    elseif ( $script:app.control.TxtFilename.Text.Substring($script:app.control.TxtFilename.Text.Length - 4) -ne ".zip") {
        $Local:errorcount++
        $script:app.control.TxtFilename.Background  = $Script:BrushInputError
        $script:app.control.TxtFilename.BorderBrush = $Script:BrushInputErrorBrdr
        script:uiEvent
    }
    else {
        $Local:filename = $script:app.control.TxtFilename.Text
    }

    if (-not ([string]::IsNullOrWhiteSpace($script:app.control.TxtZIPLocation.Text)) -and -not ([string]::IsNullOrWhiteSpace($script:app.control.TxtFilename.Text))) {
        $Local:fullpath = Join-Path $Local:location $Local:filename -ErrorAction SilentlyContinue
        if ( Test-Path -LiteralPath $Local:fullpath -PathType Leaf ) {
            $Local:errorcount++
            $script:app.control.TxtZIPLocation.Background  = $Script:BrushInputError
            $script:app.control.TxtZIPLocation.BorderBrush = $Script:BrushInputErrorBrdr
            $script:app.control.TxtFilename.Background  = $Script:BrushInputError
            $script:app.control.TxtFilename.BorderBrush = $Script:BrushInputErrorBrdr
        }
    }

    if ( $Local:errorcount -ge 1 ) {
        # Release the action buttons again
        $script:app.control.BtnDownload.IsEnabled = $true
        $script:app.control.BtnReset.IsEnabled    = $true
        $script:app.control.BtnExit.IsEnabled     = $true
        $script:logmsg=@("$($Local:errorcount) errors found in the form. Download cannot be started!")
        $null = wintwincore.WriteLogmsg -Logfile $script:app.logfile -Message $script:logmsg -Flag "WARN"
        return $false
    }
    
    $script:logmsg=@("No errors found. Start downloading reqeusted file from https://uupdump.net/.")
    $null = wintwincore.WriteLogmsg -Logfile $script:app.logfile -Message $script:logmsg -Flag "OKAY"

    $Local:DLresult = $null
    # Download Windows 11 Pro 24H2 with .NET FX 3.5 included and WIM format (default settings)
    if ( $Local:dotnet3 -eq 0) {
        $Local:DLresult = wintwincore.DownloadUUPDump -OStype "$($Local:osname)" `
        -OSvers "$($Local:osvers)" -OSarch "$($Local:osarch)" `
        -Edition "$($Local:osedit)" -Language "$($Local:oslang)" `
        -AddUpdates "$($Local:updates)" -DoCleanup "$($Local:cleanup)" -ExcludeNetFX `
        -Target "$($Local:fullpath)"
    } else {
        $Local:DLresult = wintwincore.DownloadUUPDump -OStype "$($Local:osname)" `
        -OSvers "$($Local:osvers)" -OSarch "$($Local:osarch)" `
        -Edition "$($Local:osedit)" -Language "$($Local:oslang)" `
        -AddUpdates "$($Local:updates)" -DoCleanup "$($Local:cleanup)" -IncludeNetFX `
        -Target "$($Local:fullpath)"
    }
    
    if ( $Local:DLresult.code -eq 1 ) {
        # Write something into the logfile
        $script:logmsg=@("The Download from https://uupdump.net/ failed. Reason:`n$($Local:DLresult.msg)")
        $null = wintwincore.WriteLogmsg -Logfile $script:app.logfile -Message $script:logmsg -Flag "FAIL"
        # Update the text in the statusbar
        $script:app.control.StatusText.Text = $Script:apptxt.status.dlerror
        # Display a dialog
        $null = wintwincore.SystemMessageBox -smbTitle "$($Script:errorhead)" `
        -smbText "Failed downloading requested file from uupdump.net!`nPlease check the logfile for further informations." `
        -smbIcon Warning -smbButtons OK
    } else {
        # Drop a long message about the download result to the logfile
        $script:logmsg=@("Download from https://uupdump.net/ was successfull.","Here are some details about the download:",`
        "Location:   $($Local:DLresult.data.FileName)",
        "File size:  $($Local:DLresult.data.FileSize) KB",
        "Full Name:  $($Local:DLresult.data.BuildText)"
        "Edition:    $($Local:DLresult.data.Edition)",
        "Language:   $($Local:DLresult.data.Language)",
        "BuildNo:    $($Local:DLresult.data.BuildNo) ($($Local:DLresult.data.BuildText))",
        "UUIDBuild:   $($Local:DLresult.data.UUIDBuild)")
        $null = wintwincore.WriteLogmsg -Logfile $script:app.logfile -Message $script:logmsg -Flag "OKAY"
        # Update the text in the statusbar
        $script:app.control.StatusText.Text = $Script:apptxt.status.dlsuccess

        # Update the job-actions for UUPD.Compose
        $script:config.jobaction."uupd-compose".zipfile = "$($Local:DLresult.data.FileName)"
        $script:config.jobaction."uupd-compose".isopath = "$($Local:location)"
        # Prepare a ISO-Filename based on the ZIP-Filename
        $script:isoFilename = $Local:DLresult.data.FileName.Substring(0, $Local:DLresult.data.FileName.Length - 4)
        $script:isoFilename = "$($script:isoFilename).iso"
        $script:config.jobaction."uupd-compose".isoname = "$($script:isoFilename)"
        # Write the current job action config to the JSON-File
        $script:writeJSON = wintwincore.WriteJSON -Path $script:configfile.jobaction -Value $script:config.jobaction
        if ($script:writeJSON.code -ne 0) {
            $script:logmsg=@("Failed updating job action details for $($script:app.name)","zipfile:  $($Local:DLresult.data.FileName)",`
            "isopath:  $($Local:location)","isonane:  $($script:isoFilename)")
            $null = wintwincore.WriteLogmsg -Logfile $script:setupconfig.logfile -Message $script:logmsg -Flag "FAIL"
            $script:logmsg=@("Function wintwincore.writeJSON failed:","File: $($script:configfile.jobaction)",`
            "Exit Code: $($script:writeJSON.code)","Message: $($script:writeJSON.msg)","Exception: $($script:writeJSON.exception)")
            $null = wintwincore.WriteLogmsg -Logfile $script:setupconfig.logfile -Message $script:logmsg -Flag "FAIL"
        }
        # Display a dialog 
        $null = wintwincore.SystemMessageBox -smbTitle "$($Script:errorhead)" `
        -smbText "Download from https://uupdump.net/ successfully finished.`nThe Download is stored here:`n$($Local:fullpath)" `
        -smbIcon None -smbButtons OK
    }

    # Release the action buttons again
    $script:app.control.BtnDownload.IsEnabled = $true
    $script:app.control.BtnReset.IsEnabled    = $true
    $script:app.control.BtnExit.IsEnabled     = $true
})

# Reset-Button was clicked
$script:app.control.BtnReset.Add_Click({    
    # We have to reset error indicators
    $script:app.control.LblWinVersion.Foreground   = $Script:BrushText
    $script:app.control.LblEditions.Foreground     = $Script:BrushText
    $script:app.control.LblArch.Foreground         = $Script:BrushText
    $script:app.control.LblLanguage.Foreground     = $Script:BrushText
    $script:app.control.TxtZIPLocation.Background  = $Script:BrushInputBg
    $script:app.control.TxtZIPLocation.BorderBrush = $Script:BrushInputBorder
    $script:app.control.TxtFilename.Background     = $Script:BrushInputBg
    $script:app.control.TxtFilename.BorderBrush    = $Script:BrushInputBorder
    # Reset the rest of the form
    $script:app.control.RadioWin24H2.IsChecked     = $false
    $script:app.control.RadioWin25H2.IsChecked     = $false
    $script:app.control.RadioHome.IsChecked        = $false
    $script:app.control.RadioPro.IsChecked         = $false
    $script:app.control.RadioArchAmd64.IsChecked   = $false
    $script:app.control.RadioArchArm64.IsChecked   = $false
    $script:app.control.RadioLangENUS.IsChecked    = $false
    $script:app.control.RadioLangDEDE.IsChecked    = $false
    $script:app.control.ChkAddUpdates.IsChecked    = $false
    $script:app.control.ChkCleanup.IsChecked       = $false
    $script:app.control.ChkNetFx35.IsChecked       = $false
    $script:app.control.TxtZIPLocation.Clear()
    $script:app.control.TxtFilename.Clear()
    $script:app.control.ChkCloseWhenDone.IsChecked = $false
    $script:app.control.StatusText.Text            = $Script:apptxt.status.isready
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

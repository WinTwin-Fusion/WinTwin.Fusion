<#
.SYNOPSIS
    UUPD.Compose - UI Frontend for creating ISO Files from a previous download from uupdump.net
.DESCRIPTION
    The UUPD.Compose provides a graphical interface that helps you creating ISO-Files
    from a ZIP-File that was previously downloaded from uupdump.net
.NOTES
    CREATOR:    Praetoriani (a.k.a M.Sczepanski)
    WEBSITE:    https://github.com/WinTwin-Fusion/PS.Tweak.Tools
    VERSION:    v1.00.05
    CREATED:    05.09.2026
    UPDATED:    06.09.2026

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
    Start-Sleep -Milliseconds 3000
    exit 1
}


# --------------------------------------------------------------------------
# ERROR HANDLING
# Using the script:Add-Error function, the installer collects information
# about errors that occurred during the process.
# --------------------------------------------------------------------------
$script:errorlist = @()
$script:errorhead = "UUPD.Compose (PS.Twaek.Tools)"
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

$script:ProcessID = Get-Process -Id $PID

$script:configfile = [PSCustomObject]@{
    framework = "..\core\config.json"
    processdb = "process.json"
    jobaction = "jobaction.json"
    psttjson  = "pstt.config.json"
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
$script:configfile.psttjson  = Join-Path "$($script:wintwin.pstt)" "$($script:configfile.psttjson)"

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
$script:JSONresult = wintwincore.LoadJSON -Path $script:configfile.psttjson
if ( $script:JSONresult.code -ne 0) { script:Show-RuntimeError -errortext "Failed loading following json file:`n$($script:configfile.psttjson)`n$($script:JSONresult.msg)" -exitapp }
$script:config.psttjson = $script:JSONresult.data

# --------------------------------------------------------------------------
# Required Application Data for UUPD.Compose
# --------------------------------------------------------------------------
$script:app = [PSCustomObject]@{
    icon       = "ps.tweak.tools.ico"
    toolbox    = $null    # <- Stores the name of the toolbox (e.g. PS.Tweak.Tools or DISM.UI.CC)
    name       = $null    # <- Stores the name of the application
    version    = $null    # <- Stores the version of the application
    language   = $null    # <- Stores the language code (e.g. en-us or de-de)
    langfile   = $null    # <- Stores the path to the language file
    logfile    = $null    # <- Stores the path to the logfile
    xmlui      = $null    # <- Stores the path to the xml ui file
    popup      = $null    # <- Stores the path to the magic.window.xml :)
    actionid   = $null    # <- Stores the action-id (required for job-registration)
    script     = [PSCustomObject]@{
        file   = $null
        type   = $null
    }
    consoleLog = $null
    process    = 'running'# can be running, stopped, handoff
    window     = $null    # <- Stores the window-objekt
    control    = $null    # <- Stores all window controls
    style      = [PSCustomObject]@{ # <- Stores styles of the window
        LabelDefaultText = $null # FindResource('BrushText')
        LabelDefaultBack = $null # FindResource('BrushInputBg')
        LabelDefaultBrdr = $null # FindResource('BrushInputBorder')
        InputErrorBack   = $null # FindResource('BrushInputError')
        InputErrorBrdr   = $null # FindResource('BrushInputErrorBrdr')
    }
}

# Load basic data from the pstt.config.json
$script:app.toolbox  = $script:config.psttjson.appinfo.name
$script:app.name     = $script:config.psttjson.apptool."uupd-compose".appname
$script:app.version  = $script:config.psttjson.apptool."uupd-compose".appvers
$script:app.actionid = $script:config.psttjson.apptool."uupd-compose"."action-id"
$script:app.xmlui    = Join-Path "$($script:wintwin.root)" "$($script:config.psttjson.apptool."uupd-compose".xmlui)"
$script:app.popup    = Join-Path "$($script:wintwin.root)" "$($script:config.psttjson.apptool."uupd-compose".popup)"

# Load the script and logging details (required for the console interaction)
$script:app.script.file = "$($script:config.psttjson.apptool."uupd-compose".scriptfile)"
$script:app.script.type = "$($script:config.psttjson.apptool."uupd-compose".scripttype)"
$script:app.consoleLog  = Join-Path "$($script:wintwin.logs)" "$($script:config.psttjson.apptool."uupd-compose".consolelog)"

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
$scripttimestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$script:app.logfile  = $script:config.jobaction."uupd-compose".logfile[1]
$script:app.logfile  = $script:app.logfile -replace '\[DATETIME\]', $scripttimestamp
# Write the first line (using override)
$script:logmsg=@("$($script:app.name) $($script:app.version) was launched.")
$null = wintwincore.WriteLogmsg -Logfile $script:app.logfile -Message $script:logmsg -Flag "INFO" -Override 1
$script:logmsg=@("All required Assemblies have been successfully loaded.",`
"The Framework Libraries were all successfully initialized.",`
"Core Configuration has been successfully loaded.",`
"Job Actions and ProcessDB were successfully initialized.",
"Configuration for $($script:app.name) successfully loaded.")
$null = wintwincore.WriteLogmsg -Logfile $script:app.logfile -Message $script:logmsg -Flag "OKAY"

#--------------------------------------------------------------------------------
# PROCESS REGISTRATION
# This step is crucial to prevent multiple processes from running in
# parallel mode and potentially accessing the same resources.
#--------------------------------------------------------------------------------
$script:processCheck = wintwincore.CheckProcess -FrameworkRoot $script:wintwin.root
if ($script:processCheck.code -ne 0) {
    # Failed checking for running process. Let's write it to the logfile
    $script:logmsg=@("$($script:app.name) failed to verify potential process locks",`
    "Function wintwincore.CheckProcess faild with the following reason:","$($script:processCheck.msg)")
    $null = wintwincore.WriteLogmsg -Logfile $script:app.logfile -Message $script:logmsg -Flag "FAIL"
    # Show an error dialog and exit
    script:Show-RuntimeError -errortext "Failed checking for active process. Please check the logfile for more details." -exitapp
}
# Running Process detected
if ($script:processCheck.data.IsRunning) {
    $script:logmsg=@("$($script:app.name) detected another running/active Framework Process!",`
    "The following Framework Process is currently running:","$($script:processCheck.data.IsRunning."proc-name")",`
    "Due to protection rules, $($script:app.name) cannot continue as long as $($script:processCheck.data.IsRunning."proc-name") is running.")
    $null = wintwincore.WriteLogmsg -Logfile $script:app.logfile -Message $script:logmsg -Flag "WARN"
    # Show an error dialog and exit
    $null = wintwincore.SystemMessageBox -smbTitle $script:errorhead `
    -smbText "Another framework process is currently running!`nPlease wait until it has finished.`n`nCheck the logfile for more informations." `
    -smbIcon Warning -smbButtons OK
    exit 0
}
$script:selfRegister = wintwincore.RegisterProcess -FrameworkRoot $script:wintwin.root `
                                     -ProcName "$($script:app.name)" `
                                     -ProcPath $PSCommandPath `
                                     -ActionId "$($script:app.actionid)" `
                                     -ProcessId $script:ProcessID.Id
if ($script:selfRegister.code -ne 0) {
    # Registration failed. Write something to the logfile
    $script:logmsg=@("$($script:app.name) failed to register as active Framework Process!",`
    "Function wintwincore.RegisterProcess failed with the following reason:","$($script:selfRegister.msg)")
    $null = wintwincore.WriteLogmsg -Logfile $script:app.logfile -Message $script:logmsg -Flag "FAIL"
    # Show an error dialog an exit
    $null = wintwincore.SystemMessageBox -smbTitle $script:errorhead `
    -smbText "$($script:app.name) could not register as active framework process.`nPlease check the logfile for more informations."
    -smbIcon Warning -smbButtons OK
    exit 1
}

$script:logmsg=@("$($script:app.name) successfully registered as current Framework Process.")
$null = wintwincore.WriteLogmsg -Logfile $script:app.logfile -Message $script:logmsg -Flag "OKAY"

#--------------------------------------------------------------------------------
# Load/Create the Window
# In this section, the UI is loaded from the XML file, the window is created,
# and all UI elements are referenced. Everything will be stored in $script:app
#--------------------------------------------------------------------------------
# The -extended switch returns the window object including the referenced controls
$script:LoadXML = xuiLoadWindow -XMLfile $script:app.xmlui -extended
if ( $script:LoadXML.code -ne 0) {
    $script:logmsg=@("Failed loading UI from following XML-File:","$($script:app.xmlui)",`
    "Function xuiLoadWindow failed with following reason:","$($script:LoadXML.msg)")
    $null = wintwincore.WriteLogmsg -Logfile $script:app.logfile -Message $script:logmsg -Flag "OKAY"
    script:Show-RuntimeError -errortext "Faild loading User Interface:`n$($script:app.xmlui)`n$($script:LoadXML.msg)" -exitapp
}
# Store the window and all controls inside the window
$script:app.window  = $script:LoadXML.data.Window
$script:app.control = $script:LoadXML.data.Controls
# Store required styles
$script:app.style.InputErrorBack   = $script:app.window.FindResource('BrushInputError')
$script:app.style.InputErrorBrdr   = $script:app.window.FindResource('BrushInputErrorBrdr')
$script:app.style.LabelDefaultBack = $script:app.window.FindResource('BrushInputBg')
$script:app.style.LabelDefaultBrdr = $script:app.window.FindResource('BrushInputBorder')
$script:app.style.LabelDefaultText = $script:app.window.FindResource('BrushText')

#--------------------------------------------------------------------------------
# Applying loaded language file to the interface
#--------------------------------------------------------------------------------
$script:app.control.LblInstructions.Text         = $script:apptxt.ui.LblInstructions
$script:app.control.LblComposeInfo.Text          = $script:apptxt.ui.LblComposeInfo
$script:app.control.LblDownloadSettings.Text     = $script:apptxt.ui.LblDownloadSettings
$script:app.control.LblZIPlocation.Text          = $script:apptxt.ui.LblZIPlocation
$script:app.control.LblISOfileSettings.Text      = $script:apptxt.ui.LblISOfileSettings
$script:app.control.LblISOlocation.Text          = $script:apptxt.ui.LblISOlocation
$script:app.control.LblISOFilename.Text          = $script:apptxt.ui.LblISOFilename
$script:app.control.LblImportantInformation.Text = $script:apptxt.ui.LblImportantInformation
$script:app.control.TxtImportantInformation.Text = $script:apptxt.ui.TxtImportantInformation
$script:app.control.BtnCreateISO.Content         = $script:apptxt.ui.BtnCreateISO
$script:app.control.BtnExitApp.Content           = $script:apptxt.ui.BtnExitApp
$script:app.control.StatusText.Text              = $script:apptxt.status.isready
$script:app.control.StatusInfo.Text              = "$($script:app.name) ($($script:app.version))"


if (Test-Path -LiteralPath $script:app.icon) {
    try {
        $titleBarLogo.Source = [System.Windows.Media.Imaging.BitmapImage]::new([System.Uri]::new($script:app.icon))
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
# This function orchestrates the magic.window.xml
function script:ShowMagicWindow {
    [CmdletBinding(DefaultParameterSetName = 'Info')]
    param(
        [Parameter(ParameterSetName = 'Info')]
        [switch]$mwInfo,

        [Parameter(ParameterSetName = 'Warning')]
        [switch]$mwWarning,

        [Parameter(ParameterSetName = 'Error')]
        [switch]$mwError,

        [ValidateSet('OK', 'OKCancel', 'YesNo', 'YesNoCancel')]
        [string]$Buttons = 'OK',

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Title,

        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string]$Message,

        [System.Windows.Window]$Owner,

        [Parameter(Mandatory = $false)]
        [string]$XamlPath = $script:app.popup
    )

    if (-not (Test-Path -LiteralPath $XamlPath -PathType Leaf)) {
        $script:logmsg=@("Failed loading UI from following XML-File:","$($XamlPath)",`
        "Function script:ShowDialogWindow failed with following reason:","File not found!")
        $null = wintwincore.WriteLogmsg -Logfile $script:app.logfile -Message $script:logmsg -Flag "FAIL"
        script:Show-RuntimeError -errortext "Faild loading User Interface:`n$($XamlPath)`nPlease check the logfile for more informations." -exitapp
    }

    try {
        [xml]$xaml = Get-Content -LiteralPath $XamlPath -Raw -Encoding UTF8 -ErrorAction Stop
        $reader = [System.Xml.XmlNodeReader]::new($xaml)
        $window = [System.Windows.Markup.XamlReader]::Load($reader)
    }
    catch {
        $script:logmsg=@("Failed loading UI from following XML-File:","$($XamlPath)",`
        "Function script:ShowDialogWindow failed with following reason:","$($_.Exception.Message)")
        $null = wintwincore.WriteLogmsg -Logfile $script:app.logfile -Message $script:logmsg -Flag "FAIL"
        script:Show-RuntimeError -errortext "Faild loading User Interface:`n$($XamlPath)`nPlease check the logfile for more informations." -exitapp
    }
    finally {
        $reader.Close()
    }

    $controls = @{}

    @(
        'TitleBarPanel',
        'TitleBarText',
        'DialogTitle',
        'DialogMessage',
        'BtnClose',
        'BtnYes',
        'BtnNo',
        'BtnOK',
        'BtnCancel',
        'TitleIconInfo',
        'TitleIconWarning',
        'TitleIconError',
        'ContentIconInfo',
        'ContentIconWarning',
        'ContentIconError'
    ) | ForEach-Object {
        $controls[$_] = $window.FindName($_)

        if ($null -eq $controls[$_]) {
            throw "XAML-Element fehlt: $_"
            $script:logmsg=@("Failed loading UI from following XML-File:","$($XamlPath)",`
            "Function script:ShowDialogWindow failed with following reason:","Following XAML-Element is missing: $($_)")
            $null = wintwincore.WriteLogmsg -Logfile $script:app.logfile -Message $script:logmsg -Flag "FAIL"
            script:Show-RuntimeError -errortext "Faild loading User Interface:`n$($XamlPath)`nPlease check the logfile for more informations." -exitapp
        }
    }

    $window.Title = $Title
    $controls.TitleBarText.Text = $Title
    $controls.DialogTitle.Text = $Title
    $controls.DialogMessage.Text = $Message

    if ($null -ne $Owner) {
        $window.Owner = $Owner
        $window.WindowStartupLocation = [System.Windows.WindowStartupLocation]::CenterOwner
    }
    else {
        $window.WindowStartupLocation = [System.Windows.WindowStartupLocation]::CenterScreen
    }

    $kind = if ($mwWarning) { 'Warning' }
    elseif ($mwError) { 'Error' }
    else { 'Info' }

    foreach ($name in @('Info', 'Warning', 'Error')) {
        $visibility = if ($name -eq $kind) { [System.Windows.Visibility]::Visible }
        else { [System.Windows.Visibility]::Collapsed }
        $controls["TitleIcon$name"].Visibility = $visibility
        $controls["ContentIcon$name"].Visibility = $visibility
    }

    $visibleButtons = switch ($Buttons) {
        'OK'          { @('BtnOK') }
        'OKCancel'    { @('BtnOK', 'BtnCancel') }
        'YesNo'       { @('BtnYes', 'BtnNo') }
        'YesNoCancel' { @('BtnYes', 'BtnNo', 'BtnCancel') }
    }

    foreach ($buttonName in @(
        'BtnYes',
        'BtnNo',
        'BtnOK',
        'BtnCancel'
    )) {
        $controls[$buttonName].Visibility =
            if ($buttonName -in $visibleButtons) {
                [System.Windows.Visibility]::Visible
            }
            else {
                [System.Windows.Visibility]::Collapsed
            }
    }

    $primaryButton = if ('BtnYes' -in $visibleButtons) { 'BtnYes' }
    else { 'BtnOK' }

    $controls[$primaryButton].IsDefault = $true

    if ('BtnCancel' -in $visibleButtons) { $controls.BtnCancel.IsCancel = $true }
    elseif ('BtnNo' -in $visibleButtons) { $controls.BtnNo.IsCancel = $true }

    $state = [pscustomobject]@{ Choice = $null }

    $closeWith = {
        param(
            [string]$Choice,
            [Nullable[bool]]$DialogResult
        )

        $state.Choice = $Choice
        $window.DialogResult = $DialogResult
    }

    $controls.BtnYes.Add_Click({ & $closeWith 'Yes' $true })
    $controls.BtnOK.Add_Click({ & $closeWith 'OK' $true })
    $controls.BtnNo.Add_Click({ & $closeWith 'No' $false })
    $controls.BtnCancel.Add_Click({ & $closeWith 'Cancel' $false })
    $controls.BtnClose.Add_Click({
        $state.Choice = if ('BtnCancel' -in $visibleButtons) { 'Cancel' }
        elseif ('BtnNo' -in $visibleButtons) { 'No' }
        else { 'None' }
        $window.Close()
    })

    $controls.TitleBarPanel.Add_MouseLeftButtonDown({
        param($senderObj, $eventObj)
        if ($eventObj.ButtonState -eq [System.Windows.Input.MouseButtonState]::Pressed ) {
            $window.DragMove()
        }
    })

    [void]$window.ShowDialog()

    return $state.Choice
}

function script:RunElevatedCommandScript {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Path
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        $script:logmsg=@("Failed executing following script:","$($Path)",`
        "Function script:RunElevatedCommandScript failed with the following reason:","File not found!")
        $null = wintwincore.WriteLogmsg -Logfile $script:app.logfile -Message $script:logmsg -Flag "FAIL"
        script:Show-RuntimeError -errortext "Function script:RunElevatedCommandScript failed!`nFollowing file could not be found:`n$($Path)" -exitapp
    }

    $resolvedPath = (Resolve-Path -LiteralPath $Path).ProviderPath
    $workingDirectory = Split-Path -Path $resolvedPath -Parent
    $cmdExe = Join-Path $env:SystemRoot 'System32\cmd.exe'

    if (-not (Test-Path -LiteralPath $cmdExe -PathType Leaf)) {
        $script:logmsg=@("Following file could not be found:","$($cmdExe)",`
        "Function script:RunElevatedCommandScript failed!")
        $null = wintwincore.WriteLogmsg -Logfile $script:app.logfile -Message $script:logmsg -Flag "FAIL"
        script:Show-RuntimeError -errortext "Function script:RunElevatedCommandScript failed!`nFollowing file could not be found:`n$($cmdExe)" -exitapp
    }

    # /d: AutoRun-Einträge deaktivieren
    # /s: definierte Verarbeitung der äußeren Anführungszeichen
    # /c: Skript ausführen und cmd.exe danach beenden
    # Alternativ (lässt die Konsole geöffnet):
    # $arguments = '/d /s /k ""{0}""' -f $resolvedPath
    $arguments = '/d /s /c ""{0}""' -f $resolvedPath

    $process = Start-Process `
        -FilePath $cmdExe `
        -ArgumentList $arguments `
        -WorkingDirectory $workingDirectory `
        -Verb RunAs `
        -WindowStyle Normal `
        -PassThru `
        -ErrorAction Stop

    if ($null -eq $process) {
        $script:logmsg=@("Function script:RunElevatedCommandScript failed with the following reason:",`
        "Start-Process Event did not return a process object!")
        $null = wintwincore.WriteLogmsg -Logfile $script:app.logfile -Message $script:logmsg -Flag "FAIL"
        script:Show-RuntimeError -errortext "Function script:RunElevatedCommandScript failed!`nStart-Process Event did not return a process object!" -exitapp
    }

    Start-Sleep -Milliseconds 750
    $process.Refresh()

    return [pscustomobject]@{
        Process      = $process
        ProcessId    = $process.Id
        HasExited    = $process.HasExited
        ScriptPath   = $resolvedPath
        Executable   = $cmdExe
        Arguments    = $arguments
        WorkingPath  = $workingDirectory
    }
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

# Browse for ZIP-File was clicked
$script:app.control.BtnZIPLocation.Add_Click({
    # Keep the old input
    $local:oldinput = $script:app.control.TxtZIPlocation.Text
    # Clear the input field
    $script:app.control.TxtZIPlocation.Clear()
    # Show the Dialog
    $local:pickfile = xuiSelectFile -Title 'Where is the ZIP-File?' -Filter '*.zip'
    # Set the new/old path to the input field
    if ($local:pickfile.code -eq 0) {
        $script:app.control.TxtZIPlocation.Text = $local:pickfile.data.Path
    } else {
        $script:app.control.TxtZIPlocation.Text = $local:oldinput
    }
})

# ISO Location was clicked
$script:app.control.BtnISOLocation.Add_Click({
    # Keep the old input
    $local:oldinput = $script:app.control.TxtISOlocation.Text
    # Clear the input field
    $script:app.control.TxtISOlocation.Clear()
    # Show the Dialog
    $local:pickfolder = xuiSelectFolder -Title 'Where do you want to store the ISO File?'
    # Set the new/old path to the input field
    if ($local:pickfolder.code -eq 0) {
        $script:app.control.TxtISOlocation.Text = $local:pickfolder.data.Path
    } else {
        $script:app.control.TxtISOlocation.Text = $local:oldinput
    }
})

# Exit was clicked
$script:app.control.BtnExitApp.Add_Click({
    $script:app.window.Close()
})

# Download ISO was clicked
$script:app.control.BtnCreateISO.Add_Click({
    # Disable the action buttons
    $script:app.control.BtnCreateISO.IsEnabled = $false
    $script:app.control.BtnExitApp.IsEnabled   = $false
    script:uiEvent

    $script:logmsg=@("'$($script:app.control.BtnCreateISO.Content)'-Button was pressed.")
    $null = wintwincore.WriteLogmsg -Logfile $script:app.logfile -Message $script:logmsg -Flag "INFO"
    
    # reset the error indication (if any)
    $script:app.control.TxtZIPlocation.Background  = $script:app.style.LabelDefaultBack
    $script:app.control.TxtZIPlocation.BorderBrush = $script:app.style.LabelDefaultBrdr
    $script:app.control.TxtISOlocation.Background  = $script:app.style.LabelDefaultBack
    $script:app.control.TxtISOlocation.BorderBrush = $script:app.style.LabelDefaultBrdr
    $script:app.control.TxtISOFilename.Background  = $script:app.style.LabelDefaultBack
    $script:app.control.TxtISOFilename.BorderBrush = $script:app.style.LabelDefaultBrdr

    $local:zipfile = $null
    $local:isopath = $null
    $local:isofile = $null
    $local:isofull = $null
    $local:errorcount = 0

    if ( [string]::IsNullOrWhiteSpace($script:app.control.TxtZIPLocation.Text) ) {
        $local:errorcount++
        $script:app.control.TxtZIPLocation.Background  = $script:app.style.InputErrorBack
        $script:app.control.TxtZIPLocation.BorderBrush = $script:app.style.InputErrorBrdr
        script:uiEvent
    }
    elseif ( -not (Test-Path -LiteralPath $script:app.control.TxtZIPLocation.Text -PathType Leaf) ) {
        $local:errorcount++
        $script:app.control.TxtZIPLocation.Background  = $script:app.style.InputErrorBack
        $script:app.control.TxtZIPLocation.BorderBrush = $script:app.style.InputErrorBrdr
        script:uiEvent
    }    
    else {
        $local:zipfile = $script:app.control.TxtZIPLocation.Text
    }

    if ( [string]::IsNullOrWhiteSpace($script:app.control.TxtISOlocation.Text) ) {
        $local:errorcount++
        $script:app.control.TxtISOlocation.Background  = $script:app.style.InputErrorBack
        $script:app.control.TxtISOlocation.BorderBrush = $script:app.style.InputErrorBrdr
        script:uiEvent
    }
    elseif ( -not (Test-Path -LiteralPath $script:app.control.TxtISOlocation.Text -PathType Container) ) {
        $local:errorcount++
        $script:app.control.TxtISOlocation.Background  = $script:app.style.InputErrorBack
        $script:app.control.TxtISOlocation.BorderBrush = $script:app.style.InputErrorBrdr
        script:uiEvent
    }    
    else {
        $local:isopath = $script:app.control.TxtISOlocation.Text
    }

    if ( [string]::IsNullOrWhiteSpace($script:app.control.TxtISOFilename.Text) ) {
        $local:errorcount++
        $script:app.control.TxtISOFilename.Background  = $script:app.style.InputErrorBack
        $script:app.control.TxtISOFilename.BorderBrush = $script:app.style.InputErrorBrdr
        script:uiEvent
    }
    else {
        # We need to perform some additional checks, if the input isn't empty
        # Filename must be at least 8 characters (like 'Test.iso')
        if ($script:app.control.TxtISOFilename.Text.Length -lt 8) {
            $local:errorcount++
            $script:app.control.TxtISOFilename.Background  = $script:app.style.InputErrorBack
            $script:app.control.TxtISOFilename.BorderBrush = $script:app.style.InputErrorBrdr
            script:uiEvent
        }
        else {
            if ( $script:app.control.TxtISOFilename.Text.Substring($script:app.control.TxtISOFilename.Text.Length - 4) -ne ".iso") {
                $local:errorcount++
                $script:app.control.TxtISOFilename.Background  = $script:app.style.InputErrorBack
                $script:app.control.TxtISOFilename.BorderBrush = $script:app.style.InputErrorBrdr
                script:uiEvent
            }
            else { $local:isofile = $script:app.control.TxtISOFilename.Text }
        }
    }

    if (-not ([string]::IsNullOrWhiteSpace($script:app.control.TxtISOlocation.Text)) -and -not ([string]::IsNullOrWhiteSpace($script:app.control.TxtISOFilename.Text))) {
        $local:isofull = Join-Path $local:isopath $local:isofile -ErrorAction SilentlyContinue
        if ( Test-Path -LiteralPath $local:isofull -PathType Leaf ) {
            $local:errorcount++
            $script:app.control.TxtISOlocation.Background  = $script:app.style.InputErrorBack
            $script:app.control.TxtISOlocation.BorderBrush = $script:app.style.InputErrorBrdr
            $script:app.control.TxtISOFilename.Background  = $script:app.style.InputErrorBack
            $script:app.control.TxtISOFilename.BorderBrush = $script:app.style.InputErrorBrdr
        }
    }

    if ( $local:errorcount -ge 1 ) {
        # Release the action buttons again
        $script:app.control.BtnCreateISO.IsEnabled = $true
        $script:app.control.BtnExitApp.IsEnabled   = $true
        $script:logmsg=@("$($local:errorcount) errors found in the form. Cannot continue creating an ISO!")
        $null = wintwincore.WriteLogmsg -Logfile $script:app.logfile -Message $script:logmsg -Flag "WARN"
        return $false
    }

    $script:logmsg=@("No errors found. We can continue creating the ISO!","Extracting ZIP-Archive now.")
    $null = wintwincore.WriteLogmsg -Logfile $script:app.logfile -Message $script:logmsg -Flag "OKAY"

    # VERY IMPORTANT!
    <#
    In principle, UUPD.Composer would normally launch "uup_download_windows.cmd" using WTF.Console
    (either via a generated script or directly). However, the situation is this: WTF.Console is
    designed to launch a *single* process invisibly and redirect its I/O stream. If that process
    restarts itself or launches another process before terminating, WTF.Console runs into a
    problem because it wouldn't detect this simply by reading the I/O stream. Consequently, we
    cannot pass uup_download_windows.cmd directly to WTF.Console. An earlier approach involved
    UUPD.Composer creating a script that internally called wintwincore.CreateUUPiso. The issue
    here, however, is that while wintwincore.CreateUUPiso can successfully launch
    uup_download_windows.cmd, it does so in its own separate process—and that process redirects
    all console output to a file. So, even if (!!) WTF.Console were aware of exactly what
    wintwincore.CreateUUPiso was doing, it still wouldn't be able to read the console output,
    as that output ends up in a file.

    The only way to proceed at this point without significant effort is for UUPD.Composer to
    locate uup_download_windows.cmd in the directory where the ZIP archive was extracted.
    UUPD.Composer then launches uup_download_windows.cmd in its own separate process with
    elevated privileges. The only problem here is the lack of actual process monitoring; we
    can simply launch uup_download_windows.cmd, exit UUPD.Composer, and hope everything
    runs as intended. ATM WinTwin.Fusion has no possibility to monitor that process!!
    #>

    # Try to extract the ZIP-Acrchive to the provided path
    $script:result = wintwincore.ExtractUUPDump `
    -ZIPfile "$($local:zipfile)" `
    -Target  "$($local:isopath)" `
    -Verify  1 -Cleanup 0
    if ($script:result.code -ne 0) {
        $script:logmsg=@("$($script:app.name) failed extracting ZIP-Archive!",`
        "Function wintwincore.ExtractUUPDump failed with the following reason:","$($script:result.msg)")
        $null = wintwincore.WriteLogmsg -Logfile $script:app.logfile -Message $script:logmsg -Flag "OKAY"
        # Error Dialog
        $null = wintwincore.SystemMessageBox -smbTitle $script:errorhead `
        -smbText "Failed extracting the ZIP archive.`nPlease check the logfile for more informations."
        -smbIcon Warning -smbButtons OK
        # Release the action buttons again
        $script:app.control.BtnCreateISO.IsEnabled = $true
        $script:app.control.BtnExitApp.IsEnabled   = $true
        return $false
    }

    $script:logmsg=@("ZIP Archive successfully extracted.", "ZIP Archive:  $($local:zipfile)", "Output Path:  $($local:isopath)")
    $null = wintwincore.WriteLogmsg -Logfile $script:app.logfile -Message $script:logmsg -Flag "OKAY"
    # Now that the ZIP Archive could be extracted, we need to find 'uup_download_windows.cmd'

    $local:uupCommand = Get-ChildItem `
    -LiteralPath $local:isopath `
    -Filter "$($script:app.script.file)" `
    -File `
    -Recurse `
    -ErrorAction Stop |
    Select-Object -First 1

    if ($null -eq $local:uupCommand) {
        $script:logmsg=@("The ZIP Archive could be extrated. But the required script file could not be found!",`
        "Missing Script File:  $($script:app.script.file)","Lookup Directory:     $($local:isopath)",
        "$($script:app.name) cannot continue without this file!")
        $null = wintwincore.WriteLogmsg -Logfile $script:app.logfile -Message $script:logmsg -Flag "FAIL"
        # Error Dialog
        $null = wintwincore.SystemMessageBox -smbTitle $script:errorhead `
        -smbText "Required Script File  '$($script:app.script.file)'  not found!`nPlease check the logfile for more informations."
        -smbIcon Warning -smbButtons OK
        # Release the action buttons again
        $script:app.control.BtnCreateISO.IsEnabled = $true
        $script:app.control.BtnExitApp.IsEnabled   = $true
        return $false
    }

    $script:app.script.file = $local:uupCommand.FullName

    $script:logmsg=@("Required UUP Command Script was found in $($local:isopath)",`
    "Script:     $($script:app.script.file)","Directory:  $($local:uupCommand.DirectoryName)")
    $null = wintwincore.WriteLogmsg -Logfile $script:app.logfile -Message $script:logmsg -Flag "OKAY"

    # Use the magic.window to display a Dialog Window
    $local:dialogChoice = script:ShowMagicWindow `
        -Info `
        -Buttons YesNo `
        -Title "$($script:app.name)  ($($script:app.toolbox))" `
        -Message (
        "The UUP dump script is launched in a separate console window " +
        "with administrator privileges.`n`n" +
        "UUPD.Compose cannot monitor the subsequent process. " +
        "The console window must not be closed while the download " +
        "and ISO creation are in progress.`n`n" +
        "If no ISO is created, the current process chain remains " +
        "interrupted, and the framework cannot automatically " +
        "resume this task.`n`n" +
        "Do you want to continue?"
        ) `
    -Owner $script:app.window

    # We will only react, if the user decided NOT to run UUPD
    if ($local:dialogChoice -ne 'Yes') {
        $script:logmsg = @("The user declined launching the external UUP Command Process.",`
        "Dialog result: $($local:dialogChoice)","UUPD.Compose will now close without creating the ISO.")
        $null = wintwincore.WriteLogmsg -Logfile $script:app.logfile -Message $script:logmsg -Flag "WARN"

        $null = script:ShowMagicWindow `
            -Warning `
            -Buttons OK `
            -Title "$($script:app.name)  ($($script:app.toolbox))" `
            -Message (
            "The external UUP dump process is not being started.\n\n" +
            "No ISO file will be created by this job. " +
            "UUPD.Compose is now terminating."
            ) `
        -Owner $script:app.window

        $script:app.window.Close()
        return
    }

    # Looks like User wants to proceed. So we do NOT use WTF.Console (currently ... hopefully)!
    # We're trying to launch the process directly with elevated rights!
    $script:logmsg=@("$($script:app.name) is now passing over to WTF.Console using following script:","$($script:wintwin.console)")
    $null = wintwincore.WriteLogmsg -Logfile $script:app.logfile -Message $script:logmsg -Flag "INFO"
    
    # LAUNCH UUP COMMAND PROCESS WITH ELEVATED RIGHTS!
    try {
        $local:externalLaunch = script:Start-ElevatedCommandScript `
        -Path $script:app.script.file
    }
    catch {
        $local:wasCanceled = ($_.Exception.PSObject.Properties['NativeErrorCode'] -and $_.Exception.NativeErrorCode -eq 1223 )

        $local:errorText = if ($local:wasCanceled) {
            'The administrator request was cancelled by the user.'
        }
        else {
            $_.Exception.Message
        }

        $script:logmsg = @(
        "The external UUP command process could not be started.",`
        "Script: $($script:app.script.file)","Reason:","$($local:errorText)")
        $null = wintwincore.WriteLogmsg -Logfile $script:app.logfile -Message $script:logmsg -Flag 'FAIL'

        $null = script:ShowMagicWindow `
            -Error `
            -Buttons OK `
            -Title "$($script:app.name)  ($($script:app.toolbox))" `
            -Message (
            "The UUP dump script could not be started.`n`n" +
            "$local:errorText`n`n" +
            "UUPD.Compose will remain open. You can retry the operation."
            ) `
        -Owner $script:app.window

        $script:app.control.BtnCreateISO.IsEnabled = $true
        $script:app.control.BtnExitApp.IsEnabled = $true
        return
    }
    # Wait for the process ...
    Start-Sleep -Milliseconds 1000

    # CHECK IF UUP COMMAND PROCESS IS STILL ALIVE!
    try {
        if ($local:externalLaunch.HasExited) {
            $local:exitCode = $null

            try { $local:exitCode = $local:externalLaunch.Process.ExitCode }
            catch { $local:exitCode = 'unknown' }

            $script:logmsg = @('The external UUP command process was created but terminated immediately.',`
            "ProcessId: $($local:externalLaunch.ProcessId)","ExitCode: $local:exitCode","Script: $($local:externalLaunch.ScriptPath)")
            $null = wintwincore.WriteLogmsg -Logfile $script:app.logfile -Message $script:logmsg -Flag 'WARN'

            $null = script:ShowMagicWindow `
                -Warning `
                -Buttons OK `
                -Title "$($script:app.name)  ($($script:app.toolbox))" `
                -Message (
                "The external process was started but terminated immediately. " +
                "`n`nExit code: $local:exitCode`n`n" +
                "Please check the console window and the UUP dump directory."
                ) `
            -Owner $script:app.window

            $script:app.control.BtnCreateISO.IsEnabled = $false
            $script:app.control.BtnExitApp.IsEnabled = $true
            return
        }
    }
    catch {
        $script:logmsg = @(
        "Failed to theck wether the UUPD Command Process is (still) alive or not!",`
        "Here is what we know about that error!",`
        "$($_.Exception.Message)",`
        "$($_.InvocationInfo.ScriptName)",`
        "$($_.InvocationInfo.ScriptLineNumber)",`
        "$($_.Exception.Source)",`
        "$($_.Exception.TargetSite)",`
        "$($_.Exception.Message)",`
        "$($_.InvocationInfo.DisplayScriptPosition)",`
        "$($_.InvocationInfo.CommandOrigin)")
        $null = wintwincore.WriteLogmsg -Logfile $script:app.logfile -Message $script:logmsg -Flag 'WARN'
        

        $null = script:ShowMagicWindow `
            -Warning `
            -Buttons OK `
            -Title "$($script:app.name)  ($($script:app.toolbox))" `
            -Message (
            "Failed to theck wether the UUP Command Process is (still) alive or not!`n" +
            "Please check if the UUP Console is still open (and running).`n" +
            "If not, please refer to the logfile for detailed informations.`n`n" +
            "$($script:app.name) is now terminating"
            ) `
        -Owner $script:app.window

        $script:app.control.BtnCreateISO.IsEnabled = $false
        $script:app.control.BtnExitApp.IsEnabled = $true
        return
    }

    $script:logmsg = @(
    "The external UUP command process was successfully created.",`
    "ProcessId: $($local:externalLaunch.ProcessId)",' '
    "Executable: $($local:externalLaunch.Executable)",' '
    "Script: $($local:externalLaunch.ScriptPath)",' '
    "WorkingDirectory: $($local:externalLaunch.WorkingPath)")
    $null = wintwincore.WriteLogmsg -Logfile $script:app.logfile -Message $script:logmsg -Flag 'OKAY'
    $script:logmsg = @("$($script:app.name) will now close.","The external process is no longer monitored by the framework.")
    $null = wintwincore.WriteLogmsg -Logfile $script:app.logfile -Message $script:logmsg -Flag 'WARN'
    $script:logmsg = @("$($script:app.name) is now trying to unregister as current Framework Process.")
    $null = wintwincore.WriteLogmsg -Logfile $script:app.logfile -Message $script:logmsg -Flag 'INFO'

    # Unregister the application before handing over to WTF.Console
    # This is important, because otherwise, WTF.Console will not start!
    $script:unregProcess = wintwincore.UnregisterProcess -FrameworkRoot $script:wintwin.root -ProcessId $($script:ProcessID.Id) -ExitCode 0
    if ( $script:unregProcess.code -ne 0 ) {
        $script:logmsg=@("$($script:app.name) failed to unregister as Framework Process!","$($script:unregProcess.msg)")
        $null = wintwincore.WriteLogmsg -Logfile $script:app.logfile -Message $script:logmsg -Flag "FAIL"
        $script:logmsg=@("The application has finished anyway (even if we did not try to unregister)",`
        "This means it was planned to close the window in any case.",`
        "We will give it a second try in the regular exit/cleanup.",
        "NOTE: `$script:app.process must be 'running' to do so!!")
        $null = wintwincore.WriteLogmsg -Logfile $script:app.logfile -Message $script:logmsg -Flag "INFO"
        # Importand for the clean exit
        $script:app.process = 'running'
        return
    }

    # Finally release the buttons again
    $script:app.control.BtnCreateISO.IsEnabled = $true
    $script:app.control.BtnExitApp.IsEnabled   = $true
    
    # Importand for the clean exit
    $script:app.process = 'handoff'
    
    $script:logmsg=@("$($script:app.name) successfully unregistered as Framework Process.")
    $null = wintwincore.WriteLogmsg -Logfile $script:app.logfile -Message $script:logmsg -Flag "OKAY"

    # DEPRECATED: This point is unattainable
    # Finally release the buttons again
    #$script:app.control.BtnCreateISO.IsEnabled = $true
    #$script:app.control.BtnExitApp.IsEnabled   = $true
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

    $script:logmsg=@("Trying to load job details from $($script:configfile.jobaction)")
    $null = wintwincore.WriteLogmsg -Logfile $script:app.logfile -Message $script:logmsg -Flag "INFO"

    $local:zipfile = "$($script:config.jobaction."uupd-compose".zipfile)"
    $local:isopath = "$($script:config.jobaction."uupd-compose".isopath)"
    $local:isoname = "$($script:config.jobaction."uupd-compose".isoname)"
    
    $script:logmsg=@("Following job details could be retreived:",`
    "zipfile:  $($local:zipfile)","isopath:  $($local:isopath)","isoname:  $($local:isoname)")
    $null = wintwincore.WriteLogmsg -Logfile $script:app.logfile -Message $script:logmsg -Flag "INFO"
    
    $script:logmsg=@("Applying (only) valid job details to the ui.")
    $null = wintwincore.WriteLogmsg -Logfile $script:app.logfile -Message $script:logmsg -Flag "INFO"
    
    if ( $local:zipfile.Contains('{0}') ) { $script:app.control.TxtZIPlocation.Text = "" }
    else { $script:app.control.TxtZIPlocation.Text = "$($local:zipfile)" }

    if ( $local:isopath.Contains('{0}') ) { $script:app.control.TxtISOlocation.Text = "" }
    else { $script:app.control.TxtISOlocation.Text = "$($local:isopath)" }

    if ( $local:zipfile.Contains('{0}') ) { $script:app.control.TxtISOFilename.Text = "" }
    else { $script:app.control.TxtISOFilename.Text = "$($local:isoname)" }
    
    # Push the changes to the ui
    script:uiEvent
})

$script:app.window.ShowDialog() | Out-Null
# Cleanup/Exit
$script:logmsg=@("The Close-Event was triggered. Performing cleanup.")
$null = wintwincore.WriteLogmsg -Logfile $script:app.logfile -Message $script:logmsg -Flag "INFO"
# Unregister before final exit

if ($script:app.process -eq 'running') {
    $script:unregProcess = wintwincore.UnregisterProcess -FrameworkRoot $script:wintwin.root -ProcessId $($script:ProcessID.Id) -ExitCode 0
    if ( $script:unregProcess.code -ne 0 ) {
        $script:logmsg=@("$($script:app.name) failed to unregister as Framework Process!","$($script:unregProcess.msg)")
        $null = wintwincore.WriteLogmsg -Logfile $script:app.logfile -Message $script:logmsg -Flag "FAIL"
    } else {
        $script:logmsg=@("$($script:app.name) successfully unregistered as Framework Process.")
        $null = wintwincore.WriteLogmsg -Logfile $script:app.logfile -Message $script:logmsg -Flag "OKAY"
    }
} else {
    $script:logmsg=@("Looks like $($script:app.name) has already unregistered as Framework Process.","Reason: $($script:app.process)")
    $null = wintwincore.WriteLogmsg -Logfile $script:app.logfile -Message $script:logmsg -Flag "INFO"
}

# Final entry to the logfile
$script:logmsg=@("$($script:app.name) $($script:app.version) was closed.","Thank you for using UUPD.Compose (PS.Tweak.Tools)")
$null = wintwincore.WriteLogmsg -Logfile $script:app.logfile -Message $script:logmsg -Flag "INFO"
# Show the console again
#$null = wintwincore.SetCMDstate -State Show -Focus $false
exit 0


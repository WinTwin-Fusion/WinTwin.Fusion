<#
.SYNOPSIS
    This is the WinTwin.Fusion Installation Manager.
.DESCRIPTION
    The WinTwin.Fusion Installation Manager provides a graphical interface for installing and configuring
    the WinTwin.Fusion Framework. It automatically checks all necessary prerequisites, independently
    adjusts the framework's configurations, and adapts everything so that the WinTwin.Fusion Framework
    can be executed from the current directory.
.NOTES
    CREATOR:    Praetoriani (a.k.a M.Sczepanski)
    WEBSITE:    https://github.com/WinTwin-Fusion/WinTwin.Fusion
    VERSION:    v1.01.06
    CREATED:    29.08.2026
    UPDATED:    02.09.2026
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [ValidateSet("en-us","de-de")]
    [string]$Language = "en-us",

    [Parameter(Mandatory = $false)]
    [switch]$CleanInstall,

    [Parameter(Mandatory = $false)]
    [switch]$SkipAdkInstall,

    [Parameter(Mandatory = $false)]
    [switch]$SkipWinPEInstall
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
$script:errorlist = @()
$script:errorhead = "WinTwin.Fusion - Install Manager"
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
# GLOBAL INSTALLER VARS
# --------------------------------------------------------------------------
$script:setupconfig = [pscustomobject]@{
    xmluiname  = "wintwin.fusion.installer.xml"
    xmlui      = $null
    currentDir = "$(Split-Path -Path $PSCommandPath -Parent)"
    langfile   = "\Core\lang\install-manager.{0}.json"
    logfile    = "$null"
    appname    = "WinTwin.Fusion Install Manager"
    appvers    = "v1.01.05"
    adkexe     = "\AddOns\adksetup.exe"
    peexe      = "\AddOns\adkwinpesetup.exe"
}
# Make sure that the required xml file for the UI can be found!
$script:setupconfig.xmlui = Join-Path "$($script:setupconfig.currentDir)" "$($script:setupconfig.xmluiname)"
if (-not (Test-Path -LiteralPath "$($script:setupconfig.xmlui)")) {
    script:Show-RuntimeError -exitapp "Cannot build XML UI for WinTwin.Fusion Installer Manager.`nMissing XML-File:   $($script:setupconfig.xmluiname)`n`nWinTwin.Fusion Installer Manager is now closing."
}

$script:setupconfig.langfile = Join-Path "$($script:setupconfig.currentDir)" "$($script:setupconfig.langfile)"
$script:setupconfig.logfile  = Join-Path "$($script:setupconfig.currentDir)" "wintwin.fusion.installer.log"

$script:setupconfig.adkexe = Join-Path "$($script:setupconfig.currentDir)" "$($script:setupconfig.adkexe)"
$script:setupconfig.peexe  = Join-Path "$($script:setupconfig.currentDir)" "$($script:setupconfig.peexe)"

# --------------------------------------------------------------------------
# INSTALL MANAGER REQUIREMENT OBJECT
# --------------------------------------------------------------------------

# This object stores all requirements we need to check
$script:requirement = [pscustomobject]@{
    # Define a reference to the required PowerShell Libraries
    wintwinlicense = [pscustomobject]@{
        licensefile = "LICENSE.MD"
        noticefile  = "NOTICE"
        licensehash = "72A7A07E2D5CF61DC40F669A1F368019085E81F557EF63C038B28DC8F70EF8E3794A6941D1039D81D08A87BE90CC59984D3C839D8BD03DCF7F05CF8B52CD0CF4"
        noticehash  = "0EBC8DB2C51A6A9446CAD73CCE8C84A341A4621D80EB5BB20A009EB2FB0263ACE88E26F71BC7AF6226CEEA687E97B0DB9C7B65C4797B264076F420ACE9F47F6E"
    }
    # Define a reference to the required PowerShell Libraries
    directory = [pscustomobject]@{
        lib      = Join-Path "$($script:setupconfig.currentDir)" "\Lib"
        lang     = Join-Path "$($script:setupconfig.currentDir)" "\Core\lang"
        logs     = Join-Path "$($script:setupconfig.currentDir)" "\Core\logs"
        ui       = Join-Path "$($script:setupconfig.currentDir)" "\Core\ui"
        fonts    = Join-Path "$($script:setupconfig.currentDir)" "\Core\fonts"
        export   = Join-Path "$($script:setupconfig.currentDir)" "\Core\export"
        addons   = Join-Path "$($script:setupconfig.currentDir)" "\AddOns"
        drivers  = Join-Path "$($script:setupconfig.currentDir)" "\Drivers"
        mountdir = Join-Path "$($script:setupconfig.currentDir)" "\Mount"
        msstore  = Join-Path "$($script:setupconfig.currentDir)" "\MSStore"
        output   = Join-Path "$($script:setupconfig.currentDir)" "\Output"
        winmenu  = Join-Path "$($script:setupconfig.currentDir)" "\Profile.Backup\Startmenu"
        wintbar  = Join-Path "$($script:setupconfig.currentDir)" "\Profile.Backup\Taskbar"
        rawiso   = Join-Path "$($script:setupconfig.currentDir)" "\RawISO"
        userdata = Join-Path "$($script:setupconfig.currentDir)" "\UserData"
    }
    # Define a reference to the required JSON-Files
    apptools = [pscustomobject]@{
        framework = Join-Path "$($script:setupconfig.currentDir)" "\DISM.UI.CC"
        processdb = Join-Path "$($script:setupconfig.currentDir)" "\PS.Tweak.Tools"
        workflows = Join-Path "$($script:setupconfig.currentDir)" "\USMT.Composer"
    }
    # Define a reference to the required JSON-Files
    configfile = [pscustomobject]@{
        framework = Join-Path "$($script:setupconfig.currentDir)" "\Core\config.json"
        processdb = Join-Path "$($script:setupconfig.currentDir)" "\Core\db\process.json"
        workflows = Join-Path "$($script:setupconfig.currentDir)" "\Core\db\workflow.json"
        jobaction = Join-Path "$($script:setupconfig.currentDir)" "\Core\db\jobaction.json"
    }
    # Define a reference to the required PowerShell Libraries
    applibrary = [pscustomobject]@{
        opsreturn = Join-Path "$($script:setupconfig.currentDir)" "\Lib\OPSreturn\OPSreturn.psd1"
        wtfxcore  = Join-Path "$($script:setupconfig.currentDir)" "\Lib\WinTwin.FXcore\WinTwin.FXcore.psd1"
        wtxui     = Join-Path "$($script:setupconfig.currentDir)" "\Lib\WinTwin.XUI\wintwin.xui.psd1"
        psappcore = Join-Path "$($script:setupconfig.currentDir)" "\Lib\PSAppCoreLib\PSAppCoreLib.psd1"
        vpdlx     = Join-Path "$($script:setupconfig.currentDir)" "\Lib\VPDLX\VPDLX.psd1"
    }
}

# --------------------------------------------------------------------------
# INSTALL MANAGER CHECKLIST
# The script:checklist object essentially functions as a checklist. Each
# element of the script:checklist represents a check performed by the
# Install Manager. Any issues or errors encountered are recorded via the
# script:Add-Error function, and the script:checklist stores whether the
# check was successfully completed.
# IMPORTANT: script:checklist does not store the specific results of a
# performed check. It only stores whether the check was performed or not.
# --------------------------------------------------------------------------
$script:checklist = [pscustomobject]@{
    iselevated     = $false     # <-  Checks for elevated rights
    rootdirfound   = $false     # <-  $true if root directory found
    verifylicense  = $false     # <-  License integrity checks
    hasallfolders  = $false     # <-  Check the folder structure (not the content!)
    alltoolsfound  = $false     # <-  Checks the diretory of each tool (e.g. PS.Tweak.Tools)
    jsonfilesfound = $false     # <-  Looks for the core JSON-files (e.g. config.json)
    librariesfound = $false     # <-  Checks if all PowerShell Libraries could be found
    coreconfigdone = $false     # <-  $true if config.json has been configured
    jobsconfigured = $false     # <-  $true if jobaction.json has been configured
    processdbdone  = $false     # <-  $true if process.json has been configured
    workflowsdone  = $false     # <-  $true if workflows.json has been configured
    iswindows11    = $false     # <-  Checks for Windows 11 (24H2/25H2)
    isdismworking  = $false     # <-  Checks if DISM is installed and working
    haswindowsadk  = $false     # <-  Checks for Windows ADK (can be silently installed if not found)
    hasadkpeaddon  = $false     # <-  Checks for Windows ADK (PE AddOn) (can be silently installed if not found)
    fondsinstalled = $false     # <-  Installs all required fonts
    finalcheckup   = $false     # <-  $true if the final checkup has been performet
    wintwinready   = $false     # <-  $true if all requrirements are fullfilled
}

# --------------------------------------------------------------------------
# PRE-LOADIND STAGE
# Since we are already familiar with the script directory, we can take
# a step ahead and immediately determine whether the libraries are
# available. If they are, we can tick off one check; as a bonus, we can
# give the Install Manager a significant boost by loading the  libraries.
# --------------------------------------------------------------------------

# 1st Step: We're going to verify that all library files exists
foreach ($prop in $script:requirement.applibrary.psobject.Properties) {
    if (-not (Test-Path -LiteralPath $prop.Value -PathType Leaf)) {
        script:Add-Error "$($prop.Value) not found!"
    }
}
# 2nd Step: Try to import the libraries one by one (counting errors)
if ( $script:errorlist.Count -eq 0) {
    $importOK = 0
    foreach ($prop in $script:requirement.applibrary.psobject.Properties) {
        try {
            Import-Module $prop.Value -Force -ErrorAction Stop
            $importOK++
        }
        catch {
            $libName = [string]$($prop.Name).ToUpper()
            Show-RuntimeError -exitapp "Failed loading internal Framework Library  $($libName)!"
        }
    }
    # Only if all libraries could be loaded
    if ( $importOK -eq 5) {
        #$script:checklist.librariesfound = $true
        Write-Host "Following Libraries were successfully loaded" -ForegroundColor Gray
        foreach ($prop in $script:requirement.applibrary.psobject.Properties) {
        Write-Host "$($prop.Value)" -ForegroundColor DarkGreen
        }
    }
}

# Now we're all set. We can now use the framework-internal
# libraries including all of their provided functions :)
$script:logmsg=@("$($script:setupconfig.appname) successfully initialized.")
$null = wintwincore.WriteLogmsg -Logfile $script:setupconfig.logfile -Message $script:logmsg -Flag "INFO" -Override 1

#--------------------------------------------------------------------------------
# Hide Console Window -> Using Function from WinTwin.FXcore
# -> We can use wintwincore.SystemMessageBox to display Error-Messages!
#--------------------------------------------------------------------------------
$null = wintwincore.SetCMDstate -State Hide

#--------------------------------------------------------------------------------
# Load/Create the Window
# In this section, the UI is loaded from the XML file, the window is created,
# and all UI elements are referenced. Everything will be stored in $script:app
#--------------------------------------------------------------------------------
$script:app = [pscustomobject]@{
    window  = $null
    control = $null
}
# The -extended switch returns the window object including the referenced controls
$script:LoadXML = xuiLoadWindow -XMLfile $script:setupconfig.xmlui -extended
if ($script:LoadXML.code -ne 0) {
    $null = wintwincore.SystemMessageBox -smbTitle $script:errorhead `
    -smbText "Faild loading User Interface:`n$($script:setupconfig.xmlui)`n$($script:LoadXML.message)" `
    -smbIcon Error -smbButtons OK
    exit 1
}
# Write a new entry into the logfile
$script:logmsg=@("User Interface successfully loaded.","$($script:setupconfig.xmlui)")
$null = wintwincore.WriteLogmsg -Logfile $script:setupconfig.logfile -Message $script:logmsg -Flag "INFO"
# Store the window and all controls inside the window
$script:app.window  = $script:LoadXML.data.Window
$script:app.control = $script:LoadXML.data.Controls

#--------------------------------------------------------------------------------
# Load Language-File for the Install Manager
#--------------------------------------------------------------------------------
$Language = $Language.ToString().ToLower()
$script:setupconfig.langfile = $script:setupconfig.langfile -f $Language

$script:result = wintwincore.LoadJSON -Path $script:setupconfig.langfile
if ($script:result.code -ne 0) {
    $null = wintwincore.SystemMessageBox -smbTitle $script:errorhead `
    -smbText "Faild loading language package:`n$($script:setupconfig.langfile)`n$($script:result.message)"
    -smbIcon Error -smbButtons OK
    exit 1
}
# Write a new entry into the logfile
$script:logmsg=@("Language file successfully loaded.","$($script:setupconfig.langfile)")
$null = wintwincore.WriteLogmsg -Logfile $script:setupconfig.logfile -Message $script:logmsg -Flag "INFO"
# Store the content of the language file
$script:apptxt = $script:result.data

#--------------------------------------------------------------------------------
# Load the text from the language file into the ui of the window
#--------------------------------------------------------------------------------
$script:app.control.LblWelcome.Text        = $script:apptxt.ui.HeaderText
$script:app.control.LblSetupInfo.Text      = $script:apptxt.ui.WelcomeText
$script:app.control.Lbliselevated.Text     = $script:apptxt.ui.CBiselevated
$script:app.control.Lbliswindows11.Text    = $script:apptxt.ui.CBiswindows11
$script:app.control.Lblisdismworking.Text  = $script:apptxt.ui.CBisdismworking
$script:app.control.Lblhaswindowsadk.Text  = $script:apptxt.ui.CBhaswindowsadk
$script:app.control.Lblhasadkpeaddon.Text  = $script:apptxt.ui.CBhasadkpeaddon
$script:app.control.Lblrootdirfound.Text   = $script:apptxt.ui.CBrootdirfound
$script:app.control.Lblverifylicense.Text  = $script:apptxt.ui.CBverifylicense
$script:app.control.Lblhasallfolders.Text  = $script:apptxt.ui.CBhasallfolders
$script:app.control.Lblalltoolsfound.Text  = $script:apptxt.ui.CBalltoolsfound
$script:app.control.Lbljsonfilesfound.Text = $script:apptxt.ui.CBjsonfilesfound
$script:app.control.Lbllibrariesfound.Text = $script:apptxt.ui.CBlibrariesfound
$script:app.control.Lblcoreconfigdone.Text = $script:apptxt.ui.CBcoreconfigdone
$script:app.control.Lbljobsconfigured.Text = $script:apptxt.ui.CBjobsconfigured
$script:app.control.Lblprocessdbdone.Text  = $script:apptxt.ui.CBprocessdbdone
$script:app.control.Lblworkflowsdone.Text  = $script:apptxt.ui.CBworkflowsdone
$script:app.control.Lblfontsinstalled.Text = $script:apptxt.ui.CBfondsinstalled
$script:app.control.Lblfinalcheckup.Text   = $script:apptxt.ui.CBfinalcheckup
$script:app.control.Lblwintwinready.Text   = $script:apptxt.ui.CBwintwinready

# Due to the instruction text includes placeholders, we need to replace them first
$script:apptxt.ui.InsctructionText = $script:apptxt.ui.InsctructionText -f `
$script:apptxt.ui.ButtonRunSetup, $script:apptxt.ui.ButtonClose, $script:apptxt.ui.ButtonCleanSetup
$script:app.control.LblInstallHint.Text   = $script:apptxt.ui.InsctructionText

$script:app.control.BtnInstall.Content    = $script:apptxt.ui.ButtonRunSetup
$script:app.control.BtnCancel.Content     = $script:apptxt.ui.ButtonClose
$script:app.control.BtnCleanSetup.Content = $script:apptxt.ui.ButtonCleanSetup

# Short configuration of BtnCleanSetup. It'll only be activated with the -CleanInstall Switch
if ($CleanInstall.IsPresent) { $script:app.control.BtnCleanSetup.IsEnabled = $true }
else { $script:app.control.BtnCleanSetup.IsEnabled = $false }

$script:app.control.StatusText.Text   = $script:apptxt.status.ready
$script:app.control.StatusInfo.Text   = "$($script:setupconfig.appname) ($($script:setupconfig.appvers))"

# Due to our checkboxes have 3 states, we initialy need to reset them
$statusCheckBoxes = @(
    'CBiselevated'
    'CBiswindows11'
    'CBisdismworking'
    'CBhaswindowsadk'
    'CBhasadkpeaddon'
    'CBrootdirfound'
    'CBverifylicense'
    'CBhasallfolders'
    'CBalltoolsfound'
    'CBjsonfilesfound'
    'CBlibrariesfound'
    'CBcoreconfigdone'
    'CBjobsconfigured'
    'CBprocessdbdone'
    'CBworkflowsdone'
    'CBfontsinstalled'
    'CBfinalcheckup'
    'CBwintwinready'
)

foreach ($controlName in $statusCheckBoxes) {
    $script:app.control[$controlName].IsChecked = $null
}

#--------------------------------------------------------------------------------
# Internal Functions for WinTwin.Fusion Install Manager
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

function script:SetStatusUpdate {
    <#
    .SYNOPSIS
        Updates the installation progress bar based on the current step.

    .DESCRIPTION
        Maps a step number (0-18) to a progress percentage and applies it
        to the PrgInstallation control. Step 0 resets the bar, step 18
        completes it, and every step in between advances it proportionally.

    .NOTES
        The original implementation referenced an undefined variable ($x)
        instead of $StepCount, which threw an exception under
        Set-StrictMode and prevented the progress bar from updating. The
        step range was also corrected to cover step 17.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [ValidateRange(0, 18)]
        [int]$StepCount
    )

    if ($StepCount -eq 0) {
        # Reset the progress bar to 0
        $script:app.control.PrgInstallation.Value = 0
    }
    elseif ($StepCount -ge 1 -and $StepCount -le 17) {
        # Calculate the progress level for the current step
        $result = [math]::Truncate(((100 / 18) * $StepCount) * 10) / 10
        $script:app.control.PrgInstallation.Value = $result
    }
    elseif ($StepCount -eq 18) {
        # Finish the progress bar
        $script:app.control.PrgInstallation.Value = 100
    }

    # Render the change immediately so the user sees live progress
    script:uiEvent
}

function script:CheckElevatedRights {
    [CmdletBinding()]
    [OutputType([bool])]
    param()

    try {
        $currentIdentity = [Security.Principal.WindowsIdentity]::GetCurrent()

        if (-not $currentIdentity) {
            return $false
        }

        $principal = New-Object Security.Principal.WindowsPrincipal($currentIdentity)

        return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    }
    catch {
        #Write-Verbose "Fehler bei der Ermittlung der Berechtigungen: $_"
        $null = wintwincore.SystemMessageBox -smbTitle $script:errorhead `
        -smbText "Function script:CheckElevatedRights failed with following error:`n$($_.Exception.Message)" `
        -smbIcon Warning -smbButtons OK
        return $false
    }
}


function script:CheckDISM {
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [int]$TimeoutSeconds = 30
    )

    try {
        # DISM.exe finden
        $dismPath = (Get-Command dism.exe -ErrorAction Stop).Source

        if (-not (Test-Path -LiteralPath $dismPath)) {
            return $false
        }

        # Funktionsprüfung: schneller, lesender DISM-Aufruf
        $process = Start-Process `
            -FilePath $dismPath `
            -ArgumentList '/Online','/Get-CurrentEdition' `
            -NoNewWindow `
            -Wait:$false `
            -PassThru

        if (-not $process.WaitForExit($TimeoutSeconds * 1000)) {
            try { $process.Kill() } catch {}
            return $false
        }

        # Erfolgreicher ExitCode = DISM funktioniert
        if ($process.ExitCode -eq 0) {
            return $true
        }

        return $false
    }
    catch {
        $script:logmsg=@("$($Script:apptxt.error.dismcheck)","$($_)")
        $null = wintwincore.WriteLogmsg -Logfile $script:setupconfig.logfile -Message $script:logmsg -Flag "OKAY"
        return $false
    }
}

#--------------------------------------------------------------------------------
# Helper-Functions for the UI-Events
#--------------------------------------------------------------------------------

# Mnimizes the window
$script:app.control.BtnMinimize.Add_Click({
    $script:app.window.WindowState = [System.Windows.WindowState]::Minimized
})

# Closes the window
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

# Action-Button: Run Installation  ->  This is where all the "magic" happens ;)
$script:app.control.BtnInstall.Add_Click({
    $script:logmsg=@("Button '$($script:app.control.BtnInstall.Content)' was clicked.")
    $null = wintwincore.WriteLogmsg -Logfile $script:setupconfig.logfile -Message $script:logmsg -Flag "OKAY"
    $script:logmsg=@("Starting $($script:setupconfig.appname) ($($script:setupconfig.appvers))",`
    "$($script:setupconfig.appname) is running in following directory:",`
    "$($($script:setupconfig.currentDir))")
    $null = wintwincore.WriteLogmsg -Logfile $script:setupconfig.logfile -Message $script:logmsg -Flag "INFO"

    # Let's start the setup/configuration
    $script:app.control.BtnInstall.IsEnabled = $false
    $script:app.control.BtnCancel.IsEnabled  = $false
    # Check No. 01: elevated rights
    $script:app.control.StatusText.Text = $script:apptxt.status.task01
    script:uiEvent
    if (-not (script:CheckElevatedRights)) {
        $null = wintwincore.SystemMessageBox -smbTitle $script:errorhead `
        -smbText "$($script:apptxt.error.noadminpopup)" `
        -smbIcon Warning -smbButtons OK
        $script:app.control.CBiselevated.IsChecked = $false
        $script:app.control.StatusText.Text = "$($script:apptxt.status.taskfail -f $script:apptxt.error.noadminstatus)"
        $script:app.control.BtnInstall.IsEnabled = $true
        $script:app.control.BtnCancel.IsEnabled  = $true
        return $false # We cannot perform any further checks without admin rights
    } else {
        $script:app.control.CBiselevated.IsChecked = $true
        script:SetStatusUpdate -StepCount 1
    }
    script:uiEvent

    # Check No. 02: check supported Windows versions (Win11 24H2/25H2)
    $script:app.control.StatusText.Text = $script:apptxt.status.task02
    script:uiEvent
    # Try to get informations about the current system
    $script:result = wintwincore.GetWinVersion
    if ($script:result.code -eq 0) { $script:result = $script:result.data }
    else {
        $script:logmsg=@("Function wintwincore.GetWinVersion failed!","Exit Code: $($script:result.code)","Message:  $($script:result.message)")
        $null = wintwincore.WriteLogmsg -Logfile $script:setupconfig.logfile -Message $script:logmsg -Flag "ERROR"
        $script:app.control.CBiswindows11.IsChecked = $false
        $script:app.control.StatusText.Text = "$($script:apptxt.status.taskfail -f "$($script:apptxt.error.scanonfail)")"
        $script:app.control.BtnInstall.IsEnabled = $true
        $script:app.control.BtnCancel.IsEnabled  = $true
        return $false # Same here: no need to continue if the current system is not supported!
    }

    $script:logmsg=@("Function wintwincore.GetWinVersion successfully finished!",`
    "---------------------------------------------------------------------------",`
    "OS: $($script:result.osname) ($($script:result.osvers))",`
    "Build: $($script:result.build)  [$($script:result.fullbuild)]",`
    "Architecture: $($script:result.architecture)  [ $($script:result.nativearchitecture) ; $($script:result.nativearchitectureraw) ]",`
    "Version: $($script:result.version)",`
    "Revision: $($script:result.revision)",`
    "Windows Client: $($script:result.iswindowsclient)",`
    "Windows Server: $($script:result.iswindowsserver)",`
    "---------------------------------------------------------------------------"`
    )
    $null = wintwincore.WriteLogmsg -Logfile $script:setupconfig.logfile -Message $script:logmsg -Flag "INFO"
    
    # Make sure that we have Windows 11 24H2/25H2
    if ( $script:result.osname.ToString().ToLower() -match "windows 11" ) {
        if ($script:result.osvers -eq "24H2" -or $script:result.osvers -eq "25H2") {
            $script:app.control.CBiswindows11.IsChecked = $true
            script:SetStatusUpdate -StepCount 2
            script:uiEvent
        } else {
            $script:logmsg=@("The current system is not supported!","Note: Only Windows 11 24H2/25H2 are supported right now!")
            $null = wintwincore.WriteLogmsg -Logfile $script:setupconfig.logfile -Message $script:logmsg -Flag "FAIL"
            $script:app.control.CBiswindows11.IsChecked = $false
            $script:app.control.StatusText.Text = "$($script:apptxt.status.taskfail -f "$($script:apptxt.error.nosupport)")"
            $script:app.control.BtnInstall.IsEnabled = $true
            $script:app.control.BtnCancel.IsEnabled  = $true
            return $false # Same here: no need to continue if the current system is not supported!
        }
    } else {
        $script:logmsg=@("The current system is not supported!","Note: Only Windows 11 24H2/25H2 are supported right now!")
        $null = wintwincore.WriteLogmsg -Logfile $script:setupconfig.logfile -Message $script:logmsg -Flag "FAIL"
        $script:app.control.CBiswindows11.IsChecked = $false
        $script:app.control.StatusText.Text = "$($script:apptxt.status.taskfail -f "$($script:apptxt.error.nosupport)")"
        $script:app.control.BtnInstall.IsEnabled = $true
        $script:app.control.BtnCancel.IsEnabled  = $true
        return $false # Same here: no need to continue if the current system is not supported!
    }

    # Check No. 03: DISM-Check
    $script:app.control.StatusText.Text = $script:apptxt.status.task03
    script:uiEvent
    if (-not (script:CheckDISM)) {
        $script:logmsg=@("DISM was either not found on the system or it's not working!")
        $null = wintwincore.WriteLogmsg -Logfile $script:setupconfig.logfile -Message $script:logmsg -Flag "ERROR"
        $script:app.control.CBisdismworking.IsChecked = $false
        $script:app.control.StatusText.Text = "$($script:apptxt.status.taskfail -f "$($script:apptxt.error.dismfail)")"
        $script:app.control.BtnInstall.IsEnabled = $true
        $script:app.control.BtnCancel.IsEnabled  = $true
        return $false # Same here: no need to continue without DISM
    } else {
        $script:app.control.CBisdismworking.IsChecked = $true
        script:SetStatusUpdate -StepCount 3
    }
    script:uiEvent

    # Check No. 04: Check ADK-Installation
    $script:app.control.StatusText.Text = $script:apptxt.status.task04
    script:uiEvent
    if (-not (wintwincore.CheckWindowsADK)) {
        $script:logmsg=@("Windows 11 ADK wasn't found on the system. Checking alternative options.")
        $null = wintwincore.WriteLogmsg -Logfile $script:setupconfig.logfile -Message $script:logmsg -Flag "ERROR"
        $script:app.control.CBhaswindowsadk.IsChecked = $false
        $script:app.control.StatusText.Text = "$($script:apptxt.status.taskfail -f "$($script:apptxt.error.nowinadk)")"
        script:uiEvent
        # In this special case we have to perfom some special checks
        if ($SkipAdkInstall.IsPresent) {
            $script:logmsg=@("The 'SkipAdkInstall'-Switch was used on the command line.","Note: Windows 11 ADK is still not installed!")
            $null = wintwincore.WriteLogmsg -Logfile $script:setupconfig.logfile -Message $script:logmsg -Flag "WARN"
            # SkipAdkInstall-Switch was used. So we have to skip it
            # Remember: The ADK isn't installed at this point!
            $null = wintwincore.SystemMessageBox -smbTitle $script:errorhead `
            -smbText "$($script:apptxt.message.InstallAdvise -f "Windows ADK")" `
            -smbIcon Information -smbButtons OK
            $script:app.control.BtnInstall.IsEnabled = $true
            $script:app.control.BtnCancel.IsEnabled  = $true
            return $false
        } else {
            # At this point, we could automatically fix it by installing it silently
            $response = wintwincore.SystemMessageBox -smbTitle $script:errorhead `
            -smbText $script:apptxt.message.InstallADKnow `
            -smbIcon Warning -smbButtons YesNo
            if ($response.code -eq 0 -and $response.data -eq 'Yes') {
                $script:logmsg=@("User chose to install the Windows 11 ADK right now.")
                $null = wintwincore.WriteLogmsg -Logfile $script:setupconfig.logfile -Message $script:logmsg -Flag "INFO"
                $script:app.control.StatusText.Text = "$($script:apptxt.status.silentsetup -f "Windows ADK")"
                script:uiEvent
                # User wants to install the windows adk
                if (-not (wintwincore.InstallADK -SetupPath $script:setupconfig.adkexe)) {
                    $script:logmsg=@("Function wintwincore.InstallADK failed! Windows 11 ADK could not be installed!")
                    $null = wintwincore.WriteLogmsg -Logfile $script:setupconfig.logfile -Message $script:logmsg -Flag "ERROR"
                    $script:app.control.StatusText.Text = "$($script:apptxt.status.taskfail -f "$($script:apptxt.error.adkfail)")"
                    $response = wintwincore.SystemMessageBox -smbTitle $script:errorhead `
                    -smbText "$($script:apptxt.message.InstallFailed -f "Windows ADK")" `
                    -smbIcon Warning -smbButtons OK
                    $script:app.control.BtnInstall.IsEnabled = $true
                    $script:app.control.BtnCancel.IsEnabled  = $true
                    return $false
                } else {
                    $script:app.control.CBhaswindowsadk.IsChecked = $true
                }
            } else {
                $script:logmsg=@("User declined installation of Windows 11 ADK!","Note: Windows 11 ADK is still not installed!")
                $null = wintwincore.WriteLogmsg -Logfile $script:setupconfig.logfile -Message $script:logmsg -Flag "WARN"
                $null = wintwincore.SystemMessageBox -smbTitle $script:errorhead `
                -smbText "$($script:apptxt.message.InstallAdvise -f "Windows ADK")" `
                -smbIcon Information -smbButtons OK
                $script:app.control.BtnInstall.IsEnabled = $true
                $script:app.control.BtnCancel.IsEnabled  = $true
                return $false
            }
        }
    } else {
        $script:app.control.CBhaswindowsadk.IsChecked = $true
        script:SetStatusUpdate -StepCount 4
    }
    script:uiEvent

    # Check No. 05: Check ADK PE AddOn
    $script:app.control.StatusText.Text = $script:apptxt.status.task05
    script:uiEvent
    if (-not (wintwincore.CheckADKPEaddon)) {
        $script:logmsg=@("Windows 11 ADK PE AddOn wasn't found on the system. Checking alternative options.")
        $null = wintwincore.WriteLogmsg -Logfile $script:setupconfig.logfile -Message $script:logmsg -Flag "ERROR"
        $script:app.control.CBhasadkpeaddon.IsChecked = $false
        $script:app.control.StatusText.Text = "$($script:apptxt.status.taskfail -f "$($script:apptxt.error.nopeaddon)")"
        script:uiEvent
        if ($SkipWinPEInstall.IsPresent) {
            # SkipWinPEInstall was used. So we have to skip it
            $script:logmsg=@("The 'SkipWinPEInstall'-Switch was used on the command line.","Note: Windows 11 ADK PE AddOn is still not installed!")
            $null = wintwincore.WriteLogmsg -Logfile $script:setupconfig.logfile -Message $script:logmsg -Flag "WARN"
            $null = wintwincore.SystemMessageBox -smbTitle $script:errorhead `
            -smbText "$($script:apptxt.message.InstallAdvise -f "ADK PE AddOn")" `
            -smbIcon Information -smbButtons OK
            $script:app.control.BtnInstall.IsEnabled = $true
            $script:app.control.BtnCancel.IsEnabled  = $true
            return $false
        } else {
            # At this point, we could automatically fix it by installing it silently
            $response = wintwincore.SystemMessageBox -smbTitle $script:errorhead `
            -smbText $script:apptxt.message.InstallPEnow `
            -smbIcon Warning -smbButtons YesNo
            if ($response.code -eq 0 -and $response.data -eq 'Yes') {
                $script:logmsg=@("User chose to install the Windows 11 ADK PE AddOn right now.")
                $null = wintwincore.WriteLogmsg -Logfile $script:setupconfig.logfile -Message $script:logmsg -Flag "INFO"
                $script:app.control.StatusText.Text = "$($script:apptxt.status.silentsetup -f "ADK PE AddOn")"
                # User wants to install the windows adk
                if (-not (wintwincore.InstallPEaddon -SetupPath $script:setupconfig.peexe)) {
                    $script:logmsg=@("Function wintwincore.InstallPEaddon failed! Windows 11 ADK PE AddOn could not be installed!")
                    $null = wintwincore.WriteLogmsg -Logfile $script:setupconfig.logfile -Message $script:logmsg -Flag "ERROR"
                    $script:app.control.StatusText.Text = "$($script:apptxt.status.taskfail -f "$($script:apptxt.error.peaddonfail)")"
                    $response = wintwincore.SystemMessageBox -smbTitle $script:errorhead `
                    -smbText "$($script:apptxt.message.InstallFailed -f "ADK PE AddOn")" `
                    -smbIcon Warning -smbButtons OK
                    $script:app.control.BtnInstall.IsEnabled = $true
                    $script:app.control.BtnCancel.IsEnabled  = $true
                    return $false
                } else {
                    $script:app.control.CBhasadkpeaddon.IsChecked = $true
                }
            }  else {
                $script:logmsg=@("User declined installation of Windows 11 PE AddOn ADK!","Note: Windows 11 ADK PE AddOn is still not installed!")
                $null = wintwincore.WriteLogmsg -Logfile $script:setupconfig.logfile -Message $script:logmsg -Flag "WARN"
                $null = wintwincore.SystemMessageBox -smbTitle $script:errorhead `
                -smbText "$($script:apptxt.message.InstallAdvise -f "ADK PE AddOn")" `
                -smbIcon Information -smbButtons OK
                $script:app.control.BtnInstall.IsEnabled = $true
                $script:app.control.BtnCancel.IsEnabled  = $true
                return $false
            }
        }
    } else {
        $script:app.control.CBhasadkpeaddon.IsChecked = $true
        script:SetStatusUpdate -StepCount 5
    }
    script:uiEvent

    # Check No. 06: Get Framework Root
    $script:app.control.StatusText.Text = $script:apptxt.status.task06
    script:uiEvent
    if (-not (Test-Path -Path $script:setupconfig.currentDir -PathType Container)) {
        $script:logmsg=@("The Framework-Root Directory could not be determined!","Looks like following path doesn't point to a valid directory:","$($script:setupconfig.currentDir)")
        $null = wintwincore.WriteLogmsg -Logfile $script:setupconfig.logfile -Message $script:logmsg -Flag "ERROR"
        $script:app.control.CBrootdirfound.IsChecked = $false
        script:Add-Error "Could not determine root directory!"
        $script:app.control.StatusText.Text = "$($script:apptxt.status.taskfail -f "$($script:apptxt.error.rootdirfail)")"
        $script:app.control.BtnInstall.IsEnabled = $true
        $script:app.control.BtnCancel.IsEnabled  = $true
        return $false
    } else {
        $script:app.control.CBrootdirfound.IsChecked = $true
        script:SetStatusUpdate -StepCount 6
    }
    script:uiEvent

    # Check No. 07: license integrity check
    $script:app.control.StatusText.Text = $script:apptxt.status.task07
    script:uiEvent
    $script:requirement.wintwinlicense.licensefile = Join-Path "$($script:setupconfig.currentDir)" "$($script:requirement.wintwinlicense.licensefile)"
    $script:requirement.wintwinlicense.noticefile  = Join-Path "$($script:setupconfig.currentDir)" "$($script:requirement.wintwinlicense.noticefile)"

    $script:logmsg=@("Performing Lincense Integrity Check",`
    "Expected SHA512 Hash for file '$($script:requirement.wintwinlicense.licensefile)':",`
    "$($script:requirement.wintwinlicense.licensehash)",`
    "Expected SHA512 Hash for file '$($script:requirement.wintwinlicense.noticefile)':",`
    "$($script:requirement.wintwinlicense.noticehash)"`
    )
    $null = wintwincore.WriteLogmsg -Logfile $script:setupconfig.logfile -Message $script:logmsg -Flag "INFO"

    $script:licensecheck = wintwincore.CheckFileIntegrity -Path $script:requirement.wintwinlicense.licensefile -Algo SHA512 -Hash $script:requirement.wintwinlicense.licensehash
    $script:noticecheck  = wintwincore.CheckFileIntegrity -Path $script:requirement.wintwinlicense.noticefile -Algo SHA512 -Hash $script:requirement.wintwinlicense.noticehash
    if ($script:licensecheck.code -eq 0 -and $script:noticecheck.code -eq 0) {
        $script:app.control.CBverifylicense.IsChecked = $true
        script:SetStatusUpdate -StepCount 7
    } else {
        $script:logmsg=@("Lincense Integrity Check failed!","License Return Code: $($script:licensecheck.code)","Error Message: $($script:licensecheck.message)","Notice Return Code: $($script:noticecheck.code)","Error Message: $($script:noticecheck.message)")
        $null = wintwincore.WriteLogmsg -Logfile $script:setupconfig.logfile -Message $script:logmsg -Flag "WARN"
        $script:app.control.CBverifylicense.IsChecked = $false
        script:Add-Error "License Integrity Check failed!"
        $script:app.control.StatusText.Text = "$($script:apptxt.status.taskfail -f "$($script:apptxt.error.licensefail)")"
    }
    script:uiEvent

    # Check No. 08: folder structure check
    $script:app.control.StatusText.Text = $script:apptxt.status.task08
    script:uiEvent
    $script:scanerror = 0
    foreach ($prop in $script:requirement.directory.psobject.Properties) {
        if (-not (Test-Path -Path $prop.Value -PathType Container)) {
            $script:logmsg=@("Path doesn't exists or is not a directory:","$($prop.Value)")
            $null = wintwincore.WriteLogmsg -Logfile $script:setupconfig.logfile -Message $script:logmsg -Flag "WARN"
            #script:Add-Error "$($prop.Value) not found!"
            $script:scanerror++
        }
    }
    if ($script:scanerror -eq 0) {
        $script:app.control.CBhasallfolders.IsChecked = $true
        script:SetStatusUpdate -StepCount 8
    } else {
        $script:app.control.CBhasallfolders.IsChecked = $false
        script:Add-Error "Folder structure is damaged!"
        $script:app.control.StatusText.Text = "$($script:apptxt.status.taskfail -f "$($script:apptxt.error.foldererror)")"
        $script:logmsg=@("Looks like we have a damaged folder structure! A Clean Install is recommended.")
        $null = wintwincore.WriteLogmsg -Logfile $script:setupconfig.logfile -Message $script:logmsg -Flag "WARN"
        $script:app.control.BtnInstall.IsEnabled = $true
        $script:app.control.BtnCancel.IsEnabled  = $true
        return $false
    }
    script:uiEvent

    # Check No. 09: additional tools check
    $script:app.control.StatusText.Text = $script:apptxt.status.task09
    script:uiEvent
    $script:scanerror = 0
    foreach ($prop in $script:requirement.apptools.psobject.Properties) {
        if (-not (Test-Path -Path $prop.Value -PathType Container)) {
            $script:logmsg=@("Path doesn't exists or is not a directory:","$($prop.Value)")
            $null = wintwincore.WriteLogmsg -Logfile $script:setupconfig.logfile -Message $script:logmsg -Flag "WARN"
            #script:Add-Error "$($prop.Value) not found!"
            $script:scanerror++
        }
    }
    if ($script:scanerror -eq 0) {
        $script:app.control.CBalltoolsfound.IsChecked = $true
        script:SetStatusUpdate -StepCount 9
    } else {
        $script:app.control.CBalltoolsfound.IsChecked = $false
        script:Add-Error "Missing Framework-Tool(s) detected!"
        $script:app.control.StatusText.Text = "$($script:apptxt.status.taskfail -f "$($script:apptxt.error.toolserror)")"
        $script:logmsg=@("One or more missing framework tool(s) found! A Clean Install is recommended!")
        $null = wintwincore.WriteLogmsg -Logfile $script:setupconfig.logfile -Message $script:logmsg -Flag "WARN"
        $script:app.control.BtnInstall.IsEnabled = $true
        $script:app.control.BtnCancel.IsEnabled  = $true
        return $false
    }
    script:uiEvent

    # Check No. 10: checking required config files
    $script:app.control.StatusText.Text = $script:apptxt.status.task10
    script:uiEvent
    $script:scanerror = 0
    foreach ($prop in $script:requirement.configfile.psobject.Properties) {
        if (-not (Test-Path -Path $prop.Value -PathType Leaf)) {
            $script:logmsg=@("Missing JSON-File detected:","$($prop.Value)")
            $null = wintwincore.WriteLogmsg -Logfile $script:setupconfig.logfile -Message $script:logmsg -Flag "WARN"
            #script:Add-Error "$($prop.Value) not found!"
            $script:scanerror++
        }
    }
    if ($script:scanerror -eq 0) {
        $script:app.control.CBjsonfilesfound.IsChecked = $true
        script:SetStatusUpdate -StepCount 10
    } else {
        $script:app.control.CBjsonfilesfound.IsChecked = $false
        script:Add-Error "Missing config file(s) detected!"
        $script:app.control.StatusText.Text = "$($script:apptxt.status.taskfail -f "$($script:apptxt.error.noconffiles)")"
        $script:logmsg=@("One or more missing config file(s) found! A Clean Install is recommended!")
        $null = wintwincore.WriteLogmsg -Logfile $script:setupconfig.logfile -Message $script:logmsg -Flag "WARN"
        $script:app.control.BtnInstall.IsEnabled = $true
        $script:app.control.BtnCancel.IsEnabled  = $true
        return $false
    }
    script:uiEvent

    # Check No. 11: framework-library check
    $script:app.control.StatusText.Text = $script:apptxt.status.task11
    script:uiEvent
    $script:scanerror = 0
    foreach ($prop in $script:requirement.applibrary.psobject.Properties) {
        if (-not (Test-Path -Path $prop.Value -PathType Leaf)) {
            $script:logmsg=@("Missing Framework Library detected:","$($prop.Value)")
            $null = wintwincore.WriteLogmsg -Logfile $script:setupconfig.logfile -Message $script:logmsg -Flag "WARN"
            #script:Add-Error "$($prop.Value) not found!"
            $script:scanerror++
        }
    }
    if ($script:scanerror -eq 0) {
        $script:app.control.CBlibrariesfound.IsChecked = $true
        script:SetStatusUpdate -StepCount 11
    } else {
        $script:app.control.CBlibrariesfound.IsChecked = $false
        script:Add-Error "Missing framework library detected!"
        $script:app.control.StatusText.Text = "$($script:apptxt.status.taskfail -f "$($script:apptxt.error.libraryfail)")"
        $script:logmsg=@("One or more missing library/libraries found! A Clean Install is recommended!")
        $null = wintwincore.WriteLogmsg -Logfile $script:setupconfig.logfile -Message $script:logmsg -Flag "WARN"
        $script:app.control.BtnInstall.IsEnabled = $true
        $script:app.control.BtnCancel.IsEnabled  = $true
        return $false
    }
    script:uiEvent

    # Check No. 12: framework configuration
    $script:app.control.StatusText.Text = $script:apptxt.status.task12
    script:uiEvent
    $script:readJSON = wintwincore.LoadJSON -Path $script:requirement.configfile.framework
    if ($script:readJSON.code -ne 0) {
        $script:logmsg=@("Function wintwincore.LoadJSON failed:","File: $($script:requirement.configfile.framework)","Exit Code: $($script:readJSON.code)","Message: $($script:readJSON.message)","Exception: $($script:readJSON.exception)")
        $null = wintwincore.WriteLogmsg -Logfile $script:setupconfig.logfile -Message $script:logmsg -Flag "ERROR"
        $script:app.control.CBcoreconfigdone.IsChecked = $false
        script:Add-Error "Framework-Configuration failed!"
        $script:app.control.StatusText.Text = "$($script:apptxt.status.taskfail -f "$($script:apptxt.error.frameworkfail)")"
        script:uiEvent
        $null = wintwincore.SystemMessageBox -smbTitle $script:errorhead `
        -smbText "$($script:apptxt.message.InstallError -f "$($script:apptxt.error.filereadfail)")" `
        -smbIcon Warning -smbButtons OK
        $script:app.control.BtnInstall.IsEnabled = $true
        $script:app.control.BtnCancel.IsEnabled  = $true
        return $false # <- we cannot continue if we cannot edit the config.json
    }
    $script:readJSON = $script:readJSON.data

    $script:readJSON.appconfig.defaultlanguage = "$($Language)"
    $script:readJSON.path.root = "$($script:setupconfig.currentDir)"

    $script:writeJSON = wintwincore.WriteJSON -Path $script:requirement.configfile.framework -Value $script:readJSON
    if ($script:writeJSON.code -ne 0) {
        $script:logmsg=@("Function wintwincore.writeJSON failed:","File: $($script:requirement.configfile.framework)","Exit Code: $($script:writeJSON.code)","Message: $($script:writeJSON.message)","Exception: $($script:writeJSON.exception)")
        $null = wintwincore.WriteLogmsg -Logfile $script:setupconfig.logfile -Message $script:logmsg -Flag "ERROR"
        $script:app.control.CBcoreconfigdone.IsChecked = $false
        script:Add-Error "Framework-Configuration failed!"
        $script:app.control.StatusText.Text = "$($script:apptxt.status.taskfail -f "$($script:apptxt.error.frameworkfail)")"
        script:uiEvent
        $null = wintwincore.SystemMessageBox -smbTitle $script:errorhead `
        -smbText "$($script:apptxt.message.InstallError -f "$($script:apptxt.error.filewritefail)")" `
        -smbIcon Warning -smbButtons OK
        $script:app.control.BtnInstall.IsEnabled = $true
        $script:app.control.BtnCancel.IsEnabled  = $true
        return $false # <- we cannot continue if we cannot edit the config.json
    }
    $script:app.control.CBcoreconfigdone.IsChecked = $true
    script:SetStatusUpdate -StepCount 12
    script:uiEvent

    # Check No. 13: job-action configuration
    $script:app.control.StatusText.Text = $script:apptxt.status.task13
    script:uiEvent
    # Try to patch the jobaction.json
    $script:result = wintwincore.PatchJSON `
        -Path $script:requirement.configfile.jobaction `
        -SearchValue 'C:\WinTwin.Fusion' `
        -ReplacementValue $script:setupconfig.currentDir `
        -CreateBackup
    # Patching failed
    if ($script:result.code -ne 0) {
        $script:logmsg=@("Function wintwincore.PatchJSON failed:","File: $($script:requirement.configfile.jobaction)","Exit Code: $($script:result.code)","Message: $($script:result.msg)","Exception: $($script:result.exception)")
        $null = wintwincore.WriteLogmsg -Logfile $script:setupconfig.logfile -Message $script:logmsg -Flag "ERROR"
        $script:app.control.CBjobsconfigured.IsChecked = $false
        script:Add-Error "Job-Configuration failed!"
        $script:app.control.StatusText.Text = "$($script:apptxt.status.taskfail -f "$($script:apptxt.error.jobconfstatus)")"
        script:uiEvent
        $null = wintwincore.SystemMessageBox -smbTitle $script:errorhead `
        -smbText "$($script:apptxt.message.InstallError -f "$($script:apptxt.error.jobconfpopup)")" `
        -smbIcon Warning -smbButtons OK
        $script:app.control.BtnInstall.IsEnabled = $true
        $script:app.control.BtnCancel.IsEnabled  = $true
        return $false # <- we cannot continue if we cannot edit the jobaction.json
    }

    # We still need to update some details for the uupd components
    # And therefore we need to get once more the detais about the system
    $script:osinfo = wintwincore.GetWinVersion
    if ($script:osinfo.code -eq 0) { $script:osinfo = $script:osinfo.data }

    $script:scanerror = 0;
    if ( $script:osinfo.osname.ToString().ToLower() -match "windows 11" ) {
        $script:writeJSON = wintwincore.WriteJSON -Path $script:requirement.configfile.jobaction -KeyPath "uupd-catch.system.name" -Value "Windows 11"
        if ($script:writeJSON.code -ne 0) { $script:scanerror++ }
    } else {
        $script:writeJSON = wintwincore.WriteJSON -Path $script:requirement.configfile.jobaction -KeyPath "uupd-catch.system.name" -Value ""
        if ($script:writeJSON.code -ne 0) { $script:scanerror++ }
    }
    
    $script:writeJSON = wintwincore.WriteJSON -Path $script:requirement.configfile.jobaction -KeyPath "uupd-catch.system.type" -Value "$($script:osinfo.osvers)"
    if ($script:writeJSON.code -ne 0) { $script:scanerror++ }
    
    $script:writeJSON = wintwincore.WriteJSON -Path $script:requirement.configfile.jobaction -KeyPath "uupd-catch.system.arch" -Value @($($script:osinfo.nativearchitecture) , $($script:osinfo.nativearchitectureraw))
    if ($script:writeJSON.code -ne 0) { $script:scanerror++ }

    if ( $script:osinfo.osname.ToString().ToLower() -match "pro" ) {
        $script:writeJSON = wintwincore.WriteJSON -Path $script:requirement.configfile.jobaction -KeyPath "uupd-catch.system.vers" -Value "pro"
        if ($script:writeJSON.code -ne 0) { $script:scanerror++ }
    } else {
        $script:writeJSON = wintwincore.WriteJSON -Path $script:requirement.configfile.jobaction -KeyPath "uupd-catch.system.vers" -Value ""
        if ($script:writeJSON.code -ne 0) { $script:scanerror++ }
    }

    if ( $script:osinfo.osname.ToString().ToLower() -match "windows 11" -and $script:osinfo.osname.ToString().ToLower() -match "pro" ) {
        $script:writeJSON = wintwincore.WriteJSON -Path $script:requirement.configfile.jobaction -KeyPath "uupd-catch.download.uupdname" -Value "Windows11-pro-$($script:osinfo.osvers)-$($script:osinfo.nativearchitectureraw)-$($Language).zip"
        if ($script:writeJSON.code -ne 0) { $script:scanerror++ }
    } else {
        $script:writeJSON = wintwincore.WriteJSON -Path $script:requirement.configfile.jobaction -KeyPath "uupd-catch.download.uupdname" -Value "Windows11-$($script:osinfo.osvers)-$($script:osinfo.nativearchitectureraw)-$($Language).zip"
        if ($script:writeJSON.code -ne 0) { $script:scanerror++ }
    }

    if ( $script:scanerror -eq 0) {
        $script:app.control.CBjobsconfigured.IsChecked = $true
        script:SetStatusUpdate -StepCount 13
    } else {
        $script:logmsg=@("All default paths could be successfully replaced inside","$($script:requirement.configfile.jobaction)",`
        "But somehow there was at least one error updating details for the uupd-catcher jobs!",`
        "This is just dropped as a WARNING, because the Framework can still operate with these errors.")
        $null = wintwincore.WriteLogmsg -Logfile $script:setupconfig.logfile -Message $script:logmsg -Flag "WARN"
        $script:app.control.CBjobsconfigured.IsChecked = $false
        #script:Add-Error "Failed updating config for UUPD.Catcher!"
        $script:app.control.StatusText.Text = "$($script:apptxt.status.taskfail -f "$($script:apptxt.error.uupdupdatefail)")"
    }
    script:uiEvent

    # Check No. 14: process database configuration
    $script:app.control.StatusText.Text = $script:apptxt.status.task14
    script:uiEvent
    $script:readJSON = wintwincore.LoadJSON -Path $script:requirement.configfile.processdb
    if ($script:readJSON.code -ne 0) {
        $script:logmsg=@("Function wintwincore.LoadJSON failed:","File: $($script:requirement.configfile.processdb)","Exit Code: $($script:readJSON.code)","Message: $($script:readJSON.message)","Exception: $($script:readJSON.exception)")
        $null = wintwincore.WriteLogmsg -Logfile $script:setupconfig.logfile -Message $script:logmsg -Flag "ERROR"
        $script:app.control.CBprocessdbdone.IsChecked = $false
        script:Add-Error "Failed setting up process database!"
        $script:app.control.StatusText.Text = "$($script:apptxt.status.taskfail -f "$($script:apptxt.error.processwrite)")"
        script:uiEvent
        $null = wintwincore.SystemMessageBox -smbTitle $script:errorhead `
        -smbText "$($script:apptxt.message.InstallError -f "$($script:apptxt.error.processread)")" `
        -smbIcon Warning -smbButtons OK
        $script:app.control.BtnInstall.IsEnabled = $true
        $script:app.control.BtnCancel.IsEnabled  = $true
        return $false # <- we cannot continue if we cannot edit the jobaction.json
    }
    $script:readJSON = $script:readJSON.data

    $script:readJSON.running."proc-name" = ""
    $script:readJSON.running."proc-path" = ""
    $script:readJSON.running."action-id" = ""
    $script:readJSON.running.processid   = 0
    $script:readJSON.running.cmdparams   = ""
    $script:readJSON.running."job-start" = ""
    $script:readJSON.running."job-state" = ""
    $script:readJSON.running.exitcode    = ""

    $script:readJSON.lastjob."proc-name" = ""
    $script:readJSON.lastjob."proc-path" = ""
    $script:readJSON.lastjob."action-id" = ""
    $script:readJSON.lastjob.processid   = 0
    $script:readJSON.lastjob.cmdparams   = ""
    $script:readJSON.lastjob."job-start" = ""
    $script:readJSON.lastjob."job-state" = ""
    $script:readJSON.lastjob."job-ended" = ""
    $script:readJSON.lastjob.exitcode    = ""

    $script:readJSON.console."proc-name" = ""
    $script:readJSON.console."proc-path" = ""
    $script:readJSON.console."action-id" = ""
    $script:readJSON.console.processid   = 0
    $script:readJSON.console.script      = ""
    $script:readJSON.console.logfile     = ""
    $script:readJSON.console."job-start" = ""
    $script:readJSON.console."job-state" = ""
    $script:readJSON.console."job-ended" = ""
    $script:readJSON.console.exitcode    = ""
    
    $script:writeJSON = wintwincore.WriteJSON -Path $script:requirement.configfile.processdb -Value $script:readJSON
    if ($script:writeJSON.code -ne 0) {
        $script:logmsg=@("Function wintwincore.writeJSON failed:","File: $($script:requirement.configfile.processdb)","Exit Code: $($script:writeJSON.code)","Message: $($script:writeJSON.message)","Exception: $($script:writeJSON.exception)")
        $null = wintwincore.WriteLogmsg -Logfile $script:setupconfig.logfile -Message $script:logmsg -Flag "ERROR"
        $script:app.control.CBprocessdbdone.IsChecked = $false
        script:Add-Error "Failed setting up process database!"
        $script:app.control.StatusText.Text = "$($script:apptxt.status.taskfail -f "$($script:apptxt.error.processwrite)")"
        script:uiEvent
        $null = wintwincore.SystemMessageBox -smbTitle $script:errorhead `
        -smbText "$($script:apptxt.message.InstallError -f "$($script:apptxt.error.processupdate)")" `
        -smbIcon Warning -smbButtons OK
        $script:app.control.BtnInstall.IsEnabled = $true
        $script:app.control.BtnCancel.IsEnabled  = $true
        return $false # <- we cannot continue if we cannot edit the jobaction.json
    }
    $script:app.control.CBprocessdbdone.IsChecked = $true
    script:SetStatusUpdate -StepCount 14
    script:uiEvent

    # Check No. 15: workflow configuration
    $script:app.control.StatusText.Text = $script:apptxt.status.task15
    script:uiEvent
    $script:readJSON = wintwincore.LoadJSON -Path $script:requirement.configfile.workflows
    if ($script:readJSON.code -ne 0) {
        $script:logmsg=@("Function wintwincore.LoadJSON failed:","File: $($script:requirement.configfile.workflows)","Exit Code: $($script:readJSON.code)","Message: $($script:readJSON.message)","Exception: $($script:readJSON.exception)")
        $null = wintwincore.WriteLogmsg -Logfile $script:setupconfig.logfile -Message $script:logmsg -Flag "ERROR"
        $script:app.control.CBworkflowsdone.IsChecked = $false
        script:Add-Error "Failed setting up workflow-feature!"
        $script:app.control.StatusText.Text = "$($script:apptxt.status.taskfail -f "$($script:apptxt.error.workflowinit)")"
        script:uiEvent
        $null = wintwincore.SystemMessageBox -smbTitle $script:errorhead `
        -smbText "$($script:apptxt.message.InstallError -f "$($script:apptxt.error.wrokflowread)")" `
        -smbIcon Warning -smbButtons OK
        $script:app.control.BtnInstall.IsEnabled = $true
        $script:app.control.BtnCancel.IsEnabled  = $true
        return $false # <- we cannot continue if we cannot edit the jobaction.json
    }
    $script:readJSON = $script:readJSON.data

    # There's nothing to do here a.t.m.
    Start-Sleep -Milliseconds 2000

    $script:writeJSON = wintwincore.WriteJSON -Path $script:requirement.configfile.workflows -Value $script:readJSON
    if ($script:writeJSON.code -ne 0) {
        $script:logmsg=@("Function wintwincore.writeJSON failed:","File: $($script:requirement.configfile.workflows)","Exit Code: $($script:writeJSON.code)","Message: $($script:writeJSON.message)","Exception: $($script:writeJSON.exception)")
        $null = wintwincore.WriteLogmsg -Logfile $script:setupconfig.logfile -Message $script:logmsg -Flag "ERROR"
        $script:app.control.CBworkflowsdone.IsChecked = $false
        script:Add-Error "Failed setting up workflow-feature!"
        $script:app.control.StatusText.Text = "$($script:apptxt.status.taskfail -f "$($script:apptxt.error.workflowinit)")"
        script:uiEvent
        $null = wintwincore.SystemMessageBox -smbTitle $script:errorhead `
        -smbText "$($script:apptxt.message.InstallError -f "$($script:apptxt.error.workflowupdate)")" `
        -smbIcon Warning -smbButtons OK
        $script:app.control.BtnInstall.IsEnabled = $true
        $script:app.control.BtnCancel.IsEnabled  = $true
        return $false # <- we cannot continue if we cannot edit the jobaction.json
    }
    $script:app.control.CBworkflowsdone.IsChecked = $true
    script:SetStatusUpdate -StepCount 15
    script:uiEvent

    # Check No. 16: install required fonts
    $script:app.control.StatusText.Text = $script:apptxt.status.task16
    script:uiEvent
    # Try to install the required Fonts
    $script:fontsresult = wintwincore.InstallRequiredFonts -Path $script:requirement.directory.fonts
    if ($script:fontsresult) {
        $script:app.control.CBfontsinstalled.IsChecked = $true
        script:SetStatusUpdate -StepCount 16
        script:uiEvent
    }
    else {
        $script:logmsg=@("Function wintwincore.InstallRequiredFonts failed!")
        $null = wintwincore.WriteLogmsg -Logfile $script:setupconfig.logfile -Message $script:logmsg -Flag "ERROR"
        $script:app.control.CBfontsinstalled.IsChecked = $false
        script:Add-Error "Font-Installation failed!"
        $script:app.control.StatusText.Text = "$($script:apptxt.status.taskfail -f "$($script:apptxt.error.fontinstall)")"
        script:uiEvent
    }

    # Check No. 17: Finan Checkup/Cleanup
    $script:app.control.StatusText.Text = $script:apptxt.status.task17
    script:uiEvent

    <# --------------------------------------------------
    SPONTANE IDEE:
    WIR KÖNNTEN ZWEI ZUSÄTZLICHE ARRAYS/OBJEKTE DEFINIEREN
    DER EINE ENTHÄLT "FOLDERS_TO_REMOVE"
    DER ANDERE IST "FILES_TO_REMOVE"
    IN DEN JEWEILIGEN ARRAYS/OBJEKTEN SIND DATEIEN/ORDNDER
    (WIE Z.B. .GITIGNORE oder .GITHUB) DEFINIERT, DIE
    AM ENDE DURCH DEN INSTALLER AUTOMATISCH ENTFERNT
    WERDEN. NACHTEIL: KÖNNTE ZU ERNSTHAFTEN PROBLEMEN
    FÜHREN, WENN ES IN DER ENTWICKLUNGSUMGEBUNG LÄUFT!
    -------------------------------------------------- #>

    # We need to count all 'Add-Error' Entries !!
    if ( $script:errorlist.Count -ge 1 ) {
        # We had at least one error
        $script:app.control.CBfinalcheckup.IsChecked = $false
        $script:app.control.StatusText.Text = "$($script:apptxt.status.taskfail -f "$($script:apptxt.error.checkhaserror)")"
        $script:logmsg=@("$($script:setupconfig.appname) ($($script:setupconfig.appvers)) has finished with errors!",`
        "Following errors were recorded during the process:")
        $null = wintwincore.WriteLogmsg -Logfile $script:setupconfig.logfile -Message $script:logmsg -Flag "WARN"
        $script:logmsg=@("$($script:errorlist)")
        $null = wintwincore.WriteLogmsg -Logfile $script:setupconfig.logfile -Message $script:logmsg -Flag "ERROR"
    } else {
        $script:logmsg=@("$($script:setupconfig.appname) ($($script:setupconfig.appvers)) successfully finished without errors!")
        $null = wintwincore.WriteLogmsg -Logfile $script:setupconfig.logfile -Message $script:logmsg -Flag "INFO"
        $script:app.control.CBfinalcheckup.IsChecked = $true
    }
    script:SetStatusUpdate -StepCount 17
    script:uiEvent
    Start-Sleep -Milliseconds 1500
    # Indicating final result
    if ( $script:errorlist.Count -ge 1 ) {
        $script:app.control.CBwintwinready.IsChecked = $false
        $null = wintwincore.SystemMessageBox -smbTitle $script:errorhead `
        -smbText "$($script:apptxt.error.resultpopup -f $script:setupconfig.appname) " `
        -smbIcon None -smbButtons OK
    } else {
        $script:app.control.CBwintwinready.IsChecked = $true
        $script:app.control.StatusText.Text = "$($script:apptxt.status.task18)"
    }
    script:SetStatusUpdate -StepCount 18
    script:uiEvent

    # Release the buttons again (depending on the results)
    if ( $script:errorlist.Count -ge 1 ) {
        $script:app.control.BtnInstall.IsEnabled = $true
    } else {
        $script:app.control.BtnInstall.IsEnabled = $false
    }
    $script:app.control.BtnCancel.IsEnabled  = $true
})

# Action-Button: Close/Exit
$script:app.control.BtnCancel.Add_Click({
    $script:app.window.Close()
})

# Action-Button: Clean/Fresh Install
$script:app.control.BtnCleanSetup.Add_Click({
    $null = wintwincore.SystemMessageBox -smbTitle $script:errorhead `
    -smbText "This feature hasn't been implemented till now.`nIt'll be coming soon in a future release :)" `
    -smbIcon None -smbButtons OK
})

# CheckBox Test
#$script:app.control.CBiselevated.IsChecked = $true

#--------------------------------------------------------------------------------
# Launch the UI and show the window
#--------------------------------------------------------------------------------

$script:app.window.Topmost = $true
$script:app.window.Add_Loaded({
    $script:app.window.Activate()
    $script:app.window.Focus()
    $script:app.window.Topmost = $false
})

$script:logmsg=@("Showing Install Manager Window using 'ShowDialog() | Out-Null'")
$null = wintwincore.WriteLogmsg -Logfile $script:setupconfig.logfile -Message $script:logmsg -Flag "INFO"

$script:app.window.ShowDialog() | Out-Null
# Cleanup/Exit
$null = wintwincore.SetCMDstate -State Show -Focus $false
$script:logmsg=@("WinTwin.Fusion Install Manager Window was closed.","Application will exit now.","Thanks for using WinTwin. Fusion Install Manager :)")
$null = wintwincore.WriteLogmsg -Logfile $script:setupconfig.logfile -Message $script:logmsg -Flag "INFO"
exit 0

<#
.SYNOPSIS
    wim.mounter - A simple tool that helps you to mount your install.wim

.DESCRIPTION
    wim.mounter is an integral part of the DISM UI Control Center and offers
    a simple way to mount Windows images to a specific folder via a graphical interface.

.NOTES
    Creation Date: 28.03.2026  (as WinISO.ScriptFXLib)
    Last Update:   26.08.2026
    Version:       1.00.08
    Author:        Praetoriani (a.k.a. M.Sczepanski)
    Website:       https://github.com/WinTwin-Fusion/DISM.UI.CC

    REQUIREMENTS & DEPENDENCIES:
    - PowerShell 5.1 or higher
    - .NET Framework 4.7.2 or higher (for Windows PowerShell)
    - DISM
#>


#--------------------------------------------------------------------------------
# Command Line Params
#--------------------------------------------------------------------------------
[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$Language = ""
)

#--------------------------------------------------------------------------------
# Set Script Root and App-Icon
#--------------------------------------------------------------------------------
$global:approot   = $PSScriptRoot
$global:appicon   = Join-Path $PSScriptRoot "DISM.UI.CC.ico"

#--------------------------------------------------------------------------------
# Internal Script vars
#--------------------------------------------------------------------------------
$config = [pscustomobject]@{
    framework = "..\core\config.json"
    jobaction = "..\core\db\jobaction.json"
    ducctools = Join-Path "$($global:approot)" "dism.config.json"
}

#--------------------------------------------------------------------------------
# Pre-Load the config.json from the WinTwin.Fusion Framework
#--------------------------------------------------------------------------------
# Explanation:
# If we do the preloading of the global config.json at this point, things are
# getting much easier for us from that point on. One advantage is that we can
# load the Libraries from the Framework much earlier. Ant that means:
# We can use the functions from the internal Framework Libraries :)
#--------------------------------------------------------------------------------

# 1st Step: We're going to check that the file exists
if (-not (Test-Path -LiteralPath "$($config.framework)")) {
    Write-Error "DISM UI Control Center (wim.mounter):  Configuration file not found:`n$($config.framework)"
    exit 1
}

# 2nd Step: We're trying to load the content from the config.json
try {
    $script:rootcfg = Get-Content -LiteralPath $config.framework -Raw | ConvertFrom-Json -ErrorAction Stop
}
catch {
    Write-Error "DISM UI Control Center (wim.mounter):  Failed to parse $($config.framework)\n$($_.Exception.Message)"
    exit 1
}

# 3rd Step: Assign important values from the global config.json
$wintwin = [pscustomobject]@{
    root    = $script:rootcfg.path.root
    lib     = Join-Path "$($script:rootcfg.path.root)" "$($script:rootcfg.path.lib)"
    lang    = Join-Path "$($script:rootcfg.path.root)" "$($script:rootcfg.path.lang)"
    logs    = Join-Path "$($script:rootcfg.path.root)" "$($script:rootcfg.path.logs)"
    xmlui   = Join-Path "$($script:rootcfg.path.root)" "$($script:rootcfg.path.appui)"
    fonts   = Join-Path "$($script:rootcfg.path.root)" "$($script:rootcfg.path.fonts)"
    export  = Join-Path "$($script:rootcfg.path.root)" "$($script:rootcfg.path.export)"
    console = Join-Path "$($script:rootcfg.path.root)" "$($script:rootcfg.path.pstools.console)"
}

# 4th Step: Fallback, if no language has been passed through command line
if ([string]::IsNullOrWhiteSpace($Language)) {
    $Language = "$($script:rootcfg.appconfig.defaultlanguage)"
}

#--------------------------------------------------------------------------------
# Try to load required Libraries from the WinTwin.Fusion Framework
#--------------------------------------------------------------------------------
$script:LibOPSR  = Join-Path "$($wintwin.lib)" "$($script:rootcfg.lib.OPSreturn)"
$script:LibPSACL = Join-Path "$($wintwin.lib)" "$($script:rootcfg.lib.PSAppCoreLib)"
$script:LibWTFXC = Join-Path "$($wintwin.lib)" "$($script:rootcfg.lib.WinTwinFXcore)"
$script:LibWTXUI = Join-Path "$($wintwin.lib)" "$($script:rootcfg.lib.WinTwinXUI)"

foreach ($requiredModulePath in @($script:LibOPSR, $script:LibPSACL, $script:LibWTFXC)) {
    if (-not (Test-Path -LiteralPath $requiredModulePath -PathType Leaf)) {
        Write-Error "DISM UI Control Center (wim.mounter):  Required module manifest not found:`n$($requiredModulePath)"
        exit 1
    }
}

try {
    Import-Module $script:LibOPSR -Force -ErrorAction Stop
    Import-Module $script:LibPSACL -Force -ErrorAction Stop
    Import-Module $script:LibWTFXC -Force -ErrorAction Stop
    Import-Module $script:LibWTXUI -Force -ErrorAction Stop
}
catch {
    Write-Error "DISM UI Control Center (wim.mounter):  Failed to import required framework modules.`n$($_.Exception.Message)"
    exit 1
}

#--------------------------------------------------------------------------------
# Hide Console Window -> Using Function from WinTwin.FXcore
# -> We can use wintwincore.SystemMessageBox to display Error-Messages!
#--------------------------------------------------------------------------------
#wintwincore.SetCMDstate -State Hide

#--------------------------------------------------------------------------------
# Load additional Libraries (Required to build the UI)
#--------------------------------------------------------------------------------
Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName PresentationCore
Add-Type -AssemblyName WindowsBase
Add-Type -AssemblyName System.Xml

#--------------------------------------------------------------------------------
# Time to load the other JSON Config files (using Functions from WinTwin.FXcore)
#--------------------------------------------------------------------------------
# Load the .\Core\db\jobaction.json
$result = wintwincore.LoadJSON -Path $config.jobaction
if($result.code -ne 0) {
    $null = wintwincore.SystemMessageBox -smbTitle "DISM UI Control Center (wim.mounter)" `
    -smbText "Failed loading file: $($config.jobaction)`n$($result.msg)" `
    -smbIcon Error -smbButtons OK
    exit 1
}
$script:jobconf = $result.data

# Load the .\dism.config.json
$result = wintwincore.LoadJSON -Path $config.ducctools
if($result.code -ne 0) {
    $null = wintwincore.SystemMessageBox -smbTitle "DISM UI Control Center (wim.mounter)" `
    -smbText "Failed loading file: $($config.ducctools)`n$($result.msg)" `
    -smbIcon Error -smbButtons OK
    exit 1
}
$script:toolcfg = $result.data

#--------------------------------------------------------------------------------
# With the content from the JSON-Files, we have to configure some more vars
#--------------------------------------------------------------------------------
# Load informations about DISM UI Control Center
$ducc = [pscustomobject]@{
    appname = "$($script:toolcfg.appinfo.appname)"
    version = "$($script:toolcfg.appinfo.version)"
    website = "$($script:toolcfg.appinfo.website)"
    devname = "$($script:toolcfg.appinfo.devname)"
}
# Load informations about wim.mounter
$wimmount = [pscustomobject]@{
    appname   = "$($script:toolcfg.apptool."wim-mount".appname)"
    acionid   = "$($script:toolcfg.apptool."wim-mount"."action-id")"
    xmlfile   = Join-Path "$($wintwin.root)" "$($script:toolcfg.apptool."wim-mount".xmlui)"
    path      = "$($script:jobconf."wim-mount".path)"
    wimfile   = "$($script:jobconf."wim-mount".imgfile)"
    index     = "$($script:jobconf."wim-mount".index)"
    logfile   = "$($script:jobconf."wim-mount".logfile[1])"
    language  = $null
    conscript = $null
}
# Set the name of the Scriptfile for the WTF.Console
$wimmount.conscript = "$($script:toolcfg.apptool."wim-mount".require.console[1])"

#--------------------------------------------------------------------------------
# Process-Registration (.\Core\db\process.json)
#--------------------------------------------------------------------------------
$processCheck = wintwincore.CheckProcess -FrameworkRoot $wintwin.root
if ($processCheck.code -ne 0) {
    $null = wintwincore.SystemMessageBox -smbTitle "DISM UI Control Center (wim.mounter)" `
    -smbText "Could not verify the framework process lock.`n$($processCheck.msg)" `
    -smbIcon Error -smbButtons OK
    exit 1
}
# Running Process detected
if ($processCheck.data.IsRunning) {
    $null = wintwincore.SystemMessageBox -smbTitle 'DISM UI Control Center (wim.mounter)' `
    -smbText "Another framework process is currently running:`n$($processCheck.data.Running.'proc-name')`n`nPlease wait until it has finished." `
    -smbIcon Warning -smbButtons OK
    exit 0
}

$selfRegister = wintwincore.RegisterProcess -FrameworkRoot $wintwin.root `
                                     -ProcName "$($wimmount.appname)" `
                                     -ProcPath $PSCommandPath `
                                     -ActionId "$($wimmount.acionid)" `
                                     -ProcessId $PID
if ($selfRegister.code -ne 0) {
    $null = wintwincore.SystemMessageBox -smbTitle "DISM UI Control Center (wim.mounter)" `
    -smbText "Could not register as the active framework process.`n$($selfRegister.msg)"
    -smbIcon Error -smbButtons OK
    exit 1
}

#--------------------------------------------------------------------------------
# Try to load the language file for wim.mounter
#--------------------------------------------------------------------------------
# Load the correct language for wim.mounter
switch ($Language) {
    'en-us' { $wimmount.language = Join-Path "$($wintwin.root)" "$($script:toolcfg.apptool."wim-mount".langfile."en-us")" }
    'de-de' { $wimmount.language = Join-Path "$($wintwin.root)" "$($script:toolcfg.apptool."wim-mount".langfile."de-de")" }
    default { $wimmount.language = Join-Path "$($wintwin.root)" "$($script:toolcfg.apptool."wim-mount".langfile."en-us")" }
}
$result = wintwincore.LoadJSON -Path $wimmount.language
if ($result.code -eq 0) { $apptxt = $result.data }
else {
    $null = wintwincore.SystemMessageBox -smbTitle "DISM UI Control Center (wim.mounter)" `
    -smbText "Faild loading language package:`n$($wimmount.language)`n$($result.message)"
    -smbIcon Error -smbButtons OK
    exit 1
}

#--------------------------------------------------------------------------------
# Try to load the XML-UI (including app icon)
#--------------------------------------------------------------------------------
$LoadXML = xuiLoadWindow -XMLfile $wimmount.xmlfile -extended
if ($LoadXML.code -ne 0) {
    $null = wintwincore.SystemMessageBox -smbTitle "DISM UI Control Center (wim.mounter)" `
    -smbText "Faild loading User Interface:`n$($wimmount.xmlfile)`n$($LoadXML.message)"
    -smbIcon Error -smbButtons OK
    exit 1
}
$window = $LoadXML.data.Window

if (Test-Path -LiteralPath $global:appicon) {
    try {
        $iconImage = [System.Windows.Media.Imaging.BitmapImage]::new([System.Uri]::new($global:appicon))
        $window.Icon = $iconImage
    }
    catch {
        Write-Verbose "DISM UI Control Center (wim.mounter):  Could not set window icon: $($_.Exception.Message)"
    }
}


#--------------------------------------------------------------------------------
# Get a reference on the UI-Elements insid the XML-Code
#--------------------------------------------------------------------------------
$titleBarPanel   = $window.FindName("TitleBarPanel")
$titleBarText    = $window.FindName("TitleBarText")
$titleBarLogo    = $window.FindName("TitleBarLogo")
$btnClose        = $window.FindName("BtnClose")
$lblInstructions = $window.FindName("LblInstructions")
$lblImageFile    = $window.FindName("LblImageFile")
$lblMountPoint   = $window.FindName("LblMountPoint")
$txtImageFile    = $window.FindName("TxtImageFile")
$btnOpenImage    = $window.FindName("BtnOpenImage")
$txtMountPoint   = $window.FindName("TxtMountPoint")
$btnBrowseMount  = $window.FindName("BtnBrowseMount")
$chkCreateMountPoint = $window.FindName('ChkCreateMountPoint')
$btnMount        = $window.FindName("BtnMount")
$btnCancel       = $window.FindName("BtnCancel")
$btnExit         = $window.FindName("BtnExit")
$statusText      = $window.FindName("StatusText")
$statusInfo      = $window.FindName("StatusInfo")

#--------------------------------------------------------------------------------
# Applying loaded language file to the interface
#--------------------------------------------------------------------------------
$window.Title                = $apptxt.window.title
$titleBarText.Text           = $apptxt.window.title
$lblInstructions.Text        = $apptxt.labels.instructions
$lblImageFile.Text           = $apptxt.labels.imageFile
$lblMountPoint.Text          = $apptxt.labels.mountPoint
$chkCreateMountPoint.Content = $apptxt.labels.createMountPoint
$btnOpenImage.ToolTip        = $apptxt.buttons.openTooltip
$btnBrowseMount.ToolTip      = $apptxt.buttons.browseTooltip
$btnMount.Content            = $apptxt.buttons.mount
$btnCancel.Content           = $apptxt.buttons.cancel
$btnExit.Content             = $apptxt.buttons.exit
$statusText.Text             = $apptxt.status.ready
$statusInfo.Text             = "$($ducc.appname) $($ducc.version)"

if (Test-Path -LiteralPath $global:appicon) {
    try {
        $titleBarLogo.Source = [System.Windows.Media.Imaging.BitmapImage]::new([System.Uri]::new($global:appicon))
    }
    catch {
        Write-Verbose "DISM UI Control Center (wim.mounter):  Could not set title bar logo: $($_.Exception.Message)"
    }
}


#--------------------------------------------------------------------------------
# Helper-Functions for UI-Interacction
#--------------------------------------------------------------------------------
function Reset-FormState {
    $txtImageFile.Text  = ""
    $txtMountPoint.Text = ""
    $chkCreateMountPoint.IsChecked = $true
    Clear-FieldError -TextBox $txtImageFile
    Clear-FieldError -TextBox $txtMountPoint
    $statusText.Text = $apptxt.status.ready
}

function Show-FieldError {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][System.Windows.Controls.TextBox]$TextBox)
    $errorBg     = $TextBox.FindResource("BrushInputError")
    $errorBorder = $TextBox.FindResource("BrushInputErrorBrdr")
    $TextBox.Background  = $errorBg
    $TextBox.BorderBrush = $errorBorder
}

function Clear-FieldError {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][System.Windows.Controls.TextBox]$TextBox)
    $normalBg     = $TextBox.FindResource("BrushInputBg")
    $normalBorder = $TextBox.FindResource("BrushInputBorder")
    $TextBox.Background  = $normalBg
    $TextBox.BorderBrush = $normalBorder
}

#$btnClose.Add_Click({ $window.Close() })
#$titleBarPanel.Add_MouseLeftButtonDown({ param($senderObj, $eventArgs) $window.DragMove() })

$btnClose.Add_Click({ $window.Close() })
$titleBarPanel.Add_MouseLeftButtonDown({
    param($senderObj, $mouseEventArgs)
    $window.DragMove()
})

$btnOpenImage.Add_Click({
    Clear-FieldError -TextBox $txtImageFile
    $filePicker = xuiSelectFile -Title $apptxt.dialogs.fileDialogTitle -Filter "$($apptxt.dialogs.fileDialogFilterName)|*.wim"
    if ($filePicker.code -eq 0) { $txtImageFile.Text = $filePicker.data.Path } else { $txtImageFile.Text = "" }
})

$btnBrowseMount.Add_Click({
    Clear-FieldError -TextBox $txtMountPoint
    $pathPicker = xuiSelectFolder -Title $apptxt.dialogs.folderDialogTitle
    if ($pathPicker.code -eq 0) { $txtMountPoint.Text = $pathPicker.data.Path } else { $txtMountPoint.Text = "" }
})

$btnCancel.Add_Click({ Reset-FormState })
$btnExit.Add_Click({ $window.Close() })

$btnMount.Add_Click({
    $imagePath = $txtImageFile.Text
    $mountDir  = $txtMountPoint.Text
    $createMountPoint = $chkCreateMountPoint.IsChecked.ToString().ToLower()
    $hasError = $false
    # Unfortunately $chkCreateMountPoint.IsChecked is "True" not $true
    # So we need to re-build the required $true
    $createMountPoint = "{0}{1}" -f "$", $createMountPoint
    #$createMountPoint = [bool]$createMountPoint

    if ([string]::IsNullOrWhiteSpace($imagePath) -or -not (Test-Path -LiteralPath $imagePath -PathType Leaf) -or ([System.IO.Path]::GetExtension($imagePath).ToLowerInvariant() -ne ".wim")) {
        Show-FieldError -TextBox $txtImageFile
        $hasError = $true
    }
    else {
        Clear-FieldError -TextBox $txtImageFile
    }

    if ([string]::IsNullOrWhiteSpace($mountDir)) {
        Show-FieldError -TextBox $txtMountPoint
        $hasError = $true
    }
    elseif (-not (Test-Path -LiteralPath $mountDir -PathType Container) -and -not $createMountPoint) {
        Show-FieldError -TextBox $txtMountPoint
        $hasError = $true
    }
    else {
        Clear-FieldError -TextBox $txtMountPoint
    }

    if ($hasError) {
        return
    }

    if (-not (Test-Path -LiteralPath $wintwin.console -PathType Leaf)) {
        $null = wintwincore.SystemMessageBox -smbTitle "$($ducc.appname) ($($wimmount.appname))" `
        -smbText "WTF.Console (PS.Tweak.Tools) was not found:`n$($wintwin.console)" `
        -smbIcon Error -smbButtons OK
        return
    }

    $btnMount.IsEnabled       = $false
    $btnCancel.IsEnabled      = $false
    $btnOpenImage.IsEnabled   = $false
    $btnBrowseMount.IsEnabled = $false
    $chkCreateMountPoint.IsEnabled = $false
    $statusText.Text          = $apptxt.status.mounting
    #$statusText.Text = $apptxt.status.launchingConsole

    try {
        # Create the Mount-Script for WTF.Console
        $scriptContent = @"
`$ErrorActionPreference = 'Stop'
Write-Output '========================================'
Write-Output 'WIM MOUNT JOB STARTED'
Write-Output '========================================'
Write-Output ('WIM file    : {0}' -f '$($imagePath.Replace("'", "''"))')
Write-Output ('Mount dir   : {0}' -f '$($mountDir.Replace("'", "''"))')
Write-Output ('WIM index   : {0}' -f '$($wimmount.index)')
Write-Output ('Create path : {0}' -f '$($createMountPoint)')

`$moduleCandidates = @(
    '$script:LibOPSR',
    '$script:LibPSACL',
    '$script:LibWTFXC'
    '$script:LibWTXUI'
) | Where-Object { -not [string]::IsNullOrWhiteSpace(`$_) }

foreach (`$modulePath in `$moduleCandidates) {
    if (-not (Test-Path -LiteralPath `$modulePath)) {
        throw ('Required module path not found: {0}' -f `$modulePath)
    }
    Import-Module `$modulePath -Force -ErrorAction Stop
}

if ($($createMountPoint) -and -not (Test-Path -LiteralPath '$($mountDir.Replace("'", "''"))')) {
    Write-Output 'Mount point does not exist. Creating directory via wintwincore.CreateNewDir...'
    `$createResult = wintwincore.CreateNewDir -Path '$($mountDir.Replace("'", "''"))' -Force
    if (`$createResult.code -ne 0) {
        throw ('wintwincore.CreateNewDir failed: {0}' -f `$createResult.msg)
    }
}

Write-Output 'Mounting image via MountWIMimage...'
#`$mountResult = MountWIMimage -WIMimage '$($imagePath.Replace("'", "''"))' -IndexNo $($wimmount.index) -MountPoint '$($mountDir.Replace("'", "''"))'
#if (`$mountResult.code -ne 0) {
#    throw `$mountResult.msg
#}
#Write-Output `$mountResult.msg

#DISM /Mount-Wim /WimFile:'$($imagePath.Replace("'", "''")) /Index:$($wimmount.index) /MountDir:$($mountDir.Replace("'", "''")) /English

Write-Output 'Running (faked) Mount-Script.'
Sleep 3.0
Write-Output 'Done.'

Write-Output 'The operation completed successfully.'
exit 0
"@
        
        # Write the generated console script to a file (path defined in dism.congif.json)
        $scriptFile = Join-Path "$($wintwin.export)" "$($wimmount.conscript)"
        $result = wintwincore.ConsoleScript -ScriptPath $scriptFile `
                                   -ScriptType ps1 `
                                   -ScriptData $scriptContent
        if ($result.code -ne 0) {
            $null = wintwincore.SystemMessageBox -smbTitle "$($ducc.appname) ($($wimmount.appname))" `
            -smbText "Error while creating console script!`n$($result.msg)" `
            #-smbText "Following console script was created:`n$($script:toolcfg.apptool."wim-mount".require.console[1])`nReturn from 'wintwincore.ConsoleScript':`n$($result.data.Path)" `
            -smbIcon Error -smbButtons OK
        }
        
        if (-not (Test-Path -LiteralPath $wintwin.logs)) {
            $createLogDir = wintwincore.CreateNewDir -Path $wintwin.logs
            if ($createLogDir.code -ne 0 -and -not (Test-Path -LiteralPath $wintwin.logs -PathType Container)) {
                throw $createLogDir.msg
            }
        }

        $timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
        if (($script:jobconf."wim-mount".logfile[0] -eq $true) -and (Test-Path $wimmount.logfile)) {
            $logPattern = [string]$wimmount.logfile
        } else {
            $logPattern = Join-Path $wintwin.logs '[DATETIME].wim.mounter.log'
        }
        $logFileName = $logPattern -replace '\[DATETIME\]', $timestamp
        $logFilePath = $logFileName

        $logInitResult = wintwincore.WriteLogmsg -Logfile $logFilePath -Message "wim.mounter launched WTF.Console mount workflow." -Flag "INFO" -Override 1
        if ($logInitResult.code -ne 0) {
            Write-Verbose "DISM UI Control Center (wim.mounter):  Failed to precreate log file: $($logInitResult.msg)"
        }
        
        # Unregister wim.mounter.ps1 befeore launching the console
        $null = wintwincore.UnregisterProcess -FrameworkRoot $wintwin.root -ProcessId $PID
        # Launch the WTF.Console Process
        # Typical wim.mounter hand-off after the tool has cleared process.json:
        $launch = wintwincore.LaunchConsole -Script $scriptFile `
                            -Mode framework `
                            -Action $wimmount.acionid `
                            -Logging $true `
                            -Logfile $logFilePath `
                            -FrameworkRoot $wintwin.root

        # Looks like there was an error while launching WTF.Console
        if ($launch.code -ne 0) {
            # Show a Win32-Dialog
            $null = wintwincore.SystemMessageBox -smbTitle "Debugging" `
            -smbText "Error while launching WTF.Console!`n$($launch.msg)" `
            -smbIcon Error -smbButtons OK
            
            # Failed launching WTF.Console. We need to re-register wim.mounter
            $null = wintwincore.RegisterProcess -FrameworkRoot $wintwin.root -ProcName 'wim.mounter' `
            -ProcPath $PSCommandPath -ActionId $wimmount.acionid -ProcessId $PID
            
            #throw $launch.msg
            $btnMount.IsEnabled       = $true
            $btnCancel.IsEnabled      = $true
            $btnOpenImage.IsEnabled   = $true
            $btnBrowseMount.IsEnabled = $true
            $chkCreateMountPoint.IsEnabled = $true
            $statusText.Text          = $apptxt.status.ready
        }
        # WTF.Console successfully launched.
        else {
            # At this point we can use $launch.data.
            # But for now ... we just close the window
            $window.Close()
        }

    }
    catch {
        $btnMount.IsEnabled       = $true
        $btnCancel.IsEnabled      = $true
        $btnOpenImage.IsEnabled   = $true
        $btnBrowseMount.IsEnabled = $true
        $chkCreateMountPoint.IsEnabled = $true
        $statusText.Text          = $apptxt.status.ready
        # Show a Win32-Dialog
        $null = wintwincore.SystemMessageBox -smbTitle "$($ducc.appname) ($($wimmount.appname))" `
        -smbText "Error while preparing WTF.Console!`n$($_.Exception.Message)" `
        -smbIcon Error -smbButtons OK
    }
})


#--------------------------------------------------------------------------------
# Launch the UI and show the window
#--------------------------------------------------------------------------------
$window.Topmost = $true
$window.Add_Loaded({
    $window.Activate()
    $window.Focus()
    $window.Topmost = $false
})

$window.ShowDialog() | Out-Null
# Cleanup ...
# Unregister wim.mounter.ps1 befeore launching the console
$null = wintwincore.UnregisterProcess -FrameworkRoot $wintwin.root -ProcessId $PID
# Show the console again
wintwincore.SetCMDstate -State Show
exit 0

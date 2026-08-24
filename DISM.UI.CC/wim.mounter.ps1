<#
.SYNOPSIS
    wim.mounter - A simple tool that helps you to mount your install.wim

.DESCRIPTION
    wim.mounter is an integral part of the DISM UI Control Center and offers
    a simple way to mount Windows images to a specific folder via a graphical interface.

.NOTES
    Creation Date: 28.03.2026  (as WinISO.ScriptFXLib)
    Last Update:   24.08.2026
    Version:       1.00.07
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
$script:app = @{
    jobid      = "wim-mount"
    configRoot = "..\core\config.json"
    jobaxnConf = "..\core\db\jobaction.json"
    configTool = Join-Path $global:approot "config.json"
    fxfile     = ""
    fxpath     = ""
    xuifile    = ""
    xuipath    = ""
    wimIndex   = ""
    lngfile    = ""
    lngpath    = ""
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
if (-not (Test-Path -LiteralPath $script:app['configRoot'])) {
    Write-Error "ducc.wim.mounter: Configuration file not found: $script:app['configRoot']"
    exit 1
}

# 2nd Step: We're trying to load the content from the config.json
try {
    $script:rootcfg = Get-Content -LiteralPath $script:app['configRoot'] -Raw | ConvertFrom-Json -ErrorAction Stop
}
catch {
    Write-Error "ducc.wim.mounter: Failed to parse $script:app['configRoot']\n$($_.Exception.Message)"
    exit 1
}

# 3rd Step: Assign important values from the global config.json
$WinTwin = @{
    root    = $script:rootcfg.path.root
    xmlui   = Join-Path $WinTwin['root'] $script:rootcfg.path.appui
    lang    = Join-Path $WinTwin['root'] $script:rootcfg.path.lang
    lib     = Join-Path $WinTwin['root'] $script:rootcfg.path.lib
    export  = Join-Path $WinTwin['root'] $script:rootcfg.path.export
    logs    = Join-Path $WinTwin['root'] $script:rootcfg.path.logs
    console = Join-Path $WinTwin['root'] $script:rootcfg.path.pstools.console
}

# 4th Step: Fallback, if no language has been passed through command line
if ([string]::IsNullOrWhiteSpace($Language)) {
    $Language = $script:rootcfg.appconfig.defaultlanguage
}

#--------------------------------------------------------------------------------
# Try to load required Libraries from the WinTwin.Fusion Framework
#--------------------------------------------------------------------------------
$script:LibOPSR  = Join-Path $WinTwin['lib'] $script:rootcfg.lib.OPSreturn
$script:LibPSACL = Join-Path $WinTwin['lib'] $script:rootcfg.lib.PSAppCoreLib
$script:LibWTFXC = Join-Path $WinTwin['lib'] $script:rootcfg.lib.WinTwinFXcore
$script:LibWTXUI = Join-Path $WinTwin['lib'] $script:rootcfg.lib.WinTwinXUI

foreach ($requiredModulePath in @($script:LibOPSR, $script:LibPSACL, $script:LibWTFXC)) {
    if (-not (Test-Path -LiteralPath $requiredModulePath -PathType Leaf)) {
        Write-Error "ducc.wim.mounter: Required module manifest not found:`n$requiredModulePath"
        exit 1
    }
}

try {
    Import-Module $script:LibOPSR -Force -ErrorAction Stop
    Import-Module $script:LibPSACL -Force -ErrorAction Stop
    Import-Module $script:LibWTFXC -Force -ErrorAction Stop
}
catch {
    Write-Error "ducc.wim.mounter: Failed to import required framework modules.`n$($_.Exception.Message)"
    exit 1
}


#--------------------------------------------------------------------------------
# Hide Console Window -> Using Function from WinTwin.FXcore
#--------------------------------------------------------------------------------
wtfxSetCMDstate -State Hide


#--------------------------------------------------------------------------------
# Time to load the other JSON Config files (using Functions from WinTwin.FXcore)
#--------------------------------------------------------------------------------

$result = wtfxLoadJSON -Path $script:app['jobaxnConf']
if ($result.code -eq 0) { $script:jobconf = $result.data }
else {
    Write-Error "ducc.wim.mounter: "+$return.message
    exit 1
}

$result = wtfxLoadJSON -Path $script:app['configTool']
if ($result.code -eq 0) { $script:toolcfg = $result.data }
else {
    Write-Error "ducc.wim.mounter: "+$return.message
    exit 1
}


#--------------------------------------------------------------------------------
# With the content from the JSON-Files, we have to configure some more vars
#--------------------------------------------------------------------------------
# Get the real action-id from the internal dism.config.json
$Script:app['jobid']  = $script:toolcfg.apptool."action-id"
# wim-mount-internal function library
$script:app['fxfile']  = $script:app['jobid']+".fx.ps1"
$script:app['fxpath']  = Join-Path $global:approot $script:app['fxfile']
# wim-mount XML-UI File
$script:app['xuifile'] = $script:app['jobid']+".main.xml"
$script:app['xuipath'] = Join-Path $WinTwin['xmlui'] $script:app['fxfile']
# wim-mount Language File
$script:app['lngfile'] = $Script:app['jobid']+"."+$Language+".json"
$script:app['lngpath'] = Join-Path $WinTwin['lang'] $script:app['lngfile']

$script:app['wimIndex'] = [int]$script:jobconf."wim-mount".index


#--------------------------------------------------------------------------------
# Try to load the wim-mounter-internal function library
#--------------------------------------------------------------------------------
if (-not (Test-Path -LiteralPath $script:app['fxpath'])) {
    Write-Error "ducc.wim.mounter: Function library directory not found:\n$script:app['fxpath']"
    exit 1
}

try {
    . $script:app['fxpath']
}
catch {
    Write-Error "ducc.wim.mounter: Failed to dot-source $script:app['fxpath']\n$($_.Exception.Message)"
    exit 1
}


#--------------------------------------------------------------------------------
# Load additional Libraries (Required to build the UI)
#--------------------------------------------------------------------------------
Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName PresentationCore
Add-Type -AssemblyName WindowsBase
Add-Type -AssemblyName System.Xml


#--------------------------------------------------------------------------------
# Try to load the language file for wim.mounter
#--------------------------------------------------------------------------------

$result = wtfxLoadJSON -Path $script:app['lngpath']
if ($result.code -eq 0) { $apptxt = $result.data }
else {
    Write-Error "ducc.wim.mounter: "+$return.message
    exit 1
}


#--------------------------------------------------------------------------------
# Try to load the XML-UI (including app icon)
#--------------------------------------------------------------------------------
$LoadXML = xuiLoadWindow -XMLfile $script:app['xuipath']
if ($LoadXML.code -eq 0) {
    $window = $LoadXML.data.Window
}

if (Test-Path -LiteralPath $global:appicon) {
    try {
        $iconImage = [System.Windows.Media.Imaging.BitmapImage]::new([System.Uri]::new($global:appicon))
        $window.Icon = $iconImage
    }
    catch {
        Write-Verbose "ducc.wim.mounter: Could not set window icon: $($_.Exception.Message)"
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
$statusInfo.Text             = $script:toolcfg.appinfo.name+" ("+$script:toolcfg.appinfo.version+")"

if (Test-Path -LiteralPath $global:appicon) {
    try {
        $titleBarLogo.Source = [System.Windows.Media.Imaging.BitmapImage]::new([System.Uri]::new($global:appicon))
    }
    catch {
        Write-Verbose "ducc.wim.mounter: Could not set title bar logo: $($_.Exception.Message)"
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

$btnClose.Add_Click({ $window.Close() })
$titleBarPanel.Add_MouseLeftButtonDown({ param($senderObj, $eventArgs) $window.DragMove() })

$btnOpenImage.Add_Click({
    Clear-FieldError -TextBox $txtImageFile
    $filePicker = xuiSelectFile -Title $apptxt.dialogs.fileDialogTitle -Filter $apptxt.dialogs.fileDialogFilterName+"|*.wim"
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
    $createMountPoint = [bool]$chkCreateMountPoint.IsChecked
    $hasError = $false

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

    if (-not (Test-Path -LiteralPath $WinTwin['console'] -PathType Leaf)) {
        [System.Windows.MessageBox]::Show(
            "WTF.Console.ps1 was not found:`n$WinTwin['console']",
            'DISM.UI.CC - wim.mounter',
            [System.Windows.MessageBoxButton]::OK,
            [System.Windows.MessageBoxImage]::Error
        ) | Out-Null
        return
    }

    $btnMount.IsEnabled       = $false
    $btnCancel.IsEnabled      = $false
    $btnOpenImage.IsEnabled   = $false
    $btnBrowseMount.IsEnabled = $false
    $chkCreateMountPoint.IsEnabled = $false
    $statusText.Text          = $apptxt.status.mounting

    try {
        # Create the Mount-Script for WTF.Console
        $scriptContent = @"
`$ErrorActionPreference = 'Stop'
Write-Output '========================================'
Write-Output 'WIM MOUNT JOB STARTED'
Write-Output '========================================'
Write-Output ('WIM file    : {0}' -f '$($imagePath.Replace("'", "''"))')
Write-Output ('Mount dir   : {0}' -f '$($imagePath.Replace("'", "''"))')
Write-Output ('WIM index   : {0}' -f '$($script:app['wimIndex'])')
Write-Output ('Create path : {0}' -f '$createMountPoint')

`$moduleCandidates = @(
    '$script:LibOPSR',
    '$script:LibPSACL',
    '$script:LibWTFXC'
) | Where-Object { -not [string]::IsNullOrWhiteSpace(`$_) }

foreach (`$modulePath in `$moduleCandidates) {
    if (-not (Test-Path -LiteralPath `$modulePath)) {
        throw ('Required module path not found: {0}' -f `$modulePath)
    }
    Import-Module `$modulePath -Force -ErrorAction Stop
}

if ($CreateMountPoint -and -not (Test-Path -LiteralPath '$($mountDir.Replace("'", "''"))')) {
    Write-Output 'Mount point does not exist. Creating directory via CreateNewDir...'
    `$createResult = CreateNewDir -Path '$($mountDir.Replace("'", "''"))' -Force -Confirm:`$false
    if (`$createResult.code -ne 0) {
        throw ('CreateNewDir failed: {0}' -f `$createResult.msg)
    }
}

Write-Output 'Mounting image via MountWIMimage...'
`$mountResult = MountWIMimage -WIMimage '$($imagePath.Replace("'", "''"))' -IndexNo $script:app['wimIndex'] -MountPoint '$($mountDir.Replace("'", "''"))'
if (`$mountResult.code -ne 0) {
    throw `$mountResult.msg
}

Write-Output `$mountResult.msg
Write-Output 'The operation completed successfully.'
exit 0
"@
        
        $scriptFile = Join-Path $WinTwin['export'] $script:toolcfg.apptool."wim-mount".console[1]
        $result = wtfxConsoleScript -ScriptPath $scriptFile `
                                   -ScriptType ps1 `
                                   -ScriptData $scriptContent
        if ($result.code -eq 0) { $result.data.Path }
        
        if (-not (Test-Path -LiteralPath $WinTwin['logs'])) {
            $createLogDir = CreateNewDir -Path $WinTwin['logs'] -Force -Confirm:$false
            if ($createLogDir.code -ne 0 -and -not (Test-Path -LiteralPath $WinTwin['logs'] -PathType Container)) {
                throw $createLogDir.msg
            }
        }

        $timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
        if (($script:jobconf."wim-mount".logfile[0] -eq $true) -and (Test-Path $script:jobconf."wim-mount".logfile[1])) {
            $logPattern = [string]$script:jobconf."wim-mount".logfile[1]
        } else {
            $logPattern = Join-Path $WinTwin['logs'] '[DATETIME].wim.mounter.log'
        }
        $logFileName = $logPattern -replace '\[DATETIME\]', $timestamp
        $logFilePath = $logFileName

        $logInitResult = wtfxWriteLogmsg -Logfile $logFilePath -Message 'wim.mounter launched WTF.Console mount workflow.' -Flag INFO -Override 0 -Confirm:$false
        if ($logInitResult.code -ne 0) {
            Write-Verbose "ducc.wim.mounter: Failed to precreate log file: $($logInitResult.msg)"
        }

        # Launch the WTF.Console Process
        # Typical wim.mounter hand-off after the tool has cleared process.json:
        $launch = wtfxLaunchConsole -Script $scriptFile `
                                    -Mode framework `
                                    -Action $script:app['jobid'] `
                                    -Logging $true `
                                    -Logfile $logFilePath `
                                    -FrameworkRoot $WinTwin['root']

        $statusText.Text = $apptxt.status.launchingConsole
        # Close & Exit win.mounter
        $window.Close()
    }
    catch {
        $btnMount.IsEnabled       = $true
        $btnCancel.IsEnabled      = $true
        $btnOpenImage.IsEnabled   = $true
        $btnBrowseMount.IsEnabled = $true
        $chkCreateMountPoint.IsEnabled = $true
        $statusText.Text          = $apptxt.status.ready

        [System.Windows.MessageBox]::Show(
            $_.Exception.Message,
            'DISM.UI.CC - wim.mounter',
            [System.Windows.MessageBoxButton]::OK,
            [System.Windows.MessageBoxImage]::Error
        ) | Out-Null
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
exit 0

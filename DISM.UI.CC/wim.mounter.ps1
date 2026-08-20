[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$Language = ""
)

$global:approot   = $PSScriptRoot
$global:appicon   = Join-Path $PSScriptRoot "DISM.UI.CC.ico"
$duccappid        = "wim.mounter"
$configRoot       = "..\core\config.json"
$configTool       = Join-Path $PSScriptRoot "config.json"

if (-not (Test-Path -LiteralPath $configRoot)) {
    Write-Error "ducc.wim.mounter: Configuration file not found: $configRoot"
    exit 1
}
if (-not (Test-Path -LiteralPath $configTool)) {
    Write-Error "ducc.wim.mounter: Configuration file not found: $configTool"
    exit 1
}

try {
    $global:cfg = Get-Content -LiteralPath $configRoot -Raw | ConvertFrom-Json -ErrorAction Stop
}
catch {
    Write-Error "ducc.wim.mounter: Failed to parse $configRoot\n$($_.Exception.Message)"
    exit 1
}

try {
    $global:appcfg = Get-Content -LiteralPath $configTool -Raw | ConvertFrom-Json -ErrorAction Stop
}
catch {
    Write-Error "ducc.wim.mounter: Failed to parse $configTool\n$($_.Exception.Message)"
    exit 1
}

$global:root       = $global:cfg.path.root
$global:uipath     = Join-Path $global:root $global:cfg.path.appui
$global:langpath   = Join-Path $global:root $global:cfg.path.lang
$global:modulesDir = Join-Path $global:root $global:cfg.path.modules
$appfxfile         = $duccappid+".fx.ps1"
$global:fxpath     = Join-Path $global:approot $appfxfile
$appxmlui          = $duccappid+".main.xml"
$global:mainwin    = Join-Path $global:uipath $appxmlui
$global:wimIndex   = [int]$global:cfg.wim.index
$global:exportPath = Join-Path $global:root $global:cfg.path.export
$global:logPath    = Join-Path $global:root $global:cfg.path.logfiles
$global:psToolsPath = Join-Path $global:root $global:cfg.path.pstools
$global:wtfConsolePath = Join-Path $global:psToolsPath 'WTF.Console.ps1'

$global:opsReturnModulePath   = Join-Path $global:modulesDir 'OPSreturn\OPSreturn.psd1'
$global:psAppCoreLibModulePath = Join-Path $global:modulesDir 'PSAppCoreLib\PSAppCoreLib.psd1'
$global:winTwinFXcoreModulePath = Join-Path $global:modulesDir 'WinTwin.FXcore\WinTwin.FXcore.psd1'

if ([string]::IsNullOrWhiteSpace($Language)) {
    $Language = $global:cfg.appconfig.defaultlanguage
}

foreach ($requiredModulePath in @($global:opsReturnModulePath, $global:psAppCoreLibModulePath, $global:winTwinFXcoreModulePath)) {
    if (-not (Test-Path -LiteralPath $requiredModulePath -PathType Leaf)) {
        Write-Error "ducc.wim.mounter: Required module manifest not found:`n$requiredModulePath"
        exit 1
    }
}

try {
    Import-Module $global:opsReturnModulePath -Force -ErrorAction Stop
    Import-Module $global:psAppCoreLibModulePath -Force -ErrorAction Stop
    Import-Module $global:winTwinFXcoreModulePath -Force -ErrorAction Stop
}
catch {
    Write-Error "ducc.wim.mounter: Failed to import required framework modules.`n$($_.Exception.Message)"
    exit 1
}

if (-not (Test-Path -LiteralPath $global:fxpath)) {
    Write-Error "ducc.wim.mounter: Function library directory not found:\n$global:fxpath"
    exit 1
}

try {
    . $global:fxpath
}
catch {
    Write-Error "ducc.wim.mounter: Failed to dot-source $global:fxpath\n$($_.Exception.Message)"
    exit 1
}

Set-ConsoleWindowState -Mode 6

Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName PresentationCore
Add-Type -AssemblyName WindowsBase
Add-Type -AssemblyName System.Xml

$applangfile = $duccappid+"."+$Language+".json"
$applangpath = Join-Path $global:langpath $applangfile
try {
    $apptxt = Get-Content -LiteralPath $applangpath -Raw | ConvertFrom-Json -ErrorAction Stop
}
catch {
    Write-Error "ducc.wim.mounter: Failed to parse $applangpath\n$($_.Exception.Message)"
    exit 1
}

try {
    $window = Import-XamlWindow -XamlFilePath $global:mainwin
}
catch {
    Write-Error $_.Exception.Message
    exit 1
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
$statusInfo.Text             = $global:appcfg.appinfo.name+" ("+$global:appcfg.appinfo.version+")"

if (Test-Path -LiteralPath $global:appicon) {
    try {
        $titleBarLogo.Source = [System.Windows.Media.Imaging.BitmapImage]::new([System.Uri]::new($global:appicon))
    }
    catch {
        Write-Verbose "ducc.wim.mounter: Could not set title bar logo: $($_.Exception.Message)"
    }
}

function Reset-FormState {
    $txtImageFile.Text  = ""
    $txtMountPoint.Text = ""
    $chkCreateMountPoint.IsChecked = $true
    Clear-FieldError -TextBox $txtImageFile
    Clear-FieldError -TextBox $txtMountPoint
    $statusText.Text = $apptxt.status.ready
}

$btnClose.Add_Click({ $window.Close() })
$titleBarPanel.Add_MouseLeftButtonDown({ param($senderObj, $eventArgs) $window.DragMove() })

$btnOpenImage.Add_Click({
    Clear-FieldError -TextBox $txtImageFile
    $selectedFile = Select-WimFile -DialogTitle $apptxt.dialogs.fileDialogTitle -FilterName  $apptxt.dialogs.fileDialogFilterName
    if ($null -ne $selectedFile) { $txtImageFile.Text = $selectedFile } else { $txtImageFile.Text = "" }
})

$btnBrowseMount.Add_Click({
    Clear-FieldError -TextBox $txtMountPoint
    $selectedFolder = Select-MountFolder -DialogTitle $apptxt.dialogs.folderDialogTitle
    if ($null -ne $selectedFolder) { $txtMountPoint.Text = $selectedFolder } else { $txtMountPoint.Text = "" }
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

    if (-not (Test-Path -LiteralPath $global:wtfConsolePath -PathType Leaf)) {
        [System.Windows.MessageBox]::Show(
            "WTF.Console.ps1 was not found:`n$global:wtfConsolePath",
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
        $mountScriptPath = New-WimMountConsoleScript `
            -ExportDirectory $global:exportPath `
            -WimFilePath $imagePath `
            -MountDirectory $mountDir `
            -WimIndex $global:wimIndex `
            -CreateMountPoint $createMountPoint `
            -ModulesRoot $global:modulesDir `
            -OpsReturnModulePath $global:opsReturnModulePath `
            -PSAppCoreLibModulePath $global:psAppCoreLibModulePath `
            -WinTwinFXcoreModulePath $global:winTwinFXcoreModulePath

        if (-not (Test-Path -LiteralPath $global:logPath)) {
            $createLogDir = CreateNewDir -Path $global:logPath -Force -Confirm:$false
            if ($createLogDir.code -ne 0 -and -not (Test-Path -LiteralPath $global:logPath -PathType Container)) {
                throw $createLogDir.msg
            }
        }

        $logPattern = '[DATETIME].wim.mounter.log'
        if ($global:cfg.console.logfile.mount) {
            $logPattern = [string]$global:cfg.console.logfile.mount
        }
        $timestamp = Get-Date -Format 'yyyyMMdd-HHmm'
        $logFileName = $logPattern -replace '\[DATETIME\]', $timestamp
        $logFilePath = Join-Path $global:logPath $logFileName

        $logInitResult = WriteLogMessage -Logfile $logFilePath -Message 'wim.mounter launched WTF.Console mount workflow.' -Flag INFO -Override 0 -Confirm:$false
        if ($logInitResult.code -ne 0) {
            Write-Verbose "ducc.wim.mounter: Failed to precreate log file: $($logInitResult.msg)"
        }

        $statusText.Text = $apptxt.status.launchingConsole
        $null = Start-WtfConsoleProcess -WtfConsolePath $global:wtfConsolePath -MountScriptPath $mountScriptPath -LogFilePath $logFilePath -Language $Language -Action 'mount'
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

$window.Topmost = $true
$window.Add_Loaded({
    $window.Activate()
    $window.Focus()
    $window.Topmost = $false
})

$window.ShowDialog() | Out-Null
exit 0

<#
.SYNOPSIS
    wim.mounter.ps1 - Mounts a Windows Image (*.wim) file into a
    target directory using DISM, presented through a PowerEdge-style dark WPF UI.

.DESCRIPTION
    wim.mounter.ps1 opens a single, non-resizable, always-centered WPF
    window (frameless, custom title bar, close button only) that lets the
    user pick a *.wim file and a target mount directory, then mounts the
    image via "DISM /Mount-Wim" inside a separate, visible console window.

    Every UI text is loaded from an external JSON language file
    (data\lang\<code>.json, default: en-us.json) and the entire window layout
    is loaded from an external XAML file (data\ui\main.window.xml) - no
    inline XAML and no hardcoded UI strings exist anywhere in this script.

    Validation errors are NOT shown as message boxes. Instead, the affected
    input field simply turns red (see Show-FieldError in data\fxlib\Functions.ps1)
    until the user provides a valid value.

.PARAMETER Language
    Optional language code (e.g. "en-us", "de-de"). Defaults to the value
    configured in data\config.json ("defaultlanguage"), which itself
    defaults to "en-us".

.EXAMPLE
    .\wim.mounter.ps1

.EXAMPLE
    .\wim.mounter.ps1 -Language de-de

.NOTES
    Creation Date: 18.08.2026
    Version:       1.00.02
    Author:        praetoriani

    REQUIREMENTS:
    - PowerShell 5.1 or higher (PowerShell 7.x recommended - see Select-MountFolder
      in Functions.ps1 for why 7.x gives the more modern folder-picker dialog)
    - .NET Framework 4.7.2+ / .NET 5+ (for WPF)
    - Windows ADK / Windows itself must provide DISM.exe (included by default
      on all Windows 10/11 client and server editions)
    - Administrative privileges are required for "DISM /Mount-Wim" to succeed
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$Language = ""
)

# ─────────────────────────────────────────────────────────────────────────────
# GLOBAL PATH CONSTANTS
# ─────────────────────────────────────────────────────────────────────────────
$global:approot   = $PSScriptRoot
$global:appicon   = Join-Path $PSScriptRoot "DISM.UI.CC.ico"
$duccappid        = "wim.mounter"
# Global WinTwin Fusion config
$configRoot       = "..\core\config.json"
# Local (app-internal) config
$configTool       = Join-Path $PSScriptRoot "config.json"

# ─────────────────────────────────────────────────────────────────────────────
# LOAD CONFIGURATION (data\config.json)
# ─────────────────────────────────────────────────────────────────────────────
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

$global:root     = $global:cfg.path.root
$global:uipath   = Join-Path $global:root $global:cfg.path.appui
$global:langpath = Join-Path $global:root $global:cfg.path.lang
$appfxfile       = $duccappid+".fx.ps1"
$global:fxpath   = Join-Path $global:approot $appfxfile
$appxmlui        = $duccappid+".main.xml"
$global:mainwin  = Join-Path $global:uipath $appxmlui
$global:wimIndex = $global:cfg.wim.index

if ([string]::IsNullOrWhiteSpace($Language)) {
    $Language = $global:cfg.appconfig.defaultlanguage
}

# ─────────────────────────────────────────────────────────────────────────────
# DOT-SOURCE EXTERNAL FUNCTION LIBRARY (data\fxlib) - same pattern as PowerEdge
# ─────────────────────────────────────────────────────────────────────────────
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

# ─────────────────────────────────────────────────────────────────────────────
# MINIMIZE THE CONSOLE WINDOW IMMEDIATELY (P/Invoke, same pattern as PowerEdge)
# ─────────────────────────────────────────────────────────────────────────────
Set-ConsoleWindowState -Mode 6   # 6 = SW_MINIMIZE

# ─────────────────────────────────────────────────────────────────────────────
# LOAD WPF ASSEMBLIES
# ─────────────────────────────────────────────────────────────────────────────
Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName PresentationCore
Add-Type -AssemblyName WindowsBase
Add-Type -AssemblyName System.Xml

# ─────────────────────────────────────────────────────────────────────────────
# LOAD LANGUAGE TABLE (data\lang\<code>.json)
# ─────────────────────────────────────────────────────────────────────────────
$applangfile = $duccappid+"."+$Language+".json"
$applangpath = Join-Path $global:langpath $applangfile
try {
    $apptxt = Get-Content -LiteralPath $applangpath -Raw | ConvertFrom-Json -ErrorAction Stop
}
catch {
    Write-Error "ducc.wim.mounter: Failed to parse $applangpath\n$($_.Exception.Message)"
    exit 1
}
# DEPRECATED
#try {
#    $lang = Get-LanguageTable -LangDirectory $global:langpath -LanguageCode $Language
#}
#catch {
#    Write-Error $_.Exception.Message
#    exit 1
#}

# ─────────────────────────────────────────────────────────────────────────────
# LOAD THE EXTERNAL XAML UI (data\ui\main.window.xml)
# ─────────────────────────────────────────────────────────────────────────────
try {
    $window = Import-XamlWindow -XamlFilePath $global:mainwin
}
catch {
    Write-Error $_.Exception.Message
    exit 1
}

# Apply the application icon (if present)
if (Test-Path -LiteralPath $global:appicon) {
    try {
        $iconImage = [System.Windows.Media.Imaging.BitmapImage]::new([System.Uri]::new($global:appicon))
        $window.Icon = $iconImage
    }
    catch {
        Write-Verbose "ducc.wim.mounter: Could not set window icon: $($_.Exception.Message)"
    }
}

# ─────────────────────────────────────────────────────────────────────────────
# RESOLVE NAMED XAML ELEMENTS
# ─────────────────────────────────────────────────────────────────────────────
$titleBarPanel  = $window.FindName("TitleBarPanel")
$titleBarText   = $window.FindName("TitleBarText")
$titleBarLogo   = $window.FindName("TitleBarLogo")
$btnClose       = $window.FindName("BtnClose")

$lblInstructions = $window.FindName("LblInstructions")
$lblImageFile     = $window.FindName("LblImageFile")
$lblMountPoint    = $window.FindName("LblMountPoint")

$txtImageFile    = $window.FindName("TxtImageFile")
$btnOpenImage    = $window.FindName("BtnOpenImage")
$txtMountPoint   = $window.FindName("TxtMountPoint")
$btnBrowseMount  = $window.FindName("BtnBrowseMount")

$btnMount        = $window.FindName("BtnMount")
$btnCancel       = $window.FindName("BtnCancel")
$btnExit         = $window.FindName("BtnExit")

$statusText      = $window.FindName("StatusText")
$statusInfo      = $window.FindName("StatusInfo")

# ─────────────────────────────────────────────────────────────────────────────
# APPLY LOCALIZED TEXTS FROM THE LANGUAGE TABLE
# ─────────────────────────────────────────────────────────────────────────────
$window.Title              = $apptxt.window.title
$titleBarText.Text         = $apptxt.window.title
$lblInstructions.Text      = $apptxt.labels.instructions
$lblImageFile.Text         = $apptxt.labels.imageFile
$lblMountPoint.Text        = $apptxt.labels.mountPoint
$btnOpenImage.ToolTip      = $apptxt.buttons.openTooltip
$btnBrowseMount.ToolTip    = $apptxt.buttons.browseTooltip
$btnMount.Content          = $apptxt.buttons.mount
$btnCancel.Content         = $apptxt.buttons.cancel
$btnExit.Content           = $apptxt.buttons.exit
$statusText.Text           = $apptxt.status.ready
$statusInfo.Text           = $global:appcfg.appinfo.name+" ("+$global:appcfg.appinfo.version+")"

if (Test-Path -LiteralPath $global:appicon) {
    try {
        $titleBarLogo.Source = [System.Windows.Media.Imaging.BitmapImage]::new([System.Uri]::new($global:appicon))
    }
    catch {
        Write-Verbose "ducc.wim.mounter: Could not set title bar logo: $($_.Exception.Message)"
    }
}

# ─────────────────────────────────────────────────────────────────────────────
# HELPER: RESET THE FORM TO ITS INITIAL STATE
# ─────────────────────────────────────────────────────────────────────────────
function Reset-FormState {
    $txtImageFile.Text  = ""
    $txtMountPoint.Text = ""
    Clear-FieldError -TextBox $txtImageFile
    Clear-FieldError -TextBox $txtMountPoint
    $statusText.Text = $apptxt.status.ready
}

# ─────────────────────────────────────────────────────────────────────────────
# EVENT WIRING - WINDOW CHROME
# ─────────────────────────────────────────────────────────────────────────────
$btnClose.Add_Click({ $window.Close() })

$titleBarPanel.Add_MouseLeftButtonDown({
    param($senderObj, $eventArgs)
    $window.DragMove()
})

# ─────────────────────────────────────────────────────────────────────────────
# EVENT WIRING - IMAGE FILE PICKER
# ─────────────────────────────────────────────────────────────────────────────
$btnOpenImage.Add_Click({
    Clear-FieldError -TextBox $txtImageFile

    $selectedFile = Select-WimFile -DialogTitle $apptxt.dialogs.fileDialogTitle `
                                    -FilterName  $apptxt.dialogs.fileDialogFilterName

    if ($null -ne $selectedFile) {
        $txtImageFile.Text = $selectedFile
    }
    else {
        # No selection / Cancel -> clear the field, as requested
        $txtImageFile.Text = ""
    }
})

# ─────────────────────────────────────────────────────────────────────────────
# EVENT WIRING - MOUNT POINT FOLDER PICKER
# ─────────────────────────────────────────────────────────────────────────────
$btnBrowseMount.Add_Click({
    Clear-FieldError -TextBox $txtMountPoint

    $selectedFolder = Select-MountFolder -DialogTitle $apptxt.dialogs.folderDialogTitle

    if ($null -ne $selectedFolder) {
        $txtMountPoint.Text = $selectedFolder
    }
    else {
        # No selection / Cancel -> clear the field, as requested
        $txtMountPoint.Text = ""
    }
})

# ─────────────────────────────────────────────────────────────────────────────
# EVENT WIRING - CANCEL BUTTON (clears both input fields)
# ─────────────────────────────────────────────────────────────────────────────
$btnCancel.Add_Click({
    Reset-FormState
})

# ─────────────────────────────────────────────────────────────────────────────
# EVENT WIRING - EXIT BUTTON (closes immediately, no confirmation)
# ─────────────────────────────────────────────────────────────────────────────
$btnExit.Add_Click({
    $window.Close()
})

# ─────────────────────────────────────────────────────────────────────────────
# EVENT WIRING - MOUNT BUTTON
# Validates both fields; on any error the affected field turns red instead of
# showing a message box, and the mount process is aborted. Only if both
# fields are valid, DISM is invoked in a new, visible console window.
# ─────────────────────────────────────────────────────────────────────────────
$btnMount.Add_Click({

    $imagePath = $txtImageFile.Text
    $mountDir  = $txtMountPoint.Text

    $hasError = $false

    # Validate the image file field
    if ([string]::IsNullOrWhiteSpace($imagePath) -or
        -not (Test-Path -LiteralPath $imagePath -PathType Leaf) -or
        ([System.IO.Path]::GetExtension($imagePath).ToLowerInvariant() -ne ".wim")) {
        Show-FieldError -TextBox $txtImageFile
        $hasError = $true
    }
    else {
        Clear-FieldError -TextBox $txtImageFile
    }

    # Validate the mount point field
    if ([string]::IsNullOrWhiteSpace($mountDir) -or
        -not (Test-Path -LiteralPath $mountDir -PathType Container)) {
        Show-FieldError -TextBox $txtMountPoint
        $hasError = $true
    }
    else {
        Clear-FieldError -TextBox $txtMountPoint
    }

    if ($hasError) {
        return
    }

    # Both fields are valid -> disable the form and run DISM
    $btnMount.IsEnabled       = $false
    $btnCancel.IsEnabled      = $false
    $btnOpenImage.IsEnabled   = $false
    $btnBrowseMount.IsEnabled = $false
    $statusText.Text          = $apptxt.status.mounting

    $mountResult = Invoke-DismMount -WimFilePath $imagePath `
                                     -MountDirectory $mountDir `
                                     -WimIndex $global:wimIndex

    # Re-enable the form and reset it to its initial state, regardless of
    # the DISM exit code (per the specified behaviour).
    $btnMount.IsEnabled       = $true
    $btnCancel.IsEnabled      = $true
    $btnOpenImage.IsEnabled   = $true
    $btnBrowseMount.IsEnabled = $true

    Reset-FormState
})

# ─────────────────────────────────────────────────────────────────────────────
# SHOW THE WINDOW (centered via WindowStartupLocation="CenterScreen" in XAML)
# ─────────────────────────────────────────────────────────────────────────────
$window.Topmost = $true
$window.Add_Loaded({
    $window.Activate()
    $window.Focus()
    $window.Topmost = $false
})

$window.ShowDialog() | Out-Null

Write-Verbose "ducc.wim.mounter: Application closed cleanly."
exit 0

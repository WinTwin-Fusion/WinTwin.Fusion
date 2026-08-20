function Set-ConsoleWindowState {
    [CmdletBinding()]
    param([int]$Mode = 6)

    if (-not ("WinIsoNativeMethods" -as [type])) {
        Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
public class WinIsoNativeMethods {
    [DllImport("user32.dll")]
    public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
    [DllImport("kernel32.dll")]
    public static extern IntPtr GetConsoleWindow();
}
"@ -ErrorAction SilentlyContinue
    }

    try {
        $consoleHandle = [WinIsoNativeMethods]::GetConsoleWindow()
        if ($consoleHandle -ne [IntPtr]::Zero) {
            [WinIsoNativeMethods]::ShowWindow($consoleHandle, $Mode) | Out-Null
        }
    }
    catch {
        Write-Verbose "ducc.wim.mounter: Could not change console window state: $($_.Exception.Message)"
    }
}

function Import-XamlWindow {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string]$XamlFilePath)

    if (-not (Test-Path -LiteralPath $XamlFilePath)) {
        throw "ducc.wim.mounter: XAML file not found: $XamlFilePath"
    }

    try {
        [xml]$xamlDoc = Get-Content -LiteralPath $XamlFilePath -Raw
        $reader = [System.Xml.XmlNodeReader]::new($xamlDoc)
        $window = [System.Windows.Markup.XamlReader]::Load($reader)
        if ($null -eq $window) {
            throw "XamlReader returned null while parsing $XamlFilePath"
        }
        return $window
    }
    catch {
        throw "ducc.wim.mounter: Failed to load XAML UI ('$XamlFilePath'): $($_.Exception.Message)"
    }
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

function Select-WimFile {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$DialogTitle,
        [Parameter(Mandatory = $true)][string]$FilterName
    )

    Add-Type -AssemblyName System.Windows.Forms -ErrorAction SilentlyContinue
    $dialog = New-Object System.Windows.Forms.OpenFileDialog
    $dialog.Title            = $DialogTitle
    $dialog.Filter           = "$FilterName|*.wim"
    $dialog.CheckFileExists  = $true
    $dialog.Multiselect      = $false
    $dialog.RestoreDirectory = $true
    $result = $dialog.ShowDialog()
    if ($result -eq [System.Windows.Forms.DialogResult]::OK -and -not [string]::IsNullOrWhiteSpace($dialog.FileName)) {
        return $dialog.FileName
    }
    return $null
}

function Select-MountFolder {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string]$DialogTitle)

    Add-Type -AssemblyName System.Windows.Forms -ErrorAction SilentlyContinue
    $dialog = New-Object System.Windows.Forms.FolderBrowserDialog
    $dialog.Description = $DialogTitle
    $dialog.UseDescriptionForTitle = $true
    $dialog.ShowNewFolderButton = $true
    $result = $dialog.ShowDialog()
    if ($result -eq [System.Windows.Forms.DialogResult]::OK -and -not [string]::IsNullOrWhiteSpace($dialog.SelectedPath)) {
        return $dialog.SelectedPath
    }
    return $null
}

function New-WimMountConsoleScript {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$ExportDirectory,
        [Parameter(Mandatory = $true)][string]$WimFilePath,
        [Parameter(Mandatory = $true)][string]$MountDirectory,
        [Parameter(Mandatory = $false)][int]$WimIndex = 1,
        [Parameter(Mandatory = $false)][bool]$CreateMountPoint = $false,
        [Parameter(Mandatory = $false)][string]$ModulesRoot,
        [Parameter(Mandatory = $false)][string]$OpsReturnModulePath,
        [Parameter(Mandatory = $false)][string]$PSAppCoreLibModulePath,
        [Parameter(Mandatory = $false)][string]$WinTwinFXcoreModulePath
    )

    if (-not (Test-Path -LiteralPath $ExportDirectory)) {
        New-Item -ItemType Directory -Path $ExportDirectory -Force | Out-Null
    }

    $scriptPath = Join-Path $ExportDirectory 'mount.image.ps1'

    $opsLiteral  = if ([string]::IsNullOrWhiteSpace($OpsReturnModulePath)) { '' } else { $OpsReturnModulePath.Replace("'", "''") }
    $psaLiteral  = if ([string]::IsNullOrWhiteSpace($PSAppCoreLibModulePath)) { '' } else { $PSAppCoreLibModulePath.Replace("'", "''") }
    $fxcLiteral  = if ([string]::IsNullOrWhiteSpace($WinTwinFXcoreModulePath)) { '' } else { $WinTwinFXcoreModulePath.Replace("'", "''") }
    $rootLiteral = if ([string]::IsNullOrWhiteSpace($ModulesRoot)) { '' } else { $ModulesRoot.Replace("'", "''") }

    $scriptContent = @"
`$ErrorActionPreference = 'Stop'
Write-Output '========================================'
Write-Output 'WIM MOUNT JOB STARTED'
Write-Output '========================================'
Write-Output ('WIM file    : {0}' -f '$($WimFilePath.Replace("'", "''"))')
Write-Output ('Mount dir   : {0}' -f '$($MountDirectory.Replace("'", "''"))')
Write-Output ('WIM index   : {0}' -f '$WimIndex')
Write-Output ('Create path : {0}' -f '$CreateMountPoint')

`$moduleCandidates = @(
    '$opsLiteral',
    '$psaLiteral',
    '$fxcLiteral'
) | Where-Object { -not [string]::IsNullOrWhiteSpace(`$_) }

foreach (`$modulePath in `$moduleCandidates) {
    if (-not (Test-Path -LiteralPath `$modulePath)) {
        throw ('Required module path not found: {0}' -f `$modulePath)
    }
    Import-Module `$modulePath -Force -ErrorAction Stop
}

if ($CreateMountPoint -and -not (Test-Path -LiteralPath '$($MountDirectory.Replace("'", "''"))')) {
    Write-Output 'Mount point does not exist. Creating directory via CreateNewDir...'
    `$createResult = CreateNewDir -Path '$($MountDirectory.Replace("'", "''"))' -Force -Confirm:`$false
    if (`$createResult.code -ne 0) {
        throw ('CreateNewDir failed: {0}' -f `$createResult.msg)
    }
}

Write-Output 'Mounting image via MountWIMimage...'
`$mountResult = MountWIMimage -WIMimage '$($WimFilePath.Replace("'", "''"))' -IndexNo $WimIndex -MountPoint '$($MountDirectory.Replace("'", "''"))'
if (`$mountResult.code -ne 0) {
    throw `$mountResult.msg
}

Write-Output `$mountResult.msg
Write-Output 'The operation completed successfully.'
exit 0
"@

    Set-Content -LiteralPath $scriptPath -Value $scriptContent -Encoding UTF8
    return $scriptPath
}

function Start-WtfConsoleProcess {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$WtfConsolePath,
        [Parameter(Mandatory = $true)][string]$MountScriptPath,
        [Parameter(Mandatory = $true)][string]$LogFilePath,
        [Parameter(Mandatory = $false)][string]$Language = 'en-us',
        [Parameter(Mandatory = $false)][string]$Action = 'mount'
    )

    $argList = @(
        '-NoLogo',
        '-NoProfile',
        '-ExecutionPolicy', 'Bypass',
        '-File', $WtfConsolePath,
        '-ScriptPath', $MountScriptPath,
        '-AppMode', 'framework',
        '-Action', $Action,
        '-Language', $Language,
        '-LogFilePath', $LogFilePath
    )

    $processResult = RunProcess -FilePath "$($PSHOME)\powershell.exe" -ArgumentList $argList -WindowStyle Normal -Confirm:$false
    if ($processResult.code -ne 0) {
        throw $processResult.msg
    }

    return $processResult.data
}

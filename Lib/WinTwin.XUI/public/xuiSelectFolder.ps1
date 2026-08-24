function xuiSelectFolder {
    <#
    .SYNOPSIS
        Shows the standard Windows folder-browser dialog and returns the selected path.

    .DESCRIPTION
        xuiSelectFolder is the generic WinTwin.XUI replacement for Select-MountFolder
        from DISM.UI.CC\wim.mounter.fx.ps1.

        The original helper only accepted a dialog title. This function keeps that
        behaviour and adds the options needed for framework-wide reuse:

          - -Title / -Description for the dialog caption
          - -InitialDirectory to preselect a folder
          - -ShowNewFolderButton (default: true, matching the original)
          - dialog is forced to the foreground via a hidden TopMost owner form

        Always returns an OPSreturn object. Cancellation is reported as a non-success
        code so callers can branch on .code without treating cancel as a crash.

    .PARAMETER Title
        Dialog title / description. Mapped to FolderBrowserDialog.Description and,
        where supported, UseDescriptionForTitle.

    .PARAMETER InitialDirectory
        Optional folder that should be preselected.

    .PARAMETER ShowNewFolderButton
        Defaults to $true, matching Select-MountFolder.

    .OUTPUTS
        PSCustomObject from OPSreturn.
        Success .data: Path, Title.

    .EXAMPLE
        $pick = xuiSelectFolder -Title 'Please select a mount point.'
        if ($pick.code -eq 0) { $txtMountPoint.Text = $pick.data.Path }

    .NOTES
        Part of: WinTwin.XUI
        Alias : xuiOpenPath  (name used in the functional documentation)
        Replaces: Select-MountFolder
        See also: xuiSelectFile, xuiLoadWindow, OPSreturn
    #>

    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    [Alias('xuiOpenPath')]
    param(
        [Parameter(Mandatory = $false)]
        [AllowEmptyString()]
        [Alias('Description')]
        [string]$Title = 'Select a folder',

        [Parameter(Mandatory = $false)]
        [AllowEmptyString()]
        [Alias('SelectedPath')]
        [string]$InitialDirectory = '',

        [Parameter(Mandatory = $false)]
        [bool]$ShowNewFolderButton = $true
    )

    try {
        Add-Type -AssemblyName System.Windows.Forms -ErrorAction Stop
    }
    catch {
        return (OPSreturn -Code fail -Message "xuiSelectFolder failed! System.Windows.Forms could not be loaded: $($_.Exception.Message)" -Exception $_.Exception)
    }

    $owner  = $null
    $dialog = $null
    try {
        $owner  = Get-XuiDialogOwner
        $dialog = New-Object System.Windows.Forms.FolderBrowserDialog
        $dialog.Description         = $(if ([string]::IsNullOrWhiteSpace($Title)) { 'Select a folder' } else { $Title })
        $dialog.ShowNewFolderButton = $ShowNewFolderButton

        # UseDescriptionForTitle exists on .NET 4.7.2+ / Windows Forms 4.8.
        if ($null -ne ($dialog.PSObject.Properties['UseDescriptionForTitle'])) {
            $dialog.UseDescriptionForTitle = $true
        }

        if (-not [string]::IsNullOrWhiteSpace($InitialDirectory) -and (Test-Path -LiteralPath $InitialDirectory -PathType Container)) {
            $dialog.SelectedPath = $InitialDirectory
        }

        $result = $dialog.ShowDialog($owner)
        if ($result -ne [System.Windows.Forms.DialogResult]::OK) {
            return (OPSreturn -Code info -Message "xuiSelectFolder: Dialog was cancelled.")
        }

        if ([string]::IsNullOrWhiteSpace($dialog.SelectedPath)) {
            return (OPSreturn -Code info -Message "xuiSelectFolder: Dialog was confirmed but no path was returned.")
        }

        $resultData = [pscustomobject]@{
            Path  = [string]$dialog.SelectedPath
            Title = $dialog.Description
        }

        return (OPSreturn -Code success -Message "xuiSelectFolder: Folder selected." -Data $resultData)
    }
    catch {
        return (OPSreturn -Code fail -Message "xuiSelectFolder failed! $($_.Exception.Message)" -Exception $_.Exception)
    }
    finally {
        if ($null -ne $dialog) { $dialog.Dispose() }
        if ($null -ne $owner)  { $owner.Close(); $owner.Dispose() }
    }
}

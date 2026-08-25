function xuiSelectFile {
    <#
    .SYNOPSIS
        Shows the standard Windows file-open dialog and returns the selected path.

    .DESCRIPTION
        xuiSelectFile is the generic WinTwin.XUI replacement for Select-WimFile from
        DISM.UI.CC\wim.mounter.fx.ps1.

        The original helper was WIM-only (Filter was hard-coded to *.wim). This function
        keeps the same dialog behaviour but is reusable across the whole framework:

          - optional -Filter (WinForms filter string or a simple "*.wim" mask)
          - optional -Title
          - optional -InitialDirectory
          - optional multi-select
          - dialog is forced to the foreground via a hidden TopMost owner form

        Always returns an OPSreturn object. Cancellation is reported as a non-success
        code so callers can branch on .code without treating cancel as a crash.

    .PARAMETER Filter
        WinForms filter (e.g. "WIM images (*.wim)|*.wim|All files (*.*)|*.*")
        or a simple mask such as "*.wim". Default: all files.

    .PARAMETER Title
        Dialog window title.

    .PARAMETER InitialDirectory
        Optional directory the dialog should open in.

    .PARAMETER MultiSelect
        When set, the user may select more than one file. .data.Paths then contains
        the full list; .data.Path still holds the first selected file.

    .PARAMETER CheckFileExists
        Defaults to $true, matching the original Select-WimFile behaviour.

    .OUTPUTS
        PSCustomObject from OPSreturn.
        Success .data: Path, Paths, Filter, Title.

    .EXAMPLE
        $pick = xuiSelectFile -Title 'Please select a WIM file.' -Filter '*.wim'
        if ($pick.code -eq 0) { $txtImageFile.Text = $pick.data.Path }

    .NOTES
        Part of: WinTwin.XUI
        Alias : xuiOpenFile  (name used in the functional documentation)
        Replaces: Select-WimFile
        See also: xuiSelectFolder, xuiLoadWindow, OPSreturn
    #>

    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    [Alias('xuiOpenFile')]
    param(
        [Parameter(Mandatory = $false)]
        [AllowEmptyString()]
        [string]$Filter = 'All files (*.*)|*.*',

        [Parameter(Mandatory = $false)]
        [AllowEmptyString()]
        [string]$Title = 'Select a file',

        [Parameter(Mandatory = $false)]
        [AllowEmptyString()]
        [string]$InitialDirectory = '',

        [Parameter(Mandatory = $false)]
        [switch]$MultiSelect,

        [Parameter(Mandatory = $false)]
        [bool]$CheckFileExists = $true
    )

    try {
        Add-Type -AssemblyName System.Windows.Forms -ErrorAction Stop
    }
    catch {
        return (OPSreturn -Code fail -Message "xuiSelectFile failed! System.Windows.Forms could not be loaded: $($_.Exception.Message)" -Exception $_.Exception)
    }

    # Allow the short "*.wim" form used in the functional documentation.
    $resolvedFilter = $Filter
    if ([string]::IsNullOrWhiteSpace($resolvedFilter)) {
        $resolvedFilter = 'All files (*.*)|*.*'
    }
    elseif ($resolvedFilter -notmatch '\|') {
        $mask  = $resolvedFilter.Trim()
        $label = $mask.TrimStart('*').TrimStart('.').ToUpperInvariant()
        if ([string]::IsNullOrWhiteSpace($label) -or $mask -eq '*.*') {
            $resolvedFilter = 'All files (*.*)|*.*'
        }
        else {
            $resolvedFilter = "{0} files ({1})|{1}|All files (*.*)|*.*" -f $label, $mask
        }
    }

    $owner  = $null
    $dialog = $null
    try {
        $owner  = xui-GetDialogOwner
        $dialog = New-Object System.Windows.Forms.OpenFileDialog
        $dialog.Title            = $(if ([string]::IsNullOrWhiteSpace($Title)) { 'Select a file' } else { $Title })
        $dialog.Filter           = $resolvedFilter
        $dialog.Multiselect      = [bool]$MultiSelect
        $dialog.CheckFileExists  = $CheckFileExists
        $dialog.RestoreDirectory = $true
        $dialog.AutoUpgradeEnabled = $true

        if (-not [string]::IsNullOrWhiteSpace($InitialDirectory) -and (Test-Path -LiteralPath $InitialDirectory -PathType Container)) {
            $dialog.InitialDirectory = $InitialDirectory
        }

        $result = $dialog.ShowDialog($owner)
        if ($result -ne [System.Windows.Forms.DialogResult]::OK) {
            return (OPSreturn -Code info -Message "xuiSelectFile: Dialog was cancelled.")
        }

        $selected = @($dialog.FileNames | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
        if ($selected.Count -eq 0) {
            return (OPSreturn -Code info -Message "xuiSelectFile: Dialog was confirmed but no path was returned.")
        }

        $resultData = [pscustomobject]@{
            Path   = [string]$selected[0]
            Paths  = $selected
            Filter = $resolvedFilter
            Title  = $dialog.Title
        }

        return (OPSreturn -Code success -Message "xuiSelectFile: File selected." -Data $resultData)
    }
    catch {
        return (OPSreturn -Code fail -Message "xuiSelectFile failed! $($_.Exception.Message)" -Exception $_.Exception)
    }
    finally {
        if ($null -ne $dialog) { $dialog.Dispose() }
        if ($null -ne $owner)  { $owner.Close(); $owner.Dispose() }
    }
}

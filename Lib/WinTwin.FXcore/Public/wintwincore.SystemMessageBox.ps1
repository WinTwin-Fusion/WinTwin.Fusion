function wintwincore.SystemMessageBox {
    <#
    .SYNOPSIS
        Shows a native System.Windows.MessageBox, always forced into the foreground.

    .DESCRIPTION
        wintwincore.SystemMessageBox is the framework-wide, temporary replacement for a proper
        in-house WinTwin.Fusion error/notification dialog. Since the framework
        consistently hides the console window (for purely cosmetic reasons, see
        wintwincore.SetCMDstate -State Hide), tools need a reliable way to surface errors to
        the user without relying on Write-Error/Write-Host, which nobody would ever
        see. Until a dedicated WinTwin.Fusion notification tool exists, this function
        wraps the built-in WPF System.Windows.MessageBox.

        The dialog is always shown while a tiny, invisible, TopMost WinForms owner
        window is active in the background. This forces the calling process into the
        foreground first, so the MessageBox reliably appears on top instead of ending
        up behind the calling tool's own window - the exact same "dialog opens behind
        everything" problem that already affected the file/folder dialogs in
        WinTwin.XUI. The owner window is disposed immediately after the message box
        is closed.

        Always returns an OPSreturn object. On success (.code = 0) .data contains the
        button the user actually clicked (as a string: OK, Cancel, Yes, No or None).

    .PARAMETER smbTitle
        Title bar text of the message box. Mandatory.

    .PARAMETER smbText
        The actual message text shown inside the message box. Mandatory.

    .PARAMETER smbIcon
        Icon to display. One of: None, Information, Warning, Error, Question.
        Default: Error (the primary use case of this function is surfacing errors
        from a tool whose console window is hidden).

    .PARAMETER smbButtons
        Which button(s) to display. One of: OK, OKCancel, YesNo, YesNoCancel.
        Default: OK.

    .OUTPUTS
        PSCustomObject from OPSreturn.
        Success .data: the clicked button as a string (OK/Cancel/Yes/No/None).

    .EXAMPLE
        wintwincore.SystemMessageBox -smbTitle 'DISM.UI.CC - wim.mounter' `
                              -smbText 'WTF.Console.ps1 was not found.' `
                              -smbIcon Error -smbButtons OK

    .EXAMPLE
        $result = wintwincore.SystemMessageBox -smbTitle 'wim.mounter' -smbText 'Overwrite existing mount point?' `
                                        -smbIcon Question -smbButtons YesNo
        if ($result.code -eq 0 -and $result.data -eq 'Yes') { ... }

    .NOTES
        Part of: WinTwin.FXcore
        Intended as: a stop-gap until a dedicated WinTwin.Fusion notification tool exists
        See also: OPSreturn
    #>

    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string]$smbTitle,

        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string]$smbText,

        [Parameter(Mandatory = $false)]
        [ValidateSet('None', 'Information', 'Warning', 'Error', 'Question')]
        [string]$smbIcon = 'Error',

        [Parameter(Mandatory = $false)]
        [ValidateSet('OK', 'OKCancel', 'YesNo', 'YesNoCancel')]
        [string]$smbButtons = 'OK'
    )

    if ([string]::IsNullOrWhiteSpace($smbTitle)) {
        return (OPSreturn -Code fail -Message "wintwincore.SystemMessageBox failed! Parameter 'smbTitle' is required and must not be empty.")
    }
    if ([string]::IsNullOrWhiteSpace($smbText)) {
        return (OPSreturn -Code fail -Message "wintwincore.SystemMessageBox failed! Parameter 'smbText' is required and must not be empty.")
    }

    try {
        Add-Type -AssemblyName PresentationFramework -ErrorAction Stop
        Add-Type -AssemblyName PresentationCore -ErrorAction Stop
        Add-Type -AssemblyName WindowsBase -ErrorAction Stop
        Add-Type -AssemblyName System.Windows.Forms -ErrorAction Stop
    }
    catch {
        return (OPSreturn -Code fail -Message "wintwincore.SystemMessageBox failed! Required WPF/WinForms assemblies could not be loaded: $($_.Exception.Message)" -Exception $_.Exception)
    }

    # --- Hidden, TopMost owner so the MessageBox is forced into the foreground ---
    # Same technique used by WinTwin.XUI's dialog helpers, reimplemented here in a
    # self-contained way so WinTwin.FXcore does not have to depend on WinTwin.XUI.
    $owner = $null
    try {
        $owner                 = New-Object System.Windows.Forms.Form
        $owner.Text            = 'WinTwin.FXcore'
        $owner.ShowInTaskbar   = $false
        $owner.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::None
        $owner.StartPosition   = [System.Windows.Forms.FormStartPosition]::Manual
        $owner.Size            = New-Object System.Drawing.Size(1, 1)
        $owner.Location        = New-Object System.Drawing.Point(-32000, -32000)
        $owner.TopMost         = $true
        $owner.Opacity         = 0
        $null = $owner.Show()
        $owner.Activate()
        $owner.BringToFront()
        [void][System.Windows.Forms.Application]::DoEvents()
    }
    catch {
        return (OPSreturn -Code fail -Message "wintwincore.SystemMessageBox failed! Could not create the hidden foreground owner window: $($_.Exception.Message)" -Exception $_.Exception)
    }

    try {
        $iconValue    = [System.Windows.MessageBoxImage]$smbIcon
        $buttonsValue = [System.Windows.MessageBoxButton]$smbButtons

        # System.Windows.MessageBox.Show(...) has no overload that accepts a WinForms
        # owner directly. Keeping $owner TopMost + activated beforehand is what
        # actually forces the subsequent modal dialog into the foreground.
        $clickedButton = [System.Windows.MessageBox]::Show(
            $smbText,
            $smbTitle,
            $buttonsValue,
            $iconValue
        )
    }
    catch {
        return (OPSreturn -Code fail -Message "wintwincore.SystemMessageBox failed! Could not show the message box: $($_.Exception.Message)" -Exception $_.Exception)
    }
    finally {
        if ($null -ne $owner) {
            $owner.Close()
            $owner.Dispose()
        }
    }

    return (OPSreturn -Code success -Message "wintwincore.SystemMessageBox: Message box closed, user clicked '$clickedButton'." -Data $clickedButton.ToString())
}

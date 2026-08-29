function xui-GetDialogOwner {
    <#
    .SYNOPSIS
        Builds a hidden, top-most WinForms owner so file/folder dialogs open focused in front.

    .DESCRIPTION
        Windows.Forms dialogs opened without an owner frequently appear behind a WPF window.
        This private helper creates a tiny, invisible TopMost form that can be passed to
        ShowDialog($owner). The caller MUST dispose the returned form when the dialog closes.

    .NOTES
        Part of: WinTwin.XUI (private)
        Used by: xuiSelectFile, xuiSelectFolder
    #>

    [CmdletBinding()]
    param()

    Add-Type -AssemblyName System.Windows.Forms -ErrorAction Stop

    $owner = New-Object System.Windows.Forms.Form
    $owner.Text            = 'WinTwin.XUI'
    $owner.ShowInTaskbar   = $false
    $owner.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::None
    $owner.StartPosition   = [System.Windows.Forms.FormStartPosition]::Manual
    $owner.Size            = New-Object System.Drawing.Size(1, 1)
    $owner.Location        = New-Object System.Drawing.Point(-32000, -32000)
    $owner.TopMost         = $true
    $owner.Opacity         = 0
    $null = $owner.Show()
    $owner.BringToFront()
    [void][System.Windows.Forms.Application]::DoEvents()
    return $owner
}

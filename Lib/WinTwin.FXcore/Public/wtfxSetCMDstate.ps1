function wtfxSetCMDstate {
    <#
    .SYNOPSIS
    Shows, hides, or minimizes the current console (cmd/PowerShell) window.

    .DESCRIPTION
    The wtfxSetCMDstate function wraps the native Win32 ShowWindow API (via a small,
    self-contained P/Invoke signature added on first use) to control the visibility
    state of the process's own console window. This is a generic, reusable
    replacement for the various framework-internal, tool-specific console-state
    helper functions (e.g. the "Set-ConsoleWindowState" helper previously
    duplicated inside wim.mounter.fx.ps1), so every WinTwin.Fusion tool can rely on
    a single, centrally maintained implementation.

    .PARAMETER State
    Desired console window state. One of:
      Show      - restores/shows the window normally (SW_SHOW)
      Hide      - completely hides the window (SW_HIDE)
      Minimize  - minimizes the window to the taskbar (SW_MINIMIZE)
      Maximize  - maximizes the window (SW_MAXIMIZE)

    .EXAMPLE
    wtfxSetCMDstate -State Hide
    Hides the current console window (e.g. while a long-running DISM job runs in
    the background and progress is only shown in a GUI).

    .EXAMPLE
    wtfxSetCMDstate -State Show
    Restores the console window again.

    .NOTES
    Part of: WinTwin.FXcore
    Uses: user32.dll!ShowWindow / kernel32.dll!GetConsoleWindow (P/Invoke)
    #>

    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet('Show', 'Hide', 'Minimize', 'Maximize')]
        [string]$State
    )

    try {
        if (-not ('WinTwin.FXcore.NativeConsole' -as [type])) {
            Add-Type -Namespace WinTwin.FXcore -Name NativeConsole -MemberDefinition @'
                [DllImport("kernel32.dll")]
                public static extern IntPtr GetConsoleWindow();

                [DllImport("user32.dll")]
                public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
'@
        }
    }
    catch {
        return (OPSreturn -Code -1 -Message "Could not register native console control type: $($_.Exception.Message)" -Exception $_.Exception)
    }

    $showCommandMap = @{
        'Hide'     = 0   # SW_HIDE
        'Show'     = 5   # SW_SHOW
        'Minimize' = 6   # SW_MINIMIZE
        'Maximize' = 3   # SW_MAXIMIZE
    }

    try {
        $hwnd = [WinTwin.FXcore.NativeConsole]::GetConsoleWindow()
        if ($hwnd -eq [IntPtr]::Zero) {
            return (OPSreturn -Code -1 -Message "Could not resolve the current console window handle (GetConsoleWindow returned NULL). This can happen when running inside an ISE or a redirected/non-console host.")
        }

        $cmdShow = $showCommandMap[$State]
        $result = [WinTwin.FXcore.NativeConsole]::ShowWindow($hwnd, $cmdShow)

        return (OPSreturn -Code 0 -Message "Console window state set to '$State'" -Data $result)
    }
    catch {
        return (OPSreturn -Code -1 -Message "Failed to set console window state to '$State': $($_.Exception.Message)" -Exception $_.Exception)
    }
}

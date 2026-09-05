function wintwincore.SetCMDstate {
    <#
    .SYNOPSIS
    Shows, hides, minimizes, or maximizes the current console (cmd/PowerShell) window.

    .DESCRIPTION
    The wintwincore.SetCMDstate function wraps native Win32 APIs to control the
    visibility state of the process's own console window.

    With -State Show, the optional -Focus parameter controls how the console is
    restored:
      -Focus $true  restores the console and brings it to the foreground.
      -Focus $false shows the console minimized.

    If -Focus is omitted, -State Show keeps the original SW_SHOW behavior.

    .PARAMETER State
    Desired console window state. One of:
      Show      - shows the window; optionally applies -Focus
      Hide      - completely hides the window (SW_HIDE)
      Minimize  - minimizes the window to the taskbar (SW_MINIMIZE)
      Maximize  - maximizes the window (SW_MAXIMIZE)

    .PARAMETER Focus
    Optional Boolean parameter that is valid only with -State Show.
      $true  - restores the console, brings it to the top, and requests focus
      $false - shows the console minimized

    .EXAMPLE
    wintwincore.SetCMDstate -State Hide
    Hides the current console window.

    .EXAMPLE
    wintwincore.SetCMDstate -State Show
    Shows the console using the original behavior.

    .EXAMPLE
    wintwincore.SetCMDstate -State Show -Focus $true
    Restores the console and brings it to the foreground.

    .EXAMPLE
    wintwincore.SetCMDstate -State Show -Focus $false
    Shows the console minimized in the taskbar.

    .NOTES
    Part of: WinTwin.FXcore
    Uses: user32.dll / kernel32.dll (P/Invoke)
    #>

    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet('Show', 'Hide', 'Minimize', 'Maximize')]
        [string]$State,

        [Parameter(Mandatory = $false)]
        [bool]$Focus
    )

    if ($PSBoundParameters.ContainsKey('Focus') -and $State -ne 'Show') {
        return (OPSreturn -Code -1 -Message "The -Focus parameter can only be used with -State Show.")
    }

    try {
        if (-not ('WinTwin.FXcore.NativeConsole' -as [type])) {
            Add-Type -Namespace WinTwin.FXcore -Name NativeConsole -MemberDefinition @'
                [DllImport("kernel32.dll")]
                public static extern IntPtr GetConsoleWindow();

                [DllImport("user32.dll")]
                public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);

                [DllImport("user32.dll")]
                public static extern bool SetForegroundWindow(IntPtr hWnd);

                [DllImport("user32.dll")]
                public static extern bool BringWindowToTop(IntPtr hWnd);

                [DllImport("user32.dll")]
                public static extern IntPtr SetActiveWindow(IntPtr hWnd);

                [DllImport("user32.dll", SetLastError = true)]
                public static extern bool SetWindowPos(
                    IntPtr hWnd,
                    IntPtr hWndInsertAfter,
                    int X,
                    int Y,
                    int cx,
                    int cy,
                    uint uFlags
                );
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

        $result = $false
        $focusResult = $null

        if ($State -eq 'Show' -and $PSBoundParameters.ContainsKey('Focus')) {
            if ($Focus) {
                $SW_RESTORE = 9
                $HWND_TOPMOST = [IntPtr](-1)
                $HWND_NOTOPMOST = [IntPtr](-2)
                $SWP_NOMOVE = 0x0002
                $SWP_NOSIZE = 0x0001
                $SWP_SHOWWINDOW = 0x0040
                $positionFlags = $SWP_NOMOVE -bor $SWP_NOSIZE -bor $SWP_SHOWWINDOW

                $result = [WinTwin.FXcore.NativeConsole]::ShowWindow($hwnd, $SW_RESTORE)
                [void][WinTwin.FXcore.NativeConsole]::SetWindowPos($hwnd, $HWND_TOPMOST, 0, 0, 0, 0, $positionFlags)
                [void][WinTwin.FXcore.NativeConsole]::BringWindowToTop($hwnd)
                [void][WinTwin.FXcore.NativeConsole]::SetActiveWindow($hwnd)
                $focusResult = [WinTwin.FXcore.NativeConsole]::SetForegroundWindow($hwnd)
                [void][WinTwin.FXcore.NativeConsole]::SetWindowPos($hwnd, $HWND_NOTOPMOST, 0, 0, 0, 0, $positionFlags)
            }
            else {
                $SW_SHOWMINIMIZED = 2
                $result = [WinTwin.FXcore.NativeConsole]::ShowWindow($hwnd, $SW_SHOWMINIMIZED)
            }
        }
        else {
            $cmdShow = $showCommandMap[$State]
            $result = [WinTwin.FXcore.NativeConsole]::ShowWindow($hwnd, $cmdShow)
        }

        $data = [PSCustomObject]@{
            ShowWindowResult      = $result
            ForegroundFocusResult = $focusResult
        }

        $message = "Console window state set to '$State'"
        if ($PSBoundParameters.ContainsKey('Focus')) {
            $message += " with Focus='$Focus'"
        }

        return (OPSreturn -Code 0 -Message $message -Data $data)
    }
    catch {
        return (OPSreturn -Code -1 -Message "Failed to set console window state to '$State': $($_.Exception.Message)" -Exception $_.Exception)
    }
}

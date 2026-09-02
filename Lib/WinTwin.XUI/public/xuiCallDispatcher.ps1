function xuiCallDispatcher {
    <#
    .SYNOPSIS
        Processes pending WPF work for a specific window dispatcher.

    .DESCRIPTION
        xuiCallDispatcher schedules a dispatcher-frame exit callback for the
        dispatcher that owns the supplied Window. While the nested frame is
        active, pending WPF work at the selected priority is processed, which
        allows layout, data binding, and rendering changes to become visible
        before the current synchronous event handler returns.

        If the function is called from a different thread, it does not create
        a nested dispatcher frame. Instead, it queues a synchronization action
        on the owning dispatcher and waits for that action to complete.

        Nested dispatcher frames introduce reentrancy. The function therefore
        blocks recursive calls by default and includes a timeout guard. Use the
        function only for short synchronous sections. Long-running work should
        be moved away from the UI thread.

    .PARAMETER Window
        The WPF Window whose dispatcher should process pending UI work.

    .PARAMETER Priority
        The priority assigned to the dispatcher synchronization callback.
        Render is the default because it processes pending work needed for a
        visual refresh while avoiding lower-priority work where possible.

    .PARAMETER TimeoutMilliseconds
        The maximum time allowed for the synchronization operation. On the UI
        thread, a high-priority DispatcherTimer terminates the nested frame. On
        another thread, this value limits the synchronous wait.

    .PARAMETER UpdateLayout
        Calls InvalidateVisual() and UpdateLayout() before the dispatcher is
        pumped. This is useful when an immediate layout pass is required, but
        it can be more expensive than processing the dispatcher queue alone.

    .PARAMETER AllowReentrancy
        Allows xuiCallDispatcher to start another nested frame while a previous
        call is still active. This is disabled by default because WPF events
        can run during a nested dispatcher frame and may mutate application
        state unexpectedly.

    .EXAMPLE
        $statusText.Text = 'Installing package...'
        $result = xuiCallDispatcher -Window $mainWindow

        Processes pending render work owned by $mainWindow.

    .EXAMPLE
        $progressBar.Value = 50
        $result = xuiCallDispatcher -Window $mainWindow -UpdateLayout `
            -Priority ([System.Windows.Threading.DispatcherPriority]::Background)

        Forces a layout pass and then processes pending work through Background
        priority. This broader queue pump may also execute input and data-bound
        callbacks, so application state must be safe for reentrancy.

    .OUTPUTS
        PSCustomObject
        Returns the standard OPSreturn object with code, msg, and data fields.

    .NOTES
        This function is a controlled WPF DoEvents-style helper. It improves
        perceived progress for short synchronous work, but it does not make a
        blocking operation asynchronous and does not keep the window fully
        responsive during long-running work.
    #>

    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, Position = 0)]
        [ValidateNotNull()]
        [System.Windows.Window]$Window,

        [Parameter()]
        [System.Windows.Threading.DispatcherPriority]$Priority =
            [System.Windows.Threading.DispatcherPriority]::Render,

        [Parameter()]
        [ValidateRange(1, 60000)]
        [int]$TimeoutMilliseconds = 1000,

        [Parameter()]
        [switch]$UpdateLayout,

        [Parameter()]
        [switch]$AllowReentrancy
    )

    try {
        $dispatcher = $Window.Dispatcher

        if ($null -eq $dispatcher) {
            return (OPSreturn -Code 1 -Message 'The supplied window does not have a dispatcher.' -Data $null)
        }

        if ($dispatcher.HasShutdownStarted -or $dispatcher.HasShutdownFinished) {
            return (OPSreturn -Code 1 -Message 'The window dispatcher is shutting down or has already stopped.' -Data $null)
        }

        # Inactive and Invalid operations are never eligible for execution and
        # would leave a nested dispatcher frame waiting only for its timeout.
        if (
            $Priority -eq [System.Windows.Threading.DispatcherPriority]::Inactive -or
            $Priority -eq [System.Windows.Threading.DispatcherPriority]::Invalid
        ) {
            return (OPSreturn -Code 1 -Message "Dispatcher priority '$Priority' cannot execute queued work." -Data $null)
        }

        $resultData = [ordered]@{
            WindowTitle        = $Window.Title
            WindowType         = $Window.GetType().FullName
            Priority           = $Priority.ToString()
            TimeoutMilliseconds = $TimeoutMilliseconds
            LayoutUpdated      = [bool]$UpdateLayout
            CalledOnUiThread   = $dispatcher.CheckAccess()
            TimedOut           = $false
        }

        # A caller on a worker thread does not need a nested frame: the owning
        # UI dispatcher is already free to process queued work. Queue a marker
        # action at the requested priority and wait until it has been reached.
        if (-not $dispatcher.CheckAccess()) {
            $windowForCallback = $Window
            $updateLayoutForCallback = [bool]$UpdateLayout

            $synchronizationAction = [System.Action]{
                if ($updateLayoutForCallback) {
                    $windowForCallback.InvalidateVisual()
                    $windowForCallback.UpdateLayout()
                }
            }

            $operation = $dispatcher.InvokeAsync($synchronizationAction, $Priority)
            $completed = $operation.Task.Wait($TimeoutMilliseconds)

            if (-not $completed) {
                if ($operation.Status -eq [System.Windows.Threading.DispatcherOperationStatus]::Pending) {
                    [void]$operation.Abort()
                }

                $resultData.TimedOut = $true
                return (OPSreturn -Code 1 -Message 'The dispatcher synchronization operation timed out.' -Data ([pscustomobject]$resultData))
            }

            # Accessing Result propagates an exception raised by the queued
            # callback instead of incorrectly reporting a successful refresh.
            [void]$operation.Task.GetAwaiter().GetResult()

            return (OPSreturn -Code 0 -Message 'The window dispatcher processed the requested UI work.' -Data ([pscustomobject]$resultData))
        }

        if (-not (Test-Path -LiteralPath 'variable:script:xuiCallDispatcherDepth')) {
            $script:xuiCallDispatcherDepth = 0
        }

        if (($script:xuiCallDispatcherDepth -gt 0) -and -not $AllowReentrancy) {
            return (OPSreturn -Code 1 -Message 'A dispatcher frame is already active. Use -AllowReentrancy only when nested event processing is safe.' -Data ([pscustomobject]$resultData))
        }

        $frame = [System.Windows.Threading.DispatcherFrame]::new($true)
        $pumpState = [pscustomobject]@{
            Frame    = $frame
            TimedOut = $false
        }

        # The callback is queued after work that is already pending at the same
        # priority. When it runs, the nested frame exits cleanly.
        $exitCallback = [System.Windows.Threading.DispatcherOperationCallback]{
            param($state)
            $state.Frame.Continue = $false
            return $null
        }

        # A Send-priority timer prevents the nested frame from remaining active
        # indefinitely if the normal exit callback cannot be reached.
        $timeoutTimer = [System.Windows.Threading.DispatcherTimer]::new(
            [System.Windows.Threading.DispatcherPriority]::Send,
            $dispatcher
        )
        $timeoutTimer.Interval = [TimeSpan]::FromMilliseconds($TimeoutMilliseconds)

        $timeoutHandler = [System.EventHandler]{
            param($sender, $eventArgs)
            $pumpState.TimedOut = $true
            $pumpState.Frame.Continue = $false
        }

        $exitOperation = $null
        $script:xuiCallDispatcherDepth++

        try {
            if ($UpdateLayout) {
                # UpdateLayout must run on the thread that owns the window.
                $Window.InvalidateVisual()
                $Window.UpdateLayout()
            }

            $timeoutTimer.add_Tick($timeoutHandler)
            $timeoutTimer.Start()

            $exitOperation = $dispatcher.BeginInvoke(
                $Priority,
                $exitCallback,
                $pumpState
            )

            [System.Windows.Threading.Dispatcher]::PushFrame($frame)
        }
        finally {
            $timeoutTimer.Stop()
            $timeoutTimer.remove_Tick($timeoutHandler)

            if (
                $null -ne $exitOperation -and
                $exitOperation.Status -eq [System.Windows.Threading.DispatcherOperationStatus]::Pending
            ) {
                [void]$exitOperation.Abort()
            }

            $script:xuiCallDispatcherDepth--
        }

        $resultData.TimedOut = [bool]$pumpState.TimedOut

        if ($pumpState.TimedOut) {
            return (OPSreturn -Code 1 -Message 'The dispatcher frame timed out before the synchronization callback completed.' -Data ([pscustomobject]$resultData))
        }

        return (OPSreturn -Code 0 -Message 'The window dispatcher processed the requested UI work.' -Data ([pscustomobject]$resultData))
    }
    catch {
        $errorData = [pscustomobject]@{
            ExceptionType = $_.Exception.GetType().FullName
            Exception     = $_.Exception.Message
            WindowType    = if ($null -ne $Window) { $Window.GetType().FullName } else { $null }
            Priority      = $Priority.ToString()
        }

        return (OPSreturn -Code 1 -Message 'Failed to process the window dispatcher.' -Data $errorData)
    }
}

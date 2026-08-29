<#
.SYNOPSIS
    OPSreturn - Creates a standardized return object for operation status reporting (WinTwin.XUI internal copy).
.DESCRIPTION
    WinTwin.XUI must work without a hard dependency on the external OPSreturn module, so this
    private, module-internal copy mirrors the public OPSreturn module and the WinTwin.FXcore
    internal helper as closely as possible.

    If FXcore (or the standalone OPSreturn module) has already declared [OPScode], this file
    reuses that enum instead of declaring a second, conflicting type.

    BACKWARD COMPATIBILITY: Callers may pass historic integer codes 0 (success) / -1 (fail).
.NOTES
    Creation Date : 24.08.2026
    Last Update   : 24.08.2026
    Origin        : Adapted from WinTwin.FXcore\Private\OPSreturn.ps1 (Praetoriani).
    Part of       : WinTwin.XUI (exclusive library for the WinTwin.Fusion Framework)
#>

# Only declare the enum if it has not already been declared (module re-import / FXcore safety).
if (-not ([System.Management.Automation.PSTypeName]'OPScode').Type) {
    Add-Type -TypeDefinition @'
public enum OPScode {
    success  = 0,
    info     = 1,
    debug    = 2,
    timeout  = 3,
    warn     = 4,
    fail     = -1,
    error    = -2,
    critical = -3,
    fatal    = -4
}
'@ -ErrorAction SilentlyContinue
}

function OPSreturn {
    <#
    .SYNOPSIS
        Creates a standardized return object for operation status reporting.

    .PARAMETER Code
        Status code. One of the OPScode enum values, or the historic integers 0 / -1.

    .PARAMETER Message
        Short message describing the operation result or error.

    .PARAMETER Data
        Optional data payload.

    .PARAMETER Exception
        Optional exception object / detailed error information.
    #>

    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory = $false)]
        [OPScode]$Code = [OPScode]::fail,

        [Parameter(Mandatory = $false)]
        [AllowEmptyString()]
        [string]$Message = "",

        [Parameter(Mandatory = $false)]
        [AllowNull()]
        $Data = $null,

        [Parameter(Mandatory = $false)]
        [AllowNull()]
        $Exception = $null
    )

    [string]$callerSrc = try {
        $callStack = Get-PSCallStack
        if ($callStack.Count -gt 2) { $callStack[2].Command }
        elseif ($callStack.Count -gt 1) { $callStack[1].Command }
        else { '<unknown>' }
    }
    catch {
        '<unknown>'
    }

    [bool]$useTimestamp = $true
    if ($null -ne $script:conf -and $script:conf.ContainsKey('timestamp')) {
        $useTimestamp = [bool]$script:conf['timestamp']
    }

    return [PSCustomObject]@{
        code      = [int]$Code
        state     = $Code.ToString()
        msg       = $Message
        data      = $Data
        exception = $Exception
        source    = $callerSrc
        timecode  = if ($useTimestamp) { (Get-Date).ToString('dd.MM.yyyy ; HH:mm:ss.fff') } else { '<notused>' }
    }
}

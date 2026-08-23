<#
.SYNOPSIS
    OPSreturn - Creates a standardized return object for operation status reporting (WinTwin.FXcore internal copy).
.DESCRIPTION
    WinTwin.FXcore must work without a hard dependency on the external OPSreturn module, so this
    private, module-internal copy mirrors the public OPSreturn module (see:
    https://github.com/praetoriani/PowerShell.Mods/tree/main/OPSreturn) as closely as possible.

    Compared to the original (pre-rework) FXcore implementation, this version adds:
    - An [OPScode] enum instead of a plain [ValidateSet(0,-1)] int, giving every function access
      to the full severity range (success/info/debug/timeout/warn/fail/error/critical/fatal)
      instead of only success/fail.
    - An optional -Exception parameter to pass a more detailed error object to the caller.
    - Automatic caller-name resolution via the call stack (`source`).
    - An optional timestamp (`timecode`), toggled via $script:conf['timestamp'].

    BACKWARD COMPATIBILITY: All existing FXcore functions call `OPSreturn -Code 0 ...` or
    `OPSreturn -Code -1 ...`. Because [OPScode]::success = 0 and [OPScode]::fail = -1, PowerShell's
    parameter binder implicitly converts these existing integer arguments to the matching enum
    values, so no other FXcore function had to be changed for this rework.
.NOTES
    Creation Date : 28.03.2026
    Last Update   : 23.08.2026
    Origin        : Adapted from the standalone OPSreturn PowerShell module (Praetoriani).
#>

# ____________________________________________________________________________________________________
#  → ENUMERATION
# ‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾
# Only declare the enum if it hasn't already been declared (module re-import safety).
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
    Status code. One of the OPScode enum values (success, info, debug, timeout, warn, fail, error,
    critical, fatal). Also accepts the historic integer values 0 (success) / -1 (fail) used by
    existing FXcore functions. Default is 'fail'.

    .PARAMETER Message
    Short message describing the operation result or error. Default is empty string.

    .PARAMETER Data
    Optional data payload to return with the status object. Default is $null.

    .PARAMETER Exception
    Optional exception object / detailed error information to return alongside Message.

    .EXAMPLE
    return OPSreturn -Code fail -Message "Config file not found: $Path"

    .EXAMPLE
    return OPSreturn -Code 0 -Message "Operation completed successfully" -Data $result
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

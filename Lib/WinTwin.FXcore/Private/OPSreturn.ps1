# ____________________________________________________________________________________________________
#  → ENUMERATION CLASS
# ‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾
# NOTE: 'success' (0) and 'fail' (-1) map 1:1 onto the two integer codes used by every existing
# WinTwin.FXcore function ("OPSreturn -Code 0 ..." / "OPSreturn -Code -1 ..."). Because PowerShell
# implicitly converts a plain [int] argument into the matching enum value, ALL existing call sites in
# this module keep working completely unchanged after this upgrade. The additional enum members
# (info/debug/timeout/warn/error/critical/fatal) are purely additive and only used by newly written
# or newly adapted functions - never required by old ones.
enum OPScode {
    success     = 0
    info        = 1
    debug       = 2
    timeout     = 3
    warn        = 4
    fail        = -1
    error       = -2
    critical    = -3
    fatal       = -4
}

function OPSreturn {
    <#
    .SYNOPSIS
    Creates a standardized return object for operation status reporting.

    .DESCRIPTION
    The OPSreturn function creates a consistent PSCustomObject for returning operation
    status information across all module functions. It provides a uniform interface for
    success/failure reporting with an optional data payload.

    ‼ BACKWARD COMPATIBILITY NOTE (aligned with the upstream OPSreturn PowerShell module,
    see https://github.com/praetoriani/PowerShell.Mods/tree/main/OPSreturn):
    This version extends the original FXcore-internal OPSreturn (which only exposed
    'code' / 'msg' / 'data' using plain integers 0 / -1) with the richer, enum-based
    schema of the standalone OPSreturn module (state / exception / source / timecode),
    WITHOUT removing or renaming any existing field. Every existing call of the shape
    "OPSreturn -Code 0 -Message '...'" or "OPSreturn -Code -1 -Message '...' " continues
    to work unmodified, because:
      - the -Code parameter still accepts plain integers 0 and -1 (auto-converted to the
        OPScode enum values 'success' and 'fail'),
      - the object returned still contains .code and .msg with their original meaning
        and .data with its original semantics,
      - all NEW fields (.state, .exception, .source, .timecode) are pure ADDITIONS. Old
        consumers that only ever read .code / .msg / .data are completely unaffected.

    .PARAMETER Code
    Status code. Accepts either an [OPScode] enum member (success/info/debug/timeout/
    warn/fail/error/critical/fatal) or one of the two legacy plain integers 0 (success)
    / -1 (fail) used by pre-upgrade FXcore code. Default is 'fail' (-1).

    .PARAMETER Message
    Detailed message describing the operation result or error. Default is empty string.

    .PARAMETER Data
    Optional data payload to return with the status object. Can contain any type of
    data (strings, arrays, objects, binary data, etc.). Default is $null.

    .PARAMETER Exception
    Optional exception object or additional detail (e.g. $_.Exception) to pass to the
    caller for deeper diagnostics. Default is $null. New in this version; purely
    additive and safe to omit.

    .EXAMPLE
    OPSreturn -Code 0 -Message "Operation completed successfully"
    Legacy call style - still fully supported.

    .EXAMPLE
    OPSreturn -Code -1 -Message "File not found: C:\test.txt"
    Legacy call style - still fully supported.

    .EXAMPLE
    OPSreturn -Code ([OPScode]::warn) -Message "Partial success" -Exception $_.Exception
    New, enum-based call style with extended diagnostics.

    .NOTES
    This is an internal helper function used by all public module functions to ensure
    consistent return value structure throughout the WinTwin.FXcore module.
    Aligned with: https://github.com/praetoriani/PowerShell.Mods/tree/main/OPSreturn
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

    # Auto-resolve the name of the calling function via the PowerShell call stack.
    # Index [0] = OPSreturn itself, Index [1] = direct caller.
    [string]$callerSrc = try {
        $callStack = Get-PSCallStack
        if ($callStack.Count -gt 1) { $callStack[1].Command }
        else { '<unknown>' }
    }
    catch {
        '<unknown>'
    }

    # Create and return standardized status object.
    # 'code' / 'msg' / 'data' preserve the exact original FXcore contract.
    # 'state' / 'exception' / 'source' / 'timecode' are additive, non-breaking extensions.
    return [PSCustomObject]@{
        code        = [int]$Code
        msg         = $Message
        data        = $Data
        state       = $Code.ToString()
        exception   = $Exception
        source      = $callerSrc
        timecode    = (Get-Date).ToString('dd.MM.yyyy ; HH:mm:ss.fff')
    }
}

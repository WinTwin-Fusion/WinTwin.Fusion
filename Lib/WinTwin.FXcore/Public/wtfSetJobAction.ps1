function wtfSetJobAction {
    <#
    .SYNOPSIS
    Writes a single field of a specific job/action node in the framework's central
    jobaction.json database.

    .DESCRIPTION
    The wtfSetJobAction function resolves the path to Core\db\jobaction.json via
    Core\config.json (path.root + path.appdb.actions) - the exact same resolution
    logic used by wtfGetJobAction, so both functions always agree on the file
    location - and updates a single, dot-separated field (e.g. "path" or
    "download.location") on the given -ActionId node, using wtfWriteJSON internally
    in whole-object mode after patching the in-memory object. All other nodes and
    fields in jobaction.json are left completely untouched.

    ‼ BACKWARD COMPATIBILITY: this function is purely additive and does not modify
    the jobaction.json schema itself - it only ever changes the value the caller
    explicitly requests.

    .PARAMETER FrameworkRoot
    Full path to the WinTwin.Fusion framework root (the directory that contains
    Core\config.json).

    .PARAMETER ActionId
    The action/job identifier to update, e.g. "wim-mount".

    .PARAMETER Field
    Dot-separated field path within the action node to update, e.g. "path" or
    "download.location". Intermediate segments must already exist as objects.

    .PARAMETER Value
    The new value to write into the given field.

    .EXAMPLE
    wtfSetJobAction -FrameworkRoot "C:\WinTwin.Fusion" -ActionId "wim-mount" -Field "path" -Value "C:\WinTwin.Fusion\Mount"

    .NOTES
    Part of: WinTwin.FXcore
    See also: wtfGetJobAction, wtfWriteJSON
    #>

    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string]$FrameworkRoot,

        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string]$ActionId,

        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string]$Field,

        [Parameter(Mandatory = $true)]
        [AllowNull()]
        $Value
    )

    if ([string]::IsNullOrEmpty($FrameworkRoot)) {
        return (OPSreturn -Code -1 -Message "Parameter 'FrameworkRoot' is required but was not provided or is empty")
    }
    if ([string]::IsNullOrEmpty($ActionId)) {
        return (OPSreturn -Code -1 -Message "Parameter 'ActionId' is required but was not provided or is empty")
    }
    if ([string]::IsNullOrEmpty($Field)) {
        return (OPSreturn -Code -1 -Message "Parameter 'Field' is required but was not provided or is empty")
    }

    $configPath = Join-Path -Path $FrameworkRoot -ChildPath 'Core\config.json'
    $configResult = wtfLoadJSON -Path $configPath
    if ($configResult.code -ne 0) {
        return (OPSreturn -Code -1 -Message "Could not load Core\config.json: $($configResult.msg)" -Exception $configResult.exception)
    }
    $config = $configResult.data

    try {
        $relativeActionsPath = $config.path.appdb.actions
    }
    catch {
        return (OPSreturn -Code -1 -Message "config.json does not contain the expected 'path.appdb.actions' key")
    }

    if ([string]::IsNullOrEmpty($relativeActionsPath)) {
        return (OPSreturn -Code -1 -Message "config.json 'path.appdb.actions' value is empty")
    }

    $jobActionPath = Join-Path -Path $FrameworkRoot -ChildPath ($relativeActionsPath.TrimStart('\'))

    $jobActionResult = wtfLoadJSON -Path $jobActionPath
    if ($jobActionResult.code -ne 0) {
        return (OPSreturn -Code -1 -Message "Could not load jobaction.json: $($jobActionResult.msg)" -Exception $jobActionResult.exception)
    }
    $db = $jobActionResult.data

    $actionProp = $db.PSObject.Properties[$ActionId]
    if ($null -eq $actionProp) {
        return (OPSreturn -Code -1 -Message "ActionId '$ActionId' was not found in jobaction.json")
    }
    $actionNode = $actionProp.Value

    $segments = $Field -split '\.'
    $node = $actionNode
    for ($i = 0; $i -lt ($segments.Count - 1); $i++) {
        $segment = $segments[$i]
        $prop = $node.PSObject.Properties[$segment]
        if ($null -eq $prop) {
            return (OPSreturn -Code -1 -Message "Field segment '$segment' does not exist on action node '$ActionId' (full field path: '$Field')")
        }
        $node = $prop.Value
    }

    $finalKey  = $segments[-1]
    $finalProp = $node.PSObject.Properties[$finalKey]

    try {
        if ($null -eq $finalProp) {
            $node | Add-Member -MemberType NoteProperty -Name $finalKey -Value $Value -Force
        }
        else {
            $node.$finalKey = $Value
        }
    }
    catch {
        return (OPSreturn -Code -1 -Message "Could not set field '$Field' on action node '$ActionId': $($_.Exception.Message)" -Exception $_.Exception)
    }

    $writeResult = wtfWriteJSON -Path $jobActionPath -Value $db
    if ($writeResult.code -ne 0) {
        return (OPSreturn -Code -1 -Message "Field '$Field' was updated in memory but could not be persisted: $($writeResult.msg)" -Exception $writeResult.exception)
    }

    return (OPSreturn -Code 0 -Message "Field '$Field' of action node '$ActionId' updated successfully")
}

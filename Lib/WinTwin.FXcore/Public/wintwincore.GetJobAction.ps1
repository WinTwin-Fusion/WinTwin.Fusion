function wintwincore.GetJobAction {
    <#
    .SYNOPSIS
    Reads a specific job/action node (or a single field of it) from the framework's
    central jobaction.json database.

    .DESCRIPTION
    The wintwincore.GetJobAction function resolves the path to Core\db\jobaction.json via
    Core\config.json (path.root + path.appdb.actions), loads it with wintwincore.LoadJSON,
    and returns either the full node for a given -ActionId (e.g. "wim-mount") or,
    if -Field is also supplied, only that single field's value (e.g. "path" or
    "logfile"). This is the read counterpart to wtfSetJobAction and is the
    recommended way for framework tools to look up their own job/action
    configuration instead of parsing jobaction.json manually.

    .PARAMETER FrameworkRoot
    Full path to the WinTwin.Fusion framework root (the directory that contains
    Core\config.json). Used to resolve the actual location of jobaction.json.

    .PARAMETER ActionId
    The action/job identifier to look up, e.g. "uupd-catch", "uupd-compose",
    "uupd-isodump", "wim-mount", "wim-eject", "wtfc". Must match a top-level key in
    jobaction.json.

    .PARAMETER Field
    Optional dot-separated field path within the action node (e.g. "path",
    "download.location", "logfile"). If omitted, the entire action node is
    returned.

    .EXAMPLE
    $result = wintwincore.GetJobAction -FrameworkRoot "C:\WinTwin.Fusion" -ActionId "wim-mount"
    if ($result.code -eq 0) { $wimMountNode = $result.data }

    .EXAMPLE
    $result = wintwincore.GetJobAction -FrameworkRoot "C:\WinTwin.Fusion" -ActionId "wim-mount" -Field "path"
    if ($result.code -eq 0) { $mountPath = $result.data }

    .NOTES
    Part of: WinTwin.FXcore
    See also: wtfSetJobAction, wintwincore.LoadJSON
    #>

    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string]$FrameworkRoot,

        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string]$ActionId,

        [Parameter(Mandatory = $false)]
        [AllowEmptyString()]
        [string]$Field = ""
    )

    if ([string]::IsNullOrEmpty($FrameworkRoot)) {
        return (OPSreturn -Code -1 -Message "Parameter 'FrameworkRoot' is required but was not provided or is empty")
    }
    if ([string]::IsNullOrEmpty($ActionId)) {
        return (OPSreturn -Code -1 -Message "Parameter 'ActionId' is required but was not provided or is empty")
    }

    $configPath = Join-Path -Path $FrameworkRoot -ChildPath 'Core\config.json'
    $configResult = wintwincore.LoadJSON -Path $configPath
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

    # relativeActionsPath is stored with a leading backslash, e.g. "\Core\db\jobaction.json"
    $jobActionPath = Join-Path -Path $FrameworkRoot -ChildPath ($relativeActionsPath.TrimStart('\'))

    $jobActionResult = wintwincore.LoadJSON -Path $jobActionPath
    if ($jobActionResult.code -ne 0) {
        return (OPSreturn -Code -1 -Message "Could not load jobaction.json: $($jobActionResult.msg)" -Exception $jobActionResult.exception)
    }
    $db = $jobActionResult.data

    $actionProp = $db.PSObject.Properties[$ActionId]
    if ($null -eq $actionProp) {
        return (OPSreturn -Code -1 -Message "ActionId '$ActionId' was not found in jobaction.json")
    }
    $actionNode = $actionProp.Value

    if ([string]::IsNullOrEmpty($Field)) {
        return (OPSreturn -Code 0 -Message "Action node '$ActionId' loaded successfully" -Data $actionNode)
    }

    $segments = $Field -split '\.'
    $node = $actionNode
    foreach ($segment in $segments) {
        $prop = $node.PSObject.Properties[$segment]
        if ($null -eq $prop) {
            return (OPSreturn -Code -1 -Message "Field '$Field' does not exist on action node '$ActionId'")
        }
        $node = $prop.Value
    }

    return (OPSreturn -Code 0 -Message "Field '$Field' of action node '$ActionId' loaded successfully" -Data $node)
}

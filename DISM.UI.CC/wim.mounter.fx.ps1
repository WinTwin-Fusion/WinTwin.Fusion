
function Start-WtfConsoleProcess {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$WtfConsolePath,
        [Parameter(Mandatory = $true)][string]$MountScriptPath,
        [Parameter(Mandatory = $true)][string]$LogFilePath,
        [Parameter(Mandatory = $false)][string]$Language = 'en-us',
        [Parameter(Mandatory = $false)][string]$Action = 'mount'
    )

    $argList = @(
        '-NoLogo',
        '-NoProfile',
        '-ExecutionPolicy', 'Bypass',
        '-File', $WtfConsolePath,
        '-ScriptPath', $MountScriptPath,
        '-AppMode', 'framework',
        '-Action', $Action,
        '-Language', $Language,
        '-LogFilePath', $LogFilePath
    )

    $processResult = RunProcess -FilePath "$($PSHOME)\powershell.exe" -ArgumentList $argList -WindowStyle Normal -Confirm:$false
    if ($processResult.code -ne 0) {
        throw $processResult.msg
    }

    return $processResult.data
}

<#
.SYNOPSIS
    Retrieves all WPF controls defined by x:Name in a XAML document
    and returns them as a hashtable.

.DESCRIPTION
    This function loads the specified XAML file, enumerates all
    elements containing an x:Name attribute and attempts to resolve
    the corresponding runtime objects by using the FindName() method
    of the supplied RootElement.

    The operation is considered successful only if every named
    element defined in the XAML file can be resolved successfully.

    If an exception occurs or one or more controls cannot be
    resolved, the function returns $false.

.PARAMETER RootElement
    The root WPF element used for control resolution.

    Supported types include:

    - Window
    - UserControl
    - Page
    - Custom controls derived from FrameworkElement

.PARAMETER XmlFile
    Path to the original XAML file that was used to create the
    WPF user interface.

.OUTPUTS
    System.Collections.Hashtable

        Key:
            x:Name of the control

        Value:
            Reference to the corresponding control instance

    System.Boolean

        $false if an error occurs.

.EXAMPLE
    $controls = xuiGetControlElements `
        -RootElement $Window `
        -XmlFile '.\MainWindow.xaml'

.NOTES
    Name        : xuiGetControlElements
    Category    : WPF / UI Helper
    Version     : 1.00.02
    Author      : praetoriani
    Website     : https://github.com/WinTwin-Fusion/WinTwin.Fusion
    Requires    : PowerShell 5.1+

    This function is intended to provide a central and reliable method
    for resolving named WPF controls.

    Design principles:

    - No runtime XAML reconstruction
    - Uses the original XAML definition
    - Immediate failure on inconsistencies
    - Success only when all controls are resolved
    - Simple access through a hashtable

.LINK
    https://github.com/WinTwin-Fusion/WinTwin.Fusion
#>
function xuiGetControlElements {

    [CmdletBinding()]
    param(

        [Parameter(Mandatory = $true)]
        [ValidateNotNull()]
        [System.Windows.FrameworkElement]
        $RootElement,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]
        $XmlFile

    )

    try {

        # Verify that the XAML file exists.
        if (-not (Test-Path -Path $XmlFile -PathType Leaf)) {
            return $false
        }

        # Load the original XAML document.
        [xml]$xamlXml = Get-Content `
            -Path $XmlFile `
            -Raw `
            -ErrorAction Stop

        # Create namespace manager for x:Name lookups.
        $namespaceManager = [System.Xml.XmlNamespaceManager]::new(
            $xamlXml.NameTable
        )

        $namespaceManager.AddNamespace(
            'x',
            'http://schemas.microsoft.com/winfx/2006/xaml'
        )

        # Retrieve all elements that define an x:Name attribute.
        $namedNodes = $xamlXml.SelectNodes(
            '//*[@x:Name]',
            $namespaceManager
        )

        if ($null -eq $namedNodes) {
            return $false
        }

        # Hashtable containing all resolved controls.
        $controls = @{}

        foreach ($node in $namedNodes) {

            $controlName = $node.GetAttribute(
                'Name',
                'http://schemas.microsoft.com/winfx/2006/xaml'
            )

            # Every named element must provide a valid name.
            if (:IsNullOrWhiteSpace($controlName)) {
                return $false
            }

            # Resolve control from the visual tree.
            $control = $RootElement.FindName($controlName)

            # Missing controls are treated as failures.
            if ($null -eq $control) {
                return $false
            }

            $controls[$controlName] = $control
        }

        # Final consistency validation.
        if ($controls.Count -ne $namedNodes.Count) {
            return $false
        }

        return $controls
    }
    catch {
        return $false
    }
}

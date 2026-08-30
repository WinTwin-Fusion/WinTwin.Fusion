function xuiLoadWindow {
    <#
    .SYNOPSIS
        Safely loads a XAML/XML window definition and returns the live WPF window.

    .DESCRIPTION
        xuiLoadWindow is the generic WinTwin.XUI replacement for Import-XamlWindow
        from DISM.UI.CC\wim.mounter.fx.ps1.

        The original helper trusted the file, parsed it with [xml] and handed it
        straight to XamlReader. This function adds an explicit safety pipeline:

          1. Path / existence / size checks
          2. STA apartment check (WPF requirement)
          3. Secure XML parse (DTD prohibited, XmlResolver disabled)
          4. Structural validation (well-formed, WPF Window root, known xmlns)
          5. Rejection of code-behind (x:Class) and markup event attributes
          6. XamlReader.Load only after the document is considered clean
          7. Collection of all named controls into a hashtable

        Always returns an OPSreturn object. On success .data contains Window,
        Controls, Path and RootType.

    .PARAMETER XMLfile
        Full path to the XAML/XML window file (for example
        Core\ui\wim.mounter.main.xml).

    .OUTPUTS
        PSCustomObject from OPSreturn.

    .EXAMPLE
        $ui = xuiLoadWindow -XMLfile 'C:\WinTwin.Fusion\Core\ui\wim.mounter.main.xml'
        if ($ui.code -eq 0) {
            $window = $ui.data.Window
            $window.FindName('BtnMount').Add_Click({ ... })
            $null = $window.ShowDialog()
        }

    .NOTES
        Part of: WinTwin.XUI
        Alias : xuiLoadXMLwindow  (name used in the functional documentation)
        Replaces: Import-XamlWindow
        See also: OPSreturn, xuiSelectFile, xuiSelectFolder
    #>

    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    [Alias('xuiLoadXMLwindow')]
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [Alias('Path', 'XamlFilePath')]
        [string]$XMLfile,
        
        [Parameter(Mandatory = $false)]
        [switch]$extended
    )

    # --- Basic path checks ----------------------------------------------------
    if ([string]::IsNullOrWhiteSpace($XMLfile)) {
        return (OPSreturn -Code fail -Message "xuiLoadWindow failed! Parameter 'XMLfile' is required and must not be empty.")
    }
    if (-not (Test-Path -LiteralPath $XMLfile -PathType Leaf)) {
        return (OPSreturn -Code fail -Message "xuiLoadWindow failed! XML/XAML file not found: '$XMLfile'.")
    }

    try {
        $resolvedPath = (Resolve-Path -LiteralPath $XMLfile).ProviderPath
        $fileInfo     = Get-Item -LiteralPath $resolvedPath -ErrorAction Stop
    }
    catch {
        return (OPSreturn -Code fail -Message "xuiLoadWindow failed! Could not resolve '$XMLfile': $($_.Exception.Message)" -Exception $_.Exception)
    }

    # Guard against accidental huge/binary drops. Framework UI files are small XML documents.
    $maxBytes = 5MB
    if ($fileInfo.Length -le 0) {
        return (OPSreturn -Code fail -Message "xuiLoadWindow failed! File is empty: '$resolvedPath'.")
    }
    if ($fileInfo.Length -gt $maxBytes) {
        return (OPSreturn -Code fail -Message "xuiLoadWindow failed! File exceeds the $maxBytes safety limit: '$resolvedPath'.")
    }

    # WPF must run in a single-threaded apartment. Windows PowerShell is usually STA,
    # but custom runspaces and some hosts are not.
    if ([System.Threading.Thread]::CurrentThread.ApartmentState -ne [System.Threading.ApartmentState]::STA) {
        return (OPSreturn -Code fail -Message "xuiLoadWindow failed! The WPF surface must be loaded on an STA thread. Current apartment: $([System.Threading.Thread]::CurrentThread.ApartmentState).")
    }

    # --- Load WPF assemblies --------------------------------------------------
    try {
        Add-Type -AssemblyName PresentationFramework -ErrorAction Stop
        Add-Type -AssemblyName PresentationCore -ErrorAction Stop
        Add-Type -AssemblyName WindowsBase -ErrorAction Stop
        Add-Type -AssemblyName System.Xaml -ErrorAction Stop
    }
    catch {
        return (OPSreturn -Code fail -Message "xuiLoadWindow failed! Required WPF assemblies could not be loaded: $($_.Exception.Message)" -Exception $_.Exception)
    }

    # --- Secure XML parse -----------------------------------------------------
    # XAML is not a harmless config file: XamlReader instantiates objects.
    # We therefore parse with a locked-down XmlReader first and only then
    # hand a validated XmlDocument to XamlReader.
    $xmlSettings = New-Object System.Xml.XmlReaderSettings
    $xmlSettings.DtdProcessing             = [System.Xml.DtdProcessing]::Prohibit
    $xmlSettings.XmlResolver               = $null
    $xmlSettings.IgnoreComments            = $true
    $xmlSettings.IgnoreProcessingInstructions = $false
    $xmlSettings.IgnoreWhitespace          = $false
    $xmlSettings.MaxCharactersFromEntities = 1024
    $xmlSettings.MaxCharactersInDocument   = [int64]$maxBytes

    $xmlDocument = New-Object System.Xml.XmlDocument
    $xmlDocument.XmlResolver = $null

    $fileReader = $null
    try {
        $fileReader = [System.Xml.XmlReader]::Create($resolvedPath, $xmlSettings)
        $xmlDocument.Load($fileReader)
    }
    catch {
        return (OPSreturn -Code fail -Message "xuiLoadWindow failed! File is not well-formed XML: $($_.Exception.Message)" -Exception $_.Exception)
    }
    finally {
        if ($null -ne $fileReader) { $fileReader.Dispose() }
    }

    if ($null -eq $xmlDocument.DocumentElement) {
        return (OPSreturn -Code fail -Message "xuiLoadWindow failed! XML document has no root element: '$resolvedPath'.")
    }

    $root = $xmlDocument.DocumentElement

    # --- Structural / safety validation --------------------------------------
    if ($root.LocalName -ne 'Window') {
        return (OPSreturn -Code fail -Message "xuiLoadWindow failed! Root element must be a WPF <Window>, found '<$($root.LocalName)>' in '$resolvedPath'.")
    }

    $presentationNs = 'http://schemas.microsoft.com/winfx/2006/xaml/presentation'
    $xamlNs         = 'http://schemas.microsoft.com/winfx/2006/xaml'
    if ($root.NamespaceURI -ne $presentationNs) {
        return (OPSreturn -Code fail -Message "xuiLoadWindow failed! Root element is not in the WPF presentation namespace. Expected '$presentationNs'.")
    }

    # Code-behind cannot be resolved from a PowerShell-hosted XamlReader.
    $xClass = $root.GetAttribute('Class', $xamlNs)
    if (-not [string]::IsNullOrWhiteSpace($xClass)) {
        return (OPSreturn -Code fail -Message "xuiLoadWindow failed! x:Class='$xClass' is not supported. WinTwin.XUI loads view-only XAML without code-behind.")
    }

    # Markup event attributes (Click="OnClick") also require code-behind.
    $eventNameManager = New-Object System.Xml.XmlNamespaceManager($xmlDocument.NameTable)
    $eventNameManager.AddNamespace('x', $xamlNs)
    foreach ($node in $xmlDocument.SelectNodes('//*')) {
        if ($null -eq $node.Attributes) { continue }
        foreach ($attribute in @($node.Attributes)) {
            if ($attribute.Name -match '^(Click|Loaded|Closing|Closed|Checked|Unchecked|SelectionChanged|TextChanged|MouseLeftButtonDown|KeyDown|Drop)$') {
                return (OPSreturn -Code fail -Message "xuiLoadWindow failed! Markup event attribute '$($attribute.Name)' on '<$($node.LocalName)>' is not allowed. Wire events in PowerShell after loading.")
            }
        }
    }

    # --- Load as a live WPF window -------------------------------------------
    $nodeReader = $null
    $window     = $null
    try {
        $nodeReader = New-Object System.Xml.XmlNodeReader $xmlDocument
        $window = [System.Windows.Markup.XamlReader]::Load($nodeReader)
    }
    catch {
        return (OPSreturn -Code fail -Message "xuiLoadWindow failed! XamlReader rejected '$resolvedPath': $($_.Exception.Message)" -Exception $_.Exception)
    }
    finally {
        if ($null -ne $nodeReader) { $nodeReader.Dispose() }
    }

    if ($null -eq $window) {
        return (OPSreturn -Code fail -Message "xuiLoadWindow failed! XamlReader returned null while parsing '$resolvedPath'.")
    }
    if ($window -isnot [System.Windows.Window]) {
        return (OPSreturn -Code fail -Message "xuiLoadWindow failed! Parsed root is '$($window.GetType().FullName)', not System.Windows.Window.")
    }

    # Collect every named control so callers do not have to call FindName() for each one.
    $controls     = @{}
    $nameManager  = New-Object System.Xml.XmlNamespaceManager($xmlDocument.NameTable)
    $nameManager.AddNamespace('x', $xamlNs)

    foreach ($node in $xmlDocument.SelectNodes('//*[@x:Name or @Name]', $nameManager)) {
        $controlName = $node.GetAttribute('Name', $xamlNs)
        if ([string]::IsNullOrWhiteSpace($controlName)) {
            $controlName = $node.GetAttribute('Name')
        }
        if ([string]::IsNullOrWhiteSpace($controlName)) { continue }

        $control = $window.FindName($controlName)
        if ($null -ne $control) {
            $controls[$controlName] = $control
        }
    }

    $resultData = [pscustomobject]@{
        Window   = $window
        Controls = $controls
        Path     = $resolvedPath
        RootType = $window.GetType().FullName
    }

    if ( $extended.IsPresent ) {
        return (OPSreturn -Code success -Message "xuiLoadWindow: Window loaded successfully from '$resolvedPath'." -Data $resultData)        
    } else {
        return (OPSreturn -Code success -Message "xuiLoadWindow: Window loaded successfully from '$resolvedPath'." -Data $resultData.Window)
    }
}

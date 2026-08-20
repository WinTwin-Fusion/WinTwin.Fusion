# WTF.Console

**A graphical wrapper around the Windows console / terminal — the redirected-I/O backbone of the WinTwin.Fusion Framework.**

WTF.Console (WTF = *WinTwin.Fusion*) starts a hidden PowerShell child process and redirects its
standard input, output and error streams into its own WPF-based user interface. This allows every
DISM-, USMT-, aria2- or otherwise console-driven operation inside WinTwin.Fusion to be fully
supervised, logged and — if necessary — reacted to, without ever displaying a native console
window. WTF.Console is organizationally part of **PS.Tweak.Tools**, but is also fully capable of
running as an independent, standalone program.

## Table of Contents

- Core Idea
- Operating Modes
- Files
- Requirements
- Usage
- Command-Line Parameters
- Project Status
- License

## Core Idea

Windows console output for long-running operations (mounting a WIM, running USMT, downloading via
aria2) is normally only visible in an external console window that the user has little control
over. WTF.Console solves this by owning the process itself: it starts the target script in a
hidden child process, reads `StandardOutput`/`StandardError` line by line, and renders everything
inside its own terminal-style textbox — while forwarding user input back into the process via
`StandardInput`. Because the framework owns the entire I/O stream, it can inspect every line before
it is displayed and react to specific patterns (e.g. completion markers, error strings) as they
occur.

## Operating Modes

|Mode|Description|
|--|--|
|`framework` (default)|Uses the shared WinTwin.Fusion resources (`Core\ui`, `Core\lang`, `Core\db`, `Lib\...`), loads `OPSreturn`, `WinTwin.FXcore`, `PSAppCoreLib` and (optionally) `VPDLX`, honors `console.logging` from the global `Core\config.json`, watches output for defined trigger patterns, and exposes a Close + Minimize title bar (fixed size unless `-WinSize` is given).|
|`standalone`|Fully self-contained. Loads `wtf.console.main.xml`, its language files and `wtf.config.json` from a `.\wtf.data` folder next to the script. Loads no framework modules, does not watch output, and always exposes Close + Minimize + Maximize buttons; starts at 800×600 and is freely resizable.|

## Files

```
PS.Tweak.Tools/
├── WTF.Console.ps1        # Main script (this program)
├── wtf.readme.md          # This file
├── wtf.license.md         # License agreement (standalone-capable tool)
└── wtf.notice.md          # Notice file, referenced by wtf.license.md

Core/
├── ui/
│   └── wtf.console.main.xml   # WPF/XAML UI definition (framework mode)
├── lang/
│   ├── wtf.console.en-us.json # English language file (framework mode)
│   └── wtf.console.de-de.json # German language file (framework mode)
└── wtf.config.json            # Program configuration (version, author, website, ...)
```

In standalone mode, the equivalent `wtf.console.main.xml`, language files and `wtf.config.json`
are placed inside a `.\wtf.data` folder next to `WTF.Console.ps1` instead of under `Core\`.

## Requirements

- Windows 11, version 24H2 or 25H2 (build 26100 or later)
- PowerShell 5.1 or later
- .NET WPF assemblies (`PresentationFramework`, `PresentationCore`, `WindowsBase`) — included with
  Windows

## Usage

```powershell
# Framework mode (default) - honors global config.json, logs via VPDLX, watches output
.\WTF.Console.ps1 -ScriptPath "C:\WinTwin\Core\db\temp.mount.ps1" -Action mount

# Standalone mode - fully self-contained, no framework dependencies
.\WTF.Console.ps1 -ScriptPath ".\myscript.ps1" -AppMode standalone

# Framework mode with a custom window size
.\WTF.Console.ps1 -ScriptPath ".\myscript.ps1" -WinSize 640x480
```

## Command-Line Parameters

|Parameter|Mandatory|Description|
|--|--|--|
|`-ScriptPath`|Yes (both modes)|Full path to the PowerShell script to execute inside the redirected console process. Validated for existence before the process starts.|
|`-AppMode`|No|`framework` (default) or `standalone`.|
|`-WinSize`|No|Custom window size as `WIDTHxHEIGHT` (e.g. `640x480`). Framework mode only; standalone mode always starts at 800×600 and is resizable afterwards.|
|`-Action`|No|Optional action tag (e.g. `mount`, `unmount`) used to annotate the framework's process database (`Core\db\dbprocess.json`) so other tools can track what WTF.Console is doing.|
|`-Language`|No|Overrides the default UI language (`en-us` / `de-de`) defined in `wtf.config.json`.|

## Project Status

WTF.Console is an early but functional milestone of the WinTwin.Fusion Framework, intended to
become the shared console back end for every other tool (starting with `wim.mounter.ps1`) that
needs to run and supervise a console-based operation.

## License

See `wtf.license.md` and `wtf.notice.md` in this repository.

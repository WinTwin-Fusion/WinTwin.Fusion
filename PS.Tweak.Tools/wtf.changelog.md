# Changelog — WTF.Console

All notable changes to `WTF.Console.ps1` (part of `PS.Tweak.Tools`) are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this tool
adheres to `Major.Minor.Patch` versioning.

Each entry below shows only the version, date and a one-line summary by default. Click on an
entry (or its **Details** line) to expand the full list of changes.

---

<details>
<summary><strong>[1.01.00] — 2026-08-21</strong> — First real console job attached: mount-workflow integration with wim.mounter.ps1</summary>

### Added
- New optional `-LogFilePath` command-line parameter, allowing calling tools (e.g.
  `wim.mounter.ps1`) to dictate exactly which log file a given job should use, instead of
  WTF.Console always deriving its own log file name.
- First action-aware output watch-trigger implementation (`Test-WtfWatchTriggers`), currently
  covering the `mount` action (English/German success, error and in-progress patterns based on
  DISM console output).
- Process state is now written to `Core\db\dbprocess.json` in framework mode
  (`Write-WtfProcessState`), recording action, script path, log file, state and exit code with a
  timestamp.

### Changed
- Logging now always attempts `Write-VpdlxLog` first (VPDLX-formatted, verbose log entries) and
  only falls back to plain `Add-Content` text logging if VPDLX is not available.
- `wtf.config.json` gained a `console.logfile` map so individual actions (currently `mount`,
  `appx`) can be associated with their own log file naming pattern.

### Known Issues
- The `Test-WtfWatchTriggers` regex patterns are first-pass placeholders and have not yet been
  validated against real DISM console output; they are expected to be refined once manual testing
  of the `wim.mounter.ps1` mount workflow begins.
- The configurable startup window size (`-WinSize` / `appconfig.defaultwinsize`) is a first
  assumption and should be revisited together with the window-size requirement noted in
  `DEV.TASKS.md`.

</details>

<details>
<summary><strong>[1.00.00] — 2026-08-20</strong> — Initial implementation of WTF.Console</summary>

### Added
- `WTF.Console.ps1`: WPF-based embedded terminal replacement that starts a hidden, redirected
  PowerShell child process (`RedirectStandardInput/Output/Error`, `CreateNoWindow`) and displays
  its output in a themed terminal view instead of a native console window.
- Mandatory `-ScriptPath` parameter to specify the script that should be executed inside the
  redirected process.
- Dual operating mode support:
  - `-AppMode framework` — consumes the shared WinTwin.Fusion framework resources
    (`Core\ui`, `Core\lang`, `Core\wtf.config.json`, `Lib\...`), Close + Minimize window controls
    only, size controlled via `-WinSize` / `wtf.config.json`.
  - `-AppMode standalone` — fully self-contained/portable mode using a local `.\wtf.data` payload
    (its own UI/lang/config resources plus the shared `Lib\` modules), Close + Minimize +
    Maximize/Restore window controls, resizable window.
- `wtf.console.main.xml`: WPF window definition (custom title bar, terminal output view, command
  input box, Send/Clear buttons, status bar).
- `wtf.console.en-us.json`: English language resource file for all WTF.Console UI strings and
  console/log message templates.
- `Core\wtf.config.json`: WTF.Console-specific configuration (app info, default language, default
  app mode, default window size, standalone app-data path, console logging behavior).

</details>

---

*Maintained by the [WinTwin-Fusion](https://github.com/WinTwin-Fusion) team.*

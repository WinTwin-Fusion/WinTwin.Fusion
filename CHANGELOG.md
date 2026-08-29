# Changelog

All notable changes to the WinTwin.Fusion framework are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project
adheres to `Major.Minor.Patch` versioning.

Each entry below shows only the version, date and a one-line summary by default. Click on an
entry (or its **Details** line) to expand the full list of changes.

***

<details>
<summary><strong>[Unreleased]</strong> — Documentation re-sync: DEV.TASKS.md alignment, WinTwin.XUI introduced, README branding update</summary>

### Added
- `WinTwin.XUI` formally introduced as the framework's dedicated UI/XAML helper module
  (own repository, currently scaffolded), responsible for `xuiLoadXMLwindow`, `xuiOpenPath`,
  `xuiOpenFile` and centralized SVG/icon graphics loading, replacing tool-local helper files
  such as `wim.mounter.fx.ps1`.
- New planned `WinTwin.FXcore` functions documented: `wtfLoadJSON`, `wtfLoadJSONC`,
  `wtfWriteJSON`, `wtfGetJobAction`, `wtfSetJobAction`, `wtfSetCMDstate`.
- Centered WinTwin.Fusion logo (`wintwin.fusion.logo.png`) added to `README.md`.

### Changed
- `DEV.TASKS.md` updated to reflect the 22.08.2026 documentation revision, including the
  clarified distinction between `Core\db\process.json` (single active process/job lock) and
  `Core\db\jobaction.json` (per-action metadata and status).
- `README.md` refreshed to mention `WinTwin.XUI` alongside `WinTwin.FXcore` as the framework's
  two preferred, mandatory shared libraries, and to document the protected `main` branch /
  development branch workflow.

</details>

<details>
<summary><strong>[0.2.0] — 2026-08-20</strong> — Console installer hardened: admin gate, machine-wide font install, license integrity check, English source</summary>

### Added
- `Assert-AdministratorOrExit`: elevation check now runs as the very first action in
  `wintwin.installer.ps1`. If the script is not running as Administrator, an error message is
  printed and the script terminates immediately, before any file system or registry change.
- `Install-FrameworkFonts`: installs every `.ttf` / `.ttc` / `.otf` file found under
  `.\Core\fonts` machine-wide (for **all** users), by copying files into `%WINDIR%\Fonts` and
  registering them under `HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Fonts`.
  Fonts are activated immediately via a `WM_FONTCHANGE` broadcast (no reboot required).
- `Get-FontRegistryDisplayName`: resolves the correct font family name via
  `System.Drawing.Text.PrivateFontCollection` to build Windows-correct registry value names
  (`"<Name> (TrueType)"` / `"(OpenType)"`).
- `Test-FrameworkLicenseIntegrity`: verifies that `LICENSE.md` and `NOTICE` exist in the framework
  root and validates their SHA512 checksum against the official WinTwin.Fusion reference values.
  Missing files or checksum mismatches are reported as failed checklist items without aborting
  the rest of the installation.
- New parameter `-SkipFontInstall` to skip the font installation step entirely.

### Changed
- The entire `wintwin.installer.ps1` source code (comments, messages, identifiers, comment-based
  help) was translated from German to **English**, per the project-wide source code language
  standard.
- Installer version bumped to `0.2.0`.
- `Core\config.json` now also records `FontsInstalledCount`.

### Known Issues
- The graphical checkbox-based progress display described in the concept documentation is not
  yet implemented; this version remains console-only by design.

</details>

<details>
<summary><strong>[0.1.0] — 2026-08-20</strong> — First console-only installer script (foundation)</summary>

### Added
- `wintwin.installer.ps1`: first, GUI-less version of the framework installer, implemented as a
  single, self-contained script (no dependency on `WinTwin.FXcore` / `OPSreturn` /
  `PSAppCoreLib` / `VPDLX`).
- Framework root auto-detection via `$PSScriptRoot`.
- Windows 11 24H2/25H2 detection (build ≥ 26100) via registry.
- DISM functionality check (`dism.exe /Online /Get-CurrentEdition`).
- Windows ADK detection (`KitsRoot10` registry key + `Deployment Tools` folder check).
- Windows ADK WinPE Add-on detection.
- Silent (re-)installation of ADK / WinPE Add-on from `.\AddOns\adksetup.exe` /
  `.\AddOns\adkwinpesetup.exe` when missing.
- Full target folder structure creation (`AddOns`, `Core` + subfolders, `DISM.UI.CC`, `Lib` +
  module subfolders, `PS.Tweak.Tools`, `USMT.Composer`, plus all documented runtime folders).
- `Core\config.json` creation/update logic that preserves unknown/custom keys and backs up a
  corrupt file as `.bak` before overwriting.
- Console checklist summary (`[x]` / `[!]` / `[ ]` / `[-]`) at the end of the run.
- `"Press any key to exit."` prompt before the console window closes.
- Companion `INSTALLER-README.md` documentation.

### Notes
- This initial version was authored with German-language comments/messages and was fully
  superseded by the English rewrite in `[0.2.0]`.

</details>

<details>
<summary><strong>[0.0.2] — 2026-08-20</strong> — WinTwin.FXcore adapted for framework integration</summary>

### Changed
- `WinTwin.FXcore` (formerly `WinISO.ScriptFXLib`) public and private functions were reviewed and
  adjusted so the module can already be consumed from within the WinTwin.Fusion framework
  ecosystem, ahead of the planned deeper architectural rework noted in the concept documentation.

</details>

<details>
<summary><strong>[0.0.1] — 2026-08-20</strong> — Repository reorganization under WinTwin-Fusion</summary>

### Changed
- The former standalone repositories `WinISO.ScriptFXLib` and `DISM.UI.CC` were retired and their
  content migrated into the new `WinTwin-Fusion` GitHub organization.
- `WinISO.ScriptFXLib` was renamed to `WinTwin.FXcore`.
- The legacy `WinISO Image Mounter` tool was integrated into `DISM.UI.CC` and renamed to
  `wim.mounter` (officially: *DISM.UI Control Center - wim.mounter*).

### Added
- Initial WinTwin.Fusion repository scaffold, including the full documented target folder
  structure, `LICENSE.md`, `NOTICE` and a project README stub.

### Known Issues
- `wim.mounter.ps1` currently freezes after a DISM operation completes; the process can only be
  terminated via Task Manager. The planned fix is to fully redirect the console input/output
  stream internally (see `WTF.Console` in `DEV.TASKS.md`) instead of relying on an external
  console window/process.

</details>

***

*Maintained by the [WinTwin.Fusion](https://github.com/WinTwin-Fusion) team.*

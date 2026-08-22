# Changelog — wim.mounter (DISM.UI.CC)

All notable changes to `wim.mounter.ps1` (part of `DISM.UI.CC`) are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this tool
adheres to `Major.Minor.Patch` versioning.

Each entry below shows only the version, date and a one-line summary by default. Click on an
entry (or its **Details** line) to expand the full list of changes.

---

<details>
<summary><strong>[1.01.00] — 2026-08-21</strong> — WTF.Console integration: mount jobs no longer freeze the tool</summary>

### Added
- `ChkCreateMountPoint` checkbox in the mount UI ("Create mount point if it does not exist"),
  wired into the mount-button validation logic so a missing mount directory is only accepted when
  the checkbox is enabled.
- `New-WimMountConsoleScript` (in `wim.mounter.fx.ps1`): generates a self-contained
  `Core\export\mount.image.ps1` job script for the current mount request (WIM path, mount
  directory, WIM index, create-mount-point behavior, DISM invocation, exit-code handling).
- `Start-WtfConsoleProcess` (in `wim.mounter.fx.ps1`): starts `PS.Tweak.Tools\WTF.Console.ps1` as
  an independent, detached PowerShell process (`-AppMode framework -Action mount -LogFilePath ...`)
  so `wim.mounter.ps1` can close immediately after handing off the job.
- New status messages (`status.launchingConsole`) and label strings (`labels.createMountPoint`)
  in both `Core\lang\wim.mounter.en-us.json` and `Core\lang\wim.mounter.de-de.json`.
- Dedicated mount-job log file computed from `Core\config.json` → `console.logfile.mount` and
  passed explicitly into `WTF.Console.ps1` via `-LogFilePath`.

### Changed
- `wim.mounter.ps1` no longer invokes DISM directly. The **Mount** button now only validates the
  form, generates the job script and log file path, starts `WTF.Console.ps1`, and closes its own
  window — the DISM operation itself, its console output and its logging are now fully owned by
  `WTF.Console.ps1`.
- Field validation for the mount-point path now depends on the new "Create mount point" checkbox
  state instead of always requiring the directory to already exist.

### Known Issues
- The generated `mount.image.ps1` currently always uses the configured default WIM index
  (`Core\config.json` → `wim.index`); no per-mount index selection exists yet in the UI.
- This version has not yet been validated by real end-to-end manual testing (see
  `DEV.TASKS.md` → *Testing & Validation*); the previously known post-DISM freeze issue is
  expected to be resolved by this change but is not yet confirmed on a real Windows 11 test
  machine.
- `wim.mounter.fx.ps1` is a transitional helper file. The functions it currently contains are
  planned to be migrated into `WinTwin.FXcore` / shared UI-helper modules, after which
  `wim.mounter.fx.ps1` itself will be removed (see `DEV.TASKS.md`).

</details>

<details>
<summary><strong>[1.00.02] — 2026-08-19</strong> — Legacy standalone mount tool baseline</summary>

### Added
- `wim.mounter.ps1` (formerly the standalone *WinISO Image Mounter*), migrated into
  `DISM.UI.CC` and renamed to `wim.mounter` (officially: *DISM.UI Control Center - wim.mounter*).
- WPF-based mount UI (`wim.mounter.main.xml`): image file picker, mount-point folder picker,
  Mount/Cancel/Exit actions, dark themed custom window chrome.
- English and German language resource files (`wim.mounter.en-us.json`,
  `wim.mounter.de-de.json`).
- Direct DISM-based mounting (`DISM /Mount-Wim`) invoked from within the tool's own process.

### Known Issues
- `wim.mounter.ps1` freezes after a DISM operation completes; the process could only be
  terminated via Task Manager. Root cause: reliance on an external console process instead of a
  fully redirected internal stream. Fix planned via `WTF.Console.ps1` (delivered in `[1.01.00]`
  above).

</details>

---

*Maintained by the [WinTwin-Fusion](https://github.com/WinTwin-Fusion) team.*

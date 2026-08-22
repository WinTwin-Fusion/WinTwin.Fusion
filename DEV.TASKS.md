
# Development Tasks — WinTwin.Fusion

This file tracks the currently pending work items for the WinTwin.Fusion framework. It is a
living document and is updated as tasks are completed, reprioritized, or newly identified. Items
are grouped by priority horizon (short-term / mid-term / long-term), mirroring the roadmap in the
project's concept documentation.

Legend: `[x]` done · `[ ]` open · `[~]` in progress

---

## Short-Term (next iteration)

- [x] Adapt `WinTwin.FXcore` public/private functions so they are usable from within the
      WinTwin.Fusion framework ecosystem.
- [x] Build `wintwin.installer.ps1` v0.1.0 — first console-only installer foundation.
- [x] Rewrite `wintwin.installer.ps1` entirely in English (project-wide source code language
      standard).
- [x] Add administrator elevation check as the very first installer action (immediate,
      message-based termination if not elevated).
- [x] Add machine-wide (all-users) Google Fonts installation routine to the installer, sourcing
      font files from `.\Core\fonts`.
- [x] Add SHA512-based integrity verification for `LICENSE.md` and `NOTICE` in the framework root.
- [ ] Deeper rework of `WinTwin.FXcore`: revisit the private `OPSreturn` helper, update
      `WinTwin.FXcore.psm1` / `.psd1` for full framework integration, and re-validate all private
      functions against the new ecosystem (the module was originally designed as a standalone
      module and needs a conceptual pass now that it is a framework-internal dependency).
- [x] Design and implement `WTF.Console.ps1` (embedded terminal replacement):
  - [x] Works as a genuine standalone tool (`-AppMode standalone`, self-contained `.\wtf.data`
        payload) as well as in framework mode (`-AppMode framework`).
  - [x] Mandatory `-ScriptPath` command-line parameter to receive the path of the script to
        execute.
  - [x] Internal hidden console process with full input/output/error stream redirection
        (`System.Diagnostics.Process`, `RedirectStandardInput/Output/Error`, `CreateNoWindow`).
  - [x] Optional `-LogFilePath` command-line parameter so calling tools (e.g. `wim.mounter.ps1`)
        can dictate exactly which log file is used for a given job.
  - [~] Output inspection/formatting before it is displayed (framework mode only) — a first,
        intentionally simple regex-based watch-trigger implementation
        (`Test-WtfWatchTriggers`) exists for the `mount` action only and needs to be validated
        against real DISM console output, then extended to the other planned actions.
  - [~] Fixed startup window size — currently configurable via `-WinSize` / `wtf.config.json`
        (`appconfig.defaultwinsize`, default `800x600`) instead of hard-coded, pending feedback
        on whether a fixed size is still desired or configurability should remain.
  - [ ] Optional Google Fonts usage in framework mode — not yet implemented.
  - [x] Completed and wired up **before** `wim.mounter.ps1` was reworked to depend on it, per the
        original sequencing requirement.

## Mid-Term

- [~] Rework `wim.mounter.ps1` on top of the new architecture:
  - [x] Integrate `WinTwin.FXcore` / `OPSreturn` (and `PSAppCoreLib` where applicable) as
        dot-sourced functions — first pass via `wim.mounter.fx.ps1` (see refactoring note below;
        this file is a transitional helper, not the final module integration).
  - [x] Migrate the legacy `config.json` and `de-de.json` into the new global configuration and
        language files (`Core\config.json`, `Core\lang\wim.mounter.*.json`).
  - [x] Re-point all path references to the global `config.json`.
  - [x] Rework the mount function itself: `wim.mounter.ps1` no longer calls DISM directly; it
        generates `Core\export\mount.image.ps1` and hands it off to `WTF.Console.ps1`, which is
        started as an independent, detached process (`-AppMode framework -Action mount
        -LogFilePath ...`) so `wim.mounter.ps1` can close immediately afterwards.
  - [ ] Add command-line parameters for external (cross-tool) control — not yet implemented for
        `wim.mounter.ps1` itself (WTF.Console already supports this on the receiving side).
  - [x] Add a "Create Mountpoint" checkbox to the UI for missing output folders
        (`ChkCreateMountPoint`, wired into `wim.mounter.ps1` validation logic).
  - [ ] Verify `wim.mounter.ps1` is fully stable and freeze-free after the `WTF.Console`
        integration — **pending manual end-to-end testing**, see "Testing & Validation" section
        below.
- [ ] **Refactoring debt — replace `wim.mounter.fx.ps1` with proper modules.** `wim.mounter.fx.ps1`
      was introduced as a fast, pragmatic first-pass helper library (console window state,
      XAML loading, field-validation helpers, mount script generation, WTF.Console process
      launch). This is intentionally a stop-gap and must **not** become a long-term pattern:
  - [ ] Move generic/reusable helpers (`Import-XamlWindow`, `Show-FieldError`,
        `Clear-FieldError`, `Set-ConsoleWindowState`) into a shared UI-helper module consumed by
        *all* DISM.UI.CC tools (candidate: a new `WinTwin.FXcore` sub-area or a dedicated
        `PSAppCoreLib` UI namespace), instead of duplicating/copy-pasting them per tool.
  - [ ] Move `New-WimMountConsoleScript` (and equivalents for future actions such as unmount,
        Appx/MSIX, capability/feature/package operations) into `WinTwin.FXcore` as proper,
        versioned, testable public functions that return `OPSreturn`-style result objects instead
        of writing ad-hoc script text.
  - [ ] Move `Start-WtfConsoleProcess` into a shared module as well, so every DISM.UI.CC /
        USMT.Composer tool launches WTF.Console the exact same way (consistent argument
        contract, consistent error handling).
  - [ ] Once all functions have been migrated, delete `wim.mounter.fx.ps1` entirely and update
        `wim.mounter.ps1` to dot-source/import only the shared modules.
- [ ] Introduce a small, structured job-metadata model (JSON, fields such as `Action`,
      `ScriptPath`, `LogFile`, `Arguments`, `CreatedAt`, `Status`, `ExitCode`) instead of the
      current single-snapshot `Core\db\dbprocess.json`, so multiple/queued WTF.Console jobs can be
      tracked reliably and other tools can safely read job state.
- [ ] Centralize WTF.Console / tool logging behind one logging adapter that always targets VPDLX
      and only falls back to plain `Add-Content` text logging as a last resort, instead of the
      current dual-path (`Write-VpdlxLog` if available, else plain text) inside `WTF.Console.ps1`.
- [ ] Harden and extend `Test-WtfWatchTriggers` in `WTF.Console.ps1`: validate the current `mount`
      regex patterns against real DISM output captured during manual testing, then add equivalent
      pattern sets for unmount, Appx/MSIX, feature, package, capability and registry-hive actions.
- [ ] Evaluate adding WIM index selection to the `wim.mounter.ps1` UI instead of always relying on
      the configured default index (`Core\config.json` → `wim.index`).
- [ ] Build `wim.unmount.ps1` using the finalized `wim.mounter.ps1` (WTF.Console-integrated
      version) as a blueprint.
- [ ] Build the remaining DISM.UI.CC tools using the same blueprint:
  - [ ] `wim.ctrl.image.ps1` — image information.
  - [ ] `wim.ctrl.drivers.ps1` — driver management.
  - [ ] `wim.ctrl.features.ps1` — Windows feature management.
  - [ ] `wim.ctrl.packages.ps1` — package management.
  - [ ] `wim.ctrl.msstore.ps1` — Appx/MSIX management (backing `WinTwin.FXcore` functions already
        exist: `GetAppxPackages`, `RemAppxPackages`, `AddAppxPackages`, `AppxPackageLookUp`).
  - [ ] `wim.ctrl.capability.ps1` — Windows Capabilities management.
  - [ ] `wim.ctrl.reghive.ps1` — offline registry hive editing (backing `WinTwin.FXcore` functions
        already exist: `LoadRegistryHive`, `RegistryHiveAdd/Rem/Import/Export/Query`,
        `UnloadRegistryHive`).
- [ ] Implement global mount-state tracking (prevent mounting a second image while one is already
      mounted), including an "always on top" status window showing mount path, image name and
      index.
- [ ] First implementation pass for `.\Core\pid.store` as a shared cross-tool data store.
- [ ] Baseline (non-production) implementation of named pipes for future inter-tool communication.
- [ ] Begin `USMT.Composer` components: `ucb.appdata.ps1`, `ucb.usrdata.ps1`, `ubr.appdata.ps1`,
      `ubr.usrdata.ps1`.
- [ ] Begin the UUP Dump `PS.Tweak.Tools` GUI wrappers (backing `WinTwin.FXcore` functions already
      exist: `DownloadUUPDump`, `ExtractUUPDump`, `CreateUUPDiso`, `ExtractUUPDiso`,
      `CleanupUUPDump`, `RenameUUPDiso`):
  - [ ] `UUPDcatcher.ps1`
  - [ ] `UUPDisodump.ps1` / `UUPDwimdump.ps1`
  - [ ] `UUPDcompose.ps1`

## Testing & Validation (new)

- [ ] Manual end-to-end test of the `wim.mounter.ps1` → `Core\export\mount.image.ps1` →
      `WTF.Console.ps1` chain on a real Windows 11 test machine: confirm `wim.mounter.ps1` closes
      immediately after handing off, `WTF.Console.ps1` starts as an independent process, DISM
      output is visible and legible in the terminal view, and the process exit status is reflected
      correctly in the UI.
- [ ] Verify that a VPDLX-formatted log file is always created for the `mount` action, both when
      DISM succeeds and when it fails, and that the log content matches the required verbose
      VPDLX format.
- [ ] Negative test: attempt to mount into a non-existent mount point with "Create mount point if
      it does not exist" **disabled** — must be rejected by `wim.mounter.ps1` validation before
      `WTF.Console.ps1` is ever started.
- [ ] Negative test: attempt to mount into a non-existent mount point with "Create mount point if
      it does not exist" **enabled** — the directory must be created by the generated
      `mount.image.ps1` job script and the mount must proceed normally.
- [ ] Verify `Core\db\dbprocess.json` is updated with sensible state transitions
      (`running` → `success`/`error` → `finished`) during a real mount job.

## Long-Term

- [ ] Implement the framework-wide "autounattend" mode (JSON task definition consumed via
      command line, executed without any user interaction).
- [ ] Build `DeskPacker.ps1` (backup/restore of taskbar, start menu, desktop, quick access and
      personalization settings).
- [ ] Build `AutoClone.ps1` (fully automated, preconfigured cloning workflow orchestrator).
- [ ] Build `AutoInstall.ps1` (internal autounattend.xml generator with GUI, based on
      Schneegans.de reference).
- [ ] Evaluate and, if viable, implement the "extract only `install.wim` instead of the full ISO"
      optimization to reduce temporary disk space usage during UUP Dump processing.
- [ ] Migrate standalone `PS.Tweak.Tools` / `USMT.Composer` scripts into proper PowerShell modules
      (`WinTwin.PSTweaks`, `WinTwin.USMTctrl`), so `WinTwin.FXcore` can eventually fully replace
      `DISM.UI.CC` as a module-only distribution of the framework.
- [ ] Add a graphical, checkbox-based progress UI to `wintwin.installer.ps1` (the current version
      is console-only by design; see `CHANGELOG.md`).
- [ ] Build a self-hosted RSAT offline repository as a framework add-on capability.
- [x] Author per-tool `LICENSE.md` / `NOTICE` files for every standalone tool in the framework,
      following the VPDLX pattern — first done for `WTF.Console` (`wtf.license.md` /
      `wtf.notice.md`); remaining standalone tools still need their own copies.

## Known Issues / Risks

- `wim.mounter.ps1` previously froze after a DISM operation completed and had to be terminated via
  Task Manager. Root cause: reliance on an external console process instead of a fully redirected
  internal stream. This is now addressed architecturally via `WTF.Console.ps1`, but the fix is
  **not yet confirmed by real end-to-end testing** — see "Testing & Validation" above.
- `WTF.Console.ps1`'s DISM/USMT output watch-trigger patterns (`Test-WtfWatchTriggers`) and the
  configurable window size defaults are first-pass placeholders/assumptions and are explicitly
  flagged for joint review once real console operations (starting with `wim.mounter.ps1`) are
  attached and tested.
- `wim.mounter.fx.ps1` is a transitional, tool-local helper file and is **not** the final
  architecture; see the dedicated refactoring debt item above.
- The Windows 11 24H2/25H2 build-number check in `wintwin.installer.ps1` only warns and does not
  block installation on unsupported systems; this is intentional for now but should be revisited
  once the framework depends on version-specific DISM/ADK behavior.

---

*This file is maintained alongside `CHANGELOG.md`. Completed items should be moved into a new
`CHANGELOG.md` entry and checked off here, not deleted, to preserve traceability.*

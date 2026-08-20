
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
- [ ] Design and implement `WTF.Console.ps1` (embedded terminal replacement):
  - [ ] Must work as a genuine standalone tool (mandatory requirement).
  - [ ] Mandatory command-line parameter to receive the path of the script to execute.
  - [ ] Internal hidden console process with full input/output stream redirection.
  - [ ] Output inspection/formatting before it is displayed (framework mode only).
  - [ ] Fixed 800x600 startup window size.
  - [ ] Optional Google Fonts usage in framework mode.
  - [ ] Must be completed **before** `wim.mounter.ps1` is reworked, since it depends on this
        component to fix the known post-DISM freeze issue.

## Mid-Term

- [ ] Rework `wim.mounter.ps1` on top of the new architecture:
  - [ ] Integrate `WinTwin.FXcore` / `OPSreturn` (and `PSAppCoreLib` where applicable) as
        dot-sourced functions.
  - [ ] Migrate the legacy `config.json` and `de-de.json` into the new global configuration and
        language files.
  - [ ] Re-point all path references to the global `config.json`.
  - [ ] Rework the mount function itself.
  - [ ] Add command-line parameters for external (cross-tool) control.
  - [ ] Add a "Create Mountpoint" checkbox to the UI for missing output folders.
  - [ ] Verify `wim.mounter.ps1` is fully stable and freeze-free after the `WTF.Console`
        integration.
- [ ] Build `wim.unmount.ps1` using the finalized `wim.mounter.ps1` as a blueprint.
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
- [ ] Author per-tool `LICENSE.md` / `NOTICE` files for every standalone tool in the framework,
      following the VPDLX pattern.

## Known Issues / Risks

- `wim.mounter.ps1` currently freezes after a DISM operation completes and must be terminated via
  Task Manager. Root cause: reliance on an external console process instead of a fully redirected
  internal stream. **Blocked on:** `WTF.Console.ps1`.
- The Windows 11 24H2/25H2 build-number check in `wintwin.installer.ps1` only warns and does not
  block installation on unsupported systems; this is intentional for now but should be revisited
  once the framework depends on version-specific DISM/ADK behavior.

---

*This file is maintained alongside `CHANGELOG.md`. Completed items should be moved into a new
`CHANGELOG.md` entry and checked off here, not deleted, to preserve traceability.*

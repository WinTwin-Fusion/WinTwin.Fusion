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
  - [ ] When started by `wim.mounter.ps1`, launch `dism.watchdog` at the end of the job instead of
        allowing the framework to close while an image is still mounted, and ensure
        `jobaction.json` → `wim-mount.state` is set to `true` so other tools can reliably detect
        an active mount (per the latest concept-documentation update, 21.08.2026).

## New From Documentation Update (2026-08-22)

- [ ] **`WinTwin.XUI` — new dedicated PowerShell module (own GitHub repository, already
      scaffolded at `WinTwin-Fusion/WinTwin.XUI`, currently a stub with a placeholder
      `README.md`).** Exclusively responsible for graphical/UI interactions of every GUI tool in
      the framework, so tools no longer need program-local helper files
      (e.g. `wim.mounter.fx.ps1`):
  - [ ] Implement a private, module-internal `OPSreturn` function modeled on the original
        `OPSreturn` module (mirrors the same requirement already tracked for `WinTwin.FXcore`,
        since `WinTwin.XUI` must also work without a hard dependency on the external module).
  - [ ] Implement `xuiLoadXMLwindow -XMLfile <path>` — loads a XAML/XML GUI window file, replacing
        `Import-XamlWindow` from `wim.mounter.fx.ps1`; must validate all prerequisites before
        loading, abort cleanly on error, and always return an `OPSreturn` object.
  - [ ] Implement `xuiOpenPath` — shows the standard Windows folder-picker dialog (always
        foreground-focused), replacing `Select-MountFolder`; returns the selected path via an
        `OPSreturn` object.
  - [ ] Implement `xuiOpenFile -Filter <filter> -Title <title>` — shows the standard Windows
        file-picker dialog (optional `-Filter` / `-Title`), replacing `Select-WimFile`; returns
        the selected file path via an `OPSreturn` object.
  - [ ] Add functions to load external `*.ico`, `*.png` and `*.svg` graphics for use inside the
        XAML UI.
  - [ ] Build an internal SVG graphics library: predefined, reusable SVG icon code (always in
        neutral white) shared across all framework components (`PS.Tweak.Tools`, `DISM.UI.CC`,
        etc.); colorization happens at the point of use.
  - [ ] Fully English, well-commented source code; add a `.\Samples` folder with example scripts
        and one or two simple demonstration XAML files.
  - [ ] Adapt the WinTwin.Fusion `LICENSE.md` / `NOTICE` for `WinTwin.XUI`, explicitly stating
        that this is an exclusive library for the WinTwin.Fusion framework and that any use
        outside the framework is at the user's own risk (not originally designed for external
        reuse).
  - [ ] Add `README.md` and `CHANGELOG.md` following the same structure/format used across all
        other framework changelogs (unified changelog format requirement).
  - [ ] Evaluate the architecture recommendations gathered from the PowerShell/WPF/XAML research
        session (Event-Map + thin `ScriptBlock` handlers, per-window controller, `Import-WpfView`
        -style control auto-discovery, `Register-WpfEventMap` / `Unregister-WpfEvents` cleanup
        pattern) as a design reference for `xuiLoadXMLwindow` and future `WinTwin.XUI` event-wiring
        helpers — the module should stay pure UI infrastructure and must not encode any
        tool-specific business logic.
- [ ] **`WinTwin.FXcore` — additional core functions identified in the functional
      documentation**, to be implemented alongside the already-tracked deeper rework:
  - [ ] `wtfLoadJSON -JSONfile <path>` — reads a JSON file and returns its content; returns an
        `OPSreturn` error object if the parameter is missing/empty or the file does not exist.
  - [ ] `wtfLoadJSONC -JSONfile <path>` — reads a JSONC file, strips `//` and `/* */` comments to
        produce valid JSON, and returns the converted content; same `OPSreturn` error handling as
        `wtfLoadJSON`.
  - [ ] `wtfWriteJSON -FileType <json|jsonc> -JSONfile <path> -KeyID <key> -DataType
        <string|bool|int|object|array> -Data <value>` — writes a value to a specific key in a
        JSON/JSONC file; must support writing empty values and always return an `OPSreturn`
        object; aborts if prerequisites are not met or the write fails.
  - [ ] `wtfGetJobAction -ActionID <id> [-KeyID <key>]` — reads details for a job action from
        `.\Core\db\jobaction.json`; returns the full action object when `-KeyID` is omitted, or
        just the requested key's value when provided; aborts (with an `OPSreturn` error) if the
        action or key cannot be found.
  - [ ] `wtfSetJobAction -ActionID <id> -KeyID <key> -DataType <type> -Data <value>` — writes a
        value into a job action entry in `.\Core\db\jobaction.json`; always returns an
        `OPSreturn` object; aborts if the file is missing or prerequisites are not met.
  - [ ] `wtfSetCMDstate -State <hide|show> [-invisible]` — forcibly minimizes/restores (`show`) or
        completely hides (`hide -invisible`) the Windows Terminal/console window, replacing
        `Set-ConsoleWindowState` from `wim.mounter.fx.ps1`.
- [ ] Implement the `-appmode standalone` app-data redirection pattern consistently across all
      framework tools: when `-appmode standalone` is passed (default remains `framework`), the
      tool looks for a local `.\appdata` folder mirroring the framework's own directory layout
      (containing only the subset of data the tool actually needs) and re-points all internal path
      references to it; this keeps the standalone/portable code path structurally identical to the
      framework mode and minimizes standalone-specific development effort.
- [ ] Evaluate centralizing all inline/external SVG and icon graphics for every tool in a single
      UI graphics store inside `WinTwin.XUI`, instead of per-tool inline SVG, to simplify
      maintenance across the framework; PNG/SVG remain the fallback where inline SVG is not
      feasible, `*.ico` remains the only accepted non-SVG/PNG exception.

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
  - [ ] Move generic/reusable UI helpers (`Import-XamlWindow`, `Show-FieldError`,
        `Clear-FieldError`) into the new `WinTwin.XUI` module (see "New From Documentation Update"
        above) instead of a shared `WinTwin.FXcore` sub-area or `PSAppCoreLib` namespace — this
        supersedes the earlier "candidate" note now that `WinTwin.XUI` exists as its own module.
  - [ ] Move `Set-ConsoleWindowState` into `WinTwin.FXcore` as `wtfSetCMDstate` (see above).
  - [ ] Move `New-WimMountConsoleScript` (and equivalents for future actions such as unmount,
        Appx/MSIX, capability/feature/package operations) into `WinTwin.FXcore` as proper,
        versioned, testable public functions that return `OPSreturn`-style result objects instead
        of writing ad-hoc script text.
  - [ ] Move `Start-WtfConsoleProcess` into a shared module as well, so every DISM.UI.CC /
        USMT.Composer tool launches WTF.Console the exact same way (consistent argument
        contract, consistent error handling).
  - [ ] Once all functions have been migrated, delete `wim.mounter.fx.ps1` entirely and update
        `wim.mounter.ps1` to dot-source/import only the shared modules (`WinTwin.FXcore` +
        `WinTwin.XUI`).
- [ ] Introduce a small, structured job-metadata model (JSON, fields such as `Action`,
      `ScriptPath`, `LogFile`, `Arguments`, `CreatedAt`, `Status`, `ExitCode`) instead of the
      current single-snapshot `Core\db\dbprocess.json`, so multiple/queued WTF.Console jobs can be
      tracked reliably and other tools can safely read job state. Must align with the two
      distinct, formally documented databases now specified in the concept documentation:
      `Core\db\process.json` (tracks the single currently-running process/job, `running.job-state`
      = `running`/`finished`, used to block concurrent tool starts) and `Core\db\jobaction.json`
      (per-action metadata/status, backed by the new `wtfGetJobAction` / `wtfSetJobAction`
      functions above). The `lastjob` and `linedup` keys in `process.json` remain unused until
      further notice.
- [ ] Centralize WTF.Console / tool logging behind one logging adapter that always targets VPDLX
      and only falls back to plain `Add-Content` text logging as a last resort, instead of the
      current dual-path (`Write-VpdlxLog` if available, else plain text) inside `WTF.Console.ps1`.
- [ ] Harden and extend `Test-WtfWatchTriggers` in `WTF.Console.ps1`: validate the current `mount`
      regex patterns against real DISM output captured during manual testing, then add equivalent
      pattern sets for unmount, Appx/MSIX, feature, package, capability and registry-hive actions.
      All DISM invocations (regardless of caller) must always pass the additional `/english`
      parameter, even when the framework's configured UI language is not `en-us`, so these watch
      triggers stay reliable.
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
- [ ] Verify that every framework tool correctly checks `Core\db\process.json` on startup
      (`running.job-state`), refuses to start a second concurrent job, and correctly
      registers/deregisters itself at start/end — per the process-handoff example
      (`wim.mounter` → `WTF.Console`) now formally documented in the concept documentation.

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
  architecture; see the dedicated refactoring debt item above. Its target replacement is now
  split across two modules: `WinTwin.FXcore` (data/job/logic helpers) and the new `WinTwin.XUI`
  (UI/XAML/dialog helpers).
- The `WinTwin.XUI` repository currently only contains a placeholder `README.md`; none of the
  functions specified in the functional documentation have been implemented yet.
- The Windows 11 24H2/25H2 build-number check in `wintwin.installer.ps1` only warns and does not
  block installation on unsupported systems; this is intentional for now but should be revisited
  once the framework depends on version-specific DISM/ADK behavior.

---

*This file is maintained alongside `CHANGELOG.md`. Completed items should be moved into a new
`CHANGELOG.md` entry and checked off here, not deleted, to preserve traceability.*

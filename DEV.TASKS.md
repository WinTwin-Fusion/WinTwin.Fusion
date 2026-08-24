# WinTwin.Fusion — Development Tasks

> **Purpose:** This file contains only active, uncompleted work for the WinTwin.Fusion framework repository.
> **Scope rule:** Implement component-specific changes in the owning component repository first. Synchronize them into this repository only through the established component-sync workflow.
> **Workflow:** Create work on a dedicated branch, validate it, open a pull request, and merge only after review.

## P0 — Release-Blocking Foundation

- [ ] **Define and publish the supported baseline.** Document supported Windows 11 editions/builds, host architecture, PowerShell edition/version, required elevation, Windows ADK/WinPE ADK versions, DISM source requirements, and minimum free disk space. Add explicit preflight failures for unsupported or incomplete environments.
- [ ] **Implement one end-to-end recovery acceptance test.** On a clean Windows 11 test VM, create a medium from a representative source system, boot the generated medium, reinstall Windows, restore the selected user and application state, and verify bootability, sign-in, installed applications, user data, drivers, and rollback/error handling. Preserve test evidence and logs outside the release artifact.
- [ ] **Introduce a durable workflow contract.** Define a versioned JSON schema for process, job-action, state, result, error, and resume data. Specify IDs, allowed states, timestamps, retry behavior, cancellation semantics, ownership, and backward compatibility. Validate every read/write at the framework boundary.
- [ ] **Make destructive operations safe by default.** Require explicit confirmation and a clearly displayed target summary before formatting, replacing image content, injecting drivers, committing WIM changes, or deleting temporary data. Add a `-WhatIf`/simulation path where technically possible.
- [ ] **Implement reliable cleanup and recovery.** On normal completion, cancellation, and failure, unmount mounted images, stop child processes, release locks, retain actionable logs, and offer a safe resume or cleanup command after interruption/reboot.
- [ ] **Define artifact integrity and provenance.** Produce a manifest for every generated installation medium with component versions, source ISO hashes, WIM index/edition, driver inventory, tool versions, command inputs, output hashes, and build timestamp. Verify hashes before use and before final packaging.

## P1 — Core Workflow Integration

- [ ] **Specify the canonical WinTwin workflow.** Write the authoritative state-machine/workflow document from source-media discovery through ISO preparation, image mount/service/commit, user-state capture, application/tweak integration, bootable-media generation, and post-install restoration. Map each state to its owning component and its success/failure criteria.
- [ ] **Complete the orchestration layer in this repository.** Implement a single entry point that performs preflight checks, creates an isolated working directory, invokes component contracts in dependency order, persists state, surfaces progress, and returns a standardized result object. Do not duplicate component implementation here.
- [ ] **Standardize component integration contracts.** Require each component to expose version, capability discovery, preflight, invoke, cancellation, status, cleanup, and structured-result interfaces. Pin compatible component versions and reject incompatible combinations early.
- [ ] **Finish and validate the installer bootstrap path.** Ensure `wintwin.installer.ps1` installs or locates required dependencies, verifies hashes/signatures, initializes configuration safely, detects previous or partial installations, and supports repair, update, and uninstall without silently overwriting user data.
- [ ] **Separate source, workspace, cache, and output paths.** Use a documented directory model with per-run workspace identifiers, volume/free-space checks, atomic output publishing, and a retention policy. Ensure generated media and large binaries are never unintentionally tracked by Git.
- [ ] **Establish resumable execution.** Persist checkpoints after every externally visible or expensive action and define safe resume boundaries for downloads, image mounting, servicing, USMT capture, ISO creation, and media writing.

## P1 — Image and Migration Quality

- [ ] **Define the supported capture model.** Clearly distinguish what is captured in the WIM/installation medium, what is migrated through USMT, what is reapplied through PS.Tweak.Tools, and what cannot or must not be reproduced. Explicitly document licensing, credentials, device-bound software, BitLocker keys, certificates, browser profiles, cloud-synced data, Store applications, and hardware-specific drivers.
- [ ] **Build the USMT profile policy.** Provide selectable migration profiles, include/exclude rules, conflict behavior, EFS/certificate handling, scanstate/loadstate command construction, detailed logs, and post-restore validation. Use least-privilege and never place secrets in generated logs or media.
- [ ] **Implement driver policy and validation.** Inventory the live system, classify inbox/OEM/third-party drivers, support an explicit include/exclude allowlist, detect architecture and OS-build incompatibility, and verify the injected driver set before WIM commit.
- [ ] **Implement image-servicing validation.** Detect edition/index automatically, validate mount state before servicing, run DISM health checks, record package/driver changes, and prohibit ISO creation when image servicing has unresolved errors.
- [ ] **Define bootable-media build and verification.** Build the ISO/media with a documented toolchain, validate UEFI boot structure, verify the final artifact hash, and run a clean-VM boot/install smoke test before declaring a release-ready build.

## P1 — UX, Diagnostics, and Security

- [ ] **Define the GUI ownership boundary.** Keep WinTwin.XUI responsible for generic WPF/XAML infrastructure and the framework responsible for orchestration views and application-specific controllers. Use thin handlers, cancellable background work, dispatcher-safe updates, structured progress events, and deterministic event deregistration.
- [ ] **Create a unified logging and diagnostic model.** Standardize log locations, correlation/run IDs, severity, redaction rules, console/UI presentation, component log forwarding, and a support-bundle generator that excludes credentials and private user content by default.
- [ ] **Add secure dependency handling.** Maintain a machine-readable dependency manifest with official source URLs, expected versions, SHA-256 values, license notices, signature verification status, and an offline-cache strategy for ADK, WinPE add-on, oscdimg, and bundled binaries.
- [ ] **Implement privilege and trust boundaries.** Elevate only for operations that require it, validate all executable and script paths, avoid `Invoke-Expression`, use argument arrays for external tools, quote paths defensively, and identify the trust model for local XAML/JSON/configuration files.
- [ ] **Run secret and supply-chain checks in CI.** Add secret scanning, dependency/artifact manifest validation, PowerShell static analysis, and license/NOTICE consistency checks to pull requests.

## P2 — Engineering Quality and Delivery

- [ ] **Create automated test tiers.** Add Pester unit tests for core contracts and helpers, component contract tests, integration tests using disposable VHDX/Hyper-V or VM fixtures, and a manual hardware validation matrix. Make release promotion depend on the appropriate test tier.
- [ ] **Establish CI quality gates.** Validate module manifests, parse PowerShell, run PSScriptAnalyzer with a project rule baseline, execute Pester, validate JSON schemas, check Markdown links, and publish test/log artifacts. Keep component sync and framework validation as separate workflows.
- [ ] **Define semantic versioning and compatibility.** Version the framework, component contracts, bundled component snapshots, schemas, and generated media manifest independently. Publish a compatibility matrix and upgrade/migration notes.
- [ ] **Formalize release engineering.** Produce signed or hash-verified release artifacts, release notes generated from curated changelog entries, a reproducible build record, rollback guidance, and a stable/beta channel policy.
- [ ] **Refine repository composition.** Keep the framework repository as orchestrator and integration snapshot; treat synchronized component directories as generated/vendor-like content. Document ownership, synchronization direction, excluded paths, conflict resolution, and the rule that no manual changes occur inside synchronized component trees.
- [ ] **Replace historical task tracking with GitHub Issues.** Create one issue per actionable task, assign priority/component labels and acceptance criteria, use this file only as a concise active roadmap, and link completed work through PRs and CHANGELOG entries.

## Suggested Execution Order

1. Publish the supported baseline and canonical workflow.
2. Stabilize the workflow/state contract and standardized component result model.
3. Implement preflight, destructive-operation safeguards, cleanup, and resumability.
4. Integrate the orchestrator with one minimal end-to-end “golden path.”
5. Validate USMT, servicing, drivers, and bootable-media generation independently.
6. Add the clean-VM recovery acceptance test and artifact provenance manifest.
7. Add CI quality gates, automated test tiers, and release engineering.

## Definition of Done

A task is complete only when its implementation is merged through a pull request, tests and validation evidence are attached or linked, relevant documentation is updated in English, and the CHANGELOG contains a user-relevant entry where appropriate.

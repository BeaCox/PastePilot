# PastePilot Agent Guide

This file is the repository-level source of truth for coding agents. Human-facing
setup and contribution details remain in `CONTRIBUTING.md` and `README.md`.

## Required Commands

- Use `make build` for the normal debug build.
- Use `make test` for tests. Do not call `swift test` directly: the Makefile
  supplies the Swift Testing framework and runtime search paths required by
  both Xcode and Command Line Tools installations.
- To run a focused test while retaining those paths, use, for example:
  `make test SWIFT_TEST_PARALLEL_FLAGS='--no-parallel --filter ProtectedHistoryTests'`.
- Run `make concurrency-check` after changing async code, actors, tasks,
  `Sendable` types, or main-actor boundaries.
- Run `make app` when changing packaging, resources, entitlements, App Intents,
  or release behavior. It produces an architecture-specific app under `dist/`.
- Before handing off any code change, run `git diff --check` plus the checks
  proportional to the change. For ordinary source changes, the expected floor
  is `make test`; include `make concurrency-check` for concurrency-related work.

## Project Shape

- `Sources/PastePilot/App`: application lifecycle, menu bar integration,
  keyboard handling, and window presentation.
- `Sources/PastePilot/Features/Clipboard`: clipboard models, capture,
  coordination, analysis, and actions. `ClipboardStore` is `@MainActor`.
- `Sources/PastePilot/Features/History`: SQLite/GRDB persistence, backups,
  external text/image lifecycle, and protected-history encryption.
- `Sources/PastePilot/Features/MenuBar`: SwiftUI popover, row interaction,
  previews, and search UI.
- `Sources/PastePilot/Features/Settings`: settings models and views.
- `Sources/PastePilot/Features/AppIntents`: Shortcuts/App Intents integration.
- `Sources/PastePilot/Services`: OCR, link metadata, paste shortcuts, and other
  bounded services.
- `Sources/PastePilot/Support`: shared utilities, localization, notices, and
  preview helpers.
- `Tests/PastePilotTests`: Swift Testing suites. Storage tests should use
  temporary directories and injected fakes from `StorageTestSupport.swift`.

## Behavioral and Safety Invariants

- PastePilot is local-first: do not add telemetry, cloud access, or implicit
  network requests. Link metadata fetching must remain explicit opt-in.
- Preserve original clipboard data when safe. Changes involving pasteboard
  representations must keep size/type limits and concealed/transient-type
  filtering intact.
- Protected clipboard payloads must remain encrypted at rest. Locked items must
  not expose plaintext through previews, actions, search indexes, logs, or
  externalized text files.
- Protected-history unlock is the authorization boundary. Once a protected item
  is unlocked, do not layer the separate sensitive-content “Reveal” control on
  top of it. Concurrent unlock requests must share one system authentication.
- Sensitive-content masking applies to unprotected history and must continue to
  honor built-in and user-defined patterns.
- Keep expensive image, OCR, persistence, and enrichment work off the main
  actor; publish observable UI state on the main actor.
- Preserve cancellation and stale-result guards on asynchronous capture,
  enrichment, image, and text work.

## Tests and User-Facing Changes

- Use Swift Testing (`import Testing`, `@Suite`, `@Test`, `#expect`) rather than
  adding XCTest-based tests.
- Add regression coverage for bug fixes at the lowest stable layer; add storage
  or menu-bar regression coverage when behavior spans those boundaries.
- New user-facing strings must use `.localized` and receive a Simplified Chinese
  entry in `Sources/PastePilot/Resources/zh-Hans.lproj/Localizable.strings`.
  `LocalizationTests` verifies coverage.
- Follow the existing dependency-injection seams instead of accessing global
  services from tests.
- Do not edit generated output under `.build/` or `dist/`.

## Scope and Style

- Keep changes focused and preserve unrelated work in a dirty worktree.
- Prefer the existing SwiftUI/AppKit split and existing service/repository
  abstractions over introducing new dependencies.
- Update `README.md`, `CONTRIBUTING.md`, `CHANGELOG.md`, or `TODO.md` only when
  the user-visible behavior or contributor workflow actually changes.

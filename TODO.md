# PastePilot Roadmap

This roadmap lists the next meaningful product and maintenance work. It is
ordered by priority rather than by a promised release date. Completed release
history belongs in `CHANGELOG.md` instead of accumulating here.

## Product Principles

- Stay local-first: no telemetry, cloud dependency, or implicit network access.
  Link metadata remains explicit opt-in.
- Keep protected clipboard payloads encrypted at rest and unavailable to
  previews, actions, search indexes, logs, and external text files while locked.
- Preserve useful pasteboard representations only within strict type and size
  limits, and continue to ignore concealed or transient clipboard data before
  capture.
- Keep capture, persistence, image processing, OCR, and enrichment work off the
  main actor while preserving cancellation and stale-result guards.
- Extend bounded declarative actions instead of loading executable plugins.

## Current Baseline

- Content-aware capture and actions for developer text, structured data, rich
  text, images, and files, with high-fidelity replay when safe.
- SQLite/FTS history with externalized large text, image storage, OCR, source
  application metadata, filters, pinned items, titles, notes, and tags.
- Local privacy controls including pause/ignore-next-copy, sensitive-content
  policies, custom patterns, encrypted protected history, and backup/restore.
- A declarative action registry, safe template actions, local JSON action
  plugins, App Intents, and the `pastepilot` command-line tool.
- The largest remaining product gap is organization beyond recency, pinned
  state, and free-form searchable metadata.

## Now — Finish and Ship Local Action Plugins

- [x] Add a bundled example plugin and a machine-readable JSON Schema for the
  version 1 manifest. Make both easy to reveal from the Actions settings page.
- [x] Improve plugin validation errors so they identify the invalid field or
  referenced content type, while keeping file, matcher, and action limits
  enforced.
- [x] Add regression coverage that exercises plugin actions through the menu
  bar action list and App Intents, not only the manifest loader.
- [x] Complete release QA for the plugin feature: run `make app`, verify plugin
  discovery/reload in the packaged app, and prepare the next version notes.

## Next — Organize Reusable History

- [x] Add tags to clipboard items.
  - Persist normalized tags separately from captured content and keep them when
    duplicate content moves to the top.
  - Add tag editing and compact tag indicators without making history rows
    visually noisy.
  - Support `tag:<name>` and `has:tag` in app and CLI search, including backup
    and restore coverage.
  - Treat tags on protected items as user-authored visible metadata, matching
    titles and notes, and document that boundary in the UI.
- [x] Add saved searches as local smart collections.
  - Store a name and existing search query instead of duplicating clipboard
    payloads.
  - Provide built-in views for recent, pinned, protected, images, and files,
    plus user-created saved searches.
  - Keep collection membership deterministic across restarts and after history
    cleanup.
- [x] Make pinned items intentionally reusable.
  - Allow manual ordering within the pinned section.
  - Keep `Command-1` through `Command-9` stable for pinned items when search is
    empty, while preserving the current visible-result behavior during search.
  - Persist ordering and cover duplicate recapture, deletion, and restore.

## Later — Workflow Polish

- [x] Add plugin management controls for enabling, disabling, importing, and
  exporting individual declarative plugins without editing Application Support
  manually.
- [x] Let users export selected history items in useful local formats such as
  plain text, JSON, original files, or images without turning export into an
  automatic sharing or network feature.
- [x] Audit keyboard and VoiceOver behavior across the menu bar, previews,
  metadata editing, protected-history authentication, and settings; add focused
  regression coverage for discovered gaps.

## Maintenance

- [x] Split `AppSettings` persistence, validation, and plugin catalog state into
  focused components while retaining its existing dependency-injection seams.
- [x] Split `SQLiteHistoryStore` migrations, row encoding, FTS indexing, and
  metadata access into focused files without changing the storage schema or
  transaction boundaries.
- [x] Add representative performance fixtures for startup, filtered search,
  externalized text search, and cleanup at the supported history limits.

## Completed Milestones

The project already includes signed release packaging, automatic update checks,
high-fidelity pasteboard replay, sensitive-content policies, encrypted protected
history, backup/restore, advanced search, metadata editing, OCR and local barcode
analysis, perceptual image deduplication, paste stack, App Intents, CLI
automation, safe custom actions, and declarative local action plugins. See
`CHANGELOG.md` for versioned details.

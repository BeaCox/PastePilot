# Changelog

All notable changes to PastePilot are documented in this file.

## [0.2.0] - 2026-06-08

### Added

- Configurable global paste-as-plain-text shortcut, defaulting to `⌥⇧⌘V`.
- Safe clipboard restoration after plain-text paste, without overwriting
  clipboard changes made by another app during the operation.
- Standard SwiftPM test target using Swift Testing, including storage and
  pasteboard lifecycle coverage.

### Changed

- Split versioned history persistence, cached image management, and OCR into
  dedicated services that can be injected in tests.

### Fixed

- Added recovery from the last valid history backup.
- Prevented unreadable history files from triggering destructive orphan-image
  cleanup.
- Moved the sensitive-content indicator to the leading type badge and added an
  explicit reveal control in the hover preview.

## [0.1.1] - 2026-06-08

### Fixed

- Hover previews now choose the side with enough screen space and anchor to the
  active clipboard item, improving the common left-opening layout when the menu
  bar icon is near the right edge of the screen.
- Preview popover sizing is more stable, and OCR text is no longer duplicated
  in the detail panel.

## [0.1.0] - 2026-06-08

### Added

- Menu bar clipboard history with search, pinning, keyboard navigation, hover
  previews, drag and drop, and configurable global shortcut.
- Smart recognition and developer actions for commands, JSON, URLs, code,
  errors, colors, Markdown, rich text, images, files, and plain text.
- Rich text preservation, image previews, Vision-powered OCR, Quick Look, and
  per-app clipboard ignore rules.
- Local history limits, automatic expiry, launch at login, sensitive-content
  masking, and English and Simplified Chinese localization.
- Architecture-specific Apple Silicon and Intel app bundles and DMGs.
- GitHub Actions for builds, tests, release packaging, checksums, and automated
  GitHub Releases.
- Sparkle-powered automatic updates with signed architecture-specific appcasts
  and a manual **Check for Updates…** action.

### Changed

- Bundle identifier changed to `space.beacox.PastePilot`.
- Menu bar popover and settings interface redesigned for adaptive sizing and
  clearer clipboard metadata.

### Security

- Clipboard history remains local and no telemetry is collected.
- Update archives are verified with a dedicated Ed25519 signing key.

# Changelog

All notable changes to PastePilot are documented in this file.

## [0.3.0] - 2026-06-09

### Changed

- Expanded menu bar keyboard control with search focus, action shortcuts,
  clear-unpinned cleanup, popover close handling, and visible action shortcut
  hints in previews.
- Added URL/file-aware image actions, including Copy Image URL for web images
  and Copy File, Quick Look, and Show in Finder for local or cached image files.
- Documented the full menu bar keyboard shortcut set for release users.

### Fixed

- Keep Return/Enter consistent with the documented copy behavior, including URL
  items whose first suggested action opens the browser.

## [0.2.3] - 2026-06-09

### Changed

- Split global shortcut configuration and Accessibility permission guidance
  into separate Settings cards.
- Add concise steps for removing the old PastePilot permission entry after an
  unsigned update.

## [0.2.2] - 2026-06-09

### Fixed

- Use the Quartz event-posting permission API for plain-text paste instead of
  the broader Accessibility API, fixing false "permission not granted" status
  on newer macOS versions.
- Open Accessibility settings when macOS no longer presents the initial
  event-posting permission prompt.
- Group both global shortcuts with one shared permission status, and explain
  that only paste-as-plain-text requires Accessibility access.
- Remind users once after an unsigned app update when Accessibility permission
  must be granted again, including guidance to close old DMGs.

## [0.2.1] - 2026-06-08

### Fixed

- Moved the sensitive-content indicator to the leading type badge and added an
  explicit reveal control in the hover preview.
- Stopped repeatedly requesting Accessibility permission from the plain-text
  paste shortcut and added live permission status in Settings.
- Added guidance for refreshing Accessibility permission after replacing an
  ad-hoc signed build.

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

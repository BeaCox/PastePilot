# Changelog

All notable changes to PastePilot are documented in this file.

## [Unreleased]

## [0.10.2] - 2026-07-23

### Added

- A local `pastepilot` command can search and read history, copy items, export a
  live SQLite backup, and report storage diagnostics. Search accepts the same
  common filters as the app, JSON output is available for automation, and
  protected content remains behind the app's authentication boundary.

### Changed

- History rows now keep a visible preview arrow, and their context menu groups
  copy, preview, paste-stack, pin, metadata, protection, and delete actions in
  one place.

### Fixed

- Copying a locked protected item now continues automatically after successful
  authentication instead of requiring the user to repeat the copy action.

## [0.10.1] - 2026-07-21

### Added

- Unlocked protected rows now expose a direct lock button and a matching
  context-menu action, so protected history can be locked immediately.

### Fixed

- Protected-history unlock now reuses the successful system-authentication
  context for the Keychain read, avoiding a second authentication flow after
  Touch ID or the login password succeeds.

## [0.10.0] - 2026-07-20

### Added

- Deleting a history item shows an "Undo" toast for a few seconds before its
  content and image files are actually removed, instead of deleting instantly
  and permanently.
- A filter menu next to the search field inserts `kind:`, `pinned:`, and
  `has:` search query tokens without needing to type the syntax.
- The history list can show a small badge of the source app's icon on each
  row, on by default with a toggle in Preferences.
- Paste stack items can be reordered by dragging in a new "Reorder…" sheet.

### Changed

- Moving an item into protected storage now encrypts it and immediately returns
  protected history to the locked state. Protected history also locks when the
  Mac sleeps or the login session becomes inactive.
- Protected items now keep their user-authored title, note, and aliases visible,
  editable, and searchable while locked, so otherwise concealed records remain
  distinguishable. Clipboard content and derived content metadata stay encrypted.
- Clicking a locked history row now starts authentication, matching the existing
  keyboard behavior.
- The menu bar icon now switches to a paused icon while clipboard capture is
  disabled, instead of giving no visual indication that capture is off.

### Fixed

- Protected-item writes are now committed synchronously before plaintext cleanup
  and locking, and unchanged protected payloads use stable fingerprints instead
  of being rewritten because of randomized encryption output.
- A notice banner shown while the panel was closed (for example, after pausing
  capture with Option-click) no longer lingers and flashes the next time the
  panel opens.

## [0.9.0] - 2026-07-20

### Added

- Clipboard items can be queued into a paste stack and pasted into the active
  app in queue order, with progress, cancellation, a 50-item limit, and
  configurable newline, space, tab, comma, or custom separators.
- Selected text-based history items can be moved into AES-GCM encrypted
  protected storage. The encryption key is kept in the macOS Keychain,
  unlocking uses system authentication, and records lock again after a
  configurable timeout.
- Locked protected items expose neither their clipboard content nor derived
  content metadata to previews, clipboard actions, search, or plaintext external
  storage. User-authored labels are intentionally visible for identification.

### Changed

- The clipboard metadata editor now matches the menu bar panel's visual
  language, including content-kind context, source information, grouped fields,
  and a distinct action footer.

### Maintenance

- Added coverage for paste stack ordering, separators, cancellation, limits,
  protected-history encryption, locked-state behavior, persistence, and
  settings validation.

## [0.8.0] - 2026-07-19

### Added

- PastePilot now exposes Shortcuts actions to get the selected history item,
  get an item by one-based index, copy or delete an item, clear unpinned
  history, and run a named PastePilot action.
- Shortcuts can choose from PastePilot's built-in actions and enabled safe
  custom template actions. Item displays respect sensitive-content masking,
  including user-defined patterns.
- Image history can optionally use perceptual hashing to merge visually similar
  images that have different encodings.
- Images can be scanned locally for QR codes and common barcodes, with detected
  payloads available in search and copy actions.
- Link title and description metadata can be fetched for newly copied HTTP(S)
  links after explicit opt-in; credential-bearing and non-web URLs are skipped.
- Users can create bounded local template actions for text and image metadata
  without granting shell, network, or file-execution access.

### Changed

- Release app bundles built with full Xcode now include extracted App Intents
  metadata so PastePilot actions are discoverable in Shortcuts.

### Maintenance

- Added App Intents coverage for selected-item lookup, action catalog contents,
  and item-specific action availability.

## [0.7.0] - 2026-07-13

### Added

- Backup and restore can export `history.sqlite`, image files, and externalized
  text into a versioned archive, validate restore input, and create a
  pre-restore backup before replacing local data.
- Capture controls now include persistent pause and one-shot **Ignore Next
  Copy** support for sensitive workflows.
- Search supports filters such as `kind:json`, `app:Terminal`, `pinned:true`,
  and `has:ocr`, with quoted phrases and source app fields included in the
  SQLite search body.
- Users can define custom sensitive-content patterns and choose whether matches
  are stored as original text, stored redacted, or skipped.
- Optional copy-and-paste behavior can paste a copied history item after
  Accessibility permission is granted.
- Original pasteboard representations are preserved for supported clipboard
  types so rich text, file groups, images, and app-specific formats can be
  replayed with higher fidelity.
- Clipboard items can now have editable titles, notes, and aliases that are
  persisted separately from captured content, indexed in search, shown in
  previews, and retained when duplicate content moves to the top.

### Changed

- Built-in clipboard actions now flow through a declarative registry with
  stable ids, titles, symbols, accepted kinds, effects, and preview close
  behavior.
- Content detection now reports confidence, reasons, and secondary traits such
  as YAML, XML, SQL, JWT, Base64, email, UUID, source code, and natural
  language.
- Menu bar search and paste feedback were refined so filtered results,
  full-text matches, notices, and inline previews stay responsive and stable.
- History search and SQLite lifecycle handling were hardened, including
  rebuilding missing search index entries and keeping storage scans bounded.

### Fixed

- Quoted secret redaction now preserves surrounding syntax while masking the
  sensitive value.
- Paste shortcut tests were stabilized to avoid timing-sensitive failures.

### Maintenance

- Added menu bar popover regression coverage for search, preview, pin/delete,
  actions, notices, empty states, and long-content layout.
- Split SQLite history storage, menu interaction state, and related tests into
  narrower units.

## [0.6.0] - 2026-07-01

### Changed

- Clipboard history now uses SQLite (`history.sqlite`) with WAL and FTS5
  trigram search for faster persistence and full-text lookup.
- Existing `history.json` and `history.backup.json` files are imported
  automatically on first launch and left on disk for downgrade safety.
- Large text and images continue to use external `text/` and `images/` files
  instead of being forced into the database.
- Search now uses the SQLite index first, including externalized large text,
  and keeps the previous file-scan path as a runtime fallback.
- Local storage totals now include SQLite database, WAL, SHM, retained legacy
  JSON, text files, and image files.
- Downgrading to a pre-0.6.0 build will only show history already present in
  the retained JSON files; history added in 0.6.0 is SQLite-only.
- CI now runs the Swift concurrency check alongside the regular test suite.
- Local app builds now read their default version from the repository `VERSION`
  file instead of a hard-coded shell script value.
- Detail previews now cache source application icons and parsed rich text to
  avoid repeated AppKit lookups while hovering through history.
- Storage tests are split into narrower suites by persistence, capture, and OCR
  behavior.
- URL detection now only treats supported URL schemes as links, avoiding
  accidental matches for colon-prefixed text.
- Sensitive-content redaction now preserves field names and authentication
  prefixes while masking secret values, with broader coverage for bearer
  tokens, JWTs, and private keys.

### Fixed

- JSON-to-TypeScript generation now remains plain string output after adding
  GRDB's SQL string interpolation support to the app target.

## [0.5.1] - 2026-06-22

### Changed

- Large plain-text clipboard items are now stored outside `history.json` while
  keeping a bounded preview snippet in history for fast startup and list
  rendering.
- Text previews now use a TextKit-backed view with incremental "show more"
  loading, avoiding SwiftUI text layout stalls on long clipboard entries.
- Search now keeps the list responsive by matching the in-history preview first
  and scanning externalized full text asynchronously.
- History rows load cached image thumbnails instead of decoding original images
  for every list render.
- Startup work was reduced by lazily creating the popover and avoiding an
  immediate clipboard capture on app launch.

### Fixed

- Reduced memory pressure and UI stalls when copying, searching, or previewing
  multi-thousand-character text.
- Deleting or replacing clipboard items now also cleans up externalized text
  files.

## [0.5.0] - 2026-06-19

### Added

- The update prompt now shows this version's release notes, generated from the
  matching CHANGELOG section and embedded into the signed appcast.
- Image OCR can now be configured from Settings with Off, Fast, and Accurate
  recognition modes plus System Language, English-only, and multilingual
  language choices.
- The menu bar panel now surfaces recoverable operational problems, including
  history save failures, image save failures, image size-limit skips, and
  global shortcut registration conflicts.

### Changed

- Clipboard capture now snapshots pasteboard contents off the main actor before
  applying them, keeping the app responsive and avoiding hangs when remote copy
  providers fail.
- History writes are coalesced before saving so rapid clipboard changes avoid
  unnecessary disk churn.

### Fixed

- Prevented clipboard capture from hanging when remote pasteboard data cannot
  be loaded.
- Invalid persisted shortcut, storage, appearance, and OCR settings now fall
  back to supported defaults.
- Static regex setup no longer uses force-try, so future regex mistakes cannot
  crash the app at launch.

### Maintenance

- Simplified content analysis by deriving the content kind once and computing
  the sensitive-data range a single time per scan.
- Added localization coverage checks and expanded storage, OCR, settings, and
  clipboard-capture tests.

## [0.4.0] - 2026-06-15

### Added

- Drag and drop files onto the menu bar icon to import them directly into
  clipboard history, even when the panel is closed.
- **After Copying** preference to choose what happens once you copy or transform
  an item: keep the panel open, close the preview, or close the whole panel.
- **Animate Preview** preference to fade the detail preview in and out.

### Changed

- Dismiss the panel and any open detail preview automatically when focus moves
  to another app.
- Redesigned Settings with grouped cards and a window that sizes itself to fit
  each page's content instead of using fixed per-tab heights.
- Consolidated the data folder shortcut on the Advanced tab and removed the
  duplicate entry from the Storage tab.

### Fixed

- **Close Panel** after copying now actually closes the panel instead of only
  the preview.
- The detail preview now vanishes together with the panel rather than animating
  out as a separate, trailing step.

### Maintenance

- Reorganized the source tree into feature-focused folders (App, Features,
  Services, Support).
- Improved type inference and expanded test coverage for content transforms and
  plain-text pasting.

## [0.3.1] - 2026-06-12

### Changed

- Moved clipboard history persistence and image encoding off the main actor to
  keep the menu bar interface responsive during larger saves and image copies.
- Improved the README with clearer positioning, developer workflow examples,
  and comparisons with other clipboard managers.

### Fixed

- Close PastePilot's inline preview before opening Quick Look, avoiding
  overlapping preview windows.
- Corrected the PastePilot menu bar icon and Settings picker preview sizes.

### Maintenance

- Split the Settings and menu bar views into focused source files.
- Added coverage for queued history writes, background image processing,
  Quick Look preview behavior, and menu bar icon sizing.
- Made `make test` work with Command Line Tools by preparing and re-signing the
  generated SwiftPM test bundle before execution.

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

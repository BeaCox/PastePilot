<div align="center">

# PastePilot

<img src="README-assets/AppIconSource.png" width="128" />

[![CI](https://github.com/BeaCox/PastePilot/actions/workflows/ci.yml/badge.svg)](https://github.com/BeaCox/PastePilot/actions/workflows/ci.yml)

A local-first macOS clipboard manager that understands developer content.

PastePilot recognizes commands, JSON, code, errors, colors, screenshots, and
files, then suggests the next useful action from your menu bar. No plugins, no
telemetry, no cloud sync. Everything stays on your Mac.

[Download latest release](https://github.com/BeaCox/PastePilot/releases/latest) ·
[See demo](#demo) ·
[Build from source](#quick-start)

</div>

## Why PastePilot?

Most clipboard managers remember what you copied. PastePilot understands what
you copied and turns it into useful developer actions.

- **Clean commands before they hit your terminal.** Strip `$`, `%`, `❯`,
  virtualenv prompts, and terminal transcript noise.
- **Work with structured data faster.** Pretty-print JSON, minify it, or
  generate TypeScript interfaces from API responses.
- **Find screenshots by text.** OCR copied images locally with macOS Vision,
  then search clipboard history by visible text.
- **Keep clipboard data local.** No plugins, no telemetry, and no cloud sync.

## Demo

![PastePilot menu bar popover demo](README-assets/pastepilot-demo.gif)

## How It Compares

| Tool | Main focus | Where PastePilot differs |
|------|------------|--------------------------|
| **PastePilot** | Developer clipboard history with smart local actions | Recognizes commands, JSON, code, errors, colors, Markdown, rich text, images, and files; includes OCR search and sensitive-content masking |
| **Maccy** | Fast, minimal clipboard history | PastePilot adds content-aware transforms and developer workflows on top of clipboard history |
| **Raycast Clipboard** | Clipboard history inside a broader launcher | PastePilot is a standalone menu bar app focused on copied developer content and local-first behavior |
| **Paste / cloud clipboard apps** | Polished history, organization, and sync workflows | PastePilot prioritizes open source code, local storage, no telemetry, and no cloud dependency |

## Features

### Smart Content Recognition

PastePilot automatically identifies 11 content types and tailors actions to each:

| Type | Examples | Actions |
|------|----------|---------|
| **Command** | `$ npm install`, `git status`, `sudo apt install` | Strip prompt (`$` / `%` / `❯`), extract from terminal output, wrap in code block |
| **JSON** | API responses, config files | Format (pretty-print), minify, generate TypeScript interfaces |
| **URL** | `https://...` | Open in browser, copy |
| **Code** | Functions, snippets | Escape for string embedding, wrap in Markdown code block |
| **Error** | Stack traces, crash logs | Clean up for issues/chat, extract embedded commands |
| **Color** | `#FF5733`, `rgb(...)`, `hsl(...)` | Normalize hex format |
| **Markdown** | Headings, lists, links | Name conversion, string escape |
| **Rich Text** | Formatted text from web/editors | Preserve formatting, copy as plain text, copy HTML source |
| **Image** | Screenshots, copied images | Copy as image data, source URL, or file; copy Markdown with URL/path fallback; Quick Look, Show in Finder, OCR text search |
| **File** | Files from Finder | Copy, Quick Look, Show in Finder |
| **Plain Text** | Everything else | Convert to `camelCase` / `snake_case`, escape as string |

### Command Intelligence

Built for the pain of copying `$ npm install` from a README and having to delete the `$` yourself:

- Recognizes 100+ command-line tools (`git`, `docker`, `kubectl`, `terraform`, `aws`, `brew`, ...)
- Strips prompt prefixes (`$`, `%`, `❯`, `➜`, `user@host$`, `(venv) $`)
- Extracts runnable commands from terminal transcripts mixed with output
- Handles multi-line commands with `\` continuation
- Parses commands inside fenced code blocks (` ```sh `, ` ```bash `, ` ```console `)

### Image OCR

Copied images are automatically scanned for text using the macOS Vision framework. Recognized text is searchable in history — find a screenshot by typing any word visible in it. Supports Chinese (simplified/traditional), English, Japanese, and Korean.

### Paste as Plain Text

Press the configurable global shortcut (default: `⌥⇧⌘V`) to paste the current
clipboard text without fonts, colors, links, or other rich-text formatting.
PastePilot restores the original clipboard contents immediately afterward, so
images, files, and rich text remain available for normal pasting.

Both global shortcuts are managed together in General settings. Opening
PastePilot does not require Accessibility permission; pasting as plain text
does, because it sends a paste keystroke to the active app. Click **Request
Permission** to authorize it. Ad-hoc signed builds may need permission again
after an update, so close old DMGs and keep only the installed copy in
`/Applications`.

### Privacy & Security

- Detects and masks API keys, tokens, passwords, and private keys
- Sensitive content hidden by default with optional reveal
- Clipboard data stays local and no telemetry is collected
- Network access is limited to checking and downloading updates from GitHub Releases
- History is stored as versioned plain JSON at `~/Library/Application Support/PastePilot/history.json`
- The last valid history file is retained as `history.backup.json` for recovery
- Copied images are stored as PNG files under `~/Library/Application Support/PastePilot/images/`
- Rich text, OCR results, source app metadata, and detected sensitive content may be persisted in history
- Sensitive-content masking only hides values in the UI; it does not encrypt data at rest
- Clear history from PastePilot or delete its Application Support folder to remove stored clipboard data

### Menu Bar Interface

- **Hover preview** — pause on any item to see full content, source app, and metadata
- **Keyboard-driven** — search, navigation, previews, item actions, pinning,
  deletion, and cleanup all have keyboard paths
- **Search** — filter history by content, type, or OCR text
- **Pin** — pinned items stay at the top and survive cleanup
- **Drag & drop** — drop files or images directly into the popover

#### Keyboard shortcuts

| Shortcut | Action |
|----------|--------|
| `↑` / `↓` | Move the selected history item |
| `↩` | Copy the selected item |
| `␣` | Open or close the selected item's preview |
| `⌘1`–`⌘9` | Copy the corresponding visible history item |
| `⌥1`–`⌥9` | Run an action for the selected item, matching the preview action list |
| `⌘P` | Pin or unpin the selected item |
| `⌘⌫` | Delete the selected item |
| `⌘⇧⌫` | Clear unpinned history after confirmation |
| `⌘F` / `⌘K` | Focus search |
| `Esc` | Close preview, clear search, then close the popover |

### Preferences

- Launch at login
- Configurable shortcuts for opening PastePilot and pasting as plain text
- History limit (50 / 100 / 200 / 500 items)
- Auto-delete timeout (never / 1 hour / 24 hours / 7 days / 30 days)
- Image size limit
- Menu bar icon style (PastePilot / Clipboard / Paperplane)
- Hover preview toggle
- Per-app ignore list with visual app picker
- Automatic update checks with a manual **Check for Updates…** action
- Reset to defaults

### Internationalization

English and Simplified Chinese. Follows system language automatically.

## Requirements

- macOS 14.0 (Sonoma) or later
- Apple Silicon (`arm64`) or Intel (`x86_64`) Mac
- Accessibility permission (for pasting as plain text into other apps)

## Quick Start

```sh
git clone https://github.com/BeaCox/PastePilot.git
cd PastePilot
make run
```

The app appears in the menu bar. Copy anything to get started.

## Build

PastePilot uses Swift Package Manager and ships architecture-specific builds
for Apple Silicon (`arm64`) and Intel (`x86_64`). The Makefile wraps all build
steps:

| Command | Description |
|---------|-------------|
| `make build` | Compile the debug executable with SwiftPM |
| `make run` | Build and launch PastePilot |
| `make app` | Build a release `.app` bundle into `dist/` (ad-hoc signed) |
| `make dmg` | Build a compressed DMG with an `Applications` shortcut |
| `make test` | Run the standard SwiftPM test suite |

Use `make test` instead of calling `swift test` directly. The Makefile passes
the Swift Testing flags and framework/runtime search paths needed by local
Xcode and Command Line Tools setups.

`make dmg` uses pinned `dmgbuild` tooling, installed into `.build/`, to create
the branded Finder layout without depending on the build machine's Finder
preferences.

### App bundle

```sh
make app
open "dist/PastePilot-$(uname -m).app"
```

### DMG

```sh
make dmg
# Output: dist/PastePilot-<version>-<arch>.dmg
```

### Environment variables

| Variable | Default | Description |
|----------|---------|-------------|
| `ARCH` | Host architecture | Target architecture (`arm64` or `x86_64`) |
| `VERSION` | `0.5.1` | CFBundleShortVersionString |
| `BUILD_NUMBER` | `1` | CFBundleVersion |
| `SIGN_IDENTITY` | `-` (ad-hoc) | Code signing identity |
| `NOTARY_PROFILE` | *(empty)* | Keychain profile for notarization |

### Code signing and notarization

The default build uses ad-hoc signing and is intended for local development.

> PastePilot is not currently signed or notarized because the maintainer does
> not yet have an Apple Developer Program account. macOS may therefore warn or
> block the app when it is downloaded by another user. Donations toward the
> annual membership fee would make signed and notarized releases possible.

To open an unsigned release, move PastePilot to `Applications`, Control-click
the app, choose **Open**, then confirm **Open**. If macOS still blocks it, use
**System Settings → Privacy & Security → Open Anyway**.

To produce a signed release DMG:

```sh
SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" \
VERSION=0.5.1 BUILD_NUMBER=1 make dmg
```

To also notarize and staple:

```sh
# Save credentials once
xcrun notarytool store-credentials "PastePilot-notary"

# Build, sign, notarize, and staple
SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" \
NOTARY_PROFILE="PastePilot-notary" \
VERSION=0.5.1 BUILD_NUMBER=1 make dmg
```

### Automatic updates

Sparkle checks the architecture-specific appcast attached to the latest GitHub
Release. Update archives and appcasts are signed with a dedicated Ed25519 key;
the private key is stored in the maintainer's keychain and the
`SPARKLE_PRIVATE_KEY` GitHub Actions secret.

## Release

Push a semver tag to trigger CI, which builds both architectures, generates
signed appcasts, and publishes a GitHub Release with DMGs and SHA-256
checksums:

```sh
git tag v0.5.1
git push origin v0.5.1
```

## Test

```sh
make test
```

Tests use Swift Testing through a standard SwiftPM test target. The suite covers
content analysis and transforms, action generation, settings persistence,
history format compatibility and backup recovery, image cleanup, expiry, and
history limits.

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for development setup, project structure, and pull request guidelines.

## Changelog

See [CHANGELOG.md](CHANGELOG.md) for release history.

## License

[MIT](LICENSE)

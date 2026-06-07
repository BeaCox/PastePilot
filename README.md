<div align="center">

# PastePilot

<img src="README-assets/AppIconSource.png" width="128" />

[![CI](https://github.com/BeaCox/PastePilot/actions/workflows/ci.yml/badge.svg)](https://github.com/BeaCox/PastePilot/actions/workflows/ci.yml)

A lightweight macOS clipboard manager built for developers. PastePilot recognizes what you copied and suggests the next useful action — no plugins, no cloud, everything stays on your Mac.

</div>

## Demo

![PastePilot menu bar popover demo](README-assets/pastepilot-demo.gif)

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
| **Image** | Screenshots, copied images | Preview, copy Markdown with web URL or file path, OCR text search |
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

### Privacy & Security

- Detects and masks API keys, tokens, passwords, and private keys
- Sensitive content hidden by default with optional reveal
- Clipboard data stays local and no telemetry is collected
- Network access is limited to checking and downloading updates from GitHub Releases
- History is stored as plain JSON at `~/Library/Application Support/PastePilot/history.json`
- Copied images are stored as PNG files under `~/Library/Application Support/PastePilot/images/`
- Rich text, OCR results, source app metadata, and detected sensitive content may be persisted in history
- Sensitive-content masking only hides values in the UI; it does not encrypt data at rest
- Clear history from PastePilot or delete its Application Support folder to remove stored clipboard data

### Menu Bar Interface

- **Hover preview** — pause on any item to see full content, source app, and metadata
- **Keyboard-driven** — `↩` copy, `␣` preview, `⌘P` pin, `⌘⌫` delete, `⌘1`–`⌘9` quick copy
- **Search** — filter history by content, type, or OCR text
- **Pin** — pinned items stay at the top and survive cleanup
- **Drag & drop** — drop files or images directly into the popover

### Preferences

- Launch at login
- Configurable global shortcut
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
- Accessibility permission (for the global shortcut)

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
| `make test` | Run the core check suite |

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
| `VERSION` | `0.1.0` | CFBundleShortVersionString |
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
VERSION=0.1.0 BUILD_NUMBER=1 make dmg
```

To also notarize and staple:

```sh
# Save credentials once
xcrun notarytool store-credentials "PastePilot-notary"

# Build, sign, notarize, and staple
SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" \
NOTARY_PROFILE="PastePilot-notary" \
VERSION=0.1.0 BUILD_NUMBER=1 make dmg
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
git tag v0.1.0
git push origin v0.1.0
```

## Test

```sh
make test
```

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for development setup, project structure, and pull request guidelines.

## Changelog

See [CHANGELOG.md](CHANGELOG.md) for release history.

## License

[MIT](LICENSE)

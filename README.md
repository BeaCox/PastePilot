# PastePilot

A lightweight macOS clipboard manager built for developers. PastePilot recognizes what you copied and suggests the next useful action — no plugins, no cloud, everything stays on your Mac.

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
- All data stored locally — no network access, no telemetry
- History stored at `~/Library/Application Support/PastePilot/`

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
- Reset to defaults

### Internationalization

English and Simplified Chinese. Follows system language automatically.

## Requirements

- macOS 14.0 (Sonoma) or later
- Accessibility permission (for the global shortcut)

## Quick Start

```sh
git clone https://github.com/BeaCox/PastePilot.git
cd PastePilot
swift run PastePilot
```

The app appears in the menu bar. Copy anything to get started.

## Build

Create a standalone `.app` bundle (ad-hoc signed):

```sh
make app
open dist/PastePilot.app
```

## Test

```sh
make test
```

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for development setup, project structure, and pull request guidelines.

## License

[MIT](LICENSE)

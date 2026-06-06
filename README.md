# PastePilot

A developer-focused macOS clipboard assistant. PastePilot recognizes clipboard
content and offers the next useful action instead of only keeping history.

## Current MVP

- Detects JSON, URLs, colors, commands, errors, Markdown, code, and plain text
- Captures screenshots, bitmap clipboard content, and image files copied from Finder
- Shows image thumbnails, dimensions, file size, source app, and hover previews
- Copies images as Markdown using the original web URL or local file path
- Preserves web image URLs and Finder file paths, with cache paths as a fallback
- Formats and minifies JSON, or converts it to a TypeScript declaration
- Converts text to `camelCase` or `snake_case`, and escapes strings
- Detects and masks common API keys, tokens, passwords, and private keys
- Supports search, pinning, deletion, and local history persistence
- Pinned items always appear in a dedicated top section and survive automatic cleanup
- Maccy-style tabbed Preferences control launch at login, monitoring, storage,
  appearance, ignored apps, custom global shortcut, and advanced cleanup
- Includes native Preferences and About windows from the menu bar popover
- Click the menu bar clipboard icon for the latest content and quick actions
- Configure a global shortcut to open or hide clipboard history
- Press `Command + 1` through `Command + 9` to copy visible Popover records

## How it works

1. Copy developer content such as JSON, a URL, command, error, or code.
2. Click the PastePilot icon or use the configurable global shortcut.
3. Search recent history, use arrow keys to select, and press Return to reuse an item.
4. Click a history row to reveal its relevant developer actions.
5. Open the full manager only when you need detailed previews or bulk cleanup.

Actions copy their processed result back to the clipboard. PastePilot never
executes terminal commands automatically, and sensitive values are hidden by
default.

## Run

```sh
swift run PastePilot
```

The app stays in the macOS menu bar. Clipboard history is stored locally at:

```text
~/Library/Application Support/PastePilot/history.json
```

To create a double-clickable, ad-hoc signed app:

```sh
make app
open dist/PastePilot.app
```

## Test

```sh
make test
```

The standalone core checks are used because the Command Line Tools-only Swift
installation does not ship the XCTest or Testing modules.

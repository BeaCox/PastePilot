# Contributing to PastePilot

Thanks for your interest in contributing! PastePilot is a macOS clipboard manager for developers, and we welcome bug reports, feature suggestions, and pull requests.

## Requirements

- macOS 14+
- Swift 6.0+ toolchain (Swift 5 language mode)
- Xcode 16+ or the Swift command-line tools

## Getting Started

```bash
git clone https://github.com/BeaCox/PastePilot.git
cd PastePilot
make build
make run
```

## Project Structure

```
Sources/PastePilot/
  AppDelegate.swift          # Menu bar, popover, hotkey, window management
  PastePilotView.swift       # Main SwiftUI views (menu bar + full history)
  SettingsView.swift         # Preferences window
  ClipboardStore.swift       # Clipboard monitoring and history coordination
  HistoryRepository.swift    # SQLite history persistence and legacy JSON import
  ClipboardImageStore.swift  # Cached image file lifecycle
  OCRService.swift           # Vision-powered text recognition
  PlainTextPasteService.swift # Temporary plain-text paste and restoration
  ClipboardItem.swift        # Data model
  ContentAnalyzer.swift      # Content type detection (command, JSON, URL, …)
  ContentTransformer.swift   # Text transforms (naming, escaping, extraction)
  ClipboardAction.swift      # Action definitions per content type
  AppIconRenderer.swift      # App icon and menu bar icon rendering
  AppSettings.swift          # User preferences (UserDefaults)
  Resources/                 # Localization strings
Tests/PastePilotTests/
  ContentBehaviorTests.swift # Analysis, transforms, actions, and models
  AppSettingsTests.swift     # UserDefaults persistence
  StorageTests.swift         # History, image storage, expiry, and recovery
  PlainTextPasteServiceTests.swift # Plain-text pasteboard lifecycle
Scripts/
  build-app.sh               # Builds the .app bundle
  generate-icon.swift        # Generates AppIcon.icns
```

## Building and Testing

```bash
make build    # Compile with SwiftPM
make test     # Run the SwiftPM test suite
make app      # Build the .app bundle into dist/
make run      # Build and launch
```

Use `make test` as the standard local and CI test entrypoint. Direct `swift test`
does not pass the Swift Testing framework and runtime search paths that the
Makefile supplies for Xcode and Command Line Tools installations.

## Pull Request Guidelines

1. **One concern per PR.** Keep changes focused — a bug fix, a new content type, a UI tweak.
2. **Add tests.** Put behavior tests under `Tests/PastePilotTests/`. Storage changes should use temporary directories and injected dependencies.
3. **Run `make test` before submitting.** All checks must pass.
4. **Follow existing style.** SwiftUI for views, AppKit where needed, no third-party dependencies.
5. **Localize user-facing strings.** Add entries to `zh-Hans.lproj/Localizable.strings` when introducing new UI text.

## Adding a New Content Type

1. Add a case to `ContentKind` in `ClipboardItem.swift`.
2. Add detection logic in `ContentAnalyzer.swift`.
3. Define actions in `ClipboardAction.swift`.
4. Add transform functions in `ContentTransformer.swift` if needed.
5. Add localization strings for the kind title, explanation, action names, and details.
6. Add test cases in `Tests/PastePilotTests/ContentBehaviorTests.swift`.

## Reporting Issues

When filing a bug, please include:

- macOS version
- Steps to reproduce
- What you expected vs. what happened
- The content type involved (if applicable)

## License

By contributing, you agree that your contributions will be licensed under the [MIT License](LICENSE).

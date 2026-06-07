import AppKit
import Foundation

struct ClipboardAction: Identifiable {
    enum Effect {
        case copy(String)
        case copyImage(String)
        case copyImageMarkdown(
            fileName: String,
            sourceURL: String?,
            originalPath: String?
        )
        case copyCachedImagePath(String)
        case copyFiles([URL])
        case copyRichText(UUID)
        case revealFiles([URL])
        case quickLook([URL])
        case open(URL)
    }

    let id: String
    let title: String
    let detail: String
    let symbol: String
    let effect: Effect

    var preview: String? {
        if case let .copy(content) = effect { return content }
        return nil
    }
}

enum ClipboardActionFactory {
    static func actions(for item: ClipboardItem) -> [ClipboardAction] {
        if item.kind == .image, let fileName = item.imageFileName {
            var imageActions = [
                ClipboardAction(
                    id: "copy-image",
                    title: "Copy Image".localized,
                    detail: "Write the original image back to the clipboard".localized,
                    symbol: "doc.on.doc",
                    effect: .copyImage(fileName)
                ),
                ClipboardAction(
                    id: "copy-image-markdown",
                    title: "Copy Markdown".localized,
                    detail: "Prefers web URL, falls back to local file path".localized,
                    symbol: "text.badge.checkmark",
                    effect: .copyImageMarkdown(
                        fileName: fileName,
                        sourceURL: item.imageSourceURL,
                        originalPath: item.imageOriginalPath
                    )
                )
            ]
            if let sourceURL = item.imageSourceURL {
                imageActions.append(
                    ClipboardAction(
                        id: "copy-image-url",
                        title: "Copy Image URL".localized,
                        detail: "Copy the original web image address".localized,
                        symbol: "link",
                        effect: .copy(sourceURL)
                    )
                )
            }
            if let originalPath = item.imageOriginalPath {
                let originalURL = URL(fileURLWithPath: originalPath)
                imageActions.append(
                    ClipboardAction(
                        id: "copy-image-path",
                        title: "Copy File Path".localized,
                        detail: "Copy the local path of the original image file".localized,
                        symbol: "folder",
                        effect: .copy(originalPath)
                    )
                )
                imageActions.append(contentsOf: fileActions(for: [originalURL]))
            } else {
                imageActions.append(
                    ClipboardAction(
                        id: "copy-image-cache-path",
                        title: "Copy Cache Path".localized,
                        detail: "Copy the PastePilot-cached PNG path".localized,
                        symbol: "internaldrive",
                        effect: .copyCachedImagePath(fileName)
                    )
                )
            }
            return deduplicated(imageActions)
        }

        var actions = [
            ClipboardAction(
                id: "copy",
                title: "Copy Original".localized,
                detail: "Copy as-is back to the clipboard".localized,
                symbol: "doc.on.doc",
                effect: .copy(item.content)
            )
        ]

        switch item.kind {
        case .file:
            actions = fileActions(for: item.fileURLs)
        case .richText:
            actions.insert(
                ClipboardAction(
                    id: "copy-rich-text",
                    title: "Copy with Formatting".localized,
                    detail: "Preserve fonts, styles, colors, and links".localized,
                    symbol: "textformat",
                    effect: .copyRichText(item.id)
                ),
                at: 0
            )
            if let html = item.richTextHTML {
                actions.append(
                    ClipboardAction(
                        id: "copy-html",
                        title: "Copy HTML Source".localized,
                        detail: "Copy the underlying HTML markup".localized,
                        symbol: "chevron.left.forwardslash.chevron.right",
                        effect: .copy(html)
                    )
                )
            }
        case .image:
            break
        case .json:
            if let formatted = ContentTransformer.formatJSON(item.content) {
                actions.append(
                    ClipboardAction(
                        id: "format-json",
                        title: "Format JSON".localized,
                        detail: "Sort keys and indent for readability".localized,
                        symbol: "increase.indent",
                        effect: .copy(formatted)
                    )
                )
            }
            if let minified = ContentTransformer.minifyJSON(item.content) {
                actions.append(
                    ClipboardAction(
                        id: "minify-json",
                        title: "Minify JSON".localized,
                        detail: "Remove whitespace for payloads and configs".localized,
                        symbol: "decrease.indent",
                        effect: .copy(minified)
                    )
                )
            }
            if let typeScript = ContentTransformer.jsonToTypeScript(item.content) {
                actions.append(
                    ClipboardAction(
                        id: "typescript",
                        title: "Generate TypeScript Types".localized,
                        detail: "Infer an interface from field values".localized,
                        symbol: "t.square",
                        effect: .copy(typeScript)
                    )
                )
            }
        case .url:
            if let url = URL(string: item.content) {
                actions.insert(
                    ClipboardAction(
                        id: "open-url",
                        title: "Open in Browser".localized,
                        detail: url.host ?? "Open this link".localized,
                        symbol: "safari",
                        effect: .open(url)
                    ),
                    at: 0
                )
            }
        case .color:
            actions.append(
                ClipboardAction(
                    id: "uppercase-color",
                    title: "Copy Uppercased Color".localized,
                    detail: "Normalize hex color format".localized,
                    symbol: "paintpalette",
                    effect: .copy(item.content.uppercased())
                )
            )
        case .command:
            actions.append(contentsOf: shellActions(for: item.content))
            actions.append(
                ClipboardAction(
                    id: "quote-command",
                    title: "Escape for String Embedding".localized,
                    detail: "Escape quotes, backslashes, and newlines".localized,
                    symbol: "quote.opening",
                    effect: .copy(ContentTransformer.escapeString(item.content))
                )
            )
        case .error:
            if let extracted = ContentTransformer.extractShellCommands(item.content) {
                actions.append(contentsOf: extractedCommandActions(extracted))
            }
            actions.append(
                ClipboardAction(
                    id: "markdown-error",
                    title: "Wrap in Markdown Code Block".localized,
                    detail: "Ready to paste into issues or chats".localized,
                    symbol: "text.badge.checkmark",
                    effect: .copy("```\n\(item.content)\n```")
                )
            )
        case .markdown, .code, .text:
            if let extracted = ContentTransformer.extractShellCommands(item.content) {
                actions.append(contentsOf: extractedCommandActions(extracted))
            }
            actions.append(contentsOf: textActions(for: item.content))
        }

        return deduplicated(actions)
    }

    static func compactActions(for item: ClipboardItem) -> [ClipboardAction] {
        let available = actions(for: item).filter {
            $0.id != copyAction(for: item).id
        }
        if item.kind == .image, item.imageOriginalPath != nil {
            let preferredIDs = ["quick-look", "reveal-files", "copy-image-markdown"]
            return preferredIDs.compactMap { id in
                available.first { $0.id == id }
            }
        }
        return Array(available.prefix(3))
    }

    static func copyAction(for item: ClipboardItem) -> ClipboardAction {
        if item.kind == .file {
            return ClipboardAction(
                id: "copy-files",
                title: "Copy Files".localized,
                detail: "Write the original files back to the clipboard".localized,
                symbol: "doc.on.doc",
                effect: .copyFiles(item.fileURLs)
            )
        }
        if item.kind == .richText, item.hasRichText {
            return ClipboardAction(
                id: "copy-rich-text",
                title: "Copy with Formatting".localized,
                detail: "Preserve fonts, styles, colors, and links".localized,
                symbol: "textformat",
                effect: .copyRichText(item.id)
            )
        }
        if let fileName = item.imageFileName {
            return ClipboardAction(
                id: "copy-image",
                title: "Copy Image".localized,
                detail: "Write the original image back to the clipboard".localized,
                symbol: "doc.on.doc",
                effect: .copyImage(fileName)
            )
        }
        return ClipboardAction(
            id: "copy",
            title: "Copy Original".localized,
            detail: "Copy as-is back to the clipboard".localized,
            symbol: "doc.on.doc",
            effect: .copy(item.content)
        )
    }

    @MainActor
    static func perform(_ action: ClipboardAction, using store: ClipboardStore) -> String {
        switch action.effect {
        case let .copy(content):
            store.copy(content)
            return "Copied: %@".localized(action.title)
        case let .copyImage(fileName):
            return store.copyImage(fileName: fileName)
                ? "Image copied".localized
                : "Image file missing".localized
        case let .copyImageMarkdown(fileName, sourceURL, originalPath):
            let reference = sourceURL
                ?? originalPath
                ?? store.imagePath(fileName: fileName)
            let altText = originalPath
                .map { URL(fileURLWithPath: $0).deletingPathExtension().lastPathComponent }
                ?? "image"
            store.copy(
                ContentTransformer.imageMarkdown(
                    reference: reference,
                    altText: altText
                )
            )
            return "Image Markdown copied".localized
        case let .copyCachedImagePath(fileName):
            store.copy(store.imagePath(fileName: fileName))
            return "Cache path copied".localized
        case let .copyFiles(urls):
            return store.copyFiles(urls)
                ? "Files copied".localized
                : "Files are no longer available".localized
        case let .copyRichText(id):
            guard let item = store.items.first(where: { $0.id == id }) else {
                return "Rich text is no longer available".localized
            }
            return store.copyRichText(for: item)
                ? "Rich text copied".localized
                : "Rich text is no longer available".localized
        case let .revealFiles(urls):
            let existingURLs = urls.filter { FileManager.default.fileExists(atPath: $0.path) }
            guard !existingURLs.isEmpty else {
                return "Files are no longer available".localized
            }
            NSWorkspace.shared.activateFileViewerSelecting(existingURLs)
            return "Shown in Finder".localized
        case let .quickLook(urls):
            return QuickLookService.shared.preview(urls)
                ? "Quick Look opened".localized
                : "Files are no longer available".localized
        case let .open(url):
            NSWorkspace.shared.open(url)
            return "Link opened".localized
        }
    }

    private static func textActions(for content: String) -> [ClipboardAction] {
        [
            ClipboardAction(
                id: "camel-case",
                title: "Convert to camelCase".localized,
                detail: "For JavaScript and Swift variable names".localized,
                symbol: "arrow.up.forward",
                effect: .copy(ContentTransformer.toCamelCase(content))
            ),
            ClipboardAction(
                id: "snake-case",
                title: "Convert to snake_case".localized,
                detail: "For database fields and Python variables".localized,
                symbol: "arrow.down.forward",
                effect: .copy(ContentTransformer.toSnakeCase(content))
            ),
            ClipboardAction(
                id: "escape",
                title: "Escape as String".localized,
                detail: "Handle quotes, backslashes, and newlines".localized,
                symbol: "quote.opening",
                effect: .copy(ContentTransformer.escapeString(content))
            )
        ]
    }

    private static func shellActions(for content: String) -> [ClipboardAction] {
        if let extracted = ContentTransformer.extractShellCommands(content),
           extracted.trimmingCharacters(in: .whitespacesAndNewlines)
            != content.trimmingCharacters(in: .whitespacesAndNewlines) {
            return extractedCommandActions(extracted)
        }
        return [
            ClipboardAction(
                id: "shell-code-block",
                title: "Wrap in Shell Code Block".localized,
                detail: "Generate a Markdown code block with sh language tag".localized,
                symbol: "chevron.left.forwardslash.chevron.right",
                effect: .copy(ContentTransformer.shellCodeBlock(content))
            )
        ]
    }

    private static func extractedCommandActions(_ extracted: String) -> [ClipboardAction] {
        [
            ClipboardAction(
                id: "extract-shell",
                title: "Extract Commands".localized,
                detail: "Strip prompts and output, keep only runnable commands".localized,
                symbol: "terminal",
                effect: .copy(extracted)
            ),
            ClipboardAction(
                id: "extracted-shell-code-block",
                title: "Command Code Block".localized,
                detail: "Wrap extracted commands in a Markdown shell code block".localized,
                symbol: "chevron.left.forwardslash.chevron.right",
                effect: .copy(ContentTransformer.shellCodeBlock(extracted))
            )
        ]
    }

    private static func fileActions(for urls: [URL]) -> [ClipboardAction] {
        guard !urls.isEmpty else { return [] }
        return [
            ClipboardAction(
                id: "copy-files",
                title: urls.count == 1 ? "Copy File".localized : "Copy Files".localized,
                detail: "Write the original files back to the clipboard".localized,
                symbol: "doc.on.doc",
                effect: .copyFiles(urls)
            ),
            ClipboardAction(
                id: "quick-look",
                title: "Quick Look".localized,
                detail: "Preview using the macOS system viewer".localized,
                symbol: "eye",
                effect: .quickLook(urls)
            ),
            ClipboardAction(
                id: "reveal-files",
                title: "Show in Finder".localized,
                detail: "Reveal the original file location".localized,
                symbol: "folder",
                effect: .revealFiles(urls)
            )
        ]
    }

    private static func deduplicated(_ actions: [ClipboardAction]) -> [ClipboardAction] {
        var seenEffects: Set<String> = []
        return actions.filter { action in
            let key: String
            switch action.effect {
            case let .copy(content):
                key = "copy:\(content)"
            case let .copyImage(fileName):
                key = "image:\(fileName)"
            case let .copyImageMarkdown(fileName, sourceURL, originalPath):
                key = "markdown:\(sourceURL ?? originalPath ?? fileName)"
            case let .copyCachedImagePath(fileName):
                key = "cache-path:\(fileName)"
            case let .copyFiles(urls):
                key = "files:\(urls.map(\.path).joined(separator: "|"))"
            case let .copyRichText(id):
                key = "rich-text:\(id.uuidString)"
            case let .revealFiles(urls):
                key = "reveal:\(urls.map(\.path).joined(separator: "|"))"
            case let .quickLook(urls):
                key = "quick-look:\(urls.map(\.path).joined(separator: "|"))"
            case let .open(url):
                key = "open:\(url.absoluteString)"
            }
            return seenEffects.insert(key).inserted
        }
    }
}

extension ContentKind {
    var localizedTitle: String {
        switch self {
        case .file: "Files".localized
        case .richText: "Rich Text".localized
        case .image: "Image".localized
        case .json: "JSON Data".localized
        case .url: "URL".localized
        case .color: "Color".localized
        case .command: "Command".localized
        case .error: "Error".localized
        case .markdown: "Markdown".localized
        case .code: "Code".localized
        case .text: "Plain Text".localized
        }
    }

    var explanation: String {
        switch self {
        case .file: "Files detected. Copy, preview, or reveal them in Finder.".localized
        case .richText: "Formatted text detected. Preserve styling or copy as plain text.".localized
        case .image: "Image detected. Preview and re-copy available.".localized
        case .json: "Structure parsed. Format, minify, or generate types.".localized
        case .url: "A reachable link. Open or copy directly.".localized
        case .color: "Color value detected. Normalize the format before use.".localized
        case .command: "Terminal command detected. Never auto-executed.".localized
        case .error: "Error detected. Clean up and share in an issue or chat.".localized
        case .markdown: "Markdown detected. Transform naming or string format.".localized
        case .code: "Code detected. Copy or escape for string embedding.".localized
        case .text: "Convert naming style or escape as a string.".localized
        }
    }
}

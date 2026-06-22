import AppKit
import Foundation

struct ClipboardAction: Identifiable {
    enum Effect {
        case copy(String)
        case copyItem(UUID)
        case copyImage(String)
        case copyImageMarkdown(
            fileName: String,
            sourceURL: String?,
            originalPath: String?
        )
        case copyCachedImageFile(String)
        case copyFiles([URL])
        case copyRichText(UUID)
        case revealCachedImageFile(String)
        case revealFiles([URL])
        case quickLookCachedImageFile(String)
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

    var closesInlinePreview: Bool {
        switch effect {
        case .quickLookCachedImageFile,
             .quickLook:
            return true
        case .copy,
             .copyItem,
             .copyImage,
             .copyImageMarkdown,
             .copyCachedImageFile,
             .copyFiles,
             .copyRichText,
             .revealCachedImageFile,
             .revealFiles,
             .open:
            return false
        }
    }
}

enum ClipboardActionFactory {
    static func actions(for item: ClipboardItem) -> [ClipboardAction] {
        if item.kind == .image, let fileName = item.imageFileName {
            if let originalPath = item.imageOriginalPath {
                return deduplicated(
                    imageActions(
                        fileName: fileName,
                        sourceURL: item.imageSourceURL,
                        originalPath: originalPath,
                        fileURL: URL(fileURLWithPath: originalPath),
                        usesCachedFile: false
                    )
                )
            }
            return deduplicated(
                imageActions(
                    fileName: fileName,
                    sourceURL: item.imageSourceURL,
                    originalPath: nil,
                    fileURL: nil,
                    usesCachedFile: true
                )
            )
        }

        var actions = [
            ClipboardAction(
                id: "copy",
                title: "Copy Original".localized,
                detail: "Copy as-is back to the clipboard".localized,
                symbol: "doc.on.doc",
                effect: item.hasExternalContent
                    ? .copyItem(item.id)
                    : .copy(item.content)
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
            guard !item.hasExternalContent else { break }
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
            guard !item.hasExternalContent else { break }
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
            guard !item.hasExternalContent else { break }
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
            guard !item.hasExternalContent else { break }
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
            guard !item.hasExternalContent else { break }
            if let extracted = ContentTransformer.extractShellCommands(item.content) {
                actions.append(contentsOf: extractedCommandActions(extracted))
            }
            actions.append(
                ClipboardAction(
                    id: "markdown-error",
                    title: "Wrap in Markdown Code Block".localized,
                    detail: "Ready to paste into issues or chats".localized,
                    symbol: "text.badge.checkmark",
                    effect: .copy(ContentTransformer.markdownCodeBlock(item.content))
                )
            )
        case .code:
            guard !item.hasExternalContent else { break }
            actions.append(contentsOf: codeActions(for: item.content))
        case .markdown, .text:
            guard !item.hasExternalContent else { break }
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
            effect: item.hasExternalContent
                ? .copyItem(item.id)
                : .copy(item.content)
        )
    }

    static func keyboardActions(for item: ClipboardItem) -> [ClipboardAction] {
        let copy = copyAction(for: item)
        return [copy] + actions(for: item).filter { $0.id != copy.id }
    }

    @MainActor
    static func perform(_ action: ClipboardAction, using store: ClipboardStore) -> String {
        switch action.effect {
        case let .copy(content):
            store.copy(content)
            return "Copied: %@".localized(action.title)
        case let .copyItem(id):
            guard let item = store.items.first(where: { $0.id == id }),
                  let content = store.content(for: item) else {
                return "Content is no longer available".localized
            }
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
        case let .copyCachedImageFile(fileName):
            return store.copyFiles([URL(fileURLWithPath: store.imagePath(fileName: fileName))])
                ? "Files copied".localized
                : "Image file missing".localized
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
        case let .revealCachedImageFile(fileName):
            let url = URL(fileURLWithPath: store.imagePath(fileName: fileName))
            guard FileManager.default.fileExists(atPath: url.path) else {
                return "Image file missing".localized
            }
            NSWorkspace.shared.activateFileViewerSelecting([url])
            return "Shown in Finder".localized
        case let .quickLook(urls):
            return QuickLookService.shared.preview(urls)
                ? "Quick Look opened".localized
                : "Files are no longer available".localized
        case let .quickLookCachedImageFile(fileName):
            return QuickLookService.shared.preview([
                URL(fileURLWithPath: store.imagePath(fileName: fileName))
            ])
                ? "Quick Look opened".localized
                : "Image file missing".localized
        case let .open(url):
            NSWorkspace.shared.open(url)
            return "Link opened".localized
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
        case .code: "Code detected. Copy or wrap as Markdown.".localized
        case .text: "Convert naming style or escape as a string.".localized
        }
    }
}

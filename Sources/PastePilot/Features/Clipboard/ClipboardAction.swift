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
        case copyOCRText(UUID)
        case copyCachedImageFile(String)
        case copyFiles([URL])
        case copyRichText(UUID)
        case revealCachedImageFile(String)
        case revealFiles([URL])
        case quickLookCachedImageFile(String)
        case quickLook([URL])
        case open(URL)
    }

    enum InputSource: String, Equatable {
        case itemContent
        case itemIdentity
        case generatedContent
        case imageAsset
        case imageURL
        case imageFile
        case fileURLs
        case richText
        case ocrText
        case barcodePayload
        case url
    }

    enum OutputEffect: String, Equatable {
        case clipboardText
        case clipboardItem
        case clipboardImage
        case clipboardFiles
        case clipboardRichText
        case revealInFinder
        case quickLook
        case openURL
    }

    enum CloseBehavior: String, Equatable {
        case keepInlinePreview
        case closeInlinePreview
    }

    let id: String
    let title: String
    let detail: String
    let symbol: String
    let acceptedKinds: Set<ContentKind>
    let inputSource: InputSource
    let outputEffect: OutputEffect
    let closeBehavior: CloseBehavior
    let effect: Effect

    init(
        id: String,
        title: String,
        detail: String,
        symbol: String,
        acceptedKinds: Set<ContentKind> = Set(ContentKind.allCases),
        inputSource: InputSource = .generatedContent,
        outputEffect: OutputEffect? = nil,
        closeBehavior: CloseBehavior? = nil,
        effect: Effect
    ) {
        self.id = id
        self.title = title
        self.detail = detail
        self.symbol = symbol
        self.acceptedKinds = acceptedKinds
        self.inputSource = inputSource
        self.outputEffect = outputEffect ?? Self.outputEffect(for: effect)
        self.closeBehavior = closeBehavior ?? Self.closeBehavior(for: effect)
        self.effect = effect
    }

    var preview: String? {
        if case let .copy(content) = effect { return content }
        return nil
    }

    var closesInlinePreview: Bool {
        closeBehavior == .closeInlinePreview
    }

    private static func outputEffect(for effect: Effect) -> OutputEffect {
        switch effect {
        case .copy,
             .copyImageMarkdown,
             .copyOCRText:
            return .clipboardText
        case .copyItem:
            return .clipboardItem
        case .copyImage:
            return .clipboardImage
        case .copyCachedImageFile,
             .copyFiles:
            return .clipboardFiles
        case .copyRichText:
            return .clipboardRichText
        case .revealCachedImageFile,
             .revealFiles:
            return .revealInFinder
        case .quickLookCachedImageFile,
             .quickLook:
            return .quickLook
        case .open:
            return .openURL
        }
    }

    private static func closeBehavior(for effect: Effect) -> CloseBehavior {
        switch effect {
        case .quickLookCachedImageFile,
             .quickLook:
            return .closeInlinePreview
        case .copy,
             .copyItem,
             .copyImage,
             .copyImageMarkdown,
             .copyOCRText,
             .copyCachedImageFile,
             .copyFiles,
             .copyRichText,
             .revealCachedImageFile,
             .revealFiles,
             .open:
            return .keepInlinePreview
        }
    }
}

struct ClipboardActionResult: Equatable {
    let message: String
    let didCopy: Bool
}

enum ClipboardActionFactory {
    static func actions(for item: ClipboardItem) -> [ClipboardAction] {
        if item.kind == .image, let fileName = item.imageFileName {
            var actions: [ClipboardAction]
            if let originalPath = item.imageOriginalPath {
                actions = imageActions(
                    fileName: fileName,
                    sourceURL: item.imageSourceURL,
                    originalPath: originalPath,
                    fileURL: URL(fileURLWithPath: originalPath),
                    usesCachedFile: false
                )
            } else {
                actions = imageActions(
                    fileName: fileName,
                    sourceURL: item.imageSourceURL,
                    originalPath: nil,
                    fileURL: nil,
                    usesCachedFile: true
                )
            }
            if item.hasPasteboardRepresentations {
                actions.insert(originalCopyAction(for: item), at: 0)
            }
            actions = insertingOCRTextAction(for: item, into: actions)
            actions = insertingBarcodeAction(for: item, into: actions)
            return deduplicated(actions)
        }

        var actions = [
            originalCopyAction(for: item)
        ]

        switch item.kind {
        case .file:
            actions = fileActions(for: item.fileURLs)
            if item.hasPasteboardRepresentations {
                actions.insert(originalCopyAction(for: item), at: 0)
            }
        case .richText:
            actions.insert(
                ClipboardActionRegistry.copyRichText.action(
                    effect: .copyRichText(item.id)
                ),
                at: 0
            )
            if let html = item.richTextHTML {
                actions.append(
                    ClipboardActionRegistry.copyHTML.action(
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
                    ClipboardActionRegistry.formatJSON.action(
                        effect: .copy(formatted)
                    )
                )
            }
            if let minified = ContentTransformer.minifyJSON(item.content) {
                actions.append(
                    ClipboardActionRegistry.minifyJSON.action(
                        effect: .copy(minified)
                    )
                )
            }
            if let typeScript = ContentTransformer.jsonToTypeScript(item.content) {
                actions.append(
                    ClipboardActionRegistry.typeScript.action(
                        effect: .copy(typeScript)
                    )
                )
            }
        case .url:
            guard !item.hasExternalContent else { break }
            if let url = URL(string: item.content) {
                actions.insert(
                    ClipboardActionRegistry.openURL.action(
                        effect: .open(url),
                        detail: url.host ?? "Open this link".localized
                    ),
                    at: 0
                )
            }
        case .color:
            guard !item.hasExternalContent else { break }
            actions.append(
                ClipboardActionRegistry.uppercaseColor.action(
                    effect: .copy(item.content.uppercased())
                )
            )
        case .command:
            guard !item.hasExternalContent else { break }
            actions.append(contentsOf: shellActions(for: item.content))
            actions.append(
                ClipboardActionRegistry.quoteCommand.action(
                    effect: .copy(ContentTransformer.escapeString(item.content))
                )
            )
        case .error:
            guard !item.hasExternalContent else { break }
            if let extracted = ContentTransformer.extractShellCommands(item.content) {
                actions.append(contentsOf: extractedCommandActions(extracted))
            }
            actions.append(
                ClipboardActionRegistry.markdownError.action(
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
        if item.hasPasteboardRepresentations {
            return originalCopyAction(for: item)
        }
        if item.kind == .file {
            return ClipboardActionRegistry.copyFiles.action(
                effect: .copyFiles(item.fileURLs)
            )
        }
        if item.kind == .richText, item.hasRichText {
            return ClipboardActionRegistry.copyRichText.action(
                effect: .copyRichText(item.id)
            )
        }
        if let fileName = item.imageFileName {
            return ClipboardActionRegistry.copyImage.action(
                effect: .copyImage(fileName)
            )
        }
        let copyEffect: ClipboardAction.Effect = item.hasExternalContent
            ? .copyItem(item.id)
            : .copy(item.content)
        return ClipboardActionRegistry.copyText.action(
            effect: copyEffect,
            inputSource: item.hasExternalContent ? .itemIdentity : nil,
            outputEffect: item.hasExternalContent ? .clipboardItem : nil
        )
    }

    static func originalCopyAction(for item: ClipboardItem) -> ClipboardAction {
        let definition = item.hasPasteboardRepresentations
            ? ClipboardActionRegistry.copyOriginalRepresentation
            : ClipboardActionRegistry.copyText
        let copyEffect: ClipboardAction.Effect =
            item.hasExternalContent || item.hasPasteboardRepresentations
                ? .copyItem(item.id)
                : .copy(item.content)
        return definition.action(
            effect: copyEffect,
            inputSource: item.hasExternalContent || item.hasPasteboardRepresentations
                ? .itemIdentity
                : nil,
            outputEffect: item.hasExternalContent || item.hasPasteboardRepresentations
                ? .clipboardItem
                : nil
        )
    }

    static func keyboardActions(for item: ClipboardItem) -> [ClipboardAction] {
        let copy = copyAction(for: item)
        return [copy] + actions(for: item).filter { $0.id != copy.id }
    }

    @MainActor
    static func perform(_ action: ClipboardAction, using store: ClipboardStore) -> String {
        performResult(action, using: store).message
    }

    @MainActor
    static func performResult(
        _ action: ClipboardAction,
        using store: ClipboardStore
    ) -> ClipboardActionResult {
        switch action.effect {
        case let .copy(content):
            store.copy(content)
            return ClipboardActionResult(
                message: "Copied: %@".localized(action.title),
                didCopy: true
            )
        case let .copyItem(id):
            guard let item = store.items.first(where: { $0.id == id }) else {
                return ClipboardActionResult(
                    message: "Content is no longer available".localized,
                    didCopy: false
                )
            }
            let didCopy = store.copyOriginalItem(item)
            return ClipboardActionResult(
                message: didCopy
                    ? "Copied: %@".localized(action.title)
                    : "Content is no longer available".localized,
                didCopy: didCopy
            )
        case let .copyImage(fileName):
            let didCopy = store.copyImage(fileName: fileName)
            return ClipboardActionResult(
                message: didCopy
                    ? "Image copied".localized
                    : "Image file missing".localized,
                didCopy: didCopy
            )
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
            return ClipboardActionResult(
                message: "Image Markdown copied".localized,
                didCopy: true
            )
        case let .copyOCRText(id):
            guard let item = store.items.first(where: { $0.id == id }),
                  let ocrText = item.ocrText?
                      .trimmingCharacters(in: .whitespacesAndNewlines),
                  !ocrText.isEmpty else {
                return ClipboardActionResult(
                    message: "OCR text is no longer available".localized,
                    didCopy: false
                )
            }
            store.copy(ocrText)
            return ClipboardActionResult(
                message: "OCR text copied".localized,
                didCopy: true
            )
        case let .copyCachedImageFile(fileName):
            let didCopy = store.copyFiles([
                URL(fileURLWithPath: store.imagePath(fileName: fileName))
            ])
            return ClipboardActionResult(
                message: didCopy
                    ? "Files copied".localized
                    : "Image file missing".localized,
                didCopy: didCopy
            )
        case let .copyFiles(urls):
            let didCopy = store.copyFiles(urls)
            return ClipboardActionResult(
                message: didCopy
                    ? "Files copied".localized
                    : "Files are no longer available".localized,
                didCopy: didCopy
            )
        case let .copyRichText(id):
            guard let item = store.items.first(where: { $0.id == id }) else {
                return ClipboardActionResult(
                    message: "Rich text is no longer available".localized,
                    didCopy: false
                )
            }
            let didCopy = store.copyRichText(for: item)
            return ClipboardActionResult(
                message: didCopy
                    ? "Rich text copied".localized
                    : "Rich text is no longer available".localized,
                didCopy: didCopy
            )
        case let .revealFiles(urls):
            let existingURLs = urls.filter { FileManager.default.fileExists(atPath: $0.path) }
            guard !existingURLs.isEmpty else {
                return ClipboardActionResult(
                    message: "Files are no longer available".localized,
                    didCopy: false
                )
            }
            NSWorkspace.shared.activateFileViewerSelecting(existingURLs)
            return ClipboardActionResult(
                message: "Shown in Finder".localized,
                didCopy: false
            )
        case let .revealCachedImageFile(fileName):
            let url = URL(fileURLWithPath: store.imagePath(fileName: fileName))
            guard FileManager.default.fileExists(atPath: url.path) else {
                return ClipboardActionResult(
                    message: "Image file missing".localized,
                    didCopy: false
                )
            }
            NSWorkspace.shared.activateFileViewerSelecting([url])
            return ClipboardActionResult(
                message: "Shown in Finder".localized,
                didCopy: false
            )
        case let .quickLook(urls):
            let didOpen = QuickLookService.shared.preview(urls)
            return ClipboardActionResult(
                message: didOpen
                    ? "Quick Look opened".localized
                    : "Files are no longer available".localized,
                didCopy: false
            )
        case let .quickLookCachedImageFile(fileName):
            let didOpen = QuickLookService.shared.preview([
                URL(fileURLWithPath: store.imagePath(fileName: fileName))
            ])
            return ClipboardActionResult(
                message: didOpen
                    ? "Quick Look opened".localized
                    : "Image file missing".localized,
                didCopy: false
            )
        case let .open(url):
            NSWorkspace.shared.open(url)
            return ClipboardActionResult(
                message: "Link opened".localized,
                didCopy: false
            )
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

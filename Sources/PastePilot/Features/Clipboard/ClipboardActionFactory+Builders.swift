import Foundation

extension ClipboardActionFactory {
    static func textActions(for content: String) -> [ClipboardAction] {
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

    static func codeActions(for content: String) -> [ClipboardAction] {
        [
            ClipboardAction(
                id: "markdown-code-block",
                title: "Wrap in Markdown Code Block".localized,
                detail: "Ready to paste into issues or chats".localized,
                symbol: "text.badge.checkmark",
                effect: .copy(ContentTransformer.markdownCodeBlock(content))
            )
        ]
    }

    static func shellActions(for content: String) -> [ClipboardAction] {
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

    static func extractedCommandActions(_ extracted: String) -> [ClipboardAction] {
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

    static func fileActions(for urls: [URL]) -> [ClipboardAction] {
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

    static func imageActions(
        fileName: String,
        sourceURL: String?,
        originalPath: String?,
        fileURL: URL?,
        usesCachedFile: Bool
    ) -> [ClipboardAction] {
        var actions = [
            ClipboardAction(
                id: "copy-image",
                title: "Copy Image".localized,
                detail: "Write the original image back to the clipboard".localized,
                symbol: "photo",
                effect: .copyImage(fileName)
            )
        ]

        if let sourceURL {
            actions.append(
                ClipboardAction(
                    id: "copy-image-url",
                    title: "Copy Image URL".localized,
                    detail: "Copy the original web image address".localized,
                    symbol: "link",
                    effect: .copy(sourceURL)
                )
            )
        } else if usesCachedFile {
            actions.append(ClipboardAction(
                id: "copy-image-file",
                title: "Copy File".localized,
                detail: "Write the cached PNG file back to the clipboard".localized,
                symbol: "doc.on.doc",
                effect: .copyCachedImageFile(fileName)
            ))
        } else if let fileURL {
            actions.append(ClipboardAction(
                id: "copy-image-file",
                title: "Copy File".localized,
                detail: "Write the original files back to the clipboard".localized,
                symbol: "doc.on.doc",
                effect: .copyFiles([fileURL])
            ))
        }

        actions.append(
            ClipboardAction(
                id: "copy-image-markdown",
                title: "Copy Markdown".localized,
                detail: "Prefers web URL, falls back to local file path".localized,
                symbol: "text.badge.checkmark",
                effect: .copyImageMarkdown(
                    fileName: fileName,
                    sourceURL: sourceURL,
                    originalPath: originalPath
                )
            )
        )

        if usesCachedFile {
            actions.append(ClipboardAction(
                id: "quick-look",
                title: "Quick Look".localized,
                detail: "Preview using the macOS system viewer".localized,
                symbol: "eye",
                effect: .quickLookCachedImageFile(fileName)
            ))
            actions.append(ClipboardAction(
                id: "reveal-files",
                title: "Show in Finder".localized,
                detail: "Reveal the cached PNG file".localized,
                symbol: "folder",
                effect: .revealCachedImageFile(fileName)
            ))
        } else if let fileURL {
            actions.append(ClipboardAction(
                id: "quick-look",
                title: "Quick Look".localized,
                detail: "Preview using the macOS system viewer".localized,
                symbol: "eye",
                effect: .quickLook([fileURL])
            ))
            actions.append(ClipboardAction(
                id: "reveal-files",
                title: "Show in Finder".localized,
                detail: "Reveal the original file location".localized,
                symbol: "folder",
                effect: .revealFiles([fileURL])
            ))
        }

        return actions
    }

    static func insertingOCRTextAction(
        for item: ClipboardItem,
        into actions: [ClipboardAction]
    ) -> [ClipboardAction] {
        guard let action = ocrTextAction(for: item) else { return actions }
        var updatedActions = actions
        let insertionIndex = min(1, updatedActions.count)
        updatedActions.insert(action, at: insertionIndex)
        return updatedActions
    }

    static func ocrTextAction(for item: ClipboardItem) -> ClipboardAction? {
        guard let ocrText = item.ocrText?
            .trimmingCharacters(in: .whitespacesAndNewlines),
            !ocrText.isEmpty else {
            return nil
        }
        return ClipboardAction(
            id: "copy-ocr-text",
            title: "Copy OCR Text".localized,
            detail: "Copy recognized text from this image".localized,
            symbol: "text.viewfinder",
            effect: .copyOCRText(item.id)
        )
    }

    static func deduplicated(_ actions: [ClipboardAction]) -> [ClipboardAction] {
        var seenEffects: Set<String> = []
        return actions.filter { action in
            let key: String
            switch action.effect {
            case let .copy(content):
                key = "copy:\(content)"
            case let .copyItem(id):
                key = "copy-item:\(id.uuidString)"
            case let .copyImage(fileName):
                key = "image:\(fileName)"
            case let .copyImageMarkdown(fileName, sourceURL, originalPath):
                key = "markdown:\(sourceURL ?? originalPath ?? fileName)"
            case let .copyOCRText(id):
                key = "ocr-text:\(id.uuidString)"
            case let .copyCachedImageFile(fileName):
                key = "cache-file:\(fileName)"
            case let .copyFiles(urls):
                key = "files:\(urls.map(\.path).joined(separator: "|"))"
            case let .copyRichText(id):
                key = "rich-text:\(id.uuidString)"
            case let .revealCachedImageFile(fileName):
                key = "reveal-cache:\(fileName)"
            case let .revealFiles(urls):
                key = "reveal:\(urls.map(\.path).joined(separator: "|"))"
            case let .quickLookCachedImageFile(fileName):
                key = "quick-look-cache:\(fileName)"
            case let .quickLook(urls):
                key = "quick-look:\(urls.map(\.path).joined(separator: "|"))"
            case let .open(url):
                key = "open:\(url.absoluteString)"
            }
            return seenEffects.insert(key).inserted
        }
    }
}

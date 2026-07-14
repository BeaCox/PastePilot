import Foundation

extension ClipboardActionFactory {
    static func textActions(for content: String) -> [ClipboardAction] {
        [
            ClipboardActionRegistry.camelCase.action(
                effect: .copy(ContentTransformer.toCamelCase(content))
            ),
            ClipboardActionRegistry.snakeCase.action(
                effect: .copy(ContentTransformer.toSnakeCase(content))
            ),
            ClipboardActionRegistry.escapeString.action(
                effect: .copy(ContentTransformer.escapeString(content))
            )
        ]
    }

    static func codeActions(for content: String) -> [ClipboardAction] {
        [
            ClipboardActionRegistry.markdownCodeBlock.action(
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
            ClipboardActionRegistry.shellCodeBlock.action(
                effect: .copy(ContentTransformer.shellCodeBlock(content))
            )
        ]
    }

    static func extractedCommandActions(_ extracted: String) -> [ClipboardAction] {
        [
            ClipboardActionRegistry.extractShell.action(
                effect: .copy(extracted)
            ),
            ClipboardActionRegistry.extractedShellCodeBlock.action(
                effect: .copy(ContentTransformer.shellCodeBlock(extracted))
            )
        ]
    }

    static func fileActions(for urls: [URL]) -> [ClipboardAction] {
        guard !urls.isEmpty else { return [] }
        return [
            ClipboardActionRegistry.copyFiles.action(
                effect: .copyFiles(urls),
                title: urls.count == 1 ? "Copy File".localized : "Copy Files".localized
            ),
            ClipboardActionRegistry.quickLook.action(
                effect: .quickLook(urls)
            ),
            ClipboardActionRegistry.revealFiles.action(
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
            ClipboardActionRegistry.copyImage.action(
                effect: .copyImage(fileName)
            )
        ]

        if let sourceURL {
            actions.append(
                ClipboardActionRegistry.copyImageURL.action(
                    effect: .copy(sourceURL)
                )
            )
        } else if usesCachedFile {
            actions.append(
                ClipboardActionRegistry.copyImageFile.action(
                    effect: .copyCachedImageFile(fileName)
                )
            )
        } else if let fileURL {
            actions.append(
                ClipboardActionRegistry.copyImageFile.action(
                    effect: .copyFiles([fileURL]),
                    detail: "Write the original files back to the clipboard".localized
                )
            )
        }

        actions.append(
            ClipboardActionRegistry.copyImageMarkdown.action(
                effect: .copyImageMarkdown(
                    fileName: fileName,
                    sourceURL: sourceURL,
                    originalPath: originalPath
                )
            )
        )

        if usesCachedFile {
            actions.append(
                ClipboardActionRegistry.quickLook.action(
                    effect: .quickLookCachedImageFile(fileName),
                    inputSource: .imageFile
                )
            )
            actions.append(
                ClipboardActionRegistry.revealFiles.action(
                    effect: .revealCachedImageFile(fileName),
                    detail: "Reveal the cached PNG file".localized,
                    inputSource: .imageFile
                )
            )
        } else if let fileURL {
            actions.append(
                ClipboardActionRegistry.quickLook.action(
                    effect: .quickLook([fileURL])
                )
            )
            actions.append(
                ClipboardActionRegistry.revealFiles.action(
                    effect: .revealFiles([fileURL])
                )
            )
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
        return ClipboardActionRegistry.copyOCRText.action(
            effect: .copyOCRText(item.id)
        )
    }

    static func insertingBarcodeAction(
        for item: ClipboardItem,
        into actions: [ClipboardAction]
    ) -> [ClipboardAction] {
        guard let barcodes = item.detectedBarcodes, !barcodes.isEmpty else {
            return actions
        }
        let payload = barcodes.map(\.payload).joined(separator: "\n")
        var updatedActions = actions
        let insertionIndex = min(1, updatedActions.count)
        updatedActions.insert(
            ClipboardActionRegistry.copyBarcodeContent.action(
                effect: .copy(payload),
                title: barcodes.count == 1
                    ? "Copy Barcode Content".localized
                    : "Copy Barcode Contents".localized
            ),
            at: insertionIndex
        )
        return updatedActions
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

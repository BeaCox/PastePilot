import AppKit
import Foundation
import UniformTypeIdentifiers

extension ClipboardStore {
    func captureImageFile(
        _ url: URL,
        source: (name: String?, bundleIdentifier: String?),
        pasteboardChangeCount: Int?
    ) -> Bool {
        guard let image = NSImage(contentsOf: url) else { return false }
        return saveImage(
            image,
            source: source,
            remoteURL: nil,
            originalPath: url.path,
            pasteboardChangeCount: pasteboardChangeCount
        )
    }

    func saveImage(
        _ image: NSImage,
        source: (name: String?, bundleIdentifier: String?),
        remoteURL: String?,
        originalPath: String?,
        pasteboardChangeCount: Int?
    ) -> Bool {
        guard !isIgnored(bundleIdentifier: source.bundleIdentifier) else { return true }
        guard let cgImage = image.cgImage(
            forProposedRect: nil,
            context: nil,
            hints: nil
        ) else {
            return false
        }

        return saveImage(
            cgImage,
            source: source,
            remoteURL: remoteURL,
            originalPath: originalPath,
            pasteboardChangeCount: pasteboardChangeCount
        )
    }

    func saveImage(
        _ cgImage: CGImage,
        source: (name: String?, bundleIdentifier: String?),
        remoteURL: String?,
        originalPath: String?,
        pasteboardChangeCount: Int?
    ) -> Bool {
        guard !isIgnored(bundleIdentifier: source.bundleIdentifier) else { return true }

        let id = UUID()
        let fileName = "\(id.uuidString).png"
        let sizeLimitBytes = settings.imageSizeLimitMB * 1_024 * 1_024
        imageProcessingQueue.encodeAndSave(
            cgImage,
            fileName: fileName,
            imageStore: imageStore,
            sizeLimitBytes: sizeLimitBytes
        ) { [weak self] result in
            Task { @MainActor in
                guard let self else { return }
                self.finishSavingImage(
                    result,
                    id: id,
                    source: source,
                    remoteURL: remoteURL,
                    originalPath: originalPath,
                    pasteboardChangeCount: pasteboardChangeCount,
                    ocrImage: cgImage
                )
            }
        }
        return true
    }

    func finishSavingImage(
        _ result: Result<ProcessedClipboardImage, Error>,
        id: UUID,
        source: (name: String?, bundleIdentifier: String?),
        remoteURL: String?,
        originalPath: String?,
        pasteboardChangeCount: Int?,
        ocrImage: CGImage
    ) {
        switch result {
        case .success(let processedImage):
            guard pasteboardChangeCount.map({ pasteboard.changeCount == $0 }) ?? true else {
                imageStore.delete(fileName: processedImage.fileName)
                return
            }
            guard items.first?.imageDigest != processedImage.digest else {
                imageStore.delete(fileName: processedImage.fileName)
                return
            }

            let wasPinned = items.first {
                $0.imageDigest == processedImage.digest
            }?.isPinned ?? false
            let item = ClipboardItem(
                id: id,
                content: "Image %d × %d".localized(
                    processedImage.width,
                    processedImage.height
                ),
                kind: .image,
                isPinned: wasPinned,
                sourceAppName: source.name,
                sourceBundleIdentifier: source.bundleIdentifier,
                imageFileName: processedImage.fileName,
                imageWidth: processedImage.width,
                imageHeight: processedImage.height,
                imageByteCount: processedImage.byteCount,
                imageDigest: processedImage.digest,
                imageSourceURL: remoteURL,
                imageOriginalPath: originalPath,
                filePaths: originalPath.map { [$0] }
            )
            let duplicateItems = items.filter {
                $0.imageDigest == processedImage.digest
            }
            cancelOCR(for: duplicateItems)
            duplicateItems.forEach(deleteImageFile)
            items.removeAll { $0.imageDigest == processedImage.digest }
            items.insert(item, at: 0)
            trimHistory(limit: settings.historyLimit)
            save()
            performOCR(on: ocrImage, itemID: id)
        case .failure(let error):
            if let processingError = error as? ClipboardImageProcessingError {
                switch processingError {
                case .encodingFailed:
                    NotificationCenter.default.postPastePilotNotice(
                        PastePilotNotice(
                            "Image could not be saved".localized,
                            style: .error
                        )
                    )
                case .exceedsSizeLimit:
                    NotificationCenter.default.postPastePilotNotice(
                        PastePilotNotice(
                            "Image exceeds the size limit".localized,
                            style: .warning
                        )
                    )
                }
            } else {
                NSLog("PastePilot failed to save image: \(error)")
                NotificationCenter.default.postPastePilotNotice(
                    PastePilotNotice(
                        "Image could not be saved".localized,
                        style: .error
                    )
                )
            }
        }
    }

    func isImageFile(_ url: URL) -> Bool {
        guard let type = UTType(filenameExtension: url.pathExtension) else {
            return false
        }
        return type.conforms(to: .image)
    }

    func performOCR(on cgImage: CGImage, itemID: UUID) {
        cancelOCR(for: itemID)
        let recognitionMode = OCRRecognitionMode(rawValue: settings.ocrRecognitionMode)
            ?? .accurate
        guard recognitionMode != .off else { return }
        let languageMode = OCRLanguageMode(rawValue: settings.ocrLanguageMode)
            ?? .multilingual
        let ocrService = ocrService
        let taskToken = UUID()
        ocrTaskTokensByItemID[itemID] = taskToken
        ocrTasksByItemID[itemID] = Task { [weak self] in
            let text = await ocrService.recognizeText(
                in: cgImage,
                recognitionMode: recognitionMode,
                languageMode: languageMode
            )
            guard let self else { return }
            defer {
                if self.ocrTaskTokensByItemID[itemID] == taskToken {
                    self.ocrTasksByItemID[itemID] = nil
                    self.ocrTaskTokensByItemID[itemID] = nil
                }
            }
            guard !Task.isCancelled,
                  let text,
                  let index = self.items.firstIndex(where: { $0.id == itemID }) else {
                return
            }
            self.items[index].ocrText = text
            self.save()
        }
    }
}

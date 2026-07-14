import AppKit
import Foundation
import UniformTypeIdentifiers

extension ClipboardStore {
    func captureImageFile(
        _ url: URL,
        source: (name: String?, bundleIdentifier: String?),
        pasteboardChangeCount: Int?,
        pasteboardRepresentations: [ClipboardPasteboardRepresentation] = []
    ) -> Bool {
        guard let image = NSImage(contentsOf: url) else { return false }
        return saveImage(
            image,
            source: source,
            remoteURL: nil,
            originalPath: url.path,
            pasteboardChangeCount: pasteboardChangeCount,
            pasteboardRepresentations: pasteboardRepresentations
        )
    }

    func saveImage(
        _ image: NSImage,
        source: (name: String?, bundleIdentifier: String?),
        remoteURL: String?,
        originalPath: String?,
        pasteboardChangeCount: Int?,
        pasteboardRepresentations: [ClipboardPasteboardRepresentation] = []
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
            pasteboardChangeCount: pasteboardChangeCount,
            pasteboardRepresentations: pasteboardRepresentations
        )
    }

    func saveImage(
        _ cgImage: CGImage,
        source: (name: String?, bundleIdentifier: String?),
        remoteURL: String?,
        originalPath: String?,
        pasteboardChangeCount: Int?,
        pasteboardRepresentations: [ClipboardPasteboardRepresentation] = []
    ) -> Bool {
        guard !isIgnored(bundleIdentifier: source.bundleIdentifier) else { return true }

        let id = UUID()
        let fileName = "\(id.uuidString).png"
        let sizeLimitBytes = settings.imageSizeLimitMB * 1_024 * 1_024
        let saveGeneration = imageSaveGeneration
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
                    ocrImage: cgImage,
                    imageSaveGeneration: saveGeneration,
                    pasteboardRepresentations: pasteboardRepresentations
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
        ocrImage: CGImage,
        imageSaveGeneration: Int? = nil,
        pasteboardRepresentations: [ClipboardPasteboardRepresentation] = []
    ) {
        switch result {
        case .success(let processedImage):
            guard pasteboardChangeCount.map({ pasteboard.changeCount == $0 }) ?? true else {
                imageStore.delete(fileName: processedImage.fileName)
                return
            }
            guard items.first.map({
                !imageIdentityMatches($0, processedImage: processedImage)
            }) ?? true else {
                imageStore.delete(fileName: processedImage.fileName)
                return
            }
            guard !shouldDiscardImageSave(
                processedImage,
                startedAt: imageSaveGeneration
            ) else {
                imageStore.delete(fileName: processedImage.fileName)
                return
            }

            let inheritedItem = items.first {
                imageIdentityMatches($0, processedImage: processedImage)
            }
            let wasPinned = inheritedItem?.isPinned ?? false
            var item = ClipboardItem(
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
                imagePerceptualHash: processedImage.perceptualHash,
                imageSourceURL: remoteURL,
                imageOriginalPath: originalPath,
                filePaths: originalPath.map { [$0] },
                pasteboardRepresentations: pasteboardRepresentations
            )
            item.inheritUserMetadata(from: inheritedItem)
            let duplicateItems = items.filter {
                imageIdentityMatches($0, processedImage: processedImage)
            }
            cancelOCR(for: duplicateItems)
            duplicateItems.forEach(deleteImageFile)
            let duplicateIDs = Set(duplicateItems.map(\.id))
            items.removeAll { duplicateIDs.contains($0.id) }
            items.insert(item, at: 0)
            trimHistory(limit: settings.historyLimit)
            enforceStorageLimit()
            save()
            performOCR(on: ocrImage, itemID: id)
        case .failure(let error):
            if let processingError = error as? ClipboardImageProcessingError {
                switch processingError {
                case .encodingFailed:
                    noticePoster.post(
                        PastePilotNotice(
                            "Image could not be saved".localized,
                            style: .error
                        )
                    )
                case .exceedsSizeLimit:
                    noticePoster.post(
                        PastePilotNotice(
                            "Image exceeds the size limit".localized,
                            style: .warning
                        )
                    )
                }
            } else {
                NSLog("PastePilot failed to save image: \(error)")
                noticePoster.post(
                    PastePilotNotice(
                        "Image could not be saved".localized,
                        style: .error
                    )
                )
            }
        }
    }

    func imageIdentityMatches(
        _ item: ClipboardItem,
        processedImage: ProcessedClipboardImage
    ) -> Bool {
        if item.imageDigest == processedImage.digest {
            return true
        }
        guard settings.perceptualImageDeduplicationEnabled,
              item.kind == .image,
              ImagePerceptualHash.areSimilar(
                item.imagePerceptualHash,
                processedImage.perceptualHash
              ),
              let width = item.imageWidth,
              let height = item.imageHeight,
              width > 0,
              height > 0,
              processedImage.width > 0,
              processedImage.height > 0 else {
            return false
        }
        let existingAspectRatio = Double(width) / Double(height)
        let newAspectRatio = Double(processedImage.width) / Double(processedImage.height)
        let relativeDifference = abs(existingAspectRatio - newAspectRatio)
            / max(existingAspectRatio, newAspectRatio)
        return relativeDifference <= 0.02
    }

    func shouldDiscardImageSave(
        _ processedImage: ProcessedClipboardImage,
        startedAt generation: Int?
    ) -> Bool {
        guard let generation else { return false }
        if generation < discardAllImageSavesBeforeGeneration {
            return true
        }
        if let deletedGeneration = deletedImageDigestGenerations[processedImage.digest],
           generation < deletedGeneration {
            return true
        }
        return false
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

    func rerunOCRForImages() {
        let recognitionMode = OCRRecognitionMode(rawValue: settings.ocrRecognitionMode)
            ?? .accurate
        guard recognitionMode != .off else { return }
        cancelAllOCRTasks()
        var didClearExistingText = false
        for index in items.indices where items[index].isImage {
            if items[index].ocrText != nil {
                items[index].ocrText = nil
                didClearExistingText = true
            }
            guard let image = image(for: items[index])?.cgImage(
                forProposedRect: nil,
                context: nil,
                hints: nil
            ) else {
                continue
            }
            performOCR(on: image, itemID: items[index].id)
        }
        if didClearExistingText {
            save()
        }
    }
}

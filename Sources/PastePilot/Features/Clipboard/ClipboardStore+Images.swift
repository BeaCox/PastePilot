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

    func captureImageIfAvailable() -> Bool {
        guard let image = clipboardImage() else {
            return false
        }
        let source = sourceApplication()
        let imageOrigin = imageOriginMetadata()
        return saveImage(
            image,
            source: source,
            remoteURL: imageOrigin.remoteURL,
            originalPath: imageOrigin.localPath,
            pasteboardChangeCount: pasteboard.changeCount
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
            items.filter {
                $0.imageDigest == processedImage.digest
            }.forEach(deleteImageFile)
            items.removeAll { $0.imageDigest == processedImage.digest }
            items.insert(item, at: 0)
            trimHistory(limit: settings.historyLimit)
            save()
            performOCR(on: ocrImage, itemID: id)
        case .failure(let error):
            if !(error is ClipboardImageProcessingError) {
                NSLog("PastePilot failed to save image: \(error)")
            }
        }
    }

    func clipboardImage() -> NSImage? {
        if let image = NSImage(pasteboard: pasteboard) {
            return image
        }
        guard let url = NSURL(from: pasteboard) as URL?,
              url.isFileURL,
              let type = UTType(filenameExtension: url.pathExtension),
              type.conforms(to: .image) else {
            return nil
        }
        return NSImage(contentsOf: url)
    }

    func isImageFile(_ url: URL) -> Bool {
        guard let type = UTType(filenameExtension: url.pathExtension) else {
            return false
        }
        return type.conforms(to: .image)
    }

    func imageOriginMetadata() -> (remoteURL: String?, localPath: String?) {
        let localURL = NSURL(from: pasteboard) as URL?
        let localPath: String?
        if let localURL,
           localURL.isFileURL,
           let type = UTType(filenameExtension: localURL.pathExtension),
           type.conforms(to: .image) {
            localPath = localURL.path
        } else {
            localPath = nil
        }

        if let html = pasteboard.string(forType: .html),
           let source = imageSourceFromHTML(html) {
            return (source, localPath)
        }

        let urlTypes = [
            NSPasteboard.PasteboardType.URL,
            NSPasteboard.PasteboardType(rawValue: "public.url"),
            NSPasteboard.PasteboardType(rawValue: "WebURLsWithTitlesPboardType")
        ]
        for type in urlTypes {
            guard let value = pasteboard.string(forType: type),
                  let url = URL(string: value),
                  ["http", "https"].contains(url.scheme?.lowercased()) else {
                continue
            }
            return (url.absoluteString, localPath)
        }

        return (nil, localPath)
    }

    func imageSourceFromHTML(_ html: String) -> String? {
        let pattern = #"<img\b[^>]*\bsrc\s*=\s*["']([^"']+)["']"#
        guard let regex = try? NSRegularExpression(
            pattern: pattern,
            options: [.caseInsensitive]
        ),
        let match = regex.firstMatch(
            in: html,
            range: NSRange(html.startIndex..., in: html)
        ),
        match.numberOfRanges > 1,
        let range = Range(match.range(at: 1), in: html) else {
            return nil
        }
        let rawValue = String(html[range])
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&quot;", with: "\"")
        guard let url = URL(string: rawValue),
              ["http", "https"].contains(url.scheme?.lowercased()) else {
            return nil
        }
        return url.absoluteString
    }

    func performOCR(on cgImage: CGImage, itemID: UUID) {
        Task {
            guard let text = await ocrService.recognizeText(in: cgImage),
                  let index = items.firstIndex(where: { $0.id == itemID }) else {
                return
            }
            items[index].ocrText = text
            save()
        }
    }
}

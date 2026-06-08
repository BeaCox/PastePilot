import AppKit
import CryptoKit
import Foundation
import UniformTypeIdentifiers

@MainActor
final class ClipboardStore: ObservableObject {
    @Published private(set) var items: [ClipboardItem] = []

    private let pasteboard: NSPasteboard
    private let settings: AppSettings
    private let historyRepository: HistoryRepository
    private let imageStore: ClipboardImageStore
    private let ocrService: any OCRService
    private var timer: Timer?
    private var lastChangeCount: Int
    private var ignoredContent: String?
    private var lastPurgeCheck: Date = .distantPast
    private static let sourcePasteboardType = NSPasteboard.PasteboardType(
        rawValue: "org.nspasteboard.source"
    )

    init(
        pasteboard: NSPasteboard = .general,
        settings: AppSettings = .shared,
        dataDirectoryURL: URL? = nil,
        ocrService: any OCRService = VisionOCRService()
    ) {
        let dataDirectoryURL = dataDirectoryURL ?? Self.defaultDataDirectoryURL
        self.pasteboard = pasteboard
        self.settings = settings
        self.historyRepository = HistoryRepository(dataDirectoryURL: dataDirectoryURL)
        self.imageStore = ClipboardImageStore(
            directoryURL: dataDirectoryURL.appendingPathComponent("images", isDirectory: true)
        )
        self.ocrService = ocrService
        self.lastChangeCount = pasteboard.changeCount
        load()
    }

    func startMonitoring() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 0.6, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.captureIfNeeded() }
        }
    }

    func stopMonitoring() {
        timer?.invalidate()
        timer = nil
    }

    func captureCurrentClipboard() {
        lastChangeCount = -1
        captureIfNeeded()
    }

    func acknowledgeCurrentClipboard() {
        lastChangeCount = pasteboard.changeCount
    }

    func copy(_ content: String) {
        ignoredContent = content
        pasteboard.clearContents()
        pasteboard.setString(content, forType: .string)
        lastChangeCount = pasteboard.changeCount
    }

    func copyImage(fileName: String) -> Bool {
        guard let image = imageStore.image(fileName: fileName) else { return false }
        pasteboard.clearContents()
        let succeeded = pasteboard.writeObjects([image])
        lastChangeCount = pasteboard.changeCount
        return succeeded
    }

    func copyFiles(_ urls: [URL]) -> Bool {
        let existingURLs = urls.filter { FileManager.default.fileExists(atPath: $0.path) }
        guard !existingURLs.isEmpty else { return false }
        pasteboard.clearContents()
        let succeeded = pasteboard.writeObjects(existingURLs as [NSURL])
        lastChangeCount = pasteboard.changeCount
        return succeeded
    }

    func copyRichText(for item: ClipboardItem) -> Bool {
        pasteboard.clearContents()
        if let base64 = item.richTextRTFBase64,
           let data = Data(base64Encoded: base64) {
            pasteboard.setData(data, forType: .rtf)
        }
        if let html = item.richTextHTML {
            pasteboard.setString(html, forType: .html)
        }
        pasteboard.setString(item.content, forType: .string)
        lastChangeCount = pasteboard.changeCount
        return item.hasRichText
    }

    func importFiles(_ urls: [URL]) {
        captureFiles(urls: urls, source: (nil, nil))
    }

    func image(for item: ClipboardItem) -> NSImage? {
        guard let fileName = item.imageFileName else { return nil }
        return imageStore.image(fileName: fileName)
    }

    func imagePath(fileName: String) -> String {
        imageStore.path(fileName: fileName)
    }

    func togglePinned(_ id: UUID) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        items[index].isPinned.toggle()
        save()
    }

    func delete(_ id: UUID) {
        if let item = items.first(where: { $0.id == id }) {
            deleteImageFile(for: item)
        }
        items.removeAll { $0.id == id }
        save()
    }

    func clearUnpinned() {
        items.filter { !$0.isPinned }.forEach(deleteImageFile)
        items.removeAll { !$0.isPinned }
        save()
    }

    func applyHistoryLimit(_ limit: Int) {
        trimHistory(limit: limit)
        save()
    }

    func purgeExpired() {
        let timeout = settings.historyTimeoutSeconds
        guard timeout > 0 else { return }
        let cutoff = Date().addingTimeInterval(-Double(timeout))
        let expired = items.filter { !$0.isPinned && $0.createdAt < cutoff }
        guard !expired.isEmpty else { return }
        expired.forEach(deleteImageFile)
        items.removeAll { !$0.isPinned && $0.createdAt < cutoff }
        save()
    }

    var dataDirectoryURL: URL {
        historyRepository.dataDirectoryURL
    }

    private func captureIfNeeded() {
        if Date().timeIntervalSince(lastPurgeCheck) > 60 {
            lastPurgeCheck = Date()
            purgeExpired()
        }
        guard pasteboard.changeCount != lastChangeCount else { return }
        lastChangeCount = pasteboard.changeCount
        if captureFileURLsIfAvailable() {
            return
        }
        if captureImageIfAvailable() {
            return
        }
        if captureRichTextIfAvailable() {
            return
        }
        guard let content = pasteboard.string(forType: .string)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !content.isEmpty else {
            return
        }
        if content == ignoredContent {
            ignoredContent = nil
            return
        }
        guard items.first?.content != content else { return }

        let analysis = ContentAnalyzer.analyze(content)
        let source = sourceApplication()
        guard !isIgnored(bundleIdentifier: source.bundleIdentifier) else { return }
        let wasPinned = items.first { $0.content == content }?.isPinned ?? false
        items.removeAll { $0.content == content }
        items.insert(
            ClipboardItem(
                content: content,
                kind: analysis.kind,
                isPinned: wasPinned,
                containsSensitiveData: analysis.containsSensitiveData,
                sourceAppName: source.name,
                sourceBundleIdentifier: source.bundleIdentifier
            ),
            at: 0
        )
        trimHistory(limit: settings.historyLimit)
        save()
    }

    private func captureFileURLsIfAvailable() -> Bool {
        let options: [NSPasteboard.ReadingOptionKey: Any] = [
            .urlReadingFileURLsOnly: true
        ]
        let urls = pasteboard.readObjects(
            forClasses: [NSURL.self],
            options: options
        ) as? [URL] ?? []
        guard !urls.isEmpty else { return false }
        captureFiles(urls: urls, source: sourceApplication())
        return true
    }

    private func captureFiles(
        urls: [URL],
        source: (name: String?, bundleIdentifier: String?)
    ) {
        let normalized = urls
            .filter(\.isFileURL)
            .map(\.standardizedFileURL)
        guard !normalized.isEmpty,
              !isIgnored(bundleIdentifier: source.bundleIdentifier) else {
            return
        }

        if normalized.count == 1,
           let url = normalized.first,
           isImageFile(url),
           captureImageFile(url, source: source) {
            return
        }

        let paths = normalized.map(\.path)
        guard items.first?.filePaths != paths else { return }
        let previous = items.first { $0.filePaths == paths }
        items.removeAll { $0.filePaths == paths }
        let content = normalized.map(\.lastPathComponent).joined(separator: "\n")
        items.insert(
            ClipboardItem(
                content: content,
                kind: .file,
                isPinned: previous?.isPinned ?? false,
                sourceAppName: source.name,
                sourceBundleIdentifier: source.bundleIdentifier,
                filePaths: paths
            ),
            at: 0
        )
        trimHistory(limit: settings.historyLimit)
        save()
    }

    private func captureImageFile(
        _ url: URL,
        source: (name: String?, bundleIdentifier: String?)
    ) -> Bool {
        guard let image = NSImage(contentsOf: url) else { return false }
        return saveImage(
            image,
            source: source,
            remoteURL: nil,
            originalPath: url.path
        )
    }

    private func captureRichTextIfAvailable() -> Bool {
        let rtfData = pasteboard.data(forType: .rtf)
        let html = pasteboard.string(forType: .html)
        guard rtfData != nil || html != nil else { return false }

        let attributedString: NSAttributedString?
        if let rtfData {
            attributedString = try? NSAttributedString(
                data: rtfData,
                options: [.documentType: NSAttributedString.DocumentType.rtf],
                documentAttributes: nil
            )
        } else if let html,
                  let data = html.data(using: .utf8) {
            attributedString = try? NSAttributedString(
                data: data,
                options: [.documentType: NSAttributedString.DocumentType.html],
                documentAttributes: nil
            )
        } else {
            attributedString = nil
        }

        let plainText = attributedString?.string
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let plainText, !plainText.isEmpty else { return false }
        let source = sourceApplication()
        guard !isIgnored(bundleIdentifier: source.bundleIdentifier) else { return true }
        let rtfBase64 = rtfData?.base64EncodedString()
        guard items.first?.content != plainText
                || items.first?.richTextRTFBase64 != rtfBase64
                || items.first?.richTextHTML != html else {
            return true
        }

        let previous = items.first {
            $0.content == plainText && $0.kind == .richText
        }
        items.removeAll {
            $0.content == plainText && $0.kind == .richText
        }
        items.insert(
            ClipboardItem(
                content: plainText,
                kind: .richText,
                isPinned: previous?.isPinned ?? false,
                sourceAppName: source.name,
                sourceBundleIdentifier: source.bundleIdentifier,
                richTextRTFBase64: rtfBase64,
                richTextHTML: html
            ),
            at: 0
        )
        trimHistory(limit: settings.historyLimit)
        save()
        return true
    }

    private func captureImageIfAvailable() -> Bool {
        guard let image = clipboardImage() else {
            return false
        }
        let source = sourceApplication()
        let imageOrigin = imageOriginMetadata()
        return saveImage(
            image,
            source: source,
            remoteURL: imageOrigin.remoteURL,
            originalPath: imageOrigin.localPath
        )
    }

    private func saveImage(
        _ image: NSImage,
        source: (name: String?, bundleIdentifier: String?),
        remoteURL: String?,
        originalPath: String?
    ) -> Bool {
        guard let pngData = pngData(for: image),
              pngData.count <= settings.imageSizeLimitMB * 1_024 * 1_024 else {
            return false
        }
        let digest = SHA256.hash(data: pngData).map { String(format: "%02x", $0) }.joined()
        guard items.first?.imageDigest != digest else { return true }

        guard !isIgnored(bundleIdentifier: source.bundleIdentifier) else { return true }
        let id = UUID()
        let fileName = "\(id.uuidString).png"
        do {
            try imageStore.save(pngData, fileName: fileName)
        } catch {
            NSLog("PastePilot failed to save image: \(error)")
            return false
        }

        let pixelSize = imagePixelSize(image)
        let wasPinned = items.first { $0.imageDigest == digest }?.isPinned ?? false
        let item = ClipboardItem(
            id: id,
            content: "Image %d × %d".localized(pixelSize.width, pixelSize.height),
            kind: .image,
            isPinned: wasPinned,
            sourceAppName: source.name,
            sourceBundleIdentifier: source.bundleIdentifier,
            imageFileName: fileName,
            imageWidth: pixelSize.width,
            imageHeight: pixelSize.height,
            imageByteCount: pngData.count,
            imageDigest: digest,
            imageSourceURL: remoteURL,
            imageOriginalPath: originalPath,
            filePaths: originalPath.map { [$0] }
        )
        items.filter { $0.imageDigest == digest }.forEach(deleteImageFile)
        items.removeAll { $0.imageDigest == digest }
        items.insert(item, at: 0)
        trimHistory(limit: settings.historyLimit)
        save()
        performOCR(on: image, itemID: id)
        return true
    }

    private func clipboardImage() -> NSImage? {
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

    private func isImageFile(_ url: URL) -> Bool {
        guard let type = UTType(filenameExtension: url.pathExtension) else {
            return false
        }
        return type.conforms(to: .image)
    }

    private func imageOriginMetadata() -> (remoteURL: String?, localPath: String?) {
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

    private func imageSourceFromHTML(_ html: String) -> String? {
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

    private func pngData(for image: NSImage) -> Data? {
        guard let tiffData = image.tiffRepresentation,
              let representation = NSBitmapImageRep(data: tiffData) else {
            return nil
        }
        return representation.representation(using: .png, properties: [:])
    }

    private func imagePixelSize(_ image: NSImage) -> (width: Int, height: Int) {
        guard let representation = image.representations.max(by: {
            $0.pixelsWide * $0.pixelsHigh < $1.pixelsWide * $1.pixelsHigh
        }) else {
            return (Int(image.size.width), Int(image.size.height))
        }
        return (representation.pixelsWide, representation.pixelsHigh)
    }

    private func sourceApplication() -> (name: String?, bundleIdentifier: String?) {
        let pasteboardBundleIdentifier = pasteboard.string(forType: Self.sourcePasteboardType)
        let frontmostApplication = NSWorkspace.shared.frontmostApplication
        let bundleIdentifier = pasteboardBundleIdentifier
            ?? frontmostApplication?.bundleIdentifier

        if let bundleIdentifier {
            let runningName = NSRunningApplication
                .runningApplications(withBundleIdentifier: bundleIdentifier)
                .first?
                .localizedName
            let installedName = NSWorkspace.shared
                .urlForApplication(withBundleIdentifier: bundleIdentifier)
                .flatMap { Bundle(url: $0) }?
                .object(forInfoDictionaryKey: "CFBundleName") as? String
            return (runningName ?? installedName, bundleIdentifier)
        }

        return (
            frontmostApplication?.localizedName,
            frontmostApplication?.bundleIdentifier
        )
    }

    private func isIgnored(bundleIdentifier: String?) -> Bool {
        guard let bundleIdentifier else { return false }
        return settings.ignoredBundleIdentifierSet.contains(bundleIdentifier)
    }

    private func sortItems() {
        items.sort { $0.createdAt > $1.createdAt }
    }

    private func trimHistory(limit: Int) {
        let pinned = items.filter(\.isPinned)
        let recent = items.filter { !$0.isPinned }.prefix(max(1, limit))
        let retainedIDs = Set((pinned + recent).map(\.id))
        items.filter { !retainedIDs.contains($0.id) }.forEach(deleteImageFile)
        items = items.filter { retainedIDs.contains($0.id) }
        sortItems()
    }

    private func load() {
        let result = historyRepository.load()
        items = result.items
        switch result.source {
        case .primary:
            removeOrphanedImages()
        case .backup:
            NSLog("PastePilot recovered clipboard history from backup")
            save()
            removeOrphanedImages()
        case .unrecoverable:
            NSLog("PastePilot could not decode clipboard history or its backup")
        case .empty:
            break
        }
        sortItems()
        purgeExpired()
    }

    private func removeOrphanedImages() {
        imageStore.removeOrphans(
            retaining: Set(items.compactMap(\.imageFileName))
        )
    }

    private func save() {
        do {
            try historyRepository.save(items)
        } catch {
            NSLog("PastePilot failed to save history: \(error)")
        }
    }

    private func deleteImageFile(for item: ClipboardItem) {
        guard let fileName = item.imageFileName else { return }
        imageStore.delete(fileName: fileName)
    }

    private func performOCR(on image: NSImage, itemID: UUID) {
        guard let cgImage = image.cgImage(
            forProposedRect: nil, context: nil, hints: nil
        ) else { return }

        Task {
            guard let text = await ocrService.recognizeText(in: cgImage),
                  let index = items.firstIndex(where: { $0.id == itemID }) else {
                return
            }
            items[index].ocrText = text
            save()
        }
    }

    private static var defaultDataDirectoryURL: URL {
        FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        )[0].appendingPathComponent("PastePilot", isDirectory: true)
    }
}

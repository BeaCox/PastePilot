import AppKit
import CryptoKit
import Foundation
import UniformTypeIdentifiers

@MainActor
final class ClipboardStore: ObservableObject {
    @Published private(set) var items: [ClipboardItem] = []

    private let pasteboard: NSPasteboard
    private let persistenceURL: URL
    private let imagesDirectoryURL: URL
    private var timer: Timer?
    private var lastChangeCount: Int
    private var ignoredContent: String?
    private static let sourcePasteboardType = NSPasteboard.PasteboardType(
        rawValue: "org.nspasteboard.source"
    )

    init(pasteboard: NSPasteboard = .general) {
        self.pasteboard = pasteboard
        self.lastChangeCount = pasteboard.changeCount
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        persistenceURL = support
            .appendingPathComponent("PastePilot", isDirectory: true)
            .appendingPathComponent("history.json")
        imagesDirectoryURL = persistenceURL
            .deletingLastPathComponent()
            .appendingPathComponent("images", isDirectory: true)
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

    func copy(_ content: String) {
        ignoredContent = content
        pasteboard.clearContents()
        pasteboard.setString(content, forType: .string)
        lastChangeCount = pasteboard.changeCount
    }

    func copyImage(fileName: String) -> Bool {
        let url = imageURL(fileName: fileName)
        guard let image = NSImage(contentsOf: url) else { return false }
        pasteboard.clearContents()
        let succeeded = pasteboard.writeObjects([image])
        lastChangeCount = pasteboard.changeCount
        return succeeded
    }

    func image(for item: ClipboardItem) -> NSImage? {
        guard let fileName = item.imageFileName else { return nil }
        return NSImage(contentsOf: imageURL(fileName: fileName))
    }

    func imagePath(fileName: String) -> String {
        imageURL(fileName: fileName).path
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

    var dataDirectoryURL: URL {
        persistenceURL.deletingLastPathComponent()
    }

    private func captureIfNeeded() {
        guard pasteboard.changeCount != lastChangeCount else { return }
        lastChangeCount = pasteboard.changeCount
        if captureImageIfAvailable() {
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
        trimHistory(limit: AppSettings.shared.historyLimit)
        save()
    }

    private func captureImageIfAvailable() -> Bool {
        guard let image = clipboardImage(),
              let pngData = pngData(for: image),
              pngData.count <= AppSettings.shared.imageSizeLimitMB * 1_024 * 1_024 else {
            return false
        }

        let digest = SHA256.hash(data: pngData).map { String(format: "%02x", $0) }.joined()
        guard items.first?.imageDigest != digest else { return true }

        let source = sourceApplication()
        guard !isIgnored(bundleIdentifier: source.bundleIdentifier) else { return true }
        let imageOrigin = imageOriginMetadata()
        let id = UUID()
        let fileName = "\(id.uuidString).png"
        do {
            try FileManager.default.createDirectory(
                at: imagesDirectoryURL,
                withIntermediateDirectories: true
            )
            try pngData.write(to: imageURL(fileName: fileName), options: .atomic)
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
            imageSourceURL: imageOrigin.remoteURL,
            imageOriginalPath: imageOrigin.localPath
        )
        items.filter { $0.imageDigest == digest }.forEach(deleteImageFile)
        items.removeAll { $0.imageDigest == digest }
        items.insert(item, at: 0)
        trimHistory(limit: AppSettings.shared.historyLimit)
        save()
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
        return AppSettings.shared.ignoredBundleIdentifierSet.contains(bundleIdentifier)
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
        guard let data = try? Data(contentsOf: persistenceURL),
              let decoded = decodeItems(from: data) else {
            return
        }
        items = decoded
        sortItems()
    }

    private func decodeItems(from data: Data) -> [ClipboardItem]? {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode([ClipboardItem].self, from: data)
    }

    private func save() {
        do {
            try FileManager.default.createDirectory(
                at: persistenceURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            try encoder.encode(items).write(to: persistenceURL, options: .atomic)
        } catch {
            NSLog("PastePilot failed to save history: \(error)")
        }
    }

    private func imageURL(fileName: String) -> URL {
        imagesDirectoryURL.appendingPathComponent(fileName)
    }

    private func deleteImageFile(for item: ClipboardItem) {
        guard let fileName = item.imageFileName else { return }
        try? FileManager.default.removeItem(at: imageURL(fileName: fileName))
    }
}

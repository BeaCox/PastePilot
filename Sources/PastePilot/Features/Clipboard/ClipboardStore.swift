import AppKit
import Foundation

@MainActor
final class ClipboardStore: ObservableObject {
    @Published var items: [ClipboardItem] = []

    let pasteboard: NSPasteboard
    let settings: AppSettings
    let historyRepository: HistoryRepository
    let historyWriteQueue: HistoryWriteQueue
    let imageStore: ClipboardImageStore
    let textStore: ClipboardTextStore
    let imageProcessingQueue: ClipboardImageProcessingQueue
    let textWriteQueue: ClipboardTextWriteQueue
    let pasteboardCaptureQueue: any ClipboardCapturing
    let ocrService: any OCRService
    let noticePoster: any PastePilotNoticePosting
    let logger: any PastePilotLogging
    var timer: Timer?
    var lastChangeCount: Int
    var pendingCaptureChangeCount: Int?
    var ocrTasksByItemID: [UUID: Task<Void, Never>] = [:]
    var ocrTaskTokensByItemID: [UUID: UUID] = [:]
    var ignoredContent: String?
    var lastPurgeCheck: Date = .distantPast
    var imageSaveGeneration = 0
    var discardAllImageSavesBeforeGeneration = 0
    var deletedImageDigestGenerations: [String: Int] = [:]
    let thumbnailCache = NSCache<NSString, NSImage>()

    init(
        pasteboard: NSPasteboard = .general,
        settings: AppSettings = .shared,
        dataDirectoryURL: URL? = nil,
        pasteboardCaptureQueue: any ClipboardCapturing = ClipboardCaptureQueue(),
        textWriteQueue: ClipboardTextWriteQueue = ClipboardTextWriteQueue(),
        ocrService: any OCRService = VisionOCRService(),
        noticePoster: any PastePilotNoticePosting = NotificationCenterPastePilotNoticePoster(),
        logger: any PastePilotLogging = NSLogPastePilotLogger()
    ) {
        let dataDirectoryURL = dataDirectoryURL ?? Self.defaultDataDirectoryURL
        let historyRepository = HistoryRepository(dataDirectoryURL: dataDirectoryURL)
        self.pasteboard = pasteboard
        self.settings = settings
        self.historyRepository = historyRepository
        self.historyWriteQueue = HistoryWriteQueue(repository: historyRepository)
        self.imageStore = ClipboardImageStore(
            directoryURL: dataDirectoryURL.appendingPathComponent("images", isDirectory: true)
        )
        self.textStore = ClipboardTextStore(
            directoryURL: dataDirectoryURL.appendingPathComponent("text", isDirectory: true)
        )
        self.imageProcessingQueue = ClipboardImageProcessingQueue()
        self.textWriteQueue = textWriteQueue
        self.pasteboardCaptureQueue = pasteboardCaptureQueue
        self.ocrService = ocrService
        self.noticePoster = noticePoster
        self.logger = logger
        self.lastChangeCount = pasteboard.changeCount
        load()
    }

    deinit {
        timer?.invalidate()
        ocrTasksByItemID.values.forEach { $0.cancel() }
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
        pendingCaptureChangeCount = nil
        lastChangeCount = -1
        captureIfNeeded()
    }

    func acknowledgeCurrentClipboard() {
        pendingCaptureChangeCount = nil
        lastChangeCount = pasteboard.changeCount
    }

    func copy(_ content: String) {
        ignoredContent = content
        pasteboard.clearContents()
        pasteboard.setString(content, forType: .string)
        pendingCaptureChangeCount = nil
        lastChangeCount = pasteboard.changeCount
    }

    func copyImage(fileName: String) -> Bool {
        guard let image = imageStore.image(fileName: fileName) else { return false }
        pasteboard.clearContents()
        let succeeded = pasteboard.writeObjects([image])
        pendingCaptureChangeCount = nil
        lastChangeCount = pasteboard.changeCount
        return succeeded
    }

    func copyFiles(_ urls: [URL]) -> Bool {
        let existingURLs = urls.filter { FileManager.default.fileExists(atPath: $0.path) }
        guard !existingURLs.isEmpty else { return false }
        pasteboard.clearContents()
        let succeeded = pasteboard.writeObjects(existingURLs as [NSURL])
        pendingCaptureChangeCount = nil
        lastChangeCount = pasteboard.changeCount
        return succeeded
    }

    func copyRichText(for item: ClipboardItem) -> Bool {
        let rtfData = item.richTextRTFBase64.flatMap {
            Data(base64Encoded: $0)
        }
        let html = item.richTextHTML
        guard rtfData != nil || html != nil else { return false }

        pasteboard.clearContents()
        var wroteRichText = false
        if let rtfData {
            wroteRichText = pasteboard.setData(rtfData, forType: .rtf)
                || wroteRichText
        }
        if let html {
            wroteRichText = pasteboard.setString(html, forType: .html)
                || wroteRichText
        }
        let wrotePlainText = pasteboard.setString(
            content(for: item) ?? item.content,
            forType: .string
        )
        if wroteRichText || wrotePlainText {
            pendingCaptureChangeCount = nil
            lastChangeCount = pasteboard.changeCount
        }
        return wroteRichText
    }

    func content(for item: ClipboardItem) -> String? {
        guard let fileName = item.contentFileName else {
            return item.content
        }
        return textStore.content(fileName: fileName)
    }

    func previewSnippet(
        for item: ClipboardItem,
        maxCharacters: Int,
        revealsSensitiveContent: Bool
    ) -> TextPreview.Snippet {
        guard let fileName = item.contentFileName,
              let prefix = textStore.prefix(
                fileName: fileName,
                maxCharacters: maxCharacters
              ) else {
            return TextPreview.detailSnippet(
                for: item,
                revealsSensitiveContent: revealsSensitiveContent,
                maxCharacters: maxCharacters
            )
        }

        let isTruncated = (item.contentCharacterCount ?? prefix.count) > prefix.count
        guard item.containsSensitiveData && !revealsSensitiveContent else {
            return TextPreview.Snippet(text: prefix, isTruncated: isTruncated)
        }
        return TextPreview.Snippet(
            text: ContentAnalyzer.redacted(prefix),
            isTruncated: isTruncated
        )
    }

    func externalContentSearchTargets() -> [(id: UUID, fileName: String)] {
        items.compactMap { item in
            guard let fileName = item.contentFileName else { return nil }
            return (item.id, fileName)
        }
    }

    func importFiles(_ urls: [URL]) {
        captureFiles(urls: urls, source: (nil, nil), pasteboardChangeCount: nil)
    }

    func image(for item: ClipboardItem) -> NSImage? {
        guard let fileName = item.imageFileName else { return nil }
        return imageStore.image(fileName: fileName)
    }

    func thumbnail(for item: ClipboardItem, pointSize: CGFloat = 22) -> NSImage? {
        guard let fileName = item.imageFileName else { return nil }
        let key = "\(fileName)-\(Int(pointSize))" as NSString
        if let image = thumbnailCache.object(forKey: key) {
            return image
        }
        guard let image = imageStore.thumbnail(
            fileName: fileName,
            pointSize: pointSize
        ) else {
            return nil
        }
        thumbnailCache.setObject(image, forKey: key)
        return image
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
            cancelOCR(for: item.id)
            deleteStoredResources(for: item)
        }
        items.removeAll { $0.id == id }
        save()
    }

    func clearUnpinned() {
        discardPendingImageSaves()
        let removedItems = items.filter { !$0.isPinned }
        cancelOCR(for: removedItems)
        removedItems.forEach(deleteStoredResources)
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
        cancelOCR(for: expired)
        expired.forEach(deleteStoredResources)
        items.removeAll { !$0.isPinned && $0.createdAt < cutoff }
        save()
    }

    func flushHistoryWrites() {
        historyWriteQueue.flush()
    }

    var dataDirectoryURL: URL {
        historyRepository.dataDirectoryURL
    }

    static var defaultDataDirectoryURL: URL {
        FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        )[0].appendingPathComponent("PastePilot", isDirectory: true)
    }
}

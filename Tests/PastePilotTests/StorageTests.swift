import AppKit
import Foundation
import Testing
@testable import PastePilot

@Suite(.serialized)
struct StorageTests {
    @Test
    func repositoryLoadsLegacyArrayAndWritesVersionedDocument() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let item = ClipboardItem(content: "legacy", kind: .text)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode([item]).write(
            to: directory.appendingPathComponent("history.json")
        )

        let repository = HistoryRepository(dataDirectoryURL: directory)
        let loadedLegacyItem = try #require(repository.load().items.first)
        #expect(loadedLegacyItem.id == item.id)
        #expect(loadedLegacyItem.content == item.content)
        #expect(loadedLegacyItem.kind == item.kind)

        try repository.save([item])
        let data = try Data(
            contentsOf: directory.appendingPathComponent("history.json")
        )
        let object = try #require(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        #expect(object["schemaVersion"] as? Int == 1)
        #expect(object["items"] as? [[String: Any]] != nil)
    }

    @Test
    func repositoryRecoversFromBackup() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let repository = HistoryRepository(dataDirectoryURL: directory)
        let first = ClipboardItem(content: "first", kind: .text)
        let second = ClipboardItem(content: "second", kind: .text)
        try repository.save([first])
        try repository.save([second])

        try Data("not json".utf8).write(
            to: directory.appendingPathComponent("history.json"),
            options: .atomic
        )

        let result = repository.load()
        let recoveredItem = try #require(result.items.first)
        #expect(recoveredItem.id == first.id)
        #expect(recoveredItem.content == first.content)
        guard case .backup = result.source else {
            Issue.record("Expected backup recovery")
            return
        }
    }

    @Test
    func repositoryOverwritesExistingBackup() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let repository = HistoryRepository(dataDirectoryURL: directory)
        let first = ClipboardItem(content: "first", kind: .text)
        let second = ClipboardItem(content: "second", kind: .text)
        let third = ClipboardItem(content: "third", kind: .text)

        try repository.save([first])
        try repository.save([second])
        try repository.save([third])

        try Data("not json".utf8).write(
            to: directory.appendingPathComponent("history.json"),
            options: .atomic
        )

        let recoveredItem = try #require(repository.load().items.first)
        #expect(recoveredItem.id == second.id)
        #expect(recoveredItem.content == second.content)
    }

    @Test
    func repositoryDistinguishesMissingAndUnrecoverableHistory() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let repository = HistoryRepository(dataDirectoryURL: directory)

        guard case .empty = repository.load().source else {
            Issue.record("Expected an empty repository")
            return
        }

        try Data("not json".utf8).write(
            to: directory.appendingPathComponent("history.json")
        )
        guard case .unrecoverable = repository.load().source else {
            Issue.record("Expected unrecoverable history")
            return
        }
    }

    @Test
    func imageStoreRemovesOnlyOrphanedFiles() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let imageStore = ClipboardImageStore(
            directoryURL: directory.appendingPathComponent("images")
        )
        try imageStore.save(Data("keep".utf8), fileName: "keep.png")
        try imageStore.save(Data("remove".utf8), fileName: "remove.png")

        imageStore.removeOrphans(retaining: ["keep.png"])

        #expect(
            FileManager.default.fileExists(
                atPath: imageStore.path(fileName: "keep.png")
            )
        )
        #expect(
            !FileManager.default.fileExists(
                atPath: imageStore.path(fileName: "remove.png")
            )
        )
    }

    @Test
    func imageProcessingQueueEncodesAndSavesPNG() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let imageStore = ClipboardImageStore(
            directoryURL: directory.appendingPathComponent("images")
        )
        let writer = ClipboardImageProcessingQueue()
        let image = try makeTestImage(width: 3, height: 2)

        let processedImage = try await withCheckedThrowingContinuation { continuation in
            writer.encodeAndSave(
                image,
                fileName: "queued.png",
                imageStore: imageStore,
                sizeLimitBytes: 1_000_000
            ) { result in
                continuation.resume(with: result)
            }
        }

        #expect(processedImage.fileName == "queued.png")
        #expect(processedImage.width == 3)
        #expect(processedImage.height == 2)
        #expect(processedImage.byteCount > 0)
        #expect(!processedImage.digest.isEmpty)
        #expect(
            FileManager.default.fileExists(
                atPath: imageStore.path(fileName: "queued.png")
            )
        )
    }

    @Test
    func historyWriteQueuePersistsAfterFlush() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let repository = HistoryRepository(dataDirectoryURL: directory)
        let writer = HistoryWriteQueue(repository: repository)
        let item = ClipboardItem(content: "queued", kind: .text)

        writer.save([item])
        writer.flush()

        let loadedItem = try #require(repository.load().items.first)
        #expect(loadedItem.id == item.id)
        #expect(loadedItem.content == item.content)
    }

    @Test
    func historyWriteQueueFlushWritesOnlyLatestPendingSnapshot() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let repository = HistoryRepository(dataDirectoryURL: directory)
        let writer = HistoryWriteQueue(
            repository: repository,
            debounceInterval: .seconds(60)
        )
        let first = ClipboardItem(content: "first", kind: .text)
        let second = ClipboardItem(content: "second", kind: .text)

        writer.save([first])
        writer.save([second])
        writer.flush()

        let loadedItem = try #require(repository.load().items.first)
        #expect(loadedItem.id == second.id)
        #expect(loadedItem.content == second.content)
        #expect(
            !FileManager.default.fileExists(
                atPath: directory.appendingPathComponent("history.backup.json").path
            )
        )
    }

    @Test
    @MainActor
    func plainTextCapturePreservesOriginalWhitespace() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let pasteboard = NSPasteboard(
            name: NSPasteboard.Name("PastePilotTests.\(UUID().uuidString)")
        )
        let store = ClipboardStore(
            pasteboard: pasteboard,
            dataDirectoryURL: directory,
            ocrService: StubOCRService()
        )
        let originalContent = "  git status --short\n"

        pasteboard.clearContents()
        pasteboard.setString(originalContent, forType: .string)
        store.captureCurrentClipboard()

        let item = try await waitForCapturedItem(in: store)
        #expect(item.content == originalContent)
        #expect(item.kind == .command)
        store.flushHistoryWrites()
    }

    @Test
    @MainActor
    func captureTimeoutDoesNotAcknowledgeChangeAndAllowsRetry() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let pasteboard = NSPasteboard(
            name: NSPasteboard.Name("PastePilotTests.\(UUID().uuidString)")
        )
        let captureQueue = StubClipboardCaptureQueue(results: [
            .timeout,
            .payload(.text("retry text"))
        ])
        let store = ClipboardStore(
            pasteboard: pasteboard,
            dataDirectoryURL: directory,
            pasteboardCaptureQueue: captureQueue,
            ocrService: StubOCRService()
        )

        pasteboard.clearContents()
        pasteboard.setString("retry text", forType: .string)
        let changeCount = pasteboard.changeCount

        store.captureIfNeeded()
        await Task.yield()
        #expect(captureQueue.captureCalls == 1)
        #expect(store.lastChangeCount != changeCount)
        #expect(store.items.isEmpty)

        store.captureIfNeeded()
        await Task.yield()
        #expect(captureQueue.captureCalls == 2)
        #expect(store.lastChangeCount == changeCount)
        #expect(store.items.first?.content == "retry text")
        store.flushHistoryWrites()
    }

    @Test
    @MainActor
    func clipboardStoreAppliesExpiryAndHistoryLimitWithInjectedStorage() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let defaultsName = "PastePilotStorageTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: defaultsName))
        defer { defaults.removePersistentDomain(forName: defaultsName) }
        defaults.removePersistentDomain(forName: defaultsName)
        let settings = AppSettings(defaults: defaults)
        settings.historyTimeoutSeconds = 60

        let pinned = ClipboardItem(
            content: "pinned",
            kind: .text,
            createdAt: Date(timeIntervalSinceNow: -3_600),
            isPinned: true
        )
        let expired = ClipboardItem(
            content: "expired",
            kind: .text,
            createdAt: Date(timeIntervalSinceNow: -3_600)
        )
        let recent = ClipboardItem(content: "recent", kind: .text)
        let repository = HistoryRepository(dataDirectoryURL: directory)
        try repository.save([recent, expired, pinned])

        let pasteboard = NSPasteboard(
            name: NSPasteboard.Name("PastePilotTests.\(UUID().uuidString)")
        )
        let store = ClipboardStore(
            pasteboard: pasteboard,
            settings: settings,
            dataDirectoryURL: directory,
            ocrService: StubOCRService()
        )
        #expect(Set(store.items.map(\.content)) == ["recent", "pinned"])
        store.flushHistoryWrites()

        let anotherRecent = ClipboardItem(
            content: "another",
            kind: .text,
            createdAt: Date(timeIntervalSinceNow: 1)
        )
        try repository.save([anotherRecent, recent, pinned])
        let reloadedStore = ClipboardStore(
            pasteboard: pasteboard,
            settings: settings,
            dataDirectoryURL: directory,
            ocrService: StubOCRService()
        )
        reloadedStore.applyHistoryLimit(1)
        #expect(Set(reloadedStore.items.map(\.content)) == ["another", "pinned"])
        reloadedStore.flushHistoryWrites()
    }

    @Test
    @MainActor
    func imageSaveResultIsDiscardedWhenClipboardHasChanged() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let pasteboard = NSPasteboard(
            name: NSPasteboard.Name("PastePilotTests.\(UUID().uuidString)")
        )
        let store = ClipboardStore(
            pasteboard: pasteboard,
            dataDirectoryURL: directory,
            ocrService: StubOCRService()
        )
        let imageStore = ClipboardImageStore(
            directoryURL: directory.appendingPathComponent("images")
        )
        try imageStore.save(Data("new".utf8), fileName: "new.png")

        let staleChangeCount = pasteboard.changeCount - 1

        store.finishSavingImage(
            .success(ProcessedClipboardImage(
                fileName: "new.png",
                byteCount: 3,
                digest: "digest",
                width: 3,
                height: 2
            )),
            id: UUID(),
            source: (nil, nil),
            remoteURL: nil,
            originalPath: nil,
            pasteboardChangeCount: staleChangeCount,
            ocrImage: try makeTestImage(width: 3, height: 2)
        )

        #expect(store.items.isEmpty)
        #expect(
            !FileManager.default.fileExists(
                atPath: imageStore.path(fileName: "new.png")
            )
        )
    }

    @Test
    @MainActor
    func duplicateImageSavePreservesPinnedStateAndRemovesOldFile() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let imageStore = ClipboardImageStore(
            directoryURL: directory.appendingPathComponent("images")
        )
        try imageStore.save(Data("old".utf8), fileName: "old.png")
        try imageStore.save(Data("new".utf8), fileName: "new.png")
        let store = ClipboardStore(
            pasteboard: NSPasteboard(
                name: NSPasteboard.Name("PastePilotTests.\(UUID().uuidString)")
            ),
            dataDirectoryURL: directory,
            ocrService: StubOCRService()
        )
        store.items = [
            ClipboardItem(content: "newer text", kind: .text),
            ClipboardItem(
                content: "old image",
                kind: .image,
                isPinned: true,
                imageFileName: "old.png",
                imageDigest: "same-digest"
            )
        ]

        store.finishSavingImage(
            .success(ProcessedClipboardImage(
                fileName: "new.png",
                byteCount: 3,
                digest: "same-digest",
                width: 3,
                height: 2
            )),
            id: UUID(),
            source: ("Preview", "com.apple.Preview"),
            remoteURL: "https://example.com/image.png",
            originalPath: nil,
            pasteboardChangeCount: nil,
            ocrImage: try makeTestImage(width: 3, height: 2)
        )

        let imageItem = try #require(store.items.first)
        #expect(imageItem.kind == .image)
        #expect(imageItem.isPinned)
        #expect(imageItem.imageFileName == "new.png")
        #expect(imageItem.imageSourceURL == "https://example.com/image.png")
        #expect(
            !FileManager.default.fileExists(
                atPath: imageStore.path(fileName: "old.png")
            )
        )
        #expect(
            FileManager.default.fileExists(
                atPath: imageStore.path(fileName: "new.png")
            )
        )
        store.flushHistoryWrites()
    }

    @Test
    @MainActor
    func ocrModeControlsImageTextRecognition() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let defaultsName = "PastePilotOCRTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: defaultsName))
        defer { defaults.removePersistentDomain(forName: defaultsName) }
        defaults.removePersistentDomain(forName: defaultsName)
        let settings = AppSettings(defaults: defaults)
        let store = ClipboardStore(
            pasteboard: NSPasteboard(
                name: NSPasteboard.Name("PastePilotTests.\(UUID().uuidString)")
            ),
            settings: settings,
            dataDirectoryURL: directory,
            ocrService: StubOCRService(result: "visible text")
        )
        let item = ClipboardItem(content: "image", kind: .image)
        store.items = [item]
        let image = try makeTestImage(width: 2, height: 2)

        settings.ocrRecognitionMode = OCRRecognitionMode.off.rawValue
        store.performOCR(on: image, itemID: item.id)
        try await Task.sleep(nanoseconds: 20_000_000)
        #expect(store.items.first?.ocrText == nil)

        settings.ocrRecognitionMode = OCRRecognitionMode.fast.rawValue
        settings.ocrLanguageMode = OCRLanguageMode.english.rawValue
        store.performOCR(on: image, itemID: item.id)
        for _ in 0..<100 where store.items.first?.ocrText == nil {
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        #expect(store.items.first?.ocrText == "visible text")
        store.flushHistoryWrites()
    }

    @Test
    @MainActor
    func cancelAllOCRTasksPreventsPendingOCRWrite() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let defaultsName = "PastePilotOCRCancelTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: defaultsName))
        defer { defaults.removePersistentDomain(forName: defaultsName) }
        defaults.removePersistentDomain(forName: defaultsName)
        let settings = AppSettings(defaults: defaults)
        settings.ocrRecognitionMode = OCRRecognitionMode.fast.rawValue
        let store = ClipboardStore(
            pasteboard: NSPasteboard(
                name: NSPasteboard.Name("PastePilotTests.\(UUID().uuidString)")
            ),
            settings: settings,
            dataDirectoryURL: directory,
            ocrService: DelayedStubOCRService(
                result: "stale text",
                delayNanoseconds: 80_000_000
            )
        )
        let item = ClipboardItem(content: "image", kind: .image)
        store.items = [item]

        store.performOCR(on: try makeTestImage(width: 2, height: 2), itemID: item.id)
        #expect(store.ocrTasksByItemID[item.id] != nil)
        store.cancelAllOCRTasks()

        try await Task.sleep(nanoseconds: 120_000_000)
        #expect(store.items.first?.ocrText == nil)
        #expect(store.ocrTasksByItemID.isEmpty)
    }

    private func makeTemporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("PastePilotTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        return directory
    }

    @MainActor
    private func waitForCapturedItem(in store: ClipboardStore) async throws -> ClipboardItem {
        for _ in 0..<100 {
            if let item = store.items.first {
                return item
            }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        return try #require(store.items.first)
    }

    private func makeTestImage(width: Int, height: Int) throws -> CGImage {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let context = try #require(
            CGContext(
                data: nil,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: width * 4,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )
        )
        context.setFillColor(NSColor.systemBlue.cgColor)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return try #require(context.makeImage())
    }
}

private struct StubOCRService: OCRService {
    var result: String?

    init(result: String? = nil) {
        self.result = result
    }

    func recognizeText(
        in image: CGImage,
        recognitionMode: OCRRecognitionMode,
        languageMode: OCRLanguageMode
    ) async -> String? {
        result
    }
}

private struct DelayedStubOCRService: OCRService {
    var result: String?
    var delayNanoseconds: UInt64

    func recognizeText(
        in image: CGImage,
        recognitionMode: OCRRecognitionMode,
        languageMode: OCRLanguageMode
    ) async -> String? {
        try? await Task.sleep(nanoseconds: delayNanoseconds)
        return result
    }
}

private enum StubCaptureResult {
    case timeout
    case payload(ClipboardCaptureSnapshot.Payload?)
}

private final class StubClipboardCaptureQueue: ClipboardCapturing {
    private var results: [StubCaptureResult]
    private(set) var captureCalls = 0

    init(results: [StubCaptureResult]) {
        self.results = results
    }

    func capture(
        pasteboard: NSPasteboard,
        changeCount: Int,
        completion: @escaping (ClipboardCaptureSnapshot?) -> Void
    ) {
        captureCalls += 1
        guard !results.isEmpty else {
            completion(nil)
            return
        }
        switch results.removeFirst() {
        case .timeout:
            completion(nil)
        case .payload(let payload):
            completion(ClipboardCaptureSnapshot(
                changeCount: changeCount,
                sourceBundleIdentifier: nil,
                payload: payload
            ))
        }
    }
}

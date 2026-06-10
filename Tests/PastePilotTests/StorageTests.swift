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

    private func makeTemporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("PastePilotTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        return directory
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
    func recognizeText(in image: CGImage) async -> String? {
        nil
    }
}

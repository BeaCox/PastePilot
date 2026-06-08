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
}

private struct StubOCRService: OCRService {
    func recognizeText(in image: CGImage) async -> String? {
        nil
    }
}

import AppKit
import Foundation
import Testing
import UniformTypeIdentifiers
@testable import PastePilot

@Suite(.serialized)
struct ClipboardStorageLifecycleTests {
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
        settings.historyTimeoutSeconds = 3_600

        let pinned = ClipboardItem(
            content: "pinned",
            kind: .text,
            createdAt: Date(timeIntervalSinceNow: -7_200),
            isPinned: true
        )
        let expired = ClipboardItem(
            content: "expired",
            kind: .text,
            createdAt: Date(timeIntervalSinceNow: -7_200)
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
    func expiringHistoryDeletesExternalizedTextFiles() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let defaultsName = "PastePilotExpiryTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: defaultsName))
        defer { defaults.removePersistentDomain(forName: defaultsName) }
        defaults.removePersistentDomain(forName: defaultsName)
        let settings = AppSettings(defaults: defaults)
        settings.historyTimeoutSeconds = 3_600

        let textStore = ClipboardTextStore(
            directoryURL: directory.appendingPathComponent("text", isDirectory: true)
        )
        let fileName = "expired.txt"
        try textStore.save("expired external text", fileName: fileName)
        let expired = ClipboardItem(
            content: "expired external text",
            kind: .text,
            createdAt: Date(timeIntervalSinceNow: -7_200),
            contentFileName: fileName
        )
        let repository = HistoryRepository(dataDirectoryURL: directory)
        try repository.save([expired])

        let store = ClipboardStore(
            pasteboard: NSPasteboard(
                name: NSPasteboard.Name("PastePilotTests.\(UUID().uuidString)")
            ),
            settings: settings,
            dataDirectoryURL: directory,
            ocrService: StubOCRService()
        )

        #expect(store.items.isEmpty)
        #expect(textStore.content(fileName: fileName) == nil)
        store.flushHistoryWrites()
    }

    @Test
    @MainActor
    func textSaveResultIsDiscardedWhenClipboardHasChanged() throws {
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
        let fileName = "stale.txt"
        try store.textStore.save("stale large text", fileName: fileName)
        let processedText = ProcessedClipboardText(
            content: "stale large text",
            fileName: fileName,
            characterCount: 16,
            lineCount: 1,
            byteCount: 16,
            digest: ContentDigest.sha256Hex(for: "stale large text")
        )
        let staleChangeCount = pasteboard.changeCount - 1

        store.finishCapturingText(
            processedText,
            originalContent: "stale large text",
            id: UUID(),
            kind: .text,
            containsSensitiveData: false,
            source: (nil, nil),
            richTextRTFBase64: nil,
            richTextHTML: nil,
            pasteboardChangeCount: staleChangeCount
        )

        #expect(store.items.isEmpty)
        #expect(store.textStore.content(fileName: fileName) == nil)
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
    func clearingHistoryCancelsPendingImageSave() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let imageStore = ClipboardImageStore(
            directoryURL: directory.appendingPathComponent("images")
        )
        try imageStore.save(Data("new".utf8), fileName: "new.png")
        let store = ClipboardStore(
            pasteboard: NSPasteboard(
                name: NSPasteboard.Name("PastePilotTests.\(UUID().uuidString)")
            ),
            dataDirectoryURL: directory,
            ocrService: StubOCRService()
        )
        let saveGeneration = store.imageSaveGeneration

        store.clearUnpinned()
        store.finishSavingImage(
            .success(ProcessedClipboardImage(
                fileName: "new.png",
                byteCount: 3,
                digest: "new-digest",
                width: 3,
                height: 2
            )),
            id: UUID(),
            source: (nil, nil),
            remoteURL: nil,
            originalPath: nil,
            pasteboardChangeCount: nil,
            ocrImage: try makeTestImage(width: 3, height: 2),
            imageSaveGeneration: saveGeneration
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
    func deletingDuplicateImageCancelsPendingReplacementSave() throws {
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
        let oldItem = ClipboardItem(
            content: "old image",
            kind: .image,
            imageFileName: "old.png",
            imageDigest: "same-digest"
        )
        store.items = [oldItem]
        let saveGeneration = store.imageSaveGeneration

        store.delete(oldItem.id)
        store.finishSavingImage(
            .success(ProcessedClipboardImage(
                fileName: "new.png",
                byteCount: 3,
                digest: "same-digest",
                width: 3,
                height: 2
            )),
            id: UUID(),
            source: (nil, nil),
            remoteURL: nil,
            originalPath: nil,
            pasteboardChangeCount: nil,
            ocrImage: try makeTestImage(width: 3, height: 2),
            imageSaveGeneration: saveGeneration
        )

        #expect(store.items.isEmpty)
        #expect(
            !FileManager.default.fileExists(
                atPath: imageStore.path(fileName: "new.png")
            )
        )
    }
}

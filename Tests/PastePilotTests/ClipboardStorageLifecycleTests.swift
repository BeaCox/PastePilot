import AppKit
import Foundation
import Testing
import UniformTypeIdentifiers
@testable import PastePilot

@Suite(.serialized)
struct ClipboardStorageLifecycleTests {
    @Test
    @MainActor
    func historySaveFailurePostsNoticeThroughInjectedPoster() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let blockedDataDirectory = directory.appendingPathComponent("blocked")
        try Data("not a directory".utf8).write(to: blockedDataDirectory)
        let noticePoster = CapturingNoticePoster()
        let store = ClipboardStore(
            pasteboard: NSPasteboard(
                name: NSPasteboard.Name("PastePilotTests.\(UUID().uuidString)")
            ),
            dataDirectoryURL: blockedDataDirectory,
            ocrService: StubOCRService(),
            noticePoster: noticePoster,
            logger: SilentPastePilotLogger()
        )
        store.items = [ClipboardItem(content: "unsaved", kind: .text)]

        store.save()
        store.flushHistoryWrites()

        #expect(
            noticePoster.notices.contains(
                PastePilotNotice(
                    "History could not be saved".localized,
                    style: .error
                )
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
    func togglingPinnedReordersStoreItems() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let old = ClipboardItem(
            content: "old",
            kind: .text,
            createdAt: Date(timeIntervalSince1970: 1)
        )
        let new = ClipboardItem(
            content: "new",
            kind: .text,
            createdAt: Date(timeIntervalSince1970: 2)
        )
        let store = ClipboardStore(
            pasteboard: NSPasteboard(
                name: NSPasteboard.Name("PastePilotTests.\(UUID().uuidString)")
            ),
            dataDirectoryURL: directory,
            ocrService: StubOCRService()
        )
        store.items = [new, old]

        store.togglePinned(old.id)

        #expect(store.items.map(\.content) == ["old", "new"])
        store.flushHistoryWrites()
    }

    @Test
    @MainActor
    func textExternalizationFailurePostsNoticeAndKeepsInlineContent() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try Data("not a directory".utf8).write(
            to: directory.appendingPathComponent("text")
        )
        let noticePoster = CapturingNoticePoster()
        let store = ClipboardStore(
            pasteboard: NSPasteboard(
                name: NSPasteboard.Name("PastePilotTests.\(UUID().uuidString)")
            ),
            dataDirectoryURL: directory,
            ocrService: StubOCRService(),
            noticePoster: noticePoster,
            logger: SilentPastePilotLogger()
        )
        let content = String(
            repeating: "large clipboard text\n",
            count: ClipboardTextStore.externalizationByteLimit / 8
        )

        store.captureText(content, source: (nil, nil))

        let item = try await waitForCapturedItem(in: store)
        #expect(item.content == content)
        #expect(item.contentFileName == nil)
        #expect(
            noticePoster.notices.contains(
                PastePilotNotice(
                    "Large text could not be saved separately".localized,
                    style: .warning
                )
            )
        )
        store.flushHistoryWrites()
    }

    @Test
    @MainActor
    func smallRichTextCapturePreservesFormattingPayload() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = ClipboardStore(
            pasteboard: NSPasteboard(
                name: NSPasteboard.Name("PastePilotTests.\(UUID().uuidString)")
            ),
            dataDirectoryURL: directory,
            ocrService: StubOCRService()
        )
        let rtfData = Data("{\\rtf1 Small rich text}".utf8)
        let html = "<strong>Small rich text</strong>"

        #expect(
            store.captureRichText(
                rtfData: rtfData,
                html: html,
                plainText: "Small rich text",
                source: (nil, nil)
            )
        )

        let item = try #require(store.items.first)
        #expect(item.kind == .richText)
        #expect(item.richTextRTFBase64 == rtfData.base64EncodedString())
        #expect(item.richTextHTML == html)
        #expect(ClipboardActionFactory.copyAction(for: item).id == "copy-rich-text")
        store.flushHistoryWrites()
    }

    @Test
    @MainActor
    func plainTextCaptureKeepsOlderRichTextWithSameContent() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = ClipboardStore(
            pasteboard: NSPasteboard(
                name: NSPasteboard.Name("PastePilotTests.\(UUID().uuidString)")
            ),
            dataDirectoryURL: directory,
            ocrService: StubOCRService()
        )
        let rtfData = Data("{\\rtf1 Formatted text}".utf8)
        let html = "<strong>Formatted text</strong>"

        #expect(
            store.captureRichText(
                rtfData: rtfData,
                html: html,
                plainText: "Formatted text",
                source: (nil, nil)
            )
        )
        let richTextItem = try #require(store.items.first)

        store.captureText("Intervening item", source: (nil, nil))
        store.captureText("Formatted text", source: (nil, nil))

        #expect(store.items.count == 3)
        #expect(store.items.first?.content == "Formatted text")
        #expect(store.items.first?.kind == .text)
        let retainedRichTextItem = try #require(
            store.items.first { $0.id == richTextItem.id }
        )
        #expect(retainedRichTextItem.kind == .richText)
        #expect(retainedRichTextItem.richTextRTFBase64 == rtfData.base64EncodedString())
        #expect(retainedRichTextItem.richTextHTML == html)
        store.flushHistoryWrites()
    }

    @Test
    @MainActor
    func oversizedRichTextCaptureKeepsPlainTextAndDropsFormattingPayload() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let noticePoster = CapturingNoticePoster()
        let store = ClipboardStore(
            pasteboard: NSPasteboard(
                name: NSPasteboard.Name("PastePilotTests.\(UUID().uuidString)")
            ),
            dataDirectoryURL: directory,
            ocrService: StubOCRService(),
            noticePoster: noticePoster
        )
        let html = "<p>" + String(
            repeating: "rich text payload ",
            count: RichTextPayloadPolicy.historyByteLimit / 4
        ) + "</p>"

        #expect(
            store.captureRichText(
                rtfData: nil,
                html: html,
                plainText: "Large formatted text",
                source: (nil, nil)
            )
        )

        let item = try #require(store.items.first)
        #expect(item.content == "Large formatted text")
        #expect(item.kind == .text)
        #expect(item.richTextRTFBase64 == nil)
        #expect(item.richTextHTML == nil)
        #expect(ClipboardActionFactory.copyAction(for: item).id == "copy")
        #expect(
            noticePoster.notices.contains(
                PastePilotNotice(
                    "Rich text formatting was too large to preserve".localized,
                    style: .warning
                )
            )
        )
        store.flushHistoryWrites()
    }

    @Test
    @MainActor
    func sensitiveTextCanBeRedactedBeforeHistoryStorage() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let defaultsName = "PastePilotSensitiveStorageTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: defaultsName))
        defer { defaults.removePersistentDomain(forName: defaultsName) }
        defaults.removePersistentDomain(forName: defaultsName)
        let settings = AppSettings(defaults: defaults)
        settings.sensitiveContentStoragePolicy =
            SensitiveContentStoragePolicy.storeRedacted.rawValue
        let store = ClipboardStore(
            pasteboard: NSPasteboard(
                name: NSPasteboard.Name("PastePilotTests.\(UUID().uuidString)")
            ),
            settings: settings,
            dataDirectoryURL: directory,
            ocrService: StubOCRService()
        )

        store.captureText("API_KEY=super-secret-value", source: (nil, nil))

        let item = try #require(store.items.first)
        #expect(item.content == "API_KEY=••••••••")
        #expect(!item.containsSensitiveData)
        #expect(store.content(for: item) == "API_KEY=••••••••")
        store.flushHistoryWrites()
    }

    @Test
    @MainActor
    func sensitiveContentCanBeSkippedBeforeHistoryStorage() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let defaultsName = "PastePilotSensitiveSkipTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: defaultsName))
        defer { defaults.removePersistentDomain(forName: defaultsName) }
        defaults.removePersistentDomain(forName: defaultsName)
        let settings = AppSettings(defaults: defaults)
        settings.sensitiveContentStoragePolicy =
            SensitiveContentStoragePolicy.skip.rawValue
        let store = ClipboardStore(
            pasteboard: NSPasteboard(
                name: NSPasteboard.Name("PastePilotTests.\(UUID().uuidString)")
            ),
            settings: settings,
            dataDirectoryURL: directory,
            ocrService: StubOCRService()
        )

        store.captureText("Authorization: Bearer abcdefghijklmnopqrstuvwxyz012345", source: (nil, nil))
        store.captureText("ordinary note", source: (nil, nil))

        #expect(store.items.map(\.content) == ["ordinary note"])
        store.flushHistoryWrites()
    }

    @Test
    @MainActor
    func customSensitivePatternCanStoreOriginalButHidePreview() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let defaultsName = "PastePilotCustomSensitiveOriginalTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: defaultsName))
        defer { defaults.removePersistentDomain(forName: defaultsName) }
        defaults.removePersistentDomain(forName: defaultsName)
        let settings = AppSettings(defaults: defaults)
        settings.customSensitivePatterns = "project raven"
        let store = ClipboardStore(
            pasteboard: NSPasteboard(
                name: NSPasteboard.Name("PastePilotTests.\(UUID().uuidString)")
            ),
            settings: settings,
            dataDirectoryURL: directory,
            ocrService: StubOCRService()
        )

        store.captureText("Project Raven launch notes", source: (nil, nil))

        let item = try #require(store.items.first)
        #expect(item.content == "Project Raven launch notes")
        #expect(item.containsSensitiveData)
        #expect(
            store.previewSnippet(
                for: item,
                maxCharacters: 200,
                revealsSensitiveContent: false
            ).text == "•••••••• launch notes"
        )
        #expect(
            store.previewSnippet(
                for: item,
                maxCharacters: 200,
                revealsSensitiveContent: true
            ).text == "Project Raven launch notes"
        )
        store.flushHistoryWrites()
    }

    @Test
    @MainActor
    func customSensitivePatternCanBeRedactedBeforeHistoryStorage() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let defaultsName = "PastePilotCustomSensitiveRedactTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: defaultsName))
        defer { defaults.removePersistentDomain(forName: defaultsName) }
        defaults.removePersistentDomain(forName: defaultsName)
        let settings = AppSettings(defaults: defaults)
        settings.sensitiveContentStoragePolicy =
            SensitiveContentStoragePolicy.storeRedacted.rawValue
        settings.customSensitivePatterns = "regex:customer-[0-9]+"
        let store = ClipboardStore(
            pasteboard: NSPasteboard(
                name: NSPasteboard.Name("PastePilotTests.\(UUID().uuidString)")
            ),
            settings: settings,
            dataDirectoryURL: directory,
            ocrService: StubOCRService()
        )

        store.captureText("customer-42 profile", source: (nil, nil))

        let item = try #require(store.items.first)
        #expect(item.content == "•••••••• profile")
        #expect(!item.containsSensitiveData)
        #expect(store.content(for: item) == "•••••••• profile")
        store.flushHistoryWrites()
    }

    @Test
    @MainActor
    func customSensitivePatternCanBeSkippedBeforeHistoryStorage() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let defaultsName = "PastePilotCustomSensitiveSkipTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: defaultsName))
        defer { defaults.removePersistentDomain(forName: defaultsName) }
        defaults.removePersistentDomain(forName: defaultsName)
        let settings = AppSettings(defaults: defaults)
        settings.sensitiveContentStoragePolicy =
            SensitiveContentStoragePolicy.skip.rawValue
        settings.customSensitivePatterns = "do not save"
        let store = ClipboardStore(
            pasteboard: NSPasteboard(
                name: NSPasteboard.Name("PastePilotTests.\(UUID().uuidString)")
            ),
            settings: settings,
            dataDirectoryURL: directory,
            ocrService: StubOCRService()
        )

        store.captureText("Do Not Save this item", source: (nil, nil))
        store.captureText("ordinary note", source: (nil, nil))

        #expect(store.items.map(\.content) == ["ordinary note"])
        store.flushHistoryWrites()
    }

    @Test
    @MainActor
    func redactedSensitiveRichTextDropsOriginalFormattingPayload() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let defaultsName = "PastePilotSensitiveRichTextTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: defaultsName))
        defer { defaults.removePersistentDomain(forName: defaultsName) }
        defaults.removePersistentDomain(forName: defaultsName)
        let settings = AppSettings(defaults: defaults)
        settings.sensitiveContentStoragePolicy =
            SensitiveContentStoragePolicy.storeRedacted.rawValue
        let store = ClipboardStore(
            pasteboard: NSPasteboard(
                name: NSPasteboard.Name("PastePilotTests.\(UUID().uuidString)")
            ),
            settings: settings,
            dataDirectoryURL: directory,
            ocrService: StubOCRService()
        )
        let rtfData = Data("{\\rtf1 API_KEY=super-secret-value}".utf8)
        let html = "<strong>API_KEY=super-secret-value</strong>"

        #expect(
            store.captureRichText(
                rtfData: rtfData,
                html: html,
                plainText: "API_KEY=super-secret-value",
                source: (nil, nil)
            )
        )

        let item = try #require(store.items.first)
        #expect(item.content == "API_KEY=••••••••")
        #expect(item.kind == .text)
        #expect(!item.containsSensitiveData)
        #expect(item.richTextRTFBase64 == nil)
        #expect(item.richTextHTML == nil)
        store.flushHistoryWrites()
    }

    @Test
    @MainActor
    func copyRichTextReportsSuccessOnlyWhenFormattingIsWritten() throws {
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
        let rtfData = Data("{\\rtf1 Formatted text}".utf8)
        let html = "<strong>Formatted text</strong>"
        let item = ClipboardItem(
            content: "Formatted text",
            kind: .richText,
            richTextRTFBase64: rtfData.base64EncodedString(),
            richTextHTML: html
        )

        #expect(store.copyRichText(for: item))
        #expect(pasteboard.data(forType: .rtf) == rtfData)
        #expect(pasteboard.string(forType: .html) == html)
        #expect(pasteboard.string(forType: .string) == "Formatted text")

        #expect(pasteboard.setString("Existing text", forType: .string))
        let invalidItem = ClipboardItem(
            content: "Broken rich text",
            kind: .richText,
            richTextRTFBase64: "not-base64"
        )

        #expect(!store.copyRichText(for: invalidItem))
        #expect(pasteboard.string(forType: .string) == "Existing text")
        store.flushHistoryWrites()
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
    func storageLimitDeletesOldestUnpinnedExternalizedTextFiles() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let defaultsName = "PastePilotStorageLimitTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: defaultsName))
        defer { defaults.removePersistentDomain(forName: defaultsName) }
        defaults.removePersistentDomain(forName: defaultsName)
        let settings = AppSettings(defaults: defaults)
        settings.storageLimitMB = 1

        let textStore = ClipboardTextStore(
            directoryURL: directory.appendingPathComponent("text", isDirectory: true)
        )
        let oldFileName = "old-large.txt"
        let newFileName = "new-large.txt"
        try textStore.save(String(repeating: "o", count: 700_000), fileName: oldFileName)
        try textStore.save(String(repeating: "n", count: 700_000), fileName: newFileName)
        let oldItem = ClipboardItem(
            content: "old",
            kind: .text,
            createdAt: Date(timeIntervalSinceNow: -10),
            contentFileName: oldFileName
        )
        let newItem = ClipboardItem(
            content: "new",
            kind: .text,
            createdAt: Date(timeIntervalSinceNow: -5),
            contentFileName: newFileName
        )
        let repository = HistoryRepository(dataDirectoryURL: directory)
        try repository.save([oldItem, newItem])

        let store = ClipboardStore(
            pasteboard: NSPasteboard(
                name: NSPasteboard.Name("PastePilotTests.\(UUID().uuidString)")
            ),
            settings: settings,
            dataDirectoryURL: directory,
            ocrService: StubOCRService()
        )

        #expect(store.items.map(\.content) == ["new"])
        #expect(textStore.content(fileName: oldFileName) == nil)
        #expect(textStore.content(fileName: newFileName) != nil)
        #expect(store.estimatedRetainedStorageByteCount() <= 1_024 * 1_024)
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
            digest: ContentDigest.sha256Hex(for: "stale large text"),
            externalizationFailed: false
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
    func imageSaveFailurePostsNoticeThroughInjectedPoster() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let noticePoster = CapturingNoticePoster()
        let store = ClipboardStore(
            pasteboard: NSPasteboard(
                name: NSPasteboard.Name("PastePilotTests.\(UUID().uuidString)")
            ),
            dataDirectoryURL: directory,
            ocrService: StubOCRService(),
            noticePoster: noticePoster
        )

        store.finishSavingImage(
            .failure(ClipboardImageProcessingError.exceedsSizeLimit),
            id: UUID(),
            source: (nil, nil),
            remoteURL: nil,
            originalPath: nil,
            pasteboardChangeCount: nil,
            ocrImage: try makeTestImage(width: 3, height: 2)
        )

        #expect(
            noticePoster.notices.contains(
                PastePilotNotice(
                    "Image exceeds the size limit".localized,
                    style: .warning
                )
            )
        )
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
        store.flushHistoryWrites()
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
        store.flushHistoryWrites()
    }
}

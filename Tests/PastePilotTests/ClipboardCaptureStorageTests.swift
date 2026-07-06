import AppKit
import Foundation
import Testing
import UniformTypeIdentifiers
@testable import PastePilot

@Suite(.serialized)
struct ClipboardCaptureStorageTests {
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
    func concealedPasteboardTypeIsIgnoredBeforeCapture() async throws {
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
        let concealedType = NSPasteboard.PasteboardType(
            rawValue: "org.nspasteboard.ConcealedType"
        )

        pasteboard.clearContents()
        pasteboard.setString("password=secret", forType: .string)
        pasteboard.setString("", forType: concealedType)
        let changeCount = pasteboard.changeCount
        store.captureCurrentClipboard()

        try await waitForClipboardAcknowledgement(
            in: store,
            changeCount: changeCount
        )
        #expect(store.items.isEmpty)
        store.flushHistoryWrites()
    }

    @Test
    @MainActor
    func ignoreNextCopySkipsOneChangedPasteboardItem() async throws {
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

        store.ignoreNextCopy()
        pasteboard.clearContents()
        pasteboard.setString("skip this", forType: .string)
        let skippedChangeCount = pasteboard.changeCount
        store.captureIfNeeded()

        try await waitForClipboardAcknowledgement(
            in: store,
            changeCount: skippedChangeCount
        )
        #expect(store.items.isEmpty)

        pasteboard.clearContents()
        pasteboard.setString("capture this", forType: .string)
        store.captureIfNeeded()

        let item = try await waitForCapturedItem(in: store)
        #expect(item.content == "capture this")
        store.flushHistoryWrites()
    }

    @Test
    @MainActor
    func largeTextCaptureExternalizesOriginalContent() async throws {
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
        let originalContent = String(
            repeating: "large clipboard text\n",
            count: ClipboardTextStore.externalizationByteLimit / 8
        )

        pasteboard.clearContents()
        pasteboard.setString(originalContent, forType: .string)
        store.captureCurrentClipboard()

        let item = try await waitForCapturedItem(in: store)
        let fileName = try #require(item.contentFileName)
        #expect(item.content.count == TextPreview.initialDetailCharacterLimit)
        #expect(item.contentDigest == ContentDigest.sha256Hex(for: originalContent))
        #expect(item.contentCharacterCount == originalContent.count)
        #expect(store.content(for: item) == originalContent)

        let copyMessage = ClipboardActionFactory.perform(
            ClipboardActionFactory.copyAction(for: item),
            using: store
        )
        #expect(copyMessage == "Copied: %@".localized("Copy Original".localized))
        #expect(pasteboard.string(forType: .string) == originalContent)

        store.delete(item.id)
        #expect(
            !FileManager.default.fileExists(
                atPath: directory
                    .appendingPathComponent("text", isDirectory: true)
                    .appendingPathComponent(fileName)
                    .path
            )
        )
        store.flushHistoryWrites()
    }

    @Test
    @MainActor
    func loadingLargeLegacyTextExternalizesContent() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let originalContent = String(
            repeating: "legacy clipboard text\n",
            count: ClipboardTextStore.externalizationByteLimit / 8
        )
        let legacyItem = ClipboardItem(content: originalContent, kind: .text)
        let repository = HistoryRepository(dataDirectoryURL: directory)
        try repository.save([legacyItem])

        let store = ClipboardStore(
            pasteboard: NSPasteboard(
                name: NSPasteboard.Name("PastePilotTests.\(UUID().uuidString)")
            ),
            dataDirectoryURL: directory,
            ocrService: StubOCRService()
        )

        let item = try #require(store.items.first)
        let fileName = try #require(item.contentFileName)
        #expect(item.id == legacyItem.id)
        #expect(item.content.count == TextPreview.initialDetailCharacterLimit)
        #expect(item.contentDigest == ContentDigest.sha256Hex(for: originalContent))
        #expect(store.content(for: item) == originalContent)
        #expect(
            FileManager.default.fileExists(
                atPath: directory
                    .appendingPathComponent("text", isDirectory: true)
                    .appendingPathComponent(fileName)
                    .path
            )
        )
        store.flushHistoryWrites()
    }

    @Test
    @MainActor
    func duplicateLargeTextCaptureUsesDigestAndPreservesPinnedState() async throws {
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
        let originalContent = String(
            repeating: "duplicate large clipboard text\n",
            count: ClipboardTextStore.externalizationByteLimit / 8
        )
        let oldFileName = "old-large.txt"
        try store.textStore.save(originalContent, fileName: oldFileName)
        let oldItem = ClipboardItem(
            content: TextPreview.clippedText(
                from: originalContent,
                maxCharacters: TextPreview.initialDetailCharacterLimit
            ).text,
            kind: .text,
            isPinned: true,
            contentFileName: oldFileName,
            contentDigest: ContentDigest.sha256Hex(for: originalContent),
            contentCharacterCount: originalContent.count,
            contentLineCount: originalContent.reduce(1) { count, character in
                character.isNewline ? count + 1 : count
            },
            contentByteCount: originalContent.utf8.count
        )
        store.items = [oldItem]

        pasteboard.clearContents()
        pasteboard.setString(originalContent, forType: .string)
        store.captureCurrentClipboard()

        let newItem = try await waitForCapturedItem(in: store) { item in
            item.id != oldItem.id
        }
        #expect(store.items.count == 1)
        #expect(newItem.isPinned)
        #expect(newItem.contentDigest == oldItem.contentDigest)
        #expect(newItem.contentFileName != oldFileName)
        #expect(store.content(for: newItem) == originalContent)
        #expect(
            !FileManager.default.fileExists(
                atPath: store.textStore.directoryURL
                    .appendingPathComponent(oldFileName)
                    .path
            )
        )
        store.flushHistoryWrites()
    }

    @Test
    @MainActor
    func richTextCapturePreservesOriginalWhitespace() async throws {
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
        let originalContent = "  Formatted text\n"
        let attributed = NSAttributedString(
            string: originalContent,
            attributes: [.font: NSFont.systemFont(ofSize: 13)]
        )
        let rtfData = try #require(
            attributed.rtf(
                from: NSRange(location: 0, length: attributed.length),
                documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf]
            )
        )

        pasteboard.clearContents()
        pasteboard.setData(rtfData, forType: .rtf)
        store.captureCurrentClipboard()

        let item = try await waitForCapturedItem(in: store)
        #expect(item.content == originalContent)
        #expect(item.kind == .richText)
        store.flushHistoryWrites()
    }

    @Test
    @MainActor
    func captureSnapshotPreservesCapturedSourceApplication() throws {
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

        pasteboard.clearContents()
        pasteboard.setString("source app text", forType: .string)
        store.applyCaptureSnapshot(ClipboardCaptureSnapshot(
            changeCount: pasteboard.changeCount,
            sourceAppName: "Captured App",
            sourceBundleIdentifier: "com.example.CapturedApp",
            payload: .text("source app text")
        ))

        let item = try #require(store.items.first)
        #expect(item.sourceAppName == "Captured App")
        #expect(item.sourceBundleIdentifier == "com.example.CapturedApp")
        store.flushHistoryWrites()
    }

    @Test
    @MainActor
    func imageCaptureReadsPasteboardImageData() async throws {
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
        let image = try makeTestImage(width: 4, height: 3)
        let imageData = try #require(
            NSBitmapImageRep(cgImage: image)
                .representation(using: .png, properties: [:])
        )

        pasteboard.clearContents()
        pasteboard.setData(
            imageData,
            forType: NSPasteboard.PasteboardType(UTType.png.identifier)
        )
        store.captureCurrentClipboard()

        let item = try await waitForCapturedItem(in: store)
        #expect(item.kind == .image)
        #expect(item.imageWidth == 4)
        #expect(item.imageHeight == 3)
        let fileName = try #require(item.imageFileName)
        #expect(
            FileManager.default.fileExists(
                atPath: store.imagePath(fileName: fileName)
            )
        )
        store.flushHistoryWrites()
    }

    @Test
    @MainActor
    func imageCapturePrefersPNGRepresentation() async throws {
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
        let tiffImage = try makeTestImage(width: 9, height: 7)
        let pngImage = try makeTestImage(width: 4, height: 3)
        let tiffData = try #require(
            NSBitmapImageRep(cgImage: tiffImage)
                .representation(using: .tiff, properties: [:])
        )
        let pngData = try #require(
            NSBitmapImageRep(cgImage: pngImage)
                .representation(using: .png, properties: [:])
        )

        pasteboard.clearContents()
        pasteboard.setData(tiffData, forType: .tiff)
        pasteboard.setData(pngData, forType: .png)
        store.captureCurrentClipboard()

        let item = try await waitForCapturedItem(in: store)
        #expect(item.kind == .image)
        #expect(item.imageWidth == 4)
        #expect(item.imageHeight == 3)
        store.flushHistoryWrites()
    }

    @Test
    @MainActor
    func imageCaptureFallsBackWhenPreferredRepresentationIsInvalid() async throws {
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
        let tiffImage = try makeTestImage(width: 9, height: 7)
        let tiffData = try #require(
            NSBitmapImageRep(cgImage: tiffImage)
                .representation(using: .tiff, properties: [:])
        )

        pasteboard.clearContents()
        pasteboard.setData(Data("not a png".utf8), forType: .png)
        pasteboard.setData(tiffData, forType: .tiff)
        store.captureCurrentClipboard()

        let item = try await waitForCapturedItem(in: store)
        #expect(item.kind == .image)
        #expect(item.imageWidth == 9)
        #expect(item.imageHeight == 7)
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
}

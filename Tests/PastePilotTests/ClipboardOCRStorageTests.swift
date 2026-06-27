import AppKit
import Foundation
import Testing
import UniformTypeIdentifiers
@testable import PastePilot

@Suite(.serialized)
struct ClipboardOCRStorageTests {
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

    @Test
    @MainActor
    func rerunOCRForImagesRefreshesStoredImageText() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let defaultsName = "PastePilotOCRRerunTests.\(UUID().uuidString)"
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
            ocrService: StubOCRService(result: "new visible text")
        )
        let image = try makeTestImage(width: 2, height: 2)
        let imageData = try #require(
            NSBitmapImageRep(cgImage: image)
                .representation(using: .png, properties: [:])
        )
        try store.imageStore.save(imageData, fileName: "stored.png")
        let item = ClipboardItem(
            content: "image",
            kind: .image,
            imageFileName: "stored.png",
            ocrText: "old text"
        )
        store.items = [item]

        store.rerunOCRForImages()

        for _ in 0..<100 where store.items.first?.ocrText != "new visible text" {
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        #expect(store.items.first?.ocrText == "new visible text")
        store.flushHistoryWrites()
    }
}

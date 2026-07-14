import AppKit
import Foundation
import Testing
@testable import PastePilot

@Suite(.serialized)
struct ContentEnrichmentTests {
    @Test
    func linkMetadataParserPrefersOpenGraphAndDecodesHTML() throws {
        let html = """
        <html>
          <head>
            <title>Fallback title</title>
            <meta content="PastePilot &amp; Friends" property="og:title">
            <meta name='description' content=' A useful &#x2014; local tool. '>
            <meta property="og:site_name" content="Example Site">
          </head>
        </html>
        """

        let metadata = try #require(
            LinkMetadataHTMLParser.metadata(
                from: html,
                resolvedURL: URL(string: "https://example.com/final")!
            )
        )

        #expect(metadata.title == "PastePilot & Friends")
        #expect(metadata.summary == "A useful — local tool.")
        #expect(metadata.siteName == "Example Site")
        #expect(metadata.resolvedURL == "https://example.com/final")
    }

    @Test
    func linkMetadataOnlyAllowsCredentialFreeWebURLs() throws {
        #expect(
            URLSessionLinkMetadataService.isEligible(
                try #require(URL(string: "https://example.com/path"))
            )
        )
        #expect(
            !URLSessionLinkMetadataService.isEligible(
                try #require(URL(string: "ftp://example.com/file"))
            )
        )
        #expect(
            !URLSessionLinkMetadataService.isEligible(
                try #require(URL(string: "https://user:secret@example.com/private"))
            )
        )
    }

    @Test
    func barcodePolicyDeduplicatesAndBoundsStoredPayloads() {
        let repeated = DetectedBarcode(payload: " same ", symbology: "QR")
        let inputs = [repeated, repeated] + (0..<30).map {
            DetectedBarcode(payload: "value-\($0)", symbology: "QR")
        }

        let retained = DetectedBarcodePolicy.retained(inputs)

        #expect(retained.count == DetectedBarcodePolicy.maximumCount)
        #expect(retained.first?.payload == "same")
        #expect(Set(retained.map(\.payload)).count == retained.count)
    }

    @Test
    @MainActor
    func copiedURLFetchesMetadataOnlyAfterExplicitOptIn() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let defaultsName = "PastePilotLinkMetadataTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: defaultsName))
        defer { defaults.removePersistentDomain(forName: defaultsName) }
        defaults.removePersistentDomain(forName: defaultsName)
        let settings = AppSettings(defaults: defaults)
        let expectedMetadata = LinkMetadata(
            title: "PastePilot Home",
            summary: "Clipboard tools",
            siteName: "PastePilot",
            resolvedURL: "https://example.com/"
        )
        let store = ClipboardStore(
            pasteboard: NSPasteboard(
                name: NSPasteboard.Name("PastePilotTests.\(UUID().uuidString)")
            ),
            settings: settings,
            dataDirectoryURL: directory,
            linkMetadataService: StubLinkMetadataService(result: expectedMetadata),
            barcodeDetectionService: StubBarcodeDetectionService(result: [])
        )

        store.captureText(
            "https://example.com/first",
            source: (nil, nil)
        )
        try await Task.sleep(nanoseconds: 30_000_000)
        #expect(store.items.first?.linkMetadata == nil)

        settings.linkMetadataFetchingEnabled = true
        store.captureText(
            "https://example.com/second",
            source: (nil, nil)
        )
        for _ in 0..<100 where store.items.first?.linkMetadata == nil {
            try await Task.sleep(nanoseconds: 10_000_000)
        }

        #expect(store.items.first?.linkMetadata == expectedMetadata)
        #expect(
            MenuBarPopoverState.shortSearchMatches(
                try #require(store.items.first),
                query: ClipboardSearchQuery("Clipboard tools")
            )
        )
        store.flushHistoryWrites()
    }

    @Test
    @MainActor
    func localBarcodeDetectionStoresSearchesAndCopiesPayloads() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let pasteboard = NSPasteboard(
            name: NSPasteboard.Name("PastePilotTests.\(UUID().uuidString)")
        )
        let detected = [
            DetectedBarcode(payload: "https://example.com/qr", symbology: "QR"),
            DetectedBarcode(payload: "0123456789012", symbology: "EAN13")
        ]
        let store = ClipboardStore(
            pasteboard: pasteboard,
            dataDirectoryURL: directory,
            ocrService: StubOCRService(),
            linkMetadataService: StubLinkMetadataService(result: nil),
            barcodeDetectionService: StubBarcodeDetectionService(result: detected)
        )
        let item = ClipboardItem(
            content: "image",
            kind: .image,
            imageFileName: "stored.png"
        )
        store.items = [item]

        store.performBarcodeDetection(
            on: try makeTestImage(width: 2, height: 2),
            itemID: item.id
        )
        for _ in 0..<100 where store.items.first?.detectedBarcodes == nil {
            try await Task.sleep(nanoseconds: 10_000_000)
        }

        let enrichedItem = try #require(store.items.first)
        #expect(enrichedItem.detectedBarcodes == detected)
        #expect(ClipboardSearchQuery("has:qr").matchesFilters(enrichedItem))
        #expect(
            MenuBarPopoverState.shortSearchMatches(
                enrichedItem,
                query: ClipboardSearchQuery("0123456789012")
            )
        )

        let action = try #require(
            ClipboardActionFactory.actions(for: enrichedItem)
                .first { $0.id == "copy-barcode-content" }
        )
        _ = ClipboardActionFactory.perform(action, using: store)
        #expect(
            pasteboard.string(forType: .string)
                == "https://example.com/qr\n0123456789012"
        )
        store.flushHistoryWrites()
    }

    @Test
    @MainActor
    func sensitiveBarcodePayloadMarksImageForProtectedPreview() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let secret = "sk-1234567890abcdefghijklmnop"
        let store = ClipboardStore(
            pasteboard: NSPasteboard(
                name: NSPasteboard.Name("PastePilotTests.\(UUID().uuidString)")
            ),
            dataDirectoryURL: directory,
            ocrService: StubOCRService(),
            linkMetadataService: StubLinkMetadataService(result: nil),
            barcodeDetectionService: StubBarcodeDetectionService(
                result: [DetectedBarcode(payload: secret, symbology: "QR")]
            )
        )
        let item = ClipboardItem(content: "image", kind: .image)
        store.items = [item]

        store.performBarcodeDetection(
            on: try makeTestImage(width: 2, height: 2),
            itemID: item.id
        )
        for _ in 0..<100 where store.items.first?.detectedBarcodes == nil {
            try await Task.sleep(nanoseconds: 10_000_000)
        }

        #expect(store.items.first?.containsSensitiveData == true)
        #expect(store.items.first?.detectedBarcodes?.first?.payload == secret)
        store.flushHistoryWrites()
    }
}

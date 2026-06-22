import AppKit
import Foundation
import Testing
@testable import PastePilot

@Suite(.serialized)
struct PlainTextPasteServiceTests {
    @Test
    @MainActor
    func pastesPlainTextAndRestoresOriginalClipboard() async throws {
        let pasteboard = TestPasteboard()
        #expect(pasteboard.setString("Formatted text", forType: .string))
        #expect(pasteboard.setString("<b>Formatted text</b>", forType: .html))
        let originalTypes = Set(pasteboard.types ?? [])
        var pasteShortcutCount = 0
        var didComplete = false

        let service = PlainTextPasteService(
            pasteboard: pasteboard,
            isAccessibilityGranted: { true },
            postPasteShortcut: { pasteShortcutCount += 1 },
            restoreDelay: .milliseconds(10)
        )

        let result = service.paste {
            didComplete = true
        }

        #expect(result == .pasted)
        #expect(pasteShortcutCount == 1)
        #expect(pasteboard.string(forType: .string) == "Formatted text")
        #expect(pasteboard.string(forType: .html) == nil)

        #expect(await waitUntil { didComplete })
        #expect(Set(pasteboard.types ?? []) == originalTypes)
        #expect(
            pasteboard.string(forType: .html) == "<b>Formatted text</b>"
        )
    }

    @Test
    @MainActor
    func doesNotOverwriteClipboardChangedDuringPaste() async throws {
        let pasteboard = TestPasteboard()
        #expect(pasteboard.setString("Original", forType: .string))

        let service = PlainTextPasteService(
            pasteboard: pasteboard,
            isAccessibilityGranted: { true },
            postPasteShortcut: {
                pasteboard.clearContents()
                _ = pasteboard.setString("New copy", forType: .string)
            },
            restoreDelay: .milliseconds(10)
        )

        var didComplete = false
        #expect(
            service.paste {
                didComplete = true
            } == .pasted
        )
        #expect(await waitUntil { didComplete })
        #expect(pasteboard.string(forType: .string) == "New copy")
    }

    @Test
    @MainActor
    func requiresAccessibilityBeforeChangingClipboard() {
        let pasteboard = TestPasteboard()
        #expect(pasteboard.setString("Original", forType: .string))

        let service = PlainTextPasteService(
            pasteboard: pasteboard,
            isAccessibilityGranted: { false },
            postPasteShortcut: {}
        )

        #expect(service.paste(completion: {}) == .accessibilityRequired)
        #expect(pasteboard.string(forType: .string) == "Original")
    }

    @Test
    @MainActor
    func pastesPlainTextFromRTFWhenStringTypeIsMissing() async throws {
        let pasteboard = TestPasteboard()
        let attributed = NSAttributedString(
            string: "Rich text",
            attributes: [.font: NSFont.boldSystemFont(ofSize: 13)]
        )
        let rtfData = try #require(
            attributed.rtf(
                from: NSRange(location: 0, length: attributed.length),
                documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf]
            )
        )
        #expect(pasteboard.setData(rtfData, forType: .rtf))
        var didComplete = false

        let service = PlainTextPasteService(
            pasteboard: pasteboard,
            isAccessibilityGranted: { true },
            postPasteShortcut: {},
            restoreDelay: .milliseconds(10)
        )

        #expect(service.paste { didComplete = true } == .pasted)
        #expect(pasteboard.string(forType: .string) == "Rich text")
        #expect(pasteboard.data(forType: .rtf) == nil)

        #expect(await waitUntil { didComplete })
        #expect(pasteboard.string(forType: .string) == nil)
        #expect(pasteboard.data(forType: .rtf) == rtfData)
    }

    @Test
    @MainActor
    func pastesPlainTextFromHTMLWhenStringTypeIsMissing() async {
        let pasteboard = TestPasteboard()
        let html = "<p><strong>HTML</strong> text</p>"
        #expect(pasteboard.setString(html, forType: .html))
        var didComplete = false

        let service = PlainTextPasteService(
            pasteboard: pasteboard,
            isAccessibilityGranted: { true },
            postPasteShortcut: {},
            restoreDelay: .milliseconds(10)
        )

        #expect(service.paste { didComplete = true } == .pasted)
        #expect(
            pasteboard.string(forType: .string)?
                .trimmingCharacters(in: .whitespacesAndNewlines) == "HTML text"
        )
        #expect(pasteboard.string(forType: .html) == nil)

        #expect(await waitUntil { didComplete })
        #expect(pasteboard.string(forType: .string) == nil)
        #expect(pasteboard.string(forType: .html) == html)
    }

    @Test
    @MainActor
    func restoresOriginalClipboardWhenTemporaryWriteFails() {
        let pasteboard = TestPasteboard()
        #expect(pasteboard.setString("Original", forType: .string))
        #expect(pasteboard.setString("<b>Original</b>", forType: .html))
        pasteboard.failStringWrites = true
        var pasteShortcutCount = 0

        let service = PlainTextPasteService(
            pasteboard: pasteboard,
            isAccessibilityGranted: { true },
            postPasteShortcut: { pasteShortcutCount += 1 }
        )

        #expect(service.paste(completion: {}) == .pasteboardWriteFailed)
        #expect(pasteShortcutCount == 0)
        #expect(pasteboard.string(forType: .string) == "Original")
        #expect(pasteboard.string(forType: .html) == "<b>Original</b>")
    }

    @Test
    @MainActor
    func returnsBusyWhileRestoreIsPending() async {
        let pasteboard = TestPasteboard()
        #expect(pasteboard.setString("Original", forType: .string))
        var didComplete = false

        let service = PlainTextPasteService(
            pasteboard: pasteboard,
            isAccessibilityGranted: { true },
            postPasteShortcut: {},
            restoreDelay: .milliseconds(50)
        )

        #expect(service.paste { didComplete = true } == .pasted)
        #expect(service.paste(completion: {}) == .busy)
        #expect(await waitUntil { didComplete })
    }

    @MainActor
    private func waitUntil(
        timeout: Duration = .seconds(5),
        condition: () -> Bool
    ) async -> Bool {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        while !condition() {
            guard clock.now < deadline else { return false }
            try? await Task.sleep(for: .milliseconds(10))
        }
        return true
    }
}

@MainActor
private final class TestPasteboard: PlainTextPasteboard {
    private(set) var changeCount = 0
    private var items: [NSPasteboardItem] = []
    var failStringWrites = false

    var types: [NSPasteboard.PasteboardType]? {
        items.first?.types
    }

    var pasteboardItems: [NSPasteboardItem]? {
        items
    }

    @discardableResult
    func clearContents() -> Int {
        let oldChangeCount = changeCount
        items = []
        changeCount += 1
        return oldChangeCount
    }

    func setString(_ string: String, forType dataType: NSPasteboard.PasteboardType) -> Bool {
        guard !failStringWrites else { return false }
        if items.isEmpty {
            items = [NSPasteboardItem()]
        }
        let didSet = items[0].setString(string, forType: dataType)
        if didSet {
            changeCount += 1
        }
        return didSet
    }

    func setData(_ data: Data, forType dataType: NSPasteboard.PasteboardType) -> Bool {
        if items.isEmpty {
            items = [NSPasteboardItem()]
        }
        let didSet = items[0].setData(data, forType: dataType)
        if didSet {
            changeCount += 1
        }
        return didSet
    }

    func string(forType dataType: NSPasteboard.PasteboardType) -> String? {
        items.first?.string(forType: dataType)
    }

    func data(forType dataType: NSPasteboard.PasteboardType) -> Data? {
        items.first?.data(forType: dataType)
    }

    func writeItems(_ items: [NSPasteboardItem]) -> Bool {
        self.items = items
        changeCount += 1
        return true
    }
}

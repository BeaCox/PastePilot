import AppKit
import Foundation
import Testing
@testable import PastePilot

@Suite(.serialized)
struct PlainTextPasteServiceTests {
    @Test
    @MainActor
    func pastesPlainTextAndRestoresOriginalClipboard() async throws {
        let pasteboard = NSPasteboard(
            name: NSPasteboard.Name("PastePilotPlainTextTests.\(UUID().uuidString)")
        )
        pasteboard.clearContents()
        pasteboard.setString("Formatted text", forType: .string)
        pasteboard.setString("<b>Formatted text</b>", forType: .html)
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

        try await Task.sleep(for: .milliseconds(30))
        #expect(didComplete)
        #expect(Set(pasteboard.types ?? []) == originalTypes)
        #expect(
            pasteboard.string(forType: .html) == "<b>Formatted text</b>"
        )
    }

    @Test
    @MainActor
    func doesNotOverwriteClipboardChangedDuringPaste() async throws {
        let pasteboard = NSPasteboard(
            name: NSPasteboard.Name("PastePilotPlainTextTests.\(UUID().uuidString)")
        )
        pasteboard.clearContents()
        pasteboard.setString("Original", forType: .string)

        let service = PlainTextPasteService(
            pasteboard: pasteboard,
            isAccessibilityGranted: { true },
            postPasteShortcut: {
                pasteboard.clearContents()
                pasteboard.setString("New copy", forType: .string)
            },
            restoreDelay: .milliseconds(10)
        )

        #expect(service.paste(completion: {}) == .pasted)
        try await Task.sleep(for: .milliseconds(30))
        #expect(pasteboard.string(forType: .string) == "New copy")
    }

    @Test
    @MainActor
    func requiresAccessibilityBeforeChangingClipboard() {
        let pasteboard = NSPasteboard(
            name: NSPasteboard.Name("PastePilotPlainTextTests.\(UUID().uuidString)")
        )
        pasteboard.clearContents()
        pasteboard.setString("Original", forType: .string)

        let service = PlainTextPasteService(
            pasteboard: pasteboard,
            isAccessibilityGranted: { false },
            postPasteShortcut: {}
        )

        #expect(service.paste(completion: {}) == .accessibilityRequired)
        #expect(pasteboard.string(forType: .string) == "Original")
    }
}

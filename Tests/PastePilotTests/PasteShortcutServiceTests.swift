import Foundation
import Testing
@testable import PastePilot

@Suite(.serialized)
struct PasteShortcutServiceTests {
    @Test
    @MainActor
    func postsPasteShortcutAfterPermissionCheck() async {
        var pasteShortcutCount = 0
        let service = PasteShortcutService(
            isAccessibilityGranted: { true },
            postPasteShortcut: { pasteShortcutCount += 1 },
            pasteDelay: .milliseconds(10)
        )

        #expect(service.paste() == .pasted)
        #expect(pasteShortcutCount == 0)
        #expect(await waitUntil { pasteShortcutCount == 1 })
    }

    @Test
    @MainActor
    func requiresAccessibilityBeforePostingPasteShortcut() async {
        var pasteShortcutCount = 0
        let service = PasteShortcutService(
            isAccessibilityGranted: { false },
            postPasteShortcut: { pasteShortcutCount += 1 },
            pasteDelay: .milliseconds(10)
        )

        #expect(service.paste() == .accessibilityRequired)
        try? await Task.sleep(for: .milliseconds(30))
        #expect(pasteShortcutCount == 0)
    }

    @Test
    @MainActor
    func newerPasteRequestCancelsPendingShortcut() async {
        var pasteShortcutCount = 0
        let service = PasteShortcutService(
            isAccessibilityGranted: { true },
            postPasteShortcut: { pasteShortcutCount += 1 },
            pasteDelay: .milliseconds(30)
        )

        #expect(service.paste() == .pasted)
        try? await Task.sleep(for: .milliseconds(10))
        #expect(service.paste() == .pasted)
        try? await Task.sleep(for: .milliseconds(20))
        #expect(pasteShortcutCount == 0)
        #expect(await waitUntil { pasteShortcutCount == 1 })
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

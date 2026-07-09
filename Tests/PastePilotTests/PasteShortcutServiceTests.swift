import Foundation
import Testing
@testable import PastePilot

@Suite(.serialized)
struct PasteShortcutServiceTests {
    @Test
    @MainActor
    func postsPasteShortcutAfterPermissionCheck() async {
        var pasteShortcutCount = 0
        let sleeper = ControlledPasteSleep()
        let service = PasteShortcutService(
            isAccessibilityGranted: { true },
            postPasteShortcut: { pasteShortcutCount += 1 },
            sleep: { await sleeper.sleep($0) },
            pasteDelay: .milliseconds(10)
        )

        #expect(service.paste() == .pasted)
        #expect(pasteShortcutCount == 0)
        await sleeper.waitForPendingCount(1)
        sleeper.resumeAll()
        await Task.yield()
        #expect(pasteShortcutCount == 1)
    }

    @Test
    @MainActor
    func requiresAccessibilityBeforePostingPasteShortcut() async {
        var pasteShortcutCount = 0
        let sleeper = ControlledPasteSleep()
        let service = PasteShortcutService(
            isAccessibilityGranted: { false },
            postPasteShortcut: { pasteShortcutCount += 1 },
            sleep: { await sleeper.sleep($0) },
            pasteDelay: .milliseconds(10)
        )

        #expect(service.paste() == .accessibilityRequired)
        await Task.yield()
        #expect(pasteShortcutCount == 0)
        #expect(sleeper.pendingCount == 0)
    }

    @Test
    @MainActor
    func newerPasteRequestCancelsPendingShortcut() async {
        var pasteShortcutCount = 0
        let sleeper = ControlledPasteSleep()
        let service = PasteShortcutService(
            isAccessibilityGranted: { true },
            postPasteShortcut: { pasteShortcutCount += 1 },
            sleep: { await sleeper.sleep($0) },
            pasteDelay: .milliseconds(30)
        )

        #expect(service.paste() == .pasted)
        await sleeper.waitForPendingCount(1)
        #expect(service.paste() == .pasted)
        await sleeper.waitForPendingCount(2)
        sleeper.resumeAll()
        await Task.yield()
        await Task.yield()
        #expect(pasteShortcutCount == 1)
    }
}

@MainActor
private final class ControlledPasteSleep {
    private var continuations: [CheckedContinuation<Void, Never>] = []

    var pendingCount: Int {
        continuations.count
    }

    func sleep(_ duration: Duration) async {
        await withCheckedContinuation { continuation in
            continuations.append(continuation)
        }
    }

    func resumeAll() {
        let pendingContinuations = continuations
        continuations.removeAll(keepingCapacity: false)
        pendingContinuations.forEach { $0.resume() }
    }

    func waitForPendingCount(_ count: Int) async {
        while continuations.count < count {
            await Task.yield()
        }
    }
}

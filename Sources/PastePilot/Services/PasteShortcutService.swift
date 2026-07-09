import Carbon
import CoreGraphics
import Foundation

@MainActor
final class PasteShortcutService {
    enum Result: Equatable {
        case pasted
        case accessibilityRequired
    }

    private let isAccessibilityGranted: @MainActor () -> Bool
    private let postPasteShortcut: @MainActor () -> Void
    private let sleep: @MainActor (Duration) async -> Void
    private let pasteDelay: Duration
    private var pasteTask: Task<Void, Never>?

    init(
        isAccessibilityGranted: @escaping @MainActor () -> Bool = {
            EventPostingPermission.isGranted
        },
        postPasteShortcut: @escaping @MainActor () -> Void = {
            PasteShortcutService.postCommandV()
        },
        sleep: @escaping @MainActor (Duration) async -> Void = { duration in
            try? await Task.sleep(for: duration)
        },
        pasteDelay: Duration = .milliseconds(120)
    ) {
        self.isAccessibilityGranted = isAccessibilityGranted
        self.postPasteShortcut = postPasteShortcut
        self.sleep = sleep
        self.pasteDelay = pasteDelay
    }

    deinit {
        pasteTask?.cancel()
    }

    func paste() -> Result {
        guard isAccessibilityGranted() else {
            return .accessibilityRequired
        }

        pasteTask?.cancel()
        pasteTask = Task { @MainActor [weak self] in
            guard let self else { return }
            await sleep(pasteDelay)
            guard !Task.isCancelled else { return }
            postPasteShortcut()
            pasteTask = nil
        }
        return .pasted
    }

    nonisolated static func postCommandV() {
        guard let source = CGEventSource(stateID: .combinedSessionState),
              let keyDown = CGEvent(
                  keyboardEventSource: source,
                  virtualKey: CGKeyCode(kVK_ANSI_V),
                  keyDown: true
              ),
              let keyUp = CGEvent(
                  keyboardEventSource: source,
                  virtualKey: CGKeyCode(kVK_ANSI_V),
                  keyDown: false
              ) else {
            return
        }
        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand
        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)
    }
}

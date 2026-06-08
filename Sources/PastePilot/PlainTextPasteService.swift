import AppKit
import ApplicationServices
import Carbon

struct PasteboardSnapshot {
    private let items: [[NSPasteboard.PasteboardType: Data]]

    init(pasteboard: NSPasteboard) {
        items = (pasteboard.pasteboardItems ?? []).map { item in
            Dictionary(
                uniqueKeysWithValues: item.types.compactMap { type in
                    item.data(forType: type).map { (type, $0) }
                }
            )
        }
    }

    @discardableResult
    func restore(to pasteboard: NSPasteboard) -> Bool {
        pasteboard.clearContents()
        let pasteboardItems = items.map { values in
            let item = NSPasteboardItem()
            for (type, data) in values {
                item.setData(data, forType: type)
            }
            return item
        }
        return pasteboardItems.isEmpty || pasteboard.writeObjects(pasteboardItems)
    }
}

@MainActor
final class PlainTextPasteService {
    enum Result: Equatable {
        case pasted
        case noText
        case accessibilityRequired
        case pasteboardWriteFailed
        case busy
    }

    private let pasteboard: NSPasteboard
    private let isAccessibilityGranted: () -> Bool
    private let postPasteShortcut: () -> Void
    private let restoreDelay: Duration
    private var restoreTask: Task<Void, Never>?

    init(
        pasteboard: NSPasteboard = .general,
        isAccessibilityGranted: @escaping () -> Bool = {
            AXIsProcessTrusted()
        },
        postPasteShortcut: @escaping () -> Void = {
            PlainTextPasteService.postCommandV()
        },
        restoreDelay: Duration = .milliseconds(250)
    ) {
        self.pasteboard = pasteboard
        self.isAccessibilityGranted = isAccessibilityGranted
        self.postPasteShortcut = postPasteShortcut
        self.restoreDelay = restoreDelay
    }

    func paste(
        willWrite: () -> Void = {},
        completion: @escaping () -> Void
    ) -> Result {
        guard restoreTask == nil else {
            return .busy
        }
        guard isAccessibilityGranted() else {
            return .accessibilityRequired
        }
        guard let plainText = plainText(), !plainText.isEmpty else {
            return .noText
        }

        willWrite()
        let snapshot = PasteboardSnapshot(pasteboard: pasteboard)
        pasteboard.clearContents()
        guard pasteboard.setString(plainText, forType: .string) else {
            snapshot.restore(to: pasteboard)
            return .pasteboardWriteFailed
        }

        let temporaryChangeCount = pasteboard.changeCount
        postPasteShortcut()
        restoreTask = Task {
            try? await Task.sleep(for: restoreDelay)
            guard !Task.isCancelled else { return }
            if pasteboard.changeCount == temporaryChangeCount {
                snapshot.restore(to: pasteboard)
            }
            restoreTask = nil
            completion()
        }
        return .pasted
    }

    private func plainText() -> String? {
        if let text = pasteboard.string(forType: .string) {
            return text
        }
        if let data = pasteboard.data(forType: .rtf),
           let value = try? NSAttributedString(
               data: data,
               options: [.documentType: NSAttributedString.DocumentType.rtf],
               documentAttributes: nil
           ) {
            return value.string
        }
        if let html = pasteboard.string(forType: .html),
           let data = html.data(using: .utf8),
           let value = try? NSAttributedString(
               data: data,
               options: [.documentType: NSAttributedString.DocumentType.html],
               documentAttributes: nil
           ) {
            return value.string
        }
        return nil
    }

    nonisolated private static func postCommandV() {
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

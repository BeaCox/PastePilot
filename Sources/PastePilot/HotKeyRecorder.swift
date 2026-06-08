import AppKit
import Carbon
import SwiftUI

enum HotKeyFormatter {
    static func carbonModifiers(from flags: NSEvent.ModifierFlags) -> UInt32 {
        var modifiers: UInt32 = 0
        if flags.contains(.control) { modifiers |= UInt32(controlKey) }
        if flags.contains(.option) { modifiers |= UInt32(optionKey) }
        if flags.contains(.shift) { modifiers |= UInt32(shiftKey) }
        if flags.contains(.command) { modifiers |= UInt32(cmdKey) }
        return modifiers
    }

    static func display(keyCode: Int, modifiers: UInt32) -> String {
        var value = ""
        if modifiers & UInt32(controlKey) != 0 { value += "⌃" }
        if modifiers & UInt32(optionKey) != 0 { value += "⌥" }
        if modifiers & UInt32(shiftKey) != 0 { value += "⇧" }
        if modifiers & UInt32(cmdKey) != 0 { value += "⌘" }
        return value + keyName(keyCode)
    }

    private static func keyName(_ code: Int) -> String {
        let names: [Int: String] = [
            kVK_ANSI_A: "A", kVK_ANSI_B: "B", kVK_ANSI_C: "C",
            kVK_ANSI_D: "D", kVK_ANSI_E: "E", kVK_ANSI_F: "F",
            kVK_ANSI_G: "G", kVK_ANSI_H: "H", kVK_ANSI_I: "I",
            kVK_ANSI_J: "J", kVK_ANSI_K: "K", kVK_ANSI_L: "L",
            kVK_ANSI_M: "M", kVK_ANSI_N: "N", kVK_ANSI_O: "O",
            kVK_ANSI_P: "P", kVK_ANSI_Q: "Q", kVK_ANSI_R: "R",
            kVK_ANSI_S: "S", kVK_ANSI_T: "T", kVK_ANSI_U: "U",
            kVK_ANSI_V: "V", kVK_ANSI_W: "W", kVK_ANSI_X: "X",
            kVK_ANSI_Y: "Y", kVK_ANSI_Z: "Z",
            kVK_ANSI_0: "0", kVK_ANSI_1: "1", kVK_ANSI_2: "2",
            kVK_ANSI_3: "3", kVK_ANSI_4: "4", kVK_ANSI_5: "5",
            kVK_ANSI_6: "6", kVK_ANSI_7: "7", kVK_ANSI_8: "8",
            kVK_ANSI_9: "9", kVK_Space: "Space", kVK_Return: "↩",
            kVK_Tab: "⇥", kVK_Escape: "⎋", kVK_Delete: "⌫",
            kVK_ForwardDelete: "⌦", kVK_Home: "↖", kVK_End: "↘",
            kVK_PageUp: "⇞", kVK_PageDown: "⇟",
            kVK_LeftArrow: "←", kVK_RightArrow: "→",
            kVK_UpArrow: "↑", kVK_DownArrow: "↓",
            kVK_F1: "F1", kVK_F2: "F2", kVK_F3: "F3", kVK_F4: "F4",
            kVK_F5: "F5", kVK_F6: "F6", kVK_F7: "F7", kVK_F8: "F8",
            kVK_F9: "F9", kVK_F10: "F10", kVK_F11: "F11", kVK_F12: "F12"
        ]
        return names[code] ?? "Key \(code)"
    }
}

struct HotKeyRecorder: NSViewRepresentable {
    @Binding var keyCode: Int
    @Binding var modifiers: UInt32
    var defaultKeyCode = AppSettings.defaultOpenHotKeyCode
    var defaultModifiers = AppSettings.defaultOpenHotKeyModifiers
    var accessibilityLabel = "Open PastePilot Shortcut".localized

    func makeNSView(context: Context) -> HotKeyRecorderNSView {
        let view = HotKeyRecorderNSView()
        view.onChange = { code, flags in
            keyCode = code
            modifiers = flags
        }
        view.onReset = {
            keyCode = defaultKeyCode
            modifiers = defaultModifiers
        }
        view.setAccessibilityLabel(accessibilityLabel)
        update(view)
        return view
    }

    func updateNSView(_ nsView: HotKeyRecorderNSView, context: Context) {
        update(nsView)
    }

    private func update(_ view: HotKeyRecorderNSView) {
        view.shortcutText = HotKeyFormatter.display(
            keyCode: keyCode,
            modifiers: modifiers
        )
        view.setAccessibilityValue(view.shortcutText)
    }
}

final class HotKeyRecorderNSView: NSView {
    var onChange: ((Int, UInt32) -> Void)?
    var onReset: (() -> Void)?
    var shortcutText = "" {
        didSet { needsDisplay = true }
    }
    private var isRecording = false

    override var acceptsFirstResponder: Bool { true }
    override var intrinsicContentSize: NSSize { NSSize(width: 190, height: 34) }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        setAccessibilityHelp(
            "Press to record a new shortcut. Press Delete to restore the default.".localized
        )
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        isRecording = true
        needsDisplay = true
        setAccessibilityValue("Press a new shortcut…".localized)
    }

    override func resignFirstResponder() -> Bool {
        isRecording = false
        needsDisplay = true
        setAccessibilityValue(shortcutText)
        return super.resignFirstResponder()
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == UInt16(kVK_Escape) {
            window?.makeFirstResponder(nil)
            return
        }
        if event.keyCode == UInt16(kVK_Delete) {
            onReset?()
            window?.makeFirstResponder(nil)
            return
        }
        let modifiers = HotKeyFormatter.carbonModifiers(from: event.modifierFlags)
        guard modifiers != 0 else {
            NSSound.beep()
            return
        }
        onChange?(Int(event.keyCode), modifiers)
        window?.makeFirstResponder(nil)
    }

    override func draw(_ dirtyRect: NSRect) {
        let bounds = self.bounds.insetBy(dx: 1, dy: 1)
        let path = NSBezierPath(roundedRect: bounds, xRadius: 8, yRadius: 8)
        (isRecording
            ? NSColor.controlAccentColor.withAlphaComponent(0.12)
            : NSColor.controlBackgroundColor
        ).setFill()
        path.fill()
        (isRecording
            ? NSColor.controlAccentColor
            : NSColor.separatorColor
        ).setStroke()
        path.lineWidth = 1
        path.stroke()

        let text = isRecording ? "Press a new shortcut…".localized : shortcutText
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 14, weight: .medium),
            .foregroundColor: isRecording
                ? NSColor.controlAccentColor
                : NSColor.labelColor
        ]
        let size = text.size(withAttributes: attributes)
        text.draw(
            at: NSPoint(
                x: bounds.midX - size.width / 2,
                y: bounds.midY - size.height / 2
            ),
            withAttributes: attributes
        )
    }
}

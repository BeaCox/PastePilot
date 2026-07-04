import AppKit
import Carbon
import Foundation

extension AppDelegate {
    func registerPopoverKeyMonitor() {
        keyEventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard self?.popover?.isShown == true else { return event }
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)

            if flags == .command,
               let number = Self.shortcutNumber(for: event.keyCode) {
                Self.post(.copyIndex(number))
                return nil
            }

            if flags == .option,
               let number = Self.shortcutNumber(for: event.keyCode) {
                Self.post(.keyboard(.performAction(number)))
                return nil
            }

            if flags == .command {
                switch event.keyCode {
                case UInt16(kVK_ANSI_P):
                    Self.post(.keyboard(.togglePinned))
                    return nil
                case UInt16(kVK_Delete):
                    Self.post(.keyboard(.deleteSelected))
                    return nil
                case UInt16(kVK_ANSI_F), UInt16(kVK_ANSI_K):
                    Self.post(.keyboard(.focusSearch))
                    return nil
                case UInt16(kVK_ANSI_W):
                    Self.post(.keyboard(.close))
                    return nil
                default:
                    break
                }
            }

            if flags == [.command, .shift],
               event.keyCode == UInt16(kVK_Delete) {
                Self.post(.keyboard(.clearUnpinned))
                return nil
            }

            let command: PopoverKeyboardCommand?
            switch event.keyCode {
            case UInt16(kVK_UpArrow):
                command = .moveUp
            case UInt16(kVK_DownArrow):
                command = .moveDown
            case UInt16(kVK_Space):
                if let editor = self?.popover?.contentViewController?
                    .view.window?.firstResponder as? NSTextView,
                   !editor.string.isEmpty {
                    return event
                }
                command = .togglePreview
            case UInt16(kVK_Return), UInt16(kVK_ANSI_KeypadEnter):
                command = .copySelected
            case UInt16(kVK_Escape):
                command = .close
            default:
                command = nil
            }
            guard let command else { return event }
            Self.post(.keyboard(command))
            return nil
        }
    }

    func registerHotKey() {
        registerConfiguredHotKeys()
    }

    func registerConfiguredHotKeys() {
        guard installHotKeyHandler() else {
            unregisterHotKeys()
            return
        }
        unregisterHotKeys()
        settings.hotKeyRegistrationWarning = nil
        var failures: [GlobalHotKey] = []
        if !registerHotKey(
            .openPanel,
            keyCode: settings.hotKeyCode,
            modifiers: settings.hotKeyModifiers
        ) {
            failures.append(.openPanel)
        }
        if !registerHotKey(
            .pastePlainText,
            keyCode: settings.plainTextHotKeyCode,
            modifiers: settings.plainTextHotKeyModifiers
        ) {
            failures.append(.pastePlainText)
        }
        settings.hotKeyRegistrationWarning = Self.hotKeyRegistrationWarning(
            for: failures
        )
    }

    @discardableResult
    func registerHotKey(
        _ hotKey: GlobalHotKey,
        keyCode: Int,
        modifiers: UInt32
    ) -> Bool {
        let signature = OSType(0x50504C54) // PPLT
        let hotKeyID = EventHotKeyID(signature: signature, id: hotKey.rawValue)
        var reference: EventHotKeyRef?
        let status = RegisterEventHotKey(
            UInt32(keyCode),
            modifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &reference
        )
        if status == noErr, let reference {
            hotKeyRefs[hotKey] = reference
            return true
        } else {
            let message = hotKeyRegistrationFailureMessage(for: hotKey)
            NotificationCenter.default.postPastePilotNotice(
                PastePilotNotice(message, style: .warning)
            )
            NSLog(
                "PastePilot failed to register hot key \(hotKey.rawValue): \(status)"
            )
            return false
        }
    }

    func hotKeyRegistrationFailureMessage(for hotKey: GlobalHotKey) -> String {
        Self.hotKeyRegistrationFailureMessage(for: hotKey)
    }

    static func hotKeyRegistrationFailureMessage(for hotKey: GlobalHotKey) -> String {
        switch hotKey {
        case .openPanel:
            "Open PastePilot shortcut is already in use.".localized
        case .pastePlainText:
            "Paste as Plain Text shortcut is already in use.".localized
        }
    }

    static func hotKeyRegistrationWarning(for failures: [GlobalHotKey]) -> String? {
        let uniqueFailures = Array(Set(failures))
        guard !uniqueFailures.isEmpty else { return nil }
        if uniqueFailures.count == 1,
           let hotKey = uniqueFailures.first {
            return hotKeyRegistrationFailureMessage(for: hotKey)
        }
        return "Open PastePilot and Paste as Plain Text shortcuts are already in use.".localized
    }

    func unregisterHotKeys() {
        for reference in hotKeyRefs.values {
            UnregisterEventHotKey(reference)
        }
        hotKeyRefs.removeAll()
    }

    @discardableResult
    func installHotKeyHandler() -> Bool {
        guard hotKeyHandler == nil else { return true }
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: OSType(kEventHotKeyPressed)
        )
        let pointer = Unmanaged.passUnretained(self).toOpaque()
        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, userData in
                guard let event, let userData else { return noErr }
                var receivedID = EventHotKeyID()
                GetEventParameter(
                    event,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &receivedID
                )
                let delegate = Unmanaged<AppDelegate>.fromOpaque(userData).takeUnretainedValue()
                guard let hotKey = GlobalHotKey(rawValue: receivedID.id) else {
                    return noErr
                }
                Task { @MainActor in
                    switch hotKey {
                    case .openPanel:
                        delegate.togglePopover()
                    case .pastePlainText:
                        delegate.pasteAsPlainText()
                    }
                }
                return noErr
            },
            1,
            &eventType,
            pointer,
            &hotKeyHandler
        )
        guard status == noErr else {
            hotKeyHandler = nil
            handleHotKeyHandlerInstallationFailure(status)
            return false
        }
        return true
    }

    func handleHotKeyHandlerInstallationFailure(_ status: OSStatus) {
        let message = "Global shortcut listener could not be installed.".localized
        settings.hotKeyRegistrationWarning = message
        NotificationCenter.default.postPastePilotNotice(
            PastePilotNotice(message, style: .warning)
        )
        NSLog("PastePilot failed to install hot key handler: \(status)")
    }

    func pasteAsPlainText() {
        var didPauseMonitoring = false
        let result = plainTextPasteService.paste(
            willWrite: { [weak self] in
                guard let self, self.settings.monitoringEnabled else { return }
                self.store.stopMonitoring()
                didPauseMonitoring = true
            },
            completion: { [weak self] in
                guard let self else { return }
                self.store.acknowledgeCurrentClipboard()
                if self.settings.monitoringEnabled {
                    self.store.startMonitoring()
                }
            }
        )

        guard result != .pasted else { return }
        if didPauseMonitoring {
            store.acknowledgeCurrentClipboard()
            if settings.monitoringEnabled {
                store.startMonitoring()
            }
        }
        if result == .accessibilityRequired {
            showAccessibilityRequiredAlert()
        } else if let notice = Self.plainTextPasteFailureNotice(for: result) {
            NotificationCenter.default.postPastePilotNotice(notice)
        }
    }

    static func plainTextPasteFailureNotice(
        for result: PlainTextPasteService.Result
    ) -> PastePilotNotice? {
        switch result {
        case .pasted, .accessibilityRequired:
            nil
        case .noText:
            PastePilotNotice(
                "No text is available to paste as plain text.".localized,
                style: .warning
            )
        case .pasteboardWriteFailed:
            PastePilotNotice(
                "Plain text could not be prepared for pasting.".localized,
                style: .error
            )
        case .busy:
            PastePilotNotice(
                "Plain-text paste is already in progress.".localized,
                style: .warning
            )
        }
    }

    func showAccessibilityRequiredAlert() {
        guard !didShowAccessibilityAlert else { return }
        let now = Date()
        guard now.timeIntervalSince(lastAccessibilityAlertShownAt)
            >= accessibilityAlertCooldown else {
            NotificationCenter.default.postPastePilotNotice(
                PastePilotNotice(
                    "Accessibility Permission Required".localized,
                    style: .warning
                )
            )
            return
        }
        didShowAccessibilityAlert = true
        lastAccessibilityAlertShownAt = now
        defer { didShowAccessibilityAlert = false }

        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = "Global Shortcut Permission".localized
        alert.informativeText = "Paste as Plain Text needs Accessibility permission.\n\nIf permission stopped working after an update, select the old PastePilot in Accessibility settings and click the minus button. Close old DMGs, then add /Applications/PastePilot.app again.".localized
        alert.addButton(withTitle: "Open Accessibility Settings".localized)
        alert.addButton(withTitle: "Not Now".localized)
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn {
            EventPostingPermission.request()
        }
    }

    static func shortcutNumber(for keyCode: UInt16) -> Int? {
        let keyCodes: [Int: Int] = [
            kVK_ANSI_1: 1,
            kVK_ANSI_2: 2,
            kVK_ANSI_3: 3,
            kVK_ANSI_4: 4,
            kVK_ANSI_5: 5,
            kVK_ANSI_6: 6,
            kVK_ANSI_7: 7,
            kVK_ANSI_8: 8,
            kVK_ANSI_9: 9
        ]
        return keyCodes[Int(keyCode)]
    }

    enum PopoverKeyPost {
        case keyboard(PopoverKeyboardCommand)
        case copyIndex(Int)
    }

    static func post(_ post: PopoverKeyPost) {
        switch post {
        case let .keyboard(command):
            NotificationCenter.default.post(
                name: .pastePilotKeyboardCommand,
                object: command
            )
        case let .copyIndex(number):
            NotificationCenter.default.post(
                name: .pastePilotCopyIndex,
                object: number
            )
        }
    }
}

extension Notification.Name {
    static let pastePilotKeyboardCommand = Notification.Name("PastePilotKeyboardCommand")
    static let pastePilotCopyIndex = Notification.Name("PastePilotCopyIndex")
}

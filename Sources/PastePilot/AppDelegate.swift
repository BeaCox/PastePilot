import AppKit
import Carbon
import Combine
import ServiceManagement
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private enum GlobalHotKey: UInt32 {
        case openPanel = 1
        case pastePlainText = 2
    }

    let settings = AppSettings.shared
    private let store = ClipboardStore()
    let updateController = UpdateController()
    private let plainTextPasteService = PlainTextPasteService()
    private var aboutWindow: NSWindow?
    private var welcomeWindow: NSWindow?
    private var popover: NSPopover?
    private var statusItem: NSStatusItem?
    private var hotKeyRefs: [GlobalHotKey: EventHotKeyRef] = [:]
    private var hotKeyHandler: EventHandlerRef?
    private var keyEventMonitor: Any?
    private var cancellables: Set<AnyCancellable> = []
    private var isSynchronizingLoginItem = false
    private var didShowAccessibilityAlert = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.applicationIconImage = AppIconRenderer.icon(size: 512)
        NSApp.setActivationPolicy(.accessory)
        configureStatusItem()
        registerHotKey()
        registerPopoverKeyMonitor()
        settings.launchAtLogin = SMAppService.mainApp.status == .enabled
        configureSettingsObservers()
        updateController.start()
        if settings.monitoringEnabled {
            store.startMonitoring()
            store.captureCurrentClipboard()
        }
        if !showWelcomeIfNeeded() {
            showPermissionReminderIfNeeded()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        store.stopMonitoring()
        store.flushHistoryWrites()
        unregisterHotKeys()
        if let hotKeyHandler {
            RemoveEventHandler(hotKeyHandler)
        }
        if let keyEventMonitor {
            NSEvent.removeMonitor(keyEventMonitor)
        }
    }

    @objc func togglePanel() {
        togglePopover()
    }

    @objc private func togglePopover() {
        guard let popover, let button = statusItem?.button else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }

    @objc private func clearHistory() {
        store.clearUnpinned()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    @objc private func showSettings() {
        popover?.close()
        NSApp.activate(ignoringOtherApps: true)
        DispatchQueue.main.async {
            guard let appMenu = NSApp.mainMenu?.items.first?.submenu,
                  let index = appMenu.items.firstIndex(where: {
                      $0.keyEquivalent == ","
                  }) else {
                return
            }
            appMenu.performActionForItem(at: index)
        }
    }

    @objc private func showAbout() {
        popover?.close()
        if aboutWindow == nil {
            let version = Bundle.main.object(
                forInfoDictionaryKey: "CFBundleShortVersionString"
            ) as? String ?? "0.3.1"
            let view = AboutView(
                settings: settings,
                version: version,
                openDataFolder: { [weak self] in self?.openDataFolder() },
                checkForUpdates: { [weak self] in
                    self?.updateController.checkForUpdates()
                }
            )
            aboutWindow = makeUtilityWindow(
                title: "About PastePilot".localized,
                size: NSSize(width: 520, height: 390),
                autosaveName: "PastePilot.AboutWindow",
                content: view
            )
        }
        showUtilityWindow(aboutWindow)
    }

    @discardableResult
    private func showWelcomeIfNeeded() -> Bool {
        let key = "hasLaunchedBefore"
        guard !UserDefaults.standard.bool(forKey: key) else { return false }
        UserDefaults.standard.set(true, forKey: key)

        let shortcut = HotKeyFormatter.display(
            keyCode: settings.hotKeyCode,
            modifiers: settings.hotKeyModifiers
        )
        let plainTextShortcut = HotKeyFormatter.display(
            keyCode: settings.plainTextHotKeyCode,
            modifiers: settings.plainTextHotKeyModifiers
        )
        let view = WelcomeView(
            shortcut: shortcut,
            plainTextShortcut: plainTextShortcut
        ) { [weak self] in
            self?.welcomeWindow?.close()
            self?.welcomeWindow = nil
        }
        welcomeWindow = makeUtilityWindow(
            title: "PastePilot",
            size: NSSize(width: 480, height: 420),
            content: view
        )
        showUtilityWindow(welcomeWindow)
        return true
    }

    private func showPermissionReminderIfNeeded() {
        guard !EventPostingPermission.isGranted else { return }
        let version = Bundle.main.object(
            forInfoDictionaryKey: "CFBundleShortVersionString"
        ) as? String ?? "unknown"
        let key = "lastPermissionReminderVersion"
        guard UserDefaults.standard.string(forKey: key) != version else { return }
        UserDefaults.standard.set(version, forKey: key)

        DispatchQueue.main.async { [weak self] in
            self?.showAccessibilityRequiredAlert()
        }
    }

    private func configureStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = statusImage(filled: !store.items.isEmpty)
        item.button?.image?.isTemplate = true
        item.button?.toolTip = "PastePilot: Click for clipboard actions".localized
        item.button?.target = self
        item.button?.action = #selector(togglePopover)
        statusItem = item

        let popover = NSPopover()
        popover.behavior = .transient
        popover.animates = false
        popover.contentSize = NSSize(width: 400, height: 450)
        popover.contentViewController = NSHostingController(
            rootView: MenuBarView(
                store: store,
                settings: settings,
                openSettings: { [weak self] in self?.showSettings() },
                openAbout: { [weak self] in self?.showAbout() },
                checkForUpdates: { [weak self] in
                    self?.updateController.checkForUpdates()
                },
                quit: { [weak self] in self?.quit() },
                closePopover: { [weak self] in self?.popover?.performClose(nil) },
                resize: { [weak self] size in
                    self?.resizePopover(size: size)
                }
            )
        )
        self.popover = popover

        store.$items
            .map { !$0.isEmpty }
            .removeDuplicates()
            .sink { [weak self] hasItems in
                self?.statusItem?.button?.image = self?.statusImage(filled: hasItems)
                self?.statusItem?.button?.image?.isTemplate = true
            }
            .store(in: &cancellables)

        settings.$menuBarIconStyle
            .removeDuplicates()
            .sink { [weak self] styleValue in
                guard let self else { return }
                let style = MenuBarIconStyle(rawValue: styleValue) ?? .pastepilot
                let filled = !self.store.items.isEmpty
                let image = AppIconRenderer.menuBarImage(style: style, filled: filled)
                image?.isTemplate = true
                self.statusItem?.button?.image = image
            }
            .store(in: &cancellables)
    }

    private func resizePopover(size: CGSize) {
        guard let popover else { return }
        let contentSize = NSSize(width: size.width, height: size.height)
        guard popover.contentSize != contentSize else { return }
        popover.contentSize = contentSize
    }

    private func configureSettingsObservers() {
        settings.$monitoringEnabled
            .dropFirst()
            .sink { [weak self] enabled in
                if enabled {
                    self?.store.startMonitoring()
                    self?.store.captureCurrentClipboard()
                } else {
                    self?.store.stopMonitoring()
                }
            }
            .store(in: &cancellables)

        settings.$historyLimit
            .dropFirst()
            .sink { [weak self] limit in
                self?.store.applyHistoryLimit(limit)
            }
            .store(in: &cancellables)

        settings.$launchAtLogin
            .dropFirst()
            .sink { [weak self] enabled in
                self?.updateLoginItem(enabled: enabled)
            }
            .store(in: &cancellables)

        settings.$hotKeyCode
            .combineLatest(settings.$hotKeyModifiers)
            .dropFirst()
            .sink { [weak self] _, _ in
                self?.registerConfiguredHotKeys()
            }
            .store(in: &cancellables)

        settings.$plainTextHotKeyCode
            .combineLatest(settings.$plainTextHotKeyModifiers)
            .dropFirst()
            .sink { [weak self] _, _ in
                self?.registerConfiguredHotKeys()
            }
            .store(in: &cancellables)

        settings.$historyTimeoutSeconds
            .dropFirst()
            .sink { [weak self] _ in
                self?.store.purgeExpired()
            }
            .store(in: &cancellables)
    }

    private func updateLoginItem(enabled: Bool) {
        guard !isSynchronizingLoginItem else { return }
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            NSLog("PastePilot failed to update login item: \(error)")
            isSynchronizingLoginItem = true
            settings.launchAtLogin = SMAppService.mainApp.status == .enabled
            isSynchronizingLoginItem = false
        }
    }

    private func makeUtilityWindow<Content: View>(
        title: String,
        size: NSSize,
        autosaveName: String? = nil,
        content: Content
    ) -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = title
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: content)
        if let autosaveName {
            if !window.setFrameUsingName(autosaveName) {
                window.center()
            }
            window.setFrameAutosaveName(autosaveName)
        } else {
            window.center()
        }
        return window
    }

    private func showUtilityWindow(_ window: NSWindow?) {
        guard let window else { return }
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    func openDataFolder() {
        try? FileManager.default.createDirectory(
            at: store.dataDirectoryURL,
            withIntermediateDirectories: true
        )
        NSWorkspace.shared.activateFileViewerSelecting([store.dataDirectoryURL])
    }

    func clearUnpinnedHistory() {
        store.clearUnpinned()
    }

    private func statusImage(filled: Bool) -> NSImage? {
        let style = MenuBarIconStyle(rawValue: settings.menuBarIconStyle) ?? .pastepilot
        let image = AppIconRenderer.menuBarImage(style: style, filled: filled)
        image?.isTemplate = true
        return image
    }

    private func registerPopoverKeyMonitor() {
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

    private func registerHotKey() {
        installHotKeyHandler()
        registerConfiguredHotKeys()
    }

    private func registerConfiguredHotKeys() {
        unregisterHotKeys()
        registerHotKey(
            .openPanel,
            keyCode: settings.hotKeyCode,
            modifiers: settings.hotKeyModifiers
        )
        registerHotKey(
            .pastePlainText,
            keyCode: settings.plainTextHotKeyCode,
            modifiers: settings.plainTextHotKeyModifiers
        )
    }

    private func registerHotKey(
        _ hotKey: GlobalHotKey,
        keyCode: Int,
        modifiers: UInt32
    ) {
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
        } else {
            NSLog(
                "PastePilot failed to register hot key \(hotKey.rawValue): \(status)"
            )
        }
    }

    private func unregisterHotKeys() {
        for reference in hotKeyRefs.values {
            UnregisterEventHotKey(reference)
        }
        hotKeyRefs.removeAll()
    }

    private func installHotKeyHandler() {
        guard hotKeyHandler == nil else { return }
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: OSType(kEventHotKeyPressed)
        )
        let pointer = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(
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
    }

    private func pasteAsPlainText() {
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
        }
    }

    private func showAccessibilityRequiredAlert() {
        guard !didShowAccessibilityAlert else { return }
        didShowAccessibilityAlert = true

        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = "Global Shortcut Permission".localized
        alert.informativeText = "Paste as Plain Text needs Accessibility permission.\n\nIf permission stopped working after an update, select the old PastePilot in Accessibility settings and click the minus button. Close old DMGs, then add /Applications/PastePilot.app again.".localized
        alert.addButton(withTitle: "Open Accessibility Settings".localized)
        alert.addButton(withTitle: "Not Now".localized)
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn,
           EventPostingPermission.request() {
            didShowAccessibilityAlert = false
        }
    }

    private static func shortcutNumber(for keyCode: UInt16) -> Int? {
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

    private enum PopoverKeyPost {
        case keyboard(PopoverKeyboardCommand)
        case copyIndex(Int)
    }

    private static func post(_ post: PopoverKeyPost) {
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

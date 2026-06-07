import AppKit
import ApplicationServices
import Carbon
import Combine
import ServiceManagement
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let settings = AppSettings.shared
    private let store = ClipboardStore()
    private let updateController = UpdateController()
    private var settingsWindow: NSWindow?
    private var aboutWindow: NSWindow?
    private var welcomeWindow: NSWindow?
    private var popover: NSPopover?
    private var statusItem: NSStatusItem?
    private var hotKeyRef: EventHotKeyRef?
    private var hotKeyHandler: EventHandlerRef?
    private var keyEventMonitor: Any?
    private var cancellables: Set<AnyCancellable> = []
    private var isSynchronizingLoginItem = false

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
        showWelcomeIfNeeded()
    }

    func applicationWillTerminate(_ notification: Notification) {
        store.stopMonitoring()
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
        }
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
        if settingsWindow == nil {
            let view = SettingsView(
                settings: settings,
                openDataFolder: { [weak self] in self?.openDataFolder() },
                clearUnpinnedHistory: { [weak self] in self?.store.clearUnpinned() },
                updateController: updateController,
                resize: { [weak self] height in
                    self?.resizeSettingsWindow(height: height)
                }
            )
            settingsWindow = makeUtilityWindow(
                title: "PastePilot Settings".localized,
                size: NSSize(width: 640, height: 350),
                content: view
            )
        }
        showUtilityWindow(settingsWindow)
    }

    @objc private func showAbout() {
        popover?.close()
        if aboutWindow == nil {
            let version = Bundle.main.object(
                forInfoDictionaryKey: "CFBundleShortVersionString"
            ) as? String ?? "0.1.0"
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
                content: view
            )
        }
        showUtilityWindow(aboutWindow)
    }

    private func showWelcomeIfNeeded() {
        let key = "hasLaunchedBefore"
        guard !UserDefaults.standard.bool(forKey: key) else { return }
        UserDefaults.standard.set(true, forKey: key)

        let shortcut = HotKeyFormatter.display(
            keyCode: settings.hotKeyCode,
            modifiers: settings.hotKeyModifiers
        )
        let view = WelcomeView(shortcut: shortcut) { [weak self] in
            self?.welcomeWindow?.close()
            self?.welcomeWindow = nil
        }
        welcomeWindow = makeUtilityWindow(
            title: "PastePilot",
            size: NSSize(width: 480, height: 420),
            content: view
        )
        showUtilityWindow(welcomeWindow)
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
        popover.animates = true
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

    private func resizeSettingsWindow(height: CGFloat) {
        guard let settingsWindow else { return }
        let size = NSSize(width: 640, height: height)
        guard settingsWindow.contentLayoutRect.size != size else { return }
        settingsWindow.setContentSize(size)
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
                self?.registerConfiguredHotKey()
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
        window.center()
        return window
    }

    private func showUtilityWindow(_ window: NSWindow?) {
        guard let window else { return }
        NSApp.activate(ignoringOtherApps: true)
        window.center()
        window.makeKeyAndOrderFront(nil)
    }

    private func openDataFolder() {
        try? FileManager.default.createDirectory(
            at: store.dataDirectoryURL,
            withIntermediateDirectories: true
        )
        NSWorkspace.shared.activateFileViewerSelecting([store.dataDirectoryURL])
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
            if flags.contains(.command),
               !flags.contains(.option),
               !flags.contains(.control),
               let number = Self.shortcutNumber(for: event.keyCode) {
                NotificationCenter.default.post(
                    name: .pastePilotCopyIndex,
                    object: number
                )
                return nil
            }

            if flags.contains(.command),
               !flags.contains(.option),
               !flags.contains(.control) {
                switch event.keyCode {
                case UInt16(kVK_ANSI_P):
                    NotificationCenter.default.post(name: .pastePilotTogglePinned, object: nil)
                    return nil
                case UInt16(kVK_Delete):
                    NotificationCenter.default.post(name: .pastePilotDeleteItem, object: nil)
                    return nil
                default:
                    break
                }
            }

            let notification: Notification.Name?
            switch event.keyCode {
            case UInt16(kVK_UpArrow):
                notification = .pastePilotMoveUp
            case UInt16(kVK_DownArrow):
                notification = .pastePilotMoveDown
            case UInt16(kVK_Space):
                if let editor = self?.popover?.contentViewController?
                    .view.window?.firstResponder as? NSTextView,
                   !editor.string.isEmpty {
                    return event
                }
                notification = .pastePilotTogglePreview
            default:
                notification = nil
            }
            guard let notification else { return event }
            NotificationCenter.default.post(name: notification, object: nil)
            return nil
        }
    }

    private func registerHotKey() {
        installHotKeyHandler()
        registerConfiguredHotKey()
    }

    private func registerConfiguredHotKey() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }
        let signature = OSType(0x50504C54) // PPLT
        let hotKeyID = EventHotKeyID(signature: signature, id: 1)
        let status = RegisterEventHotKey(
            UInt32(settings.hotKeyCode),
            settings.hotKeyModifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )
        if status != noErr {
            NSLog("PastePilot failed to register hot key: \(status)")
        }
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
                guard receivedID.id == 1 else { return noErr }
                let delegate = Unmanaged<AppDelegate>.fromOpaque(userData).takeUnretainedValue()
                Task { @MainActor in delegate.togglePopover() }
                return noErr
            },
            1,
            &eventType,
            pointer,
            &hotKeyHandler
        )
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
}

extension Notification.Name {
    static let pastePilotMoveUp = Notification.Name("PastePilotMoveUp")
    static let pastePilotMoveDown = Notification.Name("PastePilotMoveDown")
    static let pastePilotCopyIndex = Notification.Name("PastePilotCopyIndex")
    static let pastePilotTogglePreview = Notification.Name("PastePilotTogglePreview")
    static let pastePilotTogglePinned = Notification.Name("PastePilotTogglePinned")
    static let pastePilotDeleteItem = Notification.Name("PastePilotDeleteItem")
}

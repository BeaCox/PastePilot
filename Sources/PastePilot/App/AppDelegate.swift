import AppKit
import Carbon
import Combine
import ServiceManagement
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    enum GlobalHotKey: UInt32 {
        case openPanel = 1
        case pastePlainText = 2
    }

    let settings = AppSettings.shared
    let store = ClipboardStore()
    let updateController = UpdateController()
    let plainTextPasteService = PlainTextPasteService()
    let pasteShortcutService = PasteShortcutService()
    var aboutWindow: NSWindow?
    var welcomeWindow: NSWindow?
    var popover: NSPopover?
    var statusItem: NSStatusItem?
    var hotKeyRefs: [GlobalHotKey: EventHotKeyRef] = [:]
    var hotKeyHandler: EventHandlerRef?
    var keyEventMonitor: Any?
    var cancellables: Set<AnyCancellable> = []
    var isSynchronizingLoginItem = false
    var didShowAccessibilityAlert = false
    var lastAccessibilityAlertShownAt = Date.distantPast
    let accessibilityAlertCooldown: TimeInterval = 30

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        configureStatusItem()
        registerHotKey()
        registerPopoverKeyMonitor()
        settings.launchAtLogin = SMAppService.mainApp.status == .enabled
        configureSettingsObservers()
        updateController.start()
        if settings.monitoringEnabled {
            store.startMonitoring()
        }
        if !showWelcomeIfNeeded() {
            showPermissionReminderIfNeeded()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        store.stopMonitoring()
        store.cancelAllOCRTasks()
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

    func applicationDidResignActive(_ notification: Notification) {
        // When focus moves to another app, dismiss the panel and any open
        // detail preview together so nothing is left dangling.
        Self.post(.keyboard(.dismissAll))
    }

}

import AppKit
import Combine
import SwiftUI
import UniformTypeIdentifiers

enum StatusItemIconPresentation: Equatable {
    case paused
    case active(style: MenuBarIconStyle, filled: Bool)

    static func resolve(
        hasItems: Bool,
        iconStyle: String,
        monitoringEnabled: Bool
    ) -> Self {
        guard monitoringEnabled else { return .paused }
        return .active(
            style: MenuBarIconStyle(rawValue: iconStyle) ?? .pastepilot,
            filled: hasItems
        )
    }
}

extension AppDelegate {
    @objc func togglePopover() {
        guard let button = statusItem?.button else { return }
        let popover = ensurePopover()
        if popover.isShown {
            popover.performClose(nil)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }

    @objc func clearHistory() {
        store.clearUnpinned()
    }

    @objc func quit() {
        NSApp.terminate(nil)
    }

    @objc func showSettings() {
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

    @objc func showAbout() {
        popover?.close()
        if aboutWindow == nil {
            let version = Bundle.main.object(
                forInfoDictionaryKey: "CFBundleShortVersionString"
            ) as? String ?? "0.5.0"
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
                content: view.pastePilotAppearance(settings)
            )
        }
        showUtilityWindow(aboutWindow)
    }

    @discardableResult
    func showWelcomeIfNeeded() -> Bool {
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
            content: view.pastePilotAppearance(settings)
        )
        showUtilityWindow(welcomeWindow)
        return true
    }

    func showPermissionReminderIfNeeded() {
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

    func configureStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.target = self
        item.button?.action = #selector(togglePopover)
        if let button = item.button {
            let dropView = StatusItemDropView(frame: button.bounds)
            dropView.autoresizingMask = [.width, .height]
            dropView.onDropFiles = { [weak self] urls in
                self?.handleStatusItemDrop(urls)
            }
            dropView.onClick = { [weak self] event in
                self?.handleStatusItemClick(event)
            }
            button.addSubview(dropView)
        }
        statusItem = item
        updateStatusItemIcon(
            presentation: .resolve(
                hasItems: !store.items.isEmpty,
                iconStyle: settings.menuBarIconStyle,
                monitoringEnabled: settings.monitoringEnabled
            )
        )

        Publishers.CombineLatest3(
            store.$items.map { !$0.isEmpty }.removeDuplicates(),
            settings.$menuBarIconStyle.removeDuplicates(),
            settings.$monitoringEnabled.removeDuplicates()
        )
        .sink { [weak self] hasItems, iconStyle, monitoringEnabled in
            self?.updateStatusItemIcon(
                presentation: .resolve(
                    hasItems: hasItems,
                    iconStyle: iconStyle,
                    monitoringEnabled: monitoringEnabled
                )
            )
        }
        .store(in: &cancellables)
    }

    private func updateStatusItemIcon(presentation: StatusItemIconPresentation) {
        guard let button = statusItem?.button else { return }
        guard case let .active(style, filled) = presentation else {
            let image = NSImage(
                systemSymbolName: "pause.circle",
                accessibilityDescription: "PastePilot"
            )?.withSymbolConfiguration(
                NSImage.SymbolConfiguration(pointSize: 15, weight: .medium)
            )
            image?.isTemplate = true
            button.image = image
            button.toolTip = "PastePilot: Capture paused — click for clipboard actions".localized
            return
        }
        let image = AppIconRenderer.menuBarImage(style: style, filled: filled)
        image?.isTemplate = true
        button.image = image
        button.toolTip = "PastePilot: Click for clipboard actions".localized
    }

    func ensurePopover() -> NSPopover {
        if let popover {
            return popover
        }

        let popover = NSPopover()
        popover.behavior = .transient
        popover.animates = false
        popover.contentSize = NSSize(width: 400, height: 450)
        popover.contentViewController = NSHostingController(
            rootView: MenuBarView(
                store: store,
                settings: settings,
                pasteStack: pasteStack,
                openSettings: { [weak self] in self?.showSettings() },
                openAbout: { [weak self] in self?.showAbout() },
                checkForUpdates: { [weak self] in
                    self?.updateController.checkForUpdates()
                },
                quit: { [weak self] in self?.quit() },
                closePopover: { [weak self] in self?.popover?.close() },
                pasteAfterCopying: { [weak self] in
                    self?.pasteShortcutService.paste() ?? .accessibilityRequired
                },
                showAccessibilityRequired: { [weak self] in
                    self?.showAccessibilityRequiredAlert()
                },
                resize: { [weak self] size in
                    self?.resizePopover(size: size)
                }
            )
            .pastePilotAppearance(settings)
        )
        self.popover = popover
        return popover
    }

    func handleStatusItemClick(_ event: NSEvent) {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if flags.contains(.option), flags.contains(.shift) {
            store.ignoreNextCopy()
            return
        }
        if flags.contains(.option) {
            settings.monitoringEnabled.toggle()
            NotificationCenter.default.postPastePilotNotice(
                PastePilotNotice(
                    settings.monitoringEnabled
                        ? "Clipboard capture resumed".localized
                        : "Clipboard capture paused".localized
                )
            )
            return
        }
        togglePopover()
    }

    func handleStatusItemDrop(_ urls: [URL]) {
        store.importFiles(urls)
        if popover?.isShown != true {
            togglePopover()
        }
    }

    func resizePopover(size: CGSize) {
        guard let popover else { return }
        let contentSize = NSSize(width: size.width, height: size.height)
        guard popover.contentSize != contentSize else { return }
        popover.contentSize = contentSize
    }

    func makeUtilityWindow<Content: View>(
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

    func showUtilityWindow(_ window: NSWindow?) {
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

    func exportBackup() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.zip]
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = defaultBackupFileName()

        guard panel.runModal() == .OK,
              let url = panel.url else {
            return
        }

        do {
            try store.exportBackup(to: url)
        } catch {
            showBackupErrorAlert(
                title: "Backup could not be exported".localized,
                error: error
            )
        }
    }

    func restoreBackup() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.zip]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true

        guard panel.runModal() == .OK,
              let url = panel.url,
              confirmsRestoreBackup() else {
            return
        }

        do {
            try store.restoreBackup(from: url)
        } catch {
            showBackupErrorAlert(
                title: "Backup could not be restored".localized,
                error: error
            )
        }
    }

    func clearUnpinnedHistory() {
        store.clearUnpinned()
    }

    private func defaultBackupFileName(date: Date = Date()) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH.mm.ss"
        return "PastePilot Backup \(formatter.string(from: date)).zip"
    }

    private func confirmsRestoreBackup() -> Bool {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Restore Backup?".localized
        alert.informativeText = "Current history will be backed up, then replaced with the selected archive.".localized
        alert.addButton(withTitle: "Restore".localized)
        alert.addButton(withTitle: "Cancel".localized)
        return alert.runModal() == .alertFirstButtonReturn
    }

    private func showBackupErrorAlert(title: String, error: Error) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = title
        alert.informativeText = error.localizedDescription
        alert.runModal()
    }
}

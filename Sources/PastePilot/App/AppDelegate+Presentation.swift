import AppKit
import Combine
import SwiftUI

extension AppDelegate {
    @objc func togglePopover() {
        guard let popover, let button = statusItem?.button else { return }
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
            content: view
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
        item.button?.image = statusImage(filled: !store.items.isEmpty)
        item.button?.image?.isTemplate = true
        item.button?.toolTip = "PastePilot: Click for clipboard actions".localized
        item.button?.target = self
        item.button?.action = #selector(togglePopover)
        if let button = item.button {
            let dropView = StatusItemDropView(frame: button.bounds)
            dropView.autoresizingMask = [.width, .height]
            dropView.onDropFiles = { [weak self] urls in
                self?.handleStatusItemDrop(urls)
            }
            dropView.onClick = { [weak self] in
                self?.togglePopover()
            }
            button.addSubview(dropView)
        }
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

    func clearUnpinnedHistory() {
        store.clearUnpinned()
    }

    func statusImage(filled: Bool) -> NSImage? {
        let style = MenuBarIconStyle(rawValue: settings.menuBarIconStyle) ?? .pastepilot
        let image = AppIconRenderer.menuBarImage(style: style, filled: filled)
        image?.isTemplate = true
        return image
    }
}

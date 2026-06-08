import AppKit
import SwiftUI

private enum SettingsTab: String, CaseIterable, Identifiable {
    case general
    case storage
    case appearance
    case ignored
    case advanced

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: "General".localized
        case .storage: "Storage".localized
        case .appearance: "Appearance".localized
        case .ignored: "Ignored Apps".localized
        case .advanced: "Advanced".localized
        }
    }

    var symbol: String {
        switch self {
        case .general: "gearshape"
        case .storage: "internaldrive"
        case .appearance: "paintpalette"
        case .ignored: "nosign"
        case .advanced: "gearshape.2"
        }
    }
}

struct SettingsView: View {
    @ObservedObject var settings: AppSettings
    let openDataFolder: () -> Void
    let clearUnpinnedHistory: () -> Void
    let updateController: UpdateController
    let resize: (CGFloat) -> Void
    @State private var selectedTab: SettingsTab = .general
    @State private var showsResetConfirmation = false
    @State private var showsClearHistoryConfirmation = false
    @State private var accessibilityGranted = EventPostingPermission.isGranted
    @State private var accessibilityPollTimer: Timer?

    private var preferredHeight: CGFloat {
        switch selectedTab {
        case .general: 540
        case .storage: 390
        case .appearance: 330
        case .ignored: 500
        case .advanced: 380
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            tabBar
            Divider()
            ScrollView {
                page
                    .padding(.horizontal, 30)
                    .padding(.vertical, 22)
            }
        }
        .frame(width: 640, height: preferredHeight)
        .onAppear {
            resize(preferredHeight)
        }
        .onChange(of: selectedTab) {
            resize(preferredHeight)
        }
        .onAppear {
            refreshAccessibilityStatus()
            accessibilityPollTimer?.invalidate()
            accessibilityPollTimer = Timer.scheduledTimer(
                withTimeInterval: 1,
                repeats: true
            ) { _ in
                Task { @MainActor in
                    refreshAccessibilityStatus()
                }
            }
        }
        .onDisappear {
            accessibilityPollTimer?.invalidate()
            accessibilityPollTimer = nil
        }
        .confirmationDialog(
            "Reset to Defaults?".localized,
            isPresented: $showsResetConfirmation
        ) {
            Button("Reset to Defaults".localized, role: .destructive) {
                settings.reset()
            }
        } message: {
            Text("Clipboard history will not be deleted.".localized)
        }
        .confirmationDialog(
            "Clear Unpinned History?".localized,
            isPresented: $showsClearHistoryConfirmation
        ) {
            Button("Clear Unpinned".localized, role: .destructive) {
                clearUnpinnedHistory()
            }
        } message: {
            Text("Pinned items will be kept. This action cannot be undone.".localized)
        }
    }

    private var tabBar: some View {
        HStack(spacing: 6) {
            ForEach(SettingsTab.allCases) { tab in
                Button {
                    selectedTab = tab
                } label: {
                    VStack(spacing: 3) {
                        Image(systemName: tab.symbol)
                            .font(.system(size: 17, weight: .medium))
                            .frame(height: 20)
                        Text(tab.title)
                            .font(.caption)
                    }
                    .foregroundStyle(
                        selectedTab == tab ? Color.accentColor : Color.secondary
                    )
                    .frame(width: 82, height: 44)
                    .background(
                        selectedTab == tab
                            ? Color.primary.opacity(0.06)
                            : Color.clear,
                        in: RoundedRectangle(cornerRadius: 8)
                    )
                    .overlay {
                        if selectedTab == tab {
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.primary.opacity(0.08))
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(tab.title)
                .accessibilityAddTraits(selectedTab == tab ? .isSelected : [])
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(.bar)
    }

    @ViewBuilder
    private var page: some View {
        switch selectedTab {
        case .general:
            generalPage
        case .storage:
            storagePage
        case .appearance:
            appearancePage
        case .ignored:
            ignoredPage
        case .advanced:
            advancedPage
        }
    }

    private var generalPage: some View {
        SettingsPage {
            SettingsSection {
                Toggle("Launch PastePilot at Login".localized, isOn: $settings.launchAtLogin)
                Toggle("Monitor Clipboard".localized, isOn: $settings.monitoringEnabled)
                SettingsNote("When disabled, existing history can still be searched and copied.".localized)
            }

            SettingsSection {
                Text("Global Shortcuts".localized)
                    .font(.headline)

                SettingsRow(title: "Open PastePilot".localized) {
                    HotKeyRecorder(
                        keyCode: $settings.hotKeyCode,
                        modifiers: $settings.hotKeyModifiers
                    )
                }
                SettingsRow(title: "Paste as Plain Text".localized) {
                    HotKeyRecorder(
                        keyCode: $settings.plainTextHotKeyCode,
                        modifiers: $settings.plainTextHotKeyModifiers,
                        defaultKeyCode: AppSettings.defaultPlainTextHotKeyCode,
                        defaultModifiers: AppSettings.defaultPlainTextHotKeyModifiers,
                        accessibilityLabel: "Paste as Plain Text Shortcut".localized
                    )
                }
                SettingsNote("Click a shortcut field and press a new combination; press Delete to reset.".localized)
                if shortcutsConflict {
                    SettingsNote(
                        "Choose a different shortcut; both global actions currently use the same keys.".localized
                    )
                    .foregroundStyle(.red)
                } else {
                    SettingsNote(
                        "Only Paste as Plain Text requires Accessibility permission.".localized
                    )
                }
            }

            SettingsSection {
                HStack {
                    Label(
                        accessibilityGranted
                            ? "Accessibility Permission Granted".localized
                            : "Accessibility Permission Required".localized,
                        systemImage: accessibilityGranted
                            ? "checkmark.circle.fill"
                            : "exclamationmark.triangle.fill"
                    )
                    .font(.headline)
                    .foregroundStyle(accessibilityGranted ? .green : .orange)
                    Spacer()
                    if !accessibilityGranted {
                        Button("Open Accessibility Settings".localized) {
                            requestEventPostingPermission()
                        }
                    }
                }

                if !accessibilityGranted {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("Permission stopped working after an update?".localized)
                            .font(.caption.weight(.semibold))
                        Text("1. Select the old PastePilot in Accessibility settings, then click the minus button at the bottom.".localized)
                        Text("2. Close old DMGs, then add and enable /Applications/PastePilot.app again.".localized)
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private var shortcutsConflict: Bool {
        settings.hotKeyCode == settings.plainTextHotKeyCode
            && settings.hotKeyModifiers == settings.plainTextHotKeyModifiers
    }

    private func refreshAccessibilityStatus() {
        accessibilityGranted = EventPostingPermission.isGranted
    }

    private func requestEventPostingPermission() {
        accessibilityGranted = EventPostingPermission.request()
    }

    private var storagePage: some View {
        SettingsPage {
            SettingsSection {
                SettingsRow(title: "Keep up to".localized) {
                    Picker("", selection: $settings.historyLimit) {
                        Text("50 items".localized).tag(50)
                        Text("100 items".localized).tag(100)
                        Text("200 items".localized).tag(200)
                        Text("500 items".localized).tag(500)
                    }
                    .labelsHidden()
                    .frame(width: 130)
                }
                SettingsRow(title: "Auto-delete After".localized) {
                    Picker("", selection: $settings.historyTimeoutSeconds) {
                        Text("Never".localized).tag(0)
                        Text("1 hour".localized).tag(3600)
                        Text("24 hours".localized).tag(86400)
                        Text("7 days".localized).tag(604800)
                        Text("30 days".localized).tag(2592000)
                    }
                    .labelsHidden()
                    .frame(width: 130)
                }
                SettingsNote("Pinned items are excluded from this limit and never auto-deleted.".localized)
            }

            SettingsSection {
                SettingsRow(title: "Image Size Limit".localized) {
                    Picker("", selection: $settings.imageSizeLimitMB) {
                        Text("5 MB").tag(5)
                        Text("10 MB").tag(10)
                        Text("25 MB").tag(25)
                        Text("50 MB").tag(50)
                    }
                    .labelsHidden()
                    .frame(width: 130)
                }
                SettingsRow(title: "Data Folder".localized) {
                    Button("Show in Finder".localized, action: openDataFolder)
                }
            }
        }
    }

    private var appearancePage: some View {
        SettingsPage {
            SettingsSection {
                SettingsRow(title: "Menu Bar Icon".localized) {
                    Picker("", selection: $settings.menuBarIconStyle) {
                        ForEach(MenuBarIconStyle.allCases, id: \.rawValue) { style in
                            Label {
                                Text(style.displayName)
                            } icon: {
                                Image(nsImage: style.previewImage)
                                    .renderingMode(.template)
                            }
                                .tag(style.rawValue)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 180)
                }
            }

            SettingsSection {
                Toggle("Show Details on Hover".localized, isOn: $settings.hoverPreviewEnabled)
                SettingsNote("Hover briefly to see full content, source app, and metadata.".localized)
            }

            SettingsSection {
                SettingsRow(title: "Menu Bar Window".localized) {
                    Text("Adaptive".localized)
                        .foregroundStyle(.secondary)
                }
                SettingsNote("The window grows with your results and follows the system light or dark appearance.".localized)
            }
        }
    }

    private var ignoredPage: some View {
        SettingsPage {
            SettingsSection {
                IgnoredAppsEditor(settings: settings)
            }

            SettingsSection {
                Label("Ignore rules only affect new copies and won't delete existing history.".localized, systemImage: "info.circle")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var advancedPage: some View {
        SettingsPage {
            SettingsSection {
                SettingsRow(title: "Local Data".localized) {
                    Button("Open Data Folder".localized, action: openDataFolder)
                }
                SettingsRow(title: "History".localized) {
                    Button("Clear Unpinned".localized, role: .destructive) {
                        showsClearHistoryConfirmation = true
                    }
                }
            }

            SettingsSection {
                SettingsRow(title: "Updates".localized) {
                    Button("Check for Updates…".localized) {
                        updateController.checkForUpdates()
                    }
                    .disabled(!updateController.canCheckForUpdates)
                }
                Toggle(
                    "Automatically Check for Updates".localized,
                    isOn: Binding(
                        get: { updateController.automaticallyChecksForUpdates },
                        set: { updateController.automaticallyChecksForUpdates = $0 }
                    )
                )
            }

            SettingsSection {
                SettingsRow(title: "Preferences".localized) {
                    Button("Reset to Defaults…".localized) {
                        showsResetConfirmation = true
                    }
                }
                SettingsNote("Resetting preferences won't delete clipboard history or images.".localized)
            }
        }
    }
}

private struct SettingsPage<Content: View>: View {
    @ViewBuilder let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            content
        }
    }
}

private struct SettingsSection<Content: View>: View {
    @ViewBuilder let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 10))
    }
}

private struct SettingsRow<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    init(title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        HStack {
            Text(title)
            Spacer()
            content
        }
        .frame(minHeight: 28)
    }
}

private struct SettingsNote: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}

private struct InstalledApp: Identifiable {
    let id: String
    let name: String
    let icon: NSImage

    static func discover() -> [InstalledApp] {
        let fm = FileManager.default
        let searchDirs = [
            "/Applications",
            "/System/Applications",
            NSHomeDirectory() + "/Applications",
        ]
        var seen = Set<String>()
        var apps: [InstalledApp] = []

        for dir in searchDirs {
            guard let urls = try? fm.contentsOfDirectory(
                at: URL(fileURLWithPath: dir),
                includingPropertiesForKeys: nil
            ) else { continue }

            for url in urls where url.pathExtension == "app" {
                guard let bundle = Bundle(url: url),
                      let bundleID = bundle.bundleIdentifier,
                      !seen.contains(bundleID) else { continue }
                seen.insert(bundleID)
                let name = (bundle.object(forInfoDictionaryKey: "CFBundleName") as? String)
                    ?? (bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
                    ?? url.deletingPathExtension().lastPathComponent
                let icon = NSWorkspace.shared.icon(forFile: url.path)
                apps.append(InstalledApp(id: bundleID, name: name, icon: icon))
            }
        }

        return apps.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
}

private struct IgnoredAppsEditor: View {
    @ObservedObject var settings: AppSettings
    @State private var installedApps: [InstalledApp] = []
    @State private var searchText = ""

    private var ignoredSet: Set<String> {
        settings.ignoredBundleIdentifierSet
    }

    private var filteredApps: [InstalledApp] {
        let ignored = installedApps.filter { ignoredSet.contains($0.id) }
        let available = installedApps.filter { !ignoredSet.contains($0.id) }

        if searchText.isEmpty {
            return ignored + available
        }
        return (ignored + available).filter {
            $0.name.localizedCaseInsensitiveContains(searchText)
                || $0.id.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Ignore These Apps".localized)
                    .font(.headline)
                Spacer()
                Text("%d ignored".localized(ignoredSet.count))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search apps…".localized, text: $searchText)
                    .textFieldStyle(.plain)
                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.tertiary)
                    .accessibilityLabel("Clear Search".localized)
                }
            }
            .padding(.horizontal, 8)
            .frame(height: 26)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))

            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(filteredApps) { app in
                        AppToggleRow(
                            app: app,
                            isIgnored: ignoredSet.contains(app.id),
                            toggle: { toggleApp(app) }
                        )
                        if app.id != filteredApps.last?.id {
                            Divider().padding(.leading, 40)
                        }
                    }
                }
            }
            .frame(height: 200)
            .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 7))

            SettingsNote("Ignore rules only affect new copies and won't delete existing history.".localized)
        }
        .onAppear {
            if installedApps.isEmpty {
                installedApps = InstalledApp.discover()
            }
        }
    }

    private func toggleApp(_ app: InstalledApp) {
        var ids = ignoredSet
        if ids.contains(app.id) {
            ids.remove(app.id)
        } else {
            ids.insert(app.id)
        }
        settings.ignoredBundleIdentifiers = ids.sorted().joined(separator: "\n")
    }
}

private struct AppToggleRow: View {
    let app: InstalledApp
    let isIgnored: Bool
    let toggle: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button(action: toggle) {
            HStack(spacing: 10) {
                Image(nsImage: app.icon)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 24, height: 24)

                VStack(alignment: .leading, spacing: 1) {
                    Text(app.name)
                        .font(.callout)
                        .foregroundStyle(.primary)
                    Text(app.id)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }

                Spacer()

                Image(systemName: isIgnored ? "eye.slash.fill" : "eye")
                    .font(.system(size: 13))
                    .foregroundStyle(isIgnored ? Color.orange : Color.secondary.opacity(0.4))
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
            .background(
                isHovering ? Color.primary.opacity(0.04) : Color.clear,
                in: RoundedRectangle(cornerRadius: 5)
            )
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(app.name)
        .accessibilityValue(isIgnored ? "Ignored".localized : "Recorded".localized)
        .accessibilityHint("Toggles whether clipboard content from this app is recorded.".localized)
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.08)) {
                isHovering = hovering
            }
        }
    }
}

struct AboutView: View {
    @ObservedObject var settings: AppSettings
    let version: String
    let openDataFolder: () -> Void
    let checkForUpdates: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center, spacing: 18) {
                Image(nsImage: AppIconRenderer.icon(size: 256))
                    .resizable()
                    .scaledToFit()
                    .frame(width: 92, height: 92)
                    .shadow(color: Color.accentColor.opacity(0.22), radius: 14, y: 7)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 5) {
                    Text("PastePilot")
                        .font(.system(size: 30, weight: .bold, design: .rounded))
                    Text("Smart Clipboard for Developers".localized)
                        .font(.headline)
                        .foregroundStyle(.secondary)
                    Text("Version %@".localized(version))
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(.quaternary, in: Capsule())
                }

                Spacer()
            }
            .padding(.bottom, 20)

            Text("Understands developer text, rich text, images, and files — suggests the next action. All data stays on your Mac.".localized)
                .multilineTextAlignment(.leading)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, 18)

            HStack(spacing: 10) {
                AboutFeature(
                    symbol: "keyboard",
                    title: "Quick Access".localized,
                    detail: HotKeyFormatter.display(
                        keyCode: settings.hotKeyCode,
                        modifiers: settings.hotKeyModifiers
                    )
                )
                AboutFeature(
                    symbol: "lock.shield",
                    title: "Private by Design".localized,
                    detail: "Local Storage".localized
                )
                AboutFeature(
                    symbol: "wand.and.stars",
                    title: "Developer Actions".localized,
                    detail: "Built In".localized
                )
            }
            .padding(.bottom, 18)

            Divider()

            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Designed & Built by".localized)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("BeaCox")
                        .font(.headline.weight(.semibold))
                }

                Spacer()

                Button(action: openDataFolder) {
                    Label("Data Folder".localized, systemImage: "folder")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Button(action: checkForUpdates) {
                    Label("Check for Updates…".localized, systemImage: "arrow.triangle.2.circlepath")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
            .padding(.top, 16)
        }
        .padding(30)
        .frame(width: 520, height: 390)
    }
}

private struct AboutFeature: View {
    let symbol: String
    let title: String
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: symbol)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(Color.accentColor)
                .frame(width: 30, height: 30)
                .background(Color.accentColor.opacity(0.11), in: RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                Text(detail)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(.quaternary.opacity(0.55), in: RoundedRectangle(cornerRadius: 10))
        .accessibilityElement(children: .combine)
    }
}

struct WelcomeView: View {
    let shortcut: String
    let plainTextShortcut: String
    let dismiss: () -> Void
    @State private var accessibilityGranted = EventPostingPermission.isGranted
    @State private var pollTimer: Timer?

    var body: some View {
        VStack(spacing: 22) {
            Image(nsImage: AppIconRenderer.icon(size: 256))
                .resizable()
                .scaledToFit()
                .frame(width: 80, height: 80)
                .accessibilityHidden(true)

            VStack(spacing: 5) {
                Text("Welcome to PastePilot".localized)
                    .font(.title2.bold())
                Text("Smart Clipboard for Developers".localized)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            VStack(spacing: 0) {
                statusRow(
                    granted: accessibilityGranted,
                    symbol: "hand.raised",
                    title: "Global Shortcuts".localized,
                    detail: accessibilityGranted
                        ? "Both shortcuts are ready.".localized
                        : "Open PastePilot works now; paste as plain text needs Accessibility permission.".localized
                )
                Divider().padding(.leading, 42)
                statusRow(
                    granted: true,
                    symbol: "clipboard",
                    title: "Clipboard Monitoring".localized,
                    detail: "Active — no additional permission needed.".localized
                )
            }
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 10))

            if !accessibilityGranted {
                Button("Request Permission".localized) {
                    accessibilityGranted = EventPostingPermission.request()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }

            VStack(spacing: 6) {
                Text("Press %@ to open PastePilot anytime.".localized(shortcut))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(
                    "Press %@ to paste without formatting.".localized(
                        plainTextShortcut
                    )
                )
                .font(.caption)
                .foregroundStyle(.secondary)

                Button(accessibilityGranted ? "Get Started".localized : "Skip for Now".localized) {
                    dismiss()
                }
                .buttonStyle(.bordered)
                .controlSize(.regular)
            }
        }
        .padding(32)
        .frame(width: 480, height: 420)
        .onAppear {
            guard !accessibilityGranted else { return }
            pollTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
                Task { @MainActor in
                    let trusted = EventPostingPermission.isGranted
                    if trusted != accessibilityGranted {
                        withAnimation { accessibilityGranted = trusted }
                        if trusted { pollTimer?.invalidate() }
                    }
                }
            }
        }
        .onDisappear {
            pollTimer?.invalidate()
        }
    }

    private func statusRow(granted: Bool, symbol: String, title: String, detail: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: granted ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .foregroundStyle(granted ? .green : .orange)
                .font(.system(size: 18))
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.callout.weight(.medium))
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .accessibilityElement(children: .combine)
    }
}

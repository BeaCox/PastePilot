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
    @State private var selectedTab: SettingsTab = .general
    @State private var showsResetConfirmation = false

    var body: some View {
        VStack(spacing: 0) {
            tabBar
            Divider()
            ScrollView {
                page
                    .padding(.horizontal, 38)
                    .padding(.vertical, 30)
            }
        }
        .frame(width: 700, height: 570)
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
    }

    private var tabBar: some View {
        HStack(spacing: 14) {
            ForEach(SettingsTab.allCases) { tab in
                Button {
                    selectedTab = tab
                } label: {
                    VStack(spacing: 5) {
                        Image(systemName: tab.symbol)
                            .font(.system(size: 29, weight: .regular))
                            .frame(height: 32)
                        Text(tab.title)
                            .font(.callout)
                    }
                    .foregroundStyle(
                        selectedTab == tab ? Color.accentColor : Color.secondary
                    )
                    .frame(width: 78, height: 76)
                    .background(
                        selectedTab == tab
                            ? Color.primary.opacity(0.06)
                            : Color.clear,
                        in: RoundedRectangle(cornerRadius: 12)
                    )
                    .overlay {
                        if selectedTab == tab {
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color.primary.opacity(0.08))
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
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
        SettingsPage(title: "General".localized) {
            SettingsSection {
                Toggle("Launch PastePilot at Login".localized, isOn: $settings.launchAtLogin)
                Toggle("Monitor Clipboard".localized, isOn: $settings.monitoringEnabled)
                SettingsNote("When disabled, existing history can still be searched and copied.".localized)
            }

            SettingsSection {
                SettingsRow(title: "Open PastePilot".localized) {
                    HotKeyRecorder(
                        keyCode: $settings.hotKeyCode,
                        modifiers: $settings.hotKeyModifiers
                    )
                }
                SettingsNote("Click the shortcut field and press a new combination; press Delete to reset.".localized)
            }
        }
    }

    private var storagePage: some View {
        SettingsPage(title: "Storage".localized) {
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
                SettingsNote("Pinned items are excluded from this limit and never auto-cleaned.".localized)
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
        SettingsPage(title: "Appearance".localized) {
            SettingsSection {
                Toggle("Show Details on Hover".localized, isOn: $settings.hoverPreviewEnabled)
                SettingsNote("Hover briefly to see full content, source app, and metadata.".localized)
            }

            SettingsSection {
                SettingsRow(title: "Menu Bar Window".localized) {
                    Text("400 × 450")
                        .foregroundStyle(.secondary)
                }
                SettingsNote("Compact window that follows the system light or dark appearance.".localized)
            }
        }
    }

    private var ignoredPage: some View {
        SettingsPage(title: "Ignored Apps".localized) {
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
        SettingsPage(title: "Advanced".localized) {
            SettingsSection {
                SettingsRow(title: "Local Data".localized) {
                    Button("Open Data Folder".localized, action: openDataFolder)
                }
                SettingsRow(title: "History".localized) {
                    Button("Clear Unpinned".localized, role: .destructive, action: clearUnpinnedHistory)
                }
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
    let title: String
    @ViewBuilder let content: Content

    init(title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(.title2.bold())
                .frame(maxWidth: .infinity)
                .padding(.bottom, 24)
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
        .padding(.vertical, 20)
        .overlay(alignment: .top) {
            Divider()
        }
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

    var body: some View {
        VStack(spacing: 18) {
            Image(nsImage: AppIconRenderer.icon(size: 256))
                .resizable()
                .scaledToFit()
                .frame(width: 84, height: 84)

            VStack(spacing: 5) {
                Text("PastePilot")
                    .font(.title.bold())
                Text("Smart Clipboard for Developers".localized)
                    .font(.headline)
                    .foregroundStyle(.secondary)
                Text("Version %@".localized(version))
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            Text("Understands JSON, code, terminal commands, errors, URLs, and images — suggests the next action. All data stays on your Mac.".localized)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .frame(maxWidth: 360)

            HStack(spacing: 18) {
                Label(
                    "%@ to open".localized(
                        HotKeyFormatter.display(
                            keyCode: settings.hotKeyCode,
                            modifiers: settings.hotKeyModifiers
                        )
                    ),
                    systemImage: "keyboard"
                )
                Label("Local Storage".localized, systemImage: "lock")
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            Button("Open Data Folder".localized, action: openDataFolder)
        }
        .padding(32)
        .frame(width: 460, height: 390)
    }
}

struct WelcomeView: View {
    let shortcut: String
    let dismiss: () -> Void
    @State private var accessibilityGranted = AXIsProcessTrusted()
    @State private var pollTimer: Timer?

    var body: some View {
        VStack(spacing: 22) {
            Image(nsImage: AppIconRenderer.icon(size: 256))
                .resizable()
                .scaledToFit()
                .frame(width: 80, height: 80)

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
                    title: "Accessibility".localized,
                    detail: accessibilityGranted
                        ? "Global shortcut is ready.".localized
                        : "Required for the global shortcut to work system-wide.".localized
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
                Button("Open Accessibility Settings".localized) {
                    let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
                    NSWorkspace.shared.open(url)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }

            VStack(spacing: 6) {
                Text("Press %@ to open PastePilot anytime.".localized(shortcut))
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
                    let trusted = AXIsProcessTrusted()
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
    }
}

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
    @State private var selectedTab: SettingsTab = .general
    @State private var showsResetConfirmation = false
    @State private var showsClearHistoryConfirmation = false
    @State private var accessibilityGranted = EventPostingPermission.isGranted
    @State private var accessibilityPollTimer: Timer?
    @State private var pageHeights: [AnyHashable: CGFloat] = [:]

    // Fit the window to the selected page's measured content, clamped so it
    // never gets tiny or taller than a comfortable on-screen size (beyond
    // which the page scrolls).
    private var preferredHeight: CGFloat {
        let measured = pageHeights[AnyHashable(selectedTab)] ?? 360
        return min(640, max(240, measured))
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            generalPage
                .tabItem {
                    Label(SettingsTab.general.title, systemImage: SettingsTab.general.symbol)
                }
                .tag(SettingsTab.general)

            storagePage
                .tabItem {
                    Label(SettingsTab.storage.title, systemImage: SettingsTab.storage.symbol)
                }
                .tag(SettingsTab.storage)

            appearancePage
                .tabItem {
                    Label(SettingsTab.appearance.title, systemImage: SettingsTab.appearance.symbol)
                }
                .tag(SettingsTab.appearance)

            ignoredPage
                .tabItem {
                    Label(SettingsTab.ignored.title, systemImage: SettingsTab.ignored.symbol)
                }
                .tag(SettingsTab.ignored)

            advancedPage
                .tabItem {
                    Label(SettingsTab.advanced.title, systemImage: SettingsTab.advanced.symbol)
                }
                .tag(SettingsTab.advanced)
        }
        .frame(width: 620, height: preferredHeight)
        .onPreferenceChange(SettingsHeightKey.self) { pageHeights = $0 }
        .animation(.easeInOut(duration: 0.18), value: preferredHeight)
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

    private var generalPage: some View {
        SettingsPane(id: SettingsTab.general) {
            SettingsGroup {
                Toggle("Launch PastePilot at Login".localized, isOn: $settings.launchAtLogin)
                Toggle("Monitor Clipboard".localized, isOn: $settings.monitoringEnabled)
                SettingsNote("When disabled, existing history can still be searched and copied.".localized)
            }

            SettingsGroup(title: "Global Shortcuts".localized) {
                SettingsRow(title: "Open PastePilot".localized) {
                    HotKeyRecorder(
                        keyCode: $settings.hotKeyCode,
                        modifiers: $settings.hotKeyModifiers
                    )
                    .frame(width: 190, height: 34)
                }
                SettingsRow(title: "Paste as Plain Text".localized) {
                    HotKeyRecorder(
                        keyCode: $settings.plainTextHotKeyCode,
                        modifiers: $settings.plainTextHotKeyModifiers,
                        defaultKeyCode: AppSettings.defaultPlainTextHotKeyCode,
                        defaultModifiers: AppSettings.defaultPlainTextHotKeyModifiers,
                        accessibilityLabel: "Paste as Plain Text Shortcut".localized
                    )
                    .frame(width: 190, height: 34)
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

            SettingsGroup {
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
        SettingsPane(id: SettingsTab.storage) {
            SettingsGroup {
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

            SettingsGroup {
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
            }
        }
    }

    private var appearancePage: some View {
        SettingsPane(id: SettingsTab.appearance) {
            SettingsGroup {
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

            SettingsGroup {
                Toggle("Show Details on Hover".localized, isOn: $settings.hoverPreviewEnabled)
                SettingsNote("Hover briefly to see full content, source app, and metadata.".localized)
                Toggle("Animate Preview".localized, isOn: $settings.previewAnimationEnabled)
                SettingsNote("Fade the detail preview in and out. Switching apps always closes it instantly.".localized)
            }

            SettingsGroup {
                SettingsRow(title: "After Copying".localized) {
                    Picker("", selection: $settings.pasteCloseBehavior) {
                        Text("Keep Panel Open".localized)
                            .tag(PasteCloseBehavior.keepOpen.rawValue)
                        Text("Close Preview".localized)
                            .tag(PasteCloseBehavior.closePreview.rawValue)
                        Text("Close Panel".localized)
                            .tag(PasteCloseBehavior.closePanel.rawValue)
                    }
                    .labelsHidden()
                    .frame(width: 180)
                }
                SettingsNote("Choose what closes after you copy or transform an item.".localized)
            }

            SettingsGroup {
                SettingsRow(title: "Menu Bar Window".localized) {
                    Text("Adaptive".localized)
                        .foregroundStyle(.secondary)
                }
                SettingsNote("The window grows with your results and follows the system light or dark appearance.".localized)
            }
        }
    }

    private var ignoredPage: some View {
        SettingsPane(id: SettingsTab.ignored) {
            SettingsGroup {
                IgnoredAppsEditor(settings: settings)
            }

            SettingsGroup {
                Label("Ignore rules only affect new copies and won't delete existing history.".localized, systemImage: "info.circle")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var advancedPage: some View {
        SettingsPane(id: SettingsTab.advanced) {
            SettingsGroup {
                SettingsRow(title: "Local Data".localized) {
                    Button("Open Data Folder".localized, action: openDataFolder)
                }
                SettingsRow(title: "History".localized) {
                    Button("Clear Unpinned".localized, role: .destructive) {
                        showsClearHistoryConfirmation = true
                    }
                }
            }

            SettingsGroup {
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

            SettingsGroup {
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

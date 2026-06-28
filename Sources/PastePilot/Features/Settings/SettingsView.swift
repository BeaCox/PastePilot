import AppKit
import SwiftUI

enum SettingsTab: String, CaseIterable, Identifiable {
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
    @ObservedObject var store: ClipboardStore
    let openDataFolder: () -> Void
    let clearUnpinnedHistory: () -> Void
    let updateController: UpdateController
    @State private var selectedTab: SettingsTab = .general
    @State private var showsResetConfirmation = false
    @State private var showsClearHistoryConfirmation = false
    @State private var accessibilityGranted = EventPostingPermission.isGranted
    @State private var accessibilityPollTimer: Timer?
    @State private var pageHeights: [SettingsTab: CGFloat] = [:]

    // Fit the window to the selected page's measured content, clamped so it
    // never gets tiny or taller than a comfortable on-screen size (beyond
    // which the page scrolls).
    private var preferredHeight: CGFloat {
        let measured = pageHeights[selectedTab] ?? 360
        return min(640, max(240, measured))
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            GeneralSettingsPage(
                settings: settings,
                accessibilityGranted: accessibilityGranted,
                requestPermission: requestEventPostingPermission
            )
                .tabItem {
                    Label(SettingsTab.general.title, systemImage: SettingsTab.general.symbol)
                }
                .tag(SettingsTab.general)

            StorageSettingsPage(
                settings: settings,
                storageByteCount: store.localStorageByteCount(),
                rerunOCR: store.rerunOCRForImages
            )
                .tabItem {
                    Label(SettingsTab.storage.title, systemImage: SettingsTab.storage.symbol)
                }
                .tag(SettingsTab.storage)

            AppearanceSettingsPage(settings: settings)
                .tabItem {
                    Label(SettingsTab.appearance.title, systemImage: SettingsTab.appearance.symbol)
                }
                .tag(SettingsTab.appearance)

            IgnoredAppsSettingsPage(settings: settings)
                .tabItem {
                    Label(SettingsTab.ignored.title, systemImage: SettingsTab.ignored.symbol)
                }
                .tag(SettingsTab.ignored)

            AdvancedSettingsPage(
                openDataFolder: openDataFolder,
                showClearHistoryConfirmation: {
                    showsClearHistoryConfirmation = true
                },
                updateController: updateController,
                showResetConfirmation: {
                    showsResetConfirmation = true
                }
            )
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

    private func refreshAccessibilityStatus() {
        accessibilityGranted = EventPostingPermission.isGranted
    }

    private func requestEventPostingPermission() {
        accessibilityGranted = EventPostingPermission.request()
    }
}

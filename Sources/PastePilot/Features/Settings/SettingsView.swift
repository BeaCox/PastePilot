import AppKit
import SwiftUI

enum SettingsTab: String, CaseIterable, Identifiable {
    case general
    case storage
    case appearance
    case actions
    case ignored
    case advanced

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: "General".localized
        case .storage: "Storage".localized
        case .appearance: "Appearance".localized
        case .actions: "Actions".localized
        case .ignored: "Ignored Apps".localized
        case .advanced: "Advanced".localized
        }
    }

    var symbol: String {
        switch self {
        case .general: "gearshape"
        case .storage: "internaldrive"
        case .appearance: "paintpalette"
        case .actions: "wand.and.stars"
        case .ignored: "nosign"
        case .advanced: "gearshape.2"
        }
    }
}

struct SettingsView: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var store: ClipboardStore
    let openDataFolder: () -> Void
    let exportBackup: () -> Void
    let restoreBackup: () -> Void
    let clearUnpinnedHistory: () -> Void
    let updateController: UpdateController
    @State private var selectedTab: SettingsTab = .general
    @State private var showsResetConfirmation = false
    @State private var showsClearHistoryConfirmation = false
    @State private var accessibilityGranted = EventPostingPermission.isGranted
    @State private var accessibilityPollTimer: Timer?
    @State private var storageByteCount: Int64 = 0

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
                storageByteCount: storageByteCount,
                rerunOCR: store.rerunOCRForImages,
                rerunBarcodeDetection: store.rerunBarcodeDetectionForImages
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

            CustomActionsSettingsPage(settings: settings)
                .tabItem {
                    Label(SettingsTab.actions.title, systemImage: SettingsTab.actions.symbol)
                }
                .tag(SettingsTab.actions)

            IgnoredAppsSettingsPage(settings: settings)
                .tabItem {
                    Label(SettingsTab.ignored.title, systemImage: SettingsTab.ignored.symbol)
                }
                .tag(SettingsTab.ignored)

            AdvancedSettingsPage(
                openDataFolder: openDataFolder,
                exportBackup: exportBackup,
                restoreBackup: restoreBackup,
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
        .frame(width: 620, height: 520)
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
        .task(id: "\(selectedTab.rawValue)-\(store.items.count)") {
            guard selectedTab == .storage else { return }
            let repository = store.historyRepository
            let bytes = await Task.detached(priority: .utility) {
                repository.dataDirectoryByteCount()
            }.value
            guard !Task.isCancelled else { return }
            storageByteCount = bytes
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

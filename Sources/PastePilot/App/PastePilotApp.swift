import SwiftUI

@main
struct PastePilotApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            SettingsView(
                settings: appDelegate.settings,
                store: appDelegate.store,
                openDataFolder: appDelegate.openDataFolder,
                clearUnpinnedHistory: appDelegate.clearUnpinnedHistory,
                updateController: appDelegate.updateController
            )
            .pastePilotAppearance(appDelegate.settings)
        }
    }
}

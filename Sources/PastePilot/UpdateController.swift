import AppKit
import Sparkle

@MainActor
final class UpdateController: NSObject, SPUUpdaterDelegate {
    private lazy var controller = SPUStandardUpdaterController(
        startingUpdater: false,
        updaterDelegate: self,
        userDriverDelegate: nil
    )

    var automaticallyChecksForUpdates: Bool {
        get { controller.updater.automaticallyChecksForUpdates }
        set { controller.updater.automaticallyChecksForUpdates = newValue }
    }

    var canCheckForUpdates: Bool {
        isConfigured && controller.updater.canCheckForUpdates
    }

    func start() {
        guard isConfigured else { return }
        controller.startUpdater()
    }

    func checkForUpdates() {
        if isConfigured {
            controller.checkForUpdates(nil)
        } else if let releasesURL = URL(
            string: "https://github.com/BeaCox/PastePilot/releases"
        ) {
            NSWorkspace.shared.open(releasesURL)
        }
    }

    func feedURLString(for updater: SPUUpdater) -> String? {
#if arch(arm64)
        let architecture = "arm64"
#elseif arch(x86_64)
        let architecture = "x86_64"
#else
        return nil
#endif
        return "https://github.com/BeaCox/PastePilot/releases/latest/download/appcast-\(architecture).xml"
    }

    private var isConfigured: Bool {
        Bundle.main.object(forInfoDictionaryKey: "SUPublicEDKey") != nil
    }
}

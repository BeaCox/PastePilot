import Foundation

final class AppSettings: ObservableObject {
    static let shared = AppSettings()

    private enum Key {
        static let monitoringEnabled = "monitoringEnabled"
        static let hoverPreviewEnabled = "hoverPreviewEnabled"
        static let historyLimit = "historyLimit"
        static let launchAtLogin = "launchAtLogin"
        static let imageSizeLimitMB = "imageSizeLimitMB"
        static let ignoredBundleIdentifiers = "ignoredBundleIdentifiers"
        static let hotKeyCode = "hotKeyCode"
        static let hotKeyModifiers = "hotKeyModifiers"
        static let menuBarIconStyle = "menuBarIconStyle"
        static let historyTimeoutSeconds = "historyTimeoutSeconds"
    }

    private let defaults: UserDefaults

    @Published var monitoringEnabled: Bool {
        didSet { defaults.set(monitoringEnabled, forKey: Key.monitoringEnabled) }
    }

    @Published var hoverPreviewEnabled: Bool {
        didSet { defaults.set(hoverPreviewEnabled, forKey: Key.hoverPreviewEnabled) }
    }

    @Published var historyLimit: Int {
        didSet { defaults.set(historyLimit, forKey: Key.historyLimit) }
    }

    @Published var launchAtLogin: Bool {
        didSet { defaults.set(launchAtLogin, forKey: Key.launchAtLogin) }
    }

    @Published var imageSizeLimitMB: Int {
        didSet { defaults.set(imageSizeLimitMB, forKey: Key.imageSizeLimitMB) }
    }

    @Published var ignoredBundleIdentifiers: String {
        didSet {
            defaults.set(
                ignoredBundleIdentifiers,
                forKey: Key.ignoredBundleIdentifiers
            )
        }
    }

    @Published var hotKeyCode: Int {
        didSet { defaults.set(hotKeyCode, forKey: Key.hotKeyCode) }
    }

    @Published var hotKeyModifiers: UInt32 {
        didSet { defaults.set(Int(hotKeyModifiers), forKey: Key.hotKeyModifiers) }
    }

    @Published var menuBarIconStyle: String {
        didSet { defaults.set(menuBarIconStyle, forKey: Key.menuBarIconStyle) }
    }

    @Published var historyTimeoutSeconds: Int {
        didSet { defaults.set(historyTimeoutSeconds, forKey: Key.historyTimeoutSeconds) }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        defaults.register(defaults: [
            Key.monitoringEnabled: true,
            Key.hoverPreviewEnabled: true,
            Key.historyLimit: 100,
            Key.launchAtLogin: false,
            Key.imageSizeLimitMB: 25,
            Key.ignoredBundleIdentifiers: "",
            Key.hotKeyCode: 49,
            Key.hotKeyModifiers: 2_048,
            Key.menuBarIconStyle: MenuBarIconStyle.pastepilot.rawValue,
            Key.historyTimeoutSeconds: 0
        ])
        monitoringEnabled = defaults.bool(forKey: Key.monitoringEnabled)
        hoverPreviewEnabled = defaults.bool(forKey: Key.hoverPreviewEnabled)
        historyLimit = defaults.integer(forKey: Key.historyLimit)
        launchAtLogin = defaults.bool(forKey: Key.launchAtLogin)
        imageSizeLimitMB = defaults.integer(forKey: Key.imageSizeLimitMB)
        ignoredBundleIdentifiers = defaults.string(
            forKey: Key.ignoredBundleIdentifiers
        ) ?? ""
        hotKeyCode = defaults.integer(forKey: Key.hotKeyCode)
        hotKeyModifiers = UInt32(defaults.integer(forKey: Key.hotKeyModifiers))
        menuBarIconStyle = defaults.string(forKey: Key.menuBarIconStyle)
            ?? MenuBarIconStyle.pastepilot.rawValue
        historyTimeoutSeconds = defaults.integer(forKey: Key.historyTimeoutSeconds)
    }

    var ignoredBundleIdentifierSet: Set<String> {
        Set(
            ignoredBundleIdentifiers
                .components(separatedBy: .newlines)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        )
    }

    func reset() {
        monitoringEnabled = true
        hoverPreviewEnabled = true
        historyLimit = 100
        launchAtLogin = false
        imageSizeLimitMB = 25
        ignoredBundleIdentifiers = ""
        hotKeyCode = 49
        hotKeyModifiers = 2_048
        menuBarIconStyle = MenuBarIconStyle.pastepilot.rawValue
        historyTimeoutSeconds = 0
    }
}

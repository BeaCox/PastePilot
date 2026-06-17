import Carbon
import Foundation

enum PasteCloseBehavior: String, CaseIterable {
    case keepOpen
    case closePreview
    case closePanel
}

final class AppSettings: ObservableObject {
    static let shared = AppSettings()
    static let defaultOpenHotKeyCode = kVK_Space
    static let defaultOpenHotKeyModifiers = UInt32(optionKey)
    static let defaultPlainTextHotKeyCode = kVK_ANSI_V
    static let defaultPlainTextHotKeyModifiers = UInt32(
        optionKey | shiftKey | cmdKey
    )
    static let defaultHistoryLimit = 100
    static let supportedHistoryLimits = [50, 100, 200, 500]
    static let defaultImageSizeLimitMB = 25
    static let supportedImageSizeLimitsMB = [5, 10, 25, 50]
    static let defaultHistoryTimeoutSeconds = 0
    static let supportedHistoryTimeoutsSeconds = [
        0,
        3_600,
        86_400,
        604_800,
        2_592_000
    ]

    private enum Key {
        static let monitoringEnabled = "monitoringEnabled"
        static let hoverPreviewEnabled = "hoverPreviewEnabled"
        static let historyLimit = "historyLimit"
        static let launchAtLogin = "launchAtLogin"
        static let imageSizeLimitMB = "imageSizeLimitMB"
        static let ignoredBundleIdentifiers = "ignoredBundleIdentifiers"
        static let hotKeyCode = "hotKeyCode"
        static let hotKeyModifiers = "hotKeyModifiers"
        static let plainTextHotKeyCode = "plainTextHotKeyCode"
        static let plainTextHotKeyModifiers = "plainTextHotKeyModifiers"
        static let menuBarIconStyle = "menuBarIconStyle"
        static let historyTimeoutSeconds = "historyTimeoutSeconds"
        static let pasteCloseBehavior = "pasteCloseBehavior"
        static let previewAnimationEnabled = "previewAnimationEnabled"
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

    @Published var plainTextHotKeyCode: Int {
        didSet { defaults.set(plainTextHotKeyCode, forKey: Key.plainTextHotKeyCode) }
    }

    @Published var plainTextHotKeyModifiers: UInt32 {
        didSet {
            defaults.set(
                Int(plainTextHotKeyModifiers),
                forKey: Key.plainTextHotKeyModifiers
            )
        }
    }

    @Published var menuBarIconStyle: String {
        didSet { defaults.set(menuBarIconStyle, forKey: Key.menuBarIconStyle) }
    }

    @Published var historyTimeoutSeconds: Int {
        didSet { defaults.set(historyTimeoutSeconds, forKey: Key.historyTimeoutSeconds) }
    }

    @Published var pasteCloseBehavior: String {
        didSet { defaults.set(pasteCloseBehavior, forKey: Key.pasteCloseBehavior) }
    }

    @Published var previewAnimationEnabled: Bool {
        didSet { defaults.set(previewAnimationEnabled, forKey: Key.previewAnimationEnabled) }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        defaults.register(defaults: [
            Key.monitoringEnabled: true,
            Key.hoverPreviewEnabled: true,
            Key.historyLimit: Self.defaultHistoryLimit,
            Key.launchAtLogin: false,
            Key.imageSizeLimitMB: Self.defaultImageSizeLimitMB,
            Key.ignoredBundleIdentifiers: "",
            Key.hotKeyCode: Self.defaultOpenHotKeyCode,
            Key.hotKeyModifiers: Self.defaultOpenHotKeyModifiers,
            Key.plainTextHotKeyCode: Self.defaultPlainTextHotKeyCode,
            Key.plainTextHotKeyModifiers: Self.defaultPlainTextHotKeyModifiers,
            Key.menuBarIconStyle: MenuBarIconStyle.pastepilot.rawValue,
            Key.historyTimeoutSeconds: Self.defaultHistoryTimeoutSeconds,
            Key.pasteCloseBehavior: PasteCloseBehavior.closePreview.rawValue,
            Key.previewAnimationEnabled: true
        ])
        monitoringEnabled = defaults.bool(forKey: Key.monitoringEnabled)
        hoverPreviewEnabled = defaults.bool(forKey: Key.hoverPreviewEnabled)
        historyLimit = Self.supportedValue(
            defaults.integer(forKey: Key.historyLimit),
            in: Self.supportedHistoryLimits,
            default: Self.defaultHistoryLimit
        )
        launchAtLogin = defaults.bool(forKey: Key.launchAtLogin)
        imageSizeLimitMB = Self.supportedValue(
            defaults.integer(forKey: Key.imageSizeLimitMB),
            in: Self.supportedImageSizeLimitsMB,
            default: Self.defaultImageSizeLimitMB
        )
        ignoredBundleIdentifiers = defaults.string(
            forKey: Key.ignoredBundleIdentifiers
        ) ?? ""
        hotKeyCode = defaults.integer(forKey: Key.hotKeyCode)
        hotKeyModifiers = UInt32(defaults.integer(forKey: Key.hotKeyModifiers))
        plainTextHotKeyCode = defaults.integer(forKey: Key.plainTextHotKeyCode)
        plainTextHotKeyModifiers = UInt32(
            defaults.integer(forKey: Key.plainTextHotKeyModifiers)
        )
        let storedIconStyle = defaults.string(forKey: Key.menuBarIconStyle)
        menuBarIconStyle = storedIconStyle.flatMap(MenuBarIconStyle.init(rawValue:))?
            .rawValue ?? MenuBarIconStyle.pastepilot.rawValue
        historyTimeoutSeconds = Self.supportedValue(
            defaults.integer(forKey: Key.historyTimeoutSeconds),
            in: Self.supportedHistoryTimeoutsSeconds,
            default: Self.defaultHistoryTimeoutSeconds
        )
        let storedPasteCloseBehavior = defaults.string(forKey: Key.pasteCloseBehavior)
        pasteCloseBehavior = storedPasteCloseBehavior
            .flatMap(PasteCloseBehavior.init(rawValue:))?
            .rawValue ?? PasteCloseBehavior.closePreview.rawValue
        previewAnimationEnabled = defaults.bool(forKey: Key.previewAnimationEnabled)
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
        historyLimit = Self.defaultHistoryLimit
        launchAtLogin = false
        imageSizeLimitMB = Self.defaultImageSizeLimitMB
        ignoredBundleIdentifiers = ""
        hotKeyCode = Self.defaultOpenHotKeyCode
        hotKeyModifiers = Self.defaultOpenHotKeyModifiers
        plainTextHotKeyCode = Self.defaultPlainTextHotKeyCode
        plainTextHotKeyModifiers = Self.defaultPlainTextHotKeyModifiers
        menuBarIconStyle = MenuBarIconStyle.pastepilot.rawValue
        historyTimeoutSeconds = Self.defaultHistoryTimeoutSeconds
        pasteCloseBehavior = PasteCloseBehavior.closePreview.rawValue
        previewAnimationEnabled = true
    }

    private static func supportedValue(
        _ value: Int,
        in supportedValues: [Int],
        default defaultValue: Int
    ) -> Int {
        supportedValues.contains(value) ? value : defaultValue
    }
}

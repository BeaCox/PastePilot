import Carbon
import Foundation

enum PasteCloseBehavior: String, CaseIterable {
    case keepOpen
    case closePreview
    case closePanel
}

enum OCRRecognitionMode: String, CaseIterable {
    case off
    case fast
    case accurate

    var title: String {
        switch self {
        case .off:
            "Off".localized
        case .fast:
            "Fast".localized
        case .accurate:
            "Accurate".localized
        }
    }
}

enum OCRLanguageMode: String, CaseIterable {
    case system
    case english
    case multilingual

    var title: String {
        switch self {
        case .system:
            "System Language".localized
        case .english:
            "English Only".localized
        case .multilingual:
            "Multilingual".localized
        }
    }
}

final class AppSettings: ObservableObject {
    static let shared = AppSettings()
    static let defaultOpenHotKeyCode = kVK_Space
    static let defaultOpenHotKeyModifiers = UInt32(optionKey)
    static let defaultPlainTextHotKeyCode = kVK_ANSI_V
    static let defaultPlainTextHotKeyModifiers = UInt32(
        optionKey | shiftKey | cmdKey
    )
    static let supportedHotKeyCodes: Set<Int> = [
        kVK_ANSI_A, kVK_ANSI_B, kVK_ANSI_C, kVK_ANSI_D, kVK_ANSI_E,
        kVK_ANSI_F, kVK_ANSI_G, kVK_ANSI_H, kVK_ANSI_I, kVK_ANSI_J,
        kVK_ANSI_K, kVK_ANSI_L, kVK_ANSI_M, kVK_ANSI_N, kVK_ANSI_O,
        kVK_ANSI_P, kVK_ANSI_Q, kVK_ANSI_R, kVK_ANSI_S, kVK_ANSI_T,
        kVK_ANSI_U, kVK_ANSI_V, kVK_ANSI_W, kVK_ANSI_X, kVK_ANSI_Y,
        kVK_ANSI_Z, kVK_ANSI_0, kVK_ANSI_1, kVK_ANSI_2, kVK_ANSI_3,
        kVK_ANSI_4, kVK_ANSI_5, kVK_ANSI_6, kVK_ANSI_7, kVK_ANSI_8,
        kVK_ANSI_9, kVK_Space, kVK_Return, kVK_Tab, kVK_Escape,
        kVK_Delete, kVK_ForwardDelete, kVK_Home, kVK_End, kVK_PageUp,
        kVK_PageDown, kVK_LeftArrow, kVK_RightArrow, kVK_UpArrow,
        kVK_DownArrow, kVK_F1, kVK_F2, kVK_F3, kVK_F4, kVK_F5,
        kVK_F6, kVK_F7, kVK_F8, kVK_F9, kVK_F10, kVK_F11, kVK_F12
    ]
    static let supportedHotKeyModifierMask = UInt32(
        controlKey | optionKey | shiftKey | cmdKey
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
    static let defaultOCRRecognitionMode = OCRRecognitionMode.accurate.rawValue
    static let defaultOCRLanguageMode = OCRLanguageMode.multilingual.rawValue

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
        static let ocrRecognitionMode = "ocrRecognitionMode"
        static let ocrLanguageMode = "ocrLanguageMode"
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

    @Published var ocrRecognitionMode: String {
        didSet { defaults.set(ocrRecognitionMode, forKey: Key.ocrRecognitionMode) }
    }

    @Published var ocrLanguageMode: String {
        didSet { defaults.set(ocrLanguageMode, forKey: Key.ocrLanguageMode) }
    }

    @Published var hotKeyRegistrationWarning: String?

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
            Key.previewAnimationEnabled: true,
            Key.ocrRecognitionMode: Self.defaultOCRRecognitionMode,
            Key.ocrLanguageMode: Self.defaultOCRLanguageMode
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
        let openHotKey = Self.validatedHotKey(
            keyCode: defaults.integer(forKey: Key.hotKeyCode),
            modifiers: UInt32(defaults.integer(forKey: Key.hotKeyModifiers)),
            defaultKeyCode: Self.defaultOpenHotKeyCode,
            defaultModifiers: Self.defaultOpenHotKeyModifiers
        )
        hotKeyCode = openHotKey.keyCode
        hotKeyModifiers = openHotKey.modifiers
        let plainTextHotKey = Self.validatedHotKey(
            keyCode: defaults.integer(forKey: Key.plainTextHotKeyCode),
            modifiers: UInt32(defaults.integer(forKey: Key.plainTextHotKeyModifiers)),
            defaultKeyCode: Self.defaultPlainTextHotKeyCode,
            defaultModifiers: Self.defaultPlainTextHotKeyModifiers
        )
        plainTextHotKeyCode = plainTextHotKey.keyCode
        plainTextHotKeyModifiers = plainTextHotKey.modifiers
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
        let storedOCRRecognitionMode = defaults.string(forKey: Key.ocrRecognitionMode)
        ocrRecognitionMode = storedOCRRecognitionMode
            .flatMap(OCRRecognitionMode.init(rawValue:))?
            .rawValue ?? Self.defaultOCRRecognitionMode
        let storedOCRLanguageMode = defaults.string(forKey: Key.ocrLanguageMode)
        ocrLanguageMode = storedOCRLanguageMode
            .flatMap(OCRLanguageMode.init(rawValue:))?
            .rawValue ?? Self.defaultOCRLanguageMode
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
        ocrRecognitionMode = Self.defaultOCRRecognitionMode
        ocrLanguageMode = Self.defaultOCRLanguageMode
    }

    private static func supportedValue(
        _ value: Int,
        in supportedValues: [Int],
        default defaultValue: Int
    ) -> Int {
        supportedValues.contains(value) ? value : defaultValue
    }

    private static func validatedHotKey(
        keyCode: Int,
        modifiers: UInt32,
        defaultKeyCode: Int,
        defaultModifiers: UInt32
    ) -> (keyCode: Int, modifiers: UInt32) {
        let modifiersAreSupported = modifiers != 0
            && modifiers & ~supportedHotKeyModifierMask == 0
        guard supportedHotKeyCodes.contains(keyCode), modifiersAreSupported else {
            return (defaultKeyCode, defaultModifiers)
        }
        return (keyCode, modifiers)
    }
}

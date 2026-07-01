import Carbon
import Foundation

enum PasteCloseBehavior: String, CaseIterable {
    case keepOpen
    case closePreview
    case closePanel
}

enum SensitiveContentStoragePolicy: String, CaseIterable {
    case storeOriginal
    case storeRedacted
    case skip

    var title: String {
        switch self {
        case .storeOriginal:
            "Save Original".localized
        case .storeRedacted:
            "Save Redacted".localized
        case .skip:
            "Do Not Save".localized
        }
    }
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
    @MainActor static let shared = AppSettings()
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
    static let defaultStorageLimitMB = 0
    static let supportedStorageLimitsMB = [0, 1, 100, 250, 500, 1_024]
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
    static let defaultAppearanceMode = AppAppearanceMode.system.rawValue
    static let defaultSensitiveContentStoragePolicy =
        SensitiveContentStoragePolicy.storeOriginal.rawValue

    private struct AppSetting<Value: Sendable>: Sendable {
        let key: String
        let defaultValue: Value

        init(_ key: String, default defaultValue: Value) {
            self.key = key
            self.defaultValue = defaultValue
        }
    }

    private enum Setting {
        static let monitoringEnabled = AppSetting("monitoringEnabled", default: true)
        static let hoverPreviewEnabled = AppSetting("hoverPreviewEnabled", default: true)
        static let historyLimit = AppSetting(
            "historyLimit",
            default: AppSettings.defaultHistoryLimit
        )
        static let launchAtLogin = AppSetting("launchAtLogin", default: false)
        static let imageSizeLimitMB = AppSetting(
            "imageSizeLimitMB",
            default: AppSettings.defaultImageSizeLimitMB
        )
        static let storageLimitMB = AppSetting(
            "storageLimitMB",
            default: AppSettings.defaultStorageLimitMB
        )
        static let ignoredBundleIdentifiers = AppSetting(
            "ignoredBundleIdentifiers",
            default: ""
        )
        static let hotKeyCode = AppSetting(
            "hotKeyCode",
            default: AppSettings.defaultOpenHotKeyCode
        )
        static let hotKeyModifiers = AppSetting(
            "hotKeyModifiers",
            default: AppSettings.defaultOpenHotKeyModifiers
        )
        static let plainTextHotKeyCode = AppSetting(
            "plainTextHotKeyCode",
            default: AppSettings.defaultPlainTextHotKeyCode
        )
        static let plainTextHotKeyModifiers = AppSetting(
            "plainTextHotKeyModifiers",
            default: AppSettings.defaultPlainTextHotKeyModifiers
        )
        static let menuBarIconStyle = AppSetting(
            "menuBarIconStyle",
            default: MenuBarIconStyle.pastepilot.rawValue
        )
        static let historyTimeoutSeconds = AppSetting(
            "historyTimeoutSeconds",
            default: AppSettings.defaultHistoryTimeoutSeconds
        )
        static let pasteCloseBehavior = AppSetting(
            "pasteCloseBehavior",
            default: PasteCloseBehavior.closePreview.rawValue
        )
        static let previewAnimationEnabled = AppSetting(
            "previewAnimationEnabled",
            default: true
        )
        static let appearanceMode = AppSetting(
            "appearanceMode",
            default: AppSettings.defaultAppearanceMode
        )
        static let ocrRecognitionMode = AppSetting(
            "ocrRecognitionMode",
            default: AppSettings.defaultOCRRecognitionMode
        )
        static let ocrLanguageMode = AppSetting(
            "ocrLanguageMode",
            default: AppSettings.defaultOCRLanguageMode
        )
        static let sensitiveContentStoragePolicy = AppSetting(
            "sensitiveContentStoragePolicy",
            default: AppSettings.defaultSensitiveContentStoragePolicy
        )

        static var registeredDefaults: [String: Any] {
            [
                monitoringEnabled.key: monitoringEnabled.defaultValue,
                hoverPreviewEnabled.key: hoverPreviewEnabled.defaultValue,
                historyLimit.key: historyLimit.defaultValue,
                launchAtLogin.key: launchAtLogin.defaultValue,
                imageSizeLimitMB.key: imageSizeLimitMB.defaultValue,
                storageLimitMB.key: storageLimitMB.defaultValue,
                ignoredBundleIdentifiers.key: ignoredBundleIdentifiers.defaultValue,
                hotKeyCode.key: hotKeyCode.defaultValue,
                hotKeyModifiers.key: hotKeyModifiers.defaultValue,
                plainTextHotKeyCode.key: plainTextHotKeyCode.defaultValue,
                plainTextHotKeyModifiers.key: plainTextHotKeyModifiers.defaultValue,
                menuBarIconStyle.key: menuBarIconStyle.defaultValue,
                historyTimeoutSeconds.key: historyTimeoutSeconds.defaultValue,
                pasteCloseBehavior.key: pasteCloseBehavior.defaultValue,
                previewAnimationEnabled.key: previewAnimationEnabled.defaultValue,
                appearanceMode.key: appearanceMode.defaultValue,
                ocrRecognitionMode.key: ocrRecognitionMode.defaultValue,
                ocrLanguageMode.key: ocrLanguageMode.defaultValue,
                sensitiveContentStoragePolicy.key:
                    sensitiveContentStoragePolicy.defaultValue,
            ]
        }
    }

    private let defaults: UserDefaults

    @Published var monitoringEnabled: Bool {
        didSet { persist(monitoringEnabled, for: Setting.monitoringEnabled) }
    }

    @Published var hoverPreviewEnabled: Bool {
        didSet { persist(hoverPreviewEnabled, for: Setting.hoverPreviewEnabled) }
    }

    @Published var historyLimit: Int {
        didSet {
            persistSupportedValue(
                historyLimit,
                supportedValue: Self.supportedInteger(
                    historyLimit,
                    for: Setting.historyLimit,
                    supportedValues: Self.supportedHistoryLimits
                ),
                assign: { historyLimit = $0 },
                persist: { persist($0, for: Setting.historyLimit) }
            )
        }
    }

    @Published var launchAtLogin: Bool {
        didSet { persist(launchAtLogin, for: Setting.launchAtLogin) }
    }

    @Published var imageSizeLimitMB: Int {
        didSet {
            persistSupportedValue(
                imageSizeLimitMB,
                supportedValue: Self.supportedInteger(
                    imageSizeLimitMB,
                    for: Setting.imageSizeLimitMB,
                    supportedValues: Self.supportedImageSizeLimitsMB
                ),
                assign: { imageSizeLimitMB = $0 },
                persist: { persist($0, for: Setting.imageSizeLimitMB) }
            )
        }
    }

    @Published var storageLimitMB: Int {
        didSet {
            persistSupportedValue(
                storageLimitMB,
                supportedValue: Self.supportedInteger(
                    storageLimitMB,
                    for: Setting.storageLimitMB,
                    supportedValues: Self.supportedStorageLimitsMB
                ),
                assign: { storageLimitMB = $0 },
                persist: { persist($0, for: Setting.storageLimitMB) }
            )
        }
    }

    @Published var ignoredBundleIdentifiers: String {
        didSet {
            persist(
                ignoredBundleIdentifiers,
                for: Setting.ignoredBundleIdentifiers
            )
        }
    }

    @Published var hotKeyCode: Int {
        didSet {
            persistSupportedValue(
                hotKeyCode,
                supportedValue: Self.supportedHotKeyCode(hotKeyCode),
                assign: { hotKeyCode = $0 },
                persist: { persist($0, for: Setting.hotKeyCode) }
            )
        }
    }

    @Published var hotKeyModifiers: UInt32 {
        didSet {
            persistSupportedValue(
                hotKeyModifiers,
                supportedValue: Self.supportedHotKeyModifiers(hotKeyModifiers),
                assign: { hotKeyModifiers = $0 },
                persist: { persist($0, for: Setting.hotKeyModifiers) }
            )
        }
    }

    @Published var plainTextHotKeyCode: Int {
        didSet {
            persistSupportedValue(
                plainTextHotKeyCode,
                supportedValue: Self.supportedHotKeyCode(
                    plainTextHotKeyCode,
                    default: Self.defaultPlainTextHotKeyCode
                ),
                assign: { plainTextHotKeyCode = $0 },
                persist: { persist($0, for: Setting.plainTextHotKeyCode) }
            )
        }
    }

    @Published var plainTextHotKeyModifiers: UInt32 {
        didSet {
            persistSupportedValue(
                plainTextHotKeyModifiers,
                supportedValue: Self.supportedHotKeyModifiers(
                    plainTextHotKeyModifiers,
                    default: Self.defaultPlainTextHotKeyModifiers
                ),
                assign: { plainTextHotKeyModifiers = $0 },
                persist: { persist($0, for: Setting.plainTextHotKeyModifiers) }
            )
        }
    }

    @Published var menuBarIconStyle: String {
        didSet {
            persistSupportedValue(
                menuBarIconStyle,
                supportedValue: Self.supportedRawValue(
                    menuBarIconStyle,
                    for: Setting.menuBarIconStyle,
                    as: MenuBarIconStyle.self
                ),
                assign: { menuBarIconStyle = $0 },
                persist: { persist($0, for: Setting.menuBarIconStyle) }
            )
        }
    }

    @Published var historyTimeoutSeconds: Int {
        didSet {
            persistSupportedValue(
                historyTimeoutSeconds,
                supportedValue: Self.supportedInteger(
                    historyTimeoutSeconds,
                    for: Setting.historyTimeoutSeconds,
                    supportedValues: Self.supportedHistoryTimeoutsSeconds
                ),
                assign: { historyTimeoutSeconds = $0 },
                persist: { persist($0, for: Setting.historyTimeoutSeconds) }
            )
        }
    }

    @Published var pasteCloseBehavior: String {
        didSet {
            persistSupportedValue(
                pasteCloseBehavior,
                supportedValue: Self.supportedRawValue(
                    pasteCloseBehavior,
                    for: Setting.pasteCloseBehavior,
                    as: PasteCloseBehavior.self
                ),
                assign: { pasteCloseBehavior = $0 },
                persist: { persist($0, for: Setting.pasteCloseBehavior) }
            )
        }
    }

    @Published var previewAnimationEnabled: Bool {
        didSet { persist(previewAnimationEnabled, for: Setting.previewAnimationEnabled) }
    }

    @Published var appearanceMode: String {
        didSet {
            persistSupportedValue(
                appearanceMode,
                supportedValue: Self.supportedRawValue(
                    appearanceMode,
                    for: Setting.appearanceMode,
                    as: AppAppearanceMode.self
                ),
                assign: { appearanceMode = $0 },
                persist: { persist($0, for: Setting.appearanceMode) }
            )
        }
    }

    @Published var ocrRecognitionMode: String {
        didSet {
            persistSupportedValue(
                ocrRecognitionMode,
                supportedValue: Self.supportedRawValue(
                    ocrRecognitionMode,
                    for: Setting.ocrRecognitionMode,
                    as: OCRRecognitionMode.self
                ),
                assign: { ocrRecognitionMode = $0 },
                persist: { persist($0, for: Setting.ocrRecognitionMode) }
            )
        }
    }

    @Published var ocrLanguageMode: String {
        didSet {
            persistSupportedValue(
                ocrLanguageMode,
                supportedValue: Self.supportedRawValue(
                    ocrLanguageMode,
                    for: Setting.ocrLanguageMode,
                    as: OCRLanguageMode.self
                ),
                assign: { ocrLanguageMode = $0 },
                persist: { persist($0, for: Setting.ocrLanguageMode) }
            )
        }
    }

    @Published var sensitiveContentStoragePolicy: String {
        didSet {
            persistSupportedValue(
                sensitiveContentStoragePolicy,
                supportedValue: Self.supportedRawValue(
                    sensitiveContentStoragePolicy,
                    for: Setting.sensitiveContentStoragePolicy,
                    as: SensitiveContentStoragePolicy.self
                ),
                assign: { sensitiveContentStoragePolicy = $0 },
                persist: { persist($0, for: Setting.sensitiveContentStoragePolicy) }
            )
        }
    }

    @Published var hotKeyRegistrationWarning: String?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        defaults.register(defaults: Setting.registeredDefaults)
        monitoringEnabled = Self.bool(for: Setting.monitoringEnabled, in: defaults)
        hoverPreviewEnabled = Self.bool(for: Setting.hoverPreviewEnabled, in: defaults)
        historyLimit = Self.supportedInteger(
            for: Setting.historyLimit,
            in: defaults,
            supportedValues: Self.supportedHistoryLimits
        )
        launchAtLogin = Self.bool(for: Setting.launchAtLogin, in: defaults)
        imageSizeLimitMB = Self.supportedInteger(
            for: Setting.imageSizeLimitMB,
            in: defaults,
            supportedValues: Self.supportedImageSizeLimitsMB
        )
        storageLimitMB = Self.supportedInteger(
            for: Setting.storageLimitMB,
            in: defaults,
            supportedValues: Self.supportedStorageLimitsMB
        )
        ignoredBundleIdentifiers = Self.string(
            for: Setting.ignoredBundleIdentifiers,
            in: defaults
        )
        let openHotKey = Self.validatedHotKey(
            keyCode: Self.integer(for: Setting.hotKeyCode, in: defaults),
            modifiers: Self.uint32(for: Setting.hotKeyModifiers, in: defaults),
            defaultKeyCode: Setting.hotKeyCode.defaultValue,
            defaultModifiers: Setting.hotKeyModifiers.defaultValue
        )
        hotKeyCode = openHotKey.keyCode
        hotKeyModifiers = openHotKey.modifiers
        let plainTextHotKey = Self.validatedHotKey(
            keyCode: Self.integer(for: Setting.plainTextHotKeyCode, in: defaults),
            modifiers: Self.uint32(
                for: Setting.plainTextHotKeyModifiers,
                in: defaults
            ),
            defaultKeyCode: Setting.plainTextHotKeyCode.defaultValue,
            defaultModifiers: Setting.plainTextHotKeyModifiers.defaultValue
        )
        plainTextHotKeyCode = plainTextHotKey.keyCode
        plainTextHotKeyModifiers = plainTextHotKey.modifiers
        menuBarIconStyle = Self.supportedRawValue(
            for: Setting.menuBarIconStyle,
            in: defaults,
            as: MenuBarIconStyle.self
        )
        historyTimeoutSeconds = Self.supportedInteger(
            for: Setting.historyTimeoutSeconds,
            in: defaults,
            supportedValues: Self.supportedHistoryTimeoutsSeconds
        )
        pasteCloseBehavior = Self.supportedRawValue(
            for: Setting.pasteCloseBehavior,
            in: defaults,
            as: PasteCloseBehavior.self
        )
        previewAnimationEnabled = Self.bool(
            for: Setting.previewAnimationEnabled,
            in: defaults
        )
        appearanceMode = Self.supportedRawValue(
            for: Setting.appearanceMode,
            in: defaults,
            as: AppAppearanceMode.self
        )
        ocrRecognitionMode = Self.supportedRawValue(
            for: Setting.ocrRecognitionMode,
            in: defaults,
            as: OCRRecognitionMode.self
        )
        ocrLanguageMode = Self.supportedRawValue(
            for: Setting.ocrLanguageMode,
            in: defaults,
            as: OCRLanguageMode.self
        )
        sensitiveContentStoragePolicy = Self.supportedRawValue(
            for: Setting.sensitiveContentStoragePolicy,
            in: defaults,
            as: SensitiveContentStoragePolicy.self
        )
        persistCurrentValues()
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
        monitoringEnabled = Setting.monitoringEnabled.defaultValue
        hoverPreviewEnabled = Setting.hoverPreviewEnabled.defaultValue
        historyLimit = Setting.historyLimit.defaultValue
        launchAtLogin = Setting.launchAtLogin.defaultValue
        imageSizeLimitMB = Setting.imageSizeLimitMB.defaultValue
        storageLimitMB = Setting.storageLimitMB.defaultValue
        ignoredBundleIdentifiers = Setting.ignoredBundleIdentifiers.defaultValue
        hotKeyCode = Setting.hotKeyCode.defaultValue
        hotKeyModifiers = Setting.hotKeyModifiers.defaultValue
        plainTextHotKeyCode = Setting.plainTextHotKeyCode.defaultValue
        plainTextHotKeyModifiers = Setting.plainTextHotKeyModifiers.defaultValue
        menuBarIconStyle = Setting.menuBarIconStyle.defaultValue
        historyTimeoutSeconds = Setting.historyTimeoutSeconds.defaultValue
        pasteCloseBehavior = Setting.pasteCloseBehavior.defaultValue
        previewAnimationEnabled = Setting.previewAnimationEnabled.defaultValue
        appearanceMode = Setting.appearanceMode.defaultValue
        ocrRecognitionMode = Setting.ocrRecognitionMode.defaultValue
        ocrLanguageMode = Setting.ocrLanguageMode.defaultValue
        sensitiveContentStoragePolicy =
            Setting.sensitiveContentStoragePolicy.defaultValue
    }

    private static func supportedInteger(
        _ value: Int,
        for setting: AppSetting<Int>,
        supportedValues: [Int]
    ) -> Int {
        supportedValues.contains(value) ? value : setting.defaultValue
    }

    private static func supportedInteger(
        for setting: AppSetting<Int>,
        in defaults: UserDefaults,
        supportedValues: [Int]
    ) -> Int {
        supportedInteger(
            integer(for: setting, in: defaults),
            for: setting,
            supportedValues: supportedValues
        )
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

    private static func supportedHotKeyCode(
        _ keyCode: Int,
        default defaultKeyCode: Int = defaultOpenHotKeyCode
    ) -> Int {
        supportedHotKeyCodes.contains(keyCode) ? keyCode : defaultKeyCode
    }

    private static func supportedHotKeyModifiers(
        _ modifiers: UInt32,
        default defaultModifiers: UInt32 = defaultOpenHotKeyModifiers
    ) -> UInt32 {
        let modifiersAreSupported = modifiers != 0
            && modifiers & ~supportedHotKeyModifierMask == 0
        return modifiersAreSupported ? modifiers : defaultModifiers
    }

    private static func supportedRawValue<Value: RawRepresentable>(
        _ value: String,
        for setting: AppSetting<String>,
        as type: Value.Type
    ) -> String where Value.RawValue == String {
        type.init(rawValue: value)?.rawValue ?? setting.defaultValue
    }

    private static func supportedRawValue<Value: RawRepresentable>(
        for setting: AppSetting<String>,
        in defaults: UserDefaults,
        as type: Value.Type
    ) -> String where Value.RawValue == String {
        supportedRawValue(
            string(for: setting, in: defaults),
            for: setting,
            as: type
        )
    }

    private func persistSupportedValue<Value: Equatable>(
        _ value: Value,
        supportedValue: Value,
        assign: (Value) -> Void,
        persist: (Value) -> Void
    ) {
        guard value == supportedValue else {
            assign(supportedValue)
            persist(supportedValue)
            return
        }
        persist(value)
    }

    private func persistCurrentValues() {
        persist(monitoringEnabled, for: Setting.monitoringEnabled)
        persist(hoverPreviewEnabled, for: Setting.hoverPreviewEnabled)
        persist(historyLimit, for: Setting.historyLimit)
        persist(launchAtLogin, for: Setting.launchAtLogin)
        persist(imageSizeLimitMB, for: Setting.imageSizeLimitMB)
        persist(storageLimitMB, for: Setting.storageLimitMB)
        persist(ignoredBundleIdentifiers, for: Setting.ignoredBundleIdentifiers)
        persist(hotKeyCode, for: Setting.hotKeyCode)
        persist(hotKeyModifiers, for: Setting.hotKeyModifiers)
        persist(plainTextHotKeyCode, for: Setting.plainTextHotKeyCode)
        persist(plainTextHotKeyModifiers, for: Setting.plainTextHotKeyModifiers)
        persist(menuBarIconStyle, for: Setting.menuBarIconStyle)
        persist(historyTimeoutSeconds, for: Setting.historyTimeoutSeconds)
        persist(pasteCloseBehavior, for: Setting.pasteCloseBehavior)
        persist(previewAnimationEnabled, for: Setting.previewAnimationEnabled)
        persist(appearanceMode, for: Setting.appearanceMode)
        persist(ocrRecognitionMode, for: Setting.ocrRecognitionMode)
        persist(ocrLanguageMode, for: Setting.ocrLanguageMode)
        persist(
            sensitiveContentStoragePolicy,
            for: Setting.sensitiveContentStoragePolicy
        )
    }

    private static func bool(
        for setting: AppSetting<Bool>,
        in defaults: UserDefaults
    ) -> Bool {
        defaults.bool(forKey: setting.key)
    }

    private static func integer(
        for setting: AppSetting<Int>,
        in defaults: UserDefaults
    ) -> Int {
        defaults.integer(forKey: setting.key)
    }

    private static func uint32(
        for setting: AppSetting<UInt32>,
        in defaults: UserDefaults
    ) -> UInt32 {
        UInt32(defaults.integer(forKey: setting.key))
    }

    private static func string(
        for setting: AppSetting<String>,
        in defaults: UserDefaults
    ) -> String {
        defaults.string(forKey: setting.key) ?? setting.defaultValue
    }

    private func persist(_ value: Bool, for setting: AppSetting<Bool>) {
        defaults.set(value, forKey: setting.key)
    }

    private func persist(_ value: Int, for setting: AppSetting<Int>) {
        defaults.set(value, forKey: setting.key)
    }

    private func persist(_ value: UInt32, for setting: AppSetting<UInt32>) {
        defaults.set(Int(value), forKey: setting.key)
    }

    private func persist(_ value: String, for setting: AppSetting<String>) {
        defaults.set(value, forKey: setting.key)
    }
}

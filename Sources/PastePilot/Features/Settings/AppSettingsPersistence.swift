import Foundation

final class AppSettingsPersistence {
    struct Key<Value: Sendable>: Sendable {
        let key: String
        let defaultValue: Value
    
        init(_ key: String, default defaultValue: Value) {
            self.key = key
            self.defaultValue = defaultValue
        }
    }
    
    enum Setting {
        static let monitoringEnabled = Key("monitoringEnabled", default: true)
        static let hoverPreviewEnabled = Key("hoverPreviewEnabled", default: true)
        static let showSourceAppIconInHistory = Key(
            "showSourceAppIconInHistory",
            default: true
        )
        static let historyLimit = Key(
            "historyLimit",
            default: AppSettings.defaultHistoryLimit
        )
        static let launchAtLogin = Key("launchAtLogin", default: false)
        static let imageSizeLimitMB = Key(
            "imageSizeLimitMB",
            default: AppSettings.defaultImageSizeLimitMB
        )
        static let perceptualImageDeduplicationEnabled = Key(
            "perceptualImageDeduplicationEnabled",
            default: AppSettings.defaultPerceptualImageDeduplicationEnabled
        )
        static let linkMetadataFetchingEnabled = Key(
            "linkMetadataFetchingEnabled",
            default: AppSettings.defaultLinkMetadataFetchingEnabled
        )
        static let storageLimitMB = Key(
            "storageLimitMB",
            default: AppSettings.defaultStorageLimitMB
        )
        static let ignoredBundleIdentifiers = Key(
            "ignoredBundleIdentifiers",
            default: ""
        )
        static let hotKeyCode = Key(
            "hotKeyCode",
            default: AppSettings.defaultOpenHotKeyCode
        )
        static let hotKeyModifiers = Key(
            "hotKeyModifiers",
            default: AppSettings.defaultOpenHotKeyModifiers
        )
        static let plainTextHotKeyCode = Key(
            "plainTextHotKeyCode",
            default: AppSettings.defaultPlainTextHotKeyCode
        )
        static let plainTextHotKeyModifiers = Key(
            "plainTextHotKeyModifiers",
            default: AppSettings.defaultPlainTextHotKeyModifiers
        )
        static let menuBarIconStyle = Key(
            "menuBarIconStyle",
            default: MenuBarIconStyle.pastepilot.rawValue
        )
        static let historyTimeoutSeconds = Key(
            "historyTimeoutSeconds",
            default: AppSettings.defaultHistoryTimeoutSeconds
        )
        static let protectedHistoryUnlockTimeoutSeconds = Key(
            "protectedHistoryUnlockTimeoutSeconds",
            default: AppSettings.defaultProtectedHistoryUnlockTimeoutSeconds
        )
        static let pasteCloseBehavior = Key(
            "pasteCloseBehavior",
            default: PasteCloseBehavior.closePreview.rawValue
        )
        static let pasteAfterCopying = Key(
            "pasteAfterCopying",
            default: AppSettings.defaultPasteAfterCopying
        )
        static let pasteStackSeparator = Key(
            "pasteStackSeparator",
            default: AppSettings.defaultPasteStackSeparator
        )
        static let customPasteStackSeparator = Key(
            "customPasteStackSeparator",
            default: AppSettings.defaultCustomPasteStackSeparator
        )
        static let previewAnimationEnabled = Key(
            "previewAnimationEnabled",
            default: true
        )
        static let appearanceMode = Key(
            "appearanceMode",
            default: AppSettings.defaultAppearanceMode
        )
        static let ocrRecognitionMode = Key(
            "ocrRecognitionMode",
            default: AppSettings.defaultOCRRecognitionMode
        )
        static let ocrLanguageMode = Key(
            "ocrLanguageMode",
            default: AppSettings.defaultOCRLanguageMode
        )
        static let sensitiveContentStoragePolicy = Key(
            "sensitiveContentStoragePolicy",
            default: AppSettings.defaultSensitiveContentStoragePolicy
        )
        static let customSensitivePatterns = Key(
            "customSensitivePatterns",
            default: AppSettings.defaultCustomSensitivePatterns
        )
        static let customClipboardActions = Key(
            "customClipboardActions",
            default: AppSettings.defaultCustomClipboardActions
        )
        static let savedSearches = Key(
            "savedSearches",
            default: AppSettings.defaultSavedSearches
        )
        static let disabledLocalActionPluginIdentifiers = Key(
            "disabledLocalActionPluginIdentifiers",
            default: AppSettings.defaultDisabledLocalActionPluginIdentifiers
        )
    
        static var registeredDefaults: [String: Any] {
            [
                monitoringEnabled.key: monitoringEnabled.defaultValue,
                hoverPreviewEnabled.key: hoverPreviewEnabled.defaultValue,
                showSourceAppIconInHistory.key: showSourceAppIconInHistory.defaultValue,
                historyLimit.key: historyLimit.defaultValue,
                launchAtLogin.key: launchAtLogin.defaultValue,
                imageSizeLimitMB.key: imageSizeLimitMB.defaultValue,
                perceptualImageDeduplicationEnabled.key:
                    perceptualImageDeduplicationEnabled.defaultValue,
                linkMetadataFetchingEnabled.key: linkMetadataFetchingEnabled.defaultValue,
                storageLimitMB.key: storageLimitMB.defaultValue,
                ignoredBundleIdentifiers.key: ignoredBundleIdentifiers.defaultValue,
                hotKeyCode.key: hotKeyCode.defaultValue,
                hotKeyModifiers.key: hotKeyModifiers.defaultValue,
                plainTextHotKeyCode.key: plainTextHotKeyCode.defaultValue,
                plainTextHotKeyModifiers.key: plainTextHotKeyModifiers.defaultValue,
                menuBarIconStyle.key: menuBarIconStyle.defaultValue,
                historyTimeoutSeconds.key: historyTimeoutSeconds.defaultValue,
                protectedHistoryUnlockTimeoutSeconds.key:
                    protectedHistoryUnlockTimeoutSeconds.defaultValue,
                pasteCloseBehavior.key: pasteCloseBehavior.defaultValue,
                pasteAfterCopying.key: pasteAfterCopying.defaultValue,
                pasteStackSeparator.key: pasteStackSeparator.defaultValue,
                customPasteStackSeparator.key: customPasteStackSeparator.defaultValue,
                previewAnimationEnabled.key: previewAnimationEnabled.defaultValue,
                appearanceMode.key: appearanceMode.defaultValue,
                ocrRecognitionMode.key: ocrRecognitionMode.defaultValue,
                ocrLanguageMode.key: ocrLanguageMode.defaultValue,
                sensitiveContentStoragePolicy.key:
                    sensitiveContentStoragePolicy.defaultValue,
                customSensitivePatterns.key:
                    customSensitivePatterns.defaultValue,
                customClipboardActions.key:
                    customClipboardActions.defaultValue,
                savedSearches.key:
                    savedSearches.defaultValue,
                disabledLocalActionPluginIdentifiers.key:
                    disabledLocalActionPluginIdentifiers.defaultValue,
            ]
        }
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults) {
        self.defaults = defaults
        defaults.register(defaults: Setting.registeredDefaults)
    }

    func bool(for setting: Key<Bool>) -> Bool {
        defaults.bool(forKey: setting.key)
    }

    func integer(for setting: Key<Int>) -> Int {
        defaults.integer(forKey: setting.key)
    }

    func uint32(for setting: Key<UInt32>) -> UInt32 {
        UInt32(defaults.integer(forKey: setting.key))
    }

    func string(for setting: Key<String>) -> String {
        defaults.string(forKey: setting.key) ?? setting.defaultValue
    }

    func set(_ value: Bool, for setting: Key<Bool>) {
        defaults.set(value, forKey: setting.key)
    }

    func set(_ value: Int, for setting: Key<Int>) {
        defaults.set(value, forKey: setting.key)
    }

    func set(_ value: UInt32, for setting: Key<UInt32>) {
        defaults.set(Int(value), forKey: setting.key)
    }

    func set(_ value: String, for setting: Key<String>) {
        defaults.set(value, forKey: setting.key)
    }
}

import Carbon
import Foundation

enum PasteCloseBehavior: String, CaseIterable {
    case keepOpen
    case closePreview
    case closePanel
}

enum PasteStackSeparator: String, CaseIterable {
    case newline
    case space
    case tab
    case commaSpace
    case none
    case custom

    var title: String {
        switch self {
        case .newline:
            "New Line".localized
        case .space:
            "Space".localized
        case .tab:
            "Tab".localized
        case .commaSpace:
            "Comma and Space".localized
        case .none:
            "None".localized
        case .custom:
            "Custom".localized
        }
    }

    func value(customValue: String) -> String {
        switch self {
        case .newline:
            "\n"
        case .space:
            " "
        case .tab:
            "\t"
        case .commaSpace:
            ", "
        case .none:
            ""
        case .custom:
            customValue
        }
    }
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
    static let defaultProtectedHistoryUnlockTimeoutSeconds = 300
    static let supportedProtectedHistoryUnlockTimeoutsSeconds = [60, 300, 900, 3_600]
    static let defaultOCRRecognitionMode = OCRRecognitionMode.accurate.rawValue
    static let defaultOCRLanguageMode = OCRLanguageMode.multilingual.rawValue
    static let defaultAppearanceMode = AppAppearanceMode.system.rawValue
    static let defaultSensitiveContentStoragePolicy =
        SensitiveContentStoragePolicy.storeOriginal.rawValue
    static let defaultCustomSensitivePatterns = ""
    static let defaultPasteAfterCopying = false
    static let defaultPasteStackSeparator = PasteStackSeparator.newline.rawValue
    static let defaultCustomPasteStackSeparator = ""
    static let defaultPerceptualImageDeduplicationEnabled = false
    static let defaultLinkMetadataFetchingEnabled = false
    static let defaultCustomClipboardActions = "[]"
    static let defaultSavedSearches = "[]"
    static let defaultDisabledLocalActionPluginIdentifiers = "[]"
    static var defaultPluginsDirectoryURL: URL {
        FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        )[0]
        .appendingPathComponent("PastePilot", isDirectory: true)
        .appendingPathComponent("Plugins", isDirectory: true)
    }

    private typealias Setting = AppSettingsPersistence.Setting

    private let persistence: AppSettingsPersistence
    @Published private var localActionPluginCatalog: LocalActionPluginCatalogState

    var pluginsDirectoryURL: URL {
        localActionPluginCatalog.directoryURL
    }

    var localActionPlugins: [LocalActionPlugin] {
        localActionPluginCatalog.plugins
    }

    var localActionPluginErrors: [String] {
        localActionPluginCatalog.errors
    }

    var disabledLocalActionPluginIdentifiers: Set<String> {
        localActionPluginCatalog.disabledIdentifiers
    }

    @Published var monitoringEnabled: Bool {
        didSet { persist(monitoringEnabled, for: Setting.monitoringEnabled) }
    }

    @Published var hoverPreviewEnabled: Bool {
        didSet { persist(hoverPreviewEnabled, for: Setting.hoverPreviewEnabled) }
    }

    @Published var showSourceAppIconInHistory: Bool {
        didSet {
            persist(
                showSourceAppIconInHistory,
                for: Setting.showSourceAppIconInHistory
            )
        }
    }

    @Published var historyLimit: Int {
        didSet {
            persistSupportedInteger(
                historyLimit,
                for: Setting.historyLimit,
                supportedValues: Self.supportedHistoryLimits
            ) { historyLimit = $0 }
        }
    }

    @Published var launchAtLogin: Bool {
        didSet { persist(launchAtLogin, for: Setting.launchAtLogin) }
    }

    @Published var imageSizeLimitMB: Int {
        didSet {
            persistSupportedInteger(
                imageSizeLimitMB,
                for: Setting.imageSizeLimitMB,
                supportedValues: Self.supportedImageSizeLimitsMB
            ) { imageSizeLimitMB = $0 }
        }
    }

    @Published var perceptualImageDeduplicationEnabled: Bool {
        didSet {
            persist(
                perceptualImageDeduplicationEnabled,
                for: Setting.perceptualImageDeduplicationEnabled
            )
        }
    }

    @Published var linkMetadataFetchingEnabled: Bool {
        didSet { persist(linkMetadataFetchingEnabled, for: Setting.linkMetadataFetchingEnabled) }
    }

    @Published var storageLimitMB: Int {
        didSet {
            persistSupportedInteger(
                storageLimitMB,
                for: Setting.storageLimitMB,
                supportedValues: Self.supportedStorageLimitsMB
            ) { storageLimitMB = $0 }
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
            persistSupportedHotKeyCode(
                hotKeyCode,
                for: Setting.hotKeyCode
            ) { hotKeyCode = $0 }
        }
    }

    @Published var hotKeyModifiers: UInt32 {
        didSet {
            persistSupportedHotKeyModifiers(
                hotKeyModifiers,
                for: Setting.hotKeyModifiers
            ) { hotKeyModifiers = $0 }
        }
    }

    @Published var plainTextHotKeyCode: Int {
        didSet {
            persistSupportedHotKeyCode(
                plainTextHotKeyCode,
                for: Setting.plainTextHotKeyCode,
                default: Self.defaultPlainTextHotKeyCode
            ) { plainTextHotKeyCode = $0 }
        }
    }

    @Published var plainTextHotKeyModifiers: UInt32 {
        didSet {
            persistSupportedHotKeyModifiers(
                plainTextHotKeyModifiers,
                for: Setting.plainTextHotKeyModifiers,
                default: Self.defaultPlainTextHotKeyModifiers
            ) { plainTextHotKeyModifiers = $0 }
        }
    }

    @Published var menuBarIconStyle: String {
        didSet {
            persistSupportedRawValue(
                menuBarIconStyle,
                for: Setting.menuBarIconStyle,
                as: MenuBarIconStyle.self
            ) { menuBarIconStyle = $0 }
        }
    }

    @Published var historyTimeoutSeconds: Int {
        didSet {
            persistSupportedInteger(
                historyTimeoutSeconds,
                for: Setting.historyTimeoutSeconds,
                supportedValues: Self.supportedHistoryTimeoutsSeconds
            ) { historyTimeoutSeconds = $0 }
        }
    }

    @Published var protectedHistoryUnlockTimeoutSeconds: Int {
        didSet {
            persistSupportedInteger(
                protectedHistoryUnlockTimeoutSeconds,
                for: Setting.protectedHistoryUnlockTimeoutSeconds,
                supportedValues: Self.supportedProtectedHistoryUnlockTimeoutsSeconds
            ) { protectedHistoryUnlockTimeoutSeconds = $0 }
        }
    }

    @Published var pasteCloseBehavior: String {
        didSet {
            persistSupportedRawValue(
                pasteCloseBehavior,
                for: Setting.pasteCloseBehavior,
                as: PasteCloseBehavior.self
            ) { pasteCloseBehavior = $0 }
        }
    }

    @Published var pasteAfterCopying: Bool {
        didSet { persist(pasteAfterCopying, for: Setting.pasteAfterCopying) }
    }

    @Published var pasteStackSeparator: String {
        didSet {
            persistSupportedRawValue(
                pasteStackSeparator,
                for: Setting.pasteStackSeparator,
                as: PasteStackSeparator.self
            ) { pasteStackSeparator = $0 }
        }
    }

    @Published var customPasteStackSeparator: String {
        didSet {
            if customPasteStackSeparator.count > 256 {
                customPasteStackSeparator = String(
                    customPasteStackSeparator.prefix(256)
                )
                return
            }
            persist(
                customPasteStackSeparator,
                for: Setting.customPasteStackSeparator
            )
        }
    }

    @Published var previewAnimationEnabled: Bool {
        didSet { persist(previewAnimationEnabled, for: Setting.previewAnimationEnabled) }
    }

    @Published var appearanceMode: String {
        didSet {
            persistSupportedRawValue(
                appearanceMode,
                for: Setting.appearanceMode,
                as: AppAppearanceMode.self
            ) { appearanceMode = $0 }
        }
    }

    @Published var ocrRecognitionMode: String {
        didSet {
            persistSupportedRawValue(
                ocrRecognitionMode,
                for: Setting.ocrRecognitionMode,
                as: OCRRecognitionMode.self
            ) { ocrRecognitionMode = $0 }
        }
    }

    @Published var ocrLanguageMode: String {
        didSet {
            persistSupportedRawValue(
                ocrLanguageMode,
                for: Setting.ocrLanguageMode,
                as: OCRLanguageMode.self
            ) { ocrLanguageMode = $0 }
        }
    }

    @Published var sensitiveContentStoragePolicy: String {
        didSet {
            persistSupportedRawValue(
                sensitiveContentStoragePolicy,
                for: Setting.sensitiveContentStoragePolicy,
                as: SensitiveContentStoragePolicy.self
            ) { sensitiveContentStoragePolicy = $0 }
        }
    }

    @Published var customSensitivePatterns: String {
        didSet {
            persist(
                customSensitivePatterns,
                for: Setting.customSensitivePatterns
            )
        }
    }

    @Published var customClipboardActions: [CustomClipboardAction] {
        didSet {
            guard customClipboardActions.count <= CustomClipboardAction.maximumCount else {
                customClipboardActions = Array(
                    customClipboardActions.prefix(CustomClipboardAction.maximumCount)
                )
                return
            }
            persistCustomClipboardActions()
        }
    }

    @Published var savedSearches: [SavedClipboardSearch] {
        didSet {
            let normalizedSearches = SavedClipboardSearch.normalized(savedSearches)
            guard savedSearches == normalizedSearches else {
                savedSearches = normalizedSearches
                return
            }
            persistSavedSearches()
        }
    }

    @Published var hotKeyRegistrationWarning: String?

    init(
        defaults: UserDefaults = .standard,
        pluginsDirectoryURL: URL? = nil
    ) {
        let persistence = AppSettingsPersistence(defaults: defaults)
        self.persistence = persistence
        let pluginsDirectoryURL = pluginsDirectoryURL
            ?? Self.defaultPluginsDirectoryURL
        monitoringEnabled = persistence.bool(for: Setting.monitoringEnabled)
        hoverPreviewEnabled = persistence.bool(for: Setting.hoverPreviewEnabled)
        showSourceAppIconInHistory = persistence.bool(
            for: Setting.showSourceAppIconInHistory
        )
        historyLimit = AppSettingsValidation.supportedInteger(
            for: Setting.historyLimit,
            in: persistence,
            supportedValues: Self.supportedHistoryLimits
        )
        launchAtLogin = persistence.bool(for: Setting.launchAtLogin)
        imageSizeLimitMB = AppSettingsValidation.supportedInteger(
            for: Setting.imageSizeLimitMB,
            in: persistence,
            supportedValues: Self.supportedImageSizeLimitsMB
        )
        perceptualImageDeduplicationEnabled = persistence.bool(
            for: Setting.perceptualImageDeduplicationEnabled
        )
        linkMetadataFetchingEnabled = persistence.bool(
            for: Setting.linkMetadataFetchingEnabled
        )
        storageLimitMB = AppSettingsValidation.supportedInteger(
            for: Setting.storageLimitMB,
            in: persistence,
            supportedValues: Self.supportedStorageLimitsMB
        )
        ignoredBundleIdentifiers = persistence.string(
            for: Setting.ignoredBundleIdentifiers
        )
        let openHotKey = AppSettingsValidation.validatedHotKey(
            keyCode: persistence.integer(for: Setting.hotKeyCode),
            modifiers: persistence.uint32(for: Setting.hotKeyModifiers),
            defaultKeyCode: Setting.hotKeyCode.defaultValue,
            defaultModifiers: Setting.hotKeyModifiers.defaultValue
        )
        hotKeyCode = openHotKey.keyCode
        hotKeyModifiers = openHotKey.modifiers
        let plainTextHotKey = AppSettingsValidation.validatedHotKey(
            keyCode: persistence.integer(for: Setting.plainTextHotKeyCode),
            modifiers: persistence.uint32(
                for: Setting.plainTextHotKeyModifiers
            ),
            defaultKeyCode: Setting.plainTextHotKeyCode.defaultValue,
            defaultModifiers: Setting.plainTextHotKeyModifiers.defaultValue
        )
        plainTextHotKeyCode = plainTextHotKey.keyCode
        plainTextHotKeyModifiers = plainTextHotKey.modifiers
        menuBarIconStyle = AppSettingsValidation.supportedRawValue(
            for: Setting.menuBarIconStyle,
            in: persistence,
            as: MenuBarIconStyle.self
        )
        historyTimeoutSeconds = AppSettingsValidation.supportedInteger(
            for: Setting.historyTimeoutSeconds,
            in: persistence,
            supportedValues: Self.supportedHistoryTimeoutsSeconds
        )
        protectedHistoryUnlockTimeoutSeconds = AppSettingsValidation.supportedInteger(
            for: Setting.protectedHistoryUnlockTimeoutSeconds,
            in: persistence,
            supportedValues: Self.supportedProtectedHistoryUnlockTimeoutsSeconds
        )
        pasteCloseBehavior = AppSettingsValidation.supportedRawValue(
            for: Setting.pasteCloseBehavior,
            in: persistence,
            as: PasteCloseBehavior.self
        )
        pasteAfterCopying = persistence.bool(
            for: Setting.pasteAfterCopying
        )
        pasteStackSeparator = AppSettingsValidation.supportedRawValue(
            for: Setting.pasteStackSeparator,
            in: persistence,
            as: PasteStackSeparator.self
        )
        customPasteStackSeparator = String(
            persistence.string(for: Setting.customPasteStackSeparator)
                .prefix(256)
        )
        previewAnimationEnabled = persistence.bool(
            for: Setting.previewAnimationEnabled
        )
        appearanceMode = AppSettingsValidation.supportedRawValue(
            for: Setting.appearanceMode,
            in: persistence,
            as: AppAppearanceMode.self
        )
        ocrRecognitionMode = AppSettingsValidation.supportedRawValue(
            for: Setting.ocrRecognitionMode,
            in: persistence,
            as: OCRRecognitionMode.self
        )
        ocrLanguageMode = AppSettingsValidation.supportedRawValue(
            for: Setting.ocrLanguageMode,
            in: persistence,
            as: OCRLanguageMode.self
        )
        sensitiveContentStoragePolicy = AppSettingsValidation.supportedRawValue(
            for: Setting.sensitiveContentStoragePolicy,
            in: persistence,
            as: SensitiveContentStoragePolicy.self
        )
        customSensitivePatterns = persistence.string(
            for: Setting.customSensitivePatterns
        )
        customClipboardActions = Self.decodeCustomClipboardActions(
            persistence.string(for: Setting.customClipboardActions)
        )
        savedSearches = Self.decodeSavedSearches(
            persistence.string(for: Setting.savedSearches)
        )
        localActionPluginCatalog = LocalActionPluginCatalogState(
            directoryURL: pluginsDirectoryURL,
            disabledIdentifiers: Self.decodeDisabledLocalActionPluginIdentifiers(
                persistence.string(for: Setting.disabledLocalActionPluginIdentifiers)
            )
        )
        reloadLocalActionPlugins()
        persistCurrentValues()
    }

    var availableCustomClipboardActions: [CustomClipboardAction] {
        CustomClipboardAction.normalized(
            customClipboardActions + localActionPlugins
                .filter { isLocalActionPluginEnabled($0.id) }
                .flatMap(\.actions),
            limit: CustomClipboardAction.maximumRuntimeCount
        )
    }

    func isLocalActionPluginEnabled(_ identifier: String) -> Bool {
        !disabledLocalActionPluginIdentifiers.contains(identifier)
    }

    func setLocalActionPlugin(_ identifier: String, isEnabled: Bool) {
        localActionPluginCatalog.setPlugin(identifier, isEnabled: isEnabled)
        persistDisabledLocalActionPluginIdentifiers()
    }

    func reloadLocalActionPlugins() {
        localActionPluginCatalog.reload()
    }

    func createPluginsDirectory() throws {
        try localActionPluginCatalog.createDirectory()
    }

    func importLocalActionPlugins(from sourceURLs: [URL]) throws {
        try localActionPluginCatalog.importPlugins(from: sourceURLs)
    }

    func exportLocalActionPlugin(
        _ plugin: LocalActionPlugin,
        to destinationURL: URL
    ) throws {
        try localActionPluginCatalog.exportPlugin(plugin, to: destinationURL)
    }

    @discardableResult
    func upsertSavedSearch(name: String, query: String) -> Bool {
        guard let savedSearch = SavedClipboardSearch(name: name, query: query) else {
            return false
        }

        if let index = savedSearches.firstIndex(where: {
            $0.name.localizedCaseInsensitiveCompare(savedSearch.name) == .orderedSame
        }) {
            savedSearches[index] = SavedClipboardSearch(
                id: savedSearches[index].id,
                name: savedSearch.name,
                query: savedSearch.query
            ) ?? savedSearch
            return true
        }

        guard savedSearches.count < SavedClipboardSearch.maximumCount else {
            return false
        }
        savedSearches.append(savedSearch)
        return true
    }

    func deleteSavedSearch(id: UUID) {
        savedSearches.removeAll { $0.id == id }
    }

    var userSensitivePatterns: [UserSensitivePattern] {
        UserSensitivePattern.patterns(from: customSensitivePatterns)
    }

    var resolvedPasteStackSeparator: String {
        (PasteStackSeparator(rawValue: pasteStackSeparator) ?? .newline)
            .value(customValue: customPasteStackSeparator)
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
        showSourceAppIconInHistory = Setting.showSourceAppIconInHistory.defaultValue
        historyLimit = Setting.historyLimit.defaultValue
        launchAtLogin = Setting.launchAtLogin.defaultValue
        imageSizeLimitMB = Setting.imageSizeLimitMB.defaultValue
        perceptualImageDeduplicationEnabled =
            Setting.perceptualImageDeduplicationEnabled.defaultValue
        linkMetadataFetchingEnabled = Setting.linkMetadataFetchingEnabled.defaultValue
        storageLimitMB = Setting.storageLimitMB.defaultValue
        ignoredBundleIdentifiers = Setting.ignoredBundleIdentifiers.defaultValue
        hotKeyCode = Setting.hotKeyCode.defaultValue
        hotKeyModifiers = Setting.hotKeyModifiers.defaultValue
        plainTextHotKeyCode = Setting.plainTextHotKeyCode.defaultValue
        plainTextHotKeyModifiers = Setting.plainTextHotKeyModifiers.defaultValue
        menuBarIconStyle = Setting.menuBarIconStyle.defaultValue
        historyTimeoutSeconds = Setting.historyTimeoutSeconds.defaultValue
        protectedHistoryUnlockTimeoutSeconds =
            Setting.protectedHistoryUnlockTimeoutSeconds.defaultValue
        pasteCloseBehavior = Setting.pasteCloseBehavior.defaultValue
        pasteAfterCopying = Setting.pasteAfterCopying.defaultValue
        pasteStackSeparator = Setting.pasteStackSeparator.defaultValue
        customPasteStackSeparator = Setting.customPasteStackSeparator.defaultValue
        previewAnimationEnabled = Setting.previewAnimationEnabled.defaultValue
        appearanceMode = Setting.appearanceMode.defaultValue
        ocrRecognitionMode = Setting.ocrRecognitionMode.defaultValue
        ocrLanguageMode = Setting.ocrLanguageMode.defaultValue
        sensitiveContentStoragePolicy =
            Setting.sensitiveContentStoragePolicy.defaultValue
        customSensitivePatterns = Setting.customSensitivePatterns.defaultValue
        customClipboardActions = []
        savedSearches = []
        localActionPluginCatalog.removeAllDisabledIdentifiers()
        persistDisabledLocalActionPluginIdentifiers()
    }

    private func persistSupportedInteger(
        _ value: Int,
        for setting: AppSettingsPersistence.Key<Int>,
        supportedValues: [Int],
        assign: (Int) -> Void
    ) {
        persistSupportedValue(
            value,
            supportedValue: AppSettingsValidation.supportedInteger(
                value,
                for: setting,
                supportedValues: supportedValues
            ),
            assign: assign,
            persist: { persist($0, for: setting) }
        )
    }

    private func persistSupportedHotKeyCode(
        _ value: Int,
        for setting: AppSettingsPersistence.Key<Int>,
        default defaultValue: Int = defaultOpenHotKeyCode,
        assign: (Int) -> Void
    ) {
        persistSupportedValue(
            value,
            supportedValue: AppSettingsValidation.supportedHotKeyCode(value, default: defaultValue),
            assign: assign,
            persist: { persist($0, for: setting) }
        )
    }

    private func persistSupportedHotKeyModifiers(
        _ value: UInt32,
        for setting: AppSettingsPersistence.Key<UInt32>,
        default defaultValue: UInt32 = defaultOpenHotKeyModifiers,
        assign: (UInt32) -> Void
    ) {
        persistSupportedValue(
            value,
            supportedValue: AppSettingsValidation.supportedHotKeyModifiers(
                value,
                default: defaultValue
            ),
            assign: assign,
            persist: { persist($0, for: setting) }
        )
    }

    private func persistSupportedRawValue<Value: RawRepresentable>(
        _ value: String,
        for setting: AppSettingsPersistence.Key<String>,
        as type: Value.Type,
        assign: (String) -> Void
    ) where Value.RawValue == String {
        persistSupportedValue(
            value,
            supportedValue: AppSettingsValidation.supportedRawValue(value, for: setting, as: type),
            assign: assign,
            persist: { persist($0, for: setting) }
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
        persist(
            showSourceAppIconInHistory,
            for: Setting.showSourceAppIconInHistory
        )
        persist(historyLimit, for: Setting.historyLimit)
        persist(launchAtLogin, for: Setting.launchAtLogin)
        persist(imageSizeLimitMB, for: Setting.imageSizeLimitMB)
        persist(
            perceptualImageDeduplicationEnabled,
            for: Setting.perceptualImageDeduplicationEnabled
        )
        persist(linkMetadataFetchingEnabled, for: Setting.linkMetadataFetchingEnabled)
        persist(storageLimitMB, for: Setting.storageLimitMB)
        persist(ignoredBundleIdentifiers, for: Setting.ignoredBundleIdentifiers)
        persist(hotKeyCode, for: Setting.hotKeyCode)
        persist(hotKeyModifiers, for: Setting.hotKeyModifiers)
        persist(plainTextHotKeyCode, for: Setting.plainTextHotKeyCode)
        persist(plainTextHotKeyModifiers, for: Setting.plainTextHotKeyModifiers)
        persist(menuBarIconStyle, for: Setting.menuBarIconStyle)
        persist(historyTimeoutSeconds, for: Setting.historyTimeoutSeconds)
        persist(
            protectedHistoryUnlockTimeoutSeconds,
            for: Setting.protectedHistoryUnlockTimeoutSeconds
        )
        persist(pasteCloseBehavior, for: Setting.pasteCloseBehavior)
        persist(pasteAfterCopying, for: Setting.pasteAfterCopying)
        persist(pasteStackSeparator, for: Setting.pasteStackSeparator)
        persist(customPasteStackSeparator, for: Setting.customPasteStackSeparator)
        persist(previewAnimationEnabled, for: Setting.previewAnimationEnabled)
        persist(appearanceMode, for: Setting.appearanceMode)
        persist(ocrRecognitionMode, for: Setting.ocrRecognitionMode)
        persist(ocrLanguageMode, for: Setting.ocrLanguageMode)
        persist(
            sensitiveContentStoragePolicy,
            for: Setting.sensitiveContentStoragePolicy
        )
        persist(customSensitivePatterns, for: Setting.customSensitivePatterns)
        persistCustomClipboardActions()
        persistSavedSearches()
        persistDisabledLocalActionPluginIdentifiers()
    }

    private static func decodeCustomClipboardActions(
        _ encoded: String
    ) -> [CustomClipboardAction] {
        guard let data = encoded.data(using: .utf8),
              let actions = try? JSONDecoder().decode(
                  [CustomClipboardAction].self,
                  from: data
              ) else {
            return []
        }
        return CustomClipboardAction.normalized(actions)
    }

    private func persistCustomClipboardActions() {
        guard let data = try? JSONEncoder().encode(customClipboardActions),
              let encoded = String(data: data, encoding: .utf8) else {
            return
        }
        persist(encoded, for: Setting.customClipboardActions)
    }

    private static func decodeSavedSearches(
        _ encoded: String
    ) -> [SavedClipboardSearch] {
        guard let data = encoded.data(using: .utf8),
              let searches = try? JSONDecoder().decode(
                  [SavedClipboardSearch].self,
                  from: data
              ) else {
            return []
        }
        return SavedClipboardSearch.normalized(searches)
    }

    private func persistSavedSearches() {
        guard let data = try? JSONEncoder().encode(savedSearches),
              let encoded = String(data: data, encoding: .utf8) else {
            return
        }
        persist(encoded, for: Setting.savedSearches)
    }

    private static func decodeDisabledLocalActionPluginIdentifiers(
        _ encoded: String
    ) -> Set<String> {
        guard let data = encoded.data(using: .utf8),
              let identifiers = try? JSONDecoder().decode([String].self, from: data) else {
            return []
        }
        return Set(
            identifiers
                .filter(LocalActionPluginLoader.isValidIdentifier)
                .prefix(LocalActionPluginLoader.maximumPluginCount * 5)
        )
    }

    private func persistDisabledLocalActionPluginIdentifiers() {
        guard let data = try? JSONEncoder().encode(
            disabledLocalActionPluginIdentifiers.sorted()
        ), let encoded = String(data: data, encoding: .utf8) else {
            return
        }
        persist(encoded, for: Setting.disabledLocalActionPluginIdentifiers)
    }

    private func persist(
        _ value: Bool,
        for setting: AppSettingsPersistence.Key<Bool>
    ) {
        persistence.set(value, for: setting)
    }

    private func persist(
        _ value: Int,
        for setting: AppSettingsPersistence.Key<Int>
    ) {
        persistence.set(value, for: setting)
    }

    private func persist(
        _ value: UInt32,
        for setting: AppSettingsPersistence.Key<UInt32>
    ) {
        persistence.set(value, for: setting)
    }

    private func persist(
        _ value: String,
        for setting: AppSettingsPersistence.Key<String>
    ) {
        persistence.set(value, for: setting)
    }
}

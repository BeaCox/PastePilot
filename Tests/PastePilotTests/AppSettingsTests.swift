import Foundation
import Testing
@testable import PastePilot

@Suite
struct AppSettingsTests {
    @Test
    func defaultsPersistenceAndReset() throws {
        let suiteName = "PastePilotTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let settings = AppSettings(defaults: defaults)
        #expect(settings.monitoringEnabled)
        #expect(settings.historyLimit == 100)
        #expect(settings.imageSizeLimitMB == 25)
        #expect(!settings.perceptualImageDeduplicationEnabled)
        #expect(!settings.linkMetadataFetchingEnabled)
        #expect(settings.storageLimitMB == AppSettings.defaultStorageLimitMB)
        #expect(settings.hotKeyCode == AppSettings.defaultOpenHotKeyCode)
        #expect(settings.hotKeyModifiers == AppSettings.defaultOpenHotKeyModifiers)
        #expect(settings.plainTextHotKeyCode == AppSettings.defaultPlainTextHotKeyCode)
        #expect(
            settings.plainTextHotKeyModifiers
                == AppSettings.defaultPlainTextHotKeyModifiers
        )
        #expect(settings.ocrRecognitionMode == AppSettings.defaultOCRRecognitionMode)
        #expect(settings.ocrLanguageMode == AppSettings.defaultOCRLanguageMode)
        #expect(settings.appearanceMode == AppSettings.defaultAppearanceMode)
        #expect(settings.pasteAfterCopying == AppSettings.defaultPasteAfterCopying)
        #expect(
            settings.sensitiveContentStoragePolicy
                == AppSettings.defaultSensitiveContentStoragePolicy
        )
        #expect(settings.customSensitivePatterns.isEmpty)

        settings.historyLimit = 200
        settings.imageSizeLimitMB = 50
        settings.perceptualImageDeduplicationEnabled = true
        settings.linkMetadataFetchingEnabled = true
        settings.storageLimitMB = 250
        settings.hotKeyCode = 8
        settings.hotKeyModifiers = 256
        settings.plainTextHotKeyCode = 9
        settings.plainTextHotKeyModifiers = 4_096
        settings.ocrRecognitionMode = OCRRecognitionMode.fast.rawValue
        settings.ocrLanguageMode = OCRLanguageMode.english.rawValue
        settings.appearanceMode = AppAppearanceMode.dark.rawValue
        settings.pasteAfterCopying = true
        settings.sensitiveContentStoragePolicy =
            SensitiveContentStoragePolicy.storeRedacted.rawValue
        settings.customSensitivePatterns = """
        project raven
        regex:customer-[0-9]+
        """
        settings.ignoredBundleIdentifiers = """
        com.apple.keychainaccess

         com.example.private
        """

        let restored = AppSettings(defaults: defaults)
        #expect(restored.historyLimit == 200)
        #expect(restored.imageSizeLimitMB == 50)
        #expect(restored.perceptualImageDeduplicationEnabled)
        #expect(restored.linkMetadataFetchingEnabled)
        #expect(restored.storageLimitMB == 250)
        #expect(restored.hotKeyCode == 8)
        #expect(restored.hotKeyModifiers == 256)
        #expect(restored.plainTextHotKeyCode == 9)
        #expect(restored.plainTextHotKeyModifiers == 4_096)
        #expect(restored.ocrRecognitionMode == OCRRecognitionMode.fast.rawValue)
        #expect(restored.ocrLanguageMode == OCRLanguageMode.english.rawValue)
        #expect(restored.appearanceMode == AppAppearanceMode.dark.rawValue)
        #expect(restored.pasteAfterCopying)
        #expect(
            restored.sensitiveContentStoragePolicy
                == SensitiveContentStoragePolicy.storeRedacted.rawValue
        )
        #expect(
            restored.userSensitivePatterns == [
                UserSensitivePattern(kind: .literal, value: "project raven"),
                UserSensitivePattern(
                    kind: .regularExpression,
                    value: "customer-[0-9]+"
                )
            ]
        )
        #expect(
            restored.ignoredBundleIdentifierSet
                == ["com.apple.keychainaccess", "com.example.private"]
        )

        restored.reset()
        #expect(restored.historyLimit == 100)
        #expect(!restored.perceptualImageDeduplicationEnabled)
        #expect(!restored.linkMetadataFetchingEnabled)
        #expect(restored.storageLimitMB == AppSettings.defaultStorageLimitMB)
        #expect(restored.ignoredBundleIdentifiers.isEmpty)
        #expect(restored.hotKeyCode == AppSettings.defaultOpenHotKeyCode)
        #expect(restored.hotKeyModifiers == AppSettings.defaultOpenHotKeyModifiers)
        #expect(
            restored.plainTextHotKeyCode
                == AppSettings.defaultPlainTextHotKeyCode
        )
        #expect(
            restored.plainTextHotKeyModifiers
                == AppSettings.defaultPlainTextHotKeyModifiers
        )
        #expect(restored.ocrRecognitionMode == AppSettings.defaultOCRRecognitionMode)
        #expect(restored.ocrLanguageMode == AppSettings.defaultOCRLanguageMode)
        #expect(restored.appearanceMode == AppSettings.defaultAppearanceMode)
        #expect(restored.pasteAfterCopying == AppSettings.defaultPasteAfterCopying)
        #expect(
            restored.sensitiveContentStoragePolicy
                == AppSettings.defaultSensitiveContentStoragePolicy
        )
        #expect(restored.customSensitivePatterns.isEmpty)
    }

    @Test
    func invalidPersistedValuesFallBackToSupportedDefaults() throws {
        let suiteName = "PastePilotTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        defaults.set(999, forKey: "historyLimit")
        defaults.set(1_024, forKey: "imageSizeLimitMB")
        defaults.set(42, forKey: "storageLimitMB")
        defaults.set(42, forKey: "historyTimeoutSeconds")
        defaults.set("missing-icon", forKey: "menuBarIconStyle")
        defaults.set("close-everything", forKey: "pasteCloseBehavior")
        defaults.set(999, forKey: "hotKeyCode")
        defaults.set(0, forKey: "hotKeyModifiers")
        defaults.set(-1, forKey: "plainTextHotKeyCode")
        defaults.set(Int(UInt32.max), forKey: "plainTextHotKeyModifiers")
        defaults.set("slow", forKey: "ocrRecognitionMode")
        defaults.set("everywhere", forKey: "ocrLanguageMode")
        defaults.set("neon", forKey: "appearanceMode")
        defaults.set("encrypt", forKey: "sensitiveContentStoragePolicy")

        let settings = AppSettings(defaults: defaults)

        #expect(settings.historyLimit == AppSettings.defaultHistoryLimit)
        #expect(settings.imageSizeLimitMB == AppSettings.defaultImageSizeLimitMB)
        #expect(settings.storageLimitMB == AppSettings.defaultStorageLimitMB)
        #expect(
            settings.historyTimeoutSeconds
                == AppSettings.defaultHistoryTimeoutSeconds
        )
        #expect(settings.menuBarIconStyle == MenuBarIconStyle.pastepilot.rawValue)
        #expect(settings.pasteCloseBehavior == PasteCloseBehavior.closePreview.rawValue)
        #expect(settings.hotKeyCode == AppSettings.defaultOpenHotKeyCode)
        #expect(settings.hotKeyModifiers == AppSettings.defaultOpenHotKeyModifiers)
        #expect(
            settings.plainTextHotKeyCode
                == AppSettings.defaultPlainTextHotKeyCode
        )
        #expect(
            settings.plainTextHotKeyModifiers
                == AppSettings.defaultPlainTextHotKeyModifiers
        )
        #expect(settings.ocrRecognitionMode == AppSettings.defaultOCRRecognitionMode)
        #expect(settings.ocrLanguageMode == AppSettings.defaultOCRLanguageMode)
        #expect(settings.appearanceMode == AppSettings.defaultAppearanceMode)
        #expect(
            settings.sensitiveContentStoragePolicy
                == AppSettings.defaultSensitiveContentStoragePolicy
        )
        #expect(defaults.integer(forKey: "historyLimit") == AppSettings.defaultHistoryLimit)
        #expect(
            defaults.integer(forKey: "imageSizeLimitMB")
                == AppSettings.defaultImageSizeLimitMB
        )
        #expect(
            defaults.integer(forKey: "storageLimitMB")
                == AppSettings.defaultStorageLimitMB
        )
        #expect(
            defaults.integer(forKey: "historyTimeoutSeconds")
                == AppSettings.defaultHistoryTimeoutSeconds
        )
        #expect(
            defaults.string(forKey: "menuBarIconStyle")
                == MenuBarIconStyle.pastepilot.rawValue
        )
        #expect(
            defaults.string(forKey: "pasteCloseBehavior")
                == PasteCloseBehavior.closePreview.rawValue
        )
        #expect(
            defaults.integer(forKey: "hotKeyCode")
                == AppSettings.defaultOpenHotKeyCode
        )
        #expect(
            UInt32(defaults.integer(forKey: "hotKeyModifiers"))
                == AppSettings.defaultOpenHotKeyModifiers
        )
        #expect(
            defaults.integer(forKey: "plainTextHotKeyCode")
                == AppSettings.defaultPlainTextHotKeyCode
        )
        #expect(
            UInt32(defaults.integer(forKey: "plainTextHotKeyModifiers"))
                == AppSettings.defaultPlainTextHotKeyModifiers
        )
        #expect(
            defaults.string(forKey: "ocrRecognitionMode")
                == AppSettings.defaultOCRRecognitionMode
        )
        #expect(
            defaults.string(forKey: "ocrLanguageMode")
                == AppSettings.defaultOCRLanguageMode
        )
        #expect(
            defaults.string(forKey: "appearanceMode")
                == AppSettings.defaultAppearanceMode
        )
        #expect(
            defaults.string(forKey: "sensitiveContentStoragePolicy")
                == AppSettings.defaultSensitiveContentStoragePolicy
        )
    }

    @Test
    func invalidRuntimeValuesFallBackToSupportedDefaults() throws {
        let suiteName = "PastePilotTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let settings = AppSettings(defaults: defaults)
        settings.historyLimit = 200
        settings.imageSizeLimitMB = 50
        settings.storageLimitMB = 500
        settings.historyTimeoutSeconds = 3_600
        settings.menuBarIconStyle = MenuBarIconStyle.clipboard.rawValue
        settings.pasteCloseBehavior = PasteCloseBehavior.keepOpen.rawValue
        settings.hotKeyCode = 8
        settings.hotKeyModifiers = 256
        settings.plainTextHotKeyCode = 9
        settings.plainTextHotKeyModifiers = 4_096
        settings.ocrRecognitionMode = OCRRecognitionMode.fast.rawValue
        settings.ocrLanguageMode = OCRLanguageMode.english.rawValue
        settings.appearanceMode = AppAppearanceMode.light.rawValue
        settings.sensitiveContentStoragePolicy =
            SensitiveContentStoragePolicy.skip.rawValue

        settings.historyLimit = 999
        settings.imageSizeLimitMB = 1_024
        settings.storageLimitMB = 42
        settings.historyTimeoutSeconds = 42
        settings.menuBarIconStyle = "missing-icon"
        settings.pasteCloseBehavior = "close-everything"
        settings.hotKeyCode = 999
        settings.hotKeyModifiers = 0
        settings.plainTextHotKeyCode = -1
        settings.plainTextHotKeyModifiers = UInt32.max
        settings.ocrRecognitionMode = "slow"
        settings.ocrLanguageMode = "everywhere"
        settings.appearanceMode = "neon"
        settings.sensitiveContentStoragePolicy = "encrypt"

        #expect(settings.historyLimit == AppSettings.defaultHistoryLimit)
        #expect(settings.imageSizeLimitMB == AppSettings.defaultImageSizeLimitMB)
        #expect(settings.storageLimitMB == AppSettings.defaultStorageLimitMB)
        #expect(
            settings.historyTimeoutSeconds
                == AppSettings.defaultHistoryTimeoutSeconds
        )
        #expect(settings.menuBarIconStyle == MenuBarIconStyle.pastepilot.rawValue)
        #expect(settings.pasteCloseBehavior == PasteCloseBehavior.closePreview.rawValue)
        #expect(settings.hotKeyCode == AppSettings.defaultOpenHotKeyCode)
        #expect(settings.hotKeyModifiers == AppSettings.defaultOpenHotKeyModifiers)
        #expect(
            settings.plainTextHotKeyCode
                == AppSettings.defaultPlainTextHotKeyCode
        )
        #expect(
            settings.plainTextHotKeyModifiers
                == AppSettings.defaultPlainTextHotKeyModifiers
        )
        #expect(settings.ocrRecognitionMode == AppSettings.defaultOCRRecognitionMode)
        #expect(settings.ocrLanguageMode == AppSettings.defaultOCRLanguageMode)
        #expect(settings.appearanceMode == AppSettings.defaultAppearanceMode)
        #expect(
            settings.sensitiveContentStoragePolicy
                == AppSettings.defaultSensitiveContentStoragePolicy
        )
        #expect(defaults.integer(forKey: "historyLimit") == AppSettings.defaultHistoryLimit)
        #expect(
            defaults.integer(forKey: "imageSizeLimitMB")
                == AppSettings.defaultImageSizeLimitMB
        )
        #expect(
            defaults.integer(forKey: "storageLimitMB")
                == AppSettings.defaultStorageLimitMB
        )
        #expect(
            defaults.integer(forKey: "historyTimeoutSeconds")
                == AppSettings.defaultHistoryTimeoutSeconds
        )
        #expect(
            defaults.string(forKey: "menuBarIconStyle")
                == MenuBarIconStyle.pastepilot.rawValue
        )
        #expect(
            defaults.string(forKey: "pasteCloseBehavior")
                == PasteCloseBehavior.closePreview.rawValue
        )
        #expect(
            defaults.integer(forKey: "hotKeyCode")
                == AppSettings.defaultOpenHotKeyCode
        )
        #expect(
            UInt32(defaults.integer(forKey: "hotKeyModifiers"))
                == AppSettings.defaultOpenHotKeyModifiers
        )
        #expect(
            defaults.integer(forKey: "plainTextHotKeyCode")
                == AppSettings.defaultPlainTextHotKeyCode
        )
        #expect(
            UInt32(defaults.integer(forKey: "plainTextHotKeyModifiers"))
                == AppSettings.defaultPlainTextHotKeyModifiers
        )
        #expect(
            defaults.string(forKey: "ocrRecognitionMode")
                == AppSettings.defaultOCRRecognitionMode
        )
        #expect(
            defaults.string(forKey: "ocrLanguageMode")
                == AppSettings.defaultOCRLanguageMode
        )
        #expect(
            defaults.string(forKey: "appearanceMode")
                == AppSettings.defaultAppearanceMode
        )
        #expect(
            defaults.string(forKey: "sensitiveContentStoragePolicy")
                == AppSettings.defaultSensitiveContentStoragePolicy
        )
        let restored = AppSettings(defaults: defaults)
        #expect(restored.historyLimit == AppSettings.defaultHistoryLimit)
        #expect(restored.imageSizeLimitMB == AppSettings.defaultImageSizeLimitMB)
        #expect(restored.storageLimitMB == AppSettings.defaultStorageLimitMB)
        #expect(
            restored.historyTimeoutSeconds
                == AppSettings.defaultHistoryTimeoutSeconds
        )
        #expect(restored.menuBarIconStyle == MenuBarIconStyle.pastepilot.rawValue)
        #expect(restored.pasteCloseBehavior == PasteCloseBehavior.closePreview.rawValue)
        #expect(restored.hotKeyCode == AppSettings.defaultOpenHotKeyCode)
        #expect(restored.hotKeyModifiers == AppSettings.defaultOpenHotKeyModifiers)
        #expect(
            restored.plainTextHotKeyCode
                == AppSettings.defaultPlainTextHotKeyCode
        )
        #expect(
            restored.plainTextHotKeyModifiers
                == AppSettings.defaultPlainTextHotKeyModifiers
        )
        #expect(restored.ocrRecognitionMode == AppSettings.defaultOCRRecognitionMode)
        #expect(restored.ocrLanguageMode == AppSettings.defaultOCRLanguageMode)
        #expect(restored.appearanceMode == AppSettings.defaultAppearanceMode)
        #expect(
            restored.sensitiveContentStoragePolicy
                == AppSettings.defaultSensitiveContentStoragePolicy
        )
    }
}

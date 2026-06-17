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
        #expect(settings.hotKeyCode == 49)
        #expect(settings.hotKeyModifiers == 2_048)
        #expect(settings.plainTextHotKeyCode == AppSettings.defaultPlainTextHotKeyCode)
        #expect(
            settings.plainTextHotKeyModifiers
                == AppSettings.defaultPlainTextHotKeyModifiers
        )

        settings.historyLimit = 200
        settings.imageSizeLimitMB = 50
        settings.hotKeyCode = 8
        settings.hotKeyModifiers = 256
        settings.plainTextHotKeyCode = 9
        settings.plainTextHotKeyModifiers = 4_096
        settings.ignoredBundleIdentifiers = """
        com.apple.keychainaccess

         com.example.private
        """

        let restored = AppSettings(defaults: defaults)
        #expect(restored.historyLimit == 200)
        #expect(restored.imageSizeLimitMB == 50)
        #expect(restored.hotKeyCode == 8)
        #expect(restored.hotKeyModifiers == 256)
        #expect(restored.plainTextHotKeyCode == 9)
        #expect(restored.plainTextHotKeyModifiers == 4_096)
        #expect(
            restored.ignoredBundleIdentifierSet
                == ["com.apple.keychainaccess", "com.example.private"]
        )

        restored.reset()
        #expect(restored.historyLimit == 100)
        #expect(restored.ignoredBundleIdentifiers.isEmpty)
        #expect(restored.hotKeyCode == 49)
        #expect(restored.hotKeyModifiers == 2_048)
        #expect(
            restored.plainTextHotKeyCode
                == AppSettings.defaultPlainTextHotKeyCode
        )
        #expect(
            restored.plainTextHotKeyModifiers
                == AppSettings.defaultPlainTextHotKeyModifiers
        )
    }

    @Test
    func invalidPersistedValuesFallBackToSupportedDefaults() throws {
        let suiteName = "PastePilotTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        defaults.set(999, forKey: "historyLimit")
        defaults.set(1_024, forKey: "imageSizeLimitMB")
        defaults.set(42, forKey: "historyTimeoutSeconds")
        defaults.set("missing-icon", forKey: "menuBarIconStyle")
        defaults.set("close-everything", forKey: "pasteCloseBehavior")

        let settings = AppSettings(defaults: defaults)

        #expect(settings.historyLimit == AppSettings.defaultHistoryLimit)
        #expect(settings.imageSizeLimitMB == AppSettings.defaultImageSizeLimitMB)
        #expect(
            settings.historyTimeoutSeconds
                == AppSettings.defaultHistoryTimeoutSeconds
        )
        #expect(settings.menuBarIconStyle == MenuBarIconStyle.pastepilot.rawValue)
        #expect(settings.pasteCloseBehavior == PasteCloseBehavior.closePreview.rawValue)
    }
}

enum AppSettingsValidation {
    static func supportedInteger(
        _ value: Int,
        for setting: AppSettingsPersistence.Key<Int>,
        supportedValues: [Int]
    ) -> Int {
        supportedValues.contains(value) ? value : setting.defaultValue
    }
    
    static func supportedInteger(
        for setting: AppSettingsPersistence.Key<Int>,
        in persistence: AppSettingsPersistence,
        supportedValues: [Int]
    ) -> Int {
        supportedInteger(
            persistence.integer(for: setting),
            for: setting,
            supportedValues: supportedValues
        )
    }
    
    static func validatedHotKey(
        keyCode: Int,
        modifiers: UInt32,
        defaultKeyCode: Int,
        defaultModifiers: UInt32
    ) -> (keyCode: Int, modifiers: UInt32) {
        let modifiersAreSupported = modifiers != 0
            && modifiers & ~AppSettings.supportedHotKeyModifierMask == 0
        guard AppSettings.supportedHotKeyCodes.contains(keyCode), modifiersAreSupported else {
            return (defaultKeyCode, defaultModifiers)
        }
        return (keyCode, modifiers)
    }
    
    static func supportedHotKeyCode(
        _ keyCode: Int,
        default defaultKeyCode: Int = AppSettings.defaultOpenHotKeyCode
    ) -> Int {
        AppSettings.supportedHotKeyCodes.contains(keyCode) ? keyCode : defaultKeyCode
    }
    
    static func supportedHotKeyModifiers(
        _ modifiers: UInt32,
        default defaultModifiers: UInt32 = AppSettings.defaultOpenHotKeyModifiers
    ) -> UInt32 {
        let modifiersAreSupported = modifiers != 0
            && modifiers & ~AppSettings.supportedHotKeyModifierMask == 0
        return modifiersAreSupported ? modifiers : defaultModifiers
    }
    
    static func supportedRawValue<Value: RawRepresentable>(
        _ value: String,
        for setting: AppSettingsPersistence.Key<String>,
        as type: Value.Type
    ) -> String where Value.RawValue == String {
        type.init(rawValue: value)?.rawValue ?? setting.defaultValue
    }
    
    static func supportedRawValue<Value: RawRepresentable>(
        for setting: AppSettingsPersistence.Key<String>,
        in persistence: AppSettingsPersistence,
        as type: Value.Type
    ) -> String where Value.RawValue == String {
        supportedRawValue(
            persistence.string(for: setting),
            for: setting,
            as: type
        )
    }
    
}

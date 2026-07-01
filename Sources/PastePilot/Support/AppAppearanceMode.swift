import SwiftUI

enum AppAppearanceMode: String, CaseIterable {
    case system
    case light
    case dark

    var title: String {
        switch self {
        case .system:
            "System".localized
        case .light:
            "Light".localized
        case .dark:
            "Dark".localized
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system:
            nil
        case .light:
            .light
        case .dark:
            .dark
        }
    }
}

private struct PastePilotAppearanceModifier: ViewModifier {
    @ObservedObject var settings: AppSettings

    func body(content: Content) -> some View {
        content.preferredColorScheme(
            (AppAppearanceMode(rawValue: settings.appearanceMode) ?? .system)
                .colorScheme
        )
    }
}

extension View {
    func pastePilotAppearance(_ settings: AppSettings) -> some View {
        modifier(PastePilotAppearanceModifier(settings: settings))
    }
}

import SwiftUI

/// Visual themes for the search panel.
enum AppTheme: String, CaseIterable, Identifiable {
    case system    // current look — follows the macOS system accent, frosted panel
    case midnight  // the README indigo/violet look on a solid dark panel

    var id: String { rawValue }
    var label: String { self == .system ? "System (default)" : "Midnight" }

    private static let indigo = Color(red: 0.42, green: 0.47, blue: 1.0)   // ~#6a78ff
    private static let violet = Color(red: 0.36, green: 0.22, blue: 0.86)  // ~#5b38dc

    /// Accent used for controls (segmented picker, AI button…).
    var accent: Color { self == .system ? .accentColor : Self.indigo }

    /// Gradient fill for the selected result row.
    var selectionGradient: [Color] {
        self == .system
            ? [Color.accentColor.opacity(0.95), Color.accentColor.opacity(0.78)]
            : [Color(red: 0.45, green: 0.50, blue: 1.0), Self.violet]
    }

    var glow: Color { (self == .system ? Color.accentColor : Self.indigo).opacity(0.35) }

    /// Backdrop for the panel: frosted material (system) or a solid dark gradient.
    @ViewBuilder func panelBackground() -> some View {
        switch self {
        case .system:
            VisualEffectView().ignoresSafeArea()
        case .midnight:
            LinearGradient(colors: [Color(red: 0.105, green: 0.12, blue: 0.205),
                                    Color(red: 0.08, green: 0.085, blue: 0.16)],
                           startPoint: .top, endPoint: .bottom).ignoresSafeArea()
        }
    }
}

final class ThemeSettings: ObservableObject {
    @Published var theme: AppTheme { didSet { UserDefaults.standard.set(theme.rawValue, forKey: "theme") } }
    init() {
        theme = AppTheme(rawValue: UserDefaults.standard.string(forKey: "theme") ?? "") ?? .system
    }
}

private struct AppThemeKey: EnvironmentKey { static let defaultValue: AppTheme = .system }
extension EnvironmentValues {
    var appTheme: AppTheme {
        get { self[AppThemeKey.self] }
        set { self[AppThemeKey.self] = newValue }
    }
}

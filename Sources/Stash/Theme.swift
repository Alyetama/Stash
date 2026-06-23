import SwiftUI

/// Visual themes for the search panel.
enum AppTheme: String, CaseIterable, Identifiable {
    case system    // current look — follows the macOS system accent, frosted panel
    case midnight  // the README indigo/violet look on a solid dark panel
    case oneDark   // the Atom One Dark color scheme

    var id: String { rawValue }
    var label: String {
        switch self {
        case .system:   return "System (default)"
        case .midnight: return "Midnight"
        case .oneDark:  return "One Dark"
        }
    }

    private static let indigo = Color(red: 0.42, green: 0.47, blue: 1.0)   // ~#6a78ff
    private static let violet = Color(red: 0.36, green: 0.22, blue: 0.86)  // ~#5b38dc

    // Atom One Dark palette.
    private static let odBlue   = Color(red: 0.38, green: 0.69, blue: 0.94)  // #61afef
    private static let odBg1    = Color(red: 0.157, green: 0.173, blue: 0.204) // #282c34
    private static let odBg2    = Color(red: 0.125, green: 0.137, blue: 0.165) // #20232a
    // Muted slate selection (One Dark's signature highlight), not the bright accent.
    private static let odSel1   = Color(red: 0.239, green: 0.290, blue: 0.388) // #3d4a63
    private static let odSel2   = Color(red: 0.192, green: 0.227, blue: 0.302) // #313a4d

    /// Accent used for controls (segmented picker, AI button…).
    var accent: Color {
        switch self {
        case .system:   return .accentColor
        case .midnight: return Self.indigo
        case .oneDark:  return Self.odBlue
        }
    }

    /// Gradient fill for the selected result row.
    var selectionGradient: [Color] {
        switch self {
        case .system:   return [Color.accentColor.opacity(0.95), Color.accentColor.opacity(0.78)]
        case .midnight: return [Color(red: 0.45, green: 0.50, blue: 1.0), Self.violet]
        case .oneDark:  return [Self.odSel1, Self.odSel2]
        }
    }

    var glow: Color {
        switch self {
        case .system:   return Color.accentColor.opacity(0.35)
        case .midnight: return Self.indigo.opacity(0.35)
        case .oneDark:  return Color.black.opacity(0.35)   // soft dark shadow, no bright halo
        }
    }

    /// Backdrop for the panel: frosted material (system) or a solid dark gradient.
    @ViewBuilder func panelBackground() -> some View {
        switch self {
        case .system:
            VisualEffectView().ignoresSafeArea()
        case .midnight:
            LinearGradient(colors: [Color(red: 0.105, green: 0.12, blue: 0.205),
                                    Color(red: 0.08, green: 0.085, blue: 0.16)],
                           startPoint: .top, endPoint: .bottom).ignoresSafeArea()
        case .oneDark:
            LinearGradient(colors: [Self.odBg1, Self.odBg2],
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

import SwiftUI

/// Visual themes for the search panel.
enum AppTheme: String, CaseIterable, Identifiable {
    case system     // current look — follows the macOS system accent, frosted panel
    case midnight   // the README indigo/violet look on a solid dark panel
    case oneDark    // the Atom One Dark color scheme
    case dracula    // the Dracula color scheme
    case nord       // the Nord color scheme
    case tokyoNight // the Tokyo Night color scheme

    var id: String { rawValue }
    var label: String {
        switch self {
        case .system:     return "System (default)"
        case .midnight:   return "Midnight"
        case .oneDark:    return "One Dark"
        case .dracula:    return "Dracula"
        case .nord:       return "Nord"
        case .tokyoNight: return "Tokyo Night"
        }
    }

    private static let indigo = Color(red: 0.42, green: 0.47, blue: 1.0)   // ~#6a78ff
    private static let violet = Color(red: 0.36, green: 0.22, blue: 0.86)  // ~#5b38dc

    private static func rgb(_ r: Double, _ g: Double, _ b: Double) -> Color {
        Color(red: r / 255, green: g / 255, blue: b / 255)
    }

    // Per-theme palette: accent, two background-gradient stops, two selection stops.
    private struct Palette { let accent: Color; let bg1: Color; let bg2: Color; let sel1: Color; let sel2: Color }
    private var palette: Palette? {
        switch self {
        case .system, .midnight:
            return nil
        case .oneDark:    // #61afef / #282c34 / selection #3d4a63
            return Palette(accent: Self.rgb(97, 175, 239), bg1: Self.rgb(40, 44, 52), bg2: Self.rgb(32, 35, 42),
                           sel1: Self.rgb(61, 74, 99), sel2: Self.rgb(49, 58, 77))
        case .dracula:    // #bd93f9 / #282a36 / selection #44475a
            return Palette(accent: Self.rgb(189, 147, 249), bg1: Self.rgb(40, 42, 54), bg2: Self.rgb(33, 34, 44),
                           sel1: Self.rgb(68, 71, 90), sel2: Self.rgb(56, 58, 74))
        case .nord:       // #88c0d0 / #2e3440 / selection #434c5e
            return Palette(accent: Self.rgb(136, 192, 208), bg1: Self.rgb(46, 52, 64), bg2: Self.rgb(39, 44, 54),
                           sel1: Self.rgb(67, 76, 94), sel2: Self.rgb(59, 66, 82))
        case .tokyoNight: // #7aa2f7 / #1a1b26 / selection #2e3a5c
            return Palette(accent: Self.rgb(122, 162, 247), bg1: Self.rgb(26, 27, 38), bg2: Self.rgb(22, 22, 30),
                           sel1: Self.rgb(46, 58, 92), sel2: Self.rgb(37, 48, 78))
        }
    }

    /// Accent used for controls (segmented picker, AI button…).
    var accent: Color {
        switch self {
        case .system:   return .accentColor
        case .midnight: return Self.indigo
        default:        return palette?.accent ?? .accentColor
        }
    }

    /// Gradient fill for the selected result row.
    var selectionGradient: [Color] {
        switch self {
        case .system:   return [Color.accentColor.opacity(0.95), Color.accentColor.opacity(0.78)]
        case .midnight: return [Color(red: 0.45, green: 0.50, blue: 1.0), Self.violet]
        default:
            if let p = palette { return [p.sel1, p.sel2] }
            return [Color.accentColor.opacity(0.95), Color.accentColor.opacity(0.78)]
        }
    }

    var glow: Color {
        switch self {
        case .system:   return Color.accentColor.opacity(0.35)
        case .midnight: return Self.indigo.opacity(0.35)
        default:        return Color.black.opacity(0.35)   // soft dark shadow, no bright halo
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
        default:
            let p = palette
            LinearGradient(colors: [p?.bg1 ?? .black, p?.bg2 ?? .black],
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

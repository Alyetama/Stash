import Foundation

/// How a compressed export is packaged.
///
/// The tool for each format is resolved by absolute path rather than through
/// `PATH`: an app launched from Finder inherits a minimal environment, so anything
/// installed by Homebrew, MacPorts or a conda distribution is invisible to a plain
/// `which`. Only zip, gzip and bzip2 ship with macOS — the rest are offered but
/// reported as missing until they're installed.
enum ExportFormat: String, CaseIterable, Identifiable {
    case zip      = "zip"
    case zstd     = "zstd"
    case sevenZip = "7z"
    case gzip     = "gzip"
    case xz       = "xz"
    case bzip2    = "bzip2"

    /// Always present on macOS, so it can never leave the user unable to export.
    static let fallback: ExportFormat = .zip

    var id: String { rawValue }

    var label: String {
        switch self {
        case .zip:      return "Zip"
        case .zstd:     return "Zstandard"
        case .sevenZip: return "7-Zip"
        case .gzip:     return "gzip"
        case .xz:       return "xz"
        case .bzip2:    return "bzip2"
        }
    }

    /// Appended after ".sqlite" — e.g. "Stash Export 2026-08-07.sqlite.zst".
    var fileExtension: String {
        switch self {
        case .zip:      return "zip"
        case .zstd:     return "zst"
        case .sevenZip: return "7z"
        case .gzip:     return "gz"
        case .xz:       return "xz"
        case .bzip2:    return "bz2"
        }
    }

    var menuLabel: String { "\(label) (.\(fileExtension))" }

    /// Shown when the tool is missing. Nil for the formats macOS always has.
    var installHint: String? {
        switch self {
        case .zip, .gzip, .bzip2: return nil
        case .zstd:               return "brew install zstd"
        case .sevenZip:           return "brew install sevenzip"
        case .xz:                 return "brew install xz"
        }
    }

    /// Executable names to look for, most preferred first.
    private var executables: [String] {
        switch self {
        case .zip:      return ["ditto"]
        case .zstd:     return ["zstd"]
        case .sevenZip: return ["7zz", "7z", "7za"]
        case .gzip:     return ["gzip"]
        case .xz:       return ["xz"]
        case .bzip2:    return ["bzip2"]
        }
    }

    /// Where third-party tools usually land, in search order.
    private static let searchPaths: [String] = {
        let home = NSHomeDirectory()
        return ["/usr/bin", "/bin",
                "/opt/homebrew/bin",            // Homebrew (Apple Silicon)
                "/usr/local/bin",               // Homebrew (Intel) / manual installs
                "/opt/local/bin",               // MacPorts
                home + "/miniforge3/bin",
                home + "/miniconda3/bin",
                home + "/anaconda3/bin",
                home + "/.local/bin"]
    }()

    /// The tool backing this format, if it's installed.
    var toolURL: URL? {
        for name in executables {
            for dir in Self.searchPaths {
                let path = dir + "/" + name
                if FileManager.default.isExecutableFile(atPath: path) {
                    return URL(fileURLWithPath: path)
                }
            }
        }
        return nil
    }

    var isAvailable: Bool { toolURL != nil }

    /// Arguments that turn `input` into `output`, and whether the tool writes the
    /// archive itself or streams it to stdout (gzip and friends only do the latter).
    func invocation(input: URL, output: URL) -> (args: [String], writesStdout: Bool) {
        switch self {
        case .zip:      return (["-c", "-k", "--sequesterRsrc", input.path, output.path], false)
        case .zstd:     return (["-q", "-f", "-o", output.path, input.path], false)
        case .sevenZip: return (["a", "-bd", "-y", output.path, input.path], false)
        case .gzip:     return (["-c", input.path], true)
        case .xz:       return (["-c", input.path], true)
        case .bzip2:    return (["-c", input.path], true)
        }
    }

    /// The format the user picked in Settings, falling back to zip.
    static var preferred: ExportFormat {
        ExportFormat(rawValue: UserDefaults.standard.string(forKey: "exportFormat") ?? "") ?? .fallback
    }
}

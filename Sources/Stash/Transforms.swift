import SwiftUI

/// User-configurable transformations applied to a clip's text just before it is
/// placed on the clipboard. Persisted in UserDefaults so they stick across launches.
final class TransformSettings: ObservableObject {
    @Published var upper: Bool        { didSet { save("upper", upper) } }
    @Published var lower: Bool        { didSet { save("lower", lower) } }
    @Published var capitalize: Bool   { didSet { save("capitalize", capitalize) } }
    @Published var singleLine: Bool   { didSet { save("singleLine", singleLine) } }
    @Published var removeEmpty: Bool  { didSet { save("removeEmpty", removeEmpty) } }
    @Published var stripAll: Bool     { didSet { save("stripAll", stripAll) } }
    @Published var trim: Bool         { didSet { save("trim", trim) } }
    @Published var prependOn: Bool    { didSet { save("prependOn", prependOn) } }
    @Published var appendOn: Bool     { didSet { save("appendOn", appendOn) } }
    @Published var prepend: String    { didSet { d.set(prepend, forKey: k("prepend")) } }
    @Published var append: String     { didSet { d.set(append, forKey: k("append")) } }

    private let d = UserDefaults.standard
    private func k(_ s: String) -> String { "transform.\(s)" }
    private func save(_ key: String, _ v: Bool) { d.set(v, forKey: k(key)) }

    init() {
        upper = d.bool(forKey: "transform.upper")
        lower = d.bool(forKey: "transform.lower")
        capitalize = d.bool(forKey: "transform.capitalize")
        singleLine = d.bool(forKey: "transform.singleLine")
        removeEmpty = d.bool(forKey: "transform.removeEmpty")
        stripAll = d.bool(forKey: "transform.stripAll")
        trim = d.bool(forKey: "transform.trim")
        prependOn = d.bool(forKey: "transform.prependOn")
        appendOn = d.bool(forKey: "transform.appendOn")
        prepend = d.string(forKey: "transform.prepend") ?? ""
        append = d.string(forKey: "transform.append") ?? ""
    }

    var isActive: Bool {
        upper || lower || capitalize || singleLine || removeEmpty || stripAll || trim
            || (prependOn && !prepend.isEmpty) || (appendOn && !append.isEmpty)
    }

    func reset() {
        upper = false; lower = false; capitalize = false; singleLine = false
        removeEmpty = false; stripAll = false; trim = false
        prependOn = false; appendOn = false; prepend = ""; append = ""
    }

    /// Apply the enabled transforms, in a sensible order, to `text`.
    func apply(to text: String) -> String {
        var t = text
        if trim { t = t.trimmingCharacters(in: .whitespacesAndNewlines) }
        if removeEmpty {
            t = t.split(separator: "\n", omittingEmptySubsequences: false)
                 .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
                 .joined(separator: "\n")
        }
        if singleLine {
            t = t.replacingOccurrences(of: "\r\n", with: " ")
                 .replacingOccurrences(of: "\n", with: " ")
                 .replacingOccurrences(of: "\r", with: " ")
        }
        if stripAll {
            t = t.components(separatedBy: .whitespacesAndNewlines).joined()
        }
        if upper { t = t.uppercased() }
        if lower { t = t.lowercased() }
        if capitalize { t = t.capitalized }
        if prependOn { t = prepend + t }
        if appendOn { t = t + append }
        return t
    }
}

/// Popover UI listing the copy transformations.
struct TransformsView: View {
    @ObservedObject var settings: TransformSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text("Copy Transformations")
                .font(.headline)
                .padding(.bottom, 2)

            Toggle("Make Upper Case", isOn: $settings.upper)
            Toggle("Make Lower Case", isOn: $settings.lower)
            Toggle("Capitalize Words", isOn: $settings.capitalize)
            Toggle("Make Single Line", isOn: $settings.singleLine)
            Toggle("Remove Empty Lines", isOn: $settings.removeEmpty)
            Toggle("Strip All Whitespace", isOn: $settings.stripAll)
            Toggle("Trim Surrounding Whitespace", isOn: $settings.trim)

            HStack(spacing: 8) {
                Toggle("Prepend", isOn: $settings.prependOn)
                TextField("text", text: $settings.prepend).textFieldStyle(.roundedBorder)
            }
            HStack(spacing: 8) {
                Toggle("Append", isOn: $settings.appendOn)
                TextField("text", text: $settings.append).textFieldStyle(.roundedBorder)
            }

            Divider().padding(.vertical, 2)
            HStack {
                Text(settings.isActive ? "Applied when you copy a clip" : "No transforms active")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Reset") { settings.reset() }
                    .disabled(!settings.isActive)
            }
        }
        .toggleStyle(.checkbox)
        .padding(16)
        .frame(width: 340)
    }
}

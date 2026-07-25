import SwiftUI

/// Persisted set of named groups the user can sort clips into. Group membership
/// itself lives on each clip (its `list` column); this just remembers the names
/// so empty groups survive and imported lists can be merged in.
final class GroupSettings: ObservableObject {
    @Published private(set) var groups: [String] = []
    /// Per-group SF Symbol name; groups without one fall back to `defaultIcon`.
    @Published private(set) var icons: [String: String] = [:]

    static let defaultIcon = "tag"
    /// Icons offered in the group editor.
    static let iconChoices = [
        "tag", "star", "bookmark", "folder", "tray.full", "doc.text", "link",
        "curlybraces", "terminal", "key", "envelope", "creditcard", "cart",
        "photo", "music.note", "video", "person", "building.2", "globe",
        "flame", "bolt", "heart", "leaf", "paintbrush", "wrench.and.screwdriver",
        "lightbulb", "book", "graduationcap", "briefcase", "calendar",
    ]

    private let d = UserDefaults.standard
    private let key = "groups"
    private let iconKey = "groupIcons"

    init() {
        groups = d.stringArray(forKey: key) ?? []
        icons = (d.dictionary(forKey: iconKey) as? [String: String]) ?? [:]
    }

    func icon(for name: String) -> String { icons[name] ?? Self.defaultIcon }

    func setIcon(_ symbol: String, for name: String) {
        icons[name] = symbol
        d.set(icons, forKey: iconKey)
    }

    /// Rename a group locally. The caller is responsible for moving the clips
    /// (see `Indexer.renameGroup`). Returns the trimmed new name, or nil if the
    /// name is empty or already taken by a different group.
    @discardableResult
    func rename(_ old: String, to newName: String) -> String? {
        let n = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !n.isEmpty, n != old else { return nil }
        if groups.contains(where: { $0.caseInsensitiveCompare(n) == .orderedSame && $0 != old }) { return nil }
        guard let i = groups.firstIndex(of: old) else { return nil }
        groups[i] = n
        if let sym = icons[old] { icons[old] = nil; icons[n] = sym; d.set(icons, forKey: iconKey) }
        sortInPlace()
        persist()
        return n
    }

    private func has(_ name: String) -> Bool {
        groups.contains { $0.caseInsensitiveCompare(name) == .orderedSame }
    }
    private func sortInPlace() {
        groups.sort { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }
    private func persist() { d.set(groups, forKey: key) }

    /// Create a group; returns the trimmed name (existing name if it already exists).
    @discardableResult
    func add(_ name: String) -> String? {
        let n = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !n.isEmpty else { return nil }
        if !has(n) { groups.append(n); sortInPlace(); persist() }
        return n
    }

    func remove(_ name: String) {
        groups.removeAll { $0 == name }
        if icons[name] != nil { icons[name] = nil; d.set(icons, forKey: iconKey) }
        persist()
    }

    /// Fold in names discovered in the database (e.g. imported Copy 'Em lists).
    func merge(_ discovered: [String]) {
        var changed = false
        for n in discovered where !has(n) { groups.append(n); changed = true }
        if changed { sortInPlace(); persist() }
    }
}

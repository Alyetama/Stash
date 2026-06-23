import SwiftUI

/// Persisted set of named groups the user can sort clips into. Group membership
/// itself lives on each clip (its `list` column); this just remembers the names
/// so empty groups survive and imported lists can be merged in.
final class GroupSettings: ObservableObject {
    @Published private(set) var groups: [String] = []

    private let d = UserDefaults.standard
    private let key = "groups"

    init() { groups = d.stringArray(forKey: key) ?? [] }

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
        persist()
    }

    /// Fold in names discovered in the database (e.g. imported Copy 'Em lists).
    func merge(_ discovered: [String]) {
        var changed = false
        for n in discovered where !has(n) { groups.append(n); changed = true }
        if changed { sortInPlace(); persist() }
    }
}

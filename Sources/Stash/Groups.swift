import SwiftUI
import AppKit

/// Editor for named groups: rename, re-icon, delete, and create — all in one list
/// instead of hunting through the menus.
struct GroupsView: View {
    @ObservedObject var groups: GroupSettings
    @ObservedObject var indexer: Indexer
    var onChanged: () -> Void

    @State private var counts: [String: Int] = [:]
    @State private var editing: [String: String] = [:]   // group -> in-progress name
    @State private var newName = ""
    @State private var pendingDelete: String?

    var body: some View {
        VStack(spacing: 0) {
            header

            Divider()

            if groups.groups.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "tray").font(.system(size: 26)).foregroundStyle(.tertiary)
                    Text("No groups yet").foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(groups.groups, id: \.self) { g in
                            row(for: g)
                            Divider().opacity(0.4)
                        }
                    }
                }
            }

            Divider()
            footer
        }
        .frame(width: 460, height: 420)
        .onAppear(perform: reload)
        .confirmationDialog(
            "Delete the group “\(pendingDelete ?? "")”?",
            isPresented: Binding(get: { pendingDelete != nil },
                                 set: { if !$0 { pendingDelete = nil } }),
            titleVisibility: .visible
        ) {
            Button("Delete Group Only") { delete(keepClips: true) }
            Button("Delete Group & Clips", role: .destructive) { delete(keepClips: false) }
            Button("Cancel", role: .cancel) { pendingDelete = nil }
        } message: {
            Text("Keep the clips and just remove the group, or delete the clips too. This can't be undone.")
        }
    }

    private var header: some View {
        HStack {
            Text("Groups").font(.headline)
            Spacer()
            Text("\(groups.groups.count) \(groups.groups.count == 1 ? "group" : "groups")")
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private func row(for g: String) -> some View {
        HStack(spacing: 10) {
            // Icon picker.
            Menu {
                ForEach(GroupSettings.iconChoices, id: \.self) { sym in
                    Button {
                        groups.setIcon(sym, for: g)
                    } label: { Label(sym, systemImage: sym) }
                }
            } label: {
                Image(systemName: groups.icon(for: g))
                    .font(.system(size: 14))
                    .frame(width: 30, height: 26)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("Change icon")

            // Rename in place: commits on Return or when focus leaves.
            TextField("Name", text: Binding(
                get: { editing[g] ?? g },
                set: { editing[g] = $0 }
            ))
            .textFieldStyle(.roundedBorder)
            .onSubmit { commitRename(g) }

            Text("\(counts[g] ?? 0)")
                .font(.caption).foregroundStyle(.secondary)
                .frame(minWidth: 38, alignment: .trailing)

            Button {
                pendingDelete = g
            } label: {
                Image(systemName: "trash").foregroundStyle(.red)
            }
            .buttonStyle(.borderless)
            .help("Delete group")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
    }

    private var footer: some View {
        HStack(spacing: 8) {
            TextField("New group name", text: $newName)
                .textFieldStyle(.roundedBorder)
                .onSubmit(addNew)
            Button("Add", action: addNew)
                .disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    // MARK: actions

    private func reload() {
        indexer.fetchGroupCounts { counts = $0 }
    }

    private func addNew() {
        guard let created = groups.add(newName) else { return }
        newName = ""
        _ = created
        onChanged()
        reload()
    }

    private func commitRename(_ old: String) {
        guard let typed = editing[old] else { return }
        editing[old] = nil
        guard let new = groups.rename(old, to: typed) else { return }   // no-op on empty/dupe
        indexer.renameGroup(old, to: new) {
            onChanged()
            reload()
        }
    }

    private func delete(keepClips: Bool) {
        guard let g = pendingDelete else { return }
        pendingDelete = nil
        indexer.deleteGroup(g, deletingClips: !keepClips) {
            groups.remove(g)
            onChanged()
            reload()
        }
    }
}

/// Owns the Groups window (the app is a menu-bar agent, so we manage it manually).
final class GroupsWindowController {
    private var window: NSWindow?
    private let groups: GroupSettings
    private let indexer: Indexer
    private let onChanged: () -> Void

    init(groups: GroupSettings, indexer: Indexer, onChanged: @escaping () -> Void) {
        self.groups = groups
        self.indexer = indexer
        self.onChanged = onChanged
    }

    func show() {
        if window == nil {
            let view = GroupsView(groups: groups, indexer: indexer, onChanged: onChanged)
            let w = NSWindow(contentViewController: NSHostingController(rootView: view))
            w.title = "Groups"
            w.styleMask = [.titled, .closable]
            w.isReleasedWhenClosed = false
            w.center()
            window = w
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}

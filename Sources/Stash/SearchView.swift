import SwiftUI

struct SearchView: View {
    @ObservedObject var controller: SearchController
    @ObservedObject var indexer: Indexer
    var onClose: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
            Divider()
            footer
        }
        .frame(minWidth: 560, minHeight: 360)
        .onChange(of: controller.query) { _ in controller.runSearch() }
        .onChange(of: controller.mode) { _ in controller.runSearch() }
        .onChange(of: controller.favoritesOnly) { _ in controller.runSearch() }
    }

    // MARK: header (search field + mode selector)

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 18))
                .foregroundStyle(.secondary)
            SearchField(
                text: $controller.query,
                onMoveUp: { controller.moveUp() },
                onMoveDown: { controller.moveDown() },
                onSubmit: { controller.copySelected(done: onClose) },
                onCancel: onClose)
            .frame(height: 30)

            Picker("", selection: $controller.mode) {
                ForEach(SearchMode.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 210)

            // Scope dropdown: All clips vs Favorites.
            Menu {
                Button { controller.favoritesOnly = false } label: {
                    Label("All clips", systemImage: controller.favoritesOnly ? "" : "checkmark")
                }
                Button { controller.favoritesOnly = true } label: {
                    Label("Favorites", systemImage: controller.favoritesOnly ? "checkmark" : "star")
                }
            } label: {
                Image(systemName: controller.favoritesOnly ? "star.fill" : "line.3.horizontal.decrease.circle")
                    .foregroundStyle(controller.favoritesOnly ? AnyShapeStyle(.yellow) : AnyShapeStyle(.secondary))
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .help("Show all clips or only favorites")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    // MARK: content

    @ViewBuilder private var content: some View {
        if indexer.phase == .importing {
            buildingView
        } else if indexer.phase == .error {
            messageView(indexer.message, systemImage: "exclamationmark.triangle")
        } else if !controller.results.isEmpty {
            resultsList
        } else if controller.searching {
            messageView("Loading…", systemImage: "hourglass")
        } else if controller.query.isEmpty {
            messageView("No clipboard entries yet", systemImage: "tray")
        } else {
            messageView("No matches", systemImage: "tray")
        }
    }

    private var resultsList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(Array(controller.results.enumerated()), id: \.element.pk) { idx, r in
                        ResultRow(result: r, selected: idx == controller.selected)
                            .id(r.pk)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                // Single click copies to the clipboard and closes.
                                controller.selected = idx
                                controller.copySelected(done: onClose)
                            }
                            .contextMenu {
                                Button {
                                    controller.selected = idx
                                    controller.copySelected(done: onClose)
                                } label: { Label("Copy", systemImage: "doc.on.doc") }

                                Button {
                                    controller.toggleFavorite(r)
                                } label: {
                                    Label(r.favorite ? "Remove from Favorites" : "Add to Favorites",
                                          systemImage: r.favorite ? "star.slash" : "star")
                                }

                                Divider()

                                Button(role: .destructive) {
                                    controller.delete(r)
                                } label: { Label("Delete", systemImage: "trash") }
                            }
                            .onAppear {
                                // Prefetch the next page as the user scrolls near the bottom.
                                if idx >= controller.results.count - 5 { controller.loadMore() }
                            }
                    }
                    if controller.hasMore {
                        ProgressView()
                            .controlSize(.small)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                    }
                }
            }
            .onChange(of: controller.selected) { sel in
                guard controller.results.indices.contains(sel) else { return }
                withAnimation(.easeOut(duration: 0.1)) {
                    proxy.scrollTo(controller.results[sel].pk, anchor: .center)
                }
            }
        }
    }

    private var buildingView: some View {
        VStack(spacing: 14) {
            ProgressView(value: Double(indexer.buildDone),
                         total: Double(max(indexer.buildTotal, 1)))
                .frame(width: 320)
            Text("Importing history from Copy 'Em…")
                .font(.headline)
            Text("\(indexer.buildDone.formatted()) / \(indexer.buildTotal.formatted()) entries")
                .font(.callout).foregroundStyle(.secondary)
            Text("One-time. New clips are captured automatically from here on.")
                .font(.caption).foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyHint: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Substring — matches text anywhere (min 3 chars)", systemImage: "textformat")
            Label("Words — whole-word & prefix, ranked by relevance", systemImage: "text.word.spacing")
            Label("Regex — full regular-expression scan", systemImage: "asterisk")
            Divider().padding(.vertical, 4)
            Text("\(indexer.indexedCount.formatted()) entries indexed · ↵ copies the highlighted result")
                .font(.caption).foregroundStyle(.secondary)
        }
        .font(.callout)
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .padding()
    }

    private func messageView(_ text: String, systemImage: String) -> some View {
        VStack(spacing: 10) {
            Image(systemName: systemImage).font(.system(size: 28)).foregroundStyle(.tertiary)
            Text(text).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    // MARK: footer

    private var footer: some View {
        HStack {
            Text(controller.status.isEmpty
                 ? "\(indexer.indexedCount.formatted()) indexed"
                 : controller.status)
                .font(.caption).foregroundStyle(.secondary)
            Spacer()
            Text("click or ↵ copies · ↑↓ navigate · esc close")
                .font(.caption).foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }
}

private struct ResultRow: View {
    let result: SearchResult
    let selected: Bool

    private static let dateFmt: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter(); f.unitsStyle = .abbreviated; return f
    }()

    private var preview: String {
        result.text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var meta: String {
        var parts: [String] = []
        if let a = result.app, !a.isEmpty { parts.append(a) }
        if let l = result.list, !l.isEmpty { parts.append("⌗ \(l)") }
        if result.created > 0 {
            parts.append(Self.dateFmt.localizedString(for: Date(timeIntervalSince1970: result.created), relativeTo: Date()))
        }
        if result.useCount > 0 { parts.append("\(result.useCount)×") }
        return parts.joined(separator: "  ·  ")
    }

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 3) {
                Text(preview)
                    .lineLimit(3)
                    .font(.system(size: 13))
                    .foregroundStyle(selected ? Color.white : Color.primary)
                if !meta.isEmpty {
                    Text(meta)
                        .font(.caption2)
                        .foregroundStyle(selected ? Color.white.opacity(0.85) : Color.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if result.favorite {
                Image(systemName: "star.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(selected ? AnyShapeStyle(Color.white) : AnyShapeStyle(.yellow))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(selected ? Color.accentColor : Color.clear)
    }
}

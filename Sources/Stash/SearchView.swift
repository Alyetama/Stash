import SwiftUI

struct SearchView: View {
    @ObservedObject var controller: SearchController
    @ObservedObject var indexer: Indexer
    @ObservedObject var transforms: TransformSettings
    @ObservedObject var ai: AISettings
    var onClose: () -> Void
    @State private var showTransforms = false
    @State private var showAI = false

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().opacity(0.4)
            content
            Divider().opacity(0.4)
            footer
        }
        .background(VisualEffectView().ignoresSafeArea())
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

            // Copy transformations popover.
            Button { showTransforms.toggle() } label: {
                Image(systemName: "textformat")
                    .foregroundStyle(transforms.isActive ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.secondary))
            }
            .buttonStyle(.borderless)
            .help("Copy transformations")
            .popover(isPresented: $showTransforms, arrowEdge: .bottom) {
                TransformsView(settings: transforms)
            }

            // AI regex generator — only in the Regex tab.
            if controller.mode == .regex {
                Button { showAI.toggle() } label: {
                    Image(systemName: "sparkles")
                        .foregroundStyle(ai.enabled ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.secondary))
                }
                .buttonStyle(.borderless)
                .help("Generate a regex with AI")
                .popover(isPresented: $showAI, arrowEdge: .bottom) {
                    AIRegexView(ai: ai, controller: controller, onClose: { showAI = false })
                }
            }
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
                LazyVStack(spacing: 1) {
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
                .padding(.vertical, 5)
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
    @State private var hovering = false
    @State private var expanded = false

    /// Worth a "show more" toggle: multiline or long single-line text (not images).
    private var isExpandable: Bool {
        guard !result.isImage else { return false }
        return preview.contains("\n") || preview.count > 90
    }

    private static let dateFmt: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter(); f.unitsStyle = .abbreviated; return f
    }()

    private var preview: String {
        result.text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static let linkDetector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)

    /// The preview text with any URLs/links coloured blue and underlined.
    private var styledPreview: AttributedString {
        let s = preview
        var attr = AttributedString(s)
        guard let detector = Self.linkDetector else { return attr }
        let ns = s as NSString
        let linkColor = selected ? Color.white : Color(red: 0.30, green: 0.55, blue: 1.0)
        for m in detector.matches(in: s, range: NSRange(location: 0, length: ns.length)) {
            guard let r = Range(m.range, in: s) else { continue }
            let lo = s.distance(from: s.startIndex, to: r.lowerBound)
            let hi = s.distance(from: s.startIndex, to: r.upperBound)
            let aLo = attr.index(attr.startIndex, offsetByCharacters: lo)
            let aHi = attr.index(attr.startIndex, offsetByCharacters: hi)
            attr[aLo..<aHi].foregroundColor = linkColor
            attr[aLo..<aHi].underlineStyle = .single
        }
        return attr
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

    private var appName: String { (result.app?.isEmpty == false ? result.app! : "•") }

    private var badge: some View {
        let initial = String(appName.first.map(String.init) ?? "•").uppercased()
        return RoundedRectangle(cornerRadius: 7, style: .continuous)
            .fill(Self.color(for: appName).gradient)
            .frame(width: 28, height: 28)
            .overlay(Text(initial).font(.system(size: 13, weight: .semibold)).foregroundStyle(.white))
            .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).strokeBorder(.white.opacity(0.15), lineWidth: 0.5))
    }

    @ViewBuilder private var leading: some View {
        if result.isImage {
            let nsimg = result.thumbPath.flatMap { NSImage(contentsOfFile: $0) }
            Group {
                if let nsimg {
                    Image(nsImage: nsimg).resizable().aspectRatio(contentMode: .fill)
                } else {
                    Image(systemName: "photo").font(.system(size: 18)).foregroundStyle(.secondary)
                }
            }
            .frame(width: 48, height: 48)
            .background(Color.black.opacity(0.2))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(.white.opacity(0.18), lineWidth: 0.5))
        } else {
            badge
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 11) {
            leading
            VStack(alignment: .leading, spacing: 3) {
                Text(styledPreview)
                    .lineLimit(expanded ? nil : 2)
                    .font(.system(size: 13))
                    .foregroundStyle(selected ? Color.white : Color.primary)
                    .tint(selected ? Color.white : Color(red: 0.30, green: 0.55, blue: 1.0))
                if !meta.isEmpty {
                    Text(meta)
                        .font(.caption2)
                        .foregroundStyle(selected ? Color.white.opacity(0.85) : Color.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(spacing: 8) {
                if result.favorite {
                    Image(systemName: "star.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(selected ? AnyShapeStyle(.white) : AnyShapeStyle(.yellow))
                }
                if isExpandable {
                    Button { withAnimation(.easeInOut(duration: 0.15)) { expanded.toggle() } } label: {
                        Image(systemName: expanded ? "chevron.up" : "chevron.down")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(selected ? Color.white : Color.secondary)
                            .frame(width: 18, height: 18)
                            .background(
                                Circle().fill(selected ? Color.white.opacity(0.18) : Color.primary.opacity(0.08)))
                    }
                    .buttonStyle(.plain)
                    .help(expanded ? "Show less" : "Show more")
                }
            }
            .padding(.top, 1)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(selected
                      ? AnyShapeStyle(LinearGradient(colors: [Color.accentColor.opacity(0.95), Color.accentColor.opacity(0.78)],
                                                     startPoint: .top, endPoint: .bottom))
                      : (hovering ? AnyShapeStyle(Color.primary.opacity(0.07)) : AnyShapeStyle(Color.clear)))
        )
        .overlay(
            selected
            ? RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(.white.opacity(0.18), lineWidth: 0.5)
            : nil
        )
        .shadow(color: selected ? Color.accentColor.opacity(0.35) : .clear, radius: 6, y: 2)
        .padding(.horizontal, 8)
        .onHover { hovering = $0 }
    }

    /// Deterministic, pleasant color per source app.
    static func color(for s: String) -> Color {
        var h = 5381
        for u in s.unicodeScalars { h = ((h << 5) &+ h) &+ Int(u.value) }
        let hue = Double((h % 360 + 360) % 360) / 360.0
        return Color(hue: hue, saturation: 0.55, brightness: 0.72)
    }
}

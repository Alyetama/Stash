import SwiftUI
import AppKit

struct SearchView: View {
    @ObservedObject var controller: SearchController
    @ObservedObject var indexer: Indexer
    @ObservedObject var transforms: TransformSettings
    @ObservedObject var ai: AISettings
    @ObservedObject var theme: ThemeSettings
    @ObservedObject var groups: GroupSettings
    var onOpenSettings: () -> Void
    var onDeleteGroup: (String) -> Void
    var onHoldChange: (Bool) -> Void
    var onClose: () -> Void
    var compact: Bool = false
    @State private var showTransforms = false
    @State private var showAI = false
    // New-group prompt. `newGroupTarget` is the entry to add once created (nil = just create + view it).
    @State private var showNewGroup = false
    @State private var newGroupName = ""
    @State private var newGroupTarget: SearchResult?

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().opacity(0.4)
            content
            Divider().opacity(0.4)
            footer
        }
        .background(theme.theme.panelBackground())
        .environment(\.appTheme, theme.theme)
        .tint(theme.theme.accent)
        .frame(minWidth: compact ? 360 : 560, minHeight: compact ? 300 : 360)
        .onChange(of: controller.query) { _ in controller.runSearch() }
        .onChange(of: controller.mode) { _ in controller.runSearch() }
        .onChange(of: controller.scope) { _ in controller.runSearch() }
        // Keep the panel open while the AI popover (and its Keychain prompt) is up.
        .onChange(of: showAI) { onHoldChange($0) }
        // Likewise while the new-group prompt is up, so the panel doesn't dismiss.
        .onChange(of: showNewGroup) { onHoldChange($0) }
        .onAppear { controller.refreshGroups() }
        .alert("New group", isPresented: $showNewGroup) {
            TextField("Group name", text: $newGroupName)
            Button("Create") {
                let name = newGroupName
                newGroupName = ""
                guard let created = groups.add(name) else { return }
                if let target = newGroupTarget { controller.assignGroup(target, to: created) }
                else { controller.scope = .group(created) }
                newGroupTarget = nil
            }
            Button("Cancel", role: .cancel) { newGroupName = ""; newGroupTarget = nil }
        } message: {
            Text(newGroupTarget == nil ? "Name a new group to view." : "Name a new group to add this clip to.")
        }
    }

    // MARK: header (search field + mode selector)

    private var magnifier: some View {
        Image(systemName: "magnifyingglass")
            .font(.system(size: compact ? 15 : 18))
            .foregroundStyle(.secondary)
    }

    private var searchFieldView: some View {
        SearchField(
            text: $controller.query,
            fontSize: compact ? 17 : 22,
            onMoveUp: { controller.moveUp() },
            onMoveDown: { controller.moveDown() },
            onSubmit: { controller.copySelected(done: onClose) },
            onCancel: onClose)
        .frame(height: compact ? 24 : 30)
    }

    private var modePicker: some View {
        Picker("", selection: $controller.mode) {
            ForEach(SearchMode.allCases) { Text($0.rawValue).tag($0) }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .frame(width: compact ? nil : 210)
    }

    private var scopeIcon: String {
        switch controller.scope {
        case .favorites: return "star.fill"
        case .group:     return "tag.fill"
        case .all:       return "line.3.horizontal.decrease.circle"
        }
    }
    private func isScope(_ s: SearchScope) -> Bool { controller.scope == s }

    // Scope dropdown: All clips / Favorites / each named group.
    private var favoritesMenu: some View {
        Menu {
            Button { controller.scope = .all } label: {
                Label("All clips", systemImage: isScope(.all) ? "checkmark" : "tray.full")
            }
            Button { controller.scope = .favorites } label: {
                Label("Favorites", systemImage: isScope(.favorites) ? "checkmark" : "star")
            }
            if !groups.groups.isEmpty {
                Divider()
                ForEach(groups.groups, id: \.self) { g in
                    Button { controller.scope = .group(g) } label: {
                        Label(g, systemImage: isScope(.group(g)) ? "checkmark" : "tag")
                    }
                }
            }
            Divider()
            Button { newGroupTarget = nil; newGroupName = ""; showNewGroup = true } label: {
                Label("New group…", systemImage: "plus")
            }
            if !groups.groups.isEmpty {
                Menu {
                    ForEach(groups.groups, id: \.self) { g in
                        Button(role: .destructive) { onDeleteGroup(g) } label: { Text(g) }
                    }
                } label: {
                    Label("Delete group…", systemImage: "trash")
                }
            }
        } label: {
            Image(systemName: scopeIcon)
                .foregroundStyle(isScope(.all) ? AnyShapeStyle(.secondary)
                                 : (isScope(.favorites) ? AnyShapeStyle(.yellow) : AnyShapeStyle(theme.theme.accent)))
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help("Filter by favorites or a group")
    }

    private var transformsButton: some View {
        Button { showTransforms.toggle() } label: {
            Image(systemName: "textformat")
                .foregroundStyle(transforms.isActive ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.secondary))
        }
        .buttonStyle(.borderless)
        .help("Copy transformations")
        .popover(isPresented: $showTransforms, arrowEdge: .bottom) {
            TransformsView(settings: transforms)
        }
    }

    // AI regex generator — only in the Regex tab.
    @ViewBuilder private var aiButton: some View {
        if controller.mode == .regex {
            Button { showAI.toggle() } label: {
                Image(systemName: "sparkles")
                    .foregroundStyle(ai.enabled ? AnyShapeStyle(theme.theme.accent) : AnyShapeStyle(.secondary))
            }
            .buttonStyle(.borderless)
            .help("Generate a regex with AI")
            .popover(isPresented: $showAI, arrowEdge: .bottom) {
                AIRegexView(ai: ai, controller: controller, onClose: { showAI = false })
            }
        }
    }

    private var settingsButton: some View {
        Button(action: onOpenSettings) {
            Image(systemName: "gearshape").foregroundStyle(.secondary)
        }
        .buttonStyle(.borderless)
        .help("Settings")
    }

    @ViewBuilder private var header: some View {
        if compact {
            // Two rows so the controls breathe in the narrow panel.
            VStack(spacing: 8) {
                HStack(spacing: 10) { magnifier; searchFieldView; settingsButton }
                HStack(spacing: 8) {
                    modePicker.frame(maxWidth: .infinity)
                    favoritesMenu; transformsButton; aiButton
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 16)
            .padding(.bottom, 10)
        } else {
            HStack(spacing: 12) {
                magnifier; searchFieldView; modePicker
                favoritesMenu; transformsButton; aiButton; settingsButton
            }
            .padding(.horizontal, 16)
            .padding(.top, 18)
            .padding(.bottom, 12)
        }
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

    @ViewBuilder
    private func groupSubmenu(for r: SearchResult) -> some View {
        Menu {
            ForEach(groups.groups, id: \.self) { g in
                Button { controller.assignGroup(r, to: g) } label: {
                    if r.list == g { Label(g, systemImage: "checkmark") } else { Text(g) }
                }
            }
            if let l = r.list, !l.isEmpty {
                Divider()
                Button { controller.assignGroup(r, to: nil) } label: {
                    Label("Remove from group", systemImage: "tag.slash")
                }
            }
            Divider()
            Button { newGroupTarget = r; newGroupName = ""; showNewGroup = true } label: {
                Label("New group…", systemImage: "plus")
            }
        } label: {
            Label("Add to Group", systemImage: "tray.full")
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

                                groupSubmenu(for: r)

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
            Text("Importing clips…")
                .font(.headline)
            Text("\(indexer.buildDone.formatted()) / \(indexer.buildTotal.formatted()) entries")
                .font(.callout).foregroundStyle(.secondary)
            Text("You can keep using Stash while this finishes.")
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
        VStack(alignment: .leading, spacing: 2) {
            // Total clip count, on top.
            Text("\(indexer.indexedCount.formatted()) clips total")
                .font(.caption2).foregroundStyle(.secondary)
            HStack(spacing: 8) {
                Text(controller.status.isEmpty
                     ? "\(indexer.indexedCount.formatted()) indexed"
                     : controller.status)
                    .font(.caption).foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer(minLength: 8)
                // Same hint as before; shrinks to stay on one line when compact.
                Text("click or ↵ copies · ↑↓ navigate · esc close")
                    .font(.caption).foregroundStyle(.tertiary)
                    .lineLimit(1).minimumScaleFactor(0.6)
            }
        }
        .padding(.horizontal, compact ? 12 : 16)
        .padding(.vertical, 8)
    }
}

/// Resolves a source-app name (as stored on a clip) to its icon, cached so the
/// lookup happens once per app rather than per row.
enum AppIconResolver {
    private static var cache: [String: NSImage?] = [:]

    static func icon(for name: String) -> NSImage? {
        if let cached = cache[name] { return cached }
        let img = resolveURL(name).map { NSWorkspace.shared.icon(forFile: $0.path) }
        cache[name] = img
        return img
    }

    /// Map a recorded app name to its bundle URL. The recorded name is the app's
    /// *display* name, which can differ from its bundle filename (e.g. Copy 'Em
    /// stores "iTerm2" but the bundle on disk is "iTerm.app").
    private static func resolveURL(_ name: String) -> URL? {
        let ws = NSWorkspace.shared
        // 1. Exact bundle-filename match (Safari, Google Chrome, …).
        if let p = ws.fullPath(forApplication: name) { return URL(fileURLWithPath: p) }
        // 2. A running app whose display name matches (handles iTerm2 → iTerm.app).
        if let u = ws.runningApplications.first(where: { $0.localizedName == name })?.bundleURL { return u }
        // 3. Strip a trailing version number from the name and retry (iTerm2 → iTerm).
        let stripped = name.replacingOccurrences(of: "\\s*\\d+$", with: "", options: .regularExpression)
        if stripped != name, !stripped.isEmpty, let p = ws.fullPath(forApplication: stripped) {
            return URL(fileURLWithPath: p)
        }
        return nil
    }
}

private struct ResultRow: View {
    let result: SearchResult
    let selected: Bool
    @Environment(\.appTheme) private var theme
    @State private var hovering = false
    @State private var expanded = false
    @State private var availWidth: CGFloat = 0

    /// True only when the 2-line-limited preview is actually truncated.
    private var isExpandable: Bool {
        guard !result.isImage, availWidth > 1 else { return false }
        return Self.lineCount(of: preview, width: availWidth) > 2
    }

    /// How many lines `text` occupies at `width` with the row font (counts wraps
    /// and explicit newlines), so a clip that fits in 2 lines shows no toggle.
    private static func lineCount(of text: String, width: CGFloat) -> Int {
        let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 13)]
        let opts: NSString.DrawingOptions = [.usesLineFragmentOrigin, .usesFontLeading]
        let one = ("Ag" as NSString).boundingRect(
            with: NSSize(width: 100_000, height: CGFloat.greatestFiniteMagnitude),
            options: opts, attributes: attrs).height
        guard one > 0 else { return 1 }
        let full = (text as NSString).boundingRect(
            with: NSSize(width: width, height: CGFloat.greatestFiniteMagnitude),
            options: opts, attributes: attrs).height
        return Int((full / one).rounded())
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

    @ViewBuilder private var badge: some View {
        if let icon = AppIconResolver.icon(for: appName) {
            Image(nsImage: icon)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 28, height: 28)
        } else {
            let initial = String(appName.first.map(String.init) ?? "•").uppercased()
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(Self.color(for: appName).gradient)
                .frame(width: 28, height: 28)
                .overlay(Text(initial).font(.system(size: 13, weight: .semibold)).foregroundStyle(.white))
                .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).strokeBorder(.white.opacity(0.15), lineWidth: 0.5))
        }
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
            .background(GeometryReader { g in
                Color.clear
                    .onAppear { availWidth = g.size.width }
                    .onChange(of: g.size.width) { availWidth = $0 }
            })

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
                      ? AnyShapeStyle(LinearGradient(colors: theme.selectionGradient,
                                                     startPoint: .top, endPoint: .bottom))
                      : (hovering ? AnyShapeStyle(Color.primary.opacity(0.07)) : AnyShapeStyle(Color.clear)))
        )
        .overlay(
            selected
            ? RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(.white.opacity(0.18), lineWidth: 0.5)
            : nil
        )
        .shadow(color: selected ? theme.glow : .clear, radius: 6, y: 2)
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

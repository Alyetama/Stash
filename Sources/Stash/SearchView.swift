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
    @State private var rowTextWidth: CGFloat = 0   // measured once for the whole list

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

    @ViewBuilder private var clearButton: some View {
        if !controller.query.isEmpty {
            Button {
                controller.query = ""
                NotificationCenter.default.post(name: .focusSearchField, object: nil)
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: compact ? 13 : 15))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.borderless)
            .help("Clear search")
        }
    }

    private var modePicker: some View {
        Picker("", selection: $controller.mode) {
            ForEach(SearchMode.allCases) { Text($0.rawValue).tag($0) }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .frame(width: compact ? nil : 210)
    }

    private func isScope(_ s: SearchScope) -> Bool { controller.scope == s }

    // MARK: pinned quick-access scope tab (beside the mode picker)

    private var pinnedIsFavorites: Bool {
        if case .group = controller.pinnedScope { return false }
        return true
    }
    private func isPinnedGroup(_ g: String) -> Bool {
        if case .group(let n) = controller.pinnedScope { return n == g }
        return false
    }
    private var pinnedActive: Bool { controller.scope == controller.pinnedScope }
    /// Rebind the tab to a scope and switch to it (that's the "easy access" bit).
    private func selectPinned(_ s: SearchScope) {
        controller.pinnedScope = s
        controller.scope = s
    }

    @ViewBuilder private var pinnedRebindMenu: some View {
        Button { selectPinned(.favorites) } label: {
            Label("Favorites", systemImage: pinnedIsFavorites ? "checkmark" : "star")
        }
        if !groups.groups.isEmpty {
            Divider()
            ForEach(groups.groups, id: \.self) { g in
                Button { selectPinned(.group(g)) } label: {
                    Label(g, systemImage: isPinnedGroup(g) ? "checkmark" : "tag")
                }
            }
        }
    }

    /// A single quick-access tab styled like a sibling of the mode picker: click
    /// toggles the pinned scope on/off, right-click rebinds it to a group.
    // Truncate a name (ellipsis included) so it never renders wider than the default
    // "Favorites" label. Width, not character count — 8 wide letters can out-measure
    // 9 narrow ones in a proportional font.
    private static let pinFont = NSFont.systemFont(ofSize: 12, weight: .semibold)
    private static func pinTextWidth(_ s: String) -> CGFloat {
        (s as NSString).size(withAttributes: [.font: pinFont]).width
    }
    private static let pinMaxWidth = pinTextWidth("Favorites")
    private static func fitPinLabel(_ s: String) -> String {
        guard pinTextWidth(s) > pinMaxWidth else { return s }
        var i = s.count
        while i > 1 {
            i -= 1
            let c = String(s.prefix(i)) + "…"
            if pinTextWidth(c) <= pinMaxWidth { return c }
        }
        return "…"
    }

    private var pinnedScopeTab: some View {
        let active = pinnedActive
        let full = pinnedIsFavorites ? "Favorites" : (controller.pinnedScope.groupName ?? "Favorites")
        let label = Self.fitPinLabel(full)   // never wider than the "Favorites" label
        let icon = pinnedIsFavorites ? "star.fill" : "tag.fill"
        return Button {
            controller.scope = active ? .all : controller.pinnedScope
        } label: {
            HStack(spacing: 4) {
                Image(systemName: icon).font(.system(size: 9, weight: .semibold))
                Text(label).font(.system(size: 12, weight: .semibold)).lineLimit(1)
            }
            .foregroundStyle(active ? AnyShapeStyle(.white) : AnyShapeStyle(.secondary))
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(active ? AnyShapeStyle(theme.theme.accent)
                                 : AnyShapeStyle(Color.primary.opacity(0.07))))
            .contentShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
        .buttonStyle(.plain)
        .contextMenu { pinnedRebindMenu }
        .fixedSize()
        .help("\(full) — click to toggle · right-click to change group")
    }

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
            Image(systemName: "line.3.horizontal.decrease.circle")
                .foregroundStyle(isScope(.all) ? AnyShapeStyle(.secondary) : AnyShapeStyle(theme.theme.accent))
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
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
                HStack(spacing: 10) { magnifier; searchFieldView; clearButton; settingsButton }
                HStack(spacing: 8) {
                    modePicker.frame(maxWidth: .infinity)
                    pinnedScopeTab; favoritesMenu; transformsButton; aiButton
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 16)
            .padding(.bottom, 10)
        } else {
            HStack(spacing: 12) {
                magnifier; searchFieldView; clearButton; modePicker
                pinnedScopeTab; favoritesMenu; transformsButton; aiButton; settingsButton
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
                        ResultRow(result: r, selected: idx == controller.selected, textWidth: rowTextWidth, bigImages: indexer.largeImages)
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

                                // Link clips: look up the page title on demand.
                                if (r.title ?? "").isEmpty, LinkTitle.url(in: r.text) != nil {
                                    Button {
                                        controller.fetchTitle(r)
                                    } label: { Label("Fetch page title", systemImage: "link") }
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
            // Measure the list width once (not per row) for the truncation check.
            .background(GeometryReader { g in
                Color.clear
                    .onAppear { rowTextWidth = max(40, g.size.width - 116) }
                    .onChange(of: g.size.width) { rowTextWidth = max(40, $0 - 116) }
            })
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

    /// Standard app locations searched by name (LaunchServices' name-based lookup
    /// is deprecated), newest macOS layout first.
    private static let appDirs = [
        "/Applications", "/Applications/Utilities",
        "/System/Applications", "/System/Applications/Utilities",
        NSHomeDirectory() + "/Applications",
    ]

    private static func bundleURL(named name: String) -> URL? {
        for dir in appDirs {
            let u = URL(fileURLWithPath: dir).appendingPathComponent(name + ".app")
            if FileManager.default.fileExists(atPath: u.path) { return u }
        }
        return nil
    }

    /// Map a recorded app name to its bundle URL. The recorded name is the app's
    /// *display* name, which can differ from its bundle filename (e.g. Copy 'Em
    /// stores "iTerm2" but the bundle on disk is "iTerm.app").
    private static func resolveURL(_ name: String) -> URL? {
        // 1. Bundle sitting at its standard filename (Safari, Google Chrome, …).
        if let u = bundleURL(named: name) { return u }
        // 2. A running app whose display name matches (handles iTerm2 → iTerm.app).
        if let u = NSWorkspace.shared.runningApplications.first(where: { $0.localizedName == name })?.bundleURL { return u }
        // 3. Strip a trailing version number from the name and retry (iTerm2 → iTerm).
        let stripped = name.replacingOccurrences(of: "\\s*\\d+$", with: "", options: .regularExpression)
        if stripped != name, !stripped.isEmpty, let u = bundleURL(named: stripped) { return u }
        return nil
    }
}

/// Per-row memoization so scrolling doesn't redo expensive work (disk thumbnail
/// loads, link detection, text measurement) on every SwiftUI redraw.
private enum RowCache {
    static var thumbs: [String: NSImage] = [:]
    static var links: [Int64: [NSRange]] = [:]
    static var lines: [String: Int] = [:]

    // This is a long-lived menu-bar agent, so the caches are bounded to keep memory
    // flat while browsing a large history. Thumbnails hold real bitmaps, so the cap
    // is tighter; a full flush is cheap since everything is recomputable from disk.
    private static let thumbCap = 400
    private static let textCap = 3000

    static func thumb(_ path: String) -> NSImage? {
        if let c = thumbs[path] { return c }
        guard let img = NSImage(contentsOfFile: path) else { return nil }
        if thumbs.count >= thumbCap { thumbs.removeAll(keepingCapacity: true) }
        thumbs[path] = img
        return img
    }

    static var fulls: [String: NSImage] = [:]
    private static let fullCap = 120
    /// Full-resolution image for the large-preview mode (cached; opt-in only).
    static func fullImage(_ path: String?) -> NSImage? {
        guard let path else { return nil }
        if let c = fulls[path] { return c }
        guard let img = NSImage(contentsOfFile: path) else { return nil }
        if fulls.count >= fullCap { fulls.removeAll(keepingCapacity: true) }
        fulls[path] = img
        return img
    }
    static func linkRanges(pk: Int64, text: String, detector: NSDataDetector?) -> [NSRange] {
        if let c = links[pk] { return c }
        let ns = text as NSString
        let r = detector?.matches(in: text, range: NSRange(location: 0, length: ns.length)).map(\.range) ?? []
        if links.count >= textCap { links.removeAll(keepingCapacity: true) }
        links[pk] = r
        return r
    }
    static func lineCount(pk: Int64, width: CGFloat, _ compute: () -> Int) -> Int {
        let key = "\(pk):\(Int(width))"
        if let c = lines[key] { return c }
        let n = compute()
        if lines.count >= textCap { lines.removeAll(keepingCapacity: true) }
        lines[key] = n
        return n
    }
}

private struct ResultRow: View {
    let result: SearchResult
    let selected: Bool
    var textWidth: CGFloat = 0     // measured once at the list level, not per row
    var bigImages: Bool = false    // large preview for image clips (opt-in)
    @Environment(\.appTheme) private var theme
    @State private var hovering = false
    @State private var expanded = false

    /// True only when the 2-line-limited preview is actually truncated.
    private var isExpandable: Bool {
        guard !result.isImage, textWidth > 1 else { return false }
        return RowCache.lineCount(pk: result.pk, width: textWidth) {
            Self.lineCount(of: preview, width: textWidth)
        } > 2
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

    /// A capped slice of the (possibly megabyte-sized) clip for display. We only
    /// ever show ~2 lines (or a modest expanded view), so rendering/measuring the
    /// full text is what made scrolling lag. The full text is still used on copy.
    private var preview: String {
        let cap = expanded ? 4000 : 320
        let head = result.text.prefix(cap + 1)        // O(cap), avoids counting the whole string
        let truncated = head.count > cap
        let body = String(truncated ? head.prefix(cap) : head)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return truncated ? body + "…" : body
    }

    private static let linkDetector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)

    /// The preview text with any URLs/links coloured blue and underlined.
    private var styledPreview: AttributedString {
        let s = preview
        var attr = AttributedString(s)
        let ranges = RowCache.linkRanges(pk: result.pk, text: s, detector: Self.linkDetector)
        guard !ranges.isEmpty else { return attr }   // common case: no URLs
        let linkColor = selected ? Color.white : Color(red: 0.30, green: 0.55, blue: 1.0)
        for nsr in ranges {
            guard let r = Range(nsr, in: s) else { continue }
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

    private var hasTitle: Bool { !(result.title ?? "").isEmpty }

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
            let nsimg = result.thumbPath.flatMap { RowCache.thumb($0) }
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
        content
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(selected
                          ? AnyShapeStyle(LinearGradient(colors: theme.selectionGradient, startPoint: .top, endPoint: .bottom))
                          : (hovering ? AnyShapeStyle(Color.primary.opacity(0.07)) : AnyShapeStyle(Color.clear)))
            )
            .overlay(selected
                     ? RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(.white.opacity(0.18), lineWidth: 0.5)
                     : nil)
            .shadow(color: selected ? theme.glow : .clear, radius: 6, y: 2)
            .padding(.horizontal, 8)
            .onHover { hovering = $0 }
    }

    @ViewBuilder private var content: some View {
        if bigImages, result.isImage {
            bigImageRow
        } else {
            standardRow
        }
    }

    private var bigImageRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let img = RowCache.fullImage(result.imagePath) {
                Image(nsImage: img).resizable().aspectRatio(contentMode: .fit)
                    .frame(maxWidth: .infinity)
                    .frame(maxHeight: 240)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(.white.opacity(0.15), lineWidth: 0.5))
            } else {
                leading   // fall back to the thumbnail if the full image is missing
            }
            HStack(spacing: 8) {
                if result.favorite {
                    Image(systemName: "star.fill").font(.system(size: 11))
                        .foregroundStyle(selected ? AnyShapeStyle(.white) : AnyShapeStyle(.yellow))
                }
                if !meta.isEmpty {
                    Text(meta).font(.caption2)
                        .foregroundStyle(selected ? Color.white.opacity(0.85) : Color.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var standardRow: some View {
        HStack(alignment: .top, spacing: 11) {
            leading
            VStack(alignment: .leading, spacing: 3) {
                // Link clips show the page title as a chip above the URL.
                if let t = result.title, !t.isEmpty {
                    HStack(spacing: 5) {
                        Image(systemName: "globe")
                            .font(.system(size: 9, weight: .semibold))
                        Text(t)
                            .font(.system(size: 12, weight: .medium))
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                    .foregroundStyle(selected ? AnyShapeStyle(.white) : AnyShapeStyle(theme.accent))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(selected ? Color.white.opacity(0.18) : theme.accent.opacity(0.12))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .strokeBorder(selected ? Color.white.opacity(0.28) : theme.accent.opacity(0.28),
                                          lineWidth: 0.5)
                    )
                    .padding(.bottom, 1)
                }
                Text(styledPreview)
                    .lineLimit(expanded ? nil : 2)
                    .font(.system(size: hasTitle ? 11 : 13))
                    .foregroundStyle(selected ? Color.white.opacity(hasTitle ? 0.8 : 1)
                                              : (hasTitle ? Color.secondary : Color.primary))
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
    }

    /// Deterministic, pleasant color per source app.
    static func color(for s: String) -> Color {
        var h = 5381
        for u in s.unicodeScalars { h = ((h << 5) &+ h) &+ Int(u.value) }
        let hue = Double((h % 360 + 360) % 360) / 360.0
        return Color(hue: hue, saturation: 0.55, brightness: 0.72)
    }
}

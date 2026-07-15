import AppKit
import Combine

/// Drives searching for the panel: debounced queries, cancellation of superseded
/// searches, selection state, and copy-to-clipboard.
final class SearchController: ObservableObject {
    @Published var query = ""
    @Published var mode: SearchMode = .substring
    @Published private(set) var results: [SearchResult] = []
    @Published var selected = 0
    @Published private(set) var status = ""
    @Published private(set) var searching = false
    @Published private(set) var hasMore = false
    @Published var scope: SearchScope = .all
    /// One-click quick-access scope shown as a tab beside the mode picker. Defaults
    /// to Favorites; the user can rebind it to any group. Persisted across launches.
    @Published var pinnedScope: SearchScope = .favorites { didSet { Self.persistPinned(pinnedScope) } }

    let sourcePath: String
    let transforms: TransformSettings
    let ai: AISettings
    let theme: ThemeSettings
    let groups: GroupSettings
    private weak var indexer: Indexer?

    private let searchQueue = DispatchQueue(label: "com.local.stash.search")
    private var engine: SearchEngine?
    private var generation = 0
    private var loadingMore = false
    private var lastWasRecent = false
    private var invalidRegex = false
    private var firstPageMS: Double = 0
    private let lock = NSLock()

    init(sourcePath: String, indexer: Indexer? = nil,
         transforms: TransformSettings = TransformSettings(),
         ai: AISettings = AISettings(),
         theme: ThemeSettings = ThemeSettings(),
         groups: GroupSettings = GroupSettings()) {
        self.sourcePath = sourcePath
        self.indexer = indexer
        self.transforms = transforms
        self.ai = ai
        self.theme = theme
        self.groups = groups
        self.pinnedScope = Self.loadPinned()   // set directly so didSet doesn't re-persist
    }

    // MARK: pinned scope persistence

    private static let pinnedKey = "pinnedScope"
    private static func persistPinned(_ s: SearchScope) {
        // Only Favorites or a group is ever pinned; `.all` is the "off" state.
        let v: String = { if case .group(let g) = s { return "g:" + g } else { return "*fav*" } }()
        UserDefaults.standard.set(v, forKey: pinnedKey)
    }
    private static func loadPinned() -> SearchScope {
        guard let v = UserDefaults.standard.string(forKey: pinnedKey) else { return .favorites }
        return v.hasPrefix("g:") ? .group(String(v.dropFirst(2))) : .favorites
    }

    /// Run the current query from the top (or show recent items when it's empty).
    /// Cancels any in-flight search.
    func runSearch() {
        lock.lock(); generation += 1; let gen = generation; lock.unlock()
        results = []; selected = 0; hasMore = false; loadingMore = false
        searching = true
        loadPage(offset: 0, replace: true, gen: gen, start: Date())
    }

    /// Load and append the next page (triggered by scrolling/arrowing near the end).
    func loadMore() {
        guard hasMore, !loadingMore, !searching else { return }
        lock.lock(); let gen = generation; lock.unlock()
        loadingMore = true
        loadPage(offset: results.count, replace: false, gen: gen, start: Date())
    }

    private func loadPage(offset: Int, replace: Bool, gen: Int, start: Date) {
        let q = query
        let m = mode
        let sc = scope
        let recent = q.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        // Flag an uncompilable regex so an empty result reads as "bad pattern" rather
        // than a genuine miss (the engine also returns [] on a compile failure).
        if m == .regex, !recent {
            let pattern = q.trimmingCharacters(in: .whitespacesAndNewlines)
            invalidRegex = (try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive])) == nil
        } else {
            invalidRegex = false
        }
        searchQueue.async { [weak self] in
            guard let self else { return }
            if self.engine == nil { self.engine = try? SearchEngine() }
            guard let engine = self.engine else {
                DispatchQueue.main.async {
                    if self.isCurrent(gen) { self.status = "Index not ready yet"; self.searching = false; self.loadingMore = false }
                }
                return
            }
            let page = recent
                ? engine.recent(offset: offset, limit: SearchEngine.pageSize, scope: sc)
                : engine.search(q, mode: m, offset: offset,
                                limit: SearchEngine.pageSize, scope: sc,
                                isCancelled: { !self.isCurrent(gen) })
            guard self.isCurrent(gen) else { return }
            let ms = Date().timeIntervalSince(start) * 1000
            DispatchQueue.main.async {
                guard self.isCurrent(gen) else { return }
                self.lastWasRecent = recent
                if replace { self.results = page; self.selected = 0; self.firstPageMS = ms }
                else { self.results.append(contentsOf: page) }
                self.hasMore = page.count == SearchEngine.pageSize
                self.searching = false
                self.loadingMore = false
                self.updateStatus()
            }
        }
    }

    private func updateStatus() {
        let n = results.count
        if n == 0 {
            if invalidRegex { status = "Invalid regex pattern"; return }
            switch scope {
            case .favorites:    status = lastWasRecent ? "No favorites yet" : "No matching favorites"
            case .group(let g): status = lastWasRecent ? "“\(g)” is empty" : "No matches in “\(g)”"
            case .all:          status = lastWasRecent ? "" : "No matches"
            }
            return
        }
        if lastWasRecent {
            let label: String
            switch scope {
            case .favorites:    label = "favorites"
            case .group(let g): label = "in “\(g)”"
            case .all:          label = "items"
            }
            status = hasMore ? "Latest \(n) \(label) (scroll for more)"
                             : "\(n) \(label) — newest first"
        } else {
            let noun = n == 1 ? "result" : "results"
            let shown = hasMore ? "\(n)+ \(noun) (scroll for more)" : "\(n) \(noun)"
            status = "\(shown) · \(String(format: "%.0f", firstPageMS)) ms"
        }
    }

    private func isCurrent(_ gen: Int) -> Bool {
        lock.lock(); defer { lock.unlock() }; return gen == generation
    }

    /// Clear everything so the next time the panel opens it starts blank.
    func reset() {
        lock.lock(); generation += 1; lock.unlock()   // cancel any in-flight search
        query = ""
        results = []
        selected = 0
        status = ""
        searching = false
        hasMore = false
        loadingMore = false
        scope = .all
    }

    // MARK: favorite / delete

    private func withFavorite(_ r: SearchResult, _ f: Bool) -> SearchResult {
        SearchResult(pk: r.pk, text: r.text, app: r.app, list: r.list, created: r.created,
                     useCount: r.useCount, source: r.source, sourcePk: r.sourcePk, favorite: f,
                     kind: r.kind, imgW: r.imgW, imgH: r.imgH, ext: r.ext)
    }

    private func withList(_ r: SearchResult, _ list: String?) -> SearchResult {
        SearchResult(pk: r.pk, text: r.text, app: r.app, list: list, created: r.created,
                     useCount: r.useCount, source: r.source, sourcePk: r.sourcePk, favorite: r.favorite,
                     kind: r.kind, imgW: r.imgW, imgH: r.imgH, ext: r.ext)
    }

    func toggleFavorite(_ r: SearchResult) {
        let newVal = !r.favorite
        if let i = results.firstIndex(where: { $0.pk == r.pk }) {
            if scope == .favorites && !newVal {     // unfavoriting while viewing favorites → drop it
                results.remove(at: i)
                if selected >= results.count { selected = max(0, results.count - 1) }
            } else {
                results[i] = withFavorite(results[i], newVal)
            }
        }
        indexer?.setFavorite(pk: r.pk, newVal) {}
        updateStatus()
    }

    /// Add an entry to a named group (or remove it from its group with nil).
    func assignGroup(_ r: SearchResult, to name: String?) {
        if let name { groups.add(name) }
        indexer?.setGroup(pk: r.pk, name)
        if let i = results.firstIndex(where: { $0.pk == r.pk }) {
            // If we're viewing a group and the entry no longer belongs, drop it.
            if case .group(let g) = scope,
               name?.caseInsensitiveCompare(g) != .orderedSame {
                results.remove(at: i)
                if selected >= results.count { selected = max(0, results.count - 1) }
            } else {
                results[i] = withList(results[i], name)
            }
        }
        updateStatus()
    }

    /// Pull group names that exist in the database into the persisted list.
    func refreshGroups() {
        indexer?.fetchGroups { [weak self] names in self?.groups.merge(names) }
    }

    func delete(_ r: SearchResult) {
        if let i = results.firstIndex(where: { $0.pk == r.pk }) {
            results.remove(at: i)
            if selected >= results.count { selected = max(0, results.count - 1) }
        }
        indexer?.deleteEntry(pk: r.pk) {}
        // Remove the image files backing an image clip.
        if r.isImage {
            for p in [r.imagePath, r.thumbPath].compactMap({ $0 }) {
                try? FileManager.default.removeItem(atPath: p)
            }
        }
        updateStatus()
    }

    // MARK: selection

    func moveDown() {
        guard !results.isEmpty else { return }
        selected = min(selected + 1, results.count - 1)
        if selected >= results.count - 5 { loadMore() }   // prefetch as we near the end
    }
    func moveUp() { guard !results.isEmpty else { return }; selected = max(selected - 1, 0) }

    // MARK: copy

    /// Copy the selected entry's FULL text to the clipboard, then call `done`.
    func copySelected(done: @escaping () -> Void) {
        guard results.indices.contains(selected) else { done(); return }
        let r = results[selected]

        // Image clips: put the image back on the clipboard (transforms don't apply).
        if r.isImage {
            let pb = NSPasteboard.general
            pb.clearContents()
            if let path = r.imagePath, let img = NSImage(contentsOfFile: path) {
                pb.writeObjects([img])
            }
            indexer?.ignoreClipboardChange()
            done()
            return
        }

        searchQueue.async { [weak self] in
            // Apply the user's copy transformations (upper/lower/trim/prepend…).
            let text = self?.transforms.apply(to: r.text) ?? r.text
            DispatchQueue.main.async {
                let pb = NSPasteboard.general
                pb.clearContents()
                pb.setString(text, forType: .string)
                self?.indexer?.ignoreClipboardChange()
                done()
            }
        }
    }
}

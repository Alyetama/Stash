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

    let sourcePath: String

    private let searchQueue = DispatchQueue(label: "com.local.stash.search")
    private var engine: SearchEngine?
    private var generation = 0
    private var loadingMore = false
    private var lastWasRecent = false
    private var firstPageMS: Double = 0
    private let lock = NSLock()

    init(sourcePath: String) { self.sourcePath = sourcePath }

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
        let recent = q.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
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
                ? engine.recent(offset: offset, limit: SearchEngine.pageSize)
                : engine.search(q, mode: m, offset: offset,
                                limit: SearchEngine.pageSize,
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
            status = lastWasRecent ? "" : "No matches"
            return
        }
        if lastWasRecent {
            status = hasMore ? "Latest \(n) — newest first (scroll for more)"
                             : "\(n) items — newest first"
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
        searchQueue.async { [weak self] in
            var text = r.text
            // Copy 'Em imports store only a capped copy — fetch the full text from
            // Copy 'Em on demand. Self-captured clips already hold their full text.
            if let self, r.source == "copyem", let sourcePk = r.sourcePk,
               let src = try? SourceStore(path: self.sourcePath),
               let full = try? src.fullText(pk: sourcePk) {
                text = full
            }
            DispatchQueue.main.async {
                let pb = NSPasteboard.general
                pb.clearContents()
                pb.setString(text, forType: .string)
                done()
            }
        }
    }
}

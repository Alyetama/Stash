import Foundation
import Combine

/// Manages the clipboard-history database: captures new clips live, performs a
/// one-time historical import from Copy 'Em when present, and publishes status.
/// All DB writes run on a private serial queue; @Published state updates on main.
final class Indexer: ObservableObject {
    enum Phase: Equatable { case starting, importing, ready, error }

    @Published private(set) var phase: Phase = .starting
    @Published private(set) var indexedCount: Int = 0
    @Published private(set) var buildTotal: Int = 0
    @Published private(set) var buildDone: Int = 0
    @Published private(set) var lastSync: Date?
    @Published private(set) var message: String = "Starting…"
    @Published private(set) var copyEmAvailable = false

    let sourcePath: String

    private let queue = DispatchQueue(label: "com.local.stash.store")
    private var sidecar: SidecarDB?
    private var monitor: ClipboardMonitor?
    private let commitBatch = 5000

    init(sourcePath: String = SourceStore.defaultPath) {
        self.sourcePath = sourcePath
    }

    func start() {
        queue.async { [weak self] in self?.bootstrap() }
    }

    // MARK: - lifecycle

    private func bootstrap() {
        do {
            let sc = try sidecarHandle()
            let count = Int(try sc.count())
            let hasCopyEm = SourceStore.exists(at: sourcePath)
            publish {
                self.indexedCount = count
                self.copyEmAvailable = hasCopyEm
                self.phase = .ready
                self.message = "Ready"
            }

            // One-time historical import from Copy 'Em (only if present & not done).
            let alreadyImported = (try? sc.getMeta("copyem_imported")) == "1"
            if hasCopyEm && !alreadyImported {
                try importFromCopyEm(sc, initial: true)
            }
        } catch {
            fail(error)
        }
        startMonitor()
    }

    private func sidecarHandle() throws -> SidecarDB {
        if let sidecar { return sidecar }
        let sc = try SidecarDB()
        sidecar = sc
        return sc
    }

    // MARK: - live clipboard capture

    private func startMonitor() {
        DispatchQueue.main.async { [weak self] in
            guard let self, self.monitor == nil else { return }
            let m = ClipboardMonitor { [weak self] text, app in
                self?.recordClip(text: text, app: app)
            }
            m.start()
            self.monitor = m
        }
    }

    private func recordClip(text: String, app: String?) {
        queue.async { [weak self] in
            guard let self, let sc = self.sidecar else { return }
            guard let inserted = try? sc.insertClip(text: text, app: app), inserted else { return }
            self.publish {
                self.indexedCount += 1
                self.lastSync = Date()
            }
        }
    }

    // MARK: - Copy 'Em historical import (optional)

    /// Pull entries from Copy 'Em that we haven't imported yet (idempotent via
    /// last_copyem_pk). `initial` shows the building UI for the first big import.
    func importFromCopyEm() {
        queue.async { [weak self] in
            guard let self, let sc = self.sidecar else { return }
            do { try self.importFromCopyEm(sc, initial: false) } catch { self.fail(error) }
        }
    }

    private func importFromCopyEm(_ sc: SidecarDB, initial: Bool) throws {
        guard SourceStore.exists(at: sourcePath) else { return }
        let source = try SourceStore(path: sourcePath)
        let lastPK = Int64(try sc.getMeta("last_copyem_pk") ?? "0") ?? 0

        if initial {
            let total = Int(try source.liveCount())
            publish {
                self.phase = .importing
                self.buildTotal = total
                self.buildDone = 0
                self.message = "Importing \(total.formatted()) entries from Copy 'Em…"
            }
        }

        var inBatch = 0, added = 0
        var maxPK = lastPK
        try sc.begin()
        try source.forEachRow(afterPK: lastPK) { row in
            do { try sc.insertImported(row) } catch { return }
            if row.pk > maxPK { maxPK = row.pk }
            inBatch += 1; added += 1
            if inBatch >= self.commitBatch {
                try? sc.commit(); try? sc.begin()
                inBatch = 0
                let snapshot = added
                self.publish { self.buildDone = snapshot; self.indexedCount = Int((try? sc.count()) ?? 0) }
            }
        }
        try sc.commit()
        try sc.setMeta("last_copyem_pk", String(maxPK))
        try sc.setMeta("copyem_imported", "1")

        let count = Int(try sc.count())
        publish {
            self.indexedCount = count
            self.buildDone = count
            self.phase = .ready
            self.lastSync = Date()
            self.message = "Ready"
        }
    }

    // MARK: - helpers

    private func fail(_ error: Error) {
        publish {
            self.phase = .error
            self.message = "Error: \(error)"
        }
    }

    private func publish(_ work: @escaping () -> Void) {
        DispatchQueue.main.async(execute: work)
    }
}

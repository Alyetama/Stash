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
    @Published var capturePaused: Bool { didSet { UserDefaults.standard.set(capturePaused, forKey: "capturePaused") } }

    let sourcePath: String

    private let queue = DispatchQueue(label: "com.local.stash.store")
    private var sidecar: SidecarDB?
    private var monitor: ClipboardMonitor?
    private let commitBatch = 5000

    init(sourcePath: String = SourceStore.defaultPath) {
        self.sourcePath = sourcePath
        self.capturePaused = UserDefaults.standard.bool(forKey: "capturePaused")
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
            // One-time backfill of historical IMAGE clips from Copy 'Em.
            let imagesDone = (try? sc.getMeta("copyem_images_imported")) == "1"
            if hasCopyEm && !imagesDone {
                try importCopyEmImages(sc)
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
            let m = ClipboardMonitor(
                onText: { [weak self] text, app in self?.recordClip(text: text, app: app) },
                onImage: { [weak self] data, ext, app in self?.recordImage(data: data, ext: ext, app: app) })
            m.start()
            self.monitor = m
        }
    }

    /// Called after we put something on the clipboard ourselves, so the monitor
    /// doesn't re-record it as a new clip.
    func ignoreClipboardChange() {
        DispatchQueue.main.async { [weak self] in self?.monitor?.markCurrentAsSeen() }
    }

    private func recordClip(text: String, app: String?) {
        queue.async { [weak self] in
            guard let self, let sc = self.sidecar, !self.capturePaused else { return }
            guard let inserted = try? sc.insertClip(text: text, app: app), inserted else { return }
            self.publish {
                self.indexedCount += 1
                self.lastSync = Date()
            }
        }
    }

    private func recordImage(data: Data, ext: String, app: String?) {
        queue.async { [weak self] in
            guard let self, let sc = self.sidecar, !self.capturePaused else { return }
            guard let thumb = ImageThumb.make(from: data, maxPixel: 96) else { return }
            let label = "Image · \(thumb.w)×\(thumb.h)"
            guard let pk = try? sc.insertImage(label: label, app: app, w: thumb.w, h: thumb.h, ext: ext)
            else { return }
            try? FileManager.default.createDirectory(atPath: Sidecar.imagesDir, withIntermediateDirectories: true)
            try? data.write(to: URL(fileURLWithPath: Sidecar.imageFile(pk: pk, ext: ext)))
            try? thumb.png.write(to: URL(fileURLWithPath: Sidecar.thumbFile(pk: pk)))
            self.publish {
                self.indexedCount += 1
                self.lastSync = Date()
            }
        }
    }

    // MARK: - Import a Copy 'Em .cep export (user-chosen file)

    /// Import every text + image entry from a Copy 'Em store at `storePath`
    /// (the `Copy-em-Paste.storedata` inside a chosen `.cep` package). Explicit,
    /// appends, not gated by the one-time flags. Calls back on the main thread.
    func importFromStore(_ storePath: String, completion: @escaping (Result<Int, Error>) -> Void) {
        queue.async { [weak self] in
            func done(_ r: Result<Int, Error>) { DispatchQueue.main.async { completion(r) } }
            guard let self, let sc = self.sidecar else { return }
            func fail(_ m: String) {
                done(.failure(NSError(domain: "Stash", code: 1, userInfo: [NSLocalizedDescriptionKey: m])))
            }
            guard SourceStore.exists(at: storePath),
                  let source = try? SourceStore(path: storePath) else {
                return fail("No Copy 'Em data found in that file.")
            }
            do {
                let total = Int((try? source.liveCount()) ?? 0)
                self.publish {
                    self.phase = .importing
                    self.buildTotal = max(total, 1)
                    self.buildDone = 0
                    self.message = "Importing \(total.formatted()) entries…"
                }
                // Text entries.
                var inBatch = 0, added = 0
                try sc.begin()
                try source.forEachRow(afterPK: 0) { row in
                    do { try sc.insertImported(row) } catch { return }
                    inBatch += 1; added += 1
                    if inBatch >= self.commitBatch {
                        try? sc.commit(); try? sc.begin(); inBatch = 0
                        let d = added; self.publish { self.buildDone = d; self.indexedCount = Int((try? sc.count()) ?? 0) }
                    }
                }
                try sc.commit()
                // Image entries.
                try? FileManager.default.createDirectory(atPath: Sidecar.imagesDir, withIntermediateDirectories: true)
                try source.forEachImageEntry { cand in
                    guard let (data, ext) = CopyEmImage.extractLargest(from: cand.blob),
                          let thumb = ImageThumb.make(from: data, maxPixel: 96) else { return }
                    let label = "Image · \(thumb.w)×\(thumb.h)"
                    let when = cand.created > 0 ? Date(timeIntervalSince1970: cand.created) : Date()
                    guard let pk = try? sc.insertImage(label: label, app: cand.app, w: thumb.w, h: thumb.h,
                                                       ext: ext, source: "copyem", at: when) else { return }
                    try? data.write(to: URL(fileURLWithPath: Sidecar.imageFile(pk: pk, ext: ext)))
                    try? thumb.png.write(to: URL(fileURLWithPath: Sidecar.thumbFile(pk: pk)))
                    added += 1
                }
                let count = Int(try sc.count())
                self.publish {
                    self.indexedCount = count; self.buildDone = self.buildTotal
                    self.phase = .ready; self.lastSync = Date(); self.message = "Ready"
                }
                done(.success(added))
            } catch {
                self.publish { self.phase = .ready; self.message = "Ready" }
                done(.failure(error))
            }
        }
    }

    // MARK: - Copy 'Em historical import (live store, optional/auto)

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

    // MARK: - Copy 'Em image backfill (optional, one-time)

    func importCopyEmImages() {
        queue.async { [weak self] in
            guard let self, let sc = self.sidecar else { return }
            do { try self.importCopyEmImages(sc) } catch { self.fail(error) }
        }
    }

    private func importCopyEmImages(_ sc: SidecarDB) throws {
        guard SourceStore.exists(at: sourcePath) else { return }
        let source = try SourceStore(path: sourcePath)
        let total = Int(try source.imageEntryCount())
        guard total > 0 else { try sc.setMeta("copyem_images_imported", "1"); return }

        publish {
            self.phase = .importing
            self.buildTotal = total
            self.buildDone = 0
            self.message = "Importing \(total.formatted()) images from Copy 'Em…"
        }
        try? FileManager.default.createDirectory(atPath: Sidecar.imagesDir, withIntermediateDirectories: true)

        var done = 0
        try source.forEachImageEntry { cand in
            done += 1
            if done % 50 == 0 {
                let d = done, c = Int((try? sc.count()) ?? 0)
                self.publish { self.buildDone = d; self.indexedCount = c }
            }
            guard let (data, ext) = CopyEmImage.extractLargest(from: cand.blob),
                  let thumb = ImageThumb.make(from: data, maxPixel: 96) else { return }
            let label = "Image · \(thumb.w)×\(thumb.h)"
            let when = cand.created > 0 ? Date(timeIntervalSince1970: cand.created) : Date()
            guard let pk = try? sc.insertImage(label: label, app: cand.app, w: thumb.w, h: thumb.h,
                                               ext: ext, source: "copyem", at: when) else { return }
            try? data.write(to: URL(fileURLWithPath: Sidecar.imageFile(pk: pk, ext: ext)))
            try? thumb.png.write(to: URL(fileURLWithPath: Sidecar.thumbFile(pk: pk)))
        }

        try sc.setMeta("copyem_images_imported", "1")
        let count = Int(try sc.count())
        publish {
            self.indexedCount = count
            self.buildDone = total
            self.phase = .ready
            self.lastSync = Date()
            self.message = "Ready"
        }
    }

    // MARK: - edits (delete / favorite)

    func deleteEntry(pk: Int64, completion: @escaping () -> Void) {
        queue.async { [weak self] in
            guard let self, let sc = self.sidecar else { return }
            try? sc.delete(pk: pk)
            let count = Int((try? sc.count()) ?? 0)
            self.publish { self.indexedCount = count }
            DispatchQueue.main.async(execute: completion)
        }
    }

    func setFavorite(pk: Int64, _ on: Bool, completion: @escaping () -> Void) {
        queue.async { [weak self] in
            guard let self, let sc = self.sidecar else { return }
            try? sc.setFavorite(pk: pk, on)
            DispatchQueue.main.async(execute: completion)
        }
    }

    // MARK: - export

    /// Export the whole clipboard history to a standalone SQLite database at `url`
    /// (a clean `clips` table — no FTS internals). Calls back on the main thread.
    func export(to url: URL, completion: @escaping (Result<Int, Error>) -> Void) {
        queue.async { [weak self] in
            func done(_ r: Result<Int, Error>) { DispatchQueue.main.async { completion(r) } }
            guard let self, let sc = self.sidecar else {
                done(.failure(NSError(domain: "Stash", code: 1,
                    userInfo: [NSLocalizedDescriptionKey: "History isn't ready yet."])))
                return
            }
            do {
                try? FileManager.default.removeItem(at: url)
                let escaped = url.path.replacingOccurrences(of: "'", with: "''")
                try sc.db.exec("ATTACH DATABASE '\(escaped)' AS exp;")
                do {
                    try sc.db.exec("""
                        CREATE TABLE exp.clips(
                            id           INTEGER PRIMARY KEY,
                            text         TEXT,
                            app          TEXT,
                            list         TEXT,
                            created_unix REAL,
                            created_iso  TEXT,
                            usecount     INTEGER,
                            source       TEXT
                        );
                        INSERT INTO exp.clips(id, text, app, list, created_unix, created_iso, usecount, source)
                        SELECT pk, text, app, list, created,
                               datetime(created, 'unixepoch'), usecount, source
                        FROM entries ORDER BY created;
                    """)
                    let n = Int(try sc.db.scalarInt("SELECT COUNT(*) FROM exp.clips") ?? 0)
                    try sc.db.exec("DETACH DATABASE exp;")
                    done(.success(n))
                } catch {
                    try? sc.db.exec("DETACH DATABASE exp;")
                    throw error
                }
            } catch {
                done(.failure(error))
            }
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

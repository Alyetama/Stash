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
    @Published private(set) var message: String = "Starting…"
    @Published var capturePaused: Bool { didSet { UserDefaults.standard.set(capturePaused, forKey: "capturePaused") } }
    @Published var keepDuplicates: Bool { didSet { UserDefaults.standard.set(keepDuplicates, forKey: "keepDuplicates") } }

    let sourcePath: String

    private let queue = DispatchQueue(label: "com.local.stash.store")
    private var sidecar: SidecarDB?
    private var monitor: ClipboardMonitor?
    private let commitBatch = 5000

    init(sourcePath: String = SourceStore.defaultPath) {
        self.sourcePath = sourcePath
        self.capturePaused = UserDefaults.standard.bool(forKey: "capturePaused")
        self.keepDuplicates = UserDefaults.standard.bool(forKey: "keepDuplicates")
    }

    func start() {
        queue.async { [weak self] in self?.bootstrap() }
    }

    // MARK: - lifecycle

    private func bootstrap() {
        do {
            let sc = try sidecarHandle()
            let count = Int(try sc.count())
            publish {
                self.indexedCount = count
                self.phase = .ready
                self.message = "Ready"
            }
            backfillHashesIfNeeded(sc)
        } catch {
            fail(error)
        }
        startMonitor()
    }

    /// One-time: populate the content `hash` column for entries created before the
    /// column existed (e.g. an earlier import), so move-to-top dedup works on them.
    private func backfillHashesIfNeeded(_ sc: SidecarDB) {
        guard (try? sc.getMeta("hash_backfilled")) != "1" else { return }
        var updates: [(Int64, Int64)] = []
        if let s = try? sc.db.prepare("SELECT pk, text, kind, ext FROM entries WHERE hash = 0") {
            while (try? s.step()) == true {
                let pk = s.int(0)
                var uh: UInt64 = 0
                if s.string(2) == "image" {
                    let ext = s.string(3) ?? "png"
                    if let d = try? Data(contentsOf: URL(fileURLWithPath: Sidecar.imageFile(pk: pk, ext: ext))) { uh = Self.fnv1a(d) }
                } else if let t = s.string(1) {
                    uh = Self.fnv1a(t)
                }
                updates.append((pk, Int64(bitPattern: uh)))
            }
            s.finalize()
        }
        guard !updates.isEmpty, let upd = try? sc.db.prepare("UPDATE entries SET hash = ? WHERE pk = ?") else {
            try? sc.setMeta("hash_backfilled", "1"); return
        }
        try? sc.begin()
        for (i, u) in updates.enumerated() {
            upd.reset(); upd.bind(1, u.1); upd.bind(2, u.0); try? upd.step()
            if i % 5000 == 4999 { try? sc.commit(); try? sc.begin() }
        }
        try? sc.commit()
        upd.finalize()
        try? sc.setMeta("hash_backfilled", "1")
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
            let capped = text.count > SidecarDB.clipTextCap ? String(text.prefix(SidecarDB.clipTextCap)) : text
            let hash = Int64(bitPattern: Self.fnv1a(capped))
            // Ignore duplicates unless the user opted to keep them: just bump the
            // existing entry to the top (no new row).
            if !self.keepDuplicates, let pk = sc.findEntry(hash: hash, kind: "text", text: capped) {
                sc.bumpToTop(pk: pk)
                return
            }
            guard (try? sc.insertClip(text: capped, app: app, hash: hash)) != nil else { return }
            self.publish { self.indexedCount += 1 }
        }
    }

    private func recordImage(data: Data, ext: String, app: String?) {
        queue.async { [weak self] in
            guard let self, let sc = self.sidecar, !self.capturePaused else { return }
            let hash = Int64(bitPattern: Self.fnv1a(data))
            if !self.keepDuplicates, let pk = sc.findEntry(hash: hash, kind: "image", text: nil) {
                sc.bumpToTop(pk: pk)
                return
            }
            guard let thumb = ImageThumb.make(from: data, maxPixel: 96) else { return }
            let label = "\(Self.formatLabel(ext)) · \(thumb.w)×\(thumb.h)"
            guard let pk = try? sc.insertImage(label: label, app: app, w: thumb.w, h: thumb.h, ext: ext, hash: hash)
            else { return }
            try? FileManager.default.createDirectory(atPath: Sidecar.imagesDir, withIntermediateDirectories: true)
            try? data.write(to: URL(fileURLWithPath: Sidecar.imageFile(pk: pk, ext: ext)))
            try? thumb.png.write(to: URL(fileURLWithPath: Sidecar.thumbFile(pk: pk)))
            self.publish { self.indexedCount += 1 }
        }
    }

    // MARK: - Import a Copy 'Em .cep export (user-chosen file)

    /// Import every text + image entry from a Copy 'Em store at `storePath`
    /// (the `Copy-em-Paste.storedata` inside a chosen `.cep` package). Explicit,
    /// appends, not gated by the one-time flags. Calls back on the main thread.
    struct ImportResult { var added = 0; var upgraded = 0 }

    func importFromStore(_ storePath: String, keepDuplicates: Bool = false,
                         completion: @escaping (Result<ImportResult, Error>) -> Void) {
        queue.async { [weak self] in
            func done(_ r: Result<ImportResult, Error>) { DispatchQueue.main.async { completion(r) } }
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

                // Content-hash sets of what's already in Stash (to skip duplicates),
                // plus a map of previously-truncated imports so re-import upgrades
                // them to full text instead of adding a second copy.
                let legacyCap = SourceStore.legacyTextCap
                var seenText = Set<UInt64>()
                var seenImage = Set<UInt64>()
                var truncated = [UInt64: Int64]()   // hash(text) -> pk for capped 'copyem' rows
                // When keeping duplicates we insert everything, so skip building the
                // (expensive) sets of existing content.
                if !keepDuplicates, let s = try? sc.db.prepare("SELECT text, kind, pk, ext, source FROM entries") {
                    while (try? s.step()) == true {
                        if s.string(1) == "image" {
                            let pk = s.int(2), ext = s.string(3) ?? "png"
                            if let d = try? Data(contentsOf: URL(fileURLWithPath: Sidecar.imageFile(pk: pk, ext: ext))) {
                                seenImage.insert(Self.fnv1a(d))
                            }
                        } else if let t = s.string(0) {
                            let h = Self.fnv1a(t)
                            seenText.insert(h)
                            if s.string(4) == "copyem", t.count == legacyCap { truncated[h] = s.int(2) }
                        }
                    }
                    s.finalize()
                }

                // Text entries — skip exact duplicates; upgrade truncated ones to full.
                var inBatch = 0, added = 0, upgraded = 0
                try sc.begin()
                try source.forEachRow(afterPK: 0) { row in
                    let uh = Self.fnv1a(row.text)
                    if !keepDuplicates {
                        if seenText.contains(uh) { return }   // already have this exact content
                        if row.text.count > legacyCap {
                            let ph = Self.fnv1a(String(row.text.prefix(legacyCap)))
                            if let oldPk = truncated[ph] {   // an earlier 16 KB-capped copy → replace it
                                try? sc.delete(pk: oldPk)
                                truncated[ph] = nil
                                seenText.remove(ph)
                                upgraded += 1
                            }
                        }
                        seenText.insert(uh)
                    }
                    do { try sc.insertImported(row, hash: Int64(bitPattern: uh)) } catch { return }
                    inBatch += 1; added += 1
                    if inBatch >= self.commitBatch {
                        try? sc.commit(); try? sc.begin(); inBatch = 0
                        let d = added; self.publish { self.buildDone = d; self.indexedCount = Int((try? sc.count()) ?? 0) }
                    }
                }
                try sc.commit()
                // Image entries — skip ones with identical image data.
                try? FileManager.default.createDirectory(atPath: Sidecar.imagesDir, withIntermediateDirectories: true)
                try source.forEachImageEntry { cand in
                    guard let (data, ext) = CopyEmImage.extractLargest(from: cand.blob) else { return }
                    let h = Self.fnv1a(data)
                    if !keepDuplicates && seenImage.contains(h) { return }
                    guard let thumb = ImageThumb.make(from: data, maxPixel: 96) else { return }
                    let label = "\(Self.formatLabel(ext)) · \(thumb.w)×\(thumb.h)"
                    let when = cand.created > 0 ? Date(timeIntervalSince1970: cand.created) : Date()
                    guard let pk = try? sc.insertImage(label: label, app: cand.app, w: thumb.w, h: thumb.h,
                                                       ext: ext, hash: Int64(bitPattern: h),
                                                       source: "copyem", at: when) else { return }
                    try? data.write(to: URL(fileURLWithPath: Sidecar.imageFile(pk: pk, ext: ext)))
                    try? thumb.png.write(to: URL(fileURLWithPath: Sidecar.thumbFile(pk: pk)))
                    if !keepDuplicates { seenImage.insert(h) }
                    added += 1
                }
                let count = Int(try sc.count())
                self.publish {
                    self.indexedCount = count; self.buildDone = self.buildTotal
                    self.phase = .ready; self.message = "Ready"
                }
                done(.success(ImportResult(added: added, upgraded: upgraded)))
            } catch {
                self.publish { self.phase = .ready; self.message = "Ready" }
                done(.failure(error))
            }
        }
    }

    /// Human-readable format name for an image clip's file extension.
    private static func formatLabel(_ ext: String) -> String {
        switch ext.lowercased() {
        case "jpg", "jpeg": return "JPEG"
        case "gif":         return "GIF"
        case "png":         return "PNG"
        case "webp":        return "WebP"
        case "avif":        return "AVIF"
        case "heic":        return "HEIC"
        case "heif":        return "HEIF"
        case "tiff":        return "TIFF"
        default:            return ext.isEmpty ? "Image" : ext.uppercased()
        }
    }

    /// Stable 64-bit content hash (FNV-1a) for deduping imports.
    private static func fnv1a(_ s: String) -> UInt64 { fnv1a(Data(s.utf8)) }
    private static func fnv1a(_ data: Data) -> UInt64 {
        var h: UInt64 = 0xcbf29ce484222325
        data.withUnsafeBytes { raw in for b in raw { h = (h ^ UInt64(b)) &* 0x00000100000001B3 } }
        return h
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

import Foundation

enum SearchMode: String, CaseIterable, Identifiable {
    case substring = "Substring"
    case words = "Words"
    case regex = "Regex"
    var id: String { rawValue }
}

/// A row returned to the UI.
struct SearchResult: Identifiable {
    let pk: Int64
    let text: String        // stored copy (full for clips; capped for Copy 'Em imports)
    let app: String?
    let list: String?
    let created: Double
    let useCount: Int64
    let source: String?     // "clipboard" | "copyem"
    let sourcePk: Int64?    // Copy 'Em Z_PK for imported rows (for full-text fetch)
    let favorite: Bool
    let kind: String        // "text" | "image"
    let imgW: Int64
    let imgH: Int64
    let ext: String?        // image file extension for image rows (e.g. "png")
    let title: String?      // fetched page title for bare-URL clips (opt-in)
    var id: Int64 { pk }

    var isImage: Bool { kind == "image" }
    var imagePath: String? { isImage ? Sidecar.imageFile(pk: pk, ext: ext ?? "png") : nil }
    var thumbPath: String? { isImage ? Sidecar.thumbFile(pk: pk) : nil }
}

/// Default store location, in this app's own Application Support folder.
enum Sidecar {
    static var directory: String {
        FileManager.default.homeDirectoryForCurrentUser.path
            + "/Library/Application Support/Stash"
    }
    static var dbPath: String { directory + "/index.db" }
    static var imagesDir: String { directory + "/images" }
    static func imageFile(pk: Int64, ext: String) -> String { imagesDir + "/\(pk).\(ext)" }
    static func thumbFile(pk: Int64) -> String { imagesDir + "/\(pk)_thumb.png" }
}

/// Owns the writable connection to the app's clipboard-history database.
/// Confined to the manager's serial queue.
final class SidecarDB {
    let db: SQLite

    static let schemaVersion = 2
    static let clipTextCap = 1_000_000   // self-captured clips stored in full up to this
    static let cols = "e.pk, e.text, e.app, e.list, e.created, e.usecount, e.source, e.source_pk, e.favorite, e.kind, e.img_w, e.img_h, e.ext, e.title"

    init() throws {
        try FileManager.default.createDirectory(
            atPath: Sidecar.directory, withIntermediateDirectories: true)
        db = try SQLite(path: Sidecar.dbPath, readOnly: false)
        try db.exec("""
            PRAGMA journal_mode=WAL;
            PRAGMA synchronous=NORMAL;
            PRAGMA temp_store=MEMORY;
        """)
        try migrate()
    }

    // MARK: schema / migration

    private func migrate() throws {
        try db.exec("CREATE TABLE IF NOT EXISTS meta(key TEXT PRIMARY KEY, value TEXT);")
        let version = Int(try getMeta("schema_version") ?? "0") ?? 0
        // Legacy stores (schema < 2) keyed rows on Copy 'Em's pk and are structurally
        // incompatible, so they're rebuilt (this also builds a fresh, empty store).
        // From v2 on, natively-captured clips live nowhere else — every later change
        // MUST be an additive migration (below) so a schema bump never wipes history.
        if version < 2 {
            try db.exec("""
                DROP TRIGGER IF EXISTS entries_ai;
                DROP TRIGGER IF EXISTS entries_ad;
                DROP TABLE IF EXISTS fts_trigram;
                DROP TABLE IF EXISTS fts_words;
                DROP TABLE IF EXISTS entries;
                DELETE FROM meta WHERE key IN ('last_copyem_pk','copyem_imported','last_pk');
            """)
            try createTables()
        }
        try setMeta("schema_version", String(SidecarDB.schemaVersion))
        // Additive migrations (never wipe data).
        try? db.exec("ALTER TABLE entries ADD COLUMN favorite INTEGER NOT NULL DEFAULT 0;")
        try? db.exec("CREATE INDEX IF NOT EXISTS entries_favorite ON entries(favorite);")
        try? db.exec("ALTER TABLE entries ADD COLUMN kind TEXT NOT NULL DEFAULT 'text';")
        try? db.exec("ALTER TABLE entries ADD COLUMN img_w INTEGER NOT NULL DEFAULT 0;")
        try? db.exec("ALTER TABLE entries ADD COLUMN img_h INTEGER NOT NULL DEFAULT 0;")
        try? db.exec("ALTER TABLE entries ADD COLUMN ext TEXT;")
        try? db.exec("ALTER TABLE entries ADD COLUMN hash INTEGER NOT NULL DEFAULT 0;")
        try? db.exec("CREATE INDEX IF NOT EXISTS entries_hash ON entries(hash);")
        try? db.exec("ALTER TABLE entries ADD COLUMN title TEXT;")
    }

    private func createTables() throws {
        try db.exec("""
            CREATE TABLE entries(
                pk        INTEGER PRIMARY KEY AUTOINCREMENT,
                text      TEXT,
                app       TEXT,
                list      TEXT,
                created   REAL,
                usecount  INTEGER,
                source    TEXT,
                source_pk INTEGER,
                favorite  INTEGER NOT NULL DEFAULT 0,
                kind      TEXT NOT NULL DEFAULT 'text',
                img_w     INTEGER NOT NULL DEFAULT 0,
                img_h     INTEGER NOT NULL DEFAULT 0,
                ext       TEXT,
                hash      INTEGER NOT NULL DEFAULT 0,
                title     TEXT
            );
            CREATE INDEX entries_created ON entries(created);
            CREATE INDEX entries_source_pk ON entries(source_pk);
            CREATE INDEX entries_hash ON entries(hash);

            CREATE VIRTUAL TABLE fts_trigram USING fts5(
                text, content='entries', content_rowid='pk', tokenize='trigram');
            CREATE VIRTUAL TABLE fts_words USING fts5(
                text, content='entries', content_rowid='pk',
                tokenize='porter unicode61 remove_diacritics 2');

            CREATE TRIGGER entries_ai AFTER INSERT ON entries BEGIN
                INSERT INTO fts_trigram(rowid, text) VALUES (new.pk, new.text);
                INSERT INTO fts_words(rowid, text)   VALUES (new.pk, new.text);
            END;
            CREATE TRIGGER entries_ad AFTER DELETE ON entries BEGIN
                INSERT INTO fts_trigram(fts_trigram, rowid, text) VALUES('delete', old.pk, old.text);
                INSERT INTO fts_words(fts_words, rowid, text)     VALUES('delete', old.pk, old.text);
            END;
        """)
    }

    // MARK: writes

    func begin() throws { try db.exec("BEGIN;") }
    func commit() throws { try db.exec("COMMIT;") }

    private lazy var clipStmt = try! db.prepare("""
        INSERT INTO entries(text, app, list, created, usecount, source, source_pk, hash)
        VALUES (?, ?, NULL, ?, 0, 'clipboard', NULL, ?)
    """)

    /// Insert a freshly-copied text clip with its content hash. Returns the pk.
    @discardableResult
    func insertClip(text: String, app: String?, hash: Int64, at date: Date = Date()) throws -> Int64 {
        let s = clipStmt
        s.reset()
        s.bind(1, text)
        if let app { s.bind(2, app) } else { s.bindNull(2) }
        s.bind(3, date.timeIntervalSince1970)
        s.bind(4, hash)
        try s.step()
        return db.lastInsertRowID
    }

    private lazy var imageStmt = try! db.prepare("""
        INSERT INTO entries(text, app, list, created, usecount, source, source_pk, kind, img_w, img_h, ext, hash)
        VALUES (?, ?, NULL, ?, 0, ?, NULL, 'image', ?, ?, ?, ?)
    """)

    /// Insert an image clip. Returns the new row's pk so the caller can write files.
    func insertImage(label: String, app: String?, w: Int, h: Int, ext: String,
                     hash: Int64, source: String = "clipboard", at date: Date = Date()) throws -> Int64 {
        let s = imageStmt
        s.reset()
        s.bind(1, label)
        if let app { s.bind(2, app) } else { s.bindNull(2) }
        s.bind(3, date.timeIntervalSince1970)
        s.bind(4, source)
        s.bind(5, Int64(w))
        s.bind(6, Int64(h))
        s.bind(7, ext)
        s.bind(8, hash)
        try s.step()
        return db.lastInsertRowID
    }

    private lazy var importStmt = try! db.prepare("""
        INSERT INTO entries(text, app, list, created, usecount, source, source_pk, hash, title)
        VALUES (?, ?, ?, ?, ?, 'copyem', ?, ?, ?)
    """)

    /// Insert a historical entry imported from Copy 'Em.
    func insertImported(_ r: SourceRow, hash: Int64) throws {
        let s = importStmt
        s.reset()
        s.bind(1, r.text)
        if let a = r.app { s.bind(2, a) } else { s.bindNull(2) }
        if let l = r.list { s.bind(3, l) } else { s.bindNull(3) }
        s.bind(4, r.created)
        s.bind(5, r.useCount)
        s.bind(6, r.pk)         // source_pk = Copy 'Em Z_PK
        s.bind(7, hash)
        // Copy 'Em's name is the page title for copied links — keep it for those,
        // so imports get titles without any network request.
        let t = (r.title ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if !t.isEmpty, t != r.text, LinkTitle.url(in: r.text) != nil {
            s.bind(8, String(t.prefix(200)))
        } else {
            s.bindNull(8)
        }
        try s.step()
    }

    /// Find an existing entry with the same content (indexed by hash). For text,
    /// `text` is verified to guard against rare hash collisions.
    func findEntry(hash: Int64, kind: String, text: String?) -> Int64? {
        guard let s = try? db.prepare("SELECT pk, text FROM entries WHERE hash = ? AND kind = ?") else { return nil }
        defer { s.finalize() }
        s.bind(1, hash); s.bind(2, kind)
        while (try? s.step()) == true {
            if let text { if s.string(1) == text { return s.int(0) } }
            else { return s.int(0) }
        }
        return nil
    }

    /// Move an entry to the top (newest) and bump its use-count.
    func bumpToTop(pk: Int64, at date: Date = Date()) {
        guard let s = try? db.prepare("UPDATE entries SET created = ?, usecount = usecount + 1 WHERE pk = ?") else { return }
        defer { s.finalize() }
        s.bind(1, date.timeIntervalSince1970); s.bind(2, pk); _ = try? s.step()
    }

    /// Store the fetched page title for a link clip.
    func setTitle(pk: Int64, _ title: String?) {
        guard let s = try? db.prepare("UPDATE entries SET title = ? WHERE pk = ?") else { return }
        defer { s.finalize() }
        if let t = title, !t.isEmpty { s.bind(1, t) } else { s.bindNull(1) }
        s.bind(2, pk); _ = try? s.step()
    }

    /// Assign an entry to a named group (its `list`), or clear it with nil.
    func setList(pk: Int64, _ list: String?) {
        guard let s = try? db.prepare("UPDATE entries SET list = ? WHERE pk = ?") else { return }
        defer { s.finalize() }
        if let l = list, !l.isEmpty { s.bind(1, l) } else { s.bindNull(1) }
        s.bind(2, pk); _ = try? s.step()
    }

    /// Unassign every entry from a group (keeps the clips, clears their `list`).
    func clearList(_ name: String) {
        guard let s = try? db.prepare("UPDATE entries SET list = NULL WHERE list = ?") else { return }
        defer { s.finalize() }
        s.bind(1, name); _ = try? s.step()
    }

    /// Image entries (pk, ext) in a group — so the caller can remove their files.
    func imageEntriesInList(_ name: String) -> [(Int64, String)] {
        guard let s = try? db.prepare("SELECT pk, ext FROM entries WHERE list = ? AND kind = 'image'") else { return [] }
        defer { s.finalize() }
        s.bind(1, name)
        var out: [(Int64, String)] = []
        while (try? s.step()) == true { out.append((s.int(0), s.string(1) ?? "png")) }
        return out
    }

    /// Delete every entry in a group (FTS rows are removed by the AFTER DELETE trigger).
    func deleteByList(_ name: String) {
        guard let s = try? db.prepare("DELETE FROM entries WHERE list = ?") else { return }
        defer { s.finalize() }
        s.bind(1, name); _ = try? s.step()
    }

    /// Distinct non-empty group names currently in use.
    func distinctLists() -> [String] {
        guard let s = try? db.prepare("SELECT DISTINCT list FROM entries WHERE list IS NOT NULL AND list <> '' ORDER BY list COLLATE NOCASE") else { return [] }
        defer { s.finalize() }
        var out: [String] = []
        while (try? s.step()) == true { if let v = s.string(0) { out.append(v) } }
        return out
    }

    func count() throws -> Int64 { try db.scalarInt("SELECT COUNT(*) FROM entries") ?? 0 }

    /// Delete one entry (FTS rows are removed by the AFTER DELETE trigger).
    func delete(pk: Int64) throws {
        let s = try db.prepare("DELETE FROM entries WHERE pk = ?")
        defer { s.finalize() }
        s.bind(1, pk); try s.step()
    }

    /// Mark or unmark an entry as a favorite.
    func setFavorite(pk: Int64, _ on: Bool) throws {
        let s = try db.prepare("UPDATE entries SET favorite = ? WHERE pk = ?")
        defer { s.finalize() }
        s.bind(1, Int64(on ? 1 : 0)); s.bind(2, pk); try s.step()
    }

    func setMeta(_ key: String, _ value: String) throws {
        let s = try db.prepare("INSERT OR REPLACE INTO meta(key,value) VALUES(?,?)")
        defer { s.finalize() }
        s.bind(1, key); s.bind(2, value); try s.step()
    }

    func getMeta(_ key: String) throws -> String? {
        let s = try db.prepare("SELECT value FROM meta WHERE key=?")
        defer { s.finalize() }
        s.bind(1, key)
        return try s.step() ? s.string(0) : nil
    }
}

/// Owns a read-only connection used for searching, confined to the search queue.
/// What subset of clips to show: everything, only favorites, or a named group.
enum SearchScope: Equatable {
    case all
    case favorites
    case group(String)

    var groupName: String? { if case .group(let n) = self { return n } else { return nil } }
    /// Standalone WHERE clause (recent / regex queries).
    var whereClause: String {
        switch self {
        case .all:       return ""
        case .favorites: return "WHERE e.favorite = 1"
        case .group:     return "WHERE e.list = ?"
        }
    }
    /// Extra condition appended after an FTS `MATCH ?`.
    var andClause: String {
        switch self {
        case .all:       return ""
        case .favorites: return " AND e.favorite = 1"
        case .group:     return " AND e.list = ?"
        }
    }
}

final class SearchEngine {
    private let db: SQLite
    static let pageSize = 200

    init() throws {
        db = try SQLite(path: Sidecar.dbPath, readOnly: true)
        try db.exec("PRAGMA query_only=1;")
    }

    /// Most recently added entries (newest first) — shown when the query is empty.
    func recent(offset: Int, limit: Int, scope: SearchScope) -> [SearchResult] {
        do {
            let s = try db.prepare("""
                SELECT \(SidecarDB.cols) FROM entries e
                \(scope.whereClause)
                ORDER BY e.created DESC, e.pk DESC
                LIMIT ? OFFSET ?
            """)
            defer { s.finalize() }
            var i: Int32 = 1
            if let g = scope.groupName { s.bind(i, g); i += 1 }
            s.bind(i, Int64(limit)); i += 1
            s.bind(i, Int64(offset))
            return try collect(s)
        } catch {
            return []
        }
    }

    /// Fetch one page of results. `offset` is how many already-loaded rows to skip.
    func search(_ raw: String, mode: SearchMode, offset: Int, limit: Int,
                scope: SearchScope, isCancelled: () -> Bool) -> [SearchResult] {
        let query = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return [] }
        do {
            switch mode {
            case .substring: return try ftsSearch(query, table: "fts_trigram", trigram: true, offset: offset, limit: limit, scope: scope)
            case .words:     return try ftsSearch(query, table: "fts_words", trigram: false, offset: offset, limit: limit, scope: scope)
            case .regex:     return try regexSearch(query, offset: offset, limit: limit, scope: scope, isCancelled: isCancelled)
            }
        } catch {
            return []
        }
    }

    // MARK: FTS (substring + words)

    private func ftsQuote(_ s: String) -> String {
        "\"" + s.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }

    private func ftsExpression(_ query: String, trigram: Bool) -> String? {
        let terms = query.split(whereSeparator: { $0 == " " || $0 == "\t" || $0 == "\n" })
        var parts: [String] = []
        for t in terms {
            if trigram {
                if t.count >= 3 { parts.append(ftsQuote(String(t))) }
            } else {
                let clean = t.unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) }
                if !clean.isEmpty { parts.append(ftsQuote(String(String.UnicodeScalarView(clean))) + " *") }
            }
        }
        return parts.isEmpty ? nil : parts.joined(separator: " ")
    }

    private func ftsSearch(_ query: String, table: String, trigram: Bool,
                           offset: Int, limit: Int, scope: SearchScope) throws -> [SearchResult] {
        guard let expr = ftsExpression(query, trigram: trigram) else { return [] }
        // e.pk tiebreak keeps OFFSET paging stable when many rows share a `created`
        // value (e.g. undated Copy 'Em imports all stored with created = 0).
        let order = trigram ? "e.created DESC, e.pk DESC" : "bm25(\(table)), e.pk DESC"
        let sql = """
            SELECT \(SidecarDB.cols)
            FROM \(table) f
            JOIN entries e ON e.pk = f.rowid
            WHERE f.\(table) MATCH ?\(scope.andClause)
            ORDER BY \(order)
            LIMIT ? OFFSET ?
        """
        let s = try db.prepare(sql)
        defer { s.finalize() }
        var i: Int32 = 1
        s.bind(i, expr); i += 1
        if let g = scope.groupName { s.bind(i, g); i += 1 }
        s.bind(i, Int64(limit)); i += 1
        s.bind(i, Int64(offset))
        return try collect(s)
    }

    // MARK: regex (full scan of the compact text)

    private func regexSearch(_ pattern: String, offset: Int, limit: Int,
                             scope: SearchScope, isCancelled: () -> Bool) throws -> [SearchResult] {
        let re: NSRegularExpression
        do {
            re = try NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
        } catch {
            return []
        }
        let s = try db.prepare("""
            SELECT \(SidecarDB.cols) FROM entries e
            \(scope.whereClause)
            ORDER BY e.created DESC, e.pk DESC
        """)
        defer { s.finalize() }
        if let g = scope.groupName { s.bind(1, g) }
        var out: [SearchResult] = []
        var matchIndex = 0
        var sinceCheck = 0
        while try s.step() {
            sinceCheck += 1
            if sinceCheck >= 512 { sinceCheck = 0; if isCancelled() { return out } }
            guard let text = s.string(1) else { continue }
            let range = NSRange(text.startIndex..<text.endIndex, in: text)
            if re.firstMatch(in: text, options: [], range: range) != nil {
                defer { matchIndex += 1 }
                if matchIndex < offset { continue }
                out.append(row(from: s, text: text))
                if out.count >= limit { break }
            }
        }
        return out
    }

    private func collect(_ s: Statement) throws -> [SearchResult] {
        var out: [SearchResult] = []
        while try s.step() { out.append(row(from: s, text: s.string(1) ?? "")) }
        return out
    }

    private func row(from s: Statement, text: String) -> SearchResult {
        SearchResult(
            pk: s.int(0), text: text, app: s.string(2), list: s.string(3),
            created: s.double(4), useCount: s.int(5), source: s.string(6),
            sourcePk: s.isNull(7) ? nil : s.int(7), favorite: s.int(8) != 0,
            kind: s.string(9) ?? "text", imgW: s.int(10), imgH: s.int(11), ext: s.string(12),
            title: s.string(13))
    }
}

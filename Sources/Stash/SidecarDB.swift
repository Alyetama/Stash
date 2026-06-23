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
    var id: Int64 { pk }
}

/// Default store location, in this app's own Application Support folder.
enum Sidecar {
    static var directory: String {
        FileManager.default.homeDirectoryForCurrentUser.path
            + "/Library/Application Support/Stash"
    }
    static var dbPath: String { directory + "/index.db" }
}

/// Owns the writable connection to the app's clipboard-history database.
/// Confined to the manager's serial queue.
final class SidecarDB {
    let db: SQLite

    static let schemaVersion = 2
    static let clipTextCap = 1_000_000   // self-captured clips stored in full up to this
    static let cols = "e.pk, e.text, e.app, e.list, e.created, e.usecount, e.source, e.source_pk"

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
        if version != SidecarDB.schemaVersion {
            // Rebuild on schema change (older builds keyed rows on Copy 'Em's pk).
            try db.exec("""
                DROP TRIGGER IF EXISTS entries_ai;
                DROP TRIGGER IF EXISTS entries_ad;
                DROP TABLE IF EXISTS fts_trigram;
                DROP TABLE IF EXISTS fts_words;
                DROP TABLE IF EXISTS entries;
                DELETE FROM meta WHERE key IN ('last_copyem_pk','copyem_imported','last_pk');
            """)
            try createTables()
            try setMeta("schema_version", String(SidecarDB.schemaVersion))
        }
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
                source_pk INTEGER
            );
            CREATE INDEX entries_created ON entries(created);
            CREATE INDEX entries_source_pk ON entries(source_pk);

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
        INSERT INTO entries(text, app, list, created, usecount, source, source_pk)
        VALUES (?, ?, NULL, ?, 0, 'clipboard', NULL)
    """)

    /// Record a freshly-copied clip. Returns false (no insert) if it's identical
    /// to the most recent entry (de-dupes repeats and our own copy-outs).
    @discardableResult
    func insertClip(text: String, app: String?, at date: Date = Date()) throws -> Bool {
        let capped = text.count > SidecarDB.clipTextCap
            ? String(text.prefix(SidecarDB.clipTextCap)) : text
        if let last = try latestText(), last == capped { return false }
        let s = clipStmt
        s.reset()
        s.bind(1, capped)
        if let app { s.bind(2, app) } else { s.bindNull(2) }
        s.bind(3, date.timeIntervalSince1970)
        try s.step()
        return true
    }

    private lazy var importStmt = try! db.prepare("""
        INSERT INTO entries(text, app, list, created, usecount, source, source_pk)
        VALUES (?, ?, ?, ?, ?, 'copyem', ?)
    """)

    /// Insert a historical entry imported from Copy 'Em.
    func insertImported(_ r: SourceRow) throws {
        let s = importStmt
        s.reset()
        s.bind(1, r.text)
        if let a = r.app { s.bind(2, a) } else { s.bindNull(2) }
        if let l = r.list { s.bind(3, l) } else { s.bindNull(3) }
        s.bind(4, r.created)
        s.bind(5, r.useCount)
        s.bind(6, r.pk)         // source_pk = Copy 'Em Z_PK
        try s.step()
    }

    func latestText() throws -> String? {
        let s = try db.prepare("SELECT text FROM entries ORDER BY created DESC, pk DESC LIMIT 1")
        defer { s.finalize() }
        return try s.step() ? s.string(0) : nil
    }

    func count() throws -> Int64 { try db.scalarInt("SELECT COUNT(*) FROM entries") ?? 0 }

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
final class SearchEngine {
    private let db: SQLite
    static let pageSize = 200

    init() throws {
        db = try SQLite(path: Sidecar.dbPath, readOnly: true)
        try db.exec("PRAGMA query_only=1;")
    }

    /// Most recently added entries (newest first) — shown when the query is empty.
    func recent(offset: Int, limit: Int) -> [SearchResult] {
        do {
            let s = try db.prepare("""
                SELECT \(SidecarDB.cols) FROM entries e
                ORDER BY e.created DESC, e.pk DESC
                LIMIT ? OFFSET ?
            """)
            defer { s.finalize() }
            s.bind(1, Int64(limit))
            s.bind(2, Int64(offset))
            return try collect(s)
        } catch {
            return []
        }
    }

    /// Fetch one page of results. `offset` is how many already-loaded rows to skip.
    func search(_ raw: String, mode: SearchMode, offset: Int, limit: Int,
                isCancelled: () -> Bool) -> [SearchResult] {
        let query = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return [] }
        do {
            switch mode {
            case .substring: return try ftsSearch(query, table: "fts_trigram", trigram: true, offset: offset, limit: limit)
            case .words:     return try ftsSearch(query, table: "fts_words", trigram: false, offset: offset, limit: limit)
            case .regex:     return try regexSearch(query, offset: offset, limit: limit, isCancelled: isCancelled)
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
                           offset: Int, limit: Int) throws -> [SearchResult] {
        guard let expr = ftsExpression(query, trigram: trigram) else { return [] }
        let order = trigram ? "e.created DESC" : "bm25(\(table))"
        let sql = """
            SELECT \(SidecarDB.cols)
            FROM \(table) f
            JOIN entries e ON e.pk = f.rowid
            WHERE f.\(table) MATCH ?
            ORDER BY \(order)
            LIMIT ? OFFSET ?
        """
        let s = try db.prepare(sql)
        defer { s.finalize() }
        s.bind(1, expr)
        s.bind(2, Int64(limit))
        s.bind(3, Int64(offset))
        return try collect(s)
    }

    // MARK: regex (full scan of the compact text)

    private func regexSearch(_ pattern: String, offset: Int, limit: Int,
                             isCancelled: () -> Bool) throws -> [SearchResult] {
        let re: NSRegularExpression
        do {
            re = try NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
        } catch {
            return []
        }
        let s = try db.prepare("SELECT \(SidecarDB.cols) FROM entries e ORDER BY e.created DESC")
        defer { s.finalize() }
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
            sourcePk: s.isNull(7) ? nil : s.int(7))
    }
}

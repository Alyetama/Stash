import Foundation

/// One indexable record pulled from the Copy 'Em store.
struct SourceRow {
    var pk: Int64
    var text: String        // truncated copy for indexing/preview
    var app: String?
    var list: String?
    var created: Double      // unix seconds (0 if unknown)
    var lastUsed: Double
    var useCount: Int64
}

/// Strictly read-only access to Copy 'Em's Core Data SQLite store.
/// This class NEVER writes to the source database.
final class SourceStore {
    /// Core Data reference date (2001-01-01) offset to unix epoch.
    static let coreDataEpoch: Double = 978_307_200

    /// Max characters stored per imported entry. Matches the self-capture cap so
    /// imports keep full text (the app no longer reads Copy 'Em on copy). The 1 MB
    /// ceiling just guards against pathological multi-megabyte pastes bloating FTS.
    static let indexTextCap = 1_000_000

    /// The old 16 KB cap — used to detect & upgrade previously-truncated imports.
    static let legacyTextCap = 16_384

    private let db: SQLite

    /// Default location of the Copy 'Em store inside its sandbox container.
    static var defaultPath: String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return home + "/Library/Containers/Copy-em-Paste/Data/Library/Application Support/Copy-em-Paste/Copy-em-Paste.storedata"
    }

    static func exists(at path: String) -> Bool {
        FileManager.default.fileExists(atPath: path)
    }

    init(path: String) throws {
        // mode=ro + immutable off: respects WAL, reads live state, cannot write.
        let uri = "file:" + path.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed)! + "?mode=ro"
        // sqlite3_open_v2 with a URI requires the URI flag; SQLite enables URI by
        // default for file: paths opened through open_v2 when SQLITE_OPEN_URI is set.
        self.db = try SQLite.openURI(uri)
        try db.exec("PRAGMA query_only=1;")
    }

    /// Fast approximate total of live entries, used only as a progress-bar
    /// denominator. Counts ZPASTEBOARDCONTENTS alone (no join to the text table),
    /// so it returns in ~0.5s instead of ~30s. Slightly over-counts entries that
    /// have no searchable text, which is fine for a progress estimate.
    func liveCount() throws -> Int64 {
        try db.scalarInt(
            "SELECT COUNT(*) FROM ZPASTEBOARDCONTENTS WHERE ZTRASHDATE IS NULL") ?? 0
    }

    private static let selectSQL = """
        SELECT c.Z_PK,
               substr(w.ZSTRING, 1, \(SourceStore.indexTextCap)),
               a.ZNAME,
               l.ZNAME,
               c.ZCREATIONDATE,
               c.ZLASTUSEDATE,
               c.ZUSECOUNT
        FROM ZPASTEBOARDCONTENTS c
        JOIN ZPASTEBOARDCONTENTSITEMSWRAPPER w ON c.ZITEMSWRAPPER = w.Z_PK
        LEFT JOIN ZPASTEBOARDCONTENTSAPP  a ON c.ZAPPLICATION = a.Z_PK
        LEFT JOIN ZPASTEBOARDCONTENTSLIST l ON c.ZLIST       = l.Z_PK
        WHERE c.ZTRASHDATE IS NULL AND w.ZSTRING IS NOT NULL AND c.Z_PK > ?
        ORDER BY c.Z_PK
    """

    /// Stream rows with Z_PK greater than `afterPK`, invoking `handler` for each.
    /// Used for both the initial build (afterPK = 0) and incremental syncs.
    func forEachRow(afterPK: Int64, _ handler: (SourceRow) -> Void) throws {
        let s = try db.prepare(SourceStore.selectSQL)
        defer { s.finalize() }
        s.bind(1, afterPK)
        while try s.step() {
            let createdRaw = s.isNull(4) ? 0 : s.double(4)
            let lastRaw = s.isNull(5) ? 0 : s.double(5)
            handler(SourceRow(
                pk: s.int(0),
                text: s.string(1) ?? "",
                app: s.string(2),
                list: s.string(3),
                created: createdRaw == 0 ? 0 : createdRaw + SourceStore.coreDataEpoch,
                lastUsed: lastRaw == 0 ? 0 : lastRaw + SourceStore.coreDataEpoch,
                useCount: s.int(6)
            ))
        }
    }

    /// One text-less Copy 'Em entry whose pasteboard data may contain an image.
    struct ImageCandidate {
        var pk: Int64
        var blob: Data
        var app: String?
        var created: Double   // unix seconds
    }

    private static let imageEntrySQL = """
        SELECT c.Z_PK, i.ZTYPESANDDATA, a.ZNAME, c.ZCREATIONDATE
        FROM ZPASTEBOARDCONTENTS c
        JOIN ZPASTEBOARDCONTENTSITEMSWRAPPER w ON c.ZITEMSWRAPPER = w.Z_PK
        JOIN ZPASTEBOARDCONTENTSITEM i        ON i.Z5ITEMS = w.Z_PK
        LEFT JOIN ZPASTEBOARDCONTENTSAPP a    ON c.ZAPPLICATION = a.Z_PK
        WHERE c.ZTRASHDATE IS NULL AND w.ZSTRING IS NULL AND i.ZTYPESANDDATA IS NOT NULL
        ORDER BY c.ZCREATIONDATE
    """

    /// Stream text-less entries with their raw pasteboard-data blob.
    func forEachImageEntry(_ handler: (ImageCandidate) -> Void) throws {
        let s = try db.prepare(SourceStore.imageEntrySQL)
        defer { s.finalize() }
        while try s.step() {
            guard let blob = s.blob(1) else { continue }
            let created = s.isNull(3) ? 0 : s.double(3) + SourceStore.coreDataEpoch
            handler(ImageCandidate(pk: s.int(0), blob: blob, app: s.string(2), created: created))
        }
    }
}

import Foundation
import SQLite3

/// SQLite TRANSIENT destructor — tells SQLite to copy bound bytes.
let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

enum SQLiteError: Error, CustomStringConvertible {
    case open(String)
    case prepare(String)
    case step(String)
    case exec(String)

    var description: String {
        switch self {
        case .open(let m): return "sqlite open: \(m)"
        case .prepare(let m): return "sqlite prepare: \(m)"
        case .step(let m): return "sqlite step: \(m)"
        case .exec(let m): return "sqlite exec: \(m)"
        }
    }
}

/// Thin wrapper over a single sqlite3 connection. Not thread-safe; callers must
/// confine each connection to one serial queue.
final class SQLite {
    let handle: OpaquePointer

    /// Open a database. `readOnly` opens with SQLITE_OPEN_READONLY (never writes).
    init(path: String, readOnly: Bool) throws {
        var db: OpaquePointer?
        let flags = readOnly
            ? SQLITE_OPEN_READONLY
            : (SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE)
        let rc = sqlite3_open_v2(path, &db, flags | SQLITE_OPEN_FULLMUTEX, nil)
        guard rc == SQLITE_OK, let db else {
            let msg = db.map { String(cString: sqlite3_errmsg($0)) } ?? "code \(rc)"
            if let db { sqlite3_close_v2(db) }
            throw SQLiteError.open(msg)
        }
        self.handle = db
        sqlite3_busy_timeout(db, 5000)
    }

    /// Open a `file:…?mode=ro` URI strictly read-only (SQLITE_OPEN_URI required
    /// for query parameters like mode=ro to take effect).
    static func openURI(_ uri: String) throws -> SQLite {
        var db: OpaquePointer?
        let flags = SQLITE_OPEN_READONLY | SQLITE_OPEN_URI | SQLITE_OPEN_FULLMUTEX
        let rc = sqlite3_open_v2(uri, &db, flags, nil)
        guard rc == SQLITE_OK, let db else {
            let msg = db.map { String(cString: sqlite3_errmsg($0)) } ?? "code \(rc)"
            if let db { sqlite3_close_v2(db) }
            throw SQLiteError.open(msg)
        }
        sqlite3_busy_timeout(db, 5000)
        return SQLite(adopting: db)
    }

    private init(adopting db: OpaquePointer) {
        self.handle = db
    }

    deinit { sqlite3_close_v2(handle) }

    var lastErrorMessage: String { String(cString: sqlite3_errmsg(handle)) }

    var lastInsertRowID: Int64 { sqlite3_last_insert_rowid(handle) }

    /// Run one or more statements with no result rows.
    func exec(_ sql: String) throws {
        var err: UnsafeMutablePointer<CChar>?
        if sqlite3_exec(handle, sql, nil, nil, &err) != SQLITE_OK {
            let msg = err.map { String(cString: $0) } ?? lastErrorMessage
            sqlite3_free(err)
            throw SQLiteError.exec(msg)
        }
    }

    func prepare(_ sql: String) throws -> Statement {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &stmt, nil) == SQLITE_OK, let stmt else {
            throw SQLiteError.prepare(lastErrorMessage)
        }
        return Statement(stmt)
    }

    /// Convenience: prepare, run to completion, and return the first integer column
    /// of the first row (or nil).
    func scalarInt(_ sql: String) throws -> Int64? {
        let s = try prepare(sql)
        defer { s.finalize() }
        return try s.step() ? s.int(0) : nil
    }
}

/// A prepared statement. Bind parameters are 1-based; columns are 0-based.
final class Statement {
    private let stmt: OpaquePointer
    init(_ stmt: OpaquePointer) { self.stmt = stmt }
    func finalize() { sqlite3_finalize(stmt) }

    func bind(_ index: Int32, _ value: String) {
        sqlite3_bind_text(stmt, index, value, -1, SQLITE_TRANSIENT)
    }
    func bind(_ index: Int32, _ value: Int64) {
        sqlite3_bind_int64(stmt, index, value)
    }
    func bind(_ index: Int32, _ value: Double) {
        sqlite3_bind_double(stmt, index, value)
    }
    func bindNull(_ index: Int32) {
        sqlite3_bind_null(stmt, index)
    }

    /// Step once. Returns true if a row is available, false when done.
    @discardableResult
    func step() throws -> Bool {
        let rc = sqlite3_step(stmt)
        if rc == SQLITE_ROW { return true }
        if rc == SQLITE_DONE { return false }
        throw SQLiteError.step(String(cString: sqlite3_errmsg(sqlite3_db_handle(stmt))))
    }

    func reset() { sqlite3_reset(stmt); sqlite3_clear_bindings(stmt) }

    func int(_ col: Int32) -> Int64 { sqlite3_column_int64(stmt, col) }
    func double(_ col: Int32) -> Double { sqlite3_column_double(stmt, col) }
    func isNull(_ col: Int32) -> Bool { sqlite3_column_type(stmt, col) == SQLITE_NULL }
    func string(_ col: Int32) -> String? {
        guard let c = sqlite3_column_text(stmt, col) else { return nil }
        return String(cString: c)
    }
    func blob(_ col: Int32) -> Data? {
        guard let bytes = sqlite3_column_blob(stmt, col) else { return nil }
        let count = Int(sqlite3_column_bytes(stmt, col))
        return Data(bytes: bytes, count: count)
    }
}

import Foundation
import SQLite3
import CryptoKit
import Security

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

final class PteIMSqliteStore {
  private var db: OpaquePointer?
  private let cipher: PteIMLocalCipher

  init(storeKey: String) throws {
    let digest = Self.cacheDigest(storeKey)
    cipher = try PteIMLocalCipher(keyAccount: digest)
    let root = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
    let url = root.appendingPathComponent("pte-live-im-\(digest).sqlite")
    guard sqlite3_open_v2(url.path, &db, SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX, nil) == SQLITE_OK else { throw PteIMError.invalidResponse }
    try? FileManager.default.setAttributes([.protectionKey: FileProtectionType.complete], ofItemAtPath: url.path)
    try execScript("PRAGMA journal_mode=WAL; CREATE TABLE IF NOT EXISTS meta (key TEXT PRIMARY KEY, value TEXT NOT NULL); INSERT OR IGNORE INTO meta(key,value) VALUES('db_schema_version','1'); CREATE TABLE IF NOT EXISTS sync_state (id INTEGER PRIMARY KEY CHECK (id = 1), cursor TEXT NOT NULL DEFAULT ''); INSERT OR IGNORE INTO sync_state(id,cursor) VALUES(1,''); CREATE TABLE IF NOT EXISTS conversations (id TEXT PRIMARY KEY, version INTEGER NOT NULL DEFAULT 0, updated_at INTEGER NOT NULL DEFAULT 0, payload TEXT NOT NULL); CREATE TABLE IF NOT EXISTS messages (client_msg_id TEXT PRIMARY KEY, server_msg_id TEXT, conversation_id TEXT NOT NULL, server_seq INTEGER, created_at INTEGER NOT NULL DEFAULT 0, payload TEXT NOT NULL, state TEXT NOT NULL); CREATE TABLE IF NOT EXISTS outbox (client_msg_id TEXT PRIMARY KEY, retry_count INTEGER NOT NULL DEFAULT 0, next_retry_at INTEGER NOT NULL DEFAULT 0);")
    if !(try query("PRAGMA table_info(messages)") { statement in columnString(statement, 1) ?? "" }).contains("created_at") {
      try exec("ALTER TABLE messages ADD COLUMN created_at INTEGER NOT NULL DEFAULT 0")
    }
    try execScript("CREATE INDEX IF NOT EXISTS idx_messages_conversation_created_at ON messages(conversation_id, created_at); UPDATE meta SET value='2' WHERE key='db_schema_version';")
    try migrateCacheEncryption()
  }

  deinit { sqlite3_close(db) }

  /** Explicit recovery for an unavailable Keychain key or irrecoverably corrupted local cache. */
  static func clear(storeKey: String) throws {
    let digest = cacheDigest(storeKey)
    let root = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
    let baseURL = root.appendingPathComponent("pte-live-im-\(digest).sqlite")
    for suffix in ["", "-wal", "-shm"] {
      try? FileManager.default.removeItem(atPath: baseURL.path + suffix)
    }
    try PteIMLocalCipher.removeKey(keyAccount: digest)
  }

  func cursor() throws -> String {
    var statement: OpaquePointer?
    defer { sqlite3_finalize(statement) }
    guard sqlite3_prepare_v2(db, "SELECT cursor FROM sync_state WHERE id = 1", -1, &statement, nil) == SQLITE_OK, sqlite3_step(statement) == SQLITE_ROW,
          let value = sqlite3_column_text(statement, 0) else { return "" }
    return try cipher.decrypt(String(cString: value))
  }

  func enqueue(_ message: PteIMMessage) throws {
    try transaction {
      try upsert(message, state: message.state)
      try exec("INSERT OR REPLACE INTO outbox(client_msg_id) VALUES(?)", [message.clientMsgId])
    }
  }
  func markSent(clientMsgId: String, serverMsgId: String?, serverSeq: Int64?) throws {
    try transaction {
      try exec("UPDATE messages SET server_msg_id=?, server_seq=?, state='sent' WHERE client_msg_id=?", [serverMsgId, serverSeq.map(String.init), clientMsgId])
      try exec("DELETE FROM outbox WHERE client_msg_id=?", [clientMsgId])
    }
  }
  func replaceQueued(_ message: PteIMMessage) throws { try transaction { try upsert(message, state: message.state) } }
  func markFailed(clientMsgId: String) throws { try transaction { try exec("UPDATE messages SET state='failed' WHERE client_msg_id=?", [clientMsgId]); try exec("DELETE FROM outbox WHERE client_msg_id=?", [clientMsgId]) } }
  func apply(messages: [PteIMMessage], nextCursor: String) throws {
    try transaction { for message in messages { try upsert(message, state: .sent) }; try exec("UPDATE sync_state SET cursor=? WHERE id=1", [try cipher.encrypt(nextCursor)]) }
  }

  func localMessages(conversationId: String, beforeCreatedAt: Int64?, limit: Int) throws -> [StoredMessage] {
    guard (1...200).contains(limit) else { throw PteIMError.invalidResponse }
    let sql = beforeCreatedAt == nil
      ? "SELECT payload,server_msg_id,server_seq,created_at,state FROM messages WHERE conversation_id=? ORDER BY created_at DESC LIMIT \(limit)"
      : "SELECT payload,server_msg_id,server_seq,created_at,state FROM messages WHERE conversation_id=? AND created_at < ? ORDER BY created_at DESC LIMIT \(limit)"
    let args = beforeCreatedAt == nil ? [conversationId] : [conversationId, String(beforeCreatedAt!)]
    return try query(sql, args: args) { statement in
      StoredMessage(payload: try cipher.decrypt(columnString(statement, 0) ?? "{}"), serverMsgId: columnString(statement, 1), serverSeq: columnInt64(statement, 2), createdAt: columnInt64(statement, 3) ?? 0, state: columnString(statement, 4) ?? PteIMSendState.sent.rawValue)
    }
  }

  func localConversations(limit: Int) throws -> [StoredConversation] {
    guard (1...200).contains(limit) else { throw PteIMError.invalidResponse }
    return try query("SELECT conversation_id,payload,server_msg_id,server_seq,created_at,state FROM messages grouped WHERE rowid = (SELECT latest.rowid FROM messages latest WHERE latest.conversation_id=grouped.conversation_id ORDER BY created_at DESC LIMIT 1) ORDER BY created_at DESC LIMIT \(limit)") { statement in
      StoredConversation(conversationId: columnString(statement, 0) ?? "", lastMessage: StoredMessage(payload: try cipher.decrypt(columnString(statement, 1) ?? "{}"), serverMsgId: columnString(statement, 2), serverSeq: columnInt64(statement, 3), createdAt: columnInt64(statement, 4) ?? 0, state: columnString(statement, 5) ?? PteIMSendState.sent.rawValue))
    }
  }

  /** Returns retryable messages whose persisted backoff has elapsed. */
  func dueOutbox(now: Int64, limit: Int = 100) throws -> [StoredMessage] {
    guard (1...200).contains(limit) else { throw PteIMError.invalidResponse }
    return try query("SELECT m.payload,m.server_msg_id,m.server_seq,m.created_at,m.state FROM outbox o JOIN messages m ON m.client_msg_id=o.client_msg_id WHERE o.next_retry_at <= ? ORDER BY o.next_retry_at ASC LIMIT \(limit)", args: [String(now)]) { statement in
      StoredMessage(payload: try cipher.decrypt(columnString(statement, 0) ?? "{}"), serverMsgId: columnString(statement, 1), serverSeq: columnInt64(statement, 2), createdAt: columnInt64(statement, 3) ?? 0, state: columnString(statement, 4) ?? PteIMSendState.pending.rawValue)
    }
  }

  /** Records one send attempt and returns its next persisted retry time. */
  func recordOutboxAttempt(clientMsgId: String, now: Int64) throws -> Int64? {
    try transactionResult {
      let values = try query("SELECT retry_count FROM outbox WHERE client_msg_id=?", args: [clientMsgId]) { statement in sqlite3_column_int(statement, 0) }
      guard let retryCount = values.first else { return nil }
      let nextRetryAt = now + retryDelayMs(retryCount)
      try exec("UPDATE outbox SET retry_count=?,next_retry_at=? WHERE client_msg_id=?", [String(retryCount + 1), String(nextRetryAt), clientMsgId])
      return nextRetryAt
    }
  }

  func nextOutboxRetryAt() throws -> Int64? {
    try query("SELECT MIN(next_retry_at) FROM outbox") { statement in columnInt64(statement, 0) }.first ?? nil
  }

  private func upsert(_ message: PteIMMessage, state: PteIMSendState) throws {
    let data = try JSONEncoder().encode(message)
    try exec("INSERT OR REPLACE INTO messages(client_msg_id,server_msg_id,conversation_id,server_seq,created_at,payload,state) VALUES(?,?,?,?,?,?,?)", [message.clientMsgId, message.serverMsgId, message.conversationId, message.serverSeq.map(String.init), String(message.createdAt), try cipher.encrypt(String(data: data, encoding: .utf8) ?? "{}"), state.rawValue])
  }
  private func transaction(_ work: () throws -> Void) throws { try exec("BEGIN IMMEDIATE"); do { try work(); try exec("COMMIT") } catch { try? exec("ROLLBACK"); throw error } }
  private func transactionResult<T>(_ work: () throws -> T) throws -> T { try exec("BEGIN IMMEDIATE"); do { let value = try work(); try exec("COMMIT"); return value } catch { try? exec("ROLLBACK"); throw error } }
  private func exec(_ sql: String, _ args: [String?] = []) throws {
    var statement: OpaquePointer?
    defer { sqlite3_finalize(statement) }
    guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { throw PteIMError.invalidResponse }
    for (index, value) in args.enumerated() {
      if let value { sqlite3_bind_text(statement, Int32(index + 1), value, -1, SQLITE_TRANSIENT) }
      else { sqlite3_bind_null(statement, Int32(index + 1)) }
    }
    guard sqlite3_step(statement) == SQLITE_DONE else { throw PteIMError.invalidResponse }
  }
  private func execScript(_ sql: String) throws {
    var error: UnsafeMutablePointer<CChar>?
    guard sqlite3_exec(db, sql, nil, nil, &error) == SQLITE_OK else {
      defer { sqlite3_free(error) }; throw PteIMError.invalidResponse
    }
  }

  private func query<T>(_ sql: String, args: [String?] = [], map: (OpaquePointer?) throws -> T) throws -> [T] {
    var statement: OpaquePointer?
    defer { sqlite3_finalize(statement) }
    guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { throw PteIMError.invalidResponse }
    for (index, value) in args.enumerated() {
      if let value { sqlite3_bind_text(statement, Int32(index + 1), value, -1, SQLITE_TRANSIENT) } else { sqlite3_bind_null(statement, Int32(index + 1)) }
    }
    var values: [T] = []
    while sqlite3_step(statement) == SQLITE_ROW { values.append(try map(statement)) }
    return values
  }

  /** Upgrades plaintext and pte1 records to pte2 AES-GCM values without removing cached messages. */
  private func migrateCacheEncryption() throws {
    try transaction {
      let cursor = try query("SELECT cursor FROM sync_state WHERE id=1") { statement in columnString(statement, 0) ?? "" }.first ?? ""
      if cipher.needsMigration(cursor) {
        try exec("UPDATE sync_state SET cursor=? WHERE id=1", [try cipher.encrypt(cipher.decrypt(cursor))])
      }
      try migratePayloads(table: "messages", idColumn: "client_msg_id")
      try migratePayloads(table: "conversations", idColumn: "id")
    }
  }

  private func migratePayloads(table: String, idColumn: String) throws {
    let rows = try query("SELECT \(idColumn),payload FROM \(table)") { statement in
      (columnString(statement, 0) ?? "", columnString(statement, 1) ?? "")
    }
    for (id, payload) in rows where cipher.needsMigration(payload) {
      try exec("UPDATE \(table) SET payload=? WHERE \(idColumn)=?", [try cipher.encrypt(cipher.decrypt(payload)), id])
    }
  }

  private static func cacheDigest(_ storeKey: String) -> String {
    SHA256.hash(data: Data(storeKey.utf8)).map { String(format: "%02x", $0) }.joined()
  }
}

/** AES-256-GCM message-payload cipher. Its per-cache key is held in the iOS Keychain. */
private final class PteIMLocalCipher {
  private static let service = "com.ptelive.im.cache"
  private let key: SymmetricKey
  private let aad: Data

  init(keyAccount: String) throws {
    aad = Data("pte.im.cache/v2/\(keyAccount)".utf8)
    let query: [CFString: Any] = [
      kSecClass: kSecClassGenericPassword,
      kSecAttrService: Self.service,
      kSecAttrAccount: keyAccount,
      kSecReturnData: true,
    ]
    var item: CFTypeRef?
    let result = SecItemCopyMatching(query as CFDictionary, &item)
    if result == errSecSuccess, let data = item as? Data {
      key = SymmetricKey(data: data)
      return
    }
    guard result == errSecItemNotFound else { throw PteIMError.invalidResponse }
    let generated = SymmetricKey(size: .bits256)
    let data = generated.withUnsafeBytes { Data($0) }
    let add: [CFString: Any] = [
      kSecClass: kSecClassGenericPassword,
      kSecAttrService: Self.service,
      kSecAttrAccount: keyAccount,
      kSecValueData: data,
      kSecAttrAccessible: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
    ]
    guard SecItemAdd(add as CFDictionary, nil) == errSecSuccess else { throw PteIMError.invalidResponse }
    key = generated
  }

  func encrypt(_ value: String) throws -> String {
    let box = try AES.GCM.seal(Data(value.utf8), using: key, authenticating: aad)
    guard let combined = box.combined else { throw PteIMError.invalidResponse }
    return "pte2:" + combined.base64EncodedString()
  }

  func decrypt(_ value: String) throws -> String {
    guard value.hasPrefix("pte1:") || value.hasPrefix("pte2:") else { return value } // Transparent migration from previous cache records.
    guard let data = Data(base64Encoded: String(value.dropFirst(5))) else { throw PteIMError.invalidResponse }
    let box = try AES.GCM.SealedBox(combined: data)
    let decrypted = value.hasPrefix("pte2:")
      ? try AES.GCM.open(box, using: key, authenticating: aad)
      : try AES.GCM.open(box, using: key)
    guard let plaintext = String(data: decrypted, encoding: .utf8) else { throw PteIMError.invalidResponse }
    return plaintext
  }

  func needsMigration(_ value: String) -> Bool { !value.hasPrefix("pte2:") }

  static func removeKey(keyAccount: String) throws {
    let query: [CFString: Any] = [
      kSecClass: kSecClassGenericPassword,
      kSecAttrService: service,
      kSecAttrAccount: keyAccount,
    ]
    let status = SecItemDelete(query as CFDictionary)
    guard status == errSecSuccess || status == errSecItemNotFound else { throw PteIMError.invalidResponse }
  }
}

struct StoredMessage { let payload: String; let serverMsgId: String?; let serverSeq: Int64?; let createdAt: Int64; let state: String }
struct StoredConversation { let conversationId: String; let lastMessage: StoredMessage }

private func columnString(_ statement: OpaquePointer?, _ index: Int32) -> String? {
  guard let value = sqlite3_column_text(statement, index) else { return nil }; return String(cString: value)
}
private func columnInt64(_ statement: OpaquePointer?, _ index: Int32) -> Int64? {
  sqlite3_column_type(statement, index) == SQLITE_NULL ? nil : sqlite3_column_int64(statement, index)
}

private func retryDelayMs(_ retryCount: Int32) -> Int64 {
  Int64(1_000) << Int64(min(max(retryCount, 0), 5))
}

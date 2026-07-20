import CoreData
import CryptoKit
import Foundation
import Security

/** Core Data cache for one authenticated IM account. UI layers never access this store directly. */
final class PteIMCoreDataStore: @unchecked Sendable {
  private enum Kind { static let meta = "meta"; static let message = "message"; static let remote = "remote"; static let outbox = "outbox" }
  private let context: NSManagedObjectContext
  private let cipher: PteIMLocalCipher

  /**
   Production sessions use a per-account encrypted SQLite store. Preview and
   snapshot sessions explicitly select an in-memory store so they never touch
   Keychain or a user's durable message cache.
   */
  init(storeKey: String, persistent: Bool = true) throws {
    let digest = Self.cacheDigest(storeKey)
    cipher = try PteIMLocalCipher(keyAccount: digest, persistent: persistent)
    let description: NSPersistentStoreDescription
    if persistent {
      let root = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
      description = NSPersistentStoreDescription(url: root.appendingPathComponent("pte-live-im-\(digest).coredata"))
      description.type = NSSQLiteStoreType
      description.setOption(FileProtectionType.complete as NSObject, forKey: NSPersistentStoreFileProtectionKey)
    } else {
      description = NSPersistentStoreDescription()
      description.type = NSInMemoryStoreType
    }
    description.setOption(true as NSNumber, forKey: NSMigratePersistentStoresAutomaticallyOption)
    description.setOption(true as NSNumber, forKey: NSInferMappingModelAutomaticallyOption)
    let coordinator = NSPersistentStoreCoordinator(managedObjectModel: Self.model())
    // Preview sessions deliberately use an in-memory store. Passing SQLite
    // here ignored the selected description type and made the Demo's offline
    // visual-preview route fail before any UIKit screen was presented.
    try coordinator.addPersistentStore(ofType: description.type, configurationName: nil, at: description.url, options: description.options)
    context = NSManagedObjectContext(concurrencyType: .privateQueueConcurrencyType)
    context.persistentStoreCoordinator = coordinator
  }

  static func clear(storeKey: String) throws {
    let digest = cacheDigest(storeKey)
    let root = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
    let url = root.appendingPathComponent("pte-live-im-\(digest).coredata")
    for suffix in ["", "-wal", "-shm"] { try? FileManager.default.removeItem(atPath: url.path + suffix) }
    try PteIMLocalCipher.removeKey(keyAccount: digest)
  }

  func cursor() throws -> String { try meta("sync_cursor") }
  func stateCursor() throws -> String { try meta("state_sync_cursor") }
  func conversationCursor() throws -> String { try meta("conversation_sync_cursor") }
  func setStateCursor(_ value: String) throws { try setMeta("state_sync_cursor", value) }

  func apply(messages: [PteIMMessage], nextCursor: String) throws {
    try write { context in
      for message in messages { try self.upsert(message, state: .sent, in: context) }
      try self.setMeta("sync_cursor", nextCursor, in: context)
    }
  }

  func enqueue(_ message: PteIMMessage) throws {
    try write { context in
      try self.upsert(message, state: message.state, in: context)
      let outbox = self.upsertRecord(key: "outbox:\(message.clientMsgId)", kind: Kind.outbox, in: context)
      outbox.setValue(message.clientMsgId, forKey: "parent")
      outbox.setValue(Int64(0), forKey: "retryCount")
      outbox.setValue(Int64(0), forKey: "nextRetryAt")
    }
  }

  func replaceQueued(_ message: PteIMMessage) throws { try write { try self.upsert(message, state: message.state, in: $0) } }

  func markSent(clientMsgId: String, serverMsgId: String?, serverSeq: Int64?) throws {
    try write { context in
      guard let row = self.record(key: clientMsgId, in: context) else { return }
      row.setValue(serverMsgId, forKey: "serverMsgId"); row.setValue(serverSeq ?? 0, forKey: "serverSeq"); row.setValue(serverSeq != nil, forKey: "hasServerSeq"); row.setValue(PteIMSendState.sent.rawValue, forKey: "state")
      if let outbox = self.record(key: "outbox:\(clientMsgId)", in: context) { context.delete(outbox) }
    }
  }

  func markFailed(clientMsgId: String) throws {
    try write { context in
      self.record(key: clientMsgId, in: context)?.setValue(PteIMSendState.failed.rawValue, forKey: "state")
      if let outbox = self.record(key: "outbox:\(clientMsgId)", in: context) { context.delete(outbox) }
    }
  }

  func deleteLocal(clientMsgId: String) throws {
    try write { context in
      if let outbox = self.record(key: "outbox:\(clientMsgId)", in: context) { context.delete(outbox) }
      if let row = self.record(key: clientMsgId, in: context) { context.delete(row) }
    }
  }

  func applyMessageEvent(serverMsgId: String, eventType: String, status: Int, recalledAt: Int64, emoji: String, reactionAction: String, actor: String, currentUserId: String) throws -> PteIMMessage? {
    try write { context in
      let predicate = NSPredicate(format: "kind == %@ AND serverMsgId == %@", Kind.message, serverMsgId)
      guard let row = try self.records(kind: Kind.message, predicate: predicate, sort: [], limit: 1, in: context).first else { return nil }
      if eventType == "chat.message.deleted" { context.delete(row); return nil }
      var message = try JSONDecoder().decode(PteIMMessage.self, from: Data((try self.cipher.decrypt(row.value(forKey: "payload") as? String ?? "{}")).utf8))
      if eventType == "chat.message.recalled" {
        message.status = status == 0 ? 2 : status
        message.recalledAt = recalledAt > 0 ? recalledAt : nil
      } else if eventType == "chat.message.reaction_changed", !emoji.isEmpty {
        let added = reactionAction == "added"
        var reactions = message.reactions
        if let index = reactions.firstIndex(where: { $0.emoji == emoji }) {
          let current = reactions[index]
          reactions[index] = PteIMMessageReaction(emoji: emoji, count: max(0, current.count + (added ? 1 : -1)), reactedByMe: actor == currentUserId ? added : current.reactedByMe)
        } else if added {
          reactions.append(PteIMMessageReaction(emoji: emoji, count: 1, reactedByMe: actor == currentUserId))
        }
        message.reactions = reactions
      } else { return nil }
      try self.upsert(message, state: .sent, in: context)
      return message
    }
  }

  func applyRemoteConversations(_ rows: [PteIMRemoteConversation], nextCursor: String) throws {
    try write { context in
      for row in rows {
        let record = self.upsertRecord(key: "remote:\(row.id)", kind: Kind.remote, in: context)
        record.setValue(row.lastMessageAt, forKey: "createdAt")
        record.setValue(try self.cipher.encrypt(String(data: JSONEncoder().encode(row), encoding: .utf8) ?? "{}"), forKey: "payload")
      }
      try self.setMeta("conversation_sync_cursor", nextCursor, in: context)
    }
  }

  func localRemoteConversations(limit: Int) throws -> [PteIMRemoteConversation] {
    guard (1...200).contains(limit) else { throw PteIMError.invalidResponse }
    return try read { context in
      try self.records(kind: Kind.remote, predicate: nil, sort: [NSSortDescriptor(key: "createdAt", ascending: false)], limit: limit, in: context).map {
        try JSONDecoder().decode(PteIMRemoteConversation.self, from: Data((try self.cipher.decrypt($0.value(forKey: "payload") as? String ?? "{}")).utf8))
      }
    }
  }

  func localMessages(conversationId: String, beforeCreatedAt: Int64?, limit: Int) throws -> [StoredMessage] {
    guard (1...200).contains(limit) else { throw PteIMError.invalidResponse }
    return try read { context in
      var predicate = NSPredicate(format: "kind == %@ AND parent == %@", Kind.message, conversationId)
      if let beforeCreatedAt { predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [predicate, NSPredicate(format: "createdAt < %lld", beforeCreatedAt)]) }
      return try self.records(kind: Kind.message, predicate: predicate, sort: [NSSortDescriptor(key: "createdAt", ascending: false)], limit: limit, in: context).map(self.storedMessage)
    }
  }

  func localConversations(limit: Int) throws -> [StoredConversation] {
    guard (1...200).contains(limit) else { throw PteIMError.invalidResponse }
    return try read { context in
      let rows = try self.records(kind: Kind.message, predicate: nil, sort: [NSSortDescriptor(key: "createdAt", ascending: false)], limit: 2_000, in: context)
      var result: [StoredConversation] = []; var seen = Set<String>()
      for row in rows {
        let conversationId = row.value(forKey: "parent") as? String ?? ""
        if !conversationId.isEmpty && seen.insert(conversationId).inserted { result.append(StoredConversation(conversationId: conversationId, lastMessage: try self.storedMessage(row))) }
        if result.count == limit { break }
      }
      return result
    }
  }

  func dueOutbox(now: Int64, limit: Int = 100) throws -> [StoredMessage] {
    guard (1...200).contains(limit) else { throw PteIMError.invalidResponse }
    return try read { context in
      let predicate = NSPredicate(format: "kind == %@ AND nextRetryAt <= %lld", Kind.outbox, now)
      return try self.records(kind: Kind.outbox, predicate: predicate, sort: [NSSortDescriptor(key: "nextRetryAt", ascending: true)], limit: limit, in: context).compactMap {
        guard let messageId = $0.value(forKey: "parent") as? String, let message = self.record(key: messageId, in: context) else { return nil }
        return try self.storedMessage(message)
      }
    }
  }

  func recordOutboxAttempt(clientMsgId: String, now: Int64) throws -> Int64? {
    try write { context in
      guard let outbox = self.record(key: "outbox:\(clientMsgId)", in: context) else { return nil }
      let retryCount = outbox.value(forKey: "retryCount") as? Int64 ?? 0
      let next = now + retryDelayMs(retryCount)
      outbox.setValue(retryCount + 1, forKey: "retryCount"); outbox.setValue(next, forKey: "nextRetryAt")
      return next
    }
  }

  func nextOutboxRetryAt() throws -> Int64? {
    try read { context in
      try self.records(kind: Kind.outbox, predicate: nil, sort: [NSSortDescriptor(key: "nextRetryAt", ascending: true)], limit: 1, in: context).first?.value(forKey: "nextRetryAt") as? Int64
    }
  }

  private func meta(_ key: String) throws -> String { try read { context in guard let row = self.record(key: "meta:\(key)", in: context) else { return "" }; return try self.cipher.decrypt(row.value(forKey: "payload") as? String ?? "") } }
  private func setMeta(_ key: String, _ value: String) throws { try write { try self.setMeta(key, value, in: $0) } }
  private func setMeta(_ key: String, _ value: String, in context: NSManagedObjectContext) throws { let row = upsertRecord(key: "meta:\(key)", kind: Kind.meta, in: context); row.setValue(try cipher.encrypt(value), forKey: "payload") }

  private func upsert(_ message: PteIMMessage, state: PteIMSendState, in context: NSManagedObjectContext) throws {
    let row = upsertRecord(key: message.clientMsgId, kind: Kind.message, in: context)
    row.setValue(message.conversationId, forKey: "parent"); row.setValue(message.serverMsgId, forKey: "serverMsgId"); row.setValue(message.serverSeq ?? 0, forKey: "serverSeq"); row.setValue(message.serverSeq != nil, forKey: "hasServerSeq"); row.setValue(message.createdAt, forKey: "createdAt"); row.setValue(state.rawValue, forKey: "state")
    row.setValue(try cipher.encrypt(String(data: JSONEncoder().encode(message), encoding: .utf8) ?? "{}"), forKey: "payload")
  }

  private func storedMessage(_ row: NSManagedObject) throws -> StoredMessage {
    StoredMessage(payload: try cipher.decrypt(row.value(forKey: "payload") as? String ?? "{}"), serverMsgId: row.value(forKey: "serverMsgId") as? String, serverSeq: (row.value(forKey: "hasServerSeq") as? Bool ?? false) ? row.value(forKey: "serverSeq") as? Int64 : nil, createdAt: row.value(forKey: "createdAt") as? Int64 ?? 0, state: row.value(forKey: "state") as? String ?? PteIMSendState.sent.rawValue)
  }

  private func record(key: String, in context: NSManagedObjectContext) -> NSManagedObject? { try? records(kind: nil, predicate: NSPredicate(format: "key == %@", key), sort: [], limit: 1, in: context).first }
  private func upsertRecord(key: String, kind: String, in context: NSManagedObjectContext) -> NSManagedObject { if let existing = record(key: key, in: context) { return existing }; let row = NSEntityDescription.insertNewObject(forEntityName: "PteIMCacheRecord", into: context); row.setValue(key, forKey: "key"); row.setValue(kind, forKey: "kind"); return row }
  private func records(kind: String?, predicate: NSPredicate?, sort: [NSSortDescriptor], limit: Int, in context: NSManagedObjectContext) throws -> [NSManagedObject] { let request = NSFetchRequest<NSManagedObject>(entityName: "PteIMCacheRecord"); request.predicate = predicate ?? kind.map { NSPredicate(format: "kind == %@", $0) }; request.sortDescriptors = sort; request.fetchLimit = limit; return try context.fetch(request) }
  private func read<T: Sendable>(_ block: @escaping @Sendable (NSManagedObjectContext) throws -> T) throws -> T { try context.performAndWait { try block(context) } }
  private func write<T: Sendable>(_ block: @escaping @Sendable (NSManagedObjectContext) throws -> T) throws -> T { try read { context in let value = try block(context); if context.hasChanges { try context.save() }; return value } }

  private static func model() -> NSManagedObjectModel {
    let model = NSManagedObjectModel(); let entity = NSEntityDescription(); entity.name = "PteIMCacheRecord"; entity.managedObjectClassName = NSStringFromClass(NSManagedObject.self)
    func attribute(_ name: String, _ type: NSAttributeType, optional: Bool = false, defaultValue: Any? = nil) -> NSAttributeDescription { let value = NSAttributeDescription(); value.name = name; value.attributeType = type; value.isOptional = optional; value.defaultValue = defaultValue; return value }
    entity.properties = [attribute("key", .stringAttributeType), attribute("kind", .stringAttributeType), attribute("parent", .stringAttributeType, optional: true), attribute("payload", .stringAttributeType, defaultValue: ""), attribute("serverMsgId", .stringAttributeType, optional: true), attribute("serverSeq", .integer64AttributeType, defaultValue: 0), attribute("hasServerSeq", .booleanAttributeType, defaultValue: false), attribute("createdAt", .integer64AttributeType, defaultValue: 0), attribute("state", .stringAttributeType, defaultValue: ""), attribute("retryCount", .integer64AttributeType, defaultValue: 0), attribute("nextRetryAt", .integer64AttributeType, defaultValue: 0)]
    entity.uniquenessConstraints = [["key"]]; model.entities = [entity]; return model
  }
  private static func cacheDigest(_ storeKey: String) -> String { SHA256.hash(data: Data(storeKey.utf8)).map { String(format: "%02x", $0) }.joined() }
}

private final class PteIMLocalCipher {
  private static let service = "com.ptelive.im.cache"; private let key: SymmetricKey; private let aad: Data
  init(keyAccount: String, persistent: Bool = true) throws {
    aad = Data("pte.im.cache/v2/\(keyAccount)".utf8); let query: [CFString: Any] = [kSecClass: kSecClassGenericPassword, kSecAttrService: Self.service, kSecAttrAccount: keyAccount, kSecReturnData: true]
    if !persistent { key = SymmetricKey(size: .bits256); return }
    var item: CFTypeRef?; let result = SecItemCopyMatching(query as CFDictionary, &item)
    if result == errSecSuccess, let data = item as? Data { key = SymmetricKey(data: data); return }
    guard result == errSecItemNotFound else {
      #if DEBUG
      throw NSError(domain: "PteIMLocalCipher", code: Int(result), userInfo: [NSLocalizedDescriptionKey: "Keychain read failed with OSStatus \(result)"])
      #else
      throw PteIMError.invalidResponse
      #endif
    }
    let generated = SymmetricKey(size: .bits256); let data = generated.withUnsafeBytes { Data($0) }; let add: [CFString: Any] = [kSecClass: kSecClassGenericPassword, kSecAttrService: Self.service, kSecAttrAccount: keyAccount, kSecValueData: data, kSecAttrAccessible: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly]
    guard SecItemAdd(add as CFDictionary, nil) == errSecSuccess else { throw PteIMError.invalidResponse }; key = generated
  }
  func encrypt(_ value: String) throws -> String { let box = try AES.GCM.seal(Data(value.utf8), using: key, authenticating: aad); guard let combined = box.combined else { throw PteIMError.invalidResponse }; return "pte2:" + combined.base64EncodedString() }
  func decrypt(_ value: String) throws -> String { guard value.hasPrefix("pte2:"), let data = Data(base64Encoded: String(value.dropFirst(5))) else { return value }; return String(data: try AES.GCM.open(try AES.GCM.SealedBox(combined: data), using: key, authenticating: aad), encoding: .utf8) ?? "" }
  static func removeKey(keyAccount: String) throws { let query: [CFString: Any] = [kSecClass: kSecClassGenericPassword, kSecAttrService: service, kSecAttrAccount: keyAccount]; let status = SecItemDelete(query as CFDictionary); guard status == errSecSuccess || status == errSecItemNotFound else { throw PteIMError.invalidResponse } }
}

struct StoredMessage: Sendable { let payload: String; let serverMsgId: String?; let serverSeq: Int64?; let createdAt: Int64; let state: String }
struct StoredConversation: Sendable { let conversationId: String; let lastMessage: StoredMessage }
private func retryDelayMs(_ retryCount: Int64) -> Int64 { Int64(1_000) << Int64(min(max(retryCount, 0), 5)) }

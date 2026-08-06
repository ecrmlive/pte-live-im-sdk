import CryptoKit
import Foundation
import Security

/** Device identity and message envelopes for pte-live-im's P-256/A256GCM E2EE contract. */
internal final class PteIME2EE {
  private static let algorithm = "P-256/A256GCM"
  private static let messageAAD = Data("pte-live-im-message-v1".utf8)
  private static let wrapAAD = Data("pte-live-im-audit-wrap-v1".utf8)
  private let appId: Int64
  private let userId: String
  private let account: String
  private let persistentIdentity: Bool
  private var volatileIdentity: Identity?

  init(storeKey: String, appId: Int64, userId: String, persistentIdentity: Bool = true) {
    self.appId = appId; self.userId = userId
    self.account = PteIMResponseCipher.base64URL(Data(SHA256.hash(data: Data(storeKey.utf8))))
    self.persistentIdentity = persistentIdentity
  }

  func register(request: @escaping (String, [String: Any]) async throws -> Any) async throws {
    let identity = try identity()
    _ = try await request("api/v1/chat/e2ee/device/register", [
      "app_id": appId, "user_id": Int64(userId) ?? 0, "device_id": identity.deviceId,
      "public_key": encodedPublicKey(identity.privateKey.publicKey),
      "algorithm": Self.algorithm
    ])
  }

  func encrypt(_ message: PteIMMessage, request: @escaping (String, [String: Any]) async throws -> Any) async throws -> [String: Any] {
    guard let conversationId = Int64(message.conversationId) else { throw PteIMError.invalidResponse }
    let devicesResult = try await request("api/v1/chat/e2ee/device/list", ["app_id": appId, "user_id": Int64(userId) ?? 0, "conversation_id": conversationId])
    guard let devices = devicesResult as? [[String: Any]] else { throw PteIME2EEError.invalidDeviceList }
    let auditResult = try await request("api/v1/chat/e2ee/audit-key", [:])
    guard let audit = auditResult as? [String: Any] else { throw PteIME2EEError.invalidAuditKey }

    let contentKey = SymmetricKey(size: .bits256)
    let contentNonce = AES.GCM.Nonce()
    let content = try JSONSerialization.data(withJSONObject: message.contentDictionary)
    let sealed = try AES.GCM.seal(content, using: contentKey, nonce: contentNonce, authenticating: Self.messageAAD)
    var result: [String: Any] = [
      "version": 1, "algorithm": Self.algorithm,
      "ciphertext": PteIMResponseCipher.base64URL(sealed.ciphertext + sealed.tag),
      "nonce": PteIMResponseCipher.base64URL(Data(contentNonce)), "recipients": [] as [[String: Any]]
    ]
    let rawContentKey = contentKey.withUnsafeBytes { Data($0) }
    result["recipients"] = try devices.map { device in
      guard let remoteUserId = numericUserId(device["user_id"]),
            let deviceId = device["device_id"] as? String,
            let publicKey = device["public_key"] as? String,
            !deviceId.isEmpty, !publicKey.isEmpty else { throw PteIME2EEError.invalidRecipient }
      let wrapped = try wrap(rawContentKey, for: publicKey)
      return ["user_id": remoteUserId, "device_id": deviceId,
              "ephemeral_public_key": wrapped.ephemeralPublicKey, "wrapped_key": wrapped.ciphertext, "nonce": wrapped.nonce]
    }
    if (audit["enabled"] as? Bool) == true {
      guard (audit["algorithm"] as? String) == Self.algorithm,
            let keyId = audit["key_id"] as? String, let publicKey = audit["public_key"] as? String,
            !keyId.isEmpty, !publicKey.isEmpty else { throw PteIME2EEError.invalidAuditKey }
      let wrapped = try wrap(rawContentKey, for: publicKey)
      result["audit_recipients"] = [["key_id": keyId, "ephemeral_public_key": wrapped.ephemeralPublicKey, "wrapped_key": wrapped.ciphertext, "nonce": wrapped.nonce]]
    } else if (audit["required"] as? Bool) == true {
      throw PteIMError.invalidResponse
    }
    return result
  }

  func decrypt(_ envelope: [String: Any]) throws -> [String: Any] {
    guard (envelope["version"] as? NSNumber)?.intValue == 1, envelope["algorithm"] as? String == Self.algorithm,
          let recipients = envelope["recipients"] as? [[String: Any]] else { throw PteIMError.invalidResponse }
    let local = try identity()
    guard let recipient = recipients.first(where: { ($0["device_id"] as? String) == local.deviceId }),
          let ephemeral = recipient["ephemeral_public_key"] as? String,
          let wrappedKey = recipient["wrapped_key"] as? String,
          let wrapNonce = recipient["nonce"] as? String,
          let ciphertext = envelope["ciphertext"] as? String,
          let nonce = envelope["nonce"] as? String else { throw PteIMError.invalidResponse }
    let shared = try local.privateKey.sharedSecretFromKeyAgreement(with: p256PublicKey(ephemeral))
    let wrapNonceData = try PteIMResponseCipher.base64URLDecode(wrapNonce)
    let unwrapKey = PteIMResponseCipher.deriveKey(shared: shared.withUnsafeBytes { Data($0) }, salt: wrapNonceData, label: Self.wrapAAD)
    let wrappedBox = try AES.GCM.SealedBox(combined: wrapNonceData + (try PteIMResponseCipher.base64URLDecode(wrappedKey)))
    let contentKey = try AES.GCM.open(wrappedBox, using: unwrapKey, authenticating: Self.wrapAAD)
    guard contentKey.count == 32 else { throw PteIMError.invalidResponse }
    let messageNonce = try PteIMResponseCipher.base64URLDecode(nonce)
    let messageBox = try AES.GCM.SealedBox(combined: messageNonce + (try PteIMResponseCipher.base64URLDecode(ciphertext)))
    let clear = try AES.GCM.open(messageBox, using: SymmetricKey(data: contentKey), authenticating: Self.messageAAD)
    guard let object = try JSONSerialization.jsonObject(with: clear) as? [String: Any] else { throw PteIMError.invalidResponse }
    return object
  }

  /** A new local identity cannot decrypt envelopes addressed to a removed
   * device. This is a normal history condition, distinct from bad ciphertext. */
  func canDecrypt(_ envelope: [String: Any]) throws -> Bool {
    guard (envelope["version"] as? NSNumber)?.intValue == 1,
          envelope["algorithm"] as? String == Self.algorithm,
          let recipients = envelope["recipients"] as? [[String: Any]] else { throw PteIMError.invalidResponse }
    let local = try identity()
    return recipients.contains { ($0["device_id"] as? String) == local.deviceId }
  }

  private func wrap(_ contentKey: Data, for remotePublicKey: String) throws -> WrappedKey {
    let remote = try p256PublicKey(remotePublicKey)
    let ephemeral = P256.KeyAgreement.PrivateKey()
    let secret = try ephemeral.sharedSecretFromKeyAgreement(with: remote)
    let nonce = AES.GCM.Nonce()
    let nonceData = Data(nonce)
    let key = PteIMResponseCipher.deriveKey(shared: secret.withUnsafeBytes { Data($0) }, salt: nonceData, label: Self.wrapAAD)
    let sealed = try AES.GCM.seal(contentKey, using: key, nonce: nonce, authenticating: Self.wrapAAD)
    return WrappedKey(ephemeralPublicKey: encodedPublicKey(ephemeral.publicKey), ciphertext: PteIMResponseCipher.base64URL(sealed.ciphertext + sealed.tag), nonce: PteIMResponseCipher.base64URL(nonceData))
  }

  /** The IM wire contract uses uncompressed ANSI X9.63 P-256 keys: 04 || X || Y. */
  private func encodedPublicKey(_ key: P256.KeyAgreement.PublicKey) -> String {
    PteIMResponseCipher.base64URL(Data([0x04]) + key.rawRepresentation)
  }

  private func numericUserId(_ value: Any?) -> Int64? {
    if let number = value as? NSNumber { return number.int64Value }
    if let string = value as? String { return Int64(string) }
    return nil
  }

  /** The IM service accepts both 64-byte CryptoKit X/Y and 65-byte X9.63 public keys. */
  private func p256PublicKey(_ encoded: String) throws -> P256.KeyAgreement.PublicKey {
    let decoded = try PteIMResponseCipher.base64URLDecode(encoded)
    let raw = decoded.first == 0x04 ? Data(decoded.dropFirst()) : decoded
    guard raw.count == 64 else { throw PteIMError.invalidResponse }
    do {
      return try P256.KeyAgreement.PublicKey(rawRepresentation: raw)
    } catch {
      throw PteIME2EEError.invalidRecipientKey
    }
  }

  private func identity() throws -> Identity {
    if !persistentIdentity {
      if let volatileIdentity { return volatileIdentity }
      let created = makeVolatileIdentity()
      volatileIdentity = created
      return created
    }
    if let privateData = readKeychain("private"), let deviceData = readKeychain("device"), let deviceId = String(data: deviceData, encoding: .utf8) {
      return Identity(privateKey: try P256.KeyAgreement.PrivateKey(rawRepresentation: privateData), deviceId: deviceId)
    }
    let key = P256.KeyAgreement.PrivateKey(); let deviceId = UUID().uuidString
    try saveKeychain(key.rawRepresentation, named: "private"); try saveKeychain(Data(deviceId.utf8), named: "device")
    return Identity(privateKey: key, deviceId: deviceId)
  }

  /// Preview and SDK-test clients must not create a new server-side device on
  /// every process run. Production clients always use the Keychain path above.
  private func makeVolatileIdentity() -> Identity {
    var seed = Data("pte-live-im-volatile-e2ee-v1|\(account)".utf8)
    for _ in 0..<8 {
      let raw = Data(SHA256.hash(data: seed))
      if let privateKey = try? P256.KeyAgreement.PrivateKey(rawRepresentation: raw) {
        let deviceMaterial = Data(SHA256.hash(data: Data("device|\(account)".utf8)))
        let deviceId = "volatile-\(PteIMResponseCipher.base64URL(deviceMaterial))"
        return Identity(privateKey: privateKey, deviceId: deviceId)
      }
      seed = Data(SHA256.hash(data: seed))
    }
    return Identity(privateKey: P256.KeyAgreement.PrivateKey(), deviceId: UUID().uuidString)
  }

  private func readKeychain(_ name: String) -> Data? {
    let query: [CFString: Any] = [kSecClass: kSecClassGenericPassword, kSecAttrService: "com.ptelive.im.e2ee", kSecAttrAccount: "\(account).\(name)", kSecReturnData: true]
    var value: CFTypeRef?
    return SecItemCopyMatching(query as CFDictionary, &value) == errSecSuccess ? value as? Data : nil
  }

  private func saveKeychain(_ data: Data, named name: String) throws {
    let query: [CFString: Any] = [kSecClass: kSecClassGenericPassword, kSecAttrService: "com.ptelive.im.e2ee", kSecAttrAccount: "\(account).\(name)"]
    SecItemDelete(query as CFDictionary)
    var item = query; item[kSecValueData] = data; item[kSecAttrAccessible] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
    guard SecItemAdd(item as CFDictionary, nil) == errSecSuccess else { throw PteIMError.invalidResponse }
  }

  private struct Identity { let privateKey: P256.KeyAgreement.PrivateKey; let deviceId: String }
  private struct WrappedKey { let ephemeralPublicKey: String; let ciphertext: String; let nonce: String }
}

private enum PteIME2EEError: LocalizedError {
  case invalidDeviceList
  case invalidAuditKey
  case invalidRecipient
  case invalidRecipientKey

  var errorDescription: String? {
    switch self {
    case .invalidDeviceList: return "E2EE device list response is invalid"
    case .invalidAuditKey: return "E2EE audit key response is invalid"
    case .invalidRecipient: return "E2EE recipient record is invalid"
    case .invalidRecipientKey: return "E2EE recipient public key is invalid"
    }
  }
}

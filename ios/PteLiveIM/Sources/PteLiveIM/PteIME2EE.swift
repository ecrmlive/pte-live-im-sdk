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

  init(storeKey: String, appId: Int64, userId: String) {
    self.appId = appId; self.userId = userId
    self.account = PteIMResponseCipher.base64URL(Data(SHA256.hash(data: Data(storeKey.utf8))))
  }

  func register(request: @escaping (String, [String: Any]) async throws -> Any) async throws {
    let identity = try identity()
    _ = try await request("api/v1/chat/e2ee/device/register", [
      "app_id": appId, "user_id": Int64(userId) ?? 0, "device_id": identity.deviceId,
      "public_key": PteIMResponseCipher.base64URL(identity.privateKey.publicKey.rawRepresentation),
      "algorithm": Self.algorithm
    ])
  }

  func encrypt(_ message: PteIMMessage, request: @escaping (String, [String: Any]) async throws -> Any) async throws -> [String: Any] {
    guard let conversationId = Int64(message.conversationId) else { throw PteIMError.invalidResponse }
    let devicesResult = try await request("api/v1/chat/e2ee/device/list", ["app_id": appId, "user_id": Int64(userId) ?? 0, "conversation_id": conversationId])
    guard let devices = devicesResult as? [[String: Any]] else { throw PteIMError.invalidResponse }
    let auditResult = try await request("api/v1/chat/e2ee/audit-key", [:])
    guard let audit = auditResult as? [String: Any] else { throw PteIMError.invalidResponse }

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
      guard let remoteUserId = device["user_id"] as? NSNumber,
            let deviceId = device["device_id"] as? String,
            let publicKey = device["public_key"] as? String else { throw PteIMError.invalidResponse }
      let wrapped = try wrap(rawContentKey, for: publicKey)
      return ["user_id": remoteUserId.int64Value, "device_id": deviceId,
              "ephemeral_public_key": wrapped.ephemeralPublicKey, "wrapped_key": wrapped.ciphertext, "nonce": wrapped.nonce]
    }
    if (audit["enabled"] as? Bool) == true {
      guard (audit["algorithm"] as? String) == Self.algorithm,
            let keyId = audit["key_id"] as? String, let publicKey = audit["public_key"] as? String else { throw PteIMError.invalidResponse }
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
    let shared = try local.privateKey.sharedSecretFromKeyAgreement(with: P256.KeyAgreement.PublicKey(rawRepresentation: try PteIMResponseCipher.base64URLDecode(ephemeral)))
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

  private func wrap(_ contentKey: Data, for encodedPublicKey: String) throws -> WrappedKey {
    let remote = try P256.KeyAgreement.PublicKey(rawRepresentation: try PteIMResponseCipher.base64URLDecode(encodedPublicKey))
    let ephemeral = P256.KeyAgreement.PrivateKey()
    let secret = try ephemeral.sharedSecretFromKeyAgreement(with: remote)
    let nonce = AES.GCM.Nonce()
    let nonceData = Data(nonce)
    let key = PteIMResponseCipher.deriveKey(shared: secret.withUnsafeBytes { Data($0) }, salt: nonceData, label: Self.wrapAAD)
    let sealed = try AES.GCM.seal(contentKey, using: key, nonce: nonce, authenticating: Self.wrapAAD)
    return WrappedKey(ephemeralPublicKey: PteIMResponseCipher.base64URL(ephemeral.publicKey.rawRepresentation), ciphertext: PteIMResponseCipher.base64URL(sealed.ciphertext + sealed.tag), nonce: PteIMResponseCipher.base64URL(nonceData))
  }

  private func identity() throws -> Identity {
    if let privateData = readKeychain("private"), let deviceData = readKeychain("device"), let deviceId = String(data: deviceData, encoding: .utf8) {
      return Identity(privateKey: try P256.KeyAgreement.PrivateKey(rawRepresentation: privateData), deviceId: deviceId)
    }
    let key = P256.KeyAgreement.PrivateKey(); let deviceId = UUID().uuidString
    try saveKeychain(key.rawRepresentation, named: "private"); try saveKeychain(Data(deviceId.utf8), named: "device")
    return Identity(privateKey: key, deviceId: deviceId)
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

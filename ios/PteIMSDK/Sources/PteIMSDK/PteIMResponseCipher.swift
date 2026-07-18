import CryptoKit
import Foundation

/** Implements the api-im P-256/A256GCM response envelope. */
public enum PteIMResponseCipher {
  private static let context = Data("pte-live-api-response-v1".utf8)

  public static func requestKey() -> P256.KeyAgreement.PrivateKey { P256.KeyAgreement.PrivateKey() }

  public static func requestPublicKey(_ key: P256.KeyAgreement.PrivateKey) -> String {
    // CryptoKit exposes P-256 public keys as the 64-byte X || Y value, while
    // the shared API contract uses the 65-byte X9.63 representation (04 || X
    // || Y), matching Android and the Go server implementation.
    base64URL(Data([0x04]) + key.publicKey.rawRepresentation)
  }

  public static func decrypt(_ value: Data, with key: P256.KeyAgreement.PrivateKey) throws -> Data {
    let envelope = try JSONDecoder().decode(Envelope.self, from: value)
    guard envelope.version == 1, envelope.algorithm == "P-256/A256GCM" else { throw PteIMError.invalidResponse }
    let encodedServerKey = try base64URLDecode(envelope.ephemeralPublicKey)
    let serverKeyBytes = encodedServerKey.first == 0x04 ? Data(encodedServerKey.dropFirst()) : encodedServerKey
    guard serverKeyBytes.count == 64 else { throw PteIMError.invalidResponse }
    let serverKey = try P256.KeyAgreement.PublicKey(rawRepresentation: serverKeyBytes)
    let secret = try key.sharedSecretFromKeyAgreement(with: serverKey)
    let salt = try base64URLDecode(envelope.salt)
    let nonce = try base64URLDecode(envelope.nonce)
    guard salt.count == 32, nonce.count == 12 else { throw PteIMError.invalidResponse }
    let shared = secret.withUnsafeBytes { Data($0) }
    let symmetricKey = deriveKey(shared: shared, salt: salt, label: context)
    let combined = nonce + (try base64URLDecode(envelope.ciphertext))
    let box = try AES.GCM.SealedBox(combined: combined)
    return try AES.GCM.open(box, using: symmetricKey, authenticating: context)
  }

  static func deriveKey(shared: Data, salt: Data, label: Data) -> SymmetricKey {
    let material = shared + label
    let code = HMAC<SHA256>.authenticationCode(for: material, using: SymmetricKey(data: salt))
    return SymmetricKey(data: Data(code))
  }

  static func base64URL(_ value: Data) -> String {
    value.base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
  }

  static func base64URLDecode(_ value: String) throws -> Data {
    var base64 = value.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
    base64 += String(repeating: "=", count: (4 - base64.count % 4) % 4)
    guard let data = Data(base64Encoded: base64) else { throw PteIMError.invalidResponse }
    return data
  }

  private struct Envelope: Decodable {
    let version: Int
    let algorithm: String
    let ephemeralPublicKey: String
    let salt: String
    let nonce: String
    let ciphertext: String
    enum CodingKeys: String, CodingKey {
      case version, algorithm, salt, nonce, ciphertext
      case ephemeralPublicKey = "ephemeral_public_key"
    }
  }
}

import Foundation
import PteIMSDK

struct PteIMUIDemoCaptcha {
  let id: String
  let imageData: Data
}

struct PteIMUIDemoBusinessCredential {
  let mobile: String
  let nickname: String
  let sdkAppId: Int64
  let userId: String
  let userSig: String
  let expiresAt: Int64
  let refreshToken: String
  let refreshExpiresAt: Int64
}

struct PteIMUIDemoRegisteredUser {
  let userId: Int64
  let nickname: String
  let mobile: String
}

@MainActor
final class PteIMUIDemoBusinessAPI {
  private let apiDomain: URL
  private let deviceId = UUID().uuidString

  init(apiDomain: URL) { self.apiDomain = apiDomain }

  func captcha() async throws -> PteIMUIDemoCaptcha {
    let data = try await request(path: "api/v1/demo/auth/captcha", body: [:]) as? [String: Any] ?? [:]
    guard let id = data["captcha_id"] as? String, let url = data["image_data"] as? String,
          let image = Data(base64Encoded: String(url.split(separator: ",").last ?? "")) else { throw PteIMError.invalidResponse }
    return PteIMUIDemoCaptcha(id: id, imageData: image)
  }

  func register(mobile: String, nickname: String, password: String, captchaID: String, captchaCode: String) async throws -> PteIMUIDemoBusinessCredential {
    try await authenticate(path: "api/v1/demo/auth/register", mobile: mobile, nickname: nickname, password: password, captchaID: captchaID, captchaCode: captchaCode)
  }

  func login(mobile: String, password: String, captchaID: String, captchaCode: String) async throws -> PteIMUIDemoBusinessCredential {
    try await authenticate(path: "api/v1/demo/auth/login", mobile: mobile, nickname: nil, password: password, captchaID: captchaID, captchaCode: captchaCode)
  }

  func refresh(credential: PteIMUIDemoBusinessCredential) async throws -> PteIMUIDemoBusinessCredential {
    let body: [String: Any] = ["refresh_token": credential.refreshToken, "device_id": deviceId, "platform": "ios"]
    let data = try await request(path: "api/v1/im/session/refresh", body: body) as? [String: Any] ?? [:]
    return try self.credential(from: data, fallback: credential)
  }

  private func authenticate(path: String, mobile: String, nickname: String?, password: String, captchaID: String, captchaCode: String) async throws -> PteIMUIDemoBusinessCredential {
    var body: [String: Any] = ["mobile": mobile, "password": password, "captcha_id": captchaID, "captcha_code": captchaCode, "device_id": deviceId, "platform": "ios"]
    if let nickname { body["nickname"] = nickname }
    let data = try await request(path: path, body: body) as? [String: Any] ?? [:]
    return try credential(from: data)
  }

  private func credential(from data: [String: Any], fallback: PteIMUIDemoBusinessCredential? = nil) throws -> PteIMUIDemoBusinessCredential {
    guard let sdkAppID = data["sdk_app_id"] as? String, let sdk = Int64(sdkAppID), let userID = data["user_id"] as? String, let sig = data["user_sig"] as? String, let returnedMobile = (data["mobile"] as? String) ?? fallback?.mobile, let returnedNickname = (data["nickname"] as? String) ?? fallback?.nickname, let expireAt = (data["expire_at"] as? NSNumber)?.int64Value, let refreshToken = data["refresh_token"] as? String, let refreshExpireAt = (data["refresh_expire_at"] as? NSNumber)?.int64Value else { throw PteIMError.invalidResponse }
    return PteIMUIDemoBusinessCredential(mobile: returnedMobile, nickname: returnedNickname, sdkAppId: sdk, userId: userID, userSig: sig, expiresAt: expireAt, refreshToken: refreshToken, refreshExpiresAt: refreshExpireAt)
  }

  func users(credential: PteIMUIDemoBusinessCredential) async throws -> [PteIMUIDemoRegisteredUser] {
    let rows = try await request(path: "api/v1/demo/users", body: [:], credential: credential) as? [[String: Any]] ?? []
    return rows.compactMap { row in guard let rawID = row["user_id"] as? String, let id = Int64(rawID), let nickname = row["nickname"] as? String, let mobile = row["mobile"] as? String else { return nil }; return PteIMUIDemoRegisteredUser(userId: id, nickname: nickname, mobile: mobile) }
  }

  func addFriend(_ user: PteIMUIDemoRegisteredUser, credential: PteIMUIDemoBusinessCredential) async throws {
    _ = try await request(path: "api/v1/demo/friends/add", body: ["target_user_id": String(user.userId)], credential: credential)
  }

  private func request(path: String, body: [String: Any], credential: PteIMUIDemoBusinessCredential? = nil) async throws -> Any {
    let responseKey = PteIMResponseCipher.requestKey()
    var request = URLRequest(url: apiDomain.appendingPathComponent(path)); request.httpMethod = "POST"; request.timeoutInterval = 10
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.setValue(PteIMResponseCipher.requestPublicKey(responseKey), forHTTPHeaderField: "X-Pte-Response-Public-Key")
    if let credential { request.setValue("Bearer \(credential.userSig)", forHTTPHeaderField: "Authorization"); request.setValue(String(credential.sdkAppId), forHTTPHeaderField: "X-Pte-Sdk-AppId"); request.setValue(credential.userId, forHTTPHeaderField: "X-Pte-User-Id") }
    request.httpBody = try JSONSerialization.data(withJSONObject: body)
    let (data, response) = try await URLSession.shared.data(for: request)
    guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { throw PteIMError.invalidResponse }
    let clear = try PteIMResponseCipher.decrypt(data, with: responseKey)
    let root = try JSONSerialization.jsonObject(with: clear) as? [String: Any] ?? [:]
    guard (root["code"] as? Int) == 1 else { throw NSError(domain: "PteIMUIDemo", code: 1, userInfo: [NSLocalizedDescriptionKey: root["msg"] as? String ?? "请求失败"]) }
    return root["data"] ?? [:]
  }
}

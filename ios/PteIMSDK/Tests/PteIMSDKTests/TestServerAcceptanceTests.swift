import Foundation
import XCTest
@testable import PteIMSDK

/// SDK-only acceptance against the normal test server. No Demo target or business UI is involved.
final class TestServerAcceptanceTests: XCTestCase {
  private let apiDomain = "https://api-im.qxkejiwl.top"
  private let imDomain = "wss://wss.qxkejiwl.top/ws"
  private let cosDomain = "https://cos.qxkejiwl.top"
  private let commerceDomain = "https://api-im-commerce.qxkejiwl.top"

  func testNormalUsersExchangeEncryptedChatAndReceiveDeliveryAck() async throws {
    // Dedicated ordinary test-server users keep this scenario independent from
    // social/scene cases and their registered E2EE devices.
    let senderID = "98000001"
    let receiverID = "98000002"
    let sender = try await normalSDK(userId: senderID, deviceID: "ios-sdk-chat-sender")
    let receiver = try await normalSDK(userId: receiverID, deviceID: "ios-sdk-chat-receiver")
    defer { sender.stop(); receiver.stop() }

    let delivered = expectation(description: "sender receives delivery ACK")
    let received = expectation(description: "receiver decrypts text")
    let errors = AcceptanceErrorBox()
    let listenerA = PteIMListener()
    let listenerB = PteIMListener()
    let text = "ios-sdk-e2e-\(UUID().uuidString)"
    listenerA.onMessageStateChanged = { _, state in
      if state == .sent { delivered.fulfill() }
    }
    listenerA.onError = { errors.append("sender: \(String(reflecting: $0))") }
    listenerB.onMessage = { message in
      if message.text == text { received.fulfill() }
    }
    listenerB.onError = { errors.append("receiver: \(String(reflecting: $0))") }
    sender.addListener(listenerA)
    receiver.addListener(listenerB)
    defer { sender.removeListener(listenerA); receiver.removeListener(listenerB) }

    let bothConnected = await waitUntil { sender.isConnected() && receiver.isConnected() }
    XCTAssertTrue(bothConnected, "both chat clients must connect before sending")
    let conversation = try await sender.openSingleConversation(peerUserId: 98_000_002)
    _ = sender.sendText(conversationId: String(conversation.id), text: text)
    await fulfillment(of: [delivered, received], timeout: 30)
    XCTAssertTrue(errors.values.isEmpty, errors.values.joined(separator: " | "))
  }

  func testNormalUserCompletesSocialAndCommerceReadContracts() async throws {
    let sdk = try await normalSDK(userId: "91000001", deviceID: "ios-sdk-extension")
    defer { sdk.stop() }

    let profile = try await sdk.fetchMyProfile()
    XCTAssertEqual(profile.userId, 9_100_0001)
    try await sdk.follow(userId: 9_100_0002, remark: "sdk-e2e")
    let follows = try await sdk.fetchFollows(limit: 100)
    XCTAssertTrue(follows.list.contains(where: { $0.userId == "91000002" }))
    try await sdk.unfollow(userId: 9_100_0002)

    let capabilities = try await sdk.commerce.capabilities()
    XCTAssertTrue(capabilities.gifts)
    XCTAssertTrue(capabilities.backpack)
    XCTAssertTrue(capabilities.orders)
    _ = try await sdk.commerce.gifts()
    _ = try await sdk.commerce.wallet()
    _ = try await sdk.commerce.backpack()
    _ = try await sdk.commerce.orders()
  }

  func testNormalUserEntersSocialRoomsOverWss() async throws {
    for (scene, roomID) in [(PteIMSceneKind.show, "sdk-e2e-show"), (PteIMSceneKind.voice, "sdk-e2e-voice"), (PteIMSceneKind.shop, "sdk-e2e-shop")] {
      let chat = try await normalSDK(userId: "91000001", deviceID: "ios-sdk-scene-\(scene.rawValue)")
      let credential = try await issueUserSig(userId: "91000001", deviceID: "ios-sdk-scene-\(scene.rawValue)", scene: scene.rawValue, roomID: roomID)
      let client = chat.createSceneClient()
      defer { client.disconnect(); chat.stop() }
      try await client.connect(userId: credential.userID, userSig: credential.userSig, expireAt: credential.expireAt)
      let entered = try await client.enter(scene: scene, roomId: roomID)
      XCTAssertEqual(entered.scene, scene)
      XCTAssertEqual(entered.roomId, roomID)
    }
  }

  func testNormalSportsUserEntersBoundSportsRoomOverWss() async throws {
    let chat = try await normalSDK(userId: "91000001", deviceID: "ios-sdk-sports", appID: 20_001)
    let credential = try await issueUserSig(userId: "91000001", deviceID: "ios-sdk-sports", appID: 20_001, scene: "sports", roomID: "sports-live-910001")
    let client = chat.createSceneClient()
    defer { client.disconnect(); chat.stop() }
    try await client.connect(userId: credential.userID, userSig: credential.userSig, expireAt: credential.expireAt)
    let entered = try await client.enter(scene: .sports, roomId: "sports-live-910001")
    XCTAssertEqual(entered.scene, .sports)
    XCTAssertEqual(entered.roomId, "sports-live-910001")
  }

  private func normalSDK(userId: String, deviceID: String, appID: Int64 = 10_001) async throws -> PteIMSDK {
    let credential = try await issueUserSig(userId: userId, deviceID: deviceID, appID: appID)
    let base = try PteIMBaseConfig(apiDomain: apiDomain, imDomain: imDomain, cosDomain: cosDomain, commerceDomain: commerceDomain)
    let login = try PteIMLoginConfig(sdkAppId: credential.sdkAppID, userId: credential.userID, userSig: credential.userSig, userSigExpireAt: credential.expireAt)
    let sdk = try PteIMSDK(config: PteIMSessionConfig(base: base, login: login), persistentCache: false)
    sdk.start()
    return sdk
  }

  private func issueUserSig(userId: String, deviceID: String, appID: Int64 = 10_001, scene: String? = nil, roomID: String? = nil) async throws -> Credential {
    let key = PteIMResponseCipher.requestKey()
    var body: [String: Any] = [
      "app_id": String(appID), "user_id": userId, "identifier": userId,
      "user_type": "user", "device_id": deviceID, "platform": "ios", "expire": 3600,
    ]
    if let scene { body["scene"] = scene }
    if let roomID { body["room_id"] = roomID }
    var request = URLRequest(url: URL(string: "\(apiDomain)/api/v1/im/usersig")!)
    request.httpMethod = "POST"
    request.httpBody = try JSONSerialization.data(withJSONObject: body)
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.setValue(PteIMResponseCipher.requestPublicKey(key), forHTTPHeaderField: "X-Pte-Response-Public-Key")
    let (encrypted, response) = try await URLSession.shared.data(for: request)
    guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw AcceptanceError.userSigRequestFailed }
    let clear = try PteIMResponseCipher.decrypt(encrypted, with: key)
    let root = try JSONDecoder().decode(UserSigEnvelope.self, from: clear)
    guard root.code == 1, let data = root.data else { throw AcceptanceError.userSigRequestFailed }
    return Credential(sdkAppID: data.sdkAppID, userID: data.userID, userSig: data.userSig, expireAt: data.expireAt)
  }

  private func waitUntil(_ condition: @escaping () -> Bool, timeoutSeconds: Int = 25) async -> Bool {
    let deadline = Date().addingTimeInterval(TimeInterval(timeoutSeconds))
    while Date() < deadline {
      if condition() { return true }
      try? await Task.sleep(nanoseconds: 100_000_000)
    }
    return condition()
  }
}

private struct Credential {
  let sdkAppID: Int64
  let userID: String
  let userSig: String
  let expireAt: Int64
}

private struct UserSigEnvelope: Decodable {
  let code: Int
  let data: UserSigPayload?
}

private struct UserSigPayload: Decodable {
  let sdkAppID: Int64
  let userID: String
  let userSig: String
  let expireAt: Int64
  enum CodingKeys: String, CodingKey {
    case sdkAppID = "sdk_app_id"
    case userID = "user_id"
    case userSig = "user_sig"
    case expireAt = "expire_at"
  }

  init(from decoder: Decoder) throws {
    let values = try decoder.container(keyedBy: CodingKeys.self)
    userID = try values.decode(String.self, forKey: .userID)
    userSig = try values.decode(String.self, forKey: .userSig)
    if let value = try? values.decode(Int64.self, forKey: .sdkAppID) {
      sdkAppID = value
    } else {
      sdkAppID = Int64(try values.decode(String.self, forKey: .sdkAppID)) ?? 0
    }
    if let value = try? values.decode(Int64.self, forKey: .expireAt) {
      expireAt = value
    } else {
      expireAt = Int64(try values.decode(String.self, forKey: .expireAt)) ?? 0
    }
    guard sdkAppID > 0, expireAt > 0 else { throw AcceptanceError.userSigRequestFailed }
  }
}

private enum AcceptanceError: Error { case userSigRequestFailed }

private final class AcceptanceErrorBox: @unchecked Sendable {
  private let lock = NSLock()
  private var stored: [String] = []
  func append(_ value: String) { lock.lock(); stored.append(value); lock.unlock() }
  var values: [String] { lock.lock(); defer { lock.unlock() }; return stored }
}

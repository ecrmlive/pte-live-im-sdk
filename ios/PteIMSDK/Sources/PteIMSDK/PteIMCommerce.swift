import Foundation

/** First-party Commerce extension. It reuses UserSig; it never creates a second IM connection. */
public final class PteIMCommerce: @unchecked Sendable {
  private unowned let sdk: PteIMSDK
  internal init(sdk: PteIMSDK) { self.sdk = sdk }

  public func capabilities() async throws -> PteIMCommerceCapability {
    try decode(try await sdk.commercePayload(path: "v1/commerce/capabilities", body: [:]))
  }
  public func gifts() async throws -> [PteIMGift] { try list(try await sdk.commercePayload(path: "v1/commerce/gifts", body: [:])) }
  public func wallet() async throws -> PteIMWallet { try decode(try await sdk.commercePayload(path: "v1/commerce/wallet", body: [:])) }
  public func backpack() async throws -> [PteIMBackpackItem] { try list(try await sdk.commercePayload(path: "v1/commerce/backpack", body: [:])) }
  public func orders(limit: Int = 50) async throws -> [PteIMCommerceOrder] { try list(try await sdk.commercePayload(path: "v1/commerce/orders", body: ["limit": limit])) }
  public func sendGift(_ request: PteIMGiftSendRequest) async throws -> PteIMCommerceOrder { try decode(try await sdk.commercePayload(path: "v1/commerce/gifts/send", body: request.json)) }
  public func useBackpack(_ request: PteIMBackpackUseRequest) async throws -> PteIMCommerceOrder { try decode(try await sdk.commercePayload(path: "v1/commerce/backpack/use", body: request.json)) }
  public func createRedPacket(_ request: PteIMRedPacketCreateRequest) async throws -> PteIMRedPacket { try decode(try await sdk.commercePayload(path: "v1/commerce/red-packets/create", body: request.json)) }
  public func redPacket(_ id: String) async throws -> PteIMRedPacketDetail { try decode(try await sdk.commercePayload(path: "v1/commerce/red-packets/\(id)", body: [:])) }
  public func claimRedPacket(_ id: String) async throws -> PteIMRedPacketDetail { try decode(try await sdk.commercePayload(path: "v1/commerce/red-packets/\(id)/claim", body: [:])) }

  private func decode<T: Decodable>(_ value: Any) throws -> T { try JSONDecoder().decode(T.self, from: JSONSerialization.data(withJSONObject: value)) }
  private func list<T: Decodable>(_ value: Any) throws -> [T] {
    guard let object = value as? [String: Any], let rows = object["list"] else { throw PteIMError.invalidResponse }
    return try JSONDecoder().decode([T].self, from: JSONSerialization.data(withJSONObject: rows))
  }
}

public struct PteIMCommerceCapability: Codable, Sendable { public let version: Int; public let currency: String; public let gifts: Bool; public let backpack: Bool; public let orders: Bool; public let redPackets: Bool }
public struct PteIMGift: Codable, Sendable { public let sku: String; public let title: String; public let coverURL: String; public let unitAmount: Int64; public let currency: String; enum CodingKeys: String, CodingKey { case sku, title, currency; case coverURL = "cover_url"; case unitAmount = "unit_amount" } }
public struct PteIMWallet: Codable, Sendable { public let balance: Int64; public let currency: String }
public struct PteIMBackpackItem: Codable, Sendable { public let sku: String; public let title: String; public let coverURL: String; public let quantity: Int64; public let expiresAt: Int64; enum CodingKeys: String, CodingKey { case sku, title, quantity; case coverURL = "cover_url"; case expiresAt = "expires_at" } }
public struct PteIMCommerceOrder: Codable, Sendable { public let orderID: String; public let type: String; public let resourceID: String; public let amount: Int64; public let currency: String; public let status: Int; public let snapshot: String; enum CodingKeys: String, CodingKey { case type, amount, currency, status, snapshot; case orderID = "order_id"; case resourceID = "resource_id" } }
public struct PteIMRedPacket: Codable, Sendable { public let redPacketID: String; public let roomID: String; public let mode: String; public let greeting: String; public let totalAmount: Int64; public let totalCount: Int; public let remainingAmount: Int64; public let remainingCount: Int; public let currency: String; public let status: Int; public let expiresAt: Int64; enum CodingKeys: String, CodingKey { case mode, greeting, currency, status; case redPacketID = "red_packet_id"; case roomID = "room_id"; case totalAmount = "total_amount"; case totalCount = "total_count"; case remainingAmount = "remaining_amount"; case remainingCount = "remaining_count"; case expiresAt = "expires_at" } }
public struct PteIMRedPacketClaim: Codable, Sendable { public let amount: Int64 }
public struct PteIMRedPacketDetail: Codable, Sendable { public let redPacket: PteIMRedPacket; public let myClaim: PteIMRedPacketClaim?; public let claim: PteIMRedPacketClaim? }
public struct PteIMGiftSendRequest: Sendable { public let clientRequestId: String; public let sku: String; public let quantity: Int64; public let targetUserId: Int64; public let sceneType: String; public let roomId: String; public init(clientRequestId: String, sku: String, quantity: Int64, targetUserId: Int64 = 0, sceneType: String = "", roomId: String = "") { self.clientRequestId = clientRequestId; self.sku = sku; self.quantity = quantity; self.targetUserId = targetUserId; self.sceneType = sceneType; self.roomId = roomId }; fileprivate var json: [String: Any] { ["clientRequestId": clientRequestId, "sku": sku, "quantity": quantity, "targetUserId": targetUserId, "sceneType": sceneType, "roomId": roomId] } }
public struct PteIMBackpackUseRequest: Sendable { public let clientRequestId: String; public let sku: String; public let quantity: Int64; public let sceneType: String; public let roomId: String; public init(clientRequestId: String, sku: String, quantity: Int64, sceneType: String = "", roomId: String = "") { self.clientRequestId = clientRequestId; self.sku = sku; self.quantity = quantity; self.sceneType = sceneType; self.roomId = roomId }; fileprivate var json: [String: Any] { ["clientRequestId": clientRequestId, "sku": sku, "quantity": quantity, "sceneType": sceneType, "roomId": roomId] } }
public struct PteIMRedPacketCreateRequest: Sendable { public let clientRequestId: String; public let roomId: String; public let totalAmount: Int64; public let totalCount: Int; public let mode: String; public let greeting: String; public let sceneType: String; public let expiresIn: Int64; public init(clientRequestId: String, roomId: String, totalAmount: Int64, totalCount: Int, mode: String = "lucky", greeting: String = "", sceneType: String = "live", expiresIn: Int64 = 86400) { self.clientRequestId = clientRequestId; self.roomId = roomId; self.totalAmount = totalAmount; self.totalCount = totalCount; self.mode = mode; self.greeting = greeting; self.sceneType = sceneType; self.expiresIn = expiresIn }; fileprivate var json: [String: Any] { ["clientRequestId": clientRequestId, "roomId": roomId, "totalAmount": totalAmount, "totalCount": totalCount, "mode": mode, "greeting": greeting, "sceneType": sceneType, "expiresIn": expiresIn] } }

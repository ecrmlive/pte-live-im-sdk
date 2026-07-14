import Foundation

public enum PteIMThemeMode: String, Sendable { case system, light, dark }
public enum PteIMLanguage: String, Sendable { case system, zhCN = "zh-CN", enUS = "en-US" }
public struct PteIMAppearance: Sendable {
  public let themeMode: PteIMThemeMode
  public let language: PteIMLanguage
  public init(themeMode: PteIMThemeMode, language: PteIMLanguage) { self.themeMode = themeMode; self.language = language }
}

public struct PteIMBaseConfig: Sendable {
  public let apiDomain: URL
  public let imDomain: URL
  public let cosDomain: URL
  public let themeMode: PteIMThemeMode
  public let language: PteIMLanguage
  public init(apiDomain: String, imDomain: String, cosDomain: String, themeMode: PteIMThemeMode = .system, language: PteIMLanguage = .system) throws {
    guard let api = URL(string: apiDomain), api.scheme == "https", api.host != nil,
          api.path.isEmpty || api.path == "/" else { throw PteIMError.invalidApiDomain }
    guard let im = URL(string: imDomain), im.scheme == "wss", im.host != nil, im.path == "/ws" else {
      throw PteIMError.invalidImDomain
    }
    guard let cos = URL(string: cosDomain), cos.scheme == "https", cos.host != nil else { throw PteIMError.invalidApiDomain }
    self.apiDomain = api
    self.imDomain = im
    self.cosDomain = cos
    self.themeMode = themeMode; self.language = language
  }
}

public struct PteIMLoginConfig: Sendable {
  public let sdkAppId: Int64
  public let userId: String
  public var userSig: String
  public init(sdkAppId: Int64, userId: String, userSig: String) throws {
    guard sdkAppId > 0, let numericUserId = UInt64(userId), numericUserId > 0, !userSig.isEmpty else { throw PteIMError.invalidCredentials }
    self.sdkAppId = sdkAppId; self.userId = userId; self.userSig = userSig
  }
}

public struct PteIMSessionConfig: Sendable {
  public let base: PteIMBaseConfig
  public var login: PteIMLoginConfig
  public init(base: PteIMBaseConfig, login: PteIMLoginConfig) { self.base = base; self.login = login }
  var apiDomain: URL { base.apiDomain }; var imDomain: URL { base.imDomain }; var cosDomain: URL { base.cosDomain }
  var sdkAppId: Int64 { login.sdkAppId }; var userId: String { login.userId }
  var userSig: String { get { login.userSig } set { login.userSig = newValue } }
  var storeKey: String { "\(base.apiDomain.absoluteString.lowercased())|\(base.imDomain.absoluteString.lowercased())|\(base.cosDomain.absoluteString.lowercased())|\(login.sdkAppId)|\(login.userId)" }
}

public enum PteIMError: Error { case invalidApiDomain, invalidImDomain, invalidCredentials, disconnected, invalidResponse }
public enum PteIMMessageType: String, Codable, Sendable { case text, emoji, image, video, voice, location, gift, red_packet, order }
public enum PteIMSendState: String, Codable, Sendable { case pending, uploading, sent, failed }

public struct PteIMMedia: Codable, Sendable {
  public var url: String?
  public var thumbnailUrl: String?
  public var coverUrl: String?
  public var width: Int?
  public var height: Int?
  public var durationMs: Int64?
  public var sizeBytes: Int64?
  public init(url: String? = nil, thumbnailUrl: String? = nil, coverUrl: String? = nil, width: Int? = nil, height: Int? = nil, durationMs: Int64? = nil, sizeBytes: Int64? = nil) {
    self.url = url; self.thumbnailUrl = thumbnailUrl; self.coverUrl = coverUrl; self.width = width; self.height = height; self.durationMs = durationMs; self.sizeBytes = sizeBytes
  }
}
public struct PteIMVoice: Codable, Sendable {
  public var url: String; public var durationMs: Int64; public var waveform: String?; public var sizeBytes: Int64?
  public init(url: String, durationMs: Int64, waveform: String? = nil, sizeBytes: Int64? = nil) { self.url = url; self.durationMs = durationMs; self.waveform = waveform; self.sizeBytes = sizeBytes }
}
public struct PteIMLocation: Codable, Sendable {
  public var latitude: Double; public var longitude: Double; public var name: String; public var address: String?
  public init(latitude: Double, longitude: Double, name: String, address: String? = nil) { self.latitude = latitude; self.longitude = longitude; self.name = name; self.address = address }
}
public struct PteIMBusinessContent: Codable, Sendable {
  public var businessId: String; public var title: String; public var subtitle: String?; public var actionUrl: String?
  public init(businessId: String, title: String, subtitle: String? = nil, actionUrl: String? = nil) { self.businessId = businessId; self.title = title; self.subtitle = subtitle; self.actionUrl = actionUrl }
}

/** Locally cached conversation summary. Group/C2C semantics are supplied by the server conversation ID. */
public struct PteIMConversation: Sendable {
  public let conversationId: String
  public let lastMessage: PteIMMessage
  public let updatedAt: Int64
  public init(conversationId: String, lastMessage: PteIMMessage, updatedAt: Int64) { self.conversationId = conversationId; self.lastMessage = lastMessage; self.updatedAt = updatedAt }
}

/** Server-authoritative conversation item returned by the SDK paging API. */
public struct PteIMRemoteConversation: Codable, Sendable {
  public let id: Int64; public let type: String; public let title: String; public let avatar: String?
  public let lastMessageSeq: Int64; public let lastMessageSnapshot: String?; public let lastMessageAt: Int64; public let unreadCount: Int64
  enum CodingKeys: String, CodingKey { case id, type, title, avatar; case lastMessageSeq = "last_message_seq"; case lastMessageSnapshot = "last_message_snapshot"; case lastMessageAt = "last_message_at"; case unreadCount = "unread_count" }
}
public struct PteIMConversationPage: Codable, Sendable { public let total: Int64; public let list: [PteIMRemoteConversation] }

/** Server-authoritative history item returned by the SDK paging API. */
public struct PteIMRemoteMessage: Decodable, Sendable {
  public let messageId: Int64; public let conversationId: Int64; public let senderId: Int64; public let clientMsgId: String
  public let type: String; public let content: String; public let payload: String?; public let seq: Int64; public let sentAt: Int64; public let recalledAt: Int64?
  enum CodingKeys: String, CodingKey { case type, content, payload, seq; case messageId = "message_id"; case conversationId = "conversation_id"; case senderId = "sender_id"; case clientMsgId = "client_msg_id"; case sentAt = "sent_at"; case recalledAt = "recalled_at"; case messageType = "msg_type" }
  public init(from decoder: Decoder) throws {
    let value = try decoder.container(keyedBy: CodingKeys.self)
    messageId = try value.decode(Int64.self, forKey: .messageId); conversationId = try value.decode(Int64.self, forKey: .conversationId); senderId = try value.decode(Int64.self, forKey: .senderId); clientMsgId = try value.decode(String.self, forKey: .clientMsgId)
    type = try value.decode(String.self, forKey: .messageType); content = try value.decode(String.self, forKey: .content); payload = try value.decodeIfPresent(String.self, forKey: .payload); seq = try value.decode(Int64.self, forKey: .seq); sentAt = try value.decode(Int64.self, forKey: .sentAt); recalledAt = try value.decodeIfPresent(Int64.self, forKey: .recalledAt)
  }
}
public struct PteIMMessagePage: Decodable, Sendable { public let list: [PteIMRemoteMessage] }

public struct PteIMMessage: Codable, Sendable {
  public let clientMsgId: String
  public var serverMsgId: String? = nil
  public let conversationId: String
  public let type: PteIMMessageType
  public let createdAt: Int64
  public var serverSeq: Int64? = nil
  public var text: String?
  public var packageId: String?
  public var emojiId: String?
  public var media: PteIMMedia?
  public var voice: PteIMVoice? = nil
  public var location: PteIMLocation? = nil
  public var business: PteIMBusinessContent? = nil
  public var state: PteIMSendState

  public init(conversationId: String, type: PteIMMessageType, text: String? = nil, packageId: String? = nil, emojiId: String? = nil, media: PteIMMedia? = nil, voice: PteIMVoice? = nil, location: PteIMLocation? = nil, business: PteIMBusinessContent? = nil, clientMsgId: String = UUID().uuidString, createdAt: Int64 = Int64(Date().timeIntervalSince1970 * 1000), state: PteIMSendState = .pending) {
    self.clientMsgId = clientMsgId; self.conversationId = conversationId; self.type = type; self.text = text; self.packageId = packageId; self.emojiId = emojiId; self.media = media; self.voice = voice; self.location = location; self.business = business; self.createdAt = createdAt; self.state = state
  }

  enum CodingKeys: String, CodingKey { case clientMsgId, serverMsgId, conversationId, type, createdAt, serverSeq, content }
  enum ContentKeys: String, CodingKey { case text, packageId, emojiId, url, thumbnailUrl, coverUrl, width, height, durationMs, sizeBytes, waveform, latitude, longitude, name, address, businessId, title, subtitle, actionUrl }

  public init(from decoder: Decoder) throws {
    let root = try decoder.container(keyedBy: CodingKeys.self)
    clientMsgId = try root.decode(String.self, forKey: .clientMsgId); serverMsgId = try root.decodeIfPresent(String.self, forKey: .serverMsgId)
    conversationId = try root.decode(String.self, forKey: .conversationId); type = try root.decode(PteIMMessageType.self, forKey: .type)
    createdAt = try root.decode(Int64.self, forKey: .createdAt); serverSeq = try root.decodeIfPresent(Int64.self, forKey: .serverSeq)
    let content = try root.nestedContainer(keyedBy: ContentKeys.self, forKey: .content)
    text = try content.decodeIfPresent(String.self, forKey: .text); packageId = try content.decodeIfPresent(String.self, forKey: .packageId); emojiId = try content.decodeIfPresent(String.self, forKey: .emojiId)
    media = type == .image || type == .video ? PteIMMedia(url: try content.decodeIfPresent(String.self, forKey: .url), thumbnailUrl: try content.decodeIfPresent(String.self, forKey: .thumbnailUrl), coverUrl: try content.decodeIfPresent(String.self, forKey: .coverUrl), width: try content.decodeIfPresent(Int.self, forKey: .width), height: try content.decodeIfPresent(Int.self, forKey: .height), durationMs: try content.decodeIfPresent(Int64.self, forKey: .durationMs), sizeBytes: try content.decodeIfPresent(Int64.self, forKey: .sizeBytes)) : nil
    voice = type == .voice ? try content.decodeIfPresent(String.self, forKey: .url).map { PteIMVoice(url: $0, durationMs: try content.decode(Int64.self, forKey: .durationMs), waveform: try content.decodeIfPresent(String.self, forKey: .waveform), sizeBytes: try content.decodeIfPresent(Int64.self, forKey: .sizeBytes)) } : nil
    location = type == .location ? try content.decodeIfPresent(Double.self, forKey: .latitude).map { latitude in PteIMLocation(latitude: latitude, longitude: try content.decode(Double.self, forKey: .longitude), name: try content.decode(String.self, forKey: .name), address: try content.decodeIfPresent(String.self, forKey: .address)) } : nil
    business = (type == .gift || type == .red_packet || type == .order) ? try content.decodeIfPresent(String.self, forKey: .businessId).map { id in PteIMBusinessContent(businessId: id, title: try content.decode(String.self, forKey: .title), subtitle: try content.decodeIfPresent(String.self, forKey: .subtitle), actionUrl: try content.decodeIfPresent(String.self, forKey: .actionUrl)) } : nil
    state = .sent
  }

  public func encode(to encoder: Encoder) throws {
    var root = encoder.container(keyedBy: CodingKeys.self)
    try root.encode(clientMsgId, forKey: .clientMsgId); try root.encodeIfPresent(serverMsgId, forKey: .serverMsgId); try root.encode(conversationId, forKey: .conversationId)
    try root.encode(type, forKey: .type); try root.encode(createdAt, forKey: .createdAt); try root.encodeIfPresent(serverSeq, forKey: .serverSeq)
    var content = root.nestedContainer(keyedBy: ContentKeys.self, forKey: .content)
    try content.encodeIfPresent(text, forKey: .text); try content.encodeIfPresent(packageId, forKey: .packageId); try content.encodeIfPresent(emojiId, forKey: .emojiId)
    try content.encodeIfPresent(media?.url, forKey: .url); try content.encodeIfPresent(media?.thumbnailUrl, forKey: .thumbnailUrl); try content.encodeIfPresent(media?.coverUrl, forKey: .coverUrl)
    try content.encodeIfPresent(media?.width, forKey: .width); try content.encodeIfPresent(media?.height, forKey: .height); try content.encodeIfPresent(media?.durationMs, forKey: .durationMs); try content.encodeIfPresent(media?.sizeBytes, forKey: .sizeBytes)
    try content.encodeIfPresent(voice?.url, forKey: .url); try content.encodeIfPresent(voice?.durationMs, forKey: .durationMs); try content.encodeIfPresent(voice?.waveform, forKey: .waveform); try content.encodeIfPresent(voice?.sizeBytes, forKey: .sizeBytes)
    try content.encodeIfPresent(location?.latitude, forKey: .latitude); try content.encodeIfPresent(location?.longitude, forKey: .longitude); try content.encodeIfPresent(location?.name, forKey: .name); try content.encodeIfPresent(location?.address, forKey: .address)
    try content.encodeIfPresent(business?.businessId, forKey: .businessId); try content.encodeIfPresent(business?.title, forKey: .title); try content.encodeIfPresent(business?.subtitle, forKey: .subtitle); try content.encodeIfPresent(business?.actionUrl, forKey: .actionUrl)
  }

  /** JSON representation of the type-specific message content for language bridges. */
  public func contentJSON() -> String {
    var content: [String: Any] = [:]
    if let text { content["text"] = text }; if let packageId { content["packageId"] = packageId }; if let emojiId { content["emojiId"] = emojiId }
    if let media { if let url = media.url { content["url"] = url }; if let thumbnailUrl = media.thumbnailUrl { content["thumbnailUrl"] = thumbnailUrl }; if let coverUrl = media.coverUrl { content["coverUrl"] = coverUrl }; if let width = media.width { content["width"] = width }; if let height = media.height { content["height"] = height }; if let durationMs = media.durationMs { content["durationMs"] = durationMs }; if let sizeBytes = media.sizeBytes { content["sizeBytes"] = sizeBytes } }
    if let voice { content["url"] = voice.url; content["durationMs"] = voice.durationMs; if let waveform = voice.waveform { content["waveform"] = waveform }; if let sizeBytes = voice.sizeBytes { content["sizeBytes"] = sizeBytes } }
    if let location { content["latitude"] = location.latitude; content["longitude"] = location.longitude; content["name"] = location.name; if let address = location.address { content["address"] = address } }
    if let business { content["businessId"] = business.businessId; content["title"] = business.title; if let subtitle = business.subtitle { content["subtitle"] = subtitle }; if let actionURL = business.actionUrl { content["actionUrl"] = actionURL } }
    return String(data: (try? JSONSerialization.data(withJSONObject: content)) ?? Data("{}".utf8), encoding: .utf8) ?? "{}"
  }
}

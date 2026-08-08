import Foundation

/**
 The user's theme preference. `.system` is the SDK's automatic mode: light
 from 07:00 (inclusive) until 19:00 (exclusive) in the device's local time,
 and dark at all other times.
 */
public enum PteIMThemeMode: String, Sendable { case system, light, dark }
/** `.system` resolves from the device's preferred language. */
public enum PteIMLanguage: String, Sendable { case system, zhCN = "zh-CN", enUS = "en-US" }
public struct PteIMAppearance: Sendable {
  public let themeMode: PteIMThemeMode
  public let language: PteIMLanguage
  public init(themeMode: PteIMThemeMode, language: PteIMLanguage) { self.themeMode = themeMode; self.language = language }

  /** The concrete light/dark value to render at the supplied local date. */
  public func resolvedTheme(at date: Date = Date(), calendar: Calendar = .current) -> PteIMTheme {
    switch themeMode {
    case .light: return .light
    case .dark: return .dark
    case .system:
      let hour = calendar.component(.hour, from: date)
      return (7..<19).contains(hour) ? .light : .dark
    }
  }

  /** The concrete SDK language; unsupported system languages use English. */
  public func resolvedLanguage(locale: Locale? = nil) -> PteIMLanguage {
    language.resolved(locale: locale)
  }
}

public extension PteIMLanguage {
  /** Resolves system language to the two languages provided by PteIMUIKit. */
  func resolved(locale: Locale? = nil) -> PteIMLanguage {
    guard self == .system else { return self }
    let identifier = locale?.identifier ?? Locale.preferredLanguages.first ?? Locale.current.identifier
    return identifier.lowercased().hasPrefix("zh") ? .zhCN : .enUS
  }
}

/** Public defaults for [PteIMBaseConfig]. Hosts may override any field. */
public enum PteIMDefaultDomains {
  public static let api = "https://api-im.qxkejiwl.top"
  public static let im = "wss://wss.qxkejiwl.top/ws"
  public static let cos = "https://cos.qxkejiwl.top"
  public static let commerce = "https://api-im-commerce.qxkejiwl.top"
}

public struct PteIMBaseConfig: Sendable {
  public let apiDomain: URL
  public let imDomain: URL
  public let cosDomain: URL
  /** Optional HTTPS Commerce origin. Defaults to the public host; pass `nil` to disable. */
  public let commerceDomain: URL?
  public let themeMode: PteIMThemeMode
  public let language: PteIMLanguage
  /** Explicit development-only opt-in for a local Docker stack. */
  public let allowInsecureLocalhost: Bool

  public init(
    apiDomain: String = PteIMDefaultDomains.api,
    imDomain: String = PteIMDefaultDomains.im,
    cosDomain: String = PteIMDefaultDomains.cos,
    commerceDomain: String? = PteIMDefaultDomains.commerce,
    themeMode: PteIMThemeMode = .system,
    language: PteIMLanguage = .system,
    allowInsecureLocalhost: Bool = false
  ) throws {
    func allowsInsecureLocalhost(_ url: URL, scheme: String) -> Bool {
      guard allowInsecureLocalhost, url.scheme == scheme, let host = url.host?.lowercased() else { return false }
      return host == "localhost" || host == "127.0.0.1" || host == "::1"
    }

    guard let api = URL(string: apiDomain), (api.scheme == "https" || allowsInsecureLocalhost(api, scheme: "http")), api.host != nil,
          api.path.isEmpty || api.path == "/" else { throw PteIMError.invalidApiDomain }
    guard let im = URL(string: imDomain), (im.scheme == "wss" || allowsInsecureLocalhost(im, scheme: "ws")), im.host != nil, im.path == "/ws" else {
      throw PteIMError.invalidImDomain
    }
    guard let cos = URL(string: cosDomain), (cos.scheme == "https" || allowsInsecureLocalhost(cos, scheme: "http")), cos.host != nil else { throw PteIMError.invalidApiDomain }
    let commerce: URL?
    if let commerceDomain, !commerceDomain.isEmpty {
      guard let value = URL(string: commerceDomain), (value.scheme == "https" || allowsInsecureLocalhost(value, scheme: "http")), value.host != nil,
            value.path.isEmpty || value.path == "/" else { throw PteIMError.invalidApiDomain }
      commerce = value
    } else { commerce = nil }
    self.apiDomain = api
    self.imDomain = im
    self.cosDomain = cos
    self.commerceDomain = commerce
    self.themeMode = themeMode; self.language = language; self.allowInsecureLocalhost = allowInsecureLocalhost
  }
}

public struct PteIMUserSigRefreshResult: Sendable {
  public let userSig: String
  public let expireAt: Int64
  public init(userSig: String, expireAt: Int64) { self.userSig = userSig; self.expireAt = expireAt }
}

/** Host business-auth bridge. It returns a renewed credential without exposing any IM signing secret. */
public typealias PteIMUserSigProvider = @Sendable () async throws -> PteIMUserSigRefreshResult

public struct PteIMLoginConfig: Sendable {
  public let sdkAppId: Int64
  public let userId: String
  public var userSig: String
  public var userSigExpireAt: Int64
  public let userSigProvider: PteIMUserSigProvider?
  public init(sdkAppId: Int64, userId: String, userSig: String, userSigExpireAt: Int64 = 0, userSigProvider: PteIMUserSigProvider? = nil) throws {
    guard sdkAppId > 0, let numericUserId = UInt64(userId), numericUserId > 0, !userSig.isEmpty else { throw PteIMError.invalidCredentials }
    self.sdkAppId = sdkAppId; self.userId = userId; self.userSig = userSig; self.userSigExpireAt = userSigExpireAt; self.userSigProvider = userSigProvider
  }
}

public struct PteIMSessionConfig: Sendable {
  public let base: PteIMBaseConfig
  public var login: PteIMLoginConfig
  public init(base: PteIMBaseConfig, login: PteIMLoginConfig) { self.base = base; self.login = login }
  var apiDomain: URL { base.apiDomain }; var imDomain: URL { base.imDomain }; var cosDomain: URL { base.cosDomain }; var commerceDomain: URL? { base.commerceDomain }
  var sdkAppId: Int64 { login.sdkAppId }; var userId: String { login.userId }
  var userSig: String { get { login.userSig } set { login.userSig = newValue } }
  var userSigExpireAt: Int64 { get { login.userSigExpireAt } set { login.userSigExpireAt = newValue } }
  var userSigProvider: PteIMUserSigProvider? { login.userSigProvider }
  var storeKey: String { "\(base.apiDomain.absoluteString.lowercased())|\(base.imDomain.absoluteString.lowercased())|\(base.cosDomain.absoluteString.lowercased())|\(login.sdkAppId)|\(login.userId)" }
}

public enum PteIMError: Error { case invalidApiDomain, invalidImDomain, invalidCredentials, invalidConversationId, disconnected, invalidResponse, commerceNotConfigured }
public enum PteIMMessageType: String, Codable, Sendable { case text, emoji, image, video, voice, location, gift, red_packet, order, file }
public enum PteIMSendState: String, Codable, Sendable { case pending, uploading, sent, failed }
/** Provider/runtime selected by the host application when registering a push token. */
public enum PteIMPushPlatform: String, Codable, Sendable { case android, ios, harmony, web, wechat }
/** Token-free device registration result. The token is never retained in this value. */
public struct PteIMPushDevice: Codable, Sendable, Equatable {
  public let deviceId: String
  public let platform: PteIMPushPlatform
  public let notificationEnabled: Bool
  public let lastSeenAt: Int64
}

/** Server-authoritative IM profile for the currently authenticated user. */
public struct PteIMUserProfile: Codable, Sendable, Equatable {
  public let userId: Int64
  public var nickname: String?
  public var avatar: String?
  public var gender: PteIMGender
  /** ISO-8601 calendar date (`YYYY-MM-DD`), if supplied by the business app. */
  public var birthday: String?
  public var province: String?
  public var city: String?
  public var district: String?
  public init(userId: Int64, nickname: String? = nil, avatar: String? = nil, gender: PteIMGender = .unknown, birthday: String? = nil, province: String? = nil, city: String? = nil, district: String? = nil) {
    self.userId = userId; self.nickname = nickname; self.avatar = avatar; self.gender = gender; self.birthday = birthday; self.province = province; self.city = city; self.district = district
  }
  enum CodingKeys: String, CodingKey { case userId = "user_id"; case nickname, avatar, gender, birthday, province, city, district }
}

public enum PteIMGender: String, Codable, Sendable { case unknown, male, female }

public struct PteIMContact: Codable, Sendable, Equatable {
  public let userId: String; public let remark: String; public let nickname: String; public let avatar: String; public let gender: PteIMGender; public let followedAt: Int64
}
public struct PteIMContactPage: Codable, Sendable, Equatable { public let list: [PteIMContact]; public let nextCursor: String; public let hasMore: Bool }
public struct PteIMGroupPage: Codable, Sendable { public let list: [PteIMRemoteConversation]; public let nextCursor: String; public let hasMore: Bool }
public struct PteIMMember: Codable, Sendable { public let userId: Int64; public let role: Int; public let alias: String; public let muteUntil: Int64; public let joinedAt: Int64; enum CodingKeys: String, CodingKey { case role, alias; case userId = "user_id"; case muteUntil = "mute_until"; case joinedAt = "joined_at" } }
public struct PteIMMemberPage: Codable, Sendable { public let list: [PteIMMember]; public let nextCursor: String; public let hasMore: Bool }
public struct PteIMStateChange: Codable, Sendable {
  public let id: String
  public let entityType: String
  public let entityId: String
  public let operation: String
  /// State-sync payloads originate from several IM entities and may contain
  /// numeric, boolean, or nested JSON values. They are normalized to strings
  /// so callers keep the original SDK surface without decode failures.
  public let payload: [String: String]?
  public let createdAt: Int64

  enum CodingKeys: String, CodingKey { case id, entityType, entityId, operation, payload, createdAt }

  public init(from decoder: Decoder) throws {
    let values = try decoder.container(keyedBy: CodingKeys.self)
    id = try values.decode(String.self, forKey: .id)
    entityType = try values.decode(String.self, forKey: .entityType)
    entityId = try values.decode(String.self, forKey: .entityId)
    operation = try values.decode(String.self, forKey: .operation)
    createdAt = try values.decode(Int64.self, forKey: .createdAt)
    payload = try values.decodeIfPresent([String: PteIMStatePayloadValue].self, forKey: .payload)?.reduce(into: [:]) { result, item in
      result[item.key] = item.value.stringValue
    }
  }

  public func encode(to encoder: Encoder) throws {
    var values = encoder.container(keyedBy: CodingKeys.self)
    try values.encode(id, forKey: .id)
    try values.encode(entityType, forKey: .entityType)
    try values.encode(entityId, forKey: .entityId)
    try values.encode(operation, forKey: .operation)
    try values.encodeIfPresent(payload, forKey: .payload)
    try values.encode(createdAt, forKey: .createdAt)
  }
}

private indirect enum PteIMStatePayloadValue: Codable {
  case string(String), number(Double), bool(Bool), object([String: PteIMStatePayloadValue]), array([PteIMStatePayloadValue]), null

  init(from decoder: Decoder) throws {
    let single = try decoder.singleValueContainer()
    if single.decodeNil() { self = .null }
    else if let value = try? single.decode(String.self) { self = .string(value) }
    else if let value = try? single.decode(Bool.self) { self = .bool(value) }
    else if let value = try? single.decode(Double.self) { self = .number(value) }
    else if let value = try? decoder.container(keyedBy: DynamicCodingKey.self) {
      var object: [String: PteIMStatePayloadValue] = [:]
      for key in value.allKeys { object[key.stringValue] = try value.decode(PteIMStatePayloadValue.self, forKey: key) }
      self = .object(object)
    } else if var array = try? decoder.unkeyedContainer() {
      var values: [PteIMStatePayloadValue] = []
      while !array.isAtEnd { values.append(try array.decode(PteIMStatePayloadValue.self)) }
      self = .array(values)
    } else { throw PteIMError.invalidResponse }
  }

  func encode(to encoder: Encoder) throws {
    switch self {
    case .string(let value): var container = encoder.singleValueContainer(); try container.encode(value)
    case .number(let value): var container = encoder.singleValueContainer(); try container.encode(value)
    case .bool(let value): var container = encoder.singleValueContainer(); try container.encode(value)
    case .null: var container = encoder.singleValueContainer(); try container.encodeNil()
    case .object(let value): var container = encoder.container(keyedBy: DynamicCodingKey.self); for (key, item) in value { try container.encode(item, forKey: DynamicCodingKey(key)) }
    case .array(let value): var container = encoder.unkeyedContainer(); for item in value { try container.encode(item) }
    }
  }

  var stringValue: String {
    if case .string(let value) = self { return value }
    if case .number(let value) = self {
      return value.rounded() == value ? String(Int64(value)) : String(value)
    }
    if case .bool(let value) = self { return String(value) }
    if case .null = self { return "" }
    let data = (try? JSONEncoder().encode(self)) ?? Data()
    return String(data: data, encoding: .utf8) ?? ""
  }
}

private struct DynamicCodingKey: CodingKey {
  let stringValue: String
  init(_ stringValue: String) { self.stringValue = stringValue }
  init?(stringValue: String) { self.stringValue = stringValue }
  let intValue: Int? = nil
  init?(intValue: Int) { return nil }
}
public struct PteIMStateChangePage: Codable, Sendable { public let changes: [PteIMStateChange]; public let nextCursor: String; public let hasMore: Bool }
public struct PteIMDefaultSetting: Codable, Sendable { public let chatPrerequisite: String; public let notificationEnabled: Bool; public let groupJoinMode: String }

/**
 Exactly one mutable profile field. The type prevents accidental multi-field
 writes and maps one-to-one to the `/v1/im/profile/update` API contract.
 */
public enum PteIMUserProfileUpdate: Sendable, Equatable {
  case nickname(String), avatar(String), gender(PteIMGender), birthday(String), province(String), city(String), district(String)
  internal var requestBody: [String: Any] {
    switch self {
    case let .nickname(value): return ["field": "nickname", "value": value]
    case let .avatar(value): return ["field": "avatar", "value": value]
    case let .gender(value): return ["field": "gender", "value": value.rawValue]
    case let .birthday(value): return ["field": "birthday", "value": value]
    case let .province(value): return ["field": "province", "value": value]
    case let .city(value): return ["field": "city", "value": value]
    case let .district(value): return ["field": "district", "value": value]
    }
  }
}

public struct PteIMMedia: Codable, Sendable {
  public var url: String?
  public var thumbnailUrl: String?
  public var coverUrl: String?
  public var width: Int?
  public var height: Int?
  public var durationMs: Int64?
  public var sizeBytes: Int64?
  public var fileName: String?
  public var mimeType: String?
  public init(url: String? = nil, thumbnailUrl: String? = nil, coverUrl: String? = nil, width: Int? = nil, height: Int? = nil, durationMs: Int64? = nil, sizeBytes: Int64? = nil, fileName: String? = nil, mimeType: String? = nil) {
    self.url = url; self.thumbnailUrl = thumbnailUrl; self.coverUrl = coverUrl; self.width = width; self.height = height; self.durationMs = durationMs; self.sizeBytes = sizeBytes; self.fileName = fileName; self.mimeType = mimeType
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
  public let id: Int64
  public let type: String
  public let title: String
  public let avatar: String?
  public let lastMessageSeq: Int64
  public let lastMessageSnapshot: String?
  public let lastMessageAt: Int64
  public let unreadCount: Int64

  enum CodingKeys: String, CodingKey {
    case id, type, title, avatar
    case lastMessageSeq = "last_message_seq"
    case lastMessageSnapshot = "last_message_snapshot"
    case lastMessageAt = "last_message_at"
    case unreadCount = "unread_count"
  }

  /// 对齐 Android `optLong`：服务端对 0 值使用 `omitempty`（如 unread_count），不能按必填解码。
  public init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    if let v = try? c.decode(Int64.self, forKey: .id) {
      id = v
    } else if let v = try? c.decode(UInt64.self, forKey: .id) {
      id = Int64(v)
    } else if let v = try? c.decode(Int.self, forKey: .id) {
      id = Int64(v)
    } else {
      throw DecodingError.keyNotFound(
        CodingKeys.id,
        .init(codingPath: c.codingPath, debugDescription: "conversation id missing")
      )
    }
    type = (try c.decodeIfPresent(String.self, forKey: .type)) ?? ""
    title = (try c.decodeIfPresent(String.self, forKey: .title)) ?? ""
    avatar = try c.decodeIfPresent(String.self, forKey: .avatar)
    lastMessageSeq = (try c.decodeIfPresent(Int64.self, forKey: .lastMessageSeq)) ?? 0
    lastMessageSnapshot = try c.decodeIfPresent(String.self, forKey: .lastMessageSnapshot)
    lastMessageAt = (try c.decodeIfPresent(Int64.self, forKey: .lastMessageAt)) ?? 0
    unreadCount = (try c.decodeIfPresent(Int64.self, forKey: .unreadCount)) ?? 0
  }

  public init(
    id: Int64,
    type: String,
    title: String,
    avatar: String?,
    lastMessageSeq: Int64,
    lastMessageSnapshot: String?,
    lastMessageAt: Int64,
    unreadCount: Int64
  ) {
    self.id = id
    self.type = type
    self.title = title
    self.avatar = avatar
    self.lastMessageSeq = lastMessageSeq
    self.lastMessageSnapshot = lastMessageSnapshot
    self.lastMessageAt = lastMessageAt
    self.unreadCount = unreadCount
  }
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

public struct PteIMMessageReaction: Codable, Sendable, Hashable {
  public let emoji: String
  public let count: Int64
  public let reactedByMe: Bool
  public init(emoji: String, count: Int64, reactedByMe: Bool) { self.emoji = emoji; self.count = count; self.reactedByMe = reactedByMe }
}

public struct PteIMMessageReactionResult: Decodable, Sendable {
  public let messageId: String
  public let reactions: [PteIMMessageReaction]
}

/** Immutable source snapshot plus the server message ID used by the IM quote contract. */
public struct PteIMQuote: Codable, Sendable, Hashable {
  public let clientMsgId: String
  public let serverMsgId: String?
  public let senderId: String?
  public let text: String
  public init(clientMsgId: String, serverMsgId: String? = nil, senderId: String? = nil, text: String) { self.clientMsgId = clientMsgId; self.serverMsgId = serverMsgId; self.senderId = senderId; self.text = text }
}

struct PteIMMessageActionResponse: Decodable {}

public struct PteIMMessage: Codable, Sendable {
  public let clientMsgId: String
  public var serverMsgId: String? = nil
  public let conversationId: String
  public var senderId: String? = nil
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
  public var quote: PteIMQuote? = nil
  public var state: PteIMSendState
  public var status: Int = 1
  public var recalledAt: Int64? = nil
  public var reactions: [PteIMMessageReaction] = []

  public init(conversationId: String, senderId: String? = nil, type: PteIMMessageType, text: String? = nil, packageId: String? = nil, emojiId: String? = nil, media: PteIMMedia? = nil, voice: PteIMVoice? = nil, location: PteIMLocation? = nil, business: PteIMBusinessContent? = nil, quote: PteIMQuote? = nil, clientMsgId: String = UUID().uuidString, createdAt: Int64 = Int64(Date().timeIntervalSince1970 * 1000), state: PteIMSendState = .pending) {
    self.clientMsgId = clientMsgId; self.conversationId = conversationId; self.senderId = senderId; self.type = type; self.text = text; self.packageId = packageId; self.emojiId = emojiId; self.media = media; self.voice = voice; self.location = location; self.business = business; self.quote = quote; self.createdAt = createdAt; self.state = state
  }

  enum CodingKeys: String, CodingKey { case clientMsgId, serverMsgId, conversationId, senderId, type, createdAt, serverSeq, status, recalledAt, reactions, content }
  enum ContentKeys: String, CodingKey { case text, packageId, emojiId, url, thumbnailUrl, coverUrl, width, height, durationMs, sizeBytes, fileName, mimeType, waveform, latitude, longitude, name, address, businessId, title, subtitle, actionUrl, quote }

  public init(from decoder: Decoder) throws {
    let root = try decoder.container(keyedBy: CodingKeys.self)
    clientMsgId = try root.decode(String.self, forKey: .clientMsgId); serverMsgId = try root.decodeIfPresent(String.self, forKey: .serverMsgId)
    conversationId = try root.decode(String.self, forKey: .conversationId); senderId = try root.decodeIfPresent(String.self, forKey: .senderId); type = try root.decode(PteIMMessageType.self, forKey: .type)
    createdAt = try root.decode(Int64.self, forKey: .createdAt); serverSeq = try root.decodeIfPresent(Int64.self, forKey: .serverSeq)
    let content = try root.nestedContainer(keyedBy: ContentKeys.self, forKey: .content)
    text = try content.decodeIfPresent(String.self, forKey: .text); packageId = try content.decodeIfPresent(String.self, forKey: .packageId); emojiId = try content.decodeIfPresent(String.self, forKey: .emojiId)
    media = type == .image || type == .video || type == .file ? PteIMMedia(url: try content.decodeIfPresent(String.self, forKey: .url), thumbnailUrl: try content.decodeIfPresent(String.self, forKey: .thumbnailUrl), coverUrl: try content.decodeIfPresent(String.self, forKey: .coverUrl), width: try content.decodeIfPresent(Int.self, forKey: .width), height: try content.decodeIfPresent(Int.self, forKey: .height), durationMs: try content.decodeIfPresent(Int64.self, forKey: .durationMs), sizeBytes: try content.decodeIfPresent(Int64.self, forKey: .sizeBytes), fileName: try content.decodeIfPresent(String.self, forKey: .fileName), mimeType: try content.decodeIfPresent(String.self, forKey: .mimeType)) : nil
    voice = type == .voice ? try content.decodeIfPresent(String.self, forKey: .url).map { PteIMVoice(url: $0, durationMs: try content.decode(Int64.self, forKey: .durationMs), waveform: try content.decodeIfPresent(String.self, forKey: .waveform), sizeBytes: try content.decodeIfPresent(Int64.self, forKey: .sizeBytes)) } : nil
    location = type == .location ? try content.decodeIfPresent(Double.self, forKey: .latitude).map { latitude in PteIMLocation(latitude: latitude, longitude: try content.decode(Double.self, forKey: .longitude), name: try content.decode(String.self, forKey: .name), address: try content.decodeIfPresent(String.self, forKey: .address)) } : nil
    business = (type == .gift || type == .red_packet || type == .order) ? try content.decodeIfPresent(String.self, forKey: .businessId).map { id in PteIMBusinessContent(businessId: id, title: try content.decode(String.self, forKey: .title), subtitle: try content.decodeIfPresent(String.self, forKey: .subtitle), actionUrl: try content.decodeIfPresent(String.self, forKey: .actionUrl)) } : nil
    quote = try content.decodeIfPresent(PteIMQuote.self, forKey: .quote)
    status = try root.decodeIfPresent(Int.self, forKey: .status) ?? 1; recalledAt = try root.decodeIfPresent(Int64.self, forKey: .recalledAt); reactions = try root.decodeIfPresent([PteIMMessageReaction].self, forKey: .reactions) ?? []
    state = .sent
  }

  public func encode(to encoder: Encoder) throws {
    var root = encoder.container(keyedBy: CodingKeys.self)
    try root.encode(clientMsgId, forKey: .clientMsgId); try root.encodeIfPresent(serverMsgId, forKey: .serverMsgId); try root.encode(conversationId, forKey: .conversationId); try root.encodeIfPresent(senderId, forKey: .senderId)
    try root.encode(type, forKey: .type); try root.encode(createdAt, forKey: .createdAt); try root.encodeIfPresent(serverSeq, forKey: .serverSeq)
    try root.encode(status, forKey: .status); try root.encodeIfPresent(recalledAt, forKey: .recalledAt); try root.encode(reactions, forKey: .reactions)
    var content = root.nestedContainer(keyedBy: ContentKeys.self, forKey: .content)
    try content.encodeIfPresent(text, forKey: .text); try content.encodeIfPresent(packageId, forKey: .packageId); try content.encodeIfPresent(emojiId, forKey: .emojiId)
    try content.encodeIfPresent(media?.url, forKey: .url); try content.encodeIfPresent(media?.thumbnailUrl, forKey: .thumbnailUrl); try content.encodeIfPresent(media?.coverUrl, forKey: .coverUrl)
    try content.encodeIfPresent(media?.width, forKey: .width); try content.encodeIfPresent(media?.height, forKey: .height); try content.encodeIfPresent(media?.durationMs, forKey: .durationMs); try content.encodeIfPresent(media?.sizeBytes, forKey: .sizeBytes)
    try content.encodeIfPresent(media?.fileName, forKey: .fileName); try content.encodeIfPresent(media?.mimeType, forKey: .mimeType)
    try content.encodeIfPresent(voice?.url, forKey: .url); try content.encodeIfPresent(voice?.durationMs, forKey: .durationMs); try content.encodeIfPresent(voice?.waveform, forKey: .waveform); try content.encodeIfPresent(voice?.sizeBytes, forKey: .sizeBytes)
    try content.encodeIfPresent(location?.latitude, forKey: .latitude); try content.encodeIfPresent(location?.longitude, forKey: .longitude); try content.encodeIfPresent(location?.name, forKey: .name); try content.encodeIfPresent(location?.address, forKey: .address)
    try content.encodeIfPresent(business?.businessId, forKey: .businessId); try content.encodeIfPresent(business?.title, forKey: .title); try content.encodeIfPresent(business?.subtitle, forKey: .subtitle); try content.encodeIfPresent(business?.actionUrl, forKey: .actionUrl)
    try content.encodeIfPresent(quote, forKey: .quote)
  }

  /** JSON representation of the type-specific message content for language bridges. */
  public func contentJSON() -> String {
    var content: [String: Any] = [:]
    if let text { content["text"] = text }; if let packageId { content["packageId"] = packageId }; if let emojiId { content["emojiId"] = emojiId }
    if let media { if let url = media.url { content["url"] = url }; if let thumbnailUrl = media.thumbnailUrl { content["thumbnailUrl"] = thumbnailUrl }; if let coverUrl = media.coverUrl { content["coverUrl"] = coverUrl }; if let width = media.width { content["width"] = width }; if let height = media.height { content["height"] = height }; if let durationMs = media.durationMs { content["durationMs"] = durationMs }; if let sizeBytes = media.sizeBytes { content["sizeBytes"] = sizeBytes }; if let fileName = media.fileName { content["fileName"] = fileName }; if let mimeType = media.mimeType { content["mimeType"] = mimeType } }
    if let voice { content["url"] = voice.url; content["durationMs"] = voice.durationMs; if let waveform = voice.waveform { content["waveform"] = waveform }; if let sizeBytes = voice.sizeBytes { content["sizeBytes"] = sizeBytes } }
    if let location { content["latitude"] = location.latitude; content["longitude"] = location.longitude; content["name"] = location.name; if let address = location.address { content["address"] = address } }
    if let business { content["businessId"] = business.businessId; content["title"] = business.title; if let subtitle = business.subtitle { content["subtitle"] = subtitle }; if let actionURL = business.actionUrl { content["actionUrl"] = actionURL } }
    return String(data: (try? JSONSerialization.data(withJSONObject: content)) ?? Data("{}".utf8), encoding: .utf8) ?? "{}"
  }
}

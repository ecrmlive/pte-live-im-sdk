import Foundation

public final class PteLiveIM: NSObject {
  public var onConnectionChanged: ((Bool) -> Void)?
  public var onMessage: ((PteIMMessage) -> Void)?
  public var onMessageStateChanged: ((String, PteIMSendState) -> Void)?
  public var onUserSigWillExpire: (() -> Void)?
  public var onUserSigExpired: (() -> Void)?
  public var onThemeModeChanged: ((PteIMThemeMode) -> Void)?
  public var onLanguageChanged: ((PteIMLanguage) -> Void)?
  public var onError: ((Error) -> Void)?
  public private(set) var appearance: PteIMAppearance

  private var config: PteIMSessionConfig
  private let store: PteIMSqliteStore
  private lazy var session = URLSession(configuration: .default, delegate: self, delegateQueue: nil)
  private var socket: URLSessionWebSocketTask?
  private var reconnectWorkItem: DispatchWorkItem?
  private var outboxRetryWorkItem: DispatchWorkItem?
  private var reconnectAttempt = 0
  private var stopRequested = false
  private var socketConnected = false

  internal init(config: PteIMSessionConfig) throws {
    self.config = config
    self.appearance = PteIMAppearance(themeMode: config.base.themeMode, language: config.base.language)
    self.store = try PteIMSqliteStore(storeKey: config.storeKey)
    super.init()
  }

  public static func configure(_ baseConfig: PteIMBaseConfig) -> PteLiveIMBootstrap { PteLiveIMBootstrap(baseConfig: baseConfig) }

  public func start() {
    stopRequested = false
    reconnectWorkItem?.cancel(); reconnectWorkItem = nil
    socket?.cancel(with: .goingAway, reason: nil)
    let task = session.webSocketTask(with: webSocketURL())
    socket = task
    task.resume()
  }

  public func stop() { stopRequested = true; socketConnected = false; reconnectWorkItem?.cancel(); reconnectWorkItem = nil; outboxRetryWorkItem?.cancel(); outboxRetryWorkItem = nil; socket?.cancel(with: .goingAway, reason: nil); socket = nil }

  public func renewUserSig(_ userSig: String) {
    guard !userSig.isEmpty else { return }
    config.userSig = userSig
    sendEnvelope(action: "renew_user_sig", payload: ["userSig": userSig])
  }

  /** Updates host-UI preferences without reconnecting or changing the logged-in session. */
  @discardableResult public func updateAppearance(themeMode: PteIMThemeMode? = nil, language: PteIMLanguage? = nil) -> PteIMAppearance {
    let previous = appearance
    let updated = PteIMAppearance(themeMode: themeMode ?? previous.themeMode, language: language ?? previous.language)
    appearance = updated
    if updated.themeMode != previous.themeMode { onThemeModeChanged?(updated.themeMode) }
    if updated.language != previous.language { onLanguageChanged?(updated.language) }
    return updated
  }

  @discardableResult public func sendText(conversationId: String, text: String) -> PteIMMessage {
    send(PteIMMessage(conversationId: conversationId, type: .text, text: text))
  }
  @discardableResult public func sendEmoji(conversationId: String, packageId: String, emojiId: String) -> PteIMMessage {
    send(PteIMMessage(conversationId: conversationId, type: .emoji, packageId: packageId, emojiId: emojiId))
  }
  @discardableResult public func sendImage(conversationId: String, media: PteIMMedia) -> PteIMMessage {
    send(PteIMMessage(conversationId: conversationId, type: .image, media: media))
  }
  @discardableResult public func sendVideo(conversationId: String, media: PteIMMedia) -> PteIMMessage {
    send(PteIMMessage(conversationId: conversationId, type: .video, media: media))
  }
  @discardableResult public func sendVoice(conversationId: String, voice: PteIMVoice) -> PteIMMessage {
    send(PteIMMessage(conversationId: conversationId, type: .voice, voice: voice))
  }
  @discardableResult public func sendLocation(conversationId: String, location: PteIMLocation) -> PteIMMessage {
    send(PteIMMessage(conversationId: conversationId, type: .location, location: location))
  }
  @discardableResult public func sendGift(conversationId: String, content: PteIMBusinessContent) -> PteIMMessage {
    send(PteIMMessage(conversationId: conversationId, type: .gift, business: content))
  }
  @discardableResult public func sendRedPacket(conversationId: String, content: PteIMBusinessContent) -> PteIMMessage {
    send(PteIMMessage(conversationId: conversationId, type: .red_packet, business: content))
  }
  @discardableResult public func sendOrder(conversationId: String, content: PteIMBusinessContent) -> PteIMMessage {
    send(PteIMMessage(conversationId: conversationId, type: .order, business: content))
  }
  @discardableResult public func uploadAndSendImage(conversationId: String, fileURL: URL, progress: @escaping (Int64, Int64) -> Void = { _, _ in }) -> PteIMMessage {
    uploadAndSendMedia(conversationId: conversationId, fileURL: fileURL, type: .image, progress: progress)
  }
  @discardableResult public func uploadAndSendVideo(conversationId: String, fileURL: URL, progress: @escaping (Int64, Int64) -> Void = { _, _ in }) -> PteIMMessage {
    uploadAndSendMedia(conversationId: conversationId, fileURL: fileURL, type: .video, progress: progress)
  }
  @discardableResult public func uploadAndSendVoice(conversationId: String, fileURL: URL, durationMs: Int64, waveform: String? = nil, progress: @escaping (Int64, Int64) -> Void = { _, _ in }) -> PteIMMessage {
    precondition(durationMs > 0, "durationMs must be positive")
    return uploadAndSendMedia(conversationId: conversationId, fileURL: fileURL, type: .voice, voiceDurationMs: durationMs, waveform: waveform, progress: progress)
  }

  public func syncNow() {
    Task { [weak self] in
      guard let self else { return }
      do {
        let cursor = try self.store.cursor()
        let delta: PteIMSyncResponse = try await self.sdkRequest(path: "v1/im/sync", body: ["syncCursor": cursor, "pageSize": 200], response: PteIMSyncResponse.self)
        let messages = delta.messages.map(self.resolveMessage)
        try self.store.apply(messages: messages, nextCursor: delta.nextCursor)
        messages.forEach { self.onMessage?($0) }
        if delta.hasMore { self.syncNow() }
      } catch { self.onError?(error) }
    }
  }

  /** Loads a server-authoritative conversation page using the current UserSig session. */
  public func fetchConversationPage(page: Int = 1, pageSize: Int = 50) async throws -> PteIMConversationPage {
    guard page > 0, (1...200).contains(pageSize) else { throw PteIMError.invalidResponse }
    return try await sdkRequest(path: "v1/im/conversations", body: ["page": page, "pageSize": pageSize], response: PteIMConversationPage.self)
  }

  /** Opens (or idempotently creates) a C2C conversation for this UserSig identity. */
  public func openSingleConversation(peerUserId: Int64) async throws -> PteIMRemoteConversation {
    guard peerUserId > 0 else { throw PteIMError.invalidResponse }
    return try await sdkRequest(path: "v1/im/conversations/open-single", body: ["peerUserId": peerUserId], response: PteIMRemoteConversation.self)
  }

  /** Creates a group owned by this UserSig identity. */
  public func createGroupConversation(title: String, memberIds: [Int64] = [], avatar: String? = nil) async throws -> PteIMRemoteConversation {
    guard !title.isEmpty, memberIds.allSatisfy({ $0 > 0 }) else { throw PteIMError.invalidResponse }
    var body: [String: Any] = ["title": title, "memberIds": memberIds]
    if let avatar { body["avatar"] = avatar }
    return try await sdkRequest(path: "v1/im/conversations/create-group", body: body, response: PteIMRemoteConversation.self)
  }

  /** Advances this user's read sequence; zero means the latest message. */
  public func markConversationRead(conversationId: Int64, seq: Int64 = 0) async throws {
    guard conversationId > 0, seq >= 0 else { throw PteIMError.invalidResponse }
    let _: PteIMOKResponse = try await sdkRequest(path: "v1/im/conversations/read", body: ["conversationId": conversationId, "seq": seq], response: PteIMOKResponse.self)
  }

  /** Loads a server-authoritative message-history page using the current UserSig session. */
  public func fetchMessageHistory(conversationId: Int64, beforeSeq: Int64 = 0, limit: Int = 50) async throws -> PteIMMessagePage {
    guard conversationId > 0, beforeSeq >= 0, (1...200).contains(limit) else { throw PteIMError.invalidResponse }
    return try await sdkRequest(path: "v1/im/conversations/messages", body: ["conversationId": conversationId, "beforeSeq": beforeSeq, "limit": limit], response: PteIMMessagePage.self)
  }

  /** Reads the account-isolated SQLite cache. Call [syncNow] first when fresh server state is required. */
  public func localMessages(conversationId: String, beforeCreatedAt: Int64? = nil, limit: Int = 50) throws -> [PteIMMessage] {
    try store.localMessages(conversationId: conversationId, beforeCreatedAt: beforeCreatedAt, limit: limit).map { try storedMessageToModel($0) }
  }

  /** Returns conversations ordered by their newest locally stored message. */
  public func localConversations(limit: Int = 100) throws -> [PteIMConversation] {
    try store.localConversations(limit: limit).map { entry in
      let message = try storedMessageToModel(entry.lastMessage)
      return PteIMConversation(conversationId: entry.conversationId, lastMessage: message, updatedAt: message.createdAt)
    }
  }

  private func send(_ message: PteIMMessage) -> PteIMMessage {
    do { try store.enqueue(message); onMessageStateChanged?(message.clientMsgId, .pending); flushOutbox() }
    catch { onError?(error) }
    return message
  }

  private func uploadAndSendMedia(conversationId: String, fileURL: URL, type: PteIMMessageType, voiceDurationMs: Int64? = nil, waveform: String? = nil, progress: @escaping (Int64, Int64) -> Void) -> PteIMMessage {
    var message = PteIMMessage(conversationId: conversationId, type: type, state: .uploading)
    do { try store.enqueue(message); onMessageStateChanged?(message.clientMsgId, .uploading) }
    catch { onError?(error); return message }
    Task { [weak self] in
      guard let self else { return }
      do {
        let uploaded = try await self.uploadMedia(fileURL: fileURL, type: type, progress: progress)
        if type == .voice {
          guard let key = uploaded.url, let durationMs = voiceDurationMs, durationMs > 0 else { throw PteIMError.invalidResponse }
          message.voice = PteIMVoice(url: key, durationMs: durationMs, waveform: waveform, sizeBytes: uploaded.sizeBytes)
        } else { message.media = uploaded }
        message.state = .pending
        try self.store.replaceQueued(message)
        self.onMessageStateChanged?(message.clientMsgId, .pending)
        self.flushOutbox()
      } catch {
        try? self.store.markFailed(clientMsgId: message.clientMsgId)
        self.onMessageStateChanged?(message.clientMsgId, .failed); self.onError?(error)
      }
    }
    return message
  }

  private func sendQueued(_ message: PteIMMessage) { sendEnvelope(action: "send_message", payload: message.dictionary) }

  private func flushOutbox() {
    guard socketConnected, !stopRequested else { return }
    do {
      let now = Int64(Date().timeIntervalSince1970 * 1000)
      for stored in try store.dueOutbox(now: now) {
        let message = try storedMessageToModel(stored)
        _ = try store.recordOutboxAttempt(clientMsgId: message.clientMsgId, now: now)
        sendQueued(message)
      }
      scheduleOutboxRetry()
    } catch { onError?(error) }
  }

  private func scheduleOutboxRetry() {
    outboxRetryWorkItem?.cancel(); outboxRetryWorkItem = nil
    guard socketConnected, !stopRequested, let nextRetryAt = try? store.nextOutboxRetryAt() else { return }
    let now = Int64(Date().timeIntervalSince1970 * 1000)
    let delayMilliseconds = min(max(nextRetryAt - now, 100), 30_000)
    let item = DispatchWorkItem { [weak self] in self?.flushOutbox() }
    outboxRetryWorkItem = item
    DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(Int(delayMilliseconds)), execute: item)
  }

  private func receiveNext() {
    socket?.receive { [weak self] result in
      guard let self else { return }
      switch result {
      case .success(.string(let text)): self.handleInbound(text); self.receiveNext()
      case .success(.data(let data)): self.handleInbound(String(decoding: data, as: UTF8.self)); self.receiveNext()
      case .failure(let error): self.socketConnected = false; self.onError?(error); self.onConnectionChanged?(false); self.scheduleReconnect()
      @unknown default: break
      }
    }
  }

  private func handleInbound(_ text: String) {
    do {
      guard let root = try JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any], let action = root["action"] as? String else { throw PteIMError.invalidResponse }
      let payload = root["payload"] as? [String: Any] ?? [:]
      switch action {
      case "message":
        let message = try decodeMessage(payload)
        try store.apply(messages: [message], nextCursor: root["syncCursor"] as? String ?? store.cursor())
        onMessage?(message); sendEnvelope(action: "ack", payload: ["serverMsgId": message.serverMsgId ?? ""])
      case "ack":
        guard let id = payload["clientMsgId"] as? String else { return }
        let sequence = (payload["serverSeq"] as? NSNumber)?.int64Value
        try store.markSent(clientMsgId: id, serverMsgId: payload["serverMsgId"] as? String, serverSeq: sequence)
        onMessageStateChanged?(id, .sent)
      case "user_sig_will_expire": onUserSigWillExpire?()
      case "user_sig_expired": onUserSigExpired?()
      case "sync_required": syncNow()
      default: break
      }
    } catch { onError?(error) }
  }

  private func sendEnvelope(action: String, payload: [String: Any]) {
    guard let socket else { onError?(PteIMError.disconnected); return }
    let body: [String: Any] = ["protocolVersion": 1, "action": action, "requestId": UUID().uuidString, "sdkAppId": config.sdkAppId, "userId": config.userId, "userSig": config.userSig, "payload": payload]
    do {
      let text = String(decoding: try JSONSerialization.data(withJSONObject: body), as: UTF8.self)
      socket.send(.string(text)) { [weak self] error in if let error { self?.onError?(error) } }
    } catch { onError?(error) }
  }

  private func decodeMessage(_ payload: [String: Any]) throws -> PteIMMessage {
    resolveMessage(try JSONDecoder().decode(PteIMMessage.self, from: JSONSerialization.data(withJSONObject: payload)))
  }

  private func uploadMedia(fileURL: URL, type: PteIMMessageType, progress: @escaping (Int64, Int64) -> Void) async throws -> PteIMMedia {
    let fileSize = try fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize.map(Int64.init) ?? 0
    guard fileSize > 0 else { throw PteIMError.invalidResponse }
    let contentType = cosContentType(for: fileURL, type: type)
    let credential: PteIMCosPutCredential = try await apiImRequest(
      path: "v1/im/media/put-url",
      body: ["mediaType": type.rawValue, "contentType": contentType, "contentLength": fileSize],
      response: PteIMCosPutCredential.self
    )
    var request = URLRequest(url: URL(string: credential.uploadUrl)!)
    request.httpMethod = "PUT"
    credential.headers.forEach { request.setValue($0.value, forHTTPHeaderField: $0.key) }
    let (_, response) = try await session.upload(for: request, fromFile: fileURL)
    guard let http = response as? HTTPURLResponse, 200..<300 ~= http.statusCode else { throw PteIMError.invalidResponse }
    progress(fileSize, fileSize)
    return PteIMMedia(url: credential.key, sizeBytes: fileSize)
  }

  private func sdkRequest<T: Decodable>(path: String, body: [String: Any], response: T.Type) async throws -> T {
    var request = URLRequest(url: config.apiDomain.appendingPathComponent(path))
    request.httpMethod = "POST"; request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.setValue("Bearer \(config.userSig)", forHTTPHeaderField: "Authorization")
    request.setValue(String(config.sdkAppId), forHTTPHeaderField: "X-Pte-Sdk-AppId"); request.setValue(config.userId, forHTTPHeaderField: "X-Pte-User-Id")
    request.httpBody = try JSONSerialization.data(withJSONObject: body)
    let (data, httpResponse) = try await session.data(for: request)
    guard let http = httpResponse as? HTTPURLResponse, 200..<300 ~= http.statusCode else { throw PteIMError.invalidResponse }
    let envelope = try JSONDecoder().decode(PteIMSDKEnvelope<T>.self, from: data)
    guard envelope.code == 1, let value = envelope.data else { throw PteIMError.invalidResponse }
    return value
  }

  private func apiImRequest<T: Decodable>(path: String, body: [String: Any], response: T.Type) async throws -> T {
    var request = URLRequest(url: config.apiDomain.appendingPathComponent(path))
    request.httpMethod = "POST"; request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.setValue("Bearer \(config.userSig)", forHTTPHeaderField: "Authorization")
    request.setValue(String(config.sdkAppId), forHTTPHeaderField: "X-Pte-Sdk-AppId"); request.setValue(config.userId, forHTTPHeaderField: "X-Pte-User-Id")
    request.httpBody = try JSONSerialization.data(withJSONObject: body)
    let (data, httpResponse) = try await session.data(for: request)
    guard let http = httpResponse as? HTTPURLResponse, 200..<300 ~= http.statusCode else { throw PteIMError.invalidResponse }
    let envelope = try JSONDecoder().decode(PteIMSDKEnvelope<T>.self, from: data)
    guard envelope.code == 0, let value = envelope.data else { throw PteIMError.invalidResponse }
    return value
  }

  private func cosContentType(for fileURL: URL, type: PteIMMessageType) -> String {
    switch fileURL.pathExtension.lowercased() {
    case "jpg", "jpeg": return "image/jpeg"
    case "png": return "image/png"
    case "webp": return "image/webp"
    case "gif": return "image/gif"
    case "mp4": return type == .image ? "image/jpeg" : "video/mp4"
    case "webm": return "video/webm"
    case "mov": return "video/quicktime"
    case "aac": return "audio/aac"
    case "mp3": return "audio/mpeg"
    case "m4a": return "audio/mp4"
    case "ogg": return "audio/ogg"
    case "wav": return "audio/wav"
    default:
      if type == .image { return "image/jpeg" }
      if type == .voice { return "audio/mpeg" }
      return "video/mp4"
    }
  }

  private func resolveMessage(_ message: PteIMMessage) -> PteIMMessage { var value = message; value.media = value.media.map(resolveMedia); value.voice = value.voice.map { var voice = $0; voice.url = resolveCosURL(voice.url) ?? voice.url; return voice }; return value }
  private func storedMessageToModel(_ stored: StoredMessage) throws -> PteIMMessage {
    let object = try JSONSerialization.jsonObject(with: Data(stored.payload.utf8)) as? [String: Any] ?? [:]
    var value = try decodeMessage(object)
    value.serverMsgId = stored.serverMsgId; value.serverSeq = stored.serverSeq
    if stored.createdAt > 0 { value = PteIMMessage(conversationId: value.conversationId, type: value.type, text: value.text, packageId: value.packageId, emojiId: value.emojiId, media: value.media, voice: value.voice, location: value.location, business: value.business, clientMsgId: value.clientMsgId, createdAt: stored.createdAt, state: value.state); value.serverMsgId = stored.serverMsgId; value.serverSeq = stored.serverSeq }
    value.state = PteIMSendState(rawValue: stored.state) ?? .sent
    return value
  }
  private func resolveMedia(_ media: PteIMMedia) -> PteIMMedia { var value = media; value.url = resolveCosURL(value.url); value.thumbnailUrl = resolveCosURL(value.thumbnailUrl); value.coverUrl = resolveCosURL(value.coverUrl); return value }
  private func resolveCosURL(_ value: String?) -> String? {
    guard let value, URL(string: value)?.scheme == nil else { return value }
    return config.cosDomain.appendingPathComponent(value.trimmingCharacters(in: CharacterSet(charactersIn: "/"))).absoluteString
  }

  /** api-im validates UserSig during the WSS upgrade. Browsers cannot attach arbitrary
   * upgrade headers, so every SDK uses the same URL-encoded, short-lived query contract. */
  private func webSocketURL() -> URL {
    var components = URLComponents(url: config.imDomain, resolvingAgainstBaseURL: false)!
    var items = components.queryItems ?? []
    items.append(URLQueryItem(name: "sdkAppID", value: String(config.login.sdkAppId)))
    items.append(URLQueryItem(name: "identifier", value: config.login.userId))
    items.append(URLQueryItem(name: "userSig", value: config.login.userSig))
    components.queryItems = items
    return components.url!
  }

  private func scheduleReconnect() {
    guard !stopRequested, reconnectWorkItem == nil else { return }
    let delay = min(pow(2.0, Double(reconnectAttempt)), 30.0)
    reconnectAttempt = min(reconnectAttempt + 1, 5)
    let item = DispatchWorkItem { [weak self] in
      guard let self else { return }; self.reconnectWorkItem = nil; self.start()
    }
    reconnectWorkItem = item
    DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: item)
  }
}

extension PteLiveIM: URLSessionWebSocketDelegate {
  public func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didOpenWithProtocol protocol: String?) {
    reconnectAttempt = 0
    socketConnected = true
    onConnectionChanged?(true)
    sendEnvelope(action: "login", payload: ["syncCursor": (try? store.cursor()) ?? ""])
    receiveNext(); flushOutbox(); syncNow()
  }
  public func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didCloseWith closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?) {
    socketConnected = false
    onConnectionChanged?(false)
    scheduleReconnect()
  }
}

private struct PteIMSyncResponse: Decodable { let messages: [PteIMMessage]; let nextCursor: String; let hasMore: Bool }
private struct PteIMOKResponse: Decodable { let ok: Bool }
private struct PteIMSDKEnvelope<T: Decodable>: Decodable { let code: Int; let msg: String; let data: T? }
private struct PteIMCosPutCredential: Decodable { let key: String; let uploadUrl: String; let headers: [String: String]; let expiresAt: Int64 }

public final class PteLiveIMBootstrap {
  private let baseConfig: PteIMBaseConfig
  internal init(baseConfig: PteIMBaseConfig) { self.baseConfig = baseConfig }
  public func login(_ loginConfig: PteIMLoginConfig) throws -> PteLiveIM {
    let client = try PteLiveIM(config: PteIMSessionConfig(base: baseConfig, login: loginConfig))
    client.start()
    return client
  }
}

private extension PteIMMessage {
  var dictionary: [String: Any] {
    var content: [String: Any] = [:]
    if let text { content["text"] = text }; if let packageId { content["packageId"] = packageId }; if let emojiId { content["emojiId"] = emojiId }
    if let media { if let url = media.url { content["url"] = url }; if let thumbnailUrl = media.thumbnailUrl { content["thumbnailUrl"] = thumbnailUrl }; if let coverUrl = media.coverUrl { content["coverUrl"] = coverUrl }; if let width = media.width { content["width"] = width }; if let height = media.height { content["height"] = height }; if let durationMs = media.durationMs { content["durationMs"] = durationMs }; if let sizeBytes = media.sizeBytes { content["sizeBytes"] = sizeBytes } }
    if let voice { content["url"] = voice.url; content["durationMs"] = voice.durationMs; if let waveform = voice.waveform { content["waveform"] = waveform }; if let sizeBytes = voice.sizeBytes { content["sizeBytes"] = sizeBytes } }
    if let location { content["latitude"] = location.latitude; content["longitude"] = location.longitude; content["name"] = location.name; if let address = location.address { content["address"] = address } }
    if let business { content["businessId"] = business.businessId; content["title"] = business.title; if let subtitle = business.subtitle { content["subtitle"] = subtitle }; if let actionURL = business.actionUrl { content["actionUrl"] = actionURL } }
    return ["clientMsgId": clientMsgId, "conversationId": conversationId, "type": type.rawValue, "createdAt": createdAt, "content": content]
  }
}

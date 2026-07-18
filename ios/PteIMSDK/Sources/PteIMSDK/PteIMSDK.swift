import Foundation

public final class PteIMSDK: NSObject, @unchecked Sendable {
  public private(set) var appearance: PteIMAppearance

  private var config: PteIMSessionConfig
  private let store: PteIMCoreDataStore
  private let e2ee: PteIME2EE
  private let appearanceStore: PteIMAppearanceStore
  private lazy var session = URLSession(configuration: .default, delegate: self, delegateQueue: nil)
  private var socket: URLSessionWebSocketTask?
  private var reconnectWorkItem: DispatchWorkItem?
  private var outboxRetryWorkItem: DispatchWorkItem?
  private var reconnectAttempt = 0
  private var stopRequested = false
  private var socketConnected = false
  private var listeners: [ObjectIdentifier: PteIMListener] = [:]
  /** Optional Commerce extension. It shares the current UserSig and does not open another socket. */
  public lazy var commerce = PteIMCommerce(sdk: self)

  internal init(config: PteIMSessionConfig, persistentCache: Bool = true) throws {
    self.config = config
    let configuredAppearance = PteIMAppearance(themeMode: config.base.themeMode, language: config.base.language)
    let appearanceStore = PteIMAppearanceStore(storeKey: config.storeKey, persistent: persistentCache)
    self.appearanceStore = appearanceStore
    self.appearance = appearanceStore.load() ?? configuredAppearance
    self.store = try PteIMCoreDataStore(storeKey: config.storeKey, persistent: persistentCache)
    self.e2ee = PteIME2EE(storeKey: config.storeKey, appId: config.sdkAppId, userId: config.userId)
    super.init()
  }

  public static func configure(_ baseConfig: PteIMBaseConfig) -> PteIMSDKBootstrap { PteIMSDKBootstrap(baseConfig: baseConfig) }

  public func addListener(_ listener: PteIMListener) { listeners[ObjectIdentifier(listener)] = listener }
  public func removeListener(_ listener: PteIMListener) { listeners.removeValue(forKey: ObjectIdentifier(listener)) }
  private func notify(_ callback: (PteIMListener) -> Void) { listeners.values.forEach(callback) }

  /**
   Creates an offline client for UIKit previews and snapshot tests. Unlike
   `login(_:)`, this constructor never opens a socket, registers an E2EE device,
   or sends the supplied credential over the network.
   */
  public static func preview(baseConfig: PteIMBaseConfig, loginConfig: PteIMLoginConfig) throws -> PteIMSDK {
    try PteIMSDK(config: PteIMSessionConfig(base: baseConfig, login: loginConfig), persistentCache: false)
  }

  public func start() {
    stopRequested = false
    reconnectWorkItem?.cancel(); reconnectWorkItem = nil
    Task { [weak self] in
      guard let self else { return }
      do {
        try await self.e2ee.register { path, body in try await self.e2eeRequest(path: path, body: body) }
        guard !self.stopRequested else { return }
        self.connect()
      } catch { self.notify { $0.onError?(error) } }
    }
  }

  private func connect() {
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
    appearanceStore.save(updated)
    if updated.themeMode != previous.themeMode { notify { $0.onThemeModeChanged?(updated.themeMode) } }
    if updated.language != previous.language { notify { $0.onLanguageChanged?(updated.language) } }
    return updated
  }

  /** The light/dark value that UIKit should render right now. */
  public func resolvedTheme(at date: Date = Date(), calendar: Calendar = .current) -> PteIMTheme {
    appearance.resolvedTheme(at: date, calendar: calendar)
  }

  /** The Chinese/English value that UIKit should render for the current locale. */
  public func resolvedLanguage(locale: Locale? = nil) -> PteIMLanguage {
    appearance.resolvedLanguage(locale: locale)
  }

  /** Removes the saved choices and returns this account to the configured defaults. */
  @discardableResult public func resetAppearancePreferences() -> PteIMAppearance {
    let previous = appearance
    appearanceStore.remove()
    let updated = PteIMAppearance(themeMode: config.base.themeMode, language: config.base.language)
    appearance = updated
    if updated.themeMode != previous.themeMode { notify { $0.onThemeModeChanged?(updated.themeMode) } }
    if updated.language != previous.language { notify { $0.onLanguageChanged?(updated.language) } }
    return updated
  }
  public var currentUserId: String { config.userId }

  /** Reads the server-authoritative profile for the authenticated UserSig identity. */
  public func fetchMyProfile() async throws -> PteIMUserProfile {
    try await sdkRequest(path: "v1/im/profile/me", body: [:], response: PteIMUserProfile.self)
  }

  /**
   Updates exactly one profile property. Avatar must be a COS key or URL
   accepted by the host API; the SDK never uploads profile media implicitly.
   */
  @discardableResult public func updateMyProfile(_ update: PteIMUserProfileUpdate) async throws -> PteIMUserProfile {
    try await sdkRequest(path: "v1/im/profile/update", body: update.requestBody, response: PteIMUserProfile.self)
  }

  public func fetchFriends(cursor: String = "", limit: Int = 50) async throws -> PteIMContactPage { try await sdkRequest(path: "v1/im/friends", body: ["cursor": cursor, "limit": limit], response: PteIMContactPage.self) }
  public func fetchFollows(cursor: String = "", limit: Int = 50) async throws -> PteIMContactPage { try await sdkRequest(path: "v1/im/follows", body: ["cursor": cursor, "limit": limit], response: PteIMContactPage.self) }
  public func follow(userId: Int64, remark: String? = nil) async throws { var body: [String: Any] = ["targetUserId": userId]; if let remark { body["remark"] = remark }; let _: PteIMOKResponse = try await sdkRequest(path: "v1/im/follows/follow", body: body, response: PteIMOKResponse.self) }
  public func unfollow(userId: Int64) async throws { let _: PteIMOKResponse = try await sdkRequest(path: "v1/im/follows/unfollow", body: ["targetUserId": userId], response: PteIMOKResponse.self) }
  public func block(userId: Int64) async throws { let _: PteIMOKResponse = try await sdkRequest(path: "v1/im/blocks/add", body: ["targetUserId": userId], response: PteIMOKResponse.self) }
  public func unblock(userId: Int64) async throws { let _: PteIMOKResponse = try await sdkRequest(path: "v1/im/blocks/remove", body: ["targetUserId": userId], response: PteIMOKResponse.self) }
  public func fetchGroups(cursor: String = "", limit: Int = 50) async throws -> PteIMGroupPage { try await sdkRequest(path: "v1/im/groups", body: ["cursor": cursor, "limit": limit], response: PteIMGroupPage.self) }
  public func fetchGroupMembers(conversationId: Int64, cursor: String = "", limit: Int = 50) async throws -> PteIMMemberPage { try await sdkRequest(path: "v1/im/groups/members", body: ["conversationId": conversationId, "cursor": cursor, "limit": limit], response: PteIMMemberPage.self) }
  public func joinGroup(conversationId: Int64) async throws { let _: PteIMOKResponse = try await sdkRequest(path: "v1/im/groups/join", body: ["conversationId": conversationId], response: PteIMOKResponse.self) }
  public func inviteGroupMembers(conversationId: Int64, memberIds: [Int64]) async throws {
    guard conversationId > 0, !memberIds.isEmpty, memberIds.allSatisfy({ $0 > 0 }) else { throw PteIMError.invalidConversationId }
    let _: PteIMOKResponse = try await sdkRequest(path: "v1/im/groups/members/invite", body: ["conversationId": conversationId, "memberIds": memberIds], response: PteIMOKResponse.self)
  }
  public func removeGroupMember(conversationId: Int64, memberId: Int64) async throws {
    guard conversationId > 0, memberId > 0 else { throw PteIMError.invalidConversationId }
    let _: PteIMOKResponse = try await sdkRequest(path: "v1/im/groups/members/remove", body: ["conversationId": conversationId, "memberId": memberId], response: PteIMOKResponse.self)
  }
  public func leaveGroup(conversationId: Int64) async throws {
    guard conversationId > 0 else { throw PteIMError.invalidConversationId }
    let _: PteIMOKResponse = try await sdkRequest(path: "v1/im/groups/leave", body: ["conversationId": conversationId], response: PteIMOKResponse.self)
  }
  /**
   Registers the current device's provider token. The server stores AES-GCM
   ciphertext only; callers must obtain the token from APNs/U-Push themselves.
   */
  public func registerPushDevice(deviceId: String, platform: PteIMPushPlatform, token: String, notificationEnabled: Bool = true) async throws -> PteIMPushDevice {
    guard deviceId.count >= 8, token.count >= 16 else { throw PteIMError.invalidCredentials }
    return try await sdkRequest(path: "v1/im/push/devices/register", body: ["deviceId": deviceId, "platform": platform.rawValue, "token": token, "notificationEnabled": notificationEnabled], response: PteIMPushDevice.self)
  }
  public func setPushDeviceNotification(deviceId: String, platform: PteIMPushPlatform, enabled: Bool) async throws -> PteIMPushDevice {
    guard deviceId.count >= 8 else { throw PteIMError.invalidCredentials }
    return try await sdkRequest(path: "v1/im/push/devices/notification", body: ["deviceId": deviceId, "platform": platform.rawValue, "notificationEnabled": enabled], response: PteIMPushDevice.self)
  }
  /// Erases this device's encrypted provider token from the IM service.
  public func unregisterPushDevice(deviceId: String, platform: PteIMPushPlatform) async throws {
    guard deviceId.count >= 8 else { throw PteIMError.invalidCredentials }
    let _: PteIMOKResponse = try await sdkRequest(path: "v1/im/push/devices/unregister", body: ["deviceId": deviceId, "platform": platform.rawValue], response: PteIMOKResponse.self)
  }
  public func syncState(cursor: String = "", limit: Int = 100) async throws -> PteIMStateChangePage { try await sdkRequest(path: "v1/im/state/sync", body: ["cursor": cursor, "limit": limit], response: PteIMStateChangePage.self) }
  public func fetchDefaultSetting() async throws -> PteIMDefaultSetting { try await sdkRequest(path: "v1/im/settings/default", body: [:], response: PteIMDefaultSetting.self) }

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
  @discardableResult public func sendFile(conversationId: String, media: PteIMMedia) -> PteIMMessage {
    send(PteIMMessage(conversationId: conversationId, type: .file, media: media))
  }
  /**
   Requeues a failed or pending message with its original client ID. This is
   intentionally transport-only: callers that need server-side recall/delete
   must use their business API, because those permissions are server owned.
   Media uploads that failed before an object URL was obtained should be
   retried from the original local file via `uploadAndSend…` instead.
   */
  @discardableResult public func retry(message: PteIMMessage) -> PteIMMessage {
    guard let conversationId = UInt64(message.conversationId), conversationId > 0 else {
      notify { $0.onError?(PteIMError.invalidConversationId) }
      return message
    }
    var queued = message
    queued.senderId = config.userId
    queued.state = .pending
    do {
      try store.enqueue(queued)
      notify { $0.onMessageStateChanged?(queued.clientMsgId, .pending) }
      flushOutbox()
    } catch {
      notify { $0.onError?(error) }
    }
    return queued
  }
  @discardableResult public func uploadAndSendImage(conversationId: String, fileURL: URL, progress: @escaping @Sendable (Int64, Int64) -> Void = { _, _ in }) -> PteIMMessage {
    uploadAndSendMedia(conversationId: conversationId, fileURL: fileURL, type: .image, progress: progress)
  }
  @discardableResult public func uploadAndSendVideo(conversationId: String, fileURL: URL, progress: @escaping @Sendable (Int64, Int64) -> Void = { _, _ in }) -> PteIMMessage {
    uploadAndSendMedia(conversationId: conversationId, fileURL: fileURL, type: .video, progress: progress)
  }
  @discardableResult public func uploadAndSendFile(conversationId: String, fileURL: URL, progress: @escaping @Sendable (Int64, Int64) -> Void = { _, _ in }) -> PteIMMessage {
    uploadAndSendMedia(conversationId: conversationId, fileURL: fileURL, type: .file, progress: progress)
  }
  @discardableResult public func uploadAndSendVoice(conversationId: String, fileURL: URL, durationMs: Int64, waveform: String? = nil, progress: @escaping @Sendable (Int64, Int64) -> Void = { _, _ in }) -> PteIMMessage {
    precondition(durationMs > 0, "durationMs must be positive")
    return uploadAndSendMedia(conversationId: conversationId, fileURL: fileURL, type: .voice, voiceDurationMs: durationMs, waveform: waveform, progress: progress)
  }

  public func syncNow() {
    Task { [weak self] in
      guard let self else { return }
      do {
        let cursor = try self.store.cursor()
        guard let delta = try await self.sdkPayload(path: "v1/im/sync", body: ["syncCursor": cursor, "pageSize": 200]) as? [String: Any],
              let wireMessages = delta["messages"] as? [[String: Any]], let nextCursor = delta["nextCursor"] as? String else { throw PteIMError.invalidResponse }
        let messages = try wireMessages.map(self.decodeMessage).map(self.resolveMessage)
        try self.store.apply(messages: messages, nextCursor: nextCursor)
        messages.forEach { message in self.notify { $0.onMessage?(message) } }
        if (delta["hasMore"] as? Bool) == true { self.syncNow() }
      } catch { self.notify { $0.onError?(error) } }
    }
  }
  public func syncStateNow() {
    Task { [weak self] in
      guard let self else { return }
      do {
        let cursor = try self.store.stateCursor()
        let page = try await self.syncState(cursor: cursor, limit: 100)
        try self.store.setStateCursor(page.nextCursor)
        self.notify { $0.onStateChanges?(page.changes) }
        if page.hasMore { self.syncStateNow() }
      } catch { self.notify { $0.onError?(error) } }
    }
  }
  public func syncConversationsNow() {
    Task { [weak self] in
      guard let self else { return }
      do { let page = try await self.fetchConversationCursorPage(cursor: try self.store.conversationCursor()); try self.store.applyRemoteConversations(page.list, nextCursor: page.nextCursor); if page.hasMore { self.syncConversationsNow() } }
      catch { self.notify { $0.onError?(error) } }
    }
  }
  public func fetchConversationCursorPage(cursor: String = "", limit: Int = 50) async throws -> PteIMGroupPage { try await sdkRequest(path: "v1/im/conversations/cursor", body: ["cursor":cursor,"limit":limit], response: PteIMGroupPage.self) }
  public func localRemoteConversations(limit: Int = 100) throws -> [PteIMRemoteConversation] { try store.localRemoteConversations(limit: limit) }

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

  /** Reads the account-isolated Core Data cache. Call [syncNow] first when fresh server state is required. */
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
    guard let conversationId = UInt64(message.conversationId), conversationId > 0 else {
      notify { $0.onError?(PteIMError.invalidConversationId) }
      return message
    }
    var outgoing = message; outgoing.senderId = config.userId
    do { try store.enqueue(outgoing); notify { $0.onMessageStateChanged?(outgoing.clientMsgId, .pending) }; flushOutbox() }
    catch { notify { $0.onError?(error) } }
    return outgoing
  }

  private func uploadAndSendMedia(conversationId: String, fileURL: URL, type: PteIMMessageType, voiceDurationMs: Int64? = nil, waveform: String? = nil, progress: @escaping @Sendable (Int64, Int64) -> Void) -> PteIMMessage {
    guard let numericConversationId = UInt64(conversationId), numericConversationId > 0 else {
      let message = PteIMMessage(conversationId: conversationId, type: type, state: .failed)
      notify { $0.onError?(PteIMError.invalidConversationId) }
      return message
    }
    let message = PteIMMessage(conversationId: conversationId, senderId: config.userId, type: type, state: .uploading)
    do { try store.enqueue(message); notify { $0.onMessageStateChanged?(message.clientMsgId, .uploading) } }
    catch { notify { $0.onError?(error) }; return message }
    let queuedMessage = message
    Task { [weak self, message = queuedMessage] in
      guard let self else { return }
      var message = message
      do {
        let uploaded = try await self.uploadMedia(fileURL: fileURL, type: type, progress: progress)
        if type == .voice {
          guard let key = uploaded.url, let durationMs = voiceDurationMs, durationMs > 0 else { throw PteIMError.invalidResponse }
          message.voice = PteIMVoice(url: key, durationMs: durationMs, waveform: waveform, sizeBytes: uploaded.sizeBytes)
        } else {
          var attachedMedia = uploaded
          if type == .file {
            attachedMedia.fileName = fileURL.lastPathComponent
            attachedMedia.mimeType = try self.cosContentType(for: fileURL, type: type)
          }
          message.media = attachedMedia
        }
        message.state = .pending
        try self.store.replaceQueued(message)
        self.notify { $0.onMessageStateChanged?(message.clientMsgId, .pending) }
        self.flushOutbox()
      } catch {
        try? self.store.markFailed(clientMsgId: message.clientMsgId)
        self.notify { $0.onMessageStateChanged?(message.clientMsgId, .failed) }; self.notify { $0.onError?(error) }
      }
    }
    return queuedMessage
  }

  private func sendQueued(_ message: PteIMMessage) {
    Task { [weak self] in
      guard let self else { return }
      do {
        let encrypted = try await self.e2ee.encrypt(message) { path, body in try await self.e2eeRequest(path: path, body: body) }
        self.sendEnvelope(action: "send_message", payload: ["clientMsgId": message.clientMsgId, "conversationId": message.conversationId, "type": message.type.rawValue, "e2ee": encrypted])
      } catch { self.notify { $0.onError?(error) } }
    }
  }

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
    } catch { notify { $0.onError?(error) } }
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
      case .failure(let error): self.socketConnected = false; self.notify { $0.onError?(error) }; self.notify { $0.onConnectionChanged?(false) }; self.scheduleReconnect()
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
        notify { $0.onMessage?(message) }; sendEnvelope(action: "ack", payload: ["serverMsgId": message.serverMsgId ?? ""])
      case "ack":
        guard let id = payload["clientMsgId"] as? String else { return }
        let sequence = (payload["serverSeq"] as? NSNumber)?.int64Value
        try store.markSent(clientMsgId: id, serverMsgId: payload["serverMsgId"] as? String, serverSeq: sequence)
        notify { $0.onMessageStateChanged?(id, .sent) }
      case "user_sig_will_expire": notify { $0.onUserSigWillExpire?() }
      case "user_sig_expired": notify { $0.onUserSigExpired?() }
      case "sync_required": syncNow()
      default: break
      }
    } catch { notify { $0.onError?(error) } }
  }

  private func sendEnvelope(action: String, payload: [String: Any]) {
    guard let socket else { notify { $0.onError?(PteIMError.disconnected) }; return }
    let body: [String: Any] = ["protocolVersion": 1, "action": action, "requestId": UUID().uuidString, "sdkAppId": config.sdkAppId, "userId": config.userId, "userSig": config.userSig, "payload": payload]
    do {
      let text = String(decoding: try JSONSerialization.data(withJSONObject: body), as: UTF8.self)
      socket.send(.string(text)) { [weak self] error in if let error { self?.notify { $0.onError?(error) } } }
    } catch { notify { $0.onError?(error) } }
  }

  private func decodeMessage(_ payload: [String: Any]) throws -> PteIMMessage {
    var cleartext = payload
    if let envelope = payload["e2ee"] as? [String: Any] { cleartext["content"] = try e2ee.decrypt(envelope) }
    return resolveMessage(try JSONDecoder().decode(PteIMMessage.self, from: JSONSerialization.data(withJSONObject: cleartext)))
  }

  private func uploadMedia(fileURL: URL, type: PteIMMessageType, progress: @escaping @Sendable (Int64, Int64) -> Void) async throws -> PteIMMedia {
    let fileSize = try fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize.map(Int64.init) ?? 0
    guard fileSize > 0 else { throw PteIMError.invalidResponse }
    let contentType = try cosContentType(for: fileURL, type: type)
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
    let payload = try await sdkPayload(path: path, body: body)
    return try JSONDecoder().decode(T.self, from: JSONSerialization.data(withJSONObject: payload))
  }

  private func e2eeRequest(path: String, body: [String: Any]) async throws -> Any {
    try await sdkPayload(path: path, body: body)
  }

  /** api-im encrypts every application response with the caller's ephemeral P-256 public key. */
  private func sdkPayload(path: String, body: [String: Any]) async throws -> Any {
    var request = URLRequest(url: config.apiDomain.appendingPathComponent(path))
    request.httpMethod = "POST"; request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.setValue("Bearer \(config.userSig)", forHTTPHeaderField: "Authorization")
    request.setValue(String(config.sdkAppId), forHTTPHeaderField: "X-Pte-Sdk-AppId"); request.setValue(config.userId, forHTTPHeaderField: "X-Pte-User-Id")
    let responseKey = PteIMResponseCipher.requestKey()
    request.setValue(PteIMResponseCipher.requestPublicKey(responseKey), forHTTPHeaderField: "X-Pte-Response-Public-Key")
    request.httpBody = try JSONSerialization.data(withJSONObject: body)
    let (data, httpResponse) = try await session.data(for: request)
    guard let http = httpResponse as? HTTPURLResponse, 200..<300 ~= http.statusCode else { throw PteIMError.invalidResponse }
    let clear = try PteIMResponseCipher.decrypt(data, with: responseKey)
    guard let envelope = try JSONSerialization.jsonObject(with: clear) as? [String: Any],
          (envelope["code"] as? NSNumber)?.intValue == 1, let value = envelope["data"] else { throw PteIMError.invalidResponse }
    return value
  }

  internal func commercePayload(path: String, body: [String: Any]) async throws -> Any {
    guard let commerceDomain = config.commerceDomain else { throw PteIMError.commerceNotConfigured }
    var request = URLRequest(url: commerceDomain.appendingPathComponent(path))
    request.httpMethod = "POST"; request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.setValue("Bearer \(config.userSig)", forHTTPHeaderField: "Authorization")
    request.setValue(String(config.sdkAppId), forHTTPHeaderField: "X-Pte-Sdk-AppId"); request.setValue(config.userId, forHTTPHeaderField: "X-Pte-User-Id")
    request.httpBody = try JSONSerialization.data(withJSONObject: body)
    let (data, httpResponse) = try await session.data(for: request)
    guard let http = httpResponse as? HTTPURLResponse, 200..<300 ~= http.statusCode,
          let envelope = try JSONSerialization.jsonObject(with: data) as? [String: Any],
          (envelope["code"] as? NSNumber)?.intValue == 1, let value = envelope["data"] else { throw PteIMError.invalidResponse }
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

  private func cosContentType(for fileURL: URL, type: PteIMMessageType) throws -> String {
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
    case "pdf": return "application/pdf"
    case "csv": return "text/csv"
    case "json": return "application/json"
    case "zip": return "application/zip"
    case "7z": return "application/x-7z-compressed"
    case "doc": return "application/msword"
    case "docx": return "application/vnd.openxmlformats-officedocument.wordprocessingml.document"
    case "xls": return "application/vnd.ms-excel"
    case "xlsx": return "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"
    case "ppt": return "application/vnd.ms-powerpoint"
    case "pptx": return "application/vnd.openxmlformats-officedocument.presentationml.presentation"
    case "txt": return "text/plain"
    default:
      if type == .image { return "image/jpeg" }
      if type == .voice { return "audio/mpeg" }
      if type == .file { throw PteIMError.invalidResponse }
      return "video/mp4"
    }
  }

  private func resolveMessage(_ message: PteIMMessage) -> PteIMMessage { var value = message; value.media = value.media.map(resolveMedia); value.voice = value.voice.map { var voice = $0; voice.url = resolveCosURL(voice.url) ?? voice.url; return voice }; return value }
  private func storedMessageToModel(_ stored: StoredMessage) throws -> PteIMMessage {
    let object = try JSONSerialization.jsonObject(with: Data(stored.payload.utf8)) as? [String: Any] ?? [:]
    var value = try decodeMessage(object)
    value.serverMsgId = stored.serverMsgId; value.serverSeq = stored.serverSeq
    if stored.createdAt > 0 { value = PteIMMessage(conversationId: value.conversationId, senderId: value.senderId, type: value.type, text: value.text, packageId: value.packageId, emojiId: value.emojiId, media: value.media, voice: value.voice, location: value.location, business: value.business, clientMsgId: value.clientMsgId, createdAt: stored.createdAt, state: value.state); value.serverMsgId = stored.serverMsgId; value.serverSeq = stored.serverSeq }
    value.state = PteIMSendState(rawValue: stored.state) ?? .sent
    return value
  }
  private func resolveMedia(_ media: PteIMMedia) -> PteIMMedia { var value = media; value.url = resolveCosURL(value.url); value.thumbnailUrl = resolveCosURL(value.thumbnailUrl); value.coverUrl = resolveCosURL(value.coverUrl); return value }
  private func resolveCosURL(_ value: String?) -> String? {
    guard let value, URL(string: value)?.scheme == nil else { return value }
    return config.cosDomain.appendingPathComponent(value.trimmingCharacters(in: CharacterSet(charactersIn: "/"))).absoluteString
  }

  /** The configured IM service validates UserSig during the WSS upgrade. Browsers cannot attach arbitrary
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

extension PteIMSDK: URLSessionWebSocketDelegate {
  public func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didOpenWithProtocol protocol: String?) {
    reconnectAttempt = 0
    socketConnected = true
    notify { $0.onConnectionChanged?(true) }
    sendEnvelope(action: "login", payload: ["syncCursor": (try? store.cursor()) ?? ""])
    receiveNext(); flushOutbox(); syncNow(); syncStateNow(); syncConversationsNow()
  }
  public func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didCloseWith closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?) {
    socketConnected = false
    notify { $0.onConnectionChanged?(false) }
    scheduleReconnect()
  }
}

private struct PteIMOKResponse: Decodable { let ok: Bool }
/** Plain response shape used only by api-im's COS credential endpoint. */
private struct PteIMSDKEnvelope<T: Decodable>: Decodable { let code: Int; let msg: String; let data: T? }
private struct PteIMCosPutCredential: Decodable { let key: String; let uploadUrl: String; let headers: [String: String]; let expiresAt: Int64 }

public final class PteIMSDKBootstrap {
  private let baseConfig: PteIMBaseConfig
  internal init(baseConfig: PteIMBaseConfig) { self.baseConfig = baseConfig }
  public func login(_ loginConfig: PteIMLoginConfig) throws -> PteIMSDK {
    let client = try PteIMSDK(config: PteIMSessionConfig(base: baseConfig, login: loginConfig))
    client.start()
    return client
  }

  /**
   * Clears only this account's SDK cache and Keychain cache key. Stop a running client first,
   * then log in and call syncNow() to rebuild cache data from the service.
   */
  public func clearLocalCache(_ loginConfig: PteIMLoginConfig) throws {
    try PteIMCoreDataStore.clear(storeKey: PteIMSessionConfig(base: baseConfig, login: loginConfig).storeKey)
  }
}

extension PteIMMessage {
  var contentDictionary: [String: Any] {
    var content: [String: Any] = [:]
    if let text { content["text"] = text }; if let packageId { content["packageId"] = packageId }; if let emojiId { content["emojiId"] = emojiId }
    if let media { if let url = media.url { content["url"] = url }; if let thumbnailUrl = media.thumbnailUrl { content["thumbnailUrl"] = thumbnailUrl }; if let coverUrl = media.coverUrl { content["coverUrl"] = coverUrl }; if let width = media.width { content["width"] = width }; if let height = media.height { content["height"] = height }; if let durationMs = media.durationMs { content["durationMs"] = durationMs }; if let sizeBytes = media.sizeBytes { content["sizeBytes"] = sizeBytes }; if let fileName = media.fileName { content["fileName"] = fileName }; if let mimeType = media.mimeType { content["mimeType"] = mimeType } }
    if let voice { content["url"] = voice.url; content["durationMs"] = voice.durationMs; if let waveform = voice.waveform { content["waveform"] = waveform }; if let sizeBytes = voice.sizeBytes { content["sizeBytes"] = sizeBytes } }
    if let location { content["latitude"] = location.latitude; content["longitude"] = location.longitude; content["name"] = location.name; if let address = location.address { content["address"] = address } }
    if let business { content["businessId"] = business.businessId; content["title"] = business.title; if let subtitle = business.subtitle { content["subtitle"] = subtitle }; if let actionURL = business.actionUrl { content["actionUrl"] = actionURL } }
    return content
  }

  fileprivate var dictionary: [String: Any] { ["clientMsgId": clientMsgId, "conversationId": conversationId, "type": type.rawValue, "createdAt": createdAt, "content": contentDictionary] }
}

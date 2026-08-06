import Foundation

/** Room scene kinds owned by [PteIMSceneClient]. */
public enum PteIMSceneKind: String, Sendable { case show, voice, shop, sports }

public struct PteIMSceneEntered: Sendable {
  public let scene: PteIMSceneKind
  public let roomId: String
  public let groupName: String
  public let requestId: String
}

public struct PteIMLiveEventEnvelope: Sendable {
  public let eventId: String?
  public let roomSeq: Int64?
  public let serverTs: Int64?
  public let priority: String?
}

public struct PteIMLiveRoomEventRow {
  public let eventId: String
  public let eventType: String
  public let roomSeq: Int64
  public let payload: [String: Any]
}

public struct PteIMSceneCatchUpPage {
  public let currentRoomSeq: Int64
  public let events: [PteIMLiveRoomEventRow]
}

/** Host-injected HTTP catch-up source for roomSeq gaps. */
public protocol PteIMSceneCatchUpSource: Sendable {
  func getCurrentRoomSeq() async throws -> Int64
  func fetchEventsAfter(_ afterSeq: Int64, limit: Int) async throws -> PteIMSceneCatchUpPage
}

/** Scene event receiver; register multiple listeners via [PteIMSceneClient.addListener]. */
public final class PteIMSceneListener: @unchecked Sendable {
  public var onConnectionChanged: ((Bool) -> Void)?
  public var onEntered: ((PteIMSceneEntered) -> Void)?
  public var onEnterFailed: ((PteIMSceneKind, String, String) -> Void)?
  public var onEvent: ((String, [String: Any], PteIMLiveEventEnvelope) -> Void)?
  public var onError: ((String) -> Void)?

  public init() {}
}

/**
 Independent scene WSS client (show / voice / shop / sports).
 Does not share a socket with chat; the host supplies room-scoped UserSig and catch-up HTTP.
 */
public final class PteIMSceneClient: NSObject, @unchecked Sendable, URLSessionWebSocketDelegate {
  private let wsURL: URL
  private let sdkAppId: Int64
  private lazy var session = URLSession(configuration: .default, delegate: self, delegateQueue: nil)
  private var socket: URLSessionWebSocketTask?
  private var reconnectWorkItem: DispatchWorkItem?
  private let queue = DispatchQueue(label: "com.ptelive.im.scene")
  private var listeners: [ObjectIdentifier: PteIMSceneListener] = [:]
  private let tracker = RoomSeqTracker()
  private var stopped = true
  private var handshaken = false
  private var userId = ""
  private var userSig = ""
  private var userSigExpireAt: Int64 = 0
  private var reconnectAttempt = 0
  private struct ActiveRoom {
    let scene: PteIMSceneKind
    let roomId: String
    let extend: String?
    let catchUp: (any PteIMSceneCatchUpSource)?
  }
  private var active: ActiveRoom?
  private struct PendingEnter {
    let requestId: String
    let scene: PteIMSceneKind
    let roomId: String
    let timer: DispatchWorkItem
    let continuation: CheckedContinuation<PteIMSceneEntered, Error>
  }
  private var pendingEnter: PendingEnter?
  private var catchUpBusy = false
  private var pendingConnect: CheckedContinuation<Void, Error>?
  private var connectTimeoutWorkItem: DispatchWorkItem?

  internal init(wsURL: URL, sdkAppId: Int64) {
    self.wsURL = wsURL
    self.sdkAppId = sdkAppId
    super.init()
  }

  public func addListener(_ listener: PteIMSceneListener) {
    queue.sync {
      listeners[ObjectIdentifier(listener)] = listener
      if handshaken, socket != nil { listener.onConnectionChanged?(true) }
    }
  }

  public func removeListener(_ listener: PteIMSceneListener) {
    queue.sync { listeners.removeValue(forKey: ObjectIdentifier(listener)) }
  }

  public func getLastRoomSeq() -> Int64 { queue.sync { tracker.lastRoomSeq } }

  public func isConnected() -> Bool { queue.sync { handshaken && socket != nil } }

  public func renewUserSig(_ userSig: String, expireAt: Int64 = 0) throws {
    guard !userSig.isEmpty else { throw PteIMError.invalidCredentials }
    queue.sync {
      self.userSig = userSig
      self.userSigExpireAt = expireAt
    }
  }

  /** Opens an independent WSS connection and waits for the server handshake frame (code=0). */
  public func connect(userId: String, userSig: String, expireAt: Int64 = 0) async throws {
    guard !userId.isEmpty, !userSig.isEmpty else { throw PteIMError.invalidCredentials }
    try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
      queue.async {
        self.userId = userId
        self.userSig = userSig
        self.userSigExpireAt = expireAt
        self.stopped = false
        if self.handshaken, self.socket != nil {
          continuation.resume()
          return
        }
        self.pendingConnect = continuation
        self.openSocket()
        let timeout = DispatchWorkItem { [weak self] in
          guard let self, let pending = self.pendingConnect else { return }
          self.pendingConnect = nil
          pending.resume(throwing: PteIMSceneError.handshakeTimeout)
          self.socket?.cancel(with: .goingAway, reason: nil)
        }
        self.connectTimeoutWorkItem = timeout
        self.queue.asyncAfter(deadline: .now() + 15, execute: timeout)
      }
    }
  }

  public func enter(
    scene: PteIMSceneKind,
    roomId: String,
    extend: String? = nil,
    catchUp: (any PteIMSceneCatchUpSource)? = nil,
    enterTimeoutMs: Int = 15_000
  ) async throws -> PteIMSceneEntered {
    try assertSceneRoomId(scene: scene, roomId: roomId)
    guard !userId.isEmpty, !userSig.isEmpty else { throw PteIMError.invalidCredentials }
    let trimmedRoomId = roomId.trimmingCharacters(in: .whitespacesAndNewlines)
    if !isConnected() { try await connect(userId: userId, userSig: userSig, expireAt: userSigExpireAt) }
    queue.sync { active = ActiveRoom(scene: scene, roomId: trimmedRoomId, extend: extend, catchUp: catchUp) }
    if let catchUp {
      try await runCatchUp(catchUp) { [weak self] eventType, payload in
        self?.emitEvent(eventType: eventType, payload: payload)
      }
    }
    return try await sendEnter(scene: scene, roomId: trimmedRoomId, extend: extend, catchUp: catchUp, timeoutMs: enterTimeoutMs)
  }

  public func leave() {
    queue.async {
      if let current = self.active, self.handshaken {
        self.sendRaw([
          "action": "scene.leave",
          "request_id": UUID().uuidString,
          "scene": current.scene.rawValue,
          "room_id": current.roomId,
        ])
      }
      self.active = nil
      self.clearPendingEnter(message: "已离房")
    }
  }

  public func disconnect() {
    queue.async {
      self.stopped = true
      self.active = nil
      self.clearPendingEnter(message: "已断开")
      self.reconnectWorkItem?.cancel()
      self.reconnectWorkItem = nil
      self.socket?.cancel(with: .goingAway, reason: nil)
      self.socket = nil
      self.handshaken = false
      self.notifyConnection(false)
    }
  }

  public func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didOpenWithProtocol protocol: String?) {
    queue.async { self.receiveNext() }
  }

  public func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didCloseWith closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?) {
    queue.async {
      self.socket = nil
      self.handshaken = false
      self.notifyConnection(false)
      self.scheduleReconnect()
    }
  }

  private func openSocket() {
    socket?.cancel(with: .goingAway, reason: nil)
    handshaken = false
    let task = session.webSocketTask(with: webSocketURL())
    socket = task
    task.resume()
  }

  private func webSocketURL() -> URL {
    var components = URLComponents(url: wsURL, resolvingAgainstBaseURL: false)!
    var items = components.queryItems ?? []
    items.append(URLQueryItem(name: "sdkAppID", value: String(sdkAppId)))
    items.append(URLQueryItem(name: "identifier", value: userId))
    items.append(URLQueryItem(name: "userSig", value: userSig))
    components.queryItems = items
    return components.url!
  }

  private func receiveNext() {
    socket?.receive { [weak self] result in
      guard let self else { return }
      switch result {
      case .success(.string(let text)):
        self.queue.async { self.handleFrame(text) }
        self.receiveNext()
      case .success(.data(let data)):
        self.queue.async { self.handleFrame(String(decoding: data, as: UTF8.self)) }
        self.receiveNext()
      case .failure(let error):
        self.queue.async {
          self.emitError(error.localizedDescription)
          self.pendingConnect?.resume(throwing: error)
          self.pendingConnect = nil
          self.socket = nil
          self.handshaken = false
          self.notifyConnection(false)
          self.scheduleReconnect()
        }
      @unknown default: break
      }
    }
  }

  private func handleFrame(_ raw: String) {
    guard let data = raw.data(using: .utf8),
          let frame = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
      emitError("Scene 帧解析失败")
      return
    }

    if !handshaken, (frame["code"] as? NSNumber)?.intValue == 0, frame["data"] != nil {
      handshaken = true
      reconnectAttempt = 0
      connectTimeoutWorkItem?.cancel()
      connectTimeoutWorkItem = nil
      notifyConnection(true)
      pendingConnect?.resume()
      pendingConnect = nil
      return
    }

    var payloadData: [String: Any]?
    if let text = frame["data"] as? String, let object = try? JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any] {
      payloadData = object
    } else if let object = frame["data"] as? [String: Any] {
      payloadData = object
    }

    let msg = frame["msg"] as? String ?? ""
    if payloadData?["type"] as? String == "scene.ack" || msg.contains("scene") {
      let ok = (payloadData?["ok"] as? Bool) == true || (payloadData?["ok"] as? String) == "true"
      let requestId = stringOf(payloadData?["request_id"] ?? payloadData?["requestId"])
      let scene = sceneKindOf(stringOf(payloadData?["scene"]).isEmpty ? (active?.scene.rawValue ?? "show") : stringOf(payloadData?["scene"]))
      let roomId = stringOf(payloadData?["room_id"] ?? payloadData?["roomId"]).isEmpty ? (active?.roomId ?? "") : stringOf(payloadData?["room_id"] ?? payloadData?["roomId"])
      if let pending = pendingEnter, pending.requestId.isEmpty || requestId.isEmpty || requestId == pending.requestId {
        pendingEnter = nil
        pending.timer.cancel()
        if ok {
          let groupName = stringOf(payloadData?["group_name"] ?? payloadData?["groupName"]).isEmpty
            ? groupNameForScene(scene: scene, roomId: roomId) : stringOf(payloadData?["group_name"] ?? payloadData?["groupName"])
          let entered = PteIMSceneEntered(scene: scene, roomId: roomId, groupName: groupName, requestId: pending.requestId)
          notify { $0.onEntered?(entered) }
          pending.continuation.resume(returning: entered)
        } else {
          let message = msg.isEmpty ? "scene.enter 失败" : msg
          notify { $0.onEnterFailed?(scene, roomId, message) }
          pending.continuation.resume(throwing: PteIMSceneError.enterFailed(message))
        }
      }
      return
    }

    let parsed = eventTypeFromFrame(frame)
    guard let eventType = parsed.eventType, let payload = parsed.payload else { return }
    if tracker.needsCatchUp(payload) {
      guard let source = active?.catchUp, !catchUpBusy else { return }
      catchUpBusy = true
      Task { [weak self] in
        defer { self?.queue.async { self?.catchUpBusy = false } }
        do {
          try await self?.runCatchUp(source) { eventType, payload in
            self?.emitEvent(eventType: eventType, payload: payload)
          }
        } catch {
          self?.emitError(error.localizedDescription)
        }
      }
      return
    }
    if tracker.accept(payload) { emitEvent(eventType: eventType, payload: payload) }
  }

  private func sendEnter(scene: PteIMSceneKind, roomId: String, extend: String?, catchUp: (any PteIMSceneCatchUpSource)?, timeoutMs: Int) async throws -> PteIMSceneEntered {
    try await withCheckedThrowingContinuation { continuation in
      queue.async {
        guard self.handshaken, self.socket != nil else {
          continuation.resume(throwing: PteIMSceneError.notConnected)
          return
        }
        self.active = ActiveRoom(scene: scene, roomId: roomId, extend: extend, catchUp: catchUp)
        let requestId = UUID().uuidString
        let timer = DispatchWorkItem { [weak self] in
          guard let self, let pending = self.pendingEnter, pending.requestId == requestId else { return }
          self.pendingEnter = nil
          let message = "scene.enter 超时"
          self.notify { $0.onEnterFailed?(scene, roomId, message) }
          pending.continuation.resume(throwing: PteIMSceneError.enterFailed(message))
        }
        self.pendingEnter = PendingEnter(requestId: requestId, scene: scene, roomId: roomId, timer: timer, continuation: continuation)
        self.queue.asyncAfter(deadline: .now() + .milliseconds(timeoutMs), execute: timer)
        var body: [String: Any] = [
          "action": "scene.enter",
          "request_id": requestId,
          "scene": scene.rawValue,
          "room_id": roomId,
        ]
        if let extend { body["extend"] = extend }
        self.sendRaw(body)
      }
    }
  }

  private func sendRaw(_ body: [String: Any]) {
    guard handshaken, let socket else { return }
    do {
      let text = String(decoding: try JSONSerialization.data(withJSONObject: body), as: UTF8.self)
      socket.send(.string(text)) { [weak self] error in
        if let error { self?.emitError(error.localizedDescription) }
      }
    } catch {
      emitError(error.localizedDescription)
    }
  }

  private func scheduleReconnect() {
    guard !stopped, reconnectWorkItem == nil else { return }
    let delay = min(pow(2.0, Double(reconnectAttempt)), 30.0)
    reconnectAttempt = min(reconnectAttempt + 1, 5)
    let item = DispatchWorkItem { [weak self] in
      guard let self else { return }
      self.reconnectWorkItem = nil
      Task { try? await self.rejoin() }
    }
    reconnectWorkItem = item
    DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + delay, execute: item)
  }

  private func rejoin() async throws {
    guard !stopped else { return }
    try await connect(userId: userId, userSig: userSig, expireAt: userSigExpireAt)
    guard let current = active else { return }
    if let catchUp = current.catchUp {
      try await runCatchUp(catchUp) { [weak self] eventType, payload in
        self?.emitEvent(eventType: eventType, payload: payload)
      }
    }
    _ = try await sendEnter(scene: current.scene, roomId: current.roomId, extend: current.extend, catchUp: current.catchUp, timeoutMs: 15_000)
  }

  private func clearPendingEnter(message: String) {
    guard let pending = pendingEnter else { return }
    pendingEnter = nil
    pending.timer.cancel()
    pending.continuation.resume(throwing: PteIMSceneError.enterFailed(message))
  }

  private func emitEvent(eventType: String, payload: [String: Any]) {
    let envelope = readEnvelope(payload)
    notify { $0.onEvent?(eventType, payload, envelope) }
  }

  private func notifyConnection(_ connected: Bool) {
    notify { $0.onConnectionChanged?(connected) }
  }

  private func emitError(_ message: String) {
    notify { $0.onError?(message) }
  }

  private func notify(_ callback: (PteIMSceneListener) -> Void) {
    listeners.values.forEach(callback)
  }

  private func runCatchUp(_ source: any PteIMSceneCatchUpSource, apply: @escaping (String, [String: Any]) -> Void) async throws {
    let current = try await source.getCurrentRoomSeq()
    tracker.seedIfFresh(current)
    var after = tracker.lastRoomSeq
    for _ in 0..<20 {
      let page = try await source.fetchEventsAfter(after, limit: 100)
      for row in page.events {
        var payload = parseLivePayload(row.payload) ?? [:]
        if payload["eventId"] == nil { payload["eventId"] = row.eventId }
        if payload["roomSeq"] == nil { payload["roomSeq"] = row.roomSeq }
        if tracker.accept(payload) { apply(row.eventType, payload) }
        if row.roomSeq > after { after = row.roomSeq }
      }
      if page.events.count < 100 {
        if page.currentRoomSeq > tracker.lastRoomSeq { tracker.lastRoomSeq = page.currentRoomSeq }
        break
      }
    }
  }
}

public enum PteIMSceneError: Error, LocalizedError {
  case notConnected
  case handshakeTimeout
  case enterFailed(String)
  case invalidRoomId(String)

  public var errorDescription: String? {
    switch self {
    case .notConnected: return "Scene 未连接"
    case .handshakeTimeout: return "Scene WSS 握手超时"
    case .enterFailed(let message): return message
    case .invalidRoomId(let message): return message
    }
  }
}

/** Tracks roomSeq watermark and eventId dedupe for scene WSS / catch-up. */
public final class RoomSeqTracker: @unchecked Sendable {
  fileprivate var lastRoomSeq: Int64 = 0
  private var seen = Set<String>()

  public init(initialLastRoomSeq: Int64 = 0) { lastRoomSeq = initialLastRoomSeq }

  fileprivate func seedIfFresh(_ currentRoomSeq: Int64) {
    if lastRoomSeq <= 0, currentRoomSeq > 0 { lastRoomSeq = currentRoomSeq }
  }

  /** Returns false if duplicate or stale. */
  @discardableResult public func accept(_ payload: [String: Any]) -> Bool {
    let envelope = readEnvelope(payload)
    if let eventId = envelope.eventId, seen.contains(eventId) { return false }
    if let seq = envelope.roomSeq, seq > 0, seq <= lastRoomSeq {
      if let eventId = envelope.eventId { seen.insert(eventId) }
      return false
    }
    if let eventId = envelope.eventId {
      seen.insert(eventId)
      if seen.count > 2000 { seen = Set(seen.dropFirst(500)) }
    }
    if let seq = envelope.roomSeq, seq > lastRoomSeq { lastRoomSeq = seq }
    return true
  }

  public func needsCatchUp(_ payload: [String: Any]) -> Bool {
    guard let seq = readEnvelope(payload).roomSeq else { return false }
    return seq > lastRoomSeq + 1
  }
}

private func assertSceneRoomId(scene: PteIMSceneKind, roomId: String) throws {
  let id = roomId.trimmingCharacters(in: .whitespacesAndNewlines)
  guard !id.isEmpty else { throw PteIMSceneError.invalidRoomId("roomId 不能为空") }
  if scene == .sports, id.range(of: "^sports-live-\\d+$", options: .regularExpression) == nil {
    throw PteIMSceneError.invalidRoomId("体育房间 roomId 必须为 sports-live-{数字id}")
  }
}

private func groupNameForScene(scene: PteIMSceneKind, roomId: String) -> String {
  switch scene {
  case .shop: return "live:\(roomId)"
  case .sports: return "sports:\(roomId)"
  default: return "\(scene.rawValue):\(roomId)"
  }
}

private func sceneKindOf(_ value: String) -> PteIMSceneKind {
  PteIMSceneKind(rawValue: value.lowercased()) ?? .show
}

private func readEnvelope(_ payload: [String: Any]) -> PteIMLiveEventEnvelope {
  let eventId = payload["eventId"] as? String ?? payload["event_id"] as? String
  let roomSeq = numberValue(payload["roomSeq"] ?? payload["room_seq"])
  let serverTs = numberValue(payload["serverTs"] ?? payload["server_ts"])
  let priority = payload["priority"] as? String
  return PteIMLiveEventEnvelope(eventId: eventId, roomSeq: roomSeq, serverTs: serverTs, priority: priority)
}

private func parseLivePayload(_ raw: Any?) -> [String: Any]? {
  if let text = raw as? String {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty, let data = trimmed.data(using: .utf8),
          let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
    return object
  }
  return raw as? [String: Any]
}

private struct ParsedFrame { let eventType: String?; let payload: [String: Any]? }

private func eventTypeFromFrame(_ frame: [String: Any]) -> ParsedFrame {
  var envelope: Any? = frame["data"]
  if let text = envelope as? String, let data = text.data(using: .utf8) {
    envelope = try? JSONSerialization.jsonObject(with: data)
  }
  guard let root = envelope as? [String: Any] else { return ParsedFrame(eventType: nil, payload: nil) }
  let scene = root["scene"] as? [String: Any]
  let payload = parseLivePayload(scene?["payload"]) ?? flattenPayload(root)
  let eventType = root["event_type"] as? String ?? root["eventType"] as? String ?? frame["msg"] as? String
  return ParsedFrame(eventType: eventType, payload: payload)
}

private func flattenPayload(_ root: [String: Any]) -> [String: Any]? {
  if root["eventId"] != nil || root["event_id"] != nil || root["roomSeq"] != nil || root["room_seq"] != nil { return root }
  return nil
}

private func numberValue(_ raw: Any?) -> Int64? {
  if let value = raw as? NSNumber { return value.int64Value }
  if let text = raw as? String, let value = Int64(text.trimmingCharacters(in: .whitespacesAndNewlines)) { return value }
  return nil
}

private func stringOf(_ value: Any?) -> String {
  guard let value else { return "" }
  if let text = value as? String { return text.trimmingCharacters(in: .whitespacesAndNewlines) }
  return String(describing: value)
}

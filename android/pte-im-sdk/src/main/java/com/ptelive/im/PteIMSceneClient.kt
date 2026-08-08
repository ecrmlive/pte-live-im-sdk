package com.ptelive.im

import org.json.JSONArray
import org.json.JSONObject
import java.net.URLEncoder
import java.util.UUID
import java.util.concurrent.Executors
import java.util.concurrent.ScheduledExecutorService
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicReference

/** Room scene kinds owned by [PteIMSceneClient]. */
enum class PteIMSceneKind { SHOW, VOICE, SHOP, SPORTS }

data class PteIMSceneEntered(
  val scene: PteIMSceneKind,
  val roomId: String,
  val groupName: String,
  val requestId: String,
)

data class PteIMLiveEventEnvelope(
  val eventId: String? = null,
  val roomSeq: Long? = null,
  val serverTs: Long? = null,
  val priority: String? = null,
)

data class PteIMLiveRoomEventRow(
  val eventId: String,
  val eventType: String,
  val roomSeq: Long,
  val payload: JSONObject,
)

data class PteIMSceneCatchUpPage(
  val currentRoomSeq: Long,
  val events: List<PteIMLiveRoomEventRow>,
)

/** Host-injected HTTP catch-up source for roomSeq gaps. */
interface PteIMSceneCatchUpSource {
  fun getCurrentRoomSeq(callback: (Result<Long>) -> Unit)
  fun fetchEventsAfter(afterSeq: Long, limit: Int = 100, callback: (Result<PteIMSceneCatchUpPage>) -> Unit)
}

interface PteIMSceneListener {
  fun onConnectionChanged(connected: Boolean) {}
  fun onEntered(info: PteIMSceneEntered) {}
  fun onEnterFailed(info: PteIMSceneEnterFailed) {}
  fun onEvent(eventType: String, payload: JSONObject, envelope: PteIMLiveEventEnvelope) {}
  fun onError(message: String) {}
}

data class PteIMSceneEnterFailed(val scene: PteIMSceneKind, val roomId: String, val message: String)

/**
 * Independent scene WSS client (show / voice / shop / sports).
 * Does not share a socket with chat; the host supplies room-scoped UserSig and catch-up HTTP.
 */
class PteIMSceneClient internal constructor(
  private val wsUrl: String,
  private val sdkAppId: Long,
) : WssListener {
  private val executor = Executors.newSingleThreadExecutor()
  private val reconnectExecutor: ScheduledExecutorService = Executors.newSingleThreadScheduledExecutor()
  private val listeners = linkedSetOf<PteIMSceneListener>()
  private var tracker = RoomSeqTracker(0)
  private var trackerRoomKey: String? = null
  private var transport: WssTransport? = null
  @Volatile private var stopped = true
  @Volatile private var handshaken = false
  @Volatile private var userId: String = ""
  @Volatile private var userSig: String = ""
  @Volatile private var userSigExpireAt: Long = 0
  private var reconnectAttempt = 0
  private var reconnectFuture: java.util.concurrent.ScheduledFuture<*>? = null
  private var active: ActiveRoom? = null
  private var pendingEnter: PendingEnter? = null
  @Volatile private var catchUpBusy = false
  private var pendingConnect: AtomicReference<((Result<Unit>) -> Unit)?> = AtomicReference(null)
  private var connectTimeoutFuture: java.util.concurrent.ScheduledFuture<*>? = null

  fun addListener(listener: PteIMSceneListener) {
    listeners += listener
    if (handshaken && transport != null) listener.onConnectionChanged(true)
  }

  fun removeListener(listener: PteIMSceneListener) { listeners -= listener }

  fun getLastRoomSeq(): Long = tracker.getLastRoomSeq()

  fun isConnected(): Boolean = handshaken && transport != null

  fun renewUserSig(userSig: String, expireAt: Long = 0) {
    require(userSig.isNotBlank()) { "PTE IM UserSig 不能为空" }
    this.userSig = userSig
    this.userSigExpireAt = expireAt
  }

  /** Opens an independent WSS connection and waits for the server handshake frame (code=0). */
  fun connect(userId: String, userSig: String, expireAt: Long = 0, callback: (Result<Unit>) -> Unit) {
    require(userId.isNotBlank() && userSig.isNotBlank()) { "PTE IM Scene 凭证不完整" }
    executor.execute {
      try {
        this.userId = userId
        this.userSig = userSig
        this.userSigExpireAt = expireAt
        stopped = false
        if (handshaken && transport != null) {
          callback(Result.success(Unit))
          return@execute
        }
        openSocket(callback)
      } catch (error: Throwable) {
        callback(Result.failure(error))
      }
    }
  }

  fun enter(
    scene: PteIMSceneKind,
    roomId: String,
    extend: String? = null,
    catchUp: PteIMSceneCatchUpSource? = null,
    enterTimeoutMs: Long = 15_000,
    callback: (Result<PteIMSceneEntered>) -> Unit,
  ) {
    executor.execute {
      try {
        require(userId.isNotBlank() && userSig.isNotBlank()) { "请先调用 connect" }
        assertSceneRoomId(scene, roomId)
        val normalizedRoomId = roomId.trim()
        val roomKey = "${sceneWire(scene)}:$normalizedRoomId"
        if (trackerRoomKey != roomKey) {
          tracker = RoomSeqTracker(0)
          trackerRoomKey = roomKey
        }
        active = ActiveRoom(scene, normalizedRoomId, extend, catchUp)
        ensureConnected { connectResult ->
          connectResult.onFailure { callback(Result.failure(it)) }.onSuccess {
            if (catchUp != null) {
              runCatchUp(catchUp, { eventType, payload -> emitEvent(eventType, payload) }) { catchUpResult ->
                catchUpResult.onFailure { callback(Result.failure(it)) }.onSuccess { sendEnter(enterTimeoutMs, callback) }
              }
            } else {
              sendEnter(enterTimeoutMs, callback)
            }
          }
        }
      } catch (error: Throwable) {
        callback(Result.failure(error))
      }
    }
  }

  fun leave() {
    executor.execute {
      val current = active
      if (current != null && handshaken) {
        sendRaw(JSONObject().apply {
          put("action", "scene.leave")
          put("request_id", UUID.randomUUID().toString())
          put("scene", sceneWire(current.scene))
          put("room_id", current.roomId)
        })
      }
      active = null
      clearPendingEnter("已离房")
    }
  }

  fun disconnect() {
    executor.execute {
      stopped = true
      active = null
      clearPendingEnter("已断开")
      reconnectFuture?.cancel(false)
      reconnectFuture = null
      transport?.close()
      transport = null
      handshaken = false
      notifyConnection(false)
    }
  }

  override fun onOpen() { /* wait for handshake frame code=0 */ }

  override fun onText(text: String) {
    executor.execute { handleFrame(text) }
  }

  override fun onClosed() {
    executor.execute {
      if (transport == null) return@execute
      transport = null
      handshaken = false
      notifyConnection(false)
      scheduleReconnect()
    }
  }

  override fun onFailure(error: Throwable) {
    executor.execute {
      emitError(error.message ?: "Scene WSS 连接异常")
      pendingConnect.getAndSet(null)?.invoke(Result.failure(error))
    }
  }

  private data class ActiveRoom(
    val scene: PteIMSceneKind,
    val roomId: String,
    val extend: String?,
    val catchUp: PteIMSceneCatchUpSource?,
  )

  private data class PendingEnter(
    val requestId: String,
    val scene: PteIMSceneKind,
    val roomId: String,
    val timer: java.util.concurrent.ScheduledFuture<*>,
    val callback: (Result<PteIMSceneEntered>) -> Unit,
  )

  private fun ensureConnected(callback: (Result<Unit>) -> Unit) {
    if (handshaken && transport != null) {
      callback(Result.success(Unit))
      return
    }
    openSocket(callback)
  }

  private fun openSocket(callback: ((Result<Unit>) -> Unit)? = null) {
    transport?.close()
    transport = null
    handshaken = false
    connectTimeoutFuture?.cancel(false)
    pendingConnect.set(callback)
    connectTimeoutFuture = reconnectExecutor.schedule({
      executor.execute {
        val pending = pendingConnect.getAndSet(null) ?: return@execute
        pending.invoke(Result.failure(IllegalStateException("Scene WSS 握手超时")))
        transport?.close()
        transport = null
      }
    }, 15_000, TimeUnit.MILLISECONDS)
    transport = WssTransport(webSocketUrl(), this).also { it.connect() }
  }

  private fun webSocketUrl(): String {
    val separator = if (wsUrl.contains('?')) '&' else '?'
    fun encoded(value: String) = URLEncoder.encode(value, Charsets.UTF_8.name()).replace("+", "%20")
    return wsUrl + separator + "sdkAppID=${encoded(sdkAppId.toString())}" +
      "&identifier=${encoded(userId)}&userSig=${encoded(userSig)}&purpose=scene"
  }

  private fun handleFrame(raw: String, onHandshake: (() -> Unit)? = null) {
    val frame = try {
      JSONObject(raw)
    } catch (_: Throwable) {
      emitError("Scene 帧解析失败")
      return
    }

    if (!handshaken && frame.optInt("code", -1) == 0 && !frame.isNull("data")) {
      handshaken = true
      reconnectAttempt = 0
      connectTimeoutFuture?.cancel(false)
      connectTimeoutFuture = null
      notifyConnection(true)
      pendingConnect.getAndSet(null)?.invoke(Result.success(Unit))
      onHandshake?.invoke()
      return
    }

    var data: JSONObject? = null
    when (val dataRaw = frame.opt("data")) {
      is String -> runCatching { data = JSONObject(dataRaw) }
      is JSONObject -> data = dataRaw
    }

    val msg = frame.optString("msg")
    if (data?.optString("type") == "scene.ack" || msg == "scene.ack") {
      val ok = data?.optBoolean("ok") == true || data?.optString("ok") == "true"
      val requestId = stringOf(data?.opt("request_id") ?: data?.opt("requestId"))
      val scene = sceneKindOf(stringOf(data?.opt("scene")).ifBlank { active?.scene?.let(::sceneWire) ?: "show" })
      val roomId = stringOf(data?.opt("room_id") ?: data?.opt("roomId")).ifBlank { active?.roomId ?: "" }
      val pending = pendingEnter
      if (pending != null && (pending.requestId.isBlank() || requestId.isBlank() || requestId == pending.requestId)) {
        pendingEnter = null
        pending.timer.cancel(false)
        if (ok) {
          val groupName = stringOf(data?.opt("group_name") ?: data?.opt("groupName"))
            .ifBlank { groupNameForScene(scene, roomId) }
          val entered = PteIMSceneEntered(scene, roomId, groupName, pending.requestId)
          listeners.forEach { it.onEntered(entered) }
          pending.callback(Result.success(entered))
        } else {
          val message = msg.ifBlank { "scene.enter 失败" }
          val failed = PteIMSceneEnterFailed(scene, roomId, message)
          listeners.forEach { it.onEnterFailed(failed) }
          pending.callback(Result.failure(IllegalStateException(message)))
        }
      }
      return
    }

    val parsed = eventTypeFromFrame(frame)
    val eventType = parsed.first ?: return
    val payload = parsed.second ?: return
    if (tracker.needsCatchUp(payload)) {
      val source = active?.catchUp
      if (source != null && !catchUpBusy) {
        catchUpBusy = true
        runCatchUp(source, { type, row -> emitEvent(type, row) }) {
          catchUpBusy = false
          it.onFailure { error -> emitError(error.message ?: "Scene 补漏失败") }
        }
      }
      return
    }
    if (tracker.accept(payload)) emitEvent(eventType, payload)
  }

  private fun sendEnter(timeoutMs: Long, callback: (Result<PteIMSceneEntered>) -> Unit) {
    val current = active ?: return callback(Result.failure(IllegalStateException("未设置进房参数")))
    if (!handshaken || transport == null) return callback(Result.failure(IllegalStateException("Scene 未连接")))
    val requestId = UUID.randomUUID().toString()
    val timer = reconnectExecutor.schedule({
      executor.execute {
        val pending = pendingEnter ?: return@execute
        if (pending.requestId != requestId) return@execute
        pendingEnter = null
        val message = "scene.enter 超时"
        listeners.forEach { it.onEnterFailed(PteIMSceneEnterFailed(current.scene, current.roomId, message)) }
        pending.callback(Result.failure(IllegalStateException(message)))
      }
    }, timeoutMs, TimeUnit.MILLISECONDS)
    pendingEnter = PendingEnter(requestId, current.scene, current.roomId, timer, callback)
    sendRaw(JSONObject().apply {
      put("action", "scene.enter")
      put("request_id", requestId)
      put("scene", sceneWire(current.scene))
      put("room_id", current.roomId)
      current.extend?.let { put("extend", it) }
    })
  }

  private fun sendRaw(body: JSONObject) {
    if (!handshaken) return
    runCatching { transport?.sendText(body.toString()) }.onFailure { emitError(it.message ?: "Scene 发送失败") }
  }

  private fun scheduleReconnect() {
    if (stopped || reconnectFuture != null) return
    val delay = minOf(1_000L shl reconnectAttempt.coerceAtMost(5), 30_000L)
    reconnectAttempt += 1
    reconnectFuture = reconnectExecutor.schedule({
      reconnectFuture = null
      rejoin()
    }, delay, TimeUnit.MILLISECONDS)
  }

  private fun rejoin() {
    if (stopped) return
    ensureConnected { connectResult ->
      executor.execute {
        connectResult.onFailure { error ->
          emitError(error.message ?: "Scene 重连失败")
          scheduleReconnect()
        }.onSuccess {
          val current = active ?: return@execute
          if (current.catchUp != null) {
            runCatchUp(current.catchUp, { eventType, payload -> emitEvent(eventType, payload) }) {
              it.onFailure { error ->
                emitError(error.message ?: "Scene 重连失败")
                scheduleReconnect()
              }.onSuccess { sendEnter(15_000) { /* listener-driven */ } }
            }
          } else {
            sendEnter(15_000) { /* listener-driven */ }
          }
        }
      }
    }
  }

  private fun clearPendingEnter(message: String) {
    val pending = pendingEnter ?: return
    pendingEnter = null
    pending.timer.cancel(false)
    pending.callback(Result.failure(IllegalStateException(message)))
  }

  private fun emitEvent(eventType: String, payload: JSONObject) {
    val envelope = readEnvelope(payload)
    listeners.forEach { it.onEvent(eventType, payload, envelope) }
  }

  private fun notifyConnection(connected: Boolean) {
    listeners.forEach { it.onConnectionChanged(connected) }
  }

  private fun emitError(message: String) {
    listeners.forEach { it.onError(message) }
  }

  private fun runCatchUp(
    source: PteIMSceneCatchUpSource,
    apply: (String, JSONObject) -> Unit,
    callback: (Result<Unit>) -> Unit,
  ) {
    source.getCurrentRoomSeq { currentResult ->
      executor.execute {
        currentResult.onFailure { callback(Result.failure(it)) }.onSuccess { current ->
          tracker.seedIfFresh(current)
          fetchCatchUpPage(source, tracker.getLastRoomSeq(), apply, 0, callback)
        }
      }
    }
  }

  private fun fetchCatchUpPage(
    source: PteIMSceneCatchUpSource,
    after: Long,
    apply: (String, JSONObject) -> Unit,
    page: Int,
    callback: (Result<Unit>) -> Unit,
  ) {
    if (page >= 20) {
      callback(Result.success(Unit))
      return
    }
    source.fetchEventsAfter(after, 100) { pageResult ->
      executor.execute {
        pageResult.onFailure { callback(Result.failure(it)) }.onSuccess { fetched ->
          var cursor = after
          for (row in fetched.events) {
            val payload = parseLivePayload(row.payload) ?: JSONObject()
            if (!payload.has("eventId")) payload.put("eventId", row.eventId)
            if (!payload.has("roomSeq")) payload.put("roomSeq", row.roomSeq)
            if (tracker.accept(payload)) apply(row.eventType, payload)
            if (row.roomSeq > cursor) cursor = row.roomSeq
          }
          if (fetched.events.size < 100) {
            if (fetched.currentRoomSeq > tracker.getLastRoomSeq()) tracker.setLastRoomSeq(fetched.currentRoomSeq)
            callback(Result.success(Unit))
          } else {
            fetchCatchUpPage(source, cursor, apply, page + 1, callback)
          }
        }
      }
    }
  }
}

/** Tracks roomSeq watermark and eventId dedupe for scene WSS / catch-up. */
class RoomSeqTracker(initialLastRoomSeq: Long = 0) {
  private var lastRoomSeq: Long = initialLastRoomSeq
  private val seen = linkedSetOf<String>()

  fun getLastRoomSeq(): Long = lastRoomSeq

  internal fun setLastRoomSeq(value: Long) { lastRoomSeq = value }

  internal fun seedIfFresh(currentRoomSeq: Long) {
    if (lastRoomSeq <= 0 && currentRoomSeq > 0) lastRoomSeq = currentRoomSeq
  }

  /** Returns false if duplicate or stale. */
  fun accept(payload: JSONObject): Boolean {
    val envelope = readEnvelope(payload)
    envelope.eventId?.let { id ->
      if (seen.contains(id)) return false
    }
    envelope.roomSeq?.let { seq ->
      if (seq > 0 && seq <= lastRoomSeq) {
        envelope.eventId?.let { seen += it }
        return false
      }
    }
    envelope.eventId?.let { id ->
      seen += id
      if (seen.size > 2000) seen.take(500).forEach(seen::remove)
    }
    envelope.roomSeq?.let { seq -> if (seq > lastRoomSeq) lastRoomSeq = seq }
    return true
  }

  fun needsCatchUp(payload: JSONObject): Boolean {
    val seq = readEnvelope(payload).roomSeq ?: return false
    return seq > lastRoomSeq + 1
  }
}

internal fun assertSceneRoomId(scene: PteIMSceneKind, roomId: String) {
  val id = roomId.trim()
  require(id.isNotEmpty()) { "roomId 不能为空" }
  if (scene == PteIMSceneKind.SPORTS && !Regex("^sports-live-\\d+$").matches(id)) {
    throw IllegalArgumentException("体育房间 roomId 必须为 sports-live-{数字id}")
  }
}

internal fun groupNameForScene(scene: PteIMSceneKind, roomId: String): String = when (scene) {
  PteIMSceneKind.SHOP -> "live:$roomId"
  PteIMSceneKind.SPORTS -> "sports:$roomId"
  else -> "${sceneWire(scene)}:$roomId"
}

internal fun sceneWire(scene: PteIMSceneKind): String = when (scene) {
  PteIMSceneKind.SHOW -> "show"
  PteIMSceneKind.VOICE -> "voice"
  PteIMSceneKind.SHOP -> "shop"
  PteIMSceneKind.SPORTS -> "sports"
}

private fun sceneKindOf(value: String): PteIMSceneKind = when (value.lowercase()) {
  "voice" -> PteIMSceneKind.VOICE
  "shop" -> PteIMSceneKind.SHOP
  "sports" -> PteIMSceneKind.SPORTS
  else -> PteIMSceneKind.SHOW
}

internal fun readEnvelope(payload: JSONObject): PteIMLiveEventEnvelope {
  val eventId = payload.optNullableString("eventId") ?: payload.optNullableString("event_id")
  val roomSeq = payload.optNumber("roomSeq") ?: payload.optNumber("room_seq")
  val serverTs = payload.optNumber("serverTs") ?: payload.optNumber("server_ts")
  val priority = payload.optNullableString("priority")
  return PteIMLiveEventEnvelope(eventId, roomSeq, serverTs, priority)
}

internal fun parseLivePayload(raw: Any?): JSONObject? = when (raw) {
  is String -> raw.trim().takeIf { it.isNotEmpty() }?.let { runCatching { JSONObject(it) }.getOrNull() }
  is JSONObject -> raw
  else -> null
}

internal fun eventTypeFromFrame(frame: JSONObject): Pair<String?, JSONObject?> {
  var envelope: Any? = frame.opt("data")
  if (envelope is String) envelope = runCatching { JSONObject(envelope) }.getOrNull()
  val root = envelope as? JSONObject ?: return null to null
  val scene = root.optJSONObject("scene")
  val payload = parseLivePayload(scene?.opt("payload")) ?: flattenPayload(root)
  val eventType = root.optNullableString("event_type")
    ?: root.optNullableString("eventType")
    ?: frame.optNullableString("msg")
  return eventType to payload
}

private fun flattenPayload(root: JSONObject): JSONObject? =
  if (root.has("eventId") || root.has("event_id") || root.has("roomSeq") || root.has("room_seq")) root else null

private fun JSONObject.optNumber(name: String): Long? {
  if (!has(name) || isNull(name)) return null
  return when (val value = opt(name)) {
    is Number -> value.toLong()
    is String -> value.trim().takeIf { it.isNotEmpty() }?.toLongOrNull()
    else -> null
  }
}

private fun stringOf(value: Any?): String = value?.toString()?.trim().orEmpty()

private fun JSONObject.optNullableString(name: String): String? =
  if (has(name) && !isNull(name)) optString(name).takeIf { it.isNotEmpty() } else null

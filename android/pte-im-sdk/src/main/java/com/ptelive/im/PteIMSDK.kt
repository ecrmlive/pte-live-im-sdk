package com.ptelive.im

import android.content.Context
import android.net.Uri
import android.provider.OpenableColumns
import org.json.JSONArray
import org.json.JSONObject
import java.net.HttpURLConnection
import java.net.URLEncoder
import java.net.URL
import java.util.UUID
import java.util.concurrent.Executors
import java.util.concurrent.ScheduledExecutorService
import java.util.concurrent.ScheduledFuture
import java.util.concurrent.TimeUnit

interface PteIMListener {
  fun onConnectionChanged(connected: Boolean) {}
  /** Server-authoritative conversation cursor sync has updated the local cache. */
  fun onConversationsChanged() {}
  fun onMessage(message: PteIMMessage) {}
  /** A recalled message, per-user deletion, or durable reaction changed locally. */
  fun onMessageUpdated(message: PteIMMessage) {}
  fun onMessageStateChanged(clientMsgId: String, state: PteIMSendState) {}
  fun onUserSigRefreshFailed(error: Throwable) {}
  fun onThemeModeChanged(themeMode: PteIMThemeMode) {}
  fun onLanguageChanged(language: PteIMLanguage) {}
  fun onError(error: Throwable) {}
  fun onStateChanges(changes: List<PteIMStateChange>) {}
}

/** Public native Android SDK entry point. */
class PteIMSDK private constructor(private val appContext: Context, initialConfig: PteIMSessionConfig) : WssListener {
  private val executor = Executors.newSingleThreadExecutor()
  private val reconnectExecutor: ScheduledExecutorService = Executors.newSingleThreadScheduledExecutor()
  private var config = initialConfig
  private var store = PteIMRoomStore(appContext, initialConfig.storeKey())
  private val e2ee = PteIME2EE(appContext, initialConfig.storeKey(), initialConfig.sdkAppId, initialConfig.userId.toLong())
  private var transport: WssTransport? = null
  @Volatile private var stopRequested = false
  private var reconnectAttempt = 0
  @Volatile private var socketConnected = false
  private var outboxRetryFuture: ScheduledFuture<*>? = null
  private var userSigRefreshFuture: ScheduledFuture<*>? = null
  @Volatile private var userSigRefreshInFlight = false
  private val listeners = linkedSetOf<PteIMListener>()
  @Volatile private var appearance = PteIMAppearance(initialConfig.base.themeMode, initialConfig.base.language)
  /** Optional Commerce extension. It shares the current UserSig and does not open another socket. */
  val commerce: PteIMCommerce by lazy { PteIMCommerce(this) }

  companion object {
    fun configure(context: Context, baseConfig: PteIMBaseConfig): PteIMSDKBootstrap = PteIMSDKBootstrap(context.applicationContext, baseConfig)
    internal fun create(context: Context, config: PteIMSessionConfig): PteIMSDK {
      config.validate()
      return PteIMSDK(context.applicationContext, config)
    }
  }

  fun addListener(listener: PteIMListener) { listeners += listener }
  fun removeListener(listener: PteIMListener) { listeners -= listener }

  fun start() {
    config.validate()
    stopRequested = false
    transport?.close()
    scheduleUserSigRefresh()
    executor.execute {
      try { e2ee.register(::postSdkData); connect() }
      catch (error: Throwable) { listeners.forEach { it.onError(error) } }
    }
  }

  fun stop() { stopRequested = true; socketConnected = false; outboxRetryFuture?.cancel(false); userSigRefreshFuture?.cancel(false); userSigRefreshFuture = null; transport?.close(); transport = null }

  /** Applies a provider result. Credentials are never supplied by UI callers. */
  private fun applyRefreshedUserSig(userSig: String, expireAt: Long) {
    require(userSig.isNotBlank()) { "userSig is required" }
    config = config.copy(login = config.login.copy(userSig = userSig, userSigExpireAt = if (expireAt > 0) expireAt else config.login.userSigExpireAt))
    scheduleUserSigRefresh()
    sendEnvelope("renew_user_sig", JSONObject().put("userSig", userSig))
  }

  /** Uses the host bridge to renew UserSig before expiry or after an auth failure. */
  fun refreshUserSig(force: Boolean = false): Boolean {
    val provider = config.login.userSigProvider ?: return false
    if (stopRequested) return false
    val now = System.currentTimeMillis() / 1000
    if (!force && config.login.userSigExpireAt > now + 300) { scheduleUserSigRefresh(); return true }
    if (userSigRefreshInFlight) return false
    userSigRefreshInFlight = true
    provider.refreshUserSig { result ->
      result.onSuccess { renewed ->
        if (renewed.userSig.isBlank() || renewed.expireAt <= System.currentTimeMillis() / 1000) {
          listeners.forEach { it.onUserSigRefreshFailed(IllegalArgumentException("invalid UserSig refresh response")) }
        } else {
          applyRefreshedUserSig(renewed.userSig, renewed.expireAt)
          syncNow(); syncConversationsNow()
        }
      }.onFailure { error -> listeners.forEach { it.onUserSigRefreshFailed(error) } }
      userSigRefreshInFlight = false
    }
    return true
  }

  /** Updates host-UI preferences without reconnecting or changing the logged-in session. */
  fun updateAppearance(themeMode: PteIMThemeMode? = null, language: PteIMLanguage? = null): PteIMAppearance {
    val previous = appearance
    val updated = PteIMAppearance(themeMode ?: previous.themeMode, language ?: previous.language)
    appearance = updated
    if (updated.themeMode != previous.themeMode) listeners.forEach { it.onThemeModeChanged(updated.themeMode) }
    if (updated.language != previous.language) listeners.forEach { it.onLanguageChanged(updated.language) }
    return updated
  }

  fun currentAppearance(): PteIMAppearance = appearance
  fun currentUserId(): String = config.userId

  fun fetchMyProfile(callback: (Result<PteIMUserProfile>) -> Unit) {
    executor.execute { callback(runCatching { profileFromJson(postSdkJson("/v1/im/profile/me", JSONObject())) }) }
  }

  /** Sends one field only; the UserSig determines the profile owner. */
  fun updateMyProfile(update: PteIMUserProfileUpdate, callback: (Result<PteIMUserProfile>) -> Unit) {
    executor.execute { callback(runCatching { profileFromJson(postSdkJson("/v1/im/profile/update", JSONObject().put("field", update.field).put("value", update.value))) }) }
  }

  fun fetchFriends(cursor: String = "", limit: Int = 50, callback: (Result<PteIMContactPage>) -> Unit) = contactPage("/v1/im/friends", cursor, limit, callback)
  fun fetchFollows(cursor: String = "", limit: Int = 50, callback: (Result<PteIMContactPage>) -> Unit) = contactPage("/v1/im/follows", cursor, limit, callback)
  fun follow(userId: Long, remark: String? = null, callback: (Result<Unit>) -> Unit) = contactAction("/v1/im/follows/follow", userId, remark, callback)
  fun unfollow(userId: Long, callback: (Result<Unit>) -> Unit) = contactAction("/v1/im/follows/unfollow", userId, null, callback)
  fun block(userId: Long, callback: (Result<Unit>) -> Unit) = contactAction("/v1/im/blocks/add", userId, null, callback)
  fun unblock(userId: Long, callback: (Result<Unit>) -> Unit) = contactAction("/v1/im/blocks/remove", userId, null, callback)
  fun fetchGroups(cursor: String = "", limit: Int = 50, callback: (Result<PteIMGroupPage>) -> Unit) { executor.execute { callback(runCatching { val root = postSdkJson("/v1/im/groups", JSONObject().put("cursor", cursor).put("limit", limit)); val list = root.optJSONArray("list") ?: JSONArray(); PteIMGroupPage((0 until list.length()).map { remoteConversationFromJson(list.getJSONObject(it)) }, root.optString("nextCursor"), root.optBoolean("hasMore")) }) } }
  fun fetchGroupMembers(conversationId: Long, cursor: String = "", limit: Int = 50, callback: (Result<PteIMMemberPage>) -> Unit) { executor.execute { callback(runCatching { val root = postSdkJson("/v1/im/groups/members", JSONObject().put("conversationId", conversationId).put("cursor", cursor).put("limit", limit)); val list = root.optJSONArray("list") ?: JSONArray(); PteIMMemberPage((0 until list.length()).map { i -> list.getJSONObject(i).let { PteIMMember(it.getLong("user_id"), it.optInt("role"), it.optString("alias"), it.optLong("mute_until"), it.optLong("joined_at")) } }, root.optString("nextCursor"), root.optBoolean("hasMore")) }) } }
  fun joinGroup(conversationId: Long, callback: (Result<Unit>) -> Unit) { executor.execute { callback(runCatching { postSdkJson("/v1/im/groups/join", JSONObject().put("conversationId", conversationId)); Unit }) } }
  fun inviteGroupMembers(conversationId: Long, memberIds: List<Long>, callback: (Result<Unit>) -> Unit) { require(conversationId > 0 && memberIds.isNotEmpty() && memberIds.all { it > 0 }); executor.execute { callback(runCatching { postSdkJson("/v1/im/groups/members/invite", JSONObject().put("conversationId", conversationId).put("memberIds", JSONArray(memberIds))); Unit }) } }
  fun removeGroupMember(conversationId: Long, memberId: Long, callback: (Result<Unit>) -> Unit) { require(conversationId > 0 && memberId > 0); executor.execute { callback(runCatching { postSdkJson("/v1/im/groups/members/remove", JSONObject().put("conversationId", conversationId).put("memberId", memberId)); Unit }) } }
  fun leaveGroup(conversationId: Long, callback: (Result<Unit>) -> Unit) { require(conversationId > 0); executor.execute { callback(runCatching { postSdkJson("/v1/im/groups/leave", JSONObject().put("conversationId", conversationId)); Unit }) } }
  /** Registers a U-Push/APNs/runtime token; the SDK does not persist this token locally. */
  fun registerPushDevice(deviceId: String, platform: PteIMPushPlatform, token: String, notificationEnabled: Boolean = true, callback: (Result<PteIMPushDevice>) -> Unit) {
    require(deviceId.length >= 8 && token.length >= 16) { "invalid push device" }
    executor.execute { callback(runCatching { pushDeviceFromJson(postSdkJson("/v1/im/push/devices/register", JSONObject().put("deviceId", deviceId).put("platform", platform.name.lowercase()).put("token", token).put("notificationEnabled", notificationEnabled))) }) }
  }
  fun setPushDeviceNotification(deviceId: String, platform: PteIMPushPlatform, enabled: Boolean, callback: (Result<PteIMPushDevice>) -> Unit) {
    require(deviceId.length >= 8) { "invalid push device" }
    executor.execute { callback(runCatching { pushDeviceFromJson(postSdkJson("/v1/im/push/devices/notification", JSONObject().put("deviceId", deviceId).put("platform", platform.name.lowercase()).put("notificationEnabled", enabled))) }) }
  }
  fun unregisterPushDevice(deviceId: String, platform: PteIMPushPlatform, callback: (Result<Unit>) -> Unit) {
    require(deviceId.length >= 8) { "invalid push device" }
    executor.execute { callback(runCatching { postSdkJson("/v1/im/push/devices/unregister", JSONObject().put("deviceId", deviceId).put("platform", platform.name.lowercase())); Unit }) }
  }
  fun syncState(cursor: String = "", limit: Int = 100, callback: (Result<PteIMStateChangePage>) -> Unit) { executor.execute { callback(runCatching { val root = postSdkJson("/v1/im/state/sync", JSONObject().put("cursor", cursor).put("limit", limit)); val list = root.optJSONArray("changes") ?: JSONArray(); PteIMStateChangePage((0 until list.length()).map { i -> list.getJSONObject(i).let { PteIMStateChange(it.getString("id"), it.getString("entityType"), it.getString("entityId"), it.getString("operation"), it.optLong("createdAt")) } }, root.optString("nextCursor"), root.optBoolean("hasMore")) }) } }
  fun fetchDefaultSetting(callback: (Result<PteIMDefaultSetting>) -> Unit) { executor.execute { callback(runCatching { postSdkJson("/v1/im/settings/default", JSONObject()).let { PteIMDefaultSetting(it.optString("chatPrerequisite"), it.optBoolean("notificationEnabled"), it.optString("groupJoinMode")) } }) } }

  fun sendText(conversationId: String, text: String, quote: PteIMQuote? = null): PteIMMessage = send(
    PteIMMessage(conversationId = conversationId, type = PteIMMessageType.TEXT, text = text, quote = quote),
  )

  fun sendEmoji(conversationId: String, packageId: String, emojiId: String): PteIMMessage = send(
    PteIMMessage(conversationId, PteIMMessageType.EMOJI, packageId = packageId, emojiId = emojiId),
  )

  /** Sends a media descriptor obtained by the host application. */
  fun sendImage(conversationId: String, media: PteIMMedia): PteIMMessage = send(
    PteIMMessage(conversationId, PteIMMessageType.IMAGE, media = media),
  )

  /** Sends a media descriptor obtained by the host application. */
  fun sendVideo(conversationId: String, media: PteIMMedia): PteIMMessage = send(
    PteIMMessage(conversationId, PteIMMessageType.VIDEO, media = media),
  )

  /** Sends a file descriptor. Persist a COS key in [PteIMMedia.url], never a short-lived PUT URL. */
  fun sendFile(conversationId: String, media: PteIMMedia): PteIMMessage = send(
    PteIMMessage(conversationId, PteIMMessageType.FILE, media = media),
  )

  fun sendVoice(conversationId: String, voice: PteIMVoice): PteIMMessage = send(
    PteIMMessage(conversationId, PteIMMessageType.VOICE, voice = voice),
  )

  fun sendLocation(conversationId: String, location: PteIMLocation): PteIMMessage = send(
    PteIMMessage(conversationId, PteIMMessageType.LOCATION, location = location),
  )

  fun sendGift(conversationId: String, content: PteIMBusinessContent): PteIMMessage = send(
    PteIMMessage(conversationId, PteIMMessageType.GIFT, business = content),
  )

  fun sendRedPacket(conversationId: String, content: PteIMBusinessContent): PteIMMessage = send(
    PteIMMessage(conversationId, PteIMMessageType.RED_PACKET, business = content),
  )

  fun sendOrder(conversationId: String, content: PteIMBusinessContent): PteIMMessage = send(
    PteIMMessage(conversationId, PteIMMessageType.ORDER, business = content),
  )

  /**
   * Requeues a terminally failed outgoing message with its original
   * `clientMsgId`, preserving server-side idempotency for text and rich cards.
   * Upload failures require the original local URI and are retried by UIKit.
   */
  fun retryMessage(message: PteIMMessage): PteIMMessage? {
    if (message.senderId != config.userId || message.state != PteIMSendState.FAILED) return null
    val retried = store.retry(message.clientMsgId)?.let(::storedMessageToModel) ?: return null
    listeners.forEach { it.onMessageStateChanged(retried.clientMsgId, PteIMSendState.PENDING) }
    flushOutbox()
    return retried
  }

  /** Deletes only this account's local cached message; it never deletes remote history. */
  fun deleteLocalMessage(message: PteIMMessage) {
    store.deleteLocal(message.clientMsgId)
    listeners.forEach { it.onMessageStateChanged(message.clientMsgId, message.state) }
  }

  /** Globally recalls the caller's own message through the IM protocol. */
  fun recallMessage(message: PteIMMessage, callback: (Result<PteIMMessage>) -> Unit) {
    val messageId = message.serverMsgId ?: return callback(Result.failure(IllegalArgumentException("message must be sent before recall")))
    executor.execute { callback(runCatching { decodeMessage(postSdkJson("/v1/im/messages/recall", JSONObject().put("messageId", messageId))) }) }
  }

  /** Hides a message only from the current account, after durable IM confirmation. */
  fun deleteMessage(message: PteIMMessage, callback: (Result<Unit>) -> Unit) {
    val messageId = message.serverMsgId ?: return callback(Result.failure(IllegalArgumentException("message must be sent before delete")))
    executor.execute {
      callback(runCatching {
        postSdkJson("/v1/im/messages/delete", JSONObject().put("messageId", messageId))
        store.deleteLocal(message.clientMsgId)
        Unit
      })
    }
  }

  fun addMessageReaction(message: PteIMMessage, emoji: String, callback: (Result<PteIMMessageReactionResult>) -> Unit) = changeMessageReaction(message, emoji, true, callback)
  fun removeMessageReaction(message: PteIMMessage, emoji: String, callback: (Result<PteIMMessageReactionResult>) -> Unit) = changeMessageReaction(message, emoji, false, callback)

  private fun changeMessageReaction(message: PteIMMessage, emoji: String, add: Boolean, callback: (Result<PteIMMessageReactionResult>) -> Unit) {
    val messageId = message.serverMsgId ?: return callback(Result.failure(IllegalArgumentException("message must be sent before reacting")))
    executor.execute { callback(runCatching { reactionResultFromJson(postSdkJson(if (add) "/v1/im/messages/reactions/add" else "/v1/im/messages/reactions/remove", JSONObject().put("messageId", messageId).put("emoji", emoji))) }) }
  }

  /** Uploads through apiDomain and then sends an image message with the same client message ID. */
  fun uploadAndSendImage(conversationId: String, uri: Uri, onProgress: (Long, Long?) -> Unit = { _, _ -> }): PteIMMessage =
    uploadAndSendMedia(conversationId, uri, PteIMMessageType.IMAGE, onProgress)

  /** Uploads through apiDomain and then sends a video message with the same client message ID. */
  fun uploadAndSendVideo(conversationId: String, uri: Uri, onProgress: (Long, Long?) -> Unit = { _, _ -> }): PteIMMessage =
    uploadAndSendMedia(conversationId, uri, PteIMMessageType.VIDEO, onProgress)

  /** Uploads an allowed document/archive through the one-object COS PUT URL, then sends its key. */
  fun uploadAndSendFile(conversationId: String, uri: Uri, onProgress: (Long, Long?) -> Unit = { _, _ -> }): PteIMMessage =
    uploadAndSendMedia(conversationId, uri, PteIMMessageType.FILE, onProgress)

  /** Uploads voice bytes to COS. The caller provides recording duration and optional waveform metadata. */
  fun uploadAndSendVoice(conversationId: String, uri: Uri, durationMs: Long, waveform: String? = null, onProgress: (Long, Long?) -> Unit = { _, _ -> }): PteIMMessage {
    require(durationMs > 0) { "durationMs must be positive" }
    return uploadAndSendMedia(conversationId, uri, PteIMMessageType.VOICE, onProgress, durationMs, waveform)
  }

  fun syncNow(): Unit {
    executor.execute {
      try {
        val response = postSdkJson("/v1/im/sync", JSONObject().apply {
          put("syncCursor", store.cursor())
          put("pageSize", 200)
        })
        val messages = response.optJSONArray("messages") ?: JSONArray()
        val decoded = (0 until messages.length()).map { decodeMessage(messages.getJSONObject(it)) }
        store.applyDelta(response.getString("nextCursor"), decoded)
        decoded.forEach { message -> listeners.forEach { it.onMessage(message) } }
        if (response.optBoolean("hasMore")) syncNow()
      } catch (error: Throwable) { listeners.forEach { it.onError(error) } }
    }
  }
  fun syncStateNow(): Unit { executor.execute { try { val root = postSdkJson("/v1/im/state/sync", JSONObject().put("cursor", store.stateCursor()).put("limit", 100)); val list = root.optJSONArray("changes") ?: JSONArray(); val page = PteIMStateChangePage((0 until list.length()).map { i -> list.getJSONObject(i).let { PteIMStateChange(it.getString("id"), it.getString("entityType"), it.getString("entityId"), it.getString("operation"), it.optLong("createdAt")) } }, root.optString("nextCursor"), root.optBoolean("hasMore")); store.setStateCursor(page.nextCursor); listeners.forEach { it.onStateChanges(page.changes) }; if (page.hasMore) syncStateNow() } catch (error: Throwable) { listeners.forEach { it.onError(error) } } } }

  /** Cursor-based, server-authoritative conversation sync. Pages are merged into the encrypted Room cache. */
  fun syncConversationsNow(): Unit {
    executor.execute {
      try {
        val root = postSdkJson("/v1/im/conversations/cursor", JSONObject().put("cursor", store.conversationCursor()).put("limit", 100))
        val list = root.optJSONArray("list") ?: JSONArray()
        val values = (0 until list.length()).map { remoteConversationFromJson(list.getJSONObject(it)) }
        store.applyRemoteConversations(values, root.optString("nextCursor"))
        listeners.forEach { it.onConversationsChanged() }
        if (root.optBoolean("hasMore")) syncConversationsNow()
      } catch (error: Throwable) { listeners.forEach { it.onError(error) } }
    }
  }

  /** Reads the account-isolated Room cache. Call [syncNow] first when fresh server state is required. */
  fun localMessages(conversationId: String, beforeCreatedAt: Long? = null, limit: Int = 50): List<PteIMMessage> =
    store.localMessages(conversationId, beforeCreatedAt, limit).map(::storedMessageToModel)

  /** Returns conversations ordered by their newest locally stored message. */
  fun localConversations(limit: Int = 100): List<PteIMConversation> = store.localConversations(limit).map { entry ->
    PteIMConversation(entry.conversationId, storedMessageToModel(entry.lastMessage), entry.updatedAt)
  }

  /** Returns encrypted-cache conversation metadata after [syncConversationsNow] has run. */
  fun localRemoteConversations(limit: Int = 100): List<PteIMRemoteConversation> =
    store.localRemoteConversations(limit).map { remoteConversationFromJson(JSONObject(it.payload)) }

  /** Loads a server-authoritative conversation page using the current UserSig session. */
  fun fetchConversationPage(page: Int = 1, pageSize: Int = 50, callback: (Result<PteIMConversationPage>) -> Unit) {
    require(page > 0) { "page must be positive" }; require(pageSize in 1..200) { "pageSize must be in 1..200" }
    executor.execute {
      callback(runCatching {
        val data = postSdkJson("/v1/im/conversations", JSONObject().put("page", page).put("pageSize", pageSize))
        val items = data.optJSONArray("list") ?: JSONArray()
        PteIMConversationPage(data.optLong("total"), (0 until items.length()).map { remoteConversationFromJson(items.getJSONObject(it)) })
      })
    }
  }

  /** Opens (or idempotently creates) a C2C conversation for the logged-in user. */
  fun openSingleConversation(peerUserId: Long, callback: (Result<PteIMRemoteConversation>) -> Unit) {
    require(peerUserId > 0) { "peerUserId must be positive" }
    executor.execute { callback(runCatching { remoteConversationFromJson(postSdkJson("/v1/im/conversations/open-single", JSONObject().put("peerUserId", peerUserId))) }) }
  }

  /** Creates a group whose owner is always the logged-in UserSig identity. */
  fun createGroupConversation(title: String, memberIds: List<Long> = emptyList(), avatar: String? = null, callback: (Result<PteIMRemoteConversation>) -> Unit) {
    require(title.isNotBlank()) { "title is required" }; require(memberIds.all { it > 0 }) { "memberIds must be positive" }
    executor.execute { callback(runCatching {
      val members = JSONArray(); memberIds.forEach { members.put(it) }
      remoteConversationFromJson(postSdkJson("/v1/im/conversations/create-group", JSONObject().put("title", title).put("memberIds", members).apply { avatar?.let { put("avatar", it) } }))
    }) }
  }

  /** Advances this user's read sequence; pass 0 to read through the latest message. */
  fun markConversationRead(conversationId: Long, seq: Long = 0, callback: (Result<Unit>) -> Unit) {
    require(conversationId > 0 && seq >= 0) { "invalid read cursor" }
    executor.execute { callback(runCatching { postSdkJson("/v1/im/conversations/read", JSONObject().put("conversationId", conversationId).put("seq", seq)); Unit }) }
  }

  /** Loads a server-authoritative message-history page using the current UserSig session. */
  fun fetchMessageHistory(conversationId: Long, beforeSeq: Long = 0, limit: Int = 50, callback: (Result<PteIMMessagePage>) -> Unit) {
    require(conversationId > 0) { "conversationId must be positive" }; require(beforeSeq >= 0) { "beforeSeq must not be negative" }; require(limit in 1..200) { "limit must be in 1..200" }
    executor.execute {
      callback(runCatching {
        val data = postSdkJson("/v1/im/conversations/messages", JSONObject().put("conversationId", conversationId).put("beforeSeq", beforeSeq).put("limit", limit))
        val items = data.optJSONArray("list") ?: JSONArray()
        PteIMMessagePage((0 until items.length()).map { remoteMessageFromJson(items.getJSONObject(it)) })
      })
    }
  }

  private fun send(message: PteIMMessage): PteIMMessage {
    require(message.conversationId.toLongOrNull()?.let { it > 0 } == true) {
      "conversationId must be a positive numeric string returned by openSingleConversation or createGroupConversation"
    }
    val outgoing = message.copy(senderId = config.userId)
    store.enqueue(outgoing)
    listeners.forEach { it.onMessageStateChanged(outgoing.clientMsgId, PteIMSendState.PENDING) }
    flushOutbox()
    return outgoing
  }

  private fun uploadAndSendMedia(conversationId: String, uri: Uri, type: PteIMMessageType, onProgress: (Long, Long?) -> Unit, voiceDurationMs: Long? = null, waveform: String? = null): PteIMMessage {
    require(conversationId.toLongOrNull()?.let { it > 0 } == true) {
      "conversationId must be a positive numeric string returned by openSingleConversation or createGroupConversation"
    }
    val message = PteIMMessage(conversationId, type, senderId = config.userId, state = PteIMSendState.UPLOADING)
    store.enqueue(message)
    listeners.forEach { it.onMessageStateChanged(message.clientMsgId, PteIMSendState.UPLOADING) }
    executor.execute {
      try {
        val uploaded = uploadMedia(uri, type, onProgress)
        val ready = if (type == PteIMMessageType.VOICE) message.copy(
          voice = PteIMVoice(uploaded.url ?: error("COS upload returned no object key"), voiceDurationMs ?: error("voice duration is required"), waveform, uploaded.sizeBytes),
          state = PteIMSendState.PENDING,
        ) else message.copy(media = uploaded, state = PteIMSendState.PENDING)
        store.replaceQueued(ready)
        listeners.forEach { it.onMessageStateChanged(ready.clientMsgId, PteIMSendState.PENDING) }
        flushOutbox()
      } catch (error: Throwable) {
        store.markFailed(message.clientMsgId)
        listeners.forEach { it.onMessageStateChanged(message.clientMsgId, PteIMSendState.FAILED); it.onError(error) }
      }
    }
    return message
  }

  private fun sendQueued(message: PteIMMessage) = sendEnvelope("send_message", JSONObject().apply {
    put("clientMsgId", message.clientMsgId)
    put("conversationId", message.conversationId)
    put("type", message.type.name.lowercase())
    put("e2ee", e2ee.encrypt(message, ::postSdkData))
	message.quote?.serverMsgId?.takeIf { it.isNotBlank() }?.let { put("quoteMessageId", it) }
  })

  override fun onOpen() {
    reconnectAttempt = 0
    socketConnected = true
    listeners.forEach { it.onConnectionChanged(true) }
    sendEnvelope("login", JSONObject().put("syncCursor", store.cursor()))
    flushOutbox()
    syncNow(); syncStateNow(); syncConversationsNow()
  }

  override fun onText(text: String) {
    try {
      val envelope = JSONObject(text)
      when (envelope.getString("action")) {
        "message" -> decodeMessage(envelope.getJSONObject("payload")).also { message ->
          store.applyDelta(envelope.optString("syncCursor", store.cursor()), listOf(message))
          listeners.forEach { it.onMessage(message) }
          sendEnvelope("ack", JSONObject().put("serverMsgId", message.serverMsgId))
        }
        "ack" -> envelope.getJSONObject("payload").let { ack ->
          store.markSent(ack.getString("clientMsgId"), ack.optNullableString("serverMsgId"), ack.optLong("serverSeq"))
          listeners.forEach { it.onMessageStateChanged(ack.getString("clientMsgId"), PteIMSendState.SENT) }
        }
        "message_event" -> handleMessageEvent(envelope.getJSONObject("payload"))
        "user_sig_will_expire", "user_sig_expired" -> refreshUserSig(force = true)
        "sync_required" -> syncNow()
        else -> Unit
      }
    } catch (error: Throwable) { listeners.forEach { it.onError(error) } }
  }

  override fun onClosed() {
    socketConnected = false
    listeners.forEach { it.onConnectionChanged(false) }
    if (!stopRequested) scheduleReconnect()
  }
  override fun onFailure(error: Throwable) {
    socketConnected = false
    listeners.forEach { it.onError(error) }
    if (!stopRequested) scheduleReconnect()
  }

  private fun sendEnvelope(action: String, payload: JSONObject) {
    val envelope = JSONObject().apply {
      put("protocolVersion", 1)
      put("action", action)
      put("requestId", UUID.randomUUID().toString())
      put("sdkAppId", config.sdkAppId)
      put("userId", config.userId)
      put("userSig", config.userSig)
      put("payload", payload)
    }
    runCatching { transport?.sendText(envelope.toString()) }.onFailure { error -> listeners.forEach { it.onError(error) } }
  }

  private fun handleMessageEvent(payload: JSONObject) {
    val serverMsgId = payload.optNullableString("serverMsgId") ?: return
    val eventType = payload.optString("eventType")
    val updated = store.applyMessageEvent(serverMsgId, eventType, payload, config.userId) ?: return
    listeners.forEach { it.onMessageUpdated(updated) }
  }

  /** The configured IM service authenticates the WSS upgrade. Android's dependency-free transport cannot add
   * custom upgrade headers, so its short-lived UserSig is URL encoded in the documented WSS query. */
  private fun connect() { transport = WssTransport(webSocketUrl(), this).also { it.connect() } }

  private fun webSocketUrl(): String {
    val separator = if (config.imDomain.contains('?')) '&' else '?'
    fun encoded(value: String) = URLEncoder.encode(value, Charsets.UTF_8.name()).replace("+", "%20")
    return config.imDomain + separator + "sdkAppID=${encoded(config.login.sdkAppId.toString())}" +
      "&identifier=${encoded(config.login.userId)}&userSig=${encoded(config.login.userSig)}"
  }

  private fun scheduleReconnect() {
    val attempt = reconnectAttempt++.coerceAtMost(5)
    val delayMs = 1_000L shl attempt
    reconnectExecutor.schedule({ if (!stopRequested) connect() }, delayMs.coerceAtMost(30_000L), TimeUnit.MILLISECONDS)
  }

  private fun scheduleUserSigRefresh() {
    userSigRefreshFuture?.cancel(false)
    userSigRefreshFuture = null
    val expiry = config.login.userSigExpireAt
    if (stopRequested || config.login.userSigProvider == null || expiry <= 0) return
    val delaySeconds = (expiry - System.currentTimeMillis() / 1000 - 300).coerceAtLeast(1)
    userSigRefreshFuture = reconnectExecutor.schedule({ refreshUserSig(force = true) }, delaySeconds, TimeUnit.SECONDS)
  }

  private fun flushOutbox() {
    executor.execute {
      if (stopRequested || !socketConnected) return@execute
      try {
        val now = System.currentTimeMillis()
        store.dueOutbox(now).forEach { stored ->
          val message = storedMessageToModel(stored)
          store.recordOutboxAttempt(message.clientMsgId, now)
          sendQueued(message)
        }
        scheduleOutboxFlush()
      } catch (error: Throwable) { listeners.forEach { it.onError(error) } }
    }
  }

  private fun scheduleOutboxFlush() {
    outboxRetryFuture?.cancel(false)
    if (stopRequested || !socketConnected) return
    val nextRetryAt = store.nextOutboxRetryAt() ?: return
    val delay = (nextRetryAt - System.currentTimeMillis()).coerceIn(100L, 30_000L)
    outboxRetryFuture = reconnectExecutor.schedule({ flushOutbox() }, delay, TimeUnit.MILLISECONDS)
  }

  private fun resolveMedia(media: PteIMMedia): PteIMMedia = media.copy(
    url = resolveCosUrl(config.cosDomain, media.url),
    thumbnailUrl = resolveCosUrl(config.cosDomain, media.thumbnailUrl),
    coverUrl = resolveCosUrl(config.cosDomain, media.coverUrl),
  )

  private fun storedMessageToModel(value: StoredMessage): PteIMMessage = messageFromJson(JSONObject(value.payload), config.cosDomain).copy(
    serverMsgId = value.serverMsgId,
    serverSeq = value.serverSeq,
    createdAt = value.createdAt,
    state = runCatching { PteIMSendState.valueOf(value.state) }.getOrDefault(PteIMSendState.SENT),
  )

  private fun decodeMessage(json: JSONObject): PteIMMessage {
    val materialized = JSONObject(json.toString())
    if (materialized.has("e2ee") && !materialized.isNull("e2ee")) materialized.put("content", e2ee.decrypt(materialized.getJSONObject("e2ee")))
    return messageFromJson(materialized, config.cosDomain)
  }

  private fun postJson(path: String, payload: JSONObject): JSONObject {
    val connection = URL(config.apiDomain.trimEnd('/') + path).openConnection() as HttpURLConnection
    val responseKey = PteIMResponseCipher.createRequestKey()
    return try {
      connection.requestMethod = "POST"
      connection.setRequestProperty("Content-Type", "application/json")
      connection.setRequestProperty("Authorization", "Bearer ${config.userSig}")
      connection.setRequestProperty("X-Pte-Sdk-AppId", config.sdkAppId.toString())
      connection.setRequestProperty("X-Pte-User-Id", config.userId)
      connection.setRequestProperty("X-Pte-Response-Public-Key", PteIMResponseCipher.requestPublicKey(responseKey))
      connection.doOutput = true
      connection.outputStream.use { it.write(payload.toString().toByteArray(Charsets.UTF_8)) }
      val responseCode = connection.responseCode
      if (responseCode == HttpURLConnection.HTTP_UNAUTHORIZED) refreshUserSig(force = true)
      check(responseCode in 200..299) { "sync failed with HTTP $responseCode" }
      val encrypted = JSONObject(connection.inputStream.bufferedReader().use { it.readText() })
      JSONObject(PteIMResponseCipher.decrypt(encrypted, responseKey))
    } finally { connection.disconnect() }
  }

  private fun postSdkJson(path: String, payload: JSONObject): JSONObject = postSdkData(path, payload) as? JSONObject
    ?: error("IM API response data is not an object")

  private fun postSdkData(path: String, payload: JSONObject): Any {
    val root = postJson(path, payload)
    check(root.optInt("code", 1) == 1) { root.optString("msg", "IM API request failed") }
    return root.opt("data") ?: JSONObject()
  }

  internal fun executeCommerce(block: () -> Unit) { executor.execute(block) }

  internal fun postCommerceJson(path: String, payload: JSONObject): JSONObject {
    val domain = config.commerceDomain?.trimEnd('/') ?: error("commerceDomain is not configured")
    val connection = URL(domain + path).openConnection() as HttpURLConnection
    return try {
      connection.requestMethod = "POST"
      connection.setRequestProperty("Content-Type", "application/json")
      connection.setRequestProperty("Authorization", "Bearer ${config.userSig}")
      connection.setRequestProperty("X-Pte-Sdk-AppId", config.sdkAppId.toString())
      connection.setRequestProperty("X-Pte-User-Id", config.userId)
      connection.doOutput = true
      connection.outputStream.use { it.write(payload.toString().toByteArray(Charsets.UTF_8)) }
      check(connection.responseCode in 200..299) { "Commerce request failed with HTTP ${connection.responseCode}" }
      val root = JSONObject(connection.inputStream.bufferedReader().use { it.readText() })
      check(root.optInt("code", 0) == 1) { root.optString("msg", "Commerce request failed") }
      root.opt("data") as? JSONObject ?: JSONObject()
    } finally { connection.disconnect() }
  }

  private fun profileFromJson(value: JSONObject): PteIMUserProfile = PteIMUserProfile(
    userId = value.getLong("user_id"), nickname = value.optString("nickname").takeIf { it.isNotEmpty() },
    avatar = value.optString("avatar").takeIf { it.isNotEmpty() },
    gender = runCatching { PteIMGender.valueOf(value.optString("gender", "unknown").uppercase()) }.getOrDefault(PteIMGender.UNKNOWN),
    birthday = value.optString("birthday").takeIf { it.isNotEmpty() }, province = value.optString("province").takeIf { it.isNotEmpty() },
    city = value.optString("city").takeIf { it.isNotEmpty() }, district = value.optString("district").takeIf { it.isNotEmpty() },
  )

  private fun contactPage(path: String, cursor: String, limit: Int, callback: (Result<PteIMContactPage>) -> Unit) { executor.execute { callback(runCatching { val root = postSdkJson(path, JSONObject().put("cursor", cursor).put("limit", limit)); val list = root.optJSONArray("list") ?: JSONArray(); PteIMContactPage((0 until list.length()).map { i -> list.getJSONObject(i).let { PteIMContact(it.getString("userId"), it.optString("remark"), it.optString("nickname"), it.optString("avatar"), runCatching { PteIMGender.valueOf(it.optString("gender", "unknown").uppercase()) }.getOrDefault(PteIMGender.UNKNOWN), it.optLong("followedAt")) } }, root.optString("nextCursor"), root.optBoolean("hasMore")) }) } }
  private fun contactAction(path: String, userId: Long, remark: String?, callback: (Result<Unit>) -> Unit) { require(userId > 0); executor.execute { callback(runCatching { postSdkJson(path, JSONObject().put("targetUserId", userId).apply { remark?.let { put("remark", it) } }); Unit }) } }

  /** The media-credential contract uses a { code: 0, data } envelope. */
  private fun postMediaCredentialJson(path: String, payload: JSONObject): JSONObject {
    val connection = URL(config.apiDomain.trimEnd('/') + path).openConnection() as HttpURLConnection
    val root = try {
      connection.requestMethod = "POST"
      connection.setRequestProperty("Content-Type", "application/json")
      connection.setRequestProperty("Authorization", "Bearer ${config.userSig}")
      connection.setRequestProperty("X-Pte-Sdk-AppId", config.sdkAppId.toString())
      connection.setRequestProperty("X-Pte-User-Id", config.userId)
      connection.doOutput = true
      connection.outputStream.use { it.write(payload.toString().toByteArray(Charsets.UTF_8)) }
      check(connection.responseCode in 200..299) { "media credential request failed with HTTP ${connection.responseCode}" }
      JSONObject(connection.inputStream.bufferedReader().use { it.readText() })
    } finally { connection.disconnect() }
    check(root.optInt("code", -1) == 0) { root.optString("msg", "media credential request failed") }
    return root.optJSONObject("data") ?: error("media credential response has no data")
  }

  private fun uploadMedia(uri: Uri, type: PteIMMessageType, onProgress: (Long, Long?) -> Unit): PteIMMedia {
    val resolver = appContext.contentResolver
    val total = resolver.query(uri, arrayOf(OpenableColumns.SIZE), null, null, null)?.use { cursor ->
      cursor.takeIf { it.moveToFirst() }?.getLong(0)?.takeIf { it > 0 }
    } ?: error("Media size is required for COS upload")
    val mediaType = when (type) {
      PteIMMessageType.IMAGE -> "image"
      PteIMMessageType.VIDEO -> "video"
      PteIMMessageType.VOICE -> "voice"
      PteIMMessageType.FILE -> "file"
      else -> error("unsupported upload message type")
    }
    val contentType = resolver.getType(uri)?.takeUnless { it.endsWith("/*") } ?: when (type) {
      PteIMMessageType.IMAGE -> "image/jpeg"
      PteIMMessageType.VIDEO -> "video/mp4"
      PteIMMessageType.VOICE -> "audio/mpeg"
      PteIMMessageType.FILE -> contentTypeForFileName(appContext.displayName(uri) ?: "")
      else -> error("unsupported upload message type")
    }
    val credential = postMediaCredentialJson("/v1/im/media/put-url", JSONObject().apply {
      put("mediaType", mediaType); put("contentType", contentType); put("contentLength", total)
    })
    val key = credential.getString("key")
    val uploadURL = credential.getString("uploadUrl")
    val headers = credential.optJSONObject("headers") ?: JSONObject()
    val connection = URL(uploadURL).openConnection() as HttpURLConnection
    return try {
      connection.requestMethod = "PUT"
      for (name in headers.keys()) connection.setRequestProperty(name, headers.optString(name))
      connection.doOutput = true
      connection.setFixedLengthStreamingMode(total)
      connection.outputStream.buffered().use { output ->
        resolver.openInputStream(uri)?.use { input ->
          val buffer = ByteArray(8192); var sent = 0L
          while (true) {
            val count = input.read(buffer); if (count <= 0) break
            output.write(buffer, 0, count); sent += count; onProgress(sent, total)
          }
        } ?: error("Cannot read media URI")
      }
      check(connection.responseCode in 200..299) { "COS upload failed with HTTP ${connection.responseCode}" }
      PteIMMedia(url = key, sizeBytes = total, fileName = appContext.displayName(uri), mimeType = contentType)
    } finally { connection.disconnect() }
  }
}

class PteIMSDKBootstrap internal constructor(private val context: Context, private val baseConfig: PteIMBaseConfig) {
  fun login(loginConfig: PteIMLoginConfig): PteIMSDK {
    val session = PteIMSessionConfig(baseConfig, loginConfig)
    session.validate()
    return PteIMSDK.create(context, session).also { it.start() }
  }

  /**
   * Clears only the selected account's SDK cache and Keystore key. Stop a running client first,
   * then call [login] and [PteIMSDK.syncNow] to rebuild cache data from the service.
   */
  fun clearLocalCache(loginConfig: PteIMLoginConfig) {
    val session = PteIMSessionConfig(baseConfig, loginConfig)
    session.validate()
    PteIMRoomStore.clear(context, session.storeKey())
  }
}

internal fun messageFromJson(json: JSONObject, cosDomain: String): PteIMMessage {
  val content = json.optJSONObject("content") ?: JSONObject()
  val type = PteIMMessageType.valueOf(json.getString("type").uppercase())
  val media = if (type in setOf(PteIMMessageType.IMAGE, PteIMMessageType.VIDEO, PteIMMessageType.FILE)) PteIMMedia(
    url = resolveCosUrl(cosDomain, content.optNullableString("url")), thumbnailUrl = resolveCosUrl(cosDomain, content.optNullableString("thumbnailUrl")),
    coverUrl = resolveCosUrl(cosDomain, content.optNullableString("coverUrl")), width = content.optInt("width").takeIf { it > 0 },
    height = content.optInt("height").takeIf { it > 0 }, durationMs = content.optLong("durationMs").takeIf { it > 0 },
    sizeBytes = content.optLong("sizeBytes").takeIf { it > 0 }, fileName = content.optNullableString("fileName"), mimeType = content.optNullableString("mimeType"),
  ) else null
  val voice = if (type == PteIMMessageType.VOICE) content.optNullableString("url")?.let { url -> PteIMVoice(
    url = resolveCosUrl(cosDomain, url) ?: url,
    durationMs = content.optLong("durationMs"),
    waveform = content.optNullableString("waveform"),
    sizeBytes = content.optLong("sizeBytes").takeIf { it > 0 },
  ) } else null
  val location = if (type == PteIMMessageType.LOCATION) PteIMLocation(
    latitude = content.getDouble("latitude"), longitude = content.getDouble("longitude"), name = content.getString("name"), address = content.optNullableString("address"),
  ) else null
  val business = if (type in setOf(PteIMMessageType.GIFT, PteIMMessageType.RED_PACKET, PteIMMessageType.ORDER)) content.optNullableString("businessId")?.let { id -> PteIMBusinessContent(
    businessId = id, title = content.getString("title"), subtitle = content.optNullableString("subtitle"), actionUrl = content.optNullableString("actionUrl"),
  ) } else null
  val quote = content.optJSONObject("quote")?.let { value ->
    value.optNullableString("clientMsgId")?.let { clientMsgId ->
      PteIMQuote(
        clientMsgId = clientMsgId,
        serverMsgId = value.optNullableString("serverMsgId"),
        senderId = value.optNullableString("senderId"),
        text = value.optString("text"),
      )
    }
  }

  val reactions = json.optJSONArray("reactions")?.let { array ->
    (0 until array.length()).mapNotNull { index -> array.optJSONObject(index)?.let { value ->
      value.optNullableString("emoji")?.takeIf { it.isNotBlank() }?.let { emoji -> PteIMMessageReaction(emoji, value.optLong("count"), value.optBoolean("reactedByMe")) }
    } }
  } ?: emptyList()
  return PteIMMessage(
    conversationId = json.getString("conversationId"), senderId = json.optNullableString("senderId"),
    senderNickname = json.optNullableString("senderNickname") ?: json.optNullableString("senderName") ?: json.optNullableString("nickname"), type = type,
    text = content.optNullableString("text"), packageId = content.optNullableString("packageId"), emojiId = content.optNullableString("emojiId"),
    media = media, voice = voice, location = location, business = business, quote = quote, clientMsgId = json.getString("clientMsgId"), serverMsgId = json.optNullableString("serverMsgId"),
    serverSeq = json.optLong("serverSeq").takeIf { it > 0 }, createdAt = json.optLong("createdAt", System.currentTimeMillis()), state = PteIMSendState.SENT,
    status = json.optInt("status", 1), recalledAt = json.optLong("recalledAt").takeIf { it > 0 }, reactions = reactions,
  )
}

private fun reactionResultFromJson(json: JSONObject): PteIMMessageReactionResult {
  val reactions = json.optJSONArray("reactions") ?: JSONArray()
  return PteIMMessageReactionResult(json.getString("messageId"), (0 until reactions.length()).mapNotNull { index -> reactions.optJSONObject(index)?.let { value ->
    value.optNullableString("emoji")?.takeIf { it.isNotBlank() }?.let { emoji -> PteIMMessageReaction(emoji, value.optLong("count"), value.optBoolean("reactedByMe")) }
  } })
}

private fun JSONObject.optNullableString(name: String): String? =
  if (has(name) && !isNull(name)) optString(name).takeIf(String::isNotEmpty) else null

private fun mediaFromJson(json: JSONObject, cosDomain: String): PteIMMedia = PteIMMedia(
  url = resolveCosUrl(cosDomain, json.optNullableString("url")), thumbnailUrl = resolveCosUrl(cosDomain, json.optNullableString("thumbnailUrl")), coverUrl = resolveCosUrl(cosDomain, json.optNullableString("coverUrl")),
  width = json.optInt("width").takeIf { it > 0 }, height = json.optInt("height").takeIf { it > 0 },
  durationMs = json.optLong("durationMs").takeIf { it > 0 }, sizeBytes = json.optLong("sizeBytes").takeIf { it > 0 },
)

private fun remoteConversationFromJson(json: JSONObject): PteIMRemoteConversation = PteIMRemoteConversation(
  id = json.getLong("id"), type = json.optString("type"), title = json.optString("title"), avatar = json.optNullableString("avatar"),
  lastMessageSeq = json.optLong("last_message_seq"), lastMessageSnapshot = json.optNullableString("last_message_snapshot"),
  lastMessageAt = json.optLong("last_message_at"), unreadCount = json.optLong("unread_count"),
)

private fun pushDeviceFromJson(json: JSONObject): PteIMPushDevice = PteIMPushDevice(
  deviceId = json.getString("deviceId"),
  platform = PteIMPushPlatform.valueOf(json.getString("platform").uppercase()),
  notificationEnabled = json.optBoolean("notificationEnabled", true),
  lastSeenAt = json.optLong("lastSeenAt"),
)

private fun remoteMessageFromJson(json: JSONObject): PteIMRemoteMessage = PteIMRemoteMessage(
  messageId = json.getLong("message_id"), conversationId = json.getLong("conversation_id"), senderId = json.getLong("sender_id"),
  clientMsgId = json.optString("client_msg_id"), type = json.optString("msg_type"), content = json.optString("content"),
  payload = json.optNullableString("payload"), seq = json.optLong("seq"), sentAt = json.optLong("sent_at"),
  recalledAt = json.optLong("recalled_at").takeIf { it > 0 },
)

private fun messageExtension(type: PteIMMessageType): String = if (type == PteIMMessageType.IMAGE) "image" else "video"

private fun Context.displayName(uri: Uri): String? = contentResolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)?.use { cursor ->
  cursor.takeIf { it.moveToFirst() }?.getString(0)?.takeIf(String::isNotBlank)
}

private fun contentTypeForFileName(name: String): String = when (name.substringAfterLast('.', "").lowercase()) {
  "pdf" -> "application/pdf"; "txt" -> "text/plain"; "csv" -> "text/csv"; "json" -> "application/json"; "zip" -> "application/zip"; "7z" -> "application/x-7z-compressed"
  "doc" -> "application/msword"; "docx" -> "application/vnd.openxmlformats-officedocument.wordprocessingml.document"; "xls" -> "application/vnd.ms-excel"; "xlsx" -> "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"; "ppt" -> "application/vnd.ms-powerpoint"; "pptx" -> "application/vnd.openxmlformats-officedocument.presentationml.presentation"
  else -> throw IllegalArgumentException("Unsupported file content type; provide a URI with a supported MIME type")
}

private fun resolveCosUrl(cosDomain: String, value: String?): String? = value?.let {
  val uri = Uri.parse(it)
  if (!uri.scheme.isNullOrBlank()) it else cosDomain.trimEnd('/') + "/" + it.trimStart('/')
}

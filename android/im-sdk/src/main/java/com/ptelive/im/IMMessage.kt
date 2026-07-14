package com.ptelive.im

import org.json.JSONObject
import java.util.UUID

enum class PteIMMessageType { TEXT, EMOJI, IMAGE, VIDEO, VOICE, LOCATION, GIFT, RED_PACKET, ORDER }
enum class PteIMSendState { PENDING, UPLOADING, SENT, FAILED }

data class PteIMMedia(
  val url: String? = null,
  val thumbnailUrl: String? = null,
  val coverUrl: String? = null,
  val width: Int? = null,
  val height: Int? = null,
  val durationMs: Long? = null,
  val sizeBytes: Long? = null,
)

data class PteIMVoice(val url: String, val durationMs: Long, val waveform: String? = null, val sizeBytes: Long? = null)
data class PteIMLocation(val latitude: Double, val longitude: Double, val name: String, val address: String? = null)
data class PteIMBusinessContent(val businessId: String, val title: String, val subtitle: String? = null, val actionUrl: String? = null)

/** Locally cached conversation summary. Group/C2C semantics are supplied by the server conversation ID. */
data class PteIMConversation(
  val conversationId: String,
  val lastMessage: PteIMMessage,
  val updatedAt: Long,
)

/** Server-authoritative conversation page returned by POST /v1/im/conversations. */
data class PteIMRemoteConversation(
  val id: Long,
  val type: String,
  val title: String,
  val avatar: String?,
  val lastMessageSeq: Long,
  val lastMessageSnapshot: String?,
  val lastMessageAt: Long,
  val unreadCount: Long,
)
data class PteIMConversationPage(val total: Long, val items: List<PteIMRemoteConversation>)

/** Server-authoritative history row returned by POST /v1/im/conversations/messages. */
data class PteIMRemoteMessage(
  val messageId: Long,
  val conversationId: Long,
  val senderId: Long,
  val clientMsgId: String,
  val type: String,
  val content: String,
  val payload: String?,
  val seq: Long,
  val sentAt: Long,
  val recalledAt: Long?,
)
data class PteIMMessagePage(val items: List<PteIMRemoteMessage>)

data class PteIMMessage(
  val conversationId: String,
  val type: PteIMMessageType,
  val text: String? = null,
  val packageId: String? = null,
  val emojiId: String? = null,
  val media: PteIMMedia? = null,
  val voice: PteIMVoice? = null,
  val location: PteIMLocation? = null,
  val business: PteIMBusinessContent? = null,
  val clientMsgId: String = UUID.randomUUID().toString(),
  val serverMsgId: String? = null,
  val serverSeq: Long? = null,
  val createdAt: Long = System.currentTimeMillis(),
  val state: PteIMSendState = PteIMSendState.PENDING,
) {
  fun contentJson(): JSONObject = JSONObject().apply {
    text?.let { put("text", it) }
    packageId?.let { put("packageId", it) }
    emojiId?.let { put("emojiId", it) }
    media?.let {
      it.url?.let { value -> put("url", value) }
      it.thumbnailUrl?.let { value -> put("thumbnailUrl", value) }
      it.coverUrl?.let { value -> put("coverUrl", value) }
      it.width?.let { value -> put("width", value) }
      it.height?.let { value -> put("height", value) }
      it.durationMs?.let { value -> put("durationMs", value) }
      it.sizeBytes?.let { value -> put("sizeBytes", value) }
    }
    voice?.let { put("url", it.url); put("durationMs", it.durationMs); it.waveform?.let { value -> put("waveform", value) }; it.sizeBytes?.let { value -> put("sizeBytes", value) } }
    location?.let { put("latitude", it.latitude); put("longitude", it.longitude); put("name", it.name); it.address?.let { value -> put("address", value) } }
    business?.let { put("businessId", it.businessId); put("title", it.title); it.subtitle?.let { value -> put("subtitle", value) }; it.actionUrl?.let { value -> put("actionUrl", value) } }
  }

  fun toWireJson(): JSONObject = JSONObject().apply {
    put("clientMsgId", clientMsgId)
    put("conversationId", conversationId)
    put("type", type.name.lowercase())
    put("createdAt", createdAt)
    put("content", contentJson())
  }
}

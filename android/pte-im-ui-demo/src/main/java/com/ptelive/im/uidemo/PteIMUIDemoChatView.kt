package com.ptelive.im.uidemo

import android.content.Context
import android.view.View
import com.ptelive.im.PteIMBusinessContent
import com.ptelive.im.PteIMLocation
import com.ptelive.im.PteIMMedia
import com.ptelive.im.PteIMMessage
import com.ptelive.im.PteIMMessageType
import com.ptelive.im.PteIMSDK
import com.ptelive.im.PteIMSendState
import com.ptelive.im.PteIMVoice
import com.ptelive.im.ui.PteIMUIChatView
import com.ptelive.im.ui.PteIMUITheme

/**
 * Demo-only visual fixture. PteIMUIKit itself always renders cache/server
 * messages; this class fills an empty freshly-created test conversation so the
 * SDK's complete message and interaction surfaces can be reviewed offline.
 */
internal class PteIMUIDemoChatView(
  context: Context,
  client: PteIMSDK,
  conversationId: String,
  title: String,
) : PteIMUIChatView(context, client, conversationId, title, PteIMUITheme()) {
  init {
    isGroupChat = true
    groupMemberNicknameProvider = { message ->
      when (message.senderId) {
        "10002" -> "Alice Chen"
        else -> message.senderNickname
      }
    }
    post { render() }
  }
  // `render()` is invoked by the base class constructor before subclass
  // property initializers run, so this must tolerate the JVM's initial null.
  private var fixtureOutgoingMessages: MutableList<PteIMMessage>? = null
  private var cachedFixtureMessages: List<PteIMMessage>? = null
  private fun pendingFixtureMessages(): MutableList<PteIMMessage> =
    fixtureOutgoingMessages ?: mutableListOf<PteIMMessage>().also { fixtureOutgoingMessages = it }

  override fun messageAvatar(text: String, outgoing: Boolean): View = super.messageAvatar(
    text = if (outgoing) "M" else "A",
    outgoing = outgoing,
  )

  override fun render() {
    super.render()
    if (client.localMessages(conversationId, limit = 1).isNotEmpty()) return
    (fixtureMessages() + fixtureOutgoingMessages.orEmpty())
      .sortedBy { it.createdAt }
      .forEach { messages.addView(messageView(it)) }
    scroll.post { scroll.fullScroll(View.FOCUS_DOWN) }
  }

  /**
   * The review conversation intentionally has no server id.  Keep its send
   * path interactive without ever enqueueing a malformed outbox message.
   */
  override fun sendText(text: String) {
    text.trim().takeIf { it.isNotEmpty() }?.let { value ->
      pendingFixtureMessages() += PteIMMessage(
        conversationId = conversationId,
        type = PteIMMessageType.TEXT,
        senderId = client.currentUserId(),
        text = value,
        createdAt = System.currentTimeMillis(),
        state = PteIMSendState.SENT,
      )
      inputBar.clearText()
      render()
    }
  }

  override fun sendEmoji(packageId: String, emojiId: String) {
    pendingFixtureMessages() += PteIMMessage(
      conversationId = conversationId,
      type = PteIMMessageType.EMOJI,
      senderId = client.currentUserId(),
      packageId = packageId,
      emojiId = emojiId,
      createdAt = System.currentTimeMillis(),
      state = PteIMSendState.SENT,
    )
    render()
  }

  /**
   * The review fixture must keep stable Core message IDs while the screen is
   * redrawn. This is essential for optimistic reaction toggles and mirrors
   * real cached/server messages, whose IDs do not change between renders.
   */
  private fun fixtureMessages(): List<PteIMMessage> =
    cachedFixtureMessages ?: createFixtureMessages().also { cachedFixtureMessages = it }

  private fun createFixtureMessages(): List<PteIMMessage> {
    val now = System.currentTimeMillis() - 9 * 60_000L
    val remote = "10002"
    val mine = client.currentUserId()
    fun message(
      offset: Long,
      type: PteIMMessageType,
      sender: String,
      text: String? = null,
      media: PteIMMedia? = null,
      voice: PteIMVoice? = null,
      location: PteIMLocation? = null,
      business: PteIMBusinessContent? = null,
    ) = PteIMMessage(
      conversationId = conversationId,
      type = type,
      senderId = sender,
      senderNickname = if (sender == remote) "Alice Chen" else "Me",
      text = text,
      media = media,
      voice = voice,
      location = location,
      business = business,
      createdAt = now + offset,
      state = PteIMSendState.SENT,
    )
    return listOf(
      message(0, PteIMMessageType.TEXT, remote, "你好！在吗？Hey!\nAre you there?"),
      message(60_000, PteIMMessageType.TEXT, mine, "在的，什么事？\nYes, what's up?"),
      message(120_000, PteIMMessageType.LOCATION, remote, location = PteIMLocation(31.2304, 121.4737, "上海市浦东新区张江科技园", "Zhangjiang Hi-Tech Park, Pudong")),
      message(180_000, PteIMMessageType.IMAGE, remote, media = PteIMMedia(width = 1080, height = 720)),
      message(240_000, PteIMMessageType.VOICE, remote, voice = PteIMVoice("demo://voice-in", 8_000)),
      message(300_000, PteIMMessageType.VOICE, mine, voice = PteIMVoice("demo://voice-out", 15_000)),
      message(360_000, PteIMMessageType.VIDEO, remote, media = PteIMMedia(durationMs = 32_000)),
      message(420_000, PteIMMessageType.RED_PACKET, mine, business = PteIMBusinessContent("demo-red-out", "我 · Me", "恭喜发财，大吉大利")),
      message(480_000, PteIMMessageType.RED_PACKET, remote, business = PteIMBusinessContent("demo-red-in", "Alice", "恭喜发财，大吉大利")),
      message(540_000, PteIMMessageType.ORDER, remote, business = PteIMBusinessContent("demo-order", "iPhone 15 Pro 256GB 深空黑", "¥8,999")),
      message(600_000, PteIMMessageType.GIFT, mine, business = PteIMBusinessContent("demo-gift", "我 · Me", "星光礼盒 · Starlight Box")),
      message(660_000, PteIMMessageType.FILE, remote, media = PteIMMedia(fileName = "PteIMUIKit-交付说明.pdf", sizeBytes = 2_400_000, mimeType = "application/pdf")),
      message(720_000, PteIMMessageType.GIFT, remote, business = PteIMBusinessContent("demo-gift-in", "Alice", "玫瑰花束 · Rose Bouquet")),
    )
  }

  companion object {
    /** Never persisted or sent: it exists only to keep the Debug UI fixture isolated. */
    const val reviewConversationId = "pte-im-ui-review-work-team"
  }
}

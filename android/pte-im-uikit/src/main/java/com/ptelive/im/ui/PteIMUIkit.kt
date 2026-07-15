package com.ptelive.im.ui

import android.content.Context
import android.graphics.Color
import android.graphics.drawable.GradientDrawable
import android.view.Gravity
import android.view.View
import android.view.ViewGroup
import android.widget.LinearLayout
import android.widget.ScrollView
import android.widget.TextView
import com.ptelive.im.PteIMLanguage
import com.ptelive.im.PteIMListener
import com.ptelive.im.PteIMMessage
import com.ptelive.im.PteIMMessageType
import com.ptelive.im.PteIMSendState
import com.ptelive.im.PteIMThemeMode
import com.ptelive.im.PteIMSDK
import com.ptelive.im.systemTheme

/** Actions which need an application picker, location provider, or business workflow. */
enum class PteIMUIAction { IMAGE, VIDEO, VOICE, LOCATION, GIFT, RED_PACKET, ORDER }

/** Public, dependency-free Android UI Kit entry point. */
object PteIMUIkit {
  fun createChatView(context: Context, client: PteIMSDK, conversationId: String, title: String = conversationId, theme: PteIMUITheme = PteIMUITheme()): PteIMUIChatView =
    PteIMUIChatView(context, client, conversationId, title, theme)

  fun createConversationListView(context: Context, client: PteIMSDK, onConversationClick: (String) -> Unit): PteIMUIConversationListView =
    PteIMUIConversationListView(context, client, onConversationClick)
}

/**
 Reusable native View for one-to-one and group conversations. The message list
 and [PteIMUIInputBar] are intentionally separate, like MessageKit's content
 cell / InputBar architecture, but with no third-party dependency.
 */
class PteIMUIChatView(context: Context, private val client: PteIMSDK, private val conversationId: String, title: String, var uiTheme: PteIMUITheme = PteIMUITheme()) : LinearLayout(context) {
  var onActionRequested: ((PteIMUIAction) -> Unit)? = null
  var onVoiceRecordingChanged: ((Boolean) -> Unit)? = null
  private val messages = LinearLayout(context).apply { orientation = VERTICAL }
  private val scroll = ScrollView(context)
  private val header = TextView(context).apply { text = title; textSize = 18f; setPadding(dp(22), dp(16), dp(22), dp(10)) }
  private val inputBar = PteIMUIInputBar(context, resolvePalette())
  private var palette = resolvePalette()
  private val listener = object : PteIMListener {
    override fun onMessage(message: PteIMMessage) { if (message.conversationId == conversationId) post { render() } }
    override fun onMessageStateChanged(clientMsgId: String, state: PteIMSendState) { post { render() } }
    override fun onThemeModeChanged(themeMode: PteIMThemeMode) { post { applyTheme() } }
    override fun onLanguageChanged(language: PteIMLanguage) { post { applyTheme() } }
  }

  init {
    orientation = VERTICAL
    addView(header, LayoutParams(-1, -2))
    scroll.isFillViewport = true
    scroll.addView(messages, ViewGroup.LayoutParams(-1, -2)); addView(scroll, LayoutParams(-1, 0, 1f))
    addView(inputBar, LayoutParams(-1, -2))
    inputBar.onSendText = { sendText(it) }
    inputBar.onEmojiSelected = { packageId, emojiId -> client.sendEmoji(conversationId, packageId, emojiId); render() }
    inputBar.onActionSelected = { action -> onActionRequested?.invoke(action) }
    inputBar.onVoiceRecordingChanged = { active -> onVoiceRecordingChanged?.invoke(active) }
    client.addListener(listener); applyTheme(); render()
  }

  override fun onDetachedFromWindow() { client.removeListener(listener); super.onDetachedFromWindow() }
  override fun onAttachedToWindow() { super.onAttachedToWindow(); client.addListener(listener); render() }
  fun setTheme(theme: PteIMUITheme) { uiTheme = theme; applyTheme() }
  fun sendText(text: String) { text.trim().takeIf { it.isNotEmpty() }?.let { client.sendText(conversationId, it); inputBar.clearText(); render() } }
  fun refresh() = render()

  private fun render() {
    messages.removeAllViews()
    client.localMessages(conversationId, limit = 100).forEach { messages.addView(messageView(it)) }
    scroll.post { scroll.fullScroll(View.FOCUS_DOWN) }
  }
  private fun messageView(message: PteIMMessage): View {
    val outgoing = message.senderId == client.currentUserId()
    val text = TextView(context).apply {
      this.text = messageLabel(message); textSize = 15f; setTextColor(if (outgoing) palette.outgoingText else palette.incomingText)
      setPadding(dp(15), dp(10), dp(15), dp(10)); background = if (outgoing) gradient(palette.outgoingStart, palette.outgoingEnd, 18) else rounded(palette.incomingBubble, palette.incomingBubble, 18)
    }
    return LinearLayout(context).apply { gravity = if (outgoing) Gravity.END else Gravity.START; setPadding(dp(16), dp(4), dp(16), dp(4)); addView(text, LayoutParams(-2, -2)) }
  }
  private fun messageLabel(message: PteIMMessage): String = when (message.type) {
    PteIMMessageType.TEXT -> message.text.orEmpty(); PteIMMessageType.EMOJI -> "${message.packageId ?: "emoji"}:${message.emojiId ?: ""}"; PteIMMessageType.IMAGE -> "[Image]"; PteIMMessageType.VIDEO -> "[Video]"; PteIMMessageType.VOICE -> "[Voice]"; PteIMMessageType.LOCATION -> "[Location] ${message.location?.name.orEmpty()}"; PteIMMessageType.GIFT -> "[Gift] ${message.business?.title.orEmpty()}"; PteIMMessageType.RED_PACKET -> "[Red packet] ${message.business?.title.orEmpty()}"; PteIMMessageType.ORDER -> "[Order] ${message.business?.title.orEmpty()}"
  }
  private fun applyTheme() {
    palette = resolvePalette(); setBackgroundColor(palette.background); header.setTextColor(palette.primaryText); inputBar.applyPalette(palette)
    val english = client.currentAppearance().language == PteIMLanguage.EN_US
    inputBar.setCopy(if (english) "Message" else "输入消息", if (english) "Send" else "发送", if (english) "Hold to talk" else "按住说话")
    render()
  }
  private fun resolvePalette(): PteIMUIThemePalette = when (client.currentAppearance().themeMode) { PteIMThemeMode.DARK -> uiTheme.dark; PteIMThemeMode.LIGHT -> uiTheme.light; PteIMThemeMode.SYSTEM -> if (systemTheme(context).name == "DARK") uiTheme.dark else uiTheme.light }
  private fun rounded(fill: Int, stroke: Int, radius: Int) = GradientDrawable().apply { setColor(fill); setStroke(dp(1), stroke); cornerRadius = dp(radius).toFloat() }
  private fun gradient(start: Int, end: Int, radius: Int) = GradientDrawable(GradientDrawable.Orientation.LEFT_RIGHT, intArrayOf(start, end)).apply { cornerRadius = dp(radius).toFloat() }
  private fun dp(value: Int) = (value * resources.displayMetrics.density).toInt()
}

/** Cache-first conversation list; navigate with the selected conversation identifier. */
class PteIMUIConversationListView(context: Context, private val client: PteIMSDK, private val onConversationClick: (String) -> Unit) : ScrollView(context) {
  private val content = LinearLayout(context).apply { orientation = LinearLayout.VERTICAL }
  private val listener = object : PteIMListener { override fun onMessage(message: PteIMMessage) { post { refresh() } }; override fun onMessageStateChanged(clientMsgId: String, state: PteIMSendState) { post { refresh() } } }
  init { addView(content); client.addListener(listener); refresh() }
  override fun onDetachedFromWindow() { client.removeListener(listener); super.onDetachedFromWindow() }
  override fun onAttachedToWindow() { super.onAttachedToWindow(); client.addListener(listener); refresh() }
  fun refresh() { content.removeAllViews(); client.localConversations().forEach { item -> content.addView(TextView(context).apply { text = "${item.conversationId}\n${item.lastMessage.text ?: item.lastMessage.type.name.lowercase()}"; textSize = 16f; setPadding(24, 22, 24, 22); setOnClickListener { onConversationClick(item.conversationId) } }) } }
}

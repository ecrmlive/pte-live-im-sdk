package com.ptelive.im.ui

import android.content.Context
import android.graphics.Color
import android.graphics.drawable.GradientDrawable
import android.view.Gravity
import android.view.View
import android.view.ViewGroup
import android.widget.Button
import android.widget.EditText
import android.widget.LinearLayout
import android.widget.ScrollView
import android.widget.TextView
import com.ptelive.im.PteIMLanguage
import com.ptelive.im.PteIMListener
import com.ptelive.im.PteIMMessage
import com.ptelive.im.PteIMMessageType
import com.ptelive.im.PteIMSendState
import com.ptelive.im.PteIMThemeMode
import com.ptelive.im.PteLiveIM
import com.ptelive.im.systemTheme

/** Actions which need an application picker, location provider, or business workflow. */
enum class PteIMUIAction { IMAGE, VIDEO, VOICE, LOCATION, GIFT, RED_PACKET, ORDER }

/** Public, dependency-free Android UI Kit entry point. */
object PteIMUIKit {
  fun createChatView(context: Context, client: PteLiveIM, conversationId: String, title: String = conversationId): PteIMUIChatView =
    PteIMUIChatView(context, client, conversationId, title)

  fun createConversationListView(context: Context, client: PteLiveIM, onConversationClick: (String) -> Unit): PteIMUIConversationListView =
    PteIMUIConversationListView(context, client, onConversationClick)
}

/** Reusable native View for one-to-one and group conversations. */
class PteIMUIChatView(context: Context, private val client: PteLiveIM, private val conversationId: String, title: String) : LinearLayout(context) {
  var onActionRequested: ((PteIMUIAction) -> Unit)? = null
  private val messages = LinearLayout(context).apply { orientation = VERTICAL }
  private val scroll = ScrollView(context)
  private val composer = EditText(context).apply { hint = "Message"; minLines = 1; maxLines = 4 }
  private val header = TextView(context).apply { text = title; textSize = 18f; setPadding(24, 20, 24, 12) }
  private var theme = resolveTheme()
  private val listener = object : PteIMListener {
    override fun onMessage(message: PteIMMessage) { if (message.conversationId == conversationId) post { render() } }
    override fun onMessageStateChanged(clientMsgId: String, state: PteIMSendState) { post { render() } }
    override fun onThemeModeChanged(themeMode: PteIMThemeMode) { post { applyTheme() } }
    override fun onLanguageChanged(language: PteIMLanguage) { post { applyTheme() } }
  }

  init {
    orientation = VERTICAL
    addView(header, LayoutParams(-1, -2))
    scroll.addView(messages, ViewGroup.LayoutParams(-1, -2)); addView(scroll, LayoutParams(-1, 0, 1f))
    addView(LinearLayout(context).apply { orientation = HORIZONTAL; setPadding(16, 8, 16, 4); addView(composer, LayoutParams(0, -2, 1f)); addView(button("Send") { sendText() }, LayoutParams(-2, -2)) }, LayoutParams(-1, -2))
    addView(LinearLayout(context).apply {
      orientation = HORIZONTAL; gravity = Gravity.CENTER_VERTICAL; setPadding(12, 0, 12, 12)
      listOf("😀" to null, "Image" to PteIMUIAction.IMAGE, "Video" to PteIMUIAction.VIDEO, "Voice" to PteIMUIAction.VOICE, "More" to PteIMUIAction.LOCATION).forEach { (label, action) ->
        addView(button(label) { if (action == null) client.sendEmoji(conversationId, "default", "smile_001") else if (action == PteIMUIAction.LOCATION) showMoreActions() else onActionRequested?.invoke(action) }, LayoutParams(0, -2, 1f))
      }
    }, LayoutParams(-1, -2))
    client.addListener(listener); applyTheme(); render()
  }

  override fun onDetachedFromWindow() { client.removeListener(listener); super.onDetachedFromWindow() }
  override fun onAttachedToWindow() { super.onAttachedToWindow(); client.addListener(listener); render() }
  fun sendText() { composer.text.toString().trim().takeIf { it.isNotEmpty() }?.let { client.sendText(conversationId, it); composer.setText(""); render() } }
  fun refresh() = render()

  private fun showMoreActions() {
    val actions = LinearLayout(context).apply { orientation = HORIZONTAL; gravity = Gravity.CENTER }
    listOf(PteIMUIAction.LOCATION to "Location", PteIMUIAction.GIFT to "Gift", PteIMUIAction.RED_PACKET to "Red packet", PteIMUIAction.ORDER to "Order").forEach { (action, label) -> actions.addView(button(label) { onActionRequested?.invoke(action) }, LayoutParams(0, -2, 1f)) }
    if (childCount > 3) removeViewAt(3)
    addView(actions, 3)
  }

  private fun render() { messages.removeAllViews(); client.localMessages(conversationId, limit = 100).forEach { messages.addView(messageView(it)) }; scroll.post { scroll.fullScroll(View.FOCUS_DOWN) } }
  private fun messageView(message: PteIMMessage): View {
    val outgoing = message.serverMsgId == null
    val text = TextView(context).apply { this.text = messageLabel(message); textSize = 15f; setTextColor(if (outgoing) Color.WHITE else theme.primaryText); setPadding(18, 12, 18, 12); background = GradientDrawable().apply { setColor(if (outgoing) theme.outgoingBubble else theme.incomingBubble); cornerRadius = 22f } }
    return LinearLayout(context).apply { gravity = if (outgoing) Gravity.END else Gravity.START; setPadding(16, 6, 16, 6); addView(text, LayoutParams(-2, -2)) }
  }
  private fun messageLabel(message: PteIMMessage): String = when (message.type) {
    PteIMMessageType.TEXT -> message.text.orEmpty(); PteIMMessageType.EMOJI -> "${message.packageId ?: "emoji"}:${message.emojiId ?: ""}"; PteIMMessageType.IMAGE -> "[Image]"; PteIMMessageType.VIDEO -> "[Video]"; PteIMMessageType.VOICE -> "[Voice]"; PteIMMessageType.LOCATION -> "[Location] ${message.location?.name.orEmpty()}"; PteIMMessageType.GIFT -> "[Gift] ${message.business?.title.orEmpty()}"; PteIMMessageType.RED_PACKET -> "[Red packet] ${message.business?.title.orEmpty()}"; PteIMMessageType.ORDER -> "[Order] ${message.business?.title.orEmpty()}"
  }
  private fun applyTheme() { theme = resolveTheme(); setBackgroundColor(theme.background); header.setTextColor(theme.primaryText); composer.setTextColor(theme.primaryText); composer.setHintTextColor(theme.secondaryText); render() }
  private fun resolveTheme(): PteIMUITheme = when (client.currentAppearance().themeMode) { PteIMThemeMode.DARK -> PteIMUITheme.dark(); PteIMThemeMode.LIGHT -> PteIMUITheme.light(); PteIMThemeMode.SYSTEM -> if (systemTheme(context).name == "DARK") PteIMUITheme.dark() else PteIMUITheme.light() }
  private fun button(label: String, action: () -> Unit) = Button(context).apply { text = label; isAllCaps = false; setOnClickListener { action() } }
}

/** Cache-first conversation list; navigate with the selected conversation identifier. */
class PteIMUIConversationListView(context: Context, private val client: PteLiveIM, private val onConversationClick: (String) -> Unit) : ScrollView(context) {
  private val content = LinearLayout(context).apply { orientation = LinearLayout.VERTICAL }
  private val listener = object : PteIMListener { override fun onMessage(message: PteIMMessage) { post { refresh() } }; override fun onMessageStateChanged(clientMsgId: String, state: PteIMSendState) { post { refresh() } } }
  init { addView(content); client.addListener(listener); refresh() }
  override fun onDetachedFromWindow() { client.removeListener(listener); super.onDetachedFromWindow() }
  override fun onAttachedToWindow() { super.onAttachedToWindow(); client.addListener(listener); refresh() }
  fun refresh() { content.removeAllViews(); client.localConversations().forEach { item -> content.addView(TextView(context).apply { text = "${item.conversationId}\n${item.lastMessage.text ?: item.lastMessage.type.name.lowercase()}"; textSize = 16f; setPadding(24, 22, 24, 22); setOnClickListener { onConversationClick(item.conversationId) } }) } }
}

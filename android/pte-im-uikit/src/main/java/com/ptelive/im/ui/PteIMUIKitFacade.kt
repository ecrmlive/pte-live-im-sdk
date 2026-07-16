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
import android.widget.Button
import com.ptelive.im.PteIMLanguage
import com.ptelive.im.PteIMListener
import com.ptelive.im.PteIMContact
import com.ptelive.im.PteIMContactPage
import com.ptelive.im.PteIMGroupPage
import com.ptelive.im.PteIMMessage
import com.ptelive.im.PteIMMessageType
import com.ptelive.im.PteIMSendState
import com.ptelive.im.PteIMThemeMode
import com.ptelive.im.PteIMSDK
import com.ptelive.im.systemTheme

/** Actions which need an application picker, location provider, or business workflow. */
enum class PteIMUIAction { IMAGE, CAMERA, VIDEO, VOICE, LOCATION, GIFT, RED_PACKET, ORDER, FILE }

/** Built-in SDK directories. `CUSTOM` leaves all rows and loading to the host application. */
enum class PteIMUIContactListMode { FRIENDS, FOLLOWS, GROUPS, CUSTOM }

/** Display metadata can be replaced by an inheriting view before it creates a cell. */
data class PteIMUIContactPresentation(val identifier: String, val title: String, val subtitle: String = "", val avatarText: String = title.take(1), val isGroup: Boolean = false)

/** Public, dependency-free Android UI Kit entry point. */
object PteIMUIKit {
  fun createChatView(context: Context, client: PteIMSDK, conversationId: String, title: String = conversationId, theme: PteIMUITheme = PteIMUITheme()): PteIMUIChatView =
    PteIMUIChatView(context, client, conversationId, title, theme)

  fun createConversationListView(context: Context, client: PteIMSDK, theme: PteIMUITheme = PteIMUITheme(), onConversationClick: (String) -> Unit): PteIMUIConversationListView =
    PteIMUIConversationListView(context, client, onConversationClick, theme)

  fun createContactListView(context: Context, client: PteIMSDK, mode: PteIMUIContactListMode = PteIMUIContactListMode.FRIENDS, theme: PteIMUITheme = PteIMUITheme(), onConversationClick: (String, String) -> Unit): PteIMUIContactListView =
    PteIMUIContactListView(context, client, mode, onConversationClick, theme)
}

/**
 Reusable native View for one-to-one and group conversations. The message list
 and [PteIMUIInputBar] are intentionally separate, like MessageKit's content
 cell / InputBar architecture, but with no third-party dependency.
 */
open class PteIMUIChatView(context: Context, protected val client: PteIMSDK, protected val conversationId: String, title: String, var uiTheme: PteIMUITheme = PteIMUITheme()) : LinearLayout(context) {
  var onActionRequested: ((PteIMUIAction) -> Unit)? = null
  var onVoiceRecordingChanged: ((Boolean) -> Unit)? = null
  protected val messages = LinearLayout(context).apply { orientation = VERTICAL }
  protected val scroll = ScrollView(context)
  protected val header = TextView(context).apply { text = title; textSize = 18f; setPadding(dp(22), dp(16), dp(22), dp(10)) }
  protected val inputBar = PteIMUIInputBar(context, resolvePalette())
  protected var palette = resolvePalette()
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

  open fun render() {
    messages.removeAllViews()
    client.localMessages(conversationId, limit = 100).forEach { messages.addView(messageView(it)) }
    scroll.post { scroll.fullScroll(View.FOCUS_DOWN) }
  }
  open fun messageView(message: PteIMMessage): View {
    val outgoing = message.senderId == client.currentUserId()
    val text = TextView(context).apply {
      this.text = messageLabel(message); textSize = 15f; setTextColor(if (outgoing) palette.outgoingText else palette.incomingText)
      setPadding(dp(15), dp(10), dp(15), dp(10)); background = if (outgoing) gradient(palette.outgoingStart, palette.outgoingEnd, 18) else rounded(palette.incomingBubble, palette.incomingBubble, 18)
    }
    return LinearLayout(context).apply { gravity = if (outgoing) Gravity.END else Gravity.START; setPadding(dp(16), dp(4), dp(16), dp(4)); addView(text, LayoutParams(-2, -2)) }
  }
  open fun messageLabel(message: PteIMMessage): String = when (message.type) {
    PteIMMessageType.TEXT -> message.text.orEmpty(); PteIMMessageType.EMOJI -> "${message.packageId ?: "emoji"}:${message.emojiId ?: ""}"; PteIMMessageType.IMAGE -> "[Image]"; PteIMMessageType.VIDEO -> "[Video]"; PteIMMessageType.VOICE -> "[Voice]"; PteIMMessageType.LOCATION -> "[Location] ${message.location?.name.orEmpty()}"; PteIMMessageType.GIFT -> "[Gift] ${message.business?.title.orEmpty()}"; PteIMMessageType.RED_PACKET -> "[Red packet] ${message.business?.title.orEmpty()}"; PteIMMessageType.ORDER -> "[Order] ${message.business?.title.orEmpty()}"; PteIMMessageType.FILE -> "[File]"
  }
  open fun applyTheme() {
    palette = resolvePalette(); setBackgroundColor(palette.background); header.setTextColor(palette.primaryText); inputBar.applyPalette(palette)
    val english = client.currentAppearance().language == PteIMLanguage.EN_US
    inputBar.setCopy(if (english) "Message" else "输入消息", if (english) "Send" else "发送", if (english) "Hold to talk" else "按住说话")
    render()
  }
  protected fun resolvePalette(): PteIMUIThemePalette = when (client.currentAppearance().themeMode) { PteIMThemeMode.DARK -> uiTheme.dark; PteIMThemeMode.LIGHT -> uiTheme.light; PteIMThemeMode.SYSTEM -> if (systemTheme(context).name == "DARK") uiTheme.dark else uiTheme.light }
  protected fun rounded(fill: Int, stroke: Int, radius: Int) = GradientDrawable().apply { setColor(fill); setStroke(dp(1), stroke); cornerRadius = dp(radius).toFloat() }
  protected fun gradient(start: Int, end: Int, radius: Int) = GradientDrawable(GradientDrawable.Orientation.LEFT_RIGHT, intArrayOf(start, end)).apply { cornerRadius = dp(radius).toFloat() }
  protected fun dp(value: Int) = (value * resources.displayMetrics.density).toInt()
}

/** Cache-first conversation list; navigate with the selected conversation identifier. */
open class PteIMUIConversationListView(context: Context, protected val client: PteIMSDK, protected val onConversationClick: (String) -> Unit, var uiTheme: PteIMUITheme = PteIMUITheme()) : ScrollView(context) {
  private val content = LinearLayout(context).apply { orientation = LinearLayout.VERTICAL }
  private val listener = object : PteIMListener {
    override fun onMessage(message: PteIMMessage) { post { refresh() } }
    override fun onMessageStateChanged(clientMsgId: String, state: PteIMSendState) { post { refresh() } }
    override fun onThemeModeChanged(themeMode: PteIMThemeMode) { post { applyTheme() } }
  }
  init { addView(content); client.addListener(listener); applyTheme() }
  override fun onDetachedFromWindow() { client.removeListener(listener); super.onDetachedFromWindow() }
  override fun onAttachedToWindow() { super.onAttachedToWindow(); client.addListener(listener); applyTheme() }
  fun setTheme(theme: PteIMUITheme) { uiTheme = theme; applyTheme() }
  open fun applyTheme() { setBackgroundColor(resolvePalette().background); refresh() }
  open fun refresh() { content.removeAllViews(); client.localConversations().forEach { item -> content.addView(conversationRow(item.conversationId, item.lastMessage.text ?: item.lastMessage.type.name.lowercase())) } }
  /** Replace this to provide avatars, unread badges or a custom row layout. */
  open fun conversationRow(conversationId: String, preview: String): View {
    val palette = resolvePalette()
    return TextView(context).apply { text = "$conversationId\n$preview"; textSize = 16f; setTextColor(palette.primaryText); setPadding(dp(24), dp(16), dp(24), dp(16)); setBackgroundColor(palette.surface); setOnClickListener { onConversationClick(conversationId) } }
  }
  protected fun resolvePalette(): PteIMUIThemePalette = when (client.currentAppearance().themeMode) { PteIMThemeMode.DARK -> uiTheme.dark; PteIMThemeMode.LIGHT -> uiTheme.light; PteIMThemeMode.SYSTEM -> if (systemTheme(context).name == "DARK") uiTheme.dark else uiTheme.light }
  protected fun dp(value: Int) = (value * resources.displayMetrics.density).toInt()
}

/**
 Cursor-paginated friends, follows or group directory. The list opens a C2C
 conversation through Core for person rows; group rows already carry their
 conversation identifier. Override [presentation] or [contactRow] for a fully
 branded list without duplicating networking and paging behaviour.
 */
open class PteIMUIContactListView(
  context: Context,
  protected val client: PteIMSDK,
  val mode: PteIMUIContactListMode = PteIMUIContactListMode.FRIENDS,
  protected val onConversationClick: (String, String) -> Unit,
  var uiTheme: PteIMUITheme = PteIMUITheme(),
) : ScrollView(context) {
  protected val content = LinearLayout(context).apply { orientation = LinearLayout.VERTICAL }
  var onAvatarTapped: ((PteIMUIContactPresentation) -> Unit)? = null
  var onLoadError: ((Throwable) -> Unit)? = null
  var contacts: List<PteIMUIContactPresentation> = emptyList(); private set
  var hasMore: Boolean = false; private set
  private var cursor = ""
  private var loading = false
  private val appearanceListener = object : PteIMListener { override fun onThemeModeChanged(themeMode: PteIMThemeMode) { post { applyTheme() } } }

  init {
    addView(content, LayoutParams(-1, -2)); client.addListener(appearanceListener); applyTheme()
    setOnScrollChangeListener { _, _, scrollY, _, _ -> if (childCount > 0 && scrollY + height >= getChildAt(0).height - dp(96)) loadNextPage() }
    refresh()
  }

  override fun onDetachedFromWindow() { client.removeListener(appearanceListener); super.onDetachedFromWindow() }
  override fun onAttachedToWindow() { super.onAttachedToWindow(); client.addListener(appearanceListener); applyTheme() }

  /** Starts at the first SDK cursor. Custom mode only redraws host-supplied contacts. */
  open fun refresh() {
    cursor = ""; hasMore = false
    if (mode == PteIMUIContactListMode.CUSTOM) render() else loadNextPage(replacing = true)
  }
  fun setTheme(theme: PteIMUITheme) { uiTheme = theme; applyTheme() }
  open fun applyTheme() { setBackgroundColor(resolvePalette().background); render() }
  open fun loadNextPage(replacing: Boolean = false) {
    if (mode == PteIMUIContactListMode.CUSTOM || loading || (!replacing && !hasMore && contacts.isNotEmpty())) return
    loading = true
    val requestedCursor = if (replacing) "" else cursor
    when (mode) {
      PteIMUIContactListMode.FRIENDS -> client.fetchFriends(requestedCursor, 50) { page -> receiveContacts(page, replacing) }
      PteIMUIContactListMode.FOLLOWS -> client.fetchFollows(requestedCursor, 50) { page -> receiveContacts(page, replacing) }
      PteIMUIContactListMode.GROUPS -> client.fetchGroups(requestedCursor, 50) { page -> receiveGroups(page, replacing) }
      PteIMUIContactListMode.CUSTOM -> Unit
    }
  }
  /** Allows a host to replace the entire custom list without any SDK request. */
  open fun setCustomContacts(value: List<PteIMUIContactPresentation>) {
    require(mode == PteIMUIContactListMode.CUSTOM) { "setCustomContacts requires CUSTOM mode" }
    contacts = value; cursor = ""; hasMore = false; render()
  }
  open fun presentation(contact: PteIMContact): PteIMUIContactPresentation {
    val title = contact.remark.ifBlank { contact.nickname.ifBlank { contact.userId } }
    return PteIMUIContactPresentation(contact.userId, title, if (contact.remark.isBlank()) "" else contact.nickname)
  }
  /** Replace this to use remote avatars, custom typography or a bespoke cell View. */
  open fun contactRow(item: PteIMUIContactPresentation): View = LinearLayout(context).apply {
    orientation = LinearLayout.HORIZONTAL; gravity = Gravity.CENTER_VERTICAL; setPadding(dp(20), dp(12), dp(20), dp(12)); setBackgroundColor(resolvePalette().surface)
    val palette = resolvePalette()
    addView(Button(context).apply { text = item.avatarText; textSize = 14f; isAllCaps = false; setTextColor(palette.outgoingText); background = avatarBackground(palette); setOnClickListener { onAvatarTapped?.invoke(item) } }, LinearLayout.LayoutParams(dp(44), dp(44)))
    addView(LinearLayout(context).apply {
      orientation = LinearLayout.VERTICAL; setPadding(dp(12), 0, 0, 0)
      addView(TextView(context).apply { text = item.title; textSize = 16f; setTextColor(resolvePalette().primaryText) })
      if (item.subtitle.isNotBlank()) addView(TextView(context).apply { text = item.subtitle; textSize = 13f; setTextColor(resolvePalette().secondaryText) })
      setOnClickListener { select(item) }
    }, LinearLayout.LayoutParams(0, -2, 1f))
  }
  open fun select(item: PteIMUIContactPresentation) {
    if (item.isGroup) { onConversationClick(item.identifier, item.title); return }
    val userId = item.identifier.toLongOrNull() ?: return
    client.openSingleConversation(userId) { result -> post { result.onSuccess { conversation -> onConversationClick(conversation.id.toString(), item.title) }.onFailure { onLoadError?.invoke(it) } } }
  }
  protected open fun render() {
    content.removeAllViews(); contacts.forEach { content.addView(contactRow(it), LayoutParams(-1, -2)) }
  }
  private fun receiveContacts(result: Result<PteIMContactPage>, replacing: Boolean) = post {
    result.onSuccess { page -> applyPage(page.list.map(::presentation), page.nextCursor, page.hasMore, replacing) }.onFailure { finishFailure(it) }
  }
  private fun receiveGroups(result: Result<PteIMGroupPage>, replacing: Boolean) = post {
    result.onSuccess { page -> applyPage(page.list.map { group -> PteIMUIContactPresentation(group.id.toString(), group.title.ifBlank { group.id.toString() }, isGroup = true) }, page.nextCursor, page.hasMore, replacing) }.onFailure { finishFailure(it) }
  }
  private fun applyPage(values: List<PteIMUIContactPresentation>, nextCursor: String, more: Boolean, replacing: Boolean) {
    contacts = if (replacing) values else (contacts + values).distinctBy { "${it.isGroup}:${it.identifier}" }
    cursor = nextCursor; hasMore = more; loading = false; render()
  }
  private fun finishFailure(error: Throwable) { loading = false; onLoadError?.invoke(error) }
  protected fun resolvePalette(): PteIMUIThemePalette = when (client.currentAppearance().themeMode) { PteIMThemeMode.DARK -> uiTheme.dark; PteIMThemeMode.LIGHT -> uiTheme.light; PteIMThemeMode.SYSTEM -> if (systemTheme(context).name == "DARK") uiTheme.dark else uiTheme.light }
  private fun avatarBackground(palette: PteIMUIThemePalette) = GradientDrawable(GradientDrawable.Orientation.LEFT_RIGHT, intArrayOf(palette.outgoingStart, palette.outgoingEnd)).apply { cornerRadius = dp(22).toFloat() }
  private fun dp(value: Int) = (value * resources.displayMetrics.density).toInt()
}

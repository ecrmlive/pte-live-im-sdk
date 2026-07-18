package com.ptelive.im.ui

import android.content.Context
import android.content.ClipData
import android.content.ClipboardManager
import android.app.Activity
import android.graphics.drawable.ColorDrawable
import android.graphics.Color
import android.graphics.Typeface
import android.graphics.drawable.GradientDrawable
import android.text.Editable
import android.text.TextWatcher
import android.view.Gravity
import android.view.View
import android.view.ViewGroup
import android.widget.EditText
import android.widget.ImageButton
import android.widget.ImageView
import android.widget.LinearLayout
import android.widget.ScrollView
import android.widget.TextView
import android.widget.Button
import android.widget.FrameLayout
import android.widget.ProgressBar
import android.widget.PopupWindow
import com.ptelive.im.PteIMLanguage
import com.ptelive.im.PteIMListener
import com.ptelive.im.PteIMContact
import com.ptelive.im.PteIMContactPage
import com.ptelive.im.PteIMGroupPage
import com.ptelive.im.PteIMRemoteConversation
import com.ptelive.im.PteIMMessage
import com.ptelive.im.PteIMMessageType
import com.ptelive.im.PteIMQuote
import com.ptelive.im.PteIMSendState
import com.ptelive.im.PteIMThemeMode
import com.ptelive.im.PteIMSDK
import com.ptelive.im.systemTheme
import kotlin.math.min

/** Actions which need an application picker, location provider, or business workflow. */
enum class PteIMUIAction { IMAGE, CAMERA, VIDEO, VOICE, LOCATION, GIFT, RED_PACKET, ORDER, FILE }

/** One host-defined action slot. The input panel supports its eight standard slots plus up to four of these. */
data class PteIMUICustomInputAction(val identifier: String, val title: String, val iconResource: Int)

/** A 44dp emoji cell. Use [iconResource] for a host-provided 24×32 image, or [glyph] for Unicode Emoji6 content. */
data class PteIMUIEmoji(val packageId: String = "unicode", val emojiId: String, val glyph: String? = emojiId, val iconResource: Int? = null)

/** Exposes separate common and all-emoji lists; both lists can be replaced by the embedding application. */
data class PteIMUIEmojiDataSource(val common: List<PteIMUIEmoji>, val all: List<PteIMUIEmoji>)

/** Long-press actions are executed locally by UIKit, then surfaced to the host for audit/sync. */
enum class PteIMUIMessageAction { REACT, QUOTE, COPY, REVOKE, DELETE }

/**
 * Standard business/custom dispatch payload. Built-in business kinds map to
 * Core wire types; CUSTOM deliberately remains host-owned until its server
 * contract is registered.
 */
data class PteIMUICustomMessage(
  val kind: Kind,
  val content: com.ptelive.im.PteIMBusinessContent,
  val payload: String? = null,
) {
  enum class Kind { GIFT, RED_PACKET, ORDER, CUSTOM }
}

/** Delivery receipt presentation; Core stays transport-focused and does not infer read state. */
enum class PteIMUIReceiptStatus { READ, UNREAD, HIDDEN }

/** Built-in SDK directories. `CUSTOM` leaves all rows and loading to the host application. */
enum class PteIMUIContactListMode { FRIENDS, FOLLOWS, GROUPS, CUSTOM }

/** Display metadata can be replaced by an inheriting view before it creates a cell. */
data class PteIMUIContactPresentation(val identifier: String, val title: String, val subtitle: String = "", val avatarText: String = title.take(1), val isGroup: Boolean = false)
/**
 * Host-persisted reaction summary. [reactedByCurrentUser] lets UIKit apply a
 * local add/remove toggle without guessing whether the current user already
 * contributed to a server-provided aggregate count.
 */
data class PteIMUIReaction(
  val emoji: String,
  val count: Int,
  val reactedByCurrentUser: Boolean = false,
)

/**
 * Fully replaceable conversation-cell content. Hosts can transform this model
 * without duplicating Core cache, unread-count, search or navigation logic.
 */
data class PteIMUIConversationPresentation(
  val conversationId: String,
  val title: String,
  val preview: String,
  val timeText: String,
  val unreadCount: Long = 0,
  val avatarText: String = title.take(1),
  val avatarColor: Int? = null,
  val isOnline: Boolean = false,
)

/** Public, dependency-free Android UI Kit entry point. */
object PteIMUIKit {
  fun createChatView(context: Context, client: PteIMSDK, conversationId: String, title: String = conversationId, theme: PteIMUITheme = PteIMUITheme()): PteIMUIChatView =
    PteIMUIChatView(context, client, conversationId, title, theme)

  /** Creates a group chat whose incoming message cells expose each sender's group alias. */
  fun createGroupChatView(context: Context, client: PteIMSDK, conversationId: String, title: String = conversationId, theme: PteIMUITheme = PteIMUITheme()): PteIMUIChatView =
    PteIMUIChatView(context, client, conversationId, title, theme).apply { isGroupChat = true }

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
  /** Enable for group conversations. Only other members' messages show the sender name. */
  open var isGroupChat: Boolean = false
  /** Lets an embedding app resolve a group alias from its own member cache. */
  var groupMemberNicknameProvider: ((PteIMMessage) -> String?)? = null
  var onActionRequested: ((PteIMUIAction) -> Unit)? = null
  var onCustomInputActionRequested: ((PteIMUICustomInputAction) -> Unit)? = null
  var onAttachmentError: ((Throwable) -> Unit)? = null
  var onVoiceRecordingChanged: ((Boolean) -> Unit)? = null
  var onVoiceRecordingCancelled: (() -> Unit)? = null
  var onBackRequested: (() -> Unit)? = null
  var onVoiceCallRequested: (() -> Unit)? = null
  var onVideoCallRequested: (() -> Unit)? = null
  var onMoreRequested: (() -> Unit)? = null
  /** Called after UIKit selected a quote target, before the next text is sent. */
  var onQuoteRequested: ((PteIMMessage) -> Unit)? = null
  /** Server/business layer hook after UIKit has copied a text message. */
  var onMessageCopied: ((PteIMMessage) -> Unit)? = null
  /** Server/business layer hook after UIKit has removed the local timeline item. */
  var onMessageDeleted: ((PteIMMessage) -> Unit)? = null
  /** Server/business layer hook after UIKit has optimistically recalled a message locally. */
  var onMessageRevoked: ((PteIMMessage) -> Unit)? = null
  /** Called after a failed Core message is requeued, or an upload is restarted. */
  var onMessageRetryRequested: ((PteIMMessage) -> Unit)? = null
  /** Business/custom payload callback; UIKit owns no payment or order operation. */
  var onCustomMessageRequested: ((PteIMUICustomMessage) -> Unit)? = null
  var onMessageActionRequested: ((PteIMUIMessageAction, PteIMMessage) -> Unit)? = null
  /** Supplies server/business-owned reaction data without coupling Core to UI state. */
  var reactionProvider: ((PteIMMessage) -> List<PteIMUIReaction>)? = null
  /**
   * Invoked after UIKit applies the current user's local reaction toggle. The
   * host can persist this to its own service; [added] is false when a second
   * tap removes the current user's reaction.
   */
  var onReactionChanged: ((message: PteIMMessage, reaction: PteIMUIReaction, added: Boolean) -> Unit)? = null
  /** Supplies business/server receipt state for outgoing messages. */
  var receiptStatusProvider: ((PteIMMessage) -> PteIMUIReceiptStatus)? = null
  var navigationSubtitleText: String? = null
  protected val messages = LinearLayout(context).apply { orientation = VERTICAL }
  protected val scroll = ScrollView(context)
  protected val header = LinearLayout(context).apply { orientation = HORIZONTAL; gravity = Gravity.CENTER_VERTICAL; setPadding(dp(8), 0, dp(8), 0) }
  protected val inputBar = PteIMUIInputBar(context, resolvePalette())
  /** Visible composer state for the next quoted text message. */
  private val quotePreview = LinearLayout(context).apply {
    orientation = HORIZONTAL
    gravity = Gravity.CENTER_VERTICAL
    setPadding(dp(16), 0, dp(8), 0)
    visibility = GONE
  }
  private val quotePreviewText = TextView(context).apply {
    textSize = 11f
    includeFontPadding = false
    maxLines = 1
    gravity = Gravity.CENTER_VERTICAL
  }
  private val quotePreviewClose = ImageButton(context).apply {
    setImageResource(android.R.drawable.ic_menu_close_clear_cancel)
    setBackgroundColor(Color.TRANSPARENT)
    setPadding(dp(11), dp(11), dp(11), dp(11))
    contentDescription = "Cancel quote"
  }
  protected var palette = resolvePalette()
  private var activeMessageMenu: PopupWindow? = null
  private var quotedMessage: PteIMMessage? = null
  private var latestReadSequence: Long = 0L
  private val uploadRetrySources = mutableMapOf<String, Pair<PteIMUIAction, android.net.Uri>>()
  /** Survives a process restart for persistable document URIs and MediaStore sources. */
  private val uploadRetryStore = context.applicationContext.getSharedPreferences("pte_im_ui_upload_retry", Context.MODE_PRIVATE)
  /** Hosts may route default image/video previews to their own inheritable Activity subclass. */
  open var mediaPreviewActivityClass: Class<out Activity> = PteIMUIMediaPreviewActivity::class.java
  /** Hosts may route the default document hand-off to their own Activity subclass. */
  open var filePreviewActivityClass: Class<out Activity> = PteIMUIFilePreviewActivity::class.java
  /**
   * Only an optimistic current-user override lives in UIKit; aggregate counts
   * remain owned by [reactionProvider]. `true` means the user has reacted,
   * `false` means a server-side current-user reaction was removed locally.
   */
  private val localReactionOverrides = mutableMapOf<String, MutableMap<String, Boolean>>()
  private val listener = object : PteIMListener {
    override fun onMessage(message: PteIMMessage) { if (message.conversationId == conversationId) post { render() } }
    override fun onMessageStateChanged(clientMsgId: String, state: PteIMSendState) { post {
      if (state == PteIMSendState.SENT) clearUploadRetrySource(clientMsgId)
      render()
    } }
    override fun onThemeModeChanged(themeMode: PteIMThemeMode) { post { applyTheme() } }
    override fun onLanguageChanged(language: PteIMLanguage) { post { applyTheme() } }
  }

  init {
    orientation = VERTICAL
    buildHeader(title)
    addView(header, LayoutParams(-1, dp(44)))
    header.setOnClickListener { collapseTransientUi() }
    scroll.isFillViewport = true
    scroll.setOnTouchListener { _, event ->
      if (event.actionMasked == android.view.MotionEvent.ACTION_DOWN || event.actionMasked == android.view.MotionEvent.ACTION_MOVE) collapseTransientUi()
      false
    }
    scroll.addView(messages, ViewGroup.LayoutParams(-1, -2)); addView(scroll, LayoutParams(-1, 0, 1f))
    quotePreview.addView(quotePreviewText, LayoutParams(0, dp(40), 1f))
    quotePreview.addView(quotePreviewClose, LayoutParams(dp(40), dp(40)))
    quotePreviewClose.setOnClickListener { cancelQuote() }
    addView(quotePreview, LayoutParams(-1, dp(40)))
    addView(inputBar, LayoutParams(-1, -2))
    inputBar.onInteraction = { dismissMessageMenu() }
    inputBar.onSendText = { dismissMessageMenu(); sendText(it) }
    inputBar.onEmojiSelected = { packageId, emojiId -> dismissMessageMenu(); sendEmoji(packageId, emojiId) }
    inputBar.onActionSelected = { action ->
      dismissMessageMenu()
      when (action) {
        PteIMUIAction.IMAGE, PteIMUIAction.CAMERA, PteIMUIAction.VIDEO, PteIMUIAction.LOCATION, PteIMUIAction.FILE ->
          PteIMUIAttachmentBridge.launch(
            context, client, conversationId, action,
            onError = { error -> onAttachmentError?.invoke(error) },
            // COS upload completes on the bridge executor. Return to this
            // View's queue before touching the retry map or rebuilding rows.
            onQueued = { message, uri -> post {
              rememberUploadRetrySource(message.clientMsgId, action, uri)
              render()
            } },
          )
        PteIMUIAction.GIFT, PteIMUIAction.RED_PACKET, PteIMUIAction.ORDER -> onActionRequested?.invoke(action)
        PteIMUIAction.VOICE -> onActionRequested?.invoke(action)
      }
    }
    inputBar.onCustomActionSelected = { dismissMessageMenu(); onCustomInputActionRequested?.invoke(it) }
    inputBar.onVoiceRecordingChanged = { active -> dismissMessageMenu(); onVoiceRecordingChanged?.invoke(active) }
    inputBar.onVoiceRecordingCancelled = { onVoiceRecordingCancelled?.invoke() }
    client.addListener(listener); applyTheme(); render()
  }

  override fun onDetachedFromWindow() { dismissMessageMenu(); client.removeListener(listener); super.onDetachedFromWindow() }
  override fun onAttachedToWindow() { super.onAttachedToWindow(); client.addListener(listener); render() }
  fun setTheme(theme: PteIMUITheme) { uiTheme = theme; applyTheme() }
  /** Replaces only the four optional slots; UIKit retains its eight standard attachment/business actions. */
  fun setCustomInputActions(actions: List<PteIMUICustomInputAction>) { inputBar.setCustomActions(actions) }
  /** Replaces the common/all emoji groups. Emoji cells remain fixed at 44dp with 24×32 icon content. */
  fun setEmojiDataSource(source: PteIMUIEmojiDataSource) { inputBar.setEmojiDataSource(source) }
  open fun sendText(text: String) {
    text.trim().takeIf { it.isNotEmpty() }?.let { value ->
      client.sendText(conversationId, value, quotedMessage?.toQuote())
      quotedMessage = null
      refreshQuotePreview()
      inputBar.clearText()
      render()
    }
  }
  open fun sendEmoji(packageId: String, emojiId: String) { client.sendEmoji(conversationId, packageId, emojiId); render() }
  /** Sends supported business messages through Core; custom payloads are intentionally host-owned. */
  open fun sendCustomMessage(message: PteIMUICustomMessage) {
    when (message.kind) {
      PteIMUICustomMessage.Kind.GIFT -> client.sendGift(conversationId, message.content)
      PteIMUICustomMessage.Kind.RED_PACKET -> client.sendRedPacket(conversationId, message.content)
      PteIMUICustomMessage.Kind.ORDER -> client.sendOrder(conversationId, message.content)
      PteIMUICustomMessage.Kind.CUSTOM -> onCustomMessageRequested?.invoke(message)
    }
    render()
  }
  /** Clears a selected quote without changing the current draft. */
  open fun cancelQuote() { quotedMessage = null; refreshQuotePreview() }
  fun refresh() = render()

  open fun render() {
    dismissMessageMenu()
    messages.removeAllViews()
    messages.addView(dayDivider(), LayoutParams(-1, dp(44)))
    val timeline = client.localMessages(conversationId, limit = 100)
    timeline.forEach { messages.addView(messageView(it)) }
    markTimelineRead(timeline)
    scroll.post { scroll.fullScroll(View.FOCUS_DOWN) }
  }
  open fun messageView(message: PteIMMessage): View {
    val outgoing = message.senderId == client.currentUserId()
    val body = messageBody(message, outgoing)
    val bodyWidth = when (message.type) {
      PteIMMessageType.RED_PACKET, PteIMMessageType.GIFT -> dp(208)
      else -> if (isRich(message)) dp(220) else -2
    }
    val bodyHeight = when (message.type) {
      PteIMMessageType.RED_PACKET -> dp(186)
      PteIMMessageType.GIFT -> dp(182)
      else -> -2
    }
    val stack = LinearLayout(context).apply {
      orientation = VERTICAL; gravity = if (outgoing) Gravity.END else Gravity.START
      if (isGroupChat && !outgoing) {
        addView(TextView(context).apply {
          text = groupMemberNicknameProvider?.invoke(message)?.takeIf { it.isNotBlank() }
            ?: message.senderNickname?.takeIf { it.isNotBlank() }
            ?: message.senderId.orEmpty()
          textSize = 11f; includeFontPadding = false; setTextColor(palette.secondaryText); gravity = Gravity.START
        }, LayoutParams(-2, dp(18)).apply { bottomMargin = dp(2) })
      }
      message.quote?.let { quote ->
        addView(TextView(context).apply {
          text = "↪ ${quote.senderId?.takeIf(String::isNotBlank)?.plus(": ").orEmpty()}${quote.text}"
          textSize = 10f; includeFontPadding = false; maxLines = 1
          setTextColor(palette.secondaryText)
          setPadding(dp(10), dp(5), dp(10), dp(4))
          background = rounded(if (outgoing) Color.argb(42, 255, 255, 255) else palette.surface, palette.divider, 10)
        }, LayoutParams(bodyWidth, -2).apply { bottomMargin = dp(3) })
      }
      addView(body, LayoutParams(bodyWidth, bodyHeight))
      val reactions = reactionsFor(message)
      if (reactions.isNotEmpty()) addView(LinearLayout(context).apply {
        gravity = if (outgoing) Gravity.END else Gravity.START
        reactions.forEach { reaction ->
          addView(TextView(context).apply {
            text = if (reaction.count > 1) "${reaction.emoji}  ${reaction.count}" else reaction.emoji
            textSize = 11f; includeFontPadding = false; gravity = Gravity.CENTER
            setTextColor(palette.primaryText); setPadding(dp(9), dp(3), dp(9), dp(3))
            background = rounded(palette.surface, palette.divider, 12)
            setOnClickListener { toggleReaction(message, reaction.emoji) }
          }, LayoutParams(-2, dp(26)).apply { if (indexOfReaction(reactions, reaction) > 0) marginStart = dp(5) })
        }
      }, LayoutParams(-2, dp(30)).apply { topMargin = dp(4) })
      addView(deliveryView(message, outgoing), LayoutParams(-2, dp(18)))
      if (outgoing && message.state == PteIMSendState.FAILED) addView(TextView(context).apply {
        text = if (client.currentAppearance().language.isEnglish(context)) "Tap to retry" else "发送失败，点击重试"
        textSize = 10f; includeFontPadding = false; setTextColor(Color.rgb(239, 75, 82)); gravity = Gravity.END
        setPadding(0, dp(2), 0, dp(2)); setOnClickListener { retryMessage(message) }
      }, LayoutParams(-2, dp(20)))
      setOnLongClickListener { showMessageMenu(message, this); true }
    }
    return LinearLayout(context).apply {
      gravity = if (outgoing) Gravity.END else Gravity.START; setPadding(dp(12), dp(4), dp(12), dp(4))
      if (!outgoing) addView(messageAvatar(message.senderId?.take(1) ?: "A", false), LayoutParams(dp(28), dp(28)).apply { marginEnd = dp(8); topMargin = dp(2) })
      addView(stack)
      if (outgoing) addView(messageAvatar("M", true), LayoutParams(dp(28), dp(28)).apply { marginStart = dp(8); topMargin = dp(2) })
      // Rich cards have nested child views; bind the row too so long press
      // always reaches the same MessageKit-style action surface.
      setOnLongClickListener { showMessageMenu(message, this); true }
      setOnClickListener { collapseTransientUi() }
    }
  }
  open fun messageLabel(message: PteIMMessage): String = when (message.type) {
    PteIMMessageType.TEXT -> message.text.orEmpty(); PteIMMessageType.EMOJI -> message.emojiId.orEmpty(); PteIMMessageType.IMAGE -> "图片\nPhoto"; PteIMMessageType.VIDEO -> "视频\n${(message.media?.durationMs ?: 0) / 1000}s"; PteIMMessageType.VOICE -> "语音  ${(message.voice?.durationMs ?: 0) / 1000}s"; PteIMMessageType.LOCATION -> "位置\n${message.location?.name.orEmpty()}\n${message.location?.address.orEmpty()}"; PteIMMessageType.GIFT -> "礼物\n${message.business?.title.orEmpty()}\n${message.business?.subtitle.orEmpty()}"; PteIMMessageType.RED_PACKET -> "红包\n${message.business?.title.orEmpty()}\n${message.business?.subtitle.orEmpty()}"; PteIMMessageType.ORDER -> "订单\n${message.business?.title.orEmpty()}\n${message.business?.subtitle.orEmpty()}"; PteIMMessageType.FILE -> "文件\n${message.media?.fileName.orEmpty()}"
  }
  open fun applyTheme() {
    palette = resolvePalette(); setBackgroundColor(chatCanvas()); header.setBackgroundColor(palette.surface); header.findViewWithTag<TextView>("pte-title")?.setTextColor(palette.primaryText); header.findViewWithTag<TextView>("pte-subtitle")?.apply { text = navigationSubtitleText ?: if (client.currentAppearance().language.isEnglish(context)) "Online" else "在线"; setTextColor(Color.rgb(0, 192, 120)) }
    for (index in 0 until header.childCount) {
      (header.getChildAt(index) as? ImageButton)?.takeIf { it.tag == "pte-navigation-icon" }?.setColorFilter(navigationIconColor())
    }
    inputBar.applyPalette(palette)
    quotePreview.setBackgroundColor(palette.surface)
    quotePreviewText.setTextColor(palette.secondaryText)
    quotePreviewClose.setColorFilter(navigationIconColor())
    refreshQuotePreview()
    val english = client.currentAppearance().language.isEnglish(context)
    inputBar.setCopy(if (english) "Say something..." else "说点什么...", if (english) "Send" else "发送", if (english) "Hold to Record" else "按住录音")
    render()
  }
  protected fun resolvePalette(): PteIMUIThemePalette = when (client.currentAppearance().themeMode) { PteIMThemeMode.DARK -> uiTheme.dark; PteIMThemeMode.LIGHT -> uiTheme.light; PteIMThemeMode.SYSTEM -> if (systemTheme(context).name == "DARK") uiTheme.dark else uiTheme.light }
  protected fun isDark(): Boolean = client.currentAppearance().themeMode == PteIMThemeMode.DARK || (client.currentAppearance().themeMode == PteIMThemeMode.SYSTEM && systemTheme(context).name == "DARK")
  /** The supplied navigation artwork is white. Tint it for a real light-mode navigation surface. */
  protected fun navigationIconColor(): Int = if (isDark()) Color.rgb(242, 244, 255) else Color.rgb(25, 30, 54)
  protected fun chatCanvas(): Int = if (palette.background == PteIMUITheme.blueVioletDark().background) Color.rgb(8, 8, 31) else Color.rgb(243, 244, 255)
  protected fun rounded(fill: Int, stroke: Int, radius: Int) = GradientDrawable().apply { setColor(fill); setStroke(dp(1), stroke); cornerRadius = dp(radius).toFloat() }
  protected fun gradient(start: Int, end: Int, radius: Int) = GradientDrawable(GradientDrawable.Orientation.LEFT_RIGHT, intArrayOf(start, end)).apply { cornerRadius = dp(radius).toFloat() }
  /** Shared rich-card surface. Dark mode uses the 6/4/5% purple-to-cyan design gradient. */
  protected fun sharedCardGradient(radius: Int): GradientDrawable = GradientDrawable(
    GradientDrawable.Orientation.LEFT_RIGHT,
    if (isDark()) intArrayOf(
      Color.argb(15, 166, 132, 255),
      Color.argb(10, 173, 70, 255),
      Color.argb(13, 0, 211, 243),
    ) else intArrayOf(
      Color.argb(128, 29, 41, 61),
      Color.argb(128, 15, 23, 43),
      Color.argb(128, 0, 0, 0),
    ),
  ).apply { cornerRadius = dp(radius).toFloat() }
  protected fun isRich(message: PteIMMessage): Boolean = message.type in setOf(PteIMMessageType.IMAGE, PteIMMessageType.VIDEO, PteIMMessageType.LOCATION, PteIMMessageType.GIFT, PteIMMessageType.RED_PACKET, PteIMMessageType.ORDER, PteIMMessageType.FILE)
  protected fun messageBackground(message: PteIMMessage, outgoing: Boolean): GradientDrawable = when (message.type) {
    PteIMMessageType.RED_PACKET -> gradient(Color.rgb(214, 68, 45), Color.rgb(132, 33, 26), 18)
    PteIMMessageType.GIFT -> gradient(Color.rgb(121, 64, 239), Color.rgb(54, 30, 119), 18)
    PteIMMessageType.IMAGE, PteIMMessageType.VIDEO -> sharedCardGradient(18)
    PteIMMessageType.ORDER -> if (isDark()) sharedCardGradient(16) else rounded(Color.WHITE, Color.TRANSPARENT, 16)
    PteIMMessageType.VOICE -> if (outgoing) gradient(palette.outgoingStart, palette.outgoingEnd, 18) else if (isDark()) sharedCardGradient(18) else rounded(Color.WHITE, Color.TRANSPARENT, 18)
    else -> if (outgoing) gradient(palette.outgoingStart, palette.outgoingEnd, 18) else rounded(palette.incomingBubble, palette.incomingBubble, 18)
  }
  protected open fun receiptStatus(message: PteIMMessage): PteIMUIReceiptStatus = receiptStatusProvider?.invoke(message)
    ?: if (message.state == PteIMSendState.SENT) PteIMUIReceiptStatus.READ else PteIMUIReceiptStatus.UNREAD
  /** Timestamp plus supplied read/unread art; inbound cells intentionally show time only. */
  protected open fun deliveryView(message: PteIMMessage, outgoing: Boolean): View = LinearLayout(context).apply {
    gravity = if (outgoing) Gravity.END or Gravity.CENTER_VERTICAL else Gravity.START or Gravity.CENTER_VERTICAL
    addView(TextView(context).apply {
      text = java.text.SimpleDateFormat("HH:mm", java.util.Locale.getDefault()).format(java.util.Date(message.createdAt))
      textSize = 10f; includeFontPadding = false; setTextColor(if (outgoing) palette.outgoingEnd else palette.secondaryText)
    }, LayoutParams(-2, -2))
    if (outgoing) {
      val receipt = receiptStatus(message)
      if (receipt != PteIMUIReceiptStatus.HIDDEN) addView(ImageView(context).apply {
        setImageResource(if (receipt == PteIMUIReceiptStatus.READ) R.drawable.pte_im_ui_chat_receipt_read else R.drawable.pte_im_ui_chat_receipt_unread)
        scaleType = ImageView.ScaleType.FIT_CENTER
      }, LayoutParams(dp(13), dp(13)).apply { marginStart = dp(3) })
    }
  }
  /**
   * Navigation-bar extension point. Override this method to replace the
   * complete 44 dp navigation layout while retaining message loading, input
   * state, appearance updates and Core callbacks. The supplied [container] is
   * the same protected [header] instance used by [applyTheme].
   */
  protected open fun buildHeader(title: String) {
    header.removeAllViews()
    header.addView(iconButton(R.drawable.pte_im_ui_chat_back, "Back") { onBackRequested?.invoke() }, LayoutParams(dp(44), dp(44)))
    header.addView(TextView(context).apply { text = "#"; textSize = 18f; gravity = Gravity.CENTER; setTextColor(Color.WHITE); background = rounded(Color.rgb(10, 155, 188), Color.TRANSPARENT, 18) }, LayoutParams(dp(34), dp(34)).apply { marginStart = dp(2); marginEnd = dp(8) })
    header.addView(LinearLayout(context).apply {
      orientation = VERTICAL; gravity = Gravity.CENTER_VERTICAL
      addView(TextView(context).apply { text = title; textSize = 16f; typeface = Typeface.DEFAULT_BOLD; includeFontPadding = false; tag = "pte-title" }, LayoutParams(-1, dp(21)))
      addView(TextView(context).apply { textSize = 10f; includeFontPadding = false; tag = "pte-subtitle" }, LayoutParams(-1, dp(15)))
    }, LayoutParams(0, dp(44), 1f))
    header.addView(iconButton(R.drawable.pte_im_ui_chat_more, "More") { onMoreRequested?.invoke() }, LayoutParams(dp(44), dp(44)))
  }
  /** Adds a host-owned navigation item before the default trailing controls. */
  protected fun addNavigationExtension(view: View, widthDp: Int = 36) {
    header.addView(view, (header.childCount - 1).coerceAtLeast(0), LayoutParams(dp(widthDp), dp(44)))
  }
  /** 44 dp touch target with source artwork filling the entire navigation button. */
  protected open fun iconButton(resource: Int, description: String, clicked: () -> Unit): ImageButton = ImageButton(context).apply {
    setImageResource(resource)
    tag = "pte-navigation-icon"
    setColorFilter(navigationIconColor())
    contentDescription = description
    background = null
    scaleType = ImageView.ScaleType.FIT_XY
    setPadding(0, 0, 0, 0)
    setOnClickListener { clicked() }
  }
  /** Replace the date separator without reimplementing cache-to-list rendering. */
  protected open fun dayDivider(): View = LinearLayout(context).apply {
    gravity = Gravity.CENTER_VERTICAL
    addView(View(context).apply { setBackgroundColor(palette.divider) }, LayoutParams(0, dp(1), 1f).apply { marginStart = dp(16); marginEnd = dp(10) })
    addView(TextView(context).apply { text = if (client.currentAppearance().language.isEnglish(context)) "Today" else "今天"; textSize = 10f; includeFontPadding = false; setTextColor(palette.secondaryText) }, LayoutParams(-2, -2))
    addView(View(context).apply { setBackgroundColor(palette.divider) }, LayoutParams(0, dp(1), 1f).apply { marginStart = dp(10); marginEnd = dp(16) })
  }
  /** Override for remote-image avatars or profile click behaviour. */
  protected open fun messageAvatar(text: String, outgoing: Boolean): View = TextView(context).apply { this.text = text; textSize = 12f; typeface = Typeface.DEFAULT_BOLD; gravity = Gravity.CENTER; setTextColor(Color.WHITE); background = rounded(if (outgoing) palette.outgoingEnd else Color.rgb(134, 79, 241), Color.TRANSPARENT, 16) }
  /**
   * Per-message content-cell factory. This is the Android equivalent of a
   * MessageKit custom message cell: a subclass owns its custom View while
   * PteIMUIKit retains message ordering, delivery state and long-press routing.
   */
  protected open fun messageBody(message: PteIMMessage, outgoing: Boolean): View = when (message.type) {
    PteIMMessageType.RED_PACKET -> businessCard(message, R.drawable.pte_im_ui_chat_red_packet_background, Color.rgb(255, 225, 19), if (outgoing) "领取红包  →" else "★  已领取  ★", 186)
    PteIMMessageType.GIFT -> businessCard(message, R.drawable.pte_im_ui_chat_gift_background, Color.rgb(255, 222, 95), if (outgoing) "打开礼物  →" else "♥  已接收  ♥", 182)
    PteIMMessageType.VOICE -> voiceBubble(message, outgoing)
    PteIMMessageType.IMAGE -> imageCard(message)
    PteIMMessageType.VIDEO -> videoCard(message)
    PteIMMessageType.LOCATION -> locationCard(message)
    PteIMMessageType.FILE -> fileCard(message)
    PteIMMessageType.ORDER -> orderCard(message)
    else -> TextView(context).apply {
      this.text = messageLabel(message)
      textSize = if (message.type == PteIMMessageType.EMOJI) 30f else 15f
      setTextColor(if (outgoing) palette.outgoingText else palette.incomingText)
      setPadding(dp(15), dp(10), dp(15), dp(10))
      // Wrap long prose and repeated Emoji at the same maximum conversation
      // width as the supplied chat design instead of expanding across a row.
      maxWidth = maximumTextMessageWidth()
      setHorizontallyScrolling(false)
      background = messageBackground(message, outgoing)
      gravity = Gravity.START
    }
  }

  /**
   * Maximum rendered width for adaptive text/emoji bubbles. Hosts can
   * override this without replacing message layout or message send logic.
   */
  protected open fun maximumTextMessageWidth(): Int = dp(260)

  /** Merges host/server counts with this device's optimistic reaction toggle. */
  protected open fun reactionsFor(message: PteIMMessage): List<PteIMUIReaction> {
    val states = linkedMapOf<String, PteIMUIReaction>()
    reactionProvider?.invoke(message)
      ?.filter { it.emoji.isNotBlank() && it.count > 0 }
      ?.forEach { reaction ->
        val current = states[reaction.emoji]
        states[reaction.emoji] = PteIMUIReaction(
          emoji = reaction.emoji,
          count = (current?.count ?: 0) + reaction.count,
          reactedByCurrentUser = (current?.reactedByCurrentUser == true) || reaction.reactedByCurrentUser,
        )
      }
    localReactionOverrides[reactionMessageKey(message)]?.forEach { (emoji, desiredReaction) ->
      val current = states[emoji] ?: PteIMUIReaction(emoji, 0)
      if (current.reactedByCurrentUser != desiredReaction) {
        states[emoji] = current.copy(
          count = current.count + if (desiredReaction) 1 else -1,
          reactedByCurrentUser = desiredReaction,
        )
      }
    }
    return states.values.filter { it.count > 0 }
  }

  private fun indexOfReaction(reactions: List<PteIMUIReaction>, reaction: PteIMUIReaction) = reactions.indexOfFirst { it.emoji == reaction.emoji }

  /** A message-level reaction is a toggle for the current user, not a duplicate count. */
  private fun toggleReaction(message: PteIMMessage, emoji: String) {
    val currentlyReacted = reactionsFor(message).firstOrNull { it.emoji == emoji }?.reactedByCurrentUser == true
    val added = !currentlyReacted
    val serverReacted = reactionProvider?.invoke(message)
      ?.filter { it.emoji == emoji && it.count > 0 }
      ?.any { it.reactedByCurrentUser } == true
    val messageKey = reactionMessageKey(message)
    val overrides = localReactionOverrides.getOrPut(messageKey) { linkedMapOf() }
    if (added == serverReacted) overrides.remove(emoji) else overrides[emoji] = added
    if (overrides.isEmpty()) localReactionOverrides.remove(messageKey)
    val updated = reactionsFor(message).firstOrNull { it.emoji == emoji } ?: PteIMUIReaction(emoji, 0)
    onReactionChanged?.invoke(message, updated, added)
    onMessageActionRequested?.invoke(PteIMUIMessageAction.REACT, message)
    dismissMessageMenu()
    render()
  }

  /** Stable across cell redraws; server ID wins, with Core's client ID as the local fallback. */
  private fun reactionMessageKey(message: PteIMMessage): String =
    message.serverMsgId?.takeIf { it.isNotBlank() } ?: message.clientMsgId
  /** Image opens UIKit's native full-screen preview; the placeholder remains for unloaded media. */
  protected open fun imageCard(message: PteIMMessage): View = FrameLayout(context).apply {
    minimumHeight = dp(160)
    background = mediaCardBackground()
    addView(
      ImageView(context).apply {
        setImageResource(R.drawable.pte_im_ui_chat_message_image)
        scaleType = ImageView.ScaleType.FIT_CENTER
      },
      FrameLayout.LayoutParams(dp(48), dp(48), Gravity.CENTER)
    )
    setOnClickListener { PteIMUIMediaPreviewActivity.open(context, message, PteIMUIMediaPreviewActivity.Kind.IMAGE, mediaPreviewActivityClass) }
  }
  /** Video card opens UIKit's native player and uses the supplied duration glyphs. */
  protected open fun videoCard(message: PteIMMessage): View = FrameLayout(context).apply {
    minimumHeight = dp(160); background = mediaCardBackground()
    // Keep the hit target and the visual treatment independent: the supplied
    // play artwork is 20dp inside the 46dp translucent circular control.
    addView(FrameLayout(context).apply {
      background = rounded(Color.argb(26, 255, 255, 255), Color.argb(51, 255, 255, 255), 23)
      addView(ImageView(context).apply {
        setImageResource(R.drawable.pte_im_ui_chat_message_video_play)
        scaleType = ImageView.ScaleType.FIT_CENTER
      }, FrameLayout.LayoutParams(dp(20), dp(20), Gravity.CENTER))
    }, FrameLayout.LayoutParams(dp(46), dp(46), Gravity.CENTER))
    addView(LinearLayout(context).apply {
      gravity = Gravity.CENTER_VERTICAL
      setPadding(dp(6), 0, dp(7), 0)
      // Video duration uses the supplied white 10% overlay rather than a
      // dark opaque badge, including the 12dp duration glyph.
      background = rounded(Color.argb(26, 255, 255, 255), Color.TRANSPARENT, 7)
      addView(ImageView(context).apply { setImageResource(R.drawable.pte_im_ui_chat_message_video_duration); scaleType = ImageView.ScaleType.FIT_CENTER }, LayoutParams(dp(12), dp(12)))
      addView(TextView(context).apply {
        text = videoDurationLabel(message.media?.durationMs ?: 32_000)
        textSize = 10f; includeFontPadding = false; gravity = Gravity.CENTER_VERTICAL; setTextColor(Color.WHITE)
      }, LayoutParams(-2, dp(12)).apply { marginStart = dp(4) })
    }, FrameLayout.LayoutParams(-2, dp(24), Gravity.BOTTOM or Gravity.END).apply { rightMargin = dp(8); bottomMargin = dp(8) })
    setOnClickListener { PteIMUIMediaPreviewActivity.open(context, message, PteIMUIMediaPreviewActivity.Kind.VIDEO, mediaPreviewActivityClass) }
  }
  /** Formats all video durations as 00:00 so short clips do not use a `32s` suffix. */
  protected open fun videoDurationLabel(durationMs: Long): String {
    val totalSeconds = (durationMs.coerceAtLeast(0L) / 1_000L).toInt()
    return "%02d:%02d".format(totalSeconds / 60, totalSeconds % 60)
  }
  /** Image/video use the shared theme-aware three-stop background. */
  protected open fun mediaCardBackground(): GradientDrawable = sharedCardGradient(18)
  /**
   * Location is a map-thumbnail card. The built-in thumbnail preserves the
   * UIKit visual baseline; hosts can override this method with a map provider
   * while all taps still route through [PteIMUIMapNavigator].
   */
  protected open fun locationCard(message: PteIMMessage): View = LinearLayout(context).apply {
    orientation = VERTICAL
    background = rounded(palette.surface, Color.TRANSPARENT, 18)
    addView(FrameLayout(context).apply {
      background = rounded(palette.surface, Color.TRANSPARENT, 18)
      clipToOutline = true
      addView(ImageView(context).apply {
        setImageResource(R.drawable.pte_im_ui_chat_location_map_preview)
        scaleType = ImageView.ScaleType.CENTER_CROP
        contentDescription = message.location?.name.orEmpty()
      }, FrameLayout.LayoutParams(-1, -1))
    }, LayoutParams(-1, dp(104)))
    addView(LinearLayout(context).apply {
      orientation = VERTICAL; setPadding(dp(12), dp(8), dp(12), dp(9))
      addView(TextView(context).apply { text = message.location?.name.orEmpty(); textSize = 12f; typeface = Typeface.DEFAULT_BOLD; maxLines = 1; setTextColor(palette.primaryText) })
      addView(TextView(context).apply { text = message.location?.address.orEmpty(); textSize = 10f; maxLines = 1; setTextColor(palette.secondaryText); setPadding(0, dp(3), 0, 0) })
    }, LayoutParams(-1, dp(53)))
    isClickable = true
    isFocusable = true
    setOnClickListener {
      message.location?.let { location ->
        PteIMUIMapNavigator.open(context, location)
      }
    }
  }
  protected open fun fileCard(message: PteIMMessage): View = LinearLayout(context).apply {
    gravity = Gravity.CENTER_VERTICAL; setPadding(dp(13), dp(12), dp(13), dp(12)); background = rounded(palette.surface, palette.divider, 16)
    addView(ImageView(context).apply {
      setImageResource(R.drawable.pte_im_ui_chat_action_file)
      scaleType = ImageView.ScaleType.FIT_CENTER
      contentDescription = if (client.currentAppearance().language.isEnglish(context)) "File" else "文件"
    }, LayoutParams(dp(42), dp(42)))
    addView(LinearLayout(context).apply { orientation = VERTICAL; setPadding(dp(10), 0, 0, 0)
      addView(TextView(context).apply { text = message.media?.fileName ?: "Project brief.pdf"; textSize = 13f; maxLines = 1; setTextColor(palette.primaryText) })
      addView(TextView(context).apply { text = "PDF · 2.4 MB"; textSize = 10f; setTextColor(palette.secondaryText); setPadding(0, dp(4), 0, 0) })
    }, LayoutParams(0, -2, 1f))
    isClickable = true
    isFocusable = true
    setOnClickListener { PteIMUIFilePreviewActivity.open(context, message, filePreviewActivityClass) }
  }
  protected open fun orderCard(message: PteIMMessage): View = LinearLayout(context).apply {
    orientation = VERTICAL; background = if (isDark()) sharedCardGradient(16) else rounded(Color.WHITE, Color.TRANSPARENT, 16)
    addView(LinearLayout(context).apply { gravity = Gravity.CENTER_VERTICAL; setPadding(dp(12), dp(12), dp(12), dp(10))
      addView(ImageView(context).apply { setImageResource(R.drawable.pte_im_ui_chat_message_order); scaleType = ImageView.ScaleType.FIT_CENTER; background = rounded(if (isDark()) Color.rgb(38, 50, 82) else Color.rgb(225, 232, 246), Color.TRANSPARENT, 10) }, LayoutParams(dp(44), dp(44)))
      addView(LinearLayout(context).apply { orientation = VERTICAL; setPadding(dp(10), 0, 0, 0)
        addView(TextView(context).apply { text = message.business?.title ?: "iPhone 15 Pro 256GB 深空黑"; textSize = 12f; maxLines = 2; setTextColor(palette.primaryText) })
        addView(TextView(context).apply { text = message.business?.subtitle ?: "¥8,999"; textSize = 15f; typeface = Typeface.DEFAULT_BOLD; setTextColor(Color.rgb(245, 64, 64)); setPadding(0, dp(4), 0, 0) })
      }, LayoutParams(0, -2, 1f))
    }, LayoutParams(-1, dp(84)))
    addView(LinearLayout(context).apply { gravity = Gravity.CENTER_VERTICAL; setPadding(dp(12), 0, dp(12), 0); background = rounded(Color.TRANSPARENT, Color.TRANSPARENT, 0)
      addView(TextView(context).apply { text = if (client.currentAppearance().language.isEnglish(context)) "Order" else "订单"; textSize = 10f; setTextColor(palette.secondaryText) }, LayoutParams(0, dp(34), 1f))
      addView(TextView(context).apply { text = if (client.currentAppearance().language.isEnglish(context)) "View Order →" else "查看订单 →"; textSize = 10f; typeface = Typeface.DEFAULT_BOLD; setTextColor(palette.outgoingEnd) }, LayoutParams(-2, dp(34)))
    }, LayoutParams(-1, dp(34)))
  }
  protected open fun voiceBubble(message: PteIMMessage, outgoing: Boolean): View = LinearLayout(context).apply {
    val dark = isDark()
    val icon = when {
      dark && outgoing -> R.drawable.pte_im_ui_voice_outgoing_dark_icon
      dark -> R.drawable.pte_im_ui_voice_incoming_dark_icon
      outgoing -> R.drawable.pte_im_ui_voice_outgoing_light_icon
      else -> R.drawable.pte_im_ui_voice_incoming_light_icon
    }
    val waveform = when {
      dark && outgoing -> R.drawable.pte_im_ui_voice_outgoing_dark_wave
      dark -> R.drawable.pte_im_ui_voice_incoming_dark_wave
      outgoing -> R.drawable.pte_im_ui_voice_outgoing_light_wave
      else -> R.drawable.pte_im_ui_voice_incoming_light_wave
    }
    // Fixed voice-cell geometry: 173×44, 16dp leading icon, then a 78×20
    // waveform with 12dp space on both sides.
    gravity = Gravity.CENTER_VERTICAL
    minimumWidth = dp(173)
    minimumHeight = dp(44)
    setPadding(dp(16), 0, dp(16), 0)
    background = messageBackground(message, outgoing)
    addView(ImageView(context).apply { setImageResource(icon); scaleType = ImageView.ScaleType.FIT_CENTER }, LayoutParams(dp(16), dp(16)))
    addView(ImageView(context).apply { setImageResource(waveform); scaleType = ImageView.ScaleType.FIT_CENTER }, LayoutParams(dp(78), dp(20)).apply { marginStart = dp(12); marginEnd = dp(12) })
    addView(TextView(context).apply { text = "${(message.voice?.durationMs ?: 0) / 1000}s"; textSize = 12f; gravity = Gravity.CENTER_VERTICAL; includeFontPadding = false; setTextColor(if (outgoing) Color.WHITE else palette.secondaryText) }, LayoutParams(-2, dp(20)))
  }
  protected open fun businessCard(message: PteIMMessage, resource: Int, accent: Int, action: String, heightDp: Int): View = FrameLayout(context).apply {
    minimumHeight = dp(heightDp)
    background = context.getDrawable(resource)
    // The supplied background already contains the upper artwork and divider.
    // Anchor copy to that artwork rather than stacking it in a wrap-content
    // column: this preserves both source card heights and prevents the lower
    // CTA from drifting or being clipped on either direction.
    addView(TextView(context).apply {
      text = message.business?.title ?: "Alice"; textSize = 15f; typeface = Typeface.DEFAULT_BOLD; includeFontPadding = false; setTextColor(accent); gravity = Gravity.CENTER
    }, FrameLayout.LayoutParams(-1, dp(20), Gravity.TOP).apply { topMargin = dp(88) })
    addView(TextView(context).apply {
      text = message.business?.subtitle ?: "恭喜发财，大吉大利"; textSize = 11f; includeFontPadding = false; setTextColor(Color.WHITE); gravity = Gravity.CENTER; maxLines = 1
    }, FrameLayout.LayoutParams(-1, dp(18), Gravity.TOP).apply { topMargin = dp(111) })
    addView(TextView(context).apply {
      text = action; textSize = 13f; typeface = Typeface.DEFAULT_BOLD; includeFontPadding = false; setTextColor(accent); gravity = Gravity.CENTER
    }, FrameLayout.LayoutParams(-1, dp(32), Gravity.TOP).apply { topMargin = dp(143) })
  }
  /** Replace the default reactions/action menu with a business-owned surface. */
  protected open fun showMessageMenu(message: PteIMMessage, anchor: View) {
    collapseTransientUi()
    val english = client.currentAppearance().language.isEnglish(context)
    val dark = isDark()
    val surfaceColor = if (dark) Color.rgb(20, 26, 43) else Color.WHITE
    val menuStroke = if (dark) Color.rgb(47, 57, 86) else Color.rgb(232, 228, 248)
    val popupContent = LinearLayout(context).apply {
      orientation = VERTICAL
      setPadding(0, 0, 0, 0)
    }
    val popup = PopupWindow(popupContent, dp(296), -2, true).apply {
      isOutsideTouchable = true
      elevation = dp(10).toFloat()
      setBackgroundDrawable(ColorDrawable(Color.TRANSPARENT))
    }

    // Design: reaction and action controls are two independent floating cards.
    val reactionsCard = LinearLayout(context).apply {
      gravity = Gravity.CENTER_VERTICAL
      setPadding(dp(8), 0, dp(8), 0)
      background = rounded(surfaceColor, menuStroke, 16)
      listOf("👍", "❤️", "😂", "😮", "😢", "🙏").forEach { reaction ->
        addView(TextView(context).apply {
          text = reaction; textSize = 24f; includeFontPadding = false; gravity = Gravity.CENTER
          setShadowLayer(dp(2).toFloat(), 0f, 0f, Color.argb(72, 255, 255, 255))
          setOnClickListener { toggleReaction(message, reaction) }
        }, LayoutParams(0, dp(48), 1f))
      }
      addView(View(context).apply { setBackgroundColor(menuStroke) }, LayoutParams(dp(1), dp(26)).apply { marginStart = dp(2); marginEnd = dp(4) })
      addView(TextView(context).apply {
        text = "+"; textSize = 24f; gravity = Gravity.CENTER; setTextColor(palette.secondaryText)
        // This is a composer transition, not a reaction. The popup must be
        // gone before the emoji keyboard can be measured against the window.
        setOnClickListener { popup.dismiss(); inputBar.showEmojiPanel() }
      }, LayoutParams(dp(30), dp(48)))
    }
    popupContent.addView(reactionsCard, LayoutParams(-1, dp(48)))
    popupContent.addView(View(context), LayoutParams(-1, dp(8)))

    val actions = buildList {
      add(Triple(PteIMUIMessageAction.QUOTE, if (english) "Quote" else "引用", if (dark) R.drawable.pte_im_ui_chat_menu_quote_dark else R.drawable.pte_im_ui_chat_menu_quote_light))
      if (message.type == PteIMMessageType.TEXT) {
        add(Triple(PteIMUIMessageAction.COPY, if (english) "Copy" else "复制", if (dark) R.drawable.pte_im_ui_chat_menu_copy_dark else R.drawable.pte_im_ui_chat_menu_copy_light))
      }
      if (message.senderId == client.currentUserId()) {
        add(Triple(PteIMUIMessageAction.REVOKE, if (english) "Revoke" else "撤回", if (dark) R.drawable.pte_im_ui_chat_menu_revoke_dark else R.drawable.pte_im_ui_chat_menu_revoke_light))
        add(Triple(PteIMUIMessageAction.DELETE, if (english) "Delete" else "删除", if (dark) R.drawable.pte_im_ui_chat_menu_delete_dark else R.drawable.pte_im_ui_chat_menu_delete_light))
      }
    }
    val actionsCard = LinearLayout(context).apply {
      gravity = Gravity.CENTER_VERTICAL
      background = rounded(surfaceColor, menuStroke, 16)
      actions.forEachIndexed { index, (action, label, icon) ->
        if (index > 0) addView(View(context).apply { setBackgroundColor(menuStroke) }, LayoutParams(dp(1), dp(28)))
        addView(LinearLayout(context).apply {
          gravity = Gravity.CENTER; orientation = LinearLayout.HORIZONTAL; isClickable = true; isFocusable = true
          addView(ImageView(context).apply { setImageResource(icon); scaleType = ImageView.ScaleType.FIT_CENTER }, LayoutParams(dp(16), dp(16)))
          addView(TextView(context).apply {
            text = label; textSize = 11f; maxLines = 1; includeFontPadding = false; gravity = Gravity.CENTER_VERTICAL
            setTextColor(if (action == PteIMUIMessageAction.DELETE) Color.rgb(238, 75, 82) else palette.primaryText)
            setPadding(dp(5), 0, 0, 0)
          }, LayoutParams(-2, dp(36)))
          setOnClickListener { popup.dismiss(); performMessageAction(action, message) }
        }, LayoutParams(0, dp(48), 1f))
      }
    }
    popupContent.addView(actionsCard, LayoutParams(-1, dp(48)))
    popupContent.measure(
      View.MeasureSpec.makeMeasureSpec(dp(296), View.MeasureSpec.EXACTLY),
      View.MeasureSpec.makeMeasureSpec(0, View.MeasureSpec.UNSPECIFIED),
    )
    val popupHeight = popupContent.measuredHeight
    val frame = android.graphics.Rect().also { rootView.getWindowVisibleDisplayFrame(it) }
    val location = IntArray(2).also { anchor.getLocationInWindow(it) }
    val popupWidth = dp(296)
    val x = (location[0] + anchor.width / 2 - popupWidth / 2).coerceIn(frame.left + dp(8), frame.right - popupWidth - dp(8))
    val above = location[1] - popupHeight - dp(8)
    val y = if (above >= frame.top + dp(8)) above else (location[1] + anchor.height + dp(8)).coerceAtMost(frame.bottom - popupHeight - dp(8))
    activeMessageMenu = popup
    popup.setOnDismissListener { if (activeMessageMenu === popup) activeMessageMenu = null }
    popup.showAtLocation(rootView, Gravity.TOP or Gravity.START, x, y)
  }
  /**
   * Executes the UIKit-owned half of a long-press action before notifying the
   * embedding app. Recall/delete server endpoints stay host-controlled so an
   * app can apply its own permission/audit policy without UIKit inventing one.
   */
  open fun performMessageAction(action: PteIMUIMessageAction, message: PteIMMessage) {
    when (action) {
      PteIMUIMessageAction.REACT -> Unit
      PteIMUIMessageAction.QUOTE -> {
        quotedMessage = message
        refreshQuotePreview()
        inputBar.focusTextInput()
        onQuoteRequested?.invoke(message)
        PteIMUINotice.info(context, if (client.currentAppearance().language.isEnglish(context)) "Quoting message" else "已引用消息")
      }
      PteIMUIMessageAction.COPY -> {
        val clipboard = context.getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
        clipboard.setPrimaryClip(ClipData.newPlainText("PteIM message", messageCopyText(message)))
        onMessageCopied?.invoke(message)
        PteIMUINotice.success(context, if (client.currentAppearance().language.isEnglish(context)) "Copied" else "已复制")
      }
      PteIMUIMessageAction.DELETE -> {
        client.deleteLocalMessage(message)
        clearUploadRetrySource(message.clientMsgId)
        onMessageDeleted?.invoke(message)
        render()
      }
      PteIMUIMessageAction.REVOKE -> {
        // The current realtime protocol does not accept a recall envelope.
        // Hide instantly, then let the host call its authorised recall API.
        client.deleteLocalMessage(message)
        clearUploadRetrySource(message.clientMsgId)
        onMessageRevoked?.invoke(message)
        render()
      }
    }
    onMessageActionRequested?.invoke(action, message)
  }

  /** Retries a failed upload from its retained content URI, otherwise requeues Core's durable outbox row. */
  open fun retryMessage(message: PteIMMessage) {
    val source = uploadRetrySources.remove(message.clientMsgId) ?: persistedUploadRetrySource(message.clientMsgId)
    if (source != null) {
      clearUploadRetrySource(message.clientMsgId)
      client.deleteLocalMessage(message)
      val (action, uri) = source
      // The private picker is deliberately not re-opened for a known URI.
      // Invoke the same Core upload path directly so retry is one tap.
      val queued = when (action) {
        PteIMUIAction.IMAGE, PteIMUIAction.CAMERA -> client.uploadAndSendImage(conversationId, uri)
        PteIMUIAction.VIDEO -> client.uploadAndSendVideo(conversationId, uri)
        PteIMUIAction.FILE -> client.uploadAndSendFile(conversationId, uri)
        else -> return
      }
      rememberUploadRetrySource(queued.clientMsgId, action, uri)
      onMessageRetryRequested?.invoke(queued)
      render()
      return
    }
    client.retryMessage(message)?.let {
      onMessageRetryRequested?.invoke(it)
      render()
    } ?: PteIMUINotice.error(context, if (client.currentAppearance().language.isEnglish(context)) "Message cannot be retried" else "消息无法重试")
  }

  protected open fun messageCopyText(message: PteIMMessage): String = when (message.type) {
    PteIMMessageType.TEXT -> message.text.orEmpty()
    PteIMMessageType.EMOJI -> message.emojiId.orEmpty()
    PteIMMessageType.LOCATION -> listOf(message.location?.name, message.location?.address).filterNotNull().joinToString("\n")
    PteIMMessageType.FILE -> message.media?.url ?: message.media?.fileName.orEmpty()
    PteIMMessageType.IMAGE, PteIMMessageType.VIDEO -> message.media?.url.orEmpty()
    else -> message.business?.actionUrl ?: message.business?.title.orEmpty()
  }

  private fun markTimelineRead(timeline: List<PteIMMessage>) {
    val newestIncoming = timeline.filter { it.senderId != client.currentUserId() }.maxByOrNull { it.serverSeq ?: 0L } ?: return
    val sequence = newestIncoming.serverSeq ?: return
    val remoteConversationId = conversationId.toLongOrNull() ?: return
    if (sequence <= latestReadSequence) return
    latestReadSequence = sequence
    client.markConversationRead(remoteConversationId, sequence) { }
  }

  private fun PteIMMessage.toQuote(): PteIMQuote = PteIMQuote(
    clientMsgId = clientMsgId,
    serverMsgId = serverMsgId,
    senderId = senderId,
    text = messageCopyText(this).take(180),
  )

  private fun rememberUploadRetrySource(clientMsgId: String, action: PteIMUIAction, uri: android.net.Uri) {
    uploadRetrySources[clientMsgId] = action to uri
    uploadRetryStore.edit()
      .putString("$clientMsgId.action", action.name)
      .putString("$clientMsgId.uri", uri.toString())
      .apply()
  }

  private fun persistedUploadRetrySource(clientMsgId: String): Pair<PteIMUIAction, android.net.Uri>? {
    val action = uploadRetryStore.getString("$clientMsgId.action", null)
      ?.let { runCatching { PteIMUIAction.valueOf(it) }.getOrNull() }
      ?: return null
    val uri = uploadRetryStore.getString("$clientMsgId.uri", null)
      ?.let(android.net.Uri::parse)
      ?: return null
    return action to uri
  }

  private fun clearUploadRetrySource(clientMsgId: String) {
    uploadRetrySources.remove(clientMsgId)
    uploadRetryStore.edit()
      .remove("$clientMsgId.action")
      .remove("$clientMsgId.uri")
      .apply()
  }

  /** Keeps quote metadata explicit and cancellable before it is sent. */
  private fun refreshQuotePreview() {
    val message = quotedMessage
    quotePreview.visibility = if (message == null) GONE else VISIBLE
    if (message != null) {
      val sender = message.senderNickname?.takeIf { it.isNotBlank() } ?: message.senderId.orEmpty()
      quotePreviewText.text = "↪ ${if (sender.isBlank()) "" else "$sender: "}${messageCopyText(message).take(120)}"
    }
  }

  private fun dismissMessageMenu() { activeMessageMenu?.dismiss(); activeMessageMenu = null }
  /** Any non-composer gesture returns chat to its resting state. */
  private fun collapseTransientUi() { dismissMessageMenu(); inputBar.closeTransientInput() }
  protected fun dp(value: Int) = (value * resources.displayMetrics.density).toInt()
}

/**
 * Cache-first conversation list with fixed navigation/search chrome.
 *
 * Only the rows participate in pull-to-refresh and vertical scrolling. Hosts may
 * replace [conversationHeader], [conversationRow] or [onPullToRefresh] without
 * duplicating the SDK's encrypted-cache and cursor-sync behaviour.
 */
open class PteIMUIConversationListView(context: Context, protected val client: PteIMSDK, protected val onConversationClick: (String) -> Unit, var uiTheme: PteIMUITheme = PteIMUITheme()) : LinearLayout(context) {
  /** Protected list container for subclasses that need to append host-only rows. */
  protected val content = LinearLayout(context).apply { orientation = LinearLayout.VERTICAL }
  /** The fixed navigation/search chrome is outside this protected scroll view. */
  protected val listScroll = ScrollView(context).apply { isFillViewport = true; addView(content, LayoutParams(-1, -2)) }
  private val refreshIndicator = ProgressBar(context).apply { visibility = View.GONE }
  private val listContainer = FrameLayout(context).apply {
    addView(listScroll, FrameLayout.LayoutParams(-1, -1))
    addView(refreshIndicator, FrameLayout.LayoutParams(dp(28), dp(28), Gravity.TOP or Gravity.CENTER_HORIZONTAL).apply { topMargin = dp(6) })
  }
  private val searchField = EditText(context)
  private var query = ""
  private var searchListenerAttached = false
  private var refreshingFromPull = false
  private var pullStartY = 0f
  private var canPullRefresh = false
  private var headerView: View? = null
  private var searchView: View? = null
  /** Lets an application attach its own create-conversation route. */
  var onCreateConversation: (() -> Unit)? = null
  /** Optional host refresh route. Defaults to the SDK's cursor-based server sync. */
  var onPullToRefresh: (() -> Unit)? = null
  /** Allows a branded host to replace names, previews, avatar text and unread examples. */
  var presentationTransformer: ((PteIMUIConversationPresentation, Int) -> PteIMUIConversationPresentation)? = null
  /** Optional host display cap; Core pagination and cache remain untouched. */
  var maxVisibleConversations: Int? = null
  /** Receives the avatar tap without preventing the row's normal C2C/group route. */
  var onAvatarTapped: ((PteIMUIConversationPresentation) -> Unit)? = null
  private val listener = object : PteIMListener {
    override fun onMessage(message: PteIMMessage) { post { refresh() } }
    override fun onMessageStateChanged(clientMsgId: String, state: PteIMSendState) { post { refresh() } }
    override fun onConversationsChanged() { post { refresh(); finishPullRefresh() } }
    override fun onThemeModeChanged(themeMode: PteIMThemeMode) { post { applyTheme() } }
    override fun onLanguageChanged(language: PteIMLanguage) { post { applyTheme() } }
    override fun onError(error: Throwable) { post { finishPullRefresh() } }
  }
  init {
    orientation = VERTICAL
    listScroll.setOnTouchListener { _, event ->
      when (event.actionMasked) {
        android.view.MotionEvent.ACTION_DOWN -> {
          pullStartY = event.rawY
          canPullRefresh = listScroll.scrollY == 0 && !refreshingFromPull
        }
        android.view.MotionEvent.ACTION_MOVE -> if (canPullRefresh) {
          val distance = event.rawY - pullStartY
          if (distance > 0f) {
            val offset = min(dp(52).toFloat(), distance * 0.34f)
            listScroll.translationY = offset
            refreshIndicator.visibility = View.VISIBLE
            refreshIndicator.alpha = (offset / dp(36).toFloat()).coerceIn(0.35f, 1f)
          }
        }
        android.view.MotionEvent.ACTION_UP, android.view.MotionEvent.ACTION_CANCEL -> if (canPullRefresh) {
          if (listScroll.translationY >= dp(36)) requestPullRefresh() else resetPullOffset()
          canPullRefresh = false
        }
      }
      false
    }
    addView(listContainer, LayoutParams(-1, 0, 1f))
    client.addListener(listener)
    applyTheme()
  }
  override fun onDetachedFromWindow() { client.removeListener(listener); super.onDetachedFromWindow() }
  override fun onAttachedToWindow() { super.onAttachedToWindow(); client.addListener(listener); applyTheme() }
  fun setTheme(theme: PteIMUITheme) { uiTheme = theme; applyTheme() }
  open fun applyTheme() {
    val palette = resolvePalette()
    setBackgroundColor(palette.background)
    listScroll.setBackgroundColor(palette.background)
    refreshIndicator.indeterminateDrawable?.setTint(palette.outgoingEnd)
    headerView?.let(::removeView)
    searchView?.let(::removeView)
    headerView = conversationHeader().also { addView(it, 0, LayoutParams(-1, dp(44))) }
    searchView = searchBar().also { addView(it, 1, LayoutParams(-1, dp(62))) }
    refresh()
  }
  /** Begins a fixed-chrome pull refresh programmatically. */
  open fun requestPullRefresh() {
    if (refreshingFromPull) return
    refreshingFromPull = true
    refreshIndicator.visibility = View.VISIBLE
    refreshIndicator.alpha = 1f
    listScroll.animate().translationY(dp(36).toFloat()).setDuration(120).start()
    val route = onPullToRefresh
    if (route != null) route() else client.syncConversationsNow()
  }
  /** Completes a host-owned pull refresh when its custom route has finished. */
  open fun finishPullRefresh() {
    if (!refreshingFromPull && refreshIndicator.visibility != View.VISIBLE) return
    refreshingFromPull = false
    resetPullOffset()
  }
  private fun resetPullOffset() {
    listScroll.animate().translationY(0f).setDuration(160).start()
    refreshIndicator.postDelayed({ if (!refreshingFromPull) refreshIndicator.visibility = View.GONE }, 160)
  }
  open fun refresh() {
    content.removeAllViews()
    val remote = client.localRemoteConversations()
    val remoteById = remote.associateBy { it.id.toString() }
    val local = client.localConversations()
    val presentations = mutableListOf<PteIMUIConversationPresentation>()
    local.forEach { item ->
      val remoteItem = remoteById[item.conversationId]
      presentations += presentation(item.conversationId, previewFor(item.lastMessage), item.updatedAt, remoteItem)
    }
    val localIds = local.mapTo(linkedSetOf()) { it.conversationId }
    remote
      .filter { it.id.toString() !in localIds }
      .forEach { item ->
        val preview = item.lastMessageSnapshot?.takeIf { it.isNotBlank() }
          ?: if (item.type.equals("group", ignoreCase = true)) "[群聊] Group conversation" else "Start a conversation"
        presentations += presentation(item.id.toString(), preview, item.lastMessageAt, item)
      }
    presentations
      .mapIndexed { index, item -> presentationTransformer?.invoke(item, index) ?: item }
      .filter { item -> query.isBlank() || item.title.contains(query, ignoreCase = true) || item.preview.contains(query, ignoreCase = true) }
      .let { items -> maxVisibleConversations?.let(items::take) ?: items }
      .forEach { item -> content.addView(createConversationCell(item), LayoutParams(-1, -2)) }
  }
  /**
   * Primary cell factory for inherited list views. Override this for a wholly
   * custom layout, or override [conversationRow] to retain the compatibility
   * name used by earlier PteIMUIKit integrations.
   */
  open fun createConversationCell(item: PteIMUIConversationPresentation): View = conversationRow(item)
  /** Replace this to provide remote avatars, fonts, unread badges or a bespoke cell. */
  open fun conversationRow(item: PteIMUIConversationPresentation): View {
    val palette = resolvePalette()
    val body = LinearLayout(context).apply {
      gravity = Gravity.CENTER_VERTICAL
      setPadding(dp(20), dp(9), dp(20), dp(8))
      setBackgroundColor(palette.background)
      val avatar = FrameLayout(context)
      avatar.addView(TextView(context).apply {
        text = item.avatarText.take(1).uppercase(); gravity = Gravity.CENTER; textSize = 15f; typeface = Typeface.DEFAULT_BOLD; setTextColor(Color.WHITE)
        background = circle(item.avatarColor ?: avatarColor(item.conversationId))
      }, FrameLayout.LayoutParams(dp(44), dp(44)))
      if (item.isOnline) avatar.addView(View(context).apply { background = circle(Color.rgb(25, 205, 91)) }, FrameLayout.LayoutParams(dp(10), dp(10), Gravity.BOTTOM or Gravity.END).apply { rightMargin = dp(1); bottomMargin = dp(1) })
      avatar.setOnClickListener { onAvatarTapped?.invoke(item) }
      addView(avatar, LinearLayout.LayoutParams(dp(44), dp(44)))
      addView(LinearLayout(context).apply {
        orientation = LinearLayout.VERTICAL; gravity = Gravity.CENTER_VERTICAL; setPadding(dp(12), 0, dp(8), 0)
        addView(TextView(context).apply { text = item.title; maxLines = 1; textSize = 15f; typeface = Typeface.DEFAULT_BOLD; includeFontPadding = false; setTextColor(palette.primaryText) })
        addView(TextView(context).apply { text = item.preview; maxLines = 1; textSize = 12f; includeFontPadding = false; setTextColor(palette.secondaryText); setPadding(0, dp(5), 0, 0) })
      }, LinearLayout.LayoutParams(0, dp(48), 1f))
      addView(LinearLayout(context).apply {
        orientation = LinearLayout.VERTICAL; gravity = Gravity.END or Gravity.CENTER_VERTICAL
        addView(TextView(context).apply { text = item.timeText; textSize = 10f; includeFontPadding = false; gravity = Gravity.END; setTextColor(palette.secondaryText) }, LinearLayout.LayoutParams(dp(32), -2))
        if (item.unreadCount > 0) addView(TextView(context).apply {
          text = if (item.unreadCount > 99) "99+" else item.unreadCount.toString(); textSize = 10f; gravity = Gravity.CENTER; includeFontPadding = false; setTextColor(Color.WHITE)
          background = circle(Color.rgb(239, 49, 59))
        }, LinearLayout.LayoutParams(dp(18), dp(18)).apply { gravity = Gravity.END; topMargin = dp(6) })
      }, LinearLayout.LayoutParams(dp(36), dp(48)))
      setOnClickListener { selectConversation(item) }
    }
    return LinearLayout(context).apply {
      orientation = LinearLayout.VERTICAL; setBackgroundColor(palette.background)
      addView(body, LayoutParams(-1, dp(70)))
      addView(View(context).apply { setBackgroundColor(palette.divider) }, LayoutParams(-1, dp(1)).apply { leftMargin = dp(76) })
    }
  }
  /** Override to intercept a row route while Core's local paging remains intact. */
  open fun selectConversation(item: PteIMUIConversationPresentation) = onConversationClick(item.conversationId)
  /** Override to replace the full header while retaining cache, search and click handling. */
  open fun conversationHeader(): View {
    val palette = resolvePalette()
    return LinearLayout(context).apply {
      orientation = LinearLayout.HORIZONTAL; gravity = Gravity.CENTER_VERTICAL; setPadding(dp(20), 0, dp(15), 0); setBackgroundColor(palette.surface)
      addView(ImageView(context).apply { setImageResource(R.drawable.pte_im_ui_conversation_logo); scaleType = ImageView.ScaleType.FIT_CENTER }, LinearLayout.LayoutParams(dp(28), dp(28)))
      addView(TextView(context).apply { text = if (client.currentAppearance().language.isEnglish(context)) "Chats" else "会话"; textSize = 18f; typeface = Typeface.DEFAULT_BOLD; includeFontPadding = false; gravity = Gravity.CENTER_VERTICAL; setTextColor(palette.primaryText); setPadding(dp(9), 0, 0, 0) }, LinearLayout.LayoutParams(0, -1, 1f))
      addView(actionButton(if (isDark()) R.drawable.pte_im_ui_conversation_create_dark else R.drawable.pte_im_ui_conversation_create_light, "New conversation") { onCreateConversation?.invoke() }, LinearLayout.LayoutParams(dp(32), dp(32)))
    }
  }
  open fun presentation(conversationId: String, preview: String, updatedAt: Long, remote: PteIMRemoteConversation?): PteIMUIConversationPresentation {
    val title = remote?.title?.takeIf { it.isNotBlank() } ?: conversationId
    return PteIMUIConversationPresentation(conversationId, title, preview, relativeTime(updatedAt), remote?.unreadCount ?: 0, title.take(1), isOnline = false)
  }
  /** Override to replace fixed search chrome while retaining local filtering. */
  protected open fun searchBar(): View = FrameLayout(context).apply {
    setPadding(dp(20), dp(6), dp(20), dp(8))
    val palette = resolvePalette()
    val shell = FrameLayout(context).apply { background = rounded(if (isDark()) Color.rgb(30, 29, 72) else Color.rgb(238, 238, 255), 16) }
    shell.addView(ImageView(context).apply { setImageResource(R.drawable.pte_im_ui_conversation_search); scaleType = ImageView.ScaleType.FIT_CENTER }, FrameLayout.LayoutParams(dp(20), dp(20), Gravity.CENTER_VERTICAL).apply { leftMargin = dp(13) })
    searchField.apply {
      background = null; hint = if (client.currentAppearance().language.isEnglish(context)) "Search" else "搜索"; textSize = 13f; setSingleLine(true); includeFontPadding = false
      setTextColor(palette.primaryText); setHintTextColor(palette.secondaryText); setPadding(dp(42), 0, dp(12), 0)
      if (!searchListenerAttached) {
        addTextChangedListener(object : TextWatcher { override fun beforeTextChanged(s: CharSequence?, start: Int, count: Int, after: Int) {} ; override fun onTextChanged(s: CharSequence?, start: Int, before: Int, count: Int) { query = s?.toString().orEmpty(); refresh() }; override fun afterTextChanged(s: Editable?) {} })
        searchListenerAttached = true
      }
    }
    (searchField.parent as? ViewGroup)?.removeView(searchField)
    shell.addView(searchField, FrameLayout.LayoutParams(-1, -1))
    addView(shell, FrameLayout.LayoutParams(-1, -1))
  }
  protected open fun actionButton(resource: Int, description: String, action: () -> Unit): ImageButton = ImageButton(context).apply { setImageResource(resource); background = null; scaleType = ImageView.ScaleType.CENTER_INSIDE; contentDescription = description; setPadding(dp(5), dp(5), dp(5), dp(5)); setOnClickListener { action() } }
  protected open fun previewFor(message: PteIMMessage): String = when (message.type) { PteIMMessageType.TEXT -> message.text.orEmpty(); PteIMMessageType.IMAGE -> "[图片] [Image]"; PteIMMessageType.VOICE -> "[语音] ${(message.voice?.durationMs ?: 0) / 1000}秒"; PteIMMessageType.RED_PACKET -> "[红包] 恭喜发财"; PteIMMessageType.ORDER -> "[订单] ${message.business?.title.orEmpty()}"; else -> "[${message.type.name.lowercase()}]" }
  protected open fun relativeTime(value: Long): String {
    if (value <= 0) return ""
    val now = java.util.Calendar.getInstance(); val then = java.util.Calendar.getInstance().apply { timeInMillis = value }
    return when { now.get(java.util.Calendar.YEAR) == then.get(java.util.Calendar.YEAR) && now.get(java.util.Calendar.DAY_OF_YEAR) == then.get(java.util.Calendar.DAY_OF_YEAR) -> java.text.SimpleDateFormat("HH:mm", java.util.Locale.getDefault()).format(java.util.Date(value)); now.get(java.util.Calendar.YEAR) == then.get(java.util.Calendar.YEAR) && now.get(java.util.Calendar.DAY_OF_YEAR) - then.get(java.util.Calendar.DAY_OF_YEAR) == 1 -> "昨天"; else -> java.text.SimpleDateFormat("MM/dd", java.util.Locale.getDefault()).format(java.util.Date(value)) }
  }
  protected fun resolvePalette(): PteIMUIThemePalette = when (client.currentAppearance().themeMode) { PteIMThemeMode.DARK -> uiTheme.dark; PteIMThemeMode.LIGHT -> uiTheme.light; PteIMThemeMode.SYSTEM -> if (systemTheme(context).name == "DARK") uiTheme.dark else uiTheme.light }
  protected fun isDark(): Boolean = client.currentAppearance().themeMode == PteIMThemeMode.DARK || (client.currentAppearance().themeMode == PteIMThemeMode.SYSTEM && systemTheme(context).name == "DARK")
  protected fun rounded(fill: Int, radius: Int, stroke: Int = Color.TRANSPARENT) = GradientDrawable().apply { setColor(fill); if (stroke != Color.TRANSPARENT) setStroke(dp(1), stroke); cornerRadius = dp(radius).toFloat() }
  protected fun circle(fill: Int) = GradientDrawable().apply { setColor(fill); shape = GradientDrawable.OVAL }
  protected open fun avatarColor(value: String): Int = intArrayOf(Color.rgb(143, 76, 247), Color.rgb(0, 158, 199), Color.rgb(0, 159, 112), Color.rgb(229, 125, 0), Color.rgb(219, 37, 117)).let { it[(value.hashCode() and Int.MAX_VALUE) % it.size] }
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
  private val appearanceListener = object : PteIMListener {
    override fun onThemeModeChanged(themeMode: PteIMThemeMode) { post { applyTheme() } }
    override fun onLanguageChanged(language: PteIMLanguage) { post { applyTheme() } }
  }

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
    orientation = LinearLayout.HORIZONTAL; gravity = Gravity.CENTER_VERTICAL; setPadding(dp(20), dp(12), dp(20), dp(12)); setBackgroundColor(resolvePalette().background)
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
  /**
   * Primary contact-cell factory for inherited views. Subclasses may override
   * it for a custom cell while [contactRow] stays available for integrations
   * that already override the original API.
   */
  open fun createContactCell(item: PteIMUIContactPresentation): View = contactRow(item)
  protected open fun render() {
    content.removeAllViews(); content.addView(contactHeader(), LayoutParams(-1, -2)); contacts.forEach { content.addView(createContactCell(it), LayoutParams(-1, -2)) }
  }
  /** Override to replace title and quick-action chrome without touching cursor pagination. */
  open fun contactHeader(): View {
    val palette = resolvePalette()
    return LinearLayout(context).apply {
      orientation = LinearLayout.VERTICAL; setBackgroundColor(palette.background)
      addView(LinearLayout(context).apply {
        gravity = Gravity.CENTER_VERTICAL; setPadding(dp(20), dp(14), dp(20), dp(12)); setBackgroundColor(palette.surface)
        addView(TextView(context).apply { text = "◉"; gravity = Gravity.CENTER; textSize = 16f; setTextColor(palette.outgoingText); background = GradientDrawable(GradientDrawable.Orientation.LEFT_RIGHT, intArrayOf(palette.outgoingStart, palette.outgoingEnd)).apply { cornerRadius = dp(18).toFloat() } }, LinearLayout.LayoutParams(dp(36), dp(36)))
        addView(TextView(context).apply { text = if (client.currentAppearance().language.isEnglish(context)) "Contacts" else "联系人"; textSize = 22f; setTextColor(palette.primaryText); setPadding(dp(10), 0, 0, 0) }, LinearLayout.LayoutParams(0, -2, 1f))
      }, LinearLayout.LayoutParams(-1, -2))
      addView(TextView(context).apply { text = if (mode == PteIMUIContactListMode.GROUPS) "GROUPS" else "PERSONAL"; textSize = 10f; setTextColor(palette.secondaryText); setPadding(dp(20), dp(16), dp(20), dp(5)) }, LinearLayout.LayoutParams(-1, -2))
    }
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
  protected fun avatarBackground(palette: PteIMUIThemePalette) = GradientDrawable(GradientDrawable.Orientation.LEFT_RIGHT, intArrayOf(palette.outgoingStart, palette.outgoingEnd)).apply { cornerRadius = dp(22).toFloat() }
  protected fun dp(value: Int) = (value * resources.displayMetrics.density).toInt()
}

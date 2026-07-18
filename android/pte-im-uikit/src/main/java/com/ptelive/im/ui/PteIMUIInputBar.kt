package com.ptelive.im.ui

import android.content.Context
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.ColorMatrix
import android.graphics.ColorMatrixColorFilter
import android.graphics.Paint
import android.graphics.Typeface
import android.graphics.drawable.GradientDrawable
import android.icu.text.BreakIterator
import android.text.InputFilter
import android.text.InputType
import android.text.TextPaint
import android.text.TextWatcher
import android.view.Gravity
import android.view.KeyEvent
import android.view.inputmethod.EditorInfo
import android.view.inputmethod.InputMethodManager
import android.view.MotionEvent
import android.view.View
import android.widget.Button
import android.widget.EditText
import android.widget.FrameLayout
import android.widget.GridLayout
import android.widget.ImageButton
import android.widget.ImageView
import android.widget.LinearLayout
import android.widget.ScrollView
import android.widget.TextView
import android.view.ViewGroup

/**
 * Reusable native composer following the PteIMUI chat specification.
 *
 * It deliberately owns only presentation and input-state transitions. File
 * pickers, voice recording and every business action remain callbacks for the
 * embedding app, so a host can swap them without forking the chat view.
 */
open class PteIMUIInputBar(context: Context, private var palette: PteIMUIThemePalette) : LinearLayout(context) {
  var onSendText: ((String) -> Unit)? = null
  var onEmojiSelected: ((String, String) -> Unit)? = null
  var onActionSelected: ((PteIMUIAction) -> Unit)? = null
  var onCustomActionSelected: ((PteIMUICustomInputAction) -> Unit)? = null
  var onVoiceRecordingChanged: ((Boolean) -> Unit)? = null
  var onVoiceRecordingCancelled: (() -> Unit)? = null
  /** Lets the host dismiss transient surfaces before any composer interaction. */
  var onInteraction: (() -> Unit)? = null

  private val composer = LinearLayout(context).apply { orientation = HORIZONTAL; gravity = Gravity.CENTER_VERTICAL; setPadding(dp(14), dp(8), dp(14), dp(8)) }
  private val voiceToggle = imageButton()
  /** The 40dp input surface. Emoji moves into it while a panel is expanded. */
  private val inputShell = FrameLayout(context)
  private val draft = EditText(context).apply {
    // IM composer contract: the software keyboard always exposes Send. Do not
    // advertise a newline action, otherwise several Android IMEs replace Send
    // with a return key despite IME_ACTION_SEND being configured.
    inputType = InputType.TYPE_CLASS_TEXT or InputType.TYPE_TEXT_FLAG_CAP_SENTENCES
    setSingleLine(true)
    gravity = Gravity.CENTER_VERTICAL
    includeFontPadding = false
    filters = arrayOf(InputFilter.LengthFilter(200))
    isVerticalScrollBarEnabled = false
    // The IME is explicitly a send action; line breaks are not part of the
    // mobile composer interaction.
    imeOptions = EditorInfo.IME_ACTION_SEND or EditorInfo.IME_FLAG_NO_EXTRACT_UI
  }
  private val holdToTalk = Button(context).apply { isAllCaps = false; visibility = GONE; includeFontPadding = false }
  private val more = imageButton()
  private val emoji = imageButton()
  private val send = imageButton()
  private val close = ImageButton(context).apply { background = null; setImageResource(android.R.drawable.ic_menu_close_clear_cancel); visibility = GONE; contentDescription = "Close panel"; setPadding(dp(9), dp(9), dp(9), dp(9)) }
  private val panel = FrameLayout(context).apply { visibility = GONE }
  private var voiceMode = false
  private var shownPanel: Panel? = null
  private var english = false
  private var standaloneEmoji: PteIMUIEmoji? = null
  private var keyboardActive = false
  private var recording = false
  private var recordingCancelled = false
  /** Uses Android's actual fallback chain, so missing Emoji glyphs never render as tofu boxes. */
  private val emojiGlyphPaint = TextPaint(Paint.ANTI_ALIAS_FLAG).apply { typeface = Typeface.create("sans-serif", Typeface.NORMAL) }
  /** The first category contains only emojis actually used in this composer. */
  private var recentEmojis = emptyList<PteIMUIEmoji>()
  private var allEmojis = supportedEmojis(PteIMUIEmojiCatalog.smileys().map { PteIMUIEmoji(emojiId = it) })
  private var showingRecentEmojis = false
  private var customActions = emptyList<PteIMUICustomInputAction>()
  private var composerInputHeight = dp(40)

  private enum class Panel { EMOJI, MORE }

  init {
    orientation = VERTICAL
    addView(composer, LayoutParams(-1, dp(56)))
    addView(panel, LayoutParams(-1, 0))
    composer.addView(voiceToggle, LayoutParams(dp(40), dp(40)))
    composer.addView(inputShell, LayoutParams(0, dp(40), 1f).apply { marginStart = dp(4); marginEnd = dp(4) })
    inputShell.addView(draft, FrameLayout.LayoutParams(-1, -1))
    inputShell.addView(holdToTalk, FrameLayout.LayoutParams(-1, -1))
    composer.addView(emoji, LayoutParams(dp(40), dp(40)))
    composer.addView(more, LayoutParams(dp(40), dp(40)))
    composer.addView(send, LayoutParams(dp(40), dp(40)))
    composer.addView(close, LayoutParams(dp(40), dp(40)))
    voiceToggle.setOnClickListener { toggleVoice() }
    more.setOnClickListener { togglePanel(Panel.MORE) }
    emoji.setOnClickListener { togglePanel(Panel.EMOJI) }
    send.setOnClickListener { submitText() }
    close.setOnClickListener { closePanel() }
    // Mobile keyboards expose "发送" / Send; Enter maps to the same action.
    draft.setOnEditorActionListener { _, actionId, _ ->
      if (actionId == EditorInfo.IME_ACTION_SEND) { submitText(); true } else false
    }
    // Covers physical keyboards and IMEs that emit Enter instead of the
    // editor action while preserving the single-line Send behaviour.
    draft.setOnKeyListener { _, keyCode, event ->
      if (keyCode == KeyEvent.KEYCODE_ENTER && !event.isShiftPressed && event.action == KeyEvent.ACTION_UP) { submitText(); true } else false
    }
    draft.setOnFocusChangeListener { _, focused ->
      onInteraction?.invoke()
      keyboardActive = focused && !voiceMode
      if (keyboardActive) {
        // The platform IME and a custom bottom panel are mutually exclusive.
        // Clear either Emoji or More before showing the keyboard so it cannot
        // compress the message canvas underneath the IME.
        shownPanel = null
        showKeyboard()
      }
      refreshPanel()
    }
    draft.addTextChangedListener(object : TextWatcher {
      override fun beforeTextChanged(value: CharSequence?, start: Int, count: Int, after: Int) = Unit
      override fun onTextChanged(value: CharSequence?, start: Int, before: Int, count: Int) = Unit
      override fun afterTextChanged(value: android.text.Editable?) { resizeComposerForText() }
    })
    holdToTalk.setOnTouchListener { _, event ->
      when (event.actionMasked) {
        MotionEvent.ACTION_DOWN -> { onInteraction?.invoke(); recording = true; recordingCancelled = false; applyHoldToTalkAppearance(); onVoiceRecordingChanged?.invoke(true); true }
        MotionEvent.ACTION_MOVE -> {
          val cancelled = event.x !in 0f..holdToTalk.width.toFloat() || event.y !in 0f..holdToTalk.height.toFloat()
          if (recordingCancelled != cancelled) { recordingCancelled = cancelled; applyHoldToTalkAppearance() }
          true
        }
        MotionEvent.ACTION_UP -> {
          val cancelled = recordingCancelled
          recording = false; recordingCancelled = false; applyHoldToTalkAppearance(); onVoiceRecordingChanged?.invoke(false)
          if (cancelled) onVoiceRecordingCancelled?.invoke()
          true
        }
        MotionEvent.ACTION_CANCEL -> { recording = false; recordingCancelled = true; applyHoldToTalkAppearance(); onVoiceRecordingChanged?.invoke(false); onVoiceRecordingCancelled?.invoke(); true }
        else -> true
      }
    }
    applyPalette(palette)
  }

  /** Applies an independently configurable skin without changing panel state. */
  open fun applyPalette(value: PteIMUIThemePalette) {
    palette = value
    setBackgroundColor(palette.composer)
    // The recording bar is a bottom sheet: a shared top edge and rounded
    // corners keep it visually separate from the message canvas.
    composer.background = composerSurface()
    english = resources.configuration.locales[0]?.language?.equals("zh", ignoreCase = true) != true
    draft.setTextColor(palette.primaryText)
    draft.setHintTextColor(palette.secondaryText)
    draft.hint = if (english) "Say something..." else "说点什么..."
    draft.setPadding(dp(10), dp(5), dp(10), dp(5))
    draft.background = null
    inputShell.background = rounded(palette.composerInput, Color.TRANSPARENT, 12)
    applyHoldToTalkAppearance()
    applyIconState()
    refreshPanel()
  }

  fun setEmojiDataSource(value: PteIMUIEmojiDataSource) {
    // A host may seed the history (for example from persisted conversation
    // data); subsequent selections are kept at the front of this list.
    recentEmojis = supportedEmojis(value.common)
    allEmojis = supportedEmojis(value.all)
    if (showingRecentEmojis && recentEmojis.isEmpty()) showingRecentEmojis = false
    if (shownPanel == Panel.EMOJI) refreshPanel()
  }

  fun setCustomActions(value: List<PteIMUICustomInputAction>) {
    require(value.size <= 4) { "At most four custom input actions are supported" }
    customActions = value
    if (shownPanel == Panel.MORE) refreshPanel()
  }

  fun setCopy(messageHint: String, sendTitle: String, holdTitle: String) {
    english = sendTitle.equals("Send", ignoreCase = true)
    draft.hint = messageHint
    holdToTalk.text = holdTitle
  }

  fun clearText() { standaloneEmoji = null; draft.setText("") }
  fun openEmojiPanel() { togglePanel(Panel.EMOJI) }
  /** Opens the emoji input surface deterministically (rather than toggling it). */
  fun showEmojiPanel() {
    onInteraction?.invoke()
    keyboardActive = false
    draft.clearFocus()
    hideKeyboard()
    shownPanel = Panel.EMOJI
    refreshPanel()
  }
  fun openActionPanel() { togglePanel(Panel.MORE) }
  /** Opens the software keyboard for a quote or other chat-level text action. */
  fun focusTextInput() {
    onInteraction?.invoke()
    if (voiceMode) {
      voiceMode = false
      recording = false
      draft.visibility = VISIBLE
      holdToTalk.visibility = GONE
      applyIconState()
    }
    shownPanel = null
    keyboardActive = true
    refreshPanel()
    draft.requestFocus()
    showKeyboard()
  }
  /** Hides the IME and expansion panels before a chat-level transient surface opens. */
  fun closeTransientInput() {
    keyboardActive = false
    draft.clearFocus()
    hideKeyboard()
    if (shownPanel != null) {
      shownPanel = null
      refreshPanel()
    }
  }

  private fun toggleVoice() {
    onInteraction?.invoke()
    voiceMode = !voiceMode
    recording = false
    keyboardActive = false
    draft.visibility = if (voiceMode) GONE else VISIBLE
    holdToTalk.visibility = if (voiceMode) VISIBLE else GONE
    if (voiceMode) hideKeyboard() else { draft.requestFocus(); showKeyboard() }
    closePanel()
    applyIconState()
  }

  private fun togglePanel(kind: Panel) {
    onInteraction?.invoke()
    keyboardActive = false
    draft.clearFocus()
    hideKeyboard()
    shownPanel = if (shownPanel == kind) null else kind
    refreshPanel()
  }

  private fun closePanel() { shownPanel = null; refreshPanel() }

  private fun submitText() {
    onInteraction?.invoke()
    draft.text.toString().trim().takeIf { it.isNotEmpty() }?.let {
      // A single selected emoji keeps the Core emoji-message type; mixed
      // content remains a normal Unicode text message, just like native IMEs.
      val selected = standaloneEmoji
      if (selected != null && (selected.glyph ?: selected.emojiId) == it) onEmojiSelected?.invoke(selected.packageId, selected.emojiId) else onSendText?.invoke(it)
      standaloneEmoji = null
      draft.setText("")
      draft.clearFocus()
      keyboardActive = false
      closePanel()
    }
  }

  private fun applyIconState() {
    val dark = palette.background == PteIMUITheme.blueVioletDark().background
    voiceToggle.setImageResource(
      if (voiceMode) if (dark) R.drawable.pte_im_ui_chat_voice_toggle_dark else R.drawable.pte_im_ui_chat_voice_toggle_light
      else if (dark) R.drawable.pte_im_ui_chat_voice_default_dark else R.drawable.pte_im_ui_chat_voice_default_light,
    )
    emoji.setImageResource(if (shownPanel == Panel.EMOJI) if (dark) R.drawable.pte_im_ui_chat_emoji_toggle_dark else R.drawable.pte_im_ui_chat_emoji_toggle_light else if (dark) R.drawable.pte_im_ui_chat_emoji_default_dark else R.drawable.pte_im_ui_chat_emoji_default_light)
    more.setImageResource(if (shownPanel == Panel.MORE) if (dark) R.drawable.pte_im_ui_chat_more_toggle_dark else R.drawable.pte_im_ui_chat_more_toggle_light else if (dark) R.drawable.pte_im_ui_chat_more_default_dark else R.drawable.pte_im_ui_chat_more_default_light)
    send.setImageResource(if (dark) R.drawable.pte_im_ui_chat_send_dark else R.drawable.pte_im_ui_chat_send_light)
    close.setImageResource(if (dark) R.drawable.pte_im_ui_chat_more_toggle_dark else R.drawable.pte_im_ui_chat_more_toggle_light)
    voiceToggle.contentDescription = if (voiceMode) "Text input" else "Voice"
  }

  private fun refreshPanel() {
    panel.removeAllViews()
    val current = shownPanel
    panel.visibility = if (current == null) GONE else VISIBLE
    // Voice mode is intentionally minimal: speech/text switch, 40dp hold
    // surface and + only. Keyboard and expanded panels embed the emoji inside
    // the text surface exactly as the supplied states show.
    val embedEmoji = current != null || keyboardActive
    placeEmojiInInput(embedEmoji)
    more.visibility = if (current == Panel.MORE) GONE else VISIBLE
    emoji.visibility = if (voiceMode) GONE else VISIBLE
    // Keyboard submission is IME-only. The design exposes a send control only
    // in the emoji panel, where it is drawn at the panel's bottom right.
    send.visibility = GONE
    close.visibility = if (current == Panel.MORE) VISIBLE else GONE
    val params = panel.layoutParams
    params.height = when (current) {
      Panel.EMOJI -> dp(338)
      Panel.MORE -> if (customActions.isEmpty()) dp(200) else dp(295)
      null -> 0
    }
    panel.layoutParams = params
    applyIconState()
    when (current) {
      Panel.EMOJI -> renderEmojiPanel()
      Panel.MORE -> renderMorePanel()
      null -> Unit
    }
  }

  private fun renderEmojiPanel() {
    val root = FrameLayout(context)
    val wrap = LinearLayout(context).apply { orientation = VERTICAL; setPadding(dp(12), 0, dp(12), dp(6)); setBackgroundColor(palette.panel) }
    // Design-category strip: recent + eight visual categories. The supplied
    // visual design keeps every category glyph on the panel background.
    val categories = LinearLayout(context).apply { gravity = Gravity.CENTER_VERTICAL; setPadding(dp(4), dp(2), dp(4), dp(2)) }
    categories.addView(FrameLayout(context).apply {
      addView(ImageView(context).apply {
        setImageResource(R.drawable.pte_im_ui_chat_history_emoji)
        scaleType = ImageView.ScaleType.FIT_CENTER
        contentDescription = if (english) "Recent emojis" else "历史表情"
      }, FrameLayout.LayoutParams(dp(36), dp(32), Gravity.CENTER))
      isClickable = true; isFocusable = true
      setOnClickListener {
        showingRecentEmojis = !showingRecentEmojis
        refreshPanel()
      }
    }, LinearLayout.LayoutParams(0, dp(44), 1f))
    listOf("😀", "👋", "❤️", "🐶", "🍎", "⚽", "🚗", "💡", "🎉").forEach { glyph ->
      categories.addView(PteIMUIBrightEmojiView(context).apply {
        text = glyph; textSize = 20f; gravity = Gravity.CENTER; includeFontPadding = false
        background = null
        isClickable = true; isFocusable = true
        // Match iOS: these are quick-insert expressions, not inert category
        // artwork. They also leave the recent view and restore the full grid.
        setOnClickListener {
          onInteraction?.invoke()
          appendEmojiToDraft(PteIMUIEmoji(emojiId = glyph))
          showingRecentEmojis = false
          refreshPanel()
        }
      }, LinearLayout.LayoutParams(0, dp(44), 1f))
    }
    wrap.addView(categories, LayoutParams(-1, dp(48)))
    wrap.addView(View(context).apply { setBackgroundColor(palette.divider) }, LayoutParams(-1, dp(1)))
    wrap.addView(TextView(context).apply {
      text = when {
        showingRecentEmojis && english -> "RECENT"
        showingRecentEmojis -> "最近使用"
        english -> "SMILEYS"
        else -> "表情"
      }; textSize = 11f; typeface = android.graphics.Typeface.DEFAULT_BOLD
      setTextColor(palette.secondaryText); gravity = Gravity.CENTER_VERTICAL; includeFontPadding = false; setPadding(dp(6), 0, 0, 0)
    }, LayoutParams(-1, dp(26)))
    val scroll = ScrollView(context).apply {
      isFillViewport = true; setPadding(0, 0, 0, dp(52)); clipToPadding = false
      if (showingRecentEmojis && recentEmojis.isEmpty()) {
        addView(TextView(context).apply {
          text = if (english) "No recent emojis" else "暂无历史表情"
          textSize = 14f; gravity = Gravity.CENTER; includeFontPadding = false; setTextColor(palette.secondaryText)
        }, LayoutParams(-1, dp(120)))
      } else {
        addView(emojiGrid(), LayoutParams(-1, -2))
      }
    }
    wrap.addView(scroll, LayoutParams(-1, 0, 1f))
    root.addView(wrap, FrameLayout.LayoutParams(-1, -1))
    val controls = LinearLayout(context).apply { gravity = Gravity.CENTER_VERTICAL }
    controls.addView(imageButton().apply {
      // These two artwork files include their own button surface. Fit them to
      // the full 40dp touch target instead of centring a smaller icon inside it.
      scaleType = ImageView.ScaleType.FIT_XY
      setImageResource(if (isDark()) R.drawable.pte_im_ui_chat_backspace_dark else R.drawable.pte_im_ui_chat_backspace_light)
      contentDescription = "Delete emoji"
      setOnClickListener {
        deleteLastDraftGrapheme()
        if (draft.text.isEmpty()) standaloneEmoji = null
      }
    }, LinearLayout.LayoutParams(dp(40), dp(40)))
    controls.addView(imageButton().apply {
      scaleType = ImageView.ScaleType.FIT_XY
      setImageResource(if (isDark()) R.drawable.pte_im_ui_chat_send_dark else R.drawable.pte_im_ui_chat_send_light)
      contentDescription = if (english) "Send" else "发送"
      setOnClickListener { submitText() }
    }, LinearLayout.LayoutParams(dp(40), dp(40)).apply { marginStart = dp(8) })
    root.addView(controls, FrameLayout.LayoutParams(-2, dp(40), Gravity.BOTTOM or Gravity.END).apply { marginEnd = dp(14); bottomMargin = dp(8) })
    panel.addView(root, LayoutParams(-1, -1))
  }

  /**
   * A fixed eight-column row keeps a short history anchored at its first
   * column. GridLayout distributes a one-item row over the full width, which
   * visually placed the recent emoji in the centre of the panel.
   */
  private fun emojiGrid(): LinearLayout = LinearLayout(context).apply {
    orientation = VERTICAL
    val emojis = if (showingRecentEmojis) recentEmojis else allEmojis
    emojis.chunked(8).forEach { rowItems ->
      addView(LinearLayout(context).apply {
        orientation = HORIZONTAL
        gravity = Gravity.START
        rowItems.forEach { item -> addView(emojiCell(item), LayoutParams(0, dp(44), 1f)) }
        repeat(8 - rowItems.size) { addView(View(context), LayoutParams(0, dp(44), 1f)) }
      }, LayoutParams(-1, dp(44)))
    }
  }

  /**
   * Emoji commonly occupy two UTF-16 code units (and may contain variation,
   * modifier or ZWJ code points). Deleting a single code unit leaves an
   * unpaired surrogate, which Android renders as `?`. ICU character breaks
   * remove the whole visible grapheme in a single tap.
   */
  private fun deleteLastDraftGrapheme() {
    val value = draft.text.toString()
    if (value.isEmpty()) return
    val iterator = BreakIterator.getCharacterInstance()
    iterator.setText(value)
    val end = iterator.last()
    val start = iterator.previous()
    draft.text.delete(if (start == BreakIterator.DONE) 0 else start, end)
  }

  private fun supportedEmojis(items: List<PteIMUIEmoji>): List<PteIMUIEmoji> = items.filter { item ->
    item.iconResource != null || (item.glyph ?: item.emojiId).let { glyph -> glyph.isNotBlank() && emojiGlyphPaint.hasGlyph(glyph) }
  }

  private fun emojiCell(item: PteIMUIEmoji): View = FrameLayout(context).apply {
    isClickable = true; isFocusable = true
    val icon: View = if (item.iconResource != null) ImageView(context).apply { setImageResource(item.iconResource); scaleType = ImageView.ScaleType.FIT_CENTER }
    else PteIMUIBrightEmojiView(context).apply { text = item.glyph.orEmpty(); textSize = 24f; gravity = Gravity.CENTER; includeFontPadding = false }
    addView(icon, FrameLayout.LayoutParams(dp(24), dp(32), Gravity.CENTER))
    setOnClickListener {
      appendEmojiToDraft(item)
      if (showingRecentEmojis) refreshPanel()
    }
  }

  /** Appends a picker/shortcut expression and records it for the history tab. */
  private fun appendEmojiToDraft(item: PteIMUIEmoji) {
    val value = item.glyph ?: item.emojiId
    val wasBlank = draft.text.isEmpty()
    draft.append(value)
    standaloneEmoji = if (wasBlank) item else null
    // The history category is most-recent-first and bounded to one 4x8 page.
    recentEmojis = (listOf(item) + recentEmojis.filterNot {
      it.packageId == item.packageId && it.emojiId == item.emojiId
    }).take(32)
  }

  private fun renderMorePanel() {
    val wrap = GridLayout(context).apply { columnCount = 4; setPadding(dp(14), dp(10), dp(14), dp(10)); setBackgroundColor(palette.panel) }
    val standardActions = listOf(
      Triple(R.drawable.pte_im_ui_chat_action_image, if (english) "Image" else "图片", PteIMUIAction.IMAGE),
      Triple(R.drawable.pte_im_ui_chat_action_camera, if (english) "Camera" else "拍摄", PteIMUIAction.CAMERA),
      Triple(R.drawable.pte_im_ui_chat_action_video, if (english) "Video" else "视频", PteIMUIAction.VIDEO),
      Triple(R.drawable.pte_im_ui_chat_action_location, if (english) "Location" else "定位", PteIMUIAction.LOCATION),
      Triple(R.drawable.pte_im_ui_chat_action_file, if (english) "File" else "文件", PteIMUIAction.FILE),
      Triple(R.drawable.pte_im_ui_chat_action_red_packet, if (english) "Red Packet" else "红包", PteIMUIAction.RED_PACKET),
      Triple(R.drawable.pte_im_ui_chat_action_gift, if (english) "Gift" else "礼物", PteIMUIAction.GIFT),
      Triple(R.drawable.pte_im_ui_chat_action_order, if (english) "Order" else "订单", PteIMUIAction.ORDER),
    )
    standardActions.map { action -> PteIMUIInputAction(action.first, action.second) { onActionSelected?.invoke(action.third) } }
      .plus(customActions.map { action -> PteIMUIInputAction(action.iconResource, action.title) { onCustomActionSelected?.invoke(action) } })
      .take(12)
      .forEachIndexed { index, action ->
      val row = index / 4
      val column = index % 4
      wrap.addView(actionCell(action.resource, action.title) { action.click(); closePanel() }, GridLayout.LayoutParams(GridLayout.spec(row), GridLayout.spec(column, 1f)).apply {
        width = 0; height = dp(75)
        setMargins(if (column == 0) 0 else dp(10), if (row == 0) 0 else dp(20), if (column == 3) 0 else dp(10), 0)
      })
    }
    panel.addView(wrap, LayoutParams(-1, -1))
  }

  private data class PteIMUIInputAction(val resource: Int, val title: String, val click: () -> Unit)

  private fun actionCell(resource: Int, title: String, click: () -> Unit): View = LinearLayout(context).apply {
    orientation = VERTICAL; gravity = Gravity.CENTER; isClickable = true; isFocusable = true; setOnClickListener { click() }
    addView(imageButton().apply { setImageResource(resource); setPadding(0, 0, 0, 0); isClickable = false; contentDescription = title }, LayoutParams(dp(52), dp(52)))
    addView(TextView(context).apply { text = title; textSize = 10f; gravity = Gravity.CENTER; includeFontPadding = false; setTextColor(palette.secondaryText) }, LayoutParams(-1, dp(15)).apply { topMargin = dp(8) })
  }

  /** Keeps the compact composer and expanded panels structurally identical to the design. */
  private fun placeEmojiInInput(inside: Boolean) {
    val parent = emoji.parent as? ViewGroup
    parent?.removeView(emoji)
    if (inside) {
      inputShell.addView(emoji, FrameLayout.LayoutParams(dp(40), dp(40), Gravity.END or Gravity.CENTER_VERTICAL))
      draft.setPadding(dp(10), dp(5), dp(48), dp(5))
      holdToTalk.setPadding(dp(10), 0, dp(48), 0)
    } else {
      composer.addView(emoji, 2, LayoutParams(dp(40), dp(40)))
      draft.setPadding(dp(10), dp(5), dp(10), dp(5))
      holdToTalk.setPadding(dp(10), 0, dp(10), 0)
    }
  }

  private fun isDark(): Boolean = palette.background == PteIMUITheme.blueVioletDark().background

  private fun applyHoldToTalkAppearance() {
    holdToTalk.minHeight = 0; holdToTalk.minWidth = 0
    holdToTalk.gravity = Gravity.CENTER
    holdToTalk.setPadding(dp(10), 0, dp(10), 0)
    val dark = isDark()
    // Keep the recording label optically centred. The mode-switch button on
    // the left already communicates voice input, so the hold surface stays
    // text-only instead of introducing an off-centre duplicate microphone.
    holdToTalk.setCompoundDrawablesRelative(null, null, null, null)
    holdToTalk.compoundDrawablePadding = 0
    holdToTalk.text = when {
      recording && recordingCancelled && english -> "Release to cancel"
      recording && recordingCancelled -> "松开手取消录音"
      recording && english -> "Talking"
      recording -> "正在说话"
      english -> "Hold to Record"
      else -> "按住录音"
    }
    if (recording) {
      holdToTalk.setTextColor(Color.WHITE)
      // Voice recording uses its own violet state surface. Do not reuse the
      // blue-to-violet outgoing message bubble gradient here.
      val start = if (dark) Color.rgb(151, 91, 244) else palette.outgoingStart
      val end = if (dark) Color.rgb(163, 84, 244) else palette.outgoingEnd
      holdToTalk.background = GradientDrawable(GradientDrawable.Orientation.LEFT_RIGHT, intArrayOf(start, end)).apply { cornerRadius = dp(12).toFloat() }
    } else {
      holdToTalk.setTextColor(palette.secondaryText)
      holdToTalk.background = rounded(palette.composerInput, Color.TRANSPARENT, 12)
    }
  }

  private fun composerSurface(): GradientDrawable = GradientDrawable().apply {
    setColor(palette.composer)
    val topRadius = dp(22).toFloat()
    cornerRadii = floatArrayOf(topRadius, topRadius, topRadius, topRadius, 0f, 0f, 0f, 0f)
    setStroke(dp(1), if (isDark()) Color.rgb(42, 39, 81) else palette.divider)
  }

  private fun hideKeyboard() {
    (context.getSystemService(Context.INPUT_METHOD_SERVICE) as? InputMethodManager)?.hideSoftInputFromWindow(windowToken, 0)
  }

  private fun showKeyboard() {
    draft.post {
      (context.getSystemService(Context.INPUT_METHOD_SERVICE) as? InputMethodManager)
        ?.showSoftInput(draft, InputMethodManager.SHOW_IMPLICIT)
    }
  }

  private fun resizeComposerForText() {
    draft.post {
      if (voiceMode) return@post
      val lineHeight = draft.lineHeight.takeIf { it > 0 } ?: dp(20)
      val desired = (draft.lineCount * lineHeight + dp(10)).coerceIn(dp(40), dp(100))
      if (composerInputHeight == desired) return@post
      composerInputHeight = desired
      (inputShell.layoutParams as? LinearLayout.LayoutParams)?.let { params -> params.height = desired; inputShell.layoutParams = params }
      (composer.layoutParams as? LayoutParams)?.let { params -> params.height = desired + dp(16); composer.layoutParams = params }
      draft.maxHeight = dp(100)
      requestLayout()
    }
  }

  private fun imageButton(): ImageButton = ImageButton(context).apply { background = null; scaleType = ImageView.ScaleType.CENTER_INSIDE; setPadding(0, 0, 0, 0) }
  private fun rounded(fill: Int, stroke: Int, radius: Int) = GradientDrawable().apply { setColor(fill); setStroke(dp(1), stroke); cornerRadius = dp(radius).toFloat() }
  private fun dp(value: Int) = (value * resources.displayMetrics.density).toInt()
}

/** Applies the bright design treatment after Android has rendered its color-emoji glyph. */
private class PteIMUIBrightEmojiView(context: Context) : TextView(context) {
  private val brightPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
    colorFilter = ColorMatrixColorFilter(ColorMatrix(floatArrayOf(
      1.25f, 0f, 0f, 0f, 20f,
      0f, 1.25f, 0f, 0f, 20f,
      0f, 0f, 1.25f, 0f, 20f,
      0f, 0f, 0f, 1f, 0f,
    )))
  }

  override fun onDraw(canvas: Canvas) {
    val layer = canvas.saveLayer(null, brightPaint)
    super.onDraw(canvas)
    canvas.restoreToCount(layer)
  }
}

/** Kept private to avoid exposing a layout primitive as PteIMUIKit public API. */

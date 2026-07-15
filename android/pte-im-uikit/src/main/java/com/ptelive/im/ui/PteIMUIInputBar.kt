package com.ptelive.im.ui

import android.content.Context
import android.graphics.drawable.GradientDrawable
import android.view.Gravity
import android.view.MotionEvent
import android.view.View
import android.widget.Button
import android.widget.EditText
import android.widget.LinearLayout

/** Reusable, dependency-free native input bar. It delegates pickers/recording to its host. */
class PteIMUIInputBar(context: Context, private var palette: PteIMUIThemePalette) : LinearLayout(context) {
  var onSendText: ((String) -> Unit)? = null
  var onEmojiSelected: ((String, String) -> Unit)? = null
  var onActionSelected: ((PteIMUIAction) -> Unit)? = null
  var onVoiceRecordingChanged: ((Boolean) -> Unit)? = null

  private val container = LinearLayout(context).apply { orientation = HORIZONTAL; gravity = Gravity.CENTER_VERTICAL }
  private val voiceToggle = iconButton("语音")
  private val draft = EditText(context).apply { hint = "输入消息"; minLines = 1; maxLines = 4; background = null }
  private val holdToTalk = Button(context).apply { text = "按住说话"; visibility = GONE; isAllCaps = false }
  private val more = iconButton("＋")
  private val emoji = iconButton("表情")
  private val send = Button(context).apply { text = "发送"; isAllCaps = false }
  private val panel = LinearLayout(context).apply { orientation = HORIZONTAL; gravity = Gravity.CENTER; visibility = GONE }
  private var voiceMode = false
  private var shownPanel: String? = null

  init {
    orientation = VERTICAL
    setPadding(dp(10), dp(8), dp(10), dp(8))
    addView(container, LayoutParams(-1, dp(48)))
    addView(panel, LayoutParams(-1, dp(0)))
    container.addView(voiceToggle, LayoutParams(dp(46), -1))
    container.addView(draft, LayoutParams(0, -1, 1f))
    container.addView(holdToTalk, LayoutParams(0, dp(36), 1f))
    container.addView(more, LayoutParams(dp(42), -1))
    container.addView(emoji, LayoutParams(dp(48), -1))
    container.addView(send, LayoutParams(dp(56), dp(36)))
    voiceToggle.setOnClickListener { toggleVoice() }
    more.setOnClickListener { togglePanel("more") }
    emoji.setOnClickListener { togglePanel("emoji") }
    send.setOnClickListener { submitText() }
    draft.setOnEditorActionListener { _, _, _ -> submitText(); true }
    holdToTalk.setOnTouchListener { _, event ->
      when (event.action) {
        MotionEvent.ACTION_DOWN -> { holdToTalk.alpha = 0.64f; onVoiceRecordingChanged?.invoke(true); true }
        MotionEvent.ACTION_UP, MotionEvent.ACTION_CANCEL -> { holdToTalk.alpha = 1f; onVoiceRecordingChanged?.invoke(false); true }
        else -> true
      }
    }
    applyPalette(palette)
  }

  fun applyPalette(value: PteIMUIThemePalette) {
    palette = value
    setBackgroundColor(palette.composer)
    container.background = rounded(palette.surface, palette.divider, 24)
    draft.setTextColor(palette.primaryText); draft.setHintTextColor(palette.secondaryText)
    listOf(voiceToggle, more, emoji).forEach { it.setTextColor(palette.icon) }
    holdToTalk.setTextColor(palette.primaryText); holdToTalk.background = rounded(palette.panelItem, palette.divider, 16)
    send.setTextColor(palette.outgoingText); send.background = gradient(palette.outgoingStart, palette.outgoingEnd, 18)
    panel.setBackgroundColor(palette.panel)
    refreshPanel()
  }

  fun setCopy(messageHint: String, sendTitle: String, holdTitle: String) { draft.hint = messageHint; send.text = sendTitle; holdToTalk.text = holdTitle }
  fun clearText() { draft.setText("") }

  private fun toggleVoice() { voiceMode = !voiceMode; draft.visibility = if (voiceMode) GONE else VISIBLE; holdToTalk.visibility = if (voiceMode) VISIBLE else GONE; voiceToggle.text = if (voiceMode) "键盘" else "语音"; togglePanel(null) }
  private fun togglePanel(kind: String?) { shownPanel = if (shownPanel == kind) null else kind; refreshPanel() }
  private fun submitText() { draft.text.toString().trim().takeIf { it.isNotEmpty() }?.let { onSendText?.invoke(it); draft.setText(""); togglePanel(null) } }
  private fun refreshPanel() {
    panel.removeAllViews()
    val current = shownPanel
    panel.visibility = if (current == null) GONE else VISIBLE
    val params = panel.layoutParams; params.height = if (current == null) 0 else dp(108); panel.layoutParams = params
    if (current == null) return
    val values = if (current == "emoji") listOf("☺" to "smile_001", "✦" to "smile_002", "◌" to "wave_001", "♥" to "heart_001", "✓" to "thumb_001", "✺" to "party_001") else listOf("图片" to "image", "视频" to "video", "位置" to "location", "礼物" to "gift", "红包" to "red_packet", "订单" to "order")
    values.forEach { (title, id) ->
      panel.addView(Button(context).apply {
        text = title; isAllCaps = false; textSize = 12f; setTextColor(palette.icon); background = rounded(palette.panelItem, palette.divider, 14)
        setOnClickListener {
          if (current == "emoji") onEmojiSelected?.invoke("default", id) else actionFor(id)?.let { onActionSelected?.invoke(it) }
          togglePanel(null)
        }
      }, LayoutParams(0, dp(58), 1f).apply { setMargins(dp(3), dp(20), dp(3), dp(20)) })
    }
  }

  private fun actionFor(id: String): PteIMUIAction? = when (id) { "image" -> PteIMUIAction.IMAGE; "video" -> PteIMUIAction.VIDEO; "location" -> PteIMUIAction.LOCATION; "gift" -> PteIMUIAction.GIFT; "red_packet" -> PteIMUIAction.RED_PACKET; "order" -> PteIMUIAction.ORDER; else -> null }
  private fun iconButton(label: String) = Button(context).apply { text = label; textSize = 12f; isAllCaps = false; background = null }
  private fun rounded(fill: Int, stroke: Int, radius: Int) = GradientDrawable().apply { setColor(fill); setStroke(dp(1), stroke); cornerRadius = dp(radius).toFloat() }
  private fun gradient(start: Int, end: Int, radius: Int) = GradientDrawable(GradientDrawable.Orientation.LEFT_RIGHT, intArrayOf(start, end)).apply { cornerRadius = dp(radius).toFloat() }
  private fun dp(value: Int) = (value * resources.displayMetrics.density).toInt()
}

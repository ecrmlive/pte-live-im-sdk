package com.ptelive.im.ui

import android.app.Activity
import android.content.Context
import android.content.ContextWrapper
import android.graphics.Color
import android.graphics.drawable.GradientDrawable
import android.os.Looper
import android.view.Gravity
import android.view.View
import android.view.ViewGroup
import android.view.WindowInsets
import android.widget.FrameLayout
import android.widget.LinearLayout
import android.widget.TextView
import java.util.WeakHashMap

/** The semantic appearance of a [PteIMUINotice]. */
enum class PteIMUINoticeType { SUCCESS, ERROR, WARNING, INFO }

/** The overlay placement for a [PteIMUINotice]. */
enum class PteIMUINoticePosition { BOTTOM, CENTER }

/**
 * Independently configurable colours for the reusable feedback component.
 * Hosts may provide a palette without altering any conversation or chat UI.
 */
data class PteIMUINoticeColors(
  val background: Int,
  val border: Int,
  val text: Int,
  val success: Int,
  val error: Int,
  val info: Int,
  val warning: Int = Color.rgb(232, 163, 34),
) {
  companion object {
    fun light() = PteIMUINoticeColors(
      background = Color.WHITE,
      border = Color.rgb(225, 228, 243),
      text = Color.rgb(31, 35, 55),
      success = Color.rgb(22, 181, 112),
      error = Color.rgb(232, 65, 82),
      info = Color.rgb(104, 72, 238),
      warning = Color.rgb(220, 146, 24),
    )

    fun dark() = PteIMUINoticeColors(
      background = Color.rgb(27, 31, 52),
      border = Color.rgb(61, 67, 97),
      text = Color.rgb(244, 245, 255),
      success = Color.rgb(42, 204, 132),
      error = Color.rgb(255, 105, 120),
      info = Color.rgb(159, 117, 255),
      warning = Color.rgb(255, 190, 72),
    )
  }
}

/** Visual and timing configuration for one feedback prompt. */
data class PteIMUINoticeStyle(
  val position: PteIMUINoticePosition = PteIMUINoticePosition.BOTTOM,
  val darkMode: Boolean = false,
  val durationMillis: Long = 2_400L,
  val horizontalMarginDp: Int = 20,
  val bottomMarginDp: Int = 24,
  val colors: PteIMUINoticeColors = if (darkMode) PteIMUINoticeColors.dark() else PteIMUINoticeColors.light(),
)

/**
 * A small, self-contained UIKit feedback overlay.
 *
 * It replaces platform Toast usage for IM interactions. Repeated requests on
 * the same window replace the old prompt, so errors cannot stack over a chat.
 */
object PteIMUINotice {
  private const val animationMillis = 180L
  private data class Entry(val view: View, val dismiss: Runnable)
  private val activeEntries = WeakHashMap<ViewGroup, Entry>()

  fun success(host: View, message: CharSequence, style: PteIMUINoticeStyle = PteIMUINoticeStyle()) =
    show(host, message, PteIMUINoticeType.SUCCESS, style)

  fun error(host: View, message: CharSequence, style: PteIMUINoticeStyle = PteIMUINoticeStyle()) =
    show(host, message, PteIMUINoticeType.ERROR, style)

  fun info(host: View, message: CharSequence, style: PteIMUINoticeStyle = PteIMUINoticeStyle()) =
    show(host, message, PteIMUINoticeType.INFO, style)

  fun warning(host: View, message: CharSequence, style: PteIMUINoticeStyle = PteIMUINoticeStyle()) =
    show(host, message, PteIMUINoticeType.WARNING, style)

  fun success(context: Context, message: CharSequence, style: PteIMUINoticeStyle = PteIMUINoticeStyle()) =
    activityRoot(context)?.let { success(it, message, style) }

  fun error(context: Context, message: CharSequence, style: PteIMUINoticeStyle = PteIMUINoticeStyle()) =
    activityRoot(context)?.let { error(it, message, style) }

  fun info(context: Context, message: CharSequence, style: PteIMUINoticeStyle = PteIMUINoticeStyle()) =
    activityRoot(context)?.let { info(it, message, style) }

  fun warning(context: Context, message: CharSequence, style: PteIMUINoticeStyle = PteIMUINoticeStyle()) =
    activityRoot(context)?.let { warning(it, message, style) }

  fun show(host: View, message: CharSequence, type: PteIMUINoticeType = PteIMUINoticeType.INFO, style: PteIMUINoticeStyle = PteIMUINoticeStyle()) {
    if (message.isBlank()) return
    if (Looper.myLooper() != Looper.getMainLooper()) {
      host.post { show(host, message, type, style) }
      return
    }
    val root = host.rootView as? ViewGroup ?: return
    dismiss(root, animate = false)

    val notice = noticeView(root.context, message, type, style)
    val gravity = when (style.position) {
      PteIMUINoticePosition.BOTTOM -> Gravity.BOTTOM or Gravity.CENTER_HORIZONTAL
      PteIMUINoticePosition.CENTER -> Gravity.CENTER
    }
    val imeInset = root.rootWindowInsets?.getInsets(WindowInsets.Type.ime())?.bottom ?: 0
    val bottomInset = root.rootWindowInsets?.getInsets(WindowInsets.Type.navigationBars())?.bottom ?: 0
    val resolvedBottomMargin = if (style.position == PteIMUINoticePosition.BOTTOM) {
      maxOf(dp(root.context, style.bottomMarginDp), maxOf(imeInset, bottomInset) + dp(root.context, 12))
    } else 0
    root.addView(
      notice,
      FrameLayout.LayoutParams(ViewGroup.LayoutParams.WRAP_CONTENT, ViewGroup.LayoutParams.WRAP_CONTENT, gravity).apply {
        leftMargin = dp(root.context, style.horizontalMarginDp)
        rightMargin = dp(root.context, style.horizontalMarginDp)
        bottomMargin = resolvedBottomMargin
      },
    )
    notice.alpha = 0f
    notice.translationY = if (style.position == PteIMUINoticePosition.BOTTOM) dp(root.context, 14).toFloat() else 0f
    notice.animate().alpha(1f).translationY(0f).setDuration(animationMillis).start()
    val dismiss = Runnable { dismiss(root, animate = true) }
    activeEntries[root] = Entry(notice, dismiss)
    notice.setOnClickListener { dismiss.run() }
    notice.postDelayed(dismiss, style.durationMillis.coerceAtLeast(400L))
  }

  fun dismiss(host: View) {
    val root = host.rootView as? ViewGroup ?: return
    if (Looper.myLooper() == Looper.getMainLooper()) dismiss(root, animate = true) else host.post { dismiss(root, animate = true) }
  }

  private fun dismiss(root: ViewGroup, animate: Boolean) {
    val entry = activeEntries.remove(root) ?: return
    entry.view.removeCallbacks(entry.dismiss)
    if (!animate) {
      root.removeView(entry.view)
      return
    }
    entry.view.animate().alpha(0f).translationY(dp(root.context, 10).toFloat()).setDuration(animationMillis).withEndAction {
      root.removeView(entry.view)
    }.start()
  }

  private fun noticeView(context: Context, message: CharSequence, type: PteIMUINoticeType, style: PteIMUINoticeStyle): View {
    val accent = when (type) {
      PteIMUINoticeType.SUCCESS -> style.colors.success
      PteIMUINoticeType.ERROR -> style.colors.error
      PteIMUINoticeType.WARNING -> style.colors.warning
      PteIMUINoticeType.INFO -> style.colors.info
    }
    val card = LinearLayout(context).apply {
      gravity = Gravity.CENTER_VERTICAL
      minimumHeight = dp(context, 52)
      setPadding(dp(context, 12), dp(context, 8), dp(context, 18), dp(context, 8))
      background = rounded(style.colors.background, style.colors.border, dp(context, 16))
      elevation = dp(context, 12).toFloat()
      contentDescription = message
      importantForAccessibility = View.IMPORTANT_FOR_ACCESSIBILITY_YES
    }
    card.addView(TextView(context).apply {
      text = when (type) {
        PteIMUINoticeType.SUCCESS -> "✓"
        PteIMUINoticeType.ERROR -> "!"
        PteIMUINoticeType.WARNING -> "!"
        PteIMUINoticeType.INFO -> "i"
      }
      gravity = Gravity.CENTER
      textSize = 15f
      setTextColor(Color.WHITE)
      typeface = android.graphics.Typeface.DEFAULT_BOLD
      background = rounded(accent, Color.TRANSPARENT, dp(context, 16))
    }, LinearLayout.LayoutParams(dp(context, 32), dp(context, 32)))
    card.addView(TextView(context).apply {
      text = message
      textSize = 14f
      maxLines = 3
      setLineSpacing(dp(context, 2).toFloat(), 1f)
      setTextColor(style.colors.text)
      setPadding(dp(context, 10), 0, 0, 0)
      maxWidth = dp(context, 280)
    }, LinearLayout.LayoutParams(ViewGroup.LayoutParams.WRAP_CONTENT, ViewGroup.LayoutParams.WRAP_CONTENT))
    return card
  }

  private fun activityRoot(context: Context): View? {
    var current = context
    while (current is ContextWrapper) {
      if (current is Activity) return current.window?.decorView
      current = current.baseContext
    }
    return (current as? Activity)?.window?.decorView
  }

  private fun rounded(fill: Int, stroke: Int, radius: Int) = GradientDrawable().apply {
    shape = GradientDrawable.RECTANGLE
    cornerRadius = radius.toFloat()
    setColor(fill)
    if (stroke != Color.TRANSPARENT) setStroke(1, stroke)
  }

  private fun dp(context: Context, value: Int): Int = (value * context.resources.displayMetrics.density + 0.5f).toInt()
}

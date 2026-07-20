package com.ptelive.im.ui

import android.content.Context
import android.graphics.BitmapFactory
import android.graphics.Color
import android.graphics.Typeface
import android.graphics.drawable.GradientDrawable
import android.view.Gravity
import android.widget.FrameLayout
import android.widget.ImageView
import android.widget.TextView
import java.net.URL
import kotlin.math.min

/**
 * Shared avatar primitive for all Android IM surfaces. It is circular by
 * default; assign [cornerRadiusDp] to render a rounded square. Remote images
 * are always centre-cropped and clipped to the same shape.
 */
open class PteIMUIAvatarView(context: Context) : FrameLayout(context) {
  var cornerRadiusDp: Int? = null
    set(value) { field = value; applyShape() }

  private val initials = TextView(context).apply {
    gravity = Gravity.CENTER; setTextColor(Color.WHITE); textSize = 15f; typeface = Typeface.DEFAULT_BOLD
  }
  private val image = ImageView(context).apply { scaleType = ImageView.ScaleType.CENTER_CROP; visibility = GONE }
  private val presence = ImageView(context).apply { visibility = GONE }
  private var imageURL = ""
  private var initialsColor = Color.TRANSPARENT
  private var presenceVisible = false

  init {
    clipToOutline = true
    addView(initials, LayoutParams(-1, -1))
    addView(image, LayoutParams(-1, -1))
    addView(presence, LayoutParams(dp(10), dp(10), Gravity.BOTTOM or Gravity.END).apply { rightMargin = dp(1); bottomMargin = dp(1) })
  }

  fun bind(label: String, backgroundColor: Int, url: String? = null, online: Boolean = false) {
    initialsColor = backgroundColor; presenceVisible = online
    initials.text = label.take(1).uppercase()
    imageURL = url.orEmpty(); image.visibility = GONE; image.setImageDrawable(null)
    applyShape()
    if (imageURL.isBlank()) return
    val expected = imageURL
    Thread {
      val bitmap = runCatching { URL(expected).openConnection().getInputStream().use(BitmapFactory::decodeStream) }.getOrNull()
      post { if (expected == imageURL && bitmap != null) { image.setImageBitmap(bitmap); image.visibility = VISIBLE } }
    }.start()
  }

  override fun onSizeChanged(w: Int, h: Int, oldw: Int, oldh: Int) { super.onSizeChanged(w, h, oldw, oldh); applyShape() }
  private fun applyShape() {
    background = shape(Color.TRANSPARENT)
    initials.background = shape(initialsColor)
    presence.visibility = if (presenceVisible) VISIBLE else GONE
    presence.background = shape(Color.rgb(25, 205, 91))
    clipToOutline = true
  }
  private fun shape(color: Int): GradientDrawable {
    val limit = min(width.takeIf { it > 0 } ?: dp(44), height.takeIf { it > 0 } ?: dp(44)) / 2f
    val custom = cornerRadiusDp?.let(::dp)?.toFloat() ?: limit
    return GradientDrawable().apply { setColor(color); cornerRadius = custom.coerceIn(0f, limit) }
  }
  private fun dp(value: Int): Int = (value * resources.displayMetrics.density).toInt()
}

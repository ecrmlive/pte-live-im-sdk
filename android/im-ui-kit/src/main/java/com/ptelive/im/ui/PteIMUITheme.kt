package com.ptelive.im.ui

import android.graphics.Color

/** Palette used by [PteIMUIKit]. The host may provide its own brand colors. */
data class PteIMUITheme(
  val background: Int, val incomingBubble: Int, val outgoingBubble: Int,
  val primaryText: Int, val secondaryText: Int,
) {
  companion object {
    fun light() = PteIMUITheme(Color.rgb(247, 249, 252), Color.rgb(235, 239, 245), Color.rgb(25, 118, 210), Color.rgb(25, 28, 33), Color.rgb(96, 105, 117))
    fun dark() = PteIMUITheme(Color.rgb(24, 24, 27), Color.rgb(63, 63, 70), Color.rgb(30, 95, 158), Color.rgb(245, 245, 245), Color.rgb(180, 180, 190))
  }
}

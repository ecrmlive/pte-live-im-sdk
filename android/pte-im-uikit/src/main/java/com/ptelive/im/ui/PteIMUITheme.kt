package com.ptelive.im.ui

import android.graphics.Color

/** Independently configurable visual colours for one PteIMUI appearance. */
data class PteIMUIThemePalette(
  val background: Int,
  val surface: Int,
  val composer: Int,
  val incomingBubble: Int,
  val outgoingStart: Int,
  val outgoingEnd: Int,
  val primaryText: Int,
  val secondaryText: Int,
  val incomingText: Int,
  val outgoingText: Int,
  val icon: Int,
  val divider: Int,
  val panel: Int,
  val panelItem: Int,
)

/**
 Keeps light and dark component colours separate. Apps can replace either
 palette without relying on an automatic/inverted dark mode transformation.
 */
data class PteIMUITheme(val light: PteIMUIThemePalette = blueVioletLight(), val dark: PteIMUIThemePalette = blueVioletDark()) {
  companion object {
    fun blueVioletLight() = PteIMUIThemePalette(
      Color.rgb(247, 249, 255), Color.WHITE, Color.WHITE, Color.rgb(237, 241, 253),
      Color.rgb(51, 94, 244), Color.rgb(125, 64, 239), Color.rgb(23, 28, 46), Color.rgb(102, 109, 132),
      Color.rgb(23, 28, 46), Color.WHITE, Color.rgb(55, 62, 90), Color.rgb(221, 226, 242), Color.rgb(244, 246, 255), Color.WHITE,
    )
    fun blueVioletDark() = PteIMUIThemePalette(
      Color.rgb(14, 17, 28), Color.rgb(20, 24, 39), Color.rgb(24, 29, 47), Color.rgb(37, 43, 67),
      Color.rgb(68, 103, 255), Color.rgb(143, 76, 255), Color.rgb(239, 242, 255), Color.rgb(164, 173, 203),
      Color.rgb(239, 242, 255), Color.WHITE, Color.rgb(204, 211, 242), Color.rgb(49, 56, 84), Color.rgb(25, 30, 48), Color.rgb(38, 45, 70),
    )
  }
}

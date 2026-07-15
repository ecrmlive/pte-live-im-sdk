package com.ptelive.im

import android.content.Context
import android.content.res.Configuration

enum class PteIMTheme { LIGHT, DARK }

/** Core is UI-free; a host UI Kit uses this to follow the operating system. */
fun systemTheme(context: Context): PteIMTheme = when (
  context.resources.configuration.uiMode and Configuration.UI_MODE_NIGHT_MASK
) {
  Configuration.UI_MODE_NIGHT_YES -> PteIMTheme.DARK
  else -> PteIMTheme.LIGHT
}

package com.ptelive.im.ui

import android.app.Activity
import android.content.Context
import android.graphics.Color
import android.graphics.drawable.ColorDrawable
import android.graphics.drawable.GradientDrawable
import android.os.Build
import android.view.Gravity
import android.view.View
import android.view.Window
import android.widget.ImageButton
import android.widget.ImageView
import android.widget.LinearLayout
import android.widget.PopupWindow
import android.widget.TextView
import com.ptelive.im.PteIMLanguage
import com.ptelive.im.PteIMSDK
import com.ptelive.im.PteIMThemeMode

/**
 * Shared PteIMUIKit navigation chrome.
 *
 * The visible row is deliberately separate from Android's system status bar,
 * while [applySystemBars] owns the matching status/navigation-bar colours and
 * icon contrast. This keeps the same navigation model usable by an Activity,
 * a Fragment host, and the standalone PteIMUIDemo.
 */
open class PteIMUINavigationBar(
  context: Context,
  private val client: PteIMSDK? = null,
  title: String? = null,
) : LinearLayout(context) {
  var onLanguageSelected: ((PteIMLanguage) -> Unit)? = null
  var onThemeSelected: ((PteIMThemeMode) -> Unit)? = null
  /** Optional secondary-page back action. Supplying it replaces the language control. */
  var onBackRequested: (() -> Unit)? = null
    set(value) { field = value; refreshLeadingControl() }
  /** Hosts can hide language selection while keeping the shared 44 dp navigation geometry. */
  var showLanguageControl: Boolean = true
    set(value) { field = value; refreshLeadingControl() }

  private val backButton = ImageButton(context)
  private val languageButton = TextView(context)
  private val titleView = TextView(context)
  private val appearanceButton = ImageButton(context)
  private var palette = PteIMUITheme.blueVioletLight()
  private var appearance = PteIMThemeMode.LIGHT
  private var language = PteIMLanguage.EN_US

  init {
    orientation = HORIZONTAL
    gravity = Gravity.CENTER_VERTICAL
    minimumHeight = dp(44)
    // The shared navigation grid is 15 dp from each physical screen edge.
    setPadding(dp(15), 0, dp(15), 0)

    languageButton.apply {
      gravity = Gravity.CENTER
      textSize = 14f
      includeFontPadding = false
      setPadding(dp(12), 0, dp(12), 0)
      setOnClickListener { showLanguageMenu() }
    }
    backButton.apply {
      background = null
      contentDescription = "Back"
      scaleType = ImageView.ScaleType.FIT_XY
      setPadding(0, 0, 0, 0)
      setImageResource(R.drawable.pte_im_ui_chat_back)
      setOnClickListener { onBackRequested?.invoke() }
    }
    titleView.apply {
      text = title.orEmpty()
      textSize = 18f
      gravity = Gravity.CENTER
      setSingleLine(true)
    }
    appearanceButton.apply {
      background = null
      contentDescription = "Appearance"
      scaleType = ImageView.ScaleType.CENTER_INSIDE
      setPadding(dp(8), dp(8), dp(8), dp(8))
      setOnClickListener { toggleTheme() }
    }
    addView(backButton, LayoutParams(dp(44), dp(44)))
    addView(languageButton, LayoutParams(dp(122), dp(34)))
    addView(titleView, LayoutParams(0, -1, 1f))
    addView(appearanceButton, LayoutParams(dp(40), dp(40)))
    apply(PteIMUITheme.blueVioletLight(), PteIMThemeMode.LIGHT, PteIMLanguage.EN_US)
  }

  /** Rebind the bar after an SDK appearance callback or host skin update. */
  open fun apply(value: PteIMUIThemePalette, themeMode: PteIMThemeMode, language: PteIMLanguage) {
    palette = value
    appearance = themeMode
    this.language = language
    val dark = isDark(themeMode)
    setBackgroundColor(value.surface)
    languageButton.setTextColor(value.icon)
    titleView.setTextColor(value.primaryText)
    languageButton.text = languageTitle(language)
    languageButton.background = if (dark) rounded(Color.rgb(37, 34, 77), 18) else null
    appearanceButton.background = if (dark) rounded(Color.rgb(34, 32, 68), 20) else null
    appearanceButton.setImageResource(if (dark) R.drawable.pte_im_ui_navigation_theme_dark else R.drawable.pte_im_ui_navigation_theme_light)
    backButton.setColorFilter(if (dark) Color.rgb(242, 244, 255) else value.primaryText)
    refreshLeadingControl()
  }

  /** Lets a host centre a screen title without changing the current-language control. */
  open fun setTitle(value: String?) { titleView.text = value.orEmpty() }

  private fun refreshLeadingControl() {
    backButton.visibility = if (onBackRequested != null) VISIBLE else GONE
    languageButton.visibility = if (showLanguageControl && onBackRequested == null) VISIBLE else GONE
  }

  private fun showLanguageMenu() {
    val dark = isDark(appearance)
    val panel = LinearLayout(context).apply {
      orientation = VERTICAL
      setPadding(dp(6), dp(6), dp(6), dp(6))
      background = rounded(
        if (dark) Color.rgb(24, 23, 53) else Color.WHITE,
        18,
        if (dark) Color.rgb(60, 54, 104) else Color.rgb(231, 226, 250),
      )
    }
    val popup = PopupWindow(panel, dp(184), -2, true).apply {
      isOutsideTouchable = true
      elevation = dp(14).toFloat()
      setBackgroundDrawable(ColorDrawable(Color.TRANSPARENT))
    }
    listOf(
      PteIMLanguage.SYSTEM to "跟随系统",
      PteIMLanguage.ZH_CN to "简体中文",
      PteIMLanguage.EN_US to "English",
    ).forEach { (value, title) ->
      panel.addView(languageItem(value, title, dark) {
        client?.updateAppearance(language = value)
        onLanguageSelected?.invoke(value)
        popup.dismiss()
      }, LayoutParams(-1, dp(44)))
    }
    popup.showAsDropDown(languageButton, 0, dp(8))
  }

  private fun languageItem(value: PteIMLanguage, title: String, dark: Boolean, action: () -> Unit): View =
    LinearLayout(context).apply {
      gravity = Gravity.CENTER_VERTICAL
      setPadding(dp(14), 0, dp(12), 0)
      val selected = value == language
      background = if (selected) rounded(if (dark) Color.rgb(42, 38, 84) else Color.rgb(242, 237, 255), 13) else null
      val text = TextView(context).apply {
        this.text = title
        textSize = 15f
        includeFontPadding = false
        gravity = Gravity.CENTER_VERTICAL
        setTextColor(if (dark) Color.rgb(239, 237, 255) else Color.rgb(37, 35, 63))
      }
      addView(text, LayoutParams(0, -1, 1f))
      if (selected) {
        addView(View(context).apply { background = rounded(Color.rgb(139, 83, 244), 5) }, LayoutParams(dp(10), dp(10)))
      }
      setOnClickListener { action() }
    }

  private fun toggleTheme() {
    val next = if (isDark(appearance)) PteIMThemeMode.LIGHT else PteIMThemeMode.DARK
    client?.updateAppearance(themeMode = next)
    onThemeSelected?.invoke(next)
  }

  private fun isDark(mode: PteIMThemeMode): Boolean = when (mode) {
    PteIMThemeMode.DARK -> true
    PteIMThemeMode.LIGHT -> false
    PteIMThemeMode.SYSTEM -> resources.configuration.uiMode and android.content.res.Configuration.UI_MODE_NIGHT_MASK == android.content.res.Configuration.UI_MODE_NIGHT_YES
  }

  private fun languageTitle(value: PteIMLanguage): String = when (value) {
    PteIMLanguage.ZH_CN -> "简体中文"
    PteIMLanguage.EN_US -> "English"
    PteIMLanguage.SYSTEM -> "跟随系统"
  }

  private fun rounded(fill: Int, radius: Int, stroke: Int = Color.TRANSPARENT): GradientDrawable = GradientDrawable().apply {
    setColor(fill)
    if (stroke != Color.TRANSPARENT) setStroke(dp(1), stroke)
    cornerRadius = dp(radius).toFloat()
  }

  private fun dp(value: Int): Int = (value * resources.displayMetrics.density).toInt()

  companion object {
    /** Applies the navigation skin to the actual Android status and gesture bars. */
    @JvmStatic fun applySystemBars(window: Window, palette: PteIMUIThemePalette, dark: Boolean) {
      // The status bar belongs to the same 44 dp navigation surface on every
      // screen. Keeping it on `surface` prevents a visible horizontal seam
      // between Android chrome and the first navigation row.
      window.statusBarColor = palette.surface
      window.navigationBarColor = palette.surface
      if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
        window.decorView.windowInsetsController?.setSystemBarsAppearance(
          if (dark) 0 else android.view.WindowInsetsController.APPEARANCE_LIGHT_STATUS_BARS or android.view.WindowInsetsController.APPEARANCE_LIGHT_NAVIGATION_BARS,
          android.view.WindowInsetsController.APPEARANCE_LIGHT_STATUS_BARS or android.view.WindowInsetsController.APPEARANCE_LIGHT_NAVIGATION_BARS,
        )
      } else {
        @Suppress("DEPRECATION")
        window.decorView.systemUiVisibility = if (dark) 0 else android.view.View.SYSTEM_UI_FLAG_LIGHT_STATUS_BAR or android.view.View.SYSTEM_UI_FLAG_LIGHT_NAVIGATION_BAR
      }
    }

    /** Convenience for Activity hosts that use the default PteIMUIKit palette. */
    @JvmStatic fun applySystemBars(activity: Activity, palette: PteIMUIThemePalette, dark: Boolean) = applySystemBars(activity.window, palette, dark)
  }
}

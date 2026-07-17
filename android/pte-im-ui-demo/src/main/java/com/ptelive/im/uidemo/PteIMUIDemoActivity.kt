package com.ptelive.im.uidemo

import android.app.Activity
import android.graphics.Color
import android.graphics.drawable.GradientDrawable
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.util.Log
import android.text.InputType
import android.text.method.PasswordTransformationMethod
import android.view.Gravity
import android.view.View
import android.view.ViewGroup
import android.view.WindowInsets
import android.widget.Button
import android.widget.EditText
import android.widget.FrameLayout
import android.widget.ImageView
import android.widget.LinearLayout
import android.widget.ScrollView
import android.widget.Switch
import android.widget.TextView
import com.ptelive.im.PteIMBusinessContent
import com.ptelive.im.PteIMLanguage
import com.ptelive.im.PteIMListener
import com.ptelive.im.PteIMLoginConfig
import com.ptelive.im.PteIMMessageType
import com.ptelive.im.PteIMSDK
import com.ptelive.im.PteIMThemeMode
import com.ptelive.im.ui.PteIMUIAction
import com.ptelive.im.ui.PteIMUIChatView
import com.ptelive.im.ui.PteIMUIContactListMode
import com.ptelive.im.ui.PteIMUINavigationBar
import com.ptelive.im.ui.PteIMUITheme
import com.ptelive.im.ui.PteIMUIThemePalette
import com.ptelive.im.ui.PteIMUIKit
import java.util.Calendar

/**
 * Application-layer sample: [PteIMUIDemoApplication] owns domains at startup;
 * this page receives only the result of a business login (SDKAppID/userId/UserSig).
 */
class PteIMUIDemoActivity : Activity() {
  private val ink = Color.rgb(23, 24, 43)
  private val muted = Color.rgb(101, 105, 130)
  private val canvas = Color.rgb(244, 244, 255)
  private val lavender = Color.rgb(237, 233, 255)
  private val purple = Color.rgb(111, 65, 240)
  private val blue = Color.rgb(55, 108, 246)
  private val darkCanvas = Color.rgb(13, 13, 33)
  private val darkCard = Color.rgb(17, 16, 42)
  private val darkInput = Color.rgb(32, 30, 76)
  private val darkText = Color.rgb(240, 237, 255)
  private val darkMuted = Color.rgb(166, 159, 199)
  private val darkBorder = Color.rgb(57, 52, 90)

  private var client: PteIMSDK? = null
  private var credentialListener: PteIMListener? = null
  private lateinit var sessionStore: PteIMUIDemoSessionStore
  private lateinit var credentialProvider: PteIMUIDemoCredentialProvider
  private var chat: PteIMUIChatView? = null
  private var activeConversationId = ""
  private var activeConversationTitle = ""
  /** A manual value is persisted separately; this is always the resolved display mode. */
  private var darkMode = false
  /** The selected display language is independent from the business login credential. */
  private var selectedLanguage = PteIMLanguage.SYSTEM
  private var activeTab = PteIMUIDemoTab.CHATS
  private var visibleScreen = PteIMUIDemoScreen.LOGIN
  private var languageReturnScreen = PteIMUIDemoScreen.HOME
  private var predictiveBackCallback: android.window.OnBackInvokedCallback? = null
  private val english: Boolean get() = resolvedLanguage() != PteIMLanguage.ZH_CN
  private val appearanceHandler = Handler(Looper.getMainLooper())
  private val automaticThemeRefresh = object : Runnable {
    override fun run() {
      if (sessionStore.manualThemeMode() != null) return
      val oldDarkMode = darkMode
      darkMode = scheduledThemeMode() == PteIMThemeMode.DARK
      if (oldDarkMode != darkMode) redrawForAppearanceChange()
      scheduleAutomaticThemeRefresh()
    }
  }
  private lateinit var userId: EditText
  private lateinit var userSig: EditText
  private lateinit var status: TextView

  private val friends = listOf(PteIMUIDemoFriend("Alice", 10002), PteIMUIDemoFriend("Bob", 10003))

  override fun onCreate(savedInstanceState: Bundle?) {
    super.onCreate(savedInstanceState)
    sessionStore = PteIMUIDemoSessionStore(this)
    resolveAppearancePolicy()
    credentialProvider = PteIMUIDemoCredentialProvider(PteIMUIDemoApplication.baseConfig, sessionStore.deviceId())
    window.statusBarColor = canvas
    window.navigationBarColor = Color.WHITE
    setContentView(loginView())
    if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.TIRAMISU) {
      val callback = android.window.OnBackInvokedCallback { navigateBack() }
      predictiveBackCallback = callback
      onBackInvokedDispatcher.registerOnBackInvokedCallback(
        android.window.OnBackInvokedDispatcher.PRIORITY_DEFAULT,
        callback,
      )
    }
    restoreDemoSession()
  }

  override fun onResume() {
    super.onResume()
    // Re-evaluate the time policy whenever the app returns to foreground. A
    // manually selected theme is never changed by this path.
    val oldDarkMode = darkMode
    if (sessionStore.manualThemeMode() == null) {
      darkMode = scheduledThemeMode() == PteIMThemeMode.DARK
      if (oldDarkMode != darkMode) redrawForAppearanceChange()
      scheduleAutomaticThemeRefresh()
    }
  }

  override fun onPause() {
    appearanceHandler.removeCallbacks(automaticThemeRefresh)
    super.onPause()
  }

  override fun onDestroy() {
    appearanceHandler.removeCallbacks(automaticThemeRefresh)
    if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.TIRAMISU) {
      predictiveBackCallback?.let(onBackInvokedDispatcher::unregisterOnBackInvokedCallback)
    }
    credentialListener?.let { listener -> client?.removeListener(listener) }
    client?.stop()
    super.onDestroy()
  }

  private fun loginView(): View {
    visibleScreen = PteIMUIDemoScreen.LOGIN
    val navigationPalette = loginNavigationPalette()
    PteIMUINavigationBar.applySystemBars(this, navigationPalette, darkMode)
    val root = FrameLayout(this).apply {
      setBackgroundColor(if (darkMode) darkCanvas else canvas)
      clipChildren = false
      clipToPadding = false
    }
    val scroll = ScrollView(this).apply {
      isFillViewport = true
      setBackgroundColor(if (darkMode) darkCanvas else canvas)
      // The supplied login artboard uses a deliberately narrow 28 pt card inset.
      // Keep it here instead of relying on the default Material spacing.
      setPadding(dp(30), dp(12), dp(30), dp(28))
    }
    root.addView(scroll, FrameLayout.LayoutParams(-1, -1))
    val content = LinearLayout(this).apply { orientation = LinearLayout.VERTICAL }
    scroll.addView(content, ViewGroup.LayoutParams(-1, -2))

    // Keep the quiet header space in the scrolling content, but render the
    // actual 44 dp navigation row in the root. It starts immediately below
    // the live system status-bar inset and is never clipped by the form inset.
    content.addView(View(this), lp(-1, dp(138)))
    val header = loginHeader()
    root.addView(header, FrameLayout.LayoutParams(-1, dp(44)))
    root.setOnApplyWindowInsetsListener { _, insets ->
      (header.layoutParams as FrameLayout.LayoutParams).apply {
        topMargin = insets.getInsets(WindowInsets.Type.statusBars()).top
        header.layoutParams = this
      }
      insets
    }
    root.requestApplyInsets()
    // Keep the card fixed while lowering the mark into the position used by the
    // supplied artboard.  The equal-and-opposite margins avoid a device-specific
    // blank gap above the form.
    content.addView(loginBrand(), lp(-1, -2, top = 7, bottom = if (darkMode) 19 else 31))

    val card = LinearLayout(this).apply {
      orientation = LinearLayout.VERTICAL
      setPadding(dp(24), dp(26), dp(24), dp(24))
      background = rounded(if (darkMode) darkCard else Color.WHITE, if (darkMode) darkBorder else Color.TRANSPARENT, 24)
      elevation = if (darkMode) 0f else dp(8).toFloat()
    }
    val appId = credentialField(if (english) "Enter AppID" else "请输入AppID", InputType.TYPE_CLASS_NUMBER).also { if (!darkMode) it.setText("432532532") }
    userId = credentialField(if (english) "Enter user ID" else "请输入用户 ID", InputType.TYPE_CLASS_NUMBER).also { if (!darkMode) it.setText("123654") }
    userSig = credentialField(if (english) "Paste your UserSig token" else "请粘贴 UserSig 令牌", InputType.TYPE_CLASS_TEXT or InputType.TYPE_TEXT_VARIATION_PASSWORD).also {
      it.minLines = 3
      it.gravity = Gravity.TOP
      // UserSig is a multiline value: keep all four inner edges at 10 dp.
      it.setPadding(dp(10), dp(10), dp(10), dp(10))
    }
    status = label("").apply { textSize = 12f; gravity = Gravity.CENTER; setTextColor(Color.rgb(190, 55, 70)); visibility = View.GONE }
    card.addView(formLabel("SDKAppID")); card.addView(appId, lp(-1, dp(46), bottom = 10))
    card.addView(formLabel(if (english) "User ID" else "用户 ID")); card.addView(userId, lp(-1, dp(46), bottom = 10))
    card.addView(formLabel(if (english) "User Signature (UserSig)" else "用户签名（UserSig）")); card.addView(userSig, lp(-1, dp(82)))
    card.addView(View(this), lp(-1, dp(63)))
    card.addView(gradientButton(if (english) "Login" else "登录") { login(appId.text.toString()) }, lp(-1, dp(50)))
    card.addView(status, lp(-1, -2, top = 12))
    content.addView(card)
    return root
  }

  private fun loginHeader(): View = PteIMUINavigationBar(this).apply {
    apply(loginNavigationPalette(), if (darkMode) PteIMThemeMode.DARK else PteIMThemeMode.LIGHT, selectedLanguage)
    onLanguageSelected = { language ->
      applyLanguageSelection(language)
      setContentView(loginView())
    }
    onThemeSelected = { mode ->
      applyThemeSelection(mode)
      setContentView(loginView())
    }
  }

  private fun loginNavigationPalette(): PteIMUIThemePalette {
    val base = if (darkMode) PteIMUITheme.blueVioletDark() else PteIMUITheme.blueVioletLight()
    return base.copy(
      background = if (darkMode) darkCanvas else canvas,
      surface = if (darkMode) darkCanvas else canvas,
      icon = if (darkMode) Color.rgb(204, 211, 242) else muted,
    )
  }

  private fun loginBrand(): View = LinearLayout(this).apply {
    orientation = LinearLayout.VERTICAL; gravity = Gravity.CENTER_HORIZONTAL
    addView(ImageView(this@PteIMUIDemoActivity).apply { setImageResource(R.drawable.pte_im_ui_logo); scaleType = ImageView.ScaleType.FIT_XY }, lp(dp(103), dp(103)))
    addView(label(if (english) "PrivateChat" else "私域").apply { textSize = 29f; typeface = android.graphics.Typeface.DEFAULT_BOLD; gravity = Gravity.CENTER; setTextColor(if (darkMode) darkText else ink) }, lp(-1, -2, top = 34))
    addView(label(if (english) "Secure · Private · Efficient" else "安全 · 私密 · 高效通讯").apply { textSize = 14f; gravity = Gravity.CENTER; setTextColor(if (darkMode) darkMuted else muted) }, lp(-1, -2, top = 12))
  }

  private fun login(sdkAppId: String) {
    val id = userId.text.toString().trim()
    val sig = userSig.text.toString().trim()
    if (id.toLongOrNull() == null || sig.isBlank()) {
      status.text = "业务后端应返回有效的 userId 与短期 UserSig"; status.visibility = View.VISIBLE; return
    }
    runCatching {
      PteIMUIDemoCredential(sdkAppId.toLongOrNull() ?: 0, id.toLong(), sig, 0)
    }.onSuccess { credential -> startSession(credential, restore = false) }
      .onFailure { error -> status.text = "IM 登录失败：${error.message}"; status.visibility = View.VISIBLE }
  }

  /**
   * Reissues a fresh server credential on every Debug launch. Only user ID and
   * an explicit-logout flag are stored; UserSig never leaves process memory.
   */
  private fun restoreDemoSession() {
    if (!BuildConfig.DEBUG || !sessionStore.shouldRestore()) return
    Thread {
      runCatching { credentialProvider.issue(sessionStore.userId()) }
        .onSuccess { credential -> runOnUiThread { startSession(credential, restore = true) } }
        .onFailure { error -> runOnUiThread {
          // A visual-acceptance build remains inspectable without the local
          // Docker stack. This client is intentionally offline-only: it has
          // no persisted UserSig and the isolated review conversation never
          // queues a message to the IM service. A real business credential
          // always takes precedence as soon as api-im is reachable again.
          Log.w("PteIMUIDemo", "local test account unavailable; opening offline UI fixture", error)
          startSession(
            PteIMUIDemoCredential(
              sdkAppId = 432_532_532L,
              userId = PteIMUIDemoSessionStore.demoPrimaryUserId,
              userSig = "offline-ui-review-session",
              expiresAt = 0,
            ),
            restore = true,
          )
        } }
    }.apply { name = "PteIMUIDemoRestore" }.start()
  }

  private fun startSession(credential: PteIMUIDemoCredential, restore: Boolean) {
    credentialListener?.let { listener -> client?.removeListener(listener) }
    client?.stop()
    runCatching {
      PteIMUIDemoApplication.bootstrap.login(
        PteIMLoginConfig(credential.sdkAppId, credential.userId.toString(), credential.userSig),
      )
    }.onSuccess { value ->
      client = value
      value.updateAppearance(themeMode = resolvedThemeMode(), language = selectedLanguage)
      sessionStore.markLoggedIn(credential.userId)
      attachCredentialLifecycle(value, credential)
      if (BuildConfig.DEBUG) {
        // The Debug package is a visual acceptance app: it always creates a
        // short-lived local session then lands directly on the complete chat
        // fixture. Release continues through the business home flow.
        seedDemoData(value, credential)
        openChat(PteIMUIDemoChatView.reviewConversationId, "Work Team 工作群")
      } else {
        setContentView(homeView())
      }
    }.onFailure { error ->
      status.text = "IM 登录失败：${error.message}"
      status.visibility = View.VISIBLE
    }
  }

  private fun attachCredentialLifecycle(value: PteIMSDK, credential: PteIMUIDemoCredential) {
    credentialListener = object : PteIMListener {
      override fun onUserSigWillExpire() = refreshUserSig(value, credential.userId)
      override fun onUserSigExpired() = refreshUserSig(value, credential.userId)
    }.also(value::addListener)
  }

  private fun refreshUserSig(value: PteIMSDK, userId: Long) {
    if (!BuildConfig.DEBUG) return
    Thread {
      runCatching { credentialProvider.issue(userId) }
        .onSuccess { fresh -> value.renewUserSig(fresh.userSig) }
    }.apply { name = "PteIMUIDemoRenew" }.start()
  }

  private fun seedDemoData(value: PteIMSDK, credential: PteIMUIDemoCredential) {
    if (sessionStore.seeded()) {
      value.syncConversationsNow()
      return
    }
    Thread {
      runCatching { credentialProvider.seed(credential) }
        .onSuccess {
          sessionStore.markSeeded()
          value.syncConversationsNow()
        }
        .onFailure { error -> Log.w("PteIMUIDemo", "server-backed demo seed failed", error) }
    }.apply { name = "PteIMUIDemoSeed" }.start()
  }

  private fun homeView(selected: PteIMUIDemoTab = PteIMUIDemoTab.CHATS): View {
    visibleScreen = PteIMUIDemoScreen.HOME
    activeTab = selected
    val palette = if (darkMode) PteIMUITheme.blueVioletDark() else PteIMUITheme.blueVioletLight()
    PteIMUINavigationBar.applySystemBars(this, palette, darkMode)
    val root = LinearLayout(this).apply {
      orientation = LinearLayout.VERTICAL
      setBackgroundColor(palette.background)
      setOnApplyWindowInsetsListener { view, insets ->
        view.setPadding(0, insets.getInsets(WindowInsets.Type.statusBars()).top, 0, 0)
        insets
      }
    }
    root.requestApplyInsets()
    val content = FrameLayout(this)
    root.addView(content, LinearLayout.LayoutParams(-1, 0, 1f))
    root.addView(tabBar(selected), lp(-1, dp(60)))
    val screen = when (selected) {
      PteIMUIDemoTab.CHATS -> conversationScreen()
      PteIMUIDemoTab.CONTACTS -> contactsScreen()
      PteIMUIDemoTab.ME -> profileScreen()
    }
    content.addView(screen, FrameLayout.LayoutParams(-1, -1))
    return root
  }

  private val chatTitles = mutableMapOf<String, String>()

  private fun conversationScreen(): View {
    val value = client ?: return View(this)
    return PteIMUIKit.createConversationListView(this, value) { id -> openChat(id, chatTitles[id] ?: "Work Team 工作群") }.apply {
      onCreateConversation = ::openDemoGroupChat
      presentationTransformer = { item, index -> demoConversationPresentation(item, index) }
      maxVisibleConversations = 6
    }
  }

  /** Demo-only display content; the original conversation ID stays unchanged for navigation. */
  private fun demoConversationPresentation(item: com.ptelive.im.ui.PteIMUIConversationPresentation, index: Int): com.ptelive.im.ui.PteIMUIConversationPresentation {
    val samples = listOf(
      Triple("Alice Chen", "明天见！See you tomorrow!", "10:24") to Pair(2L, true),
      Triple("Work Team 工作群", "[图片] [Image]", "09:51") to Pair(5L, false),
      Triple("Bob Li", "[语音] 12秒", "昨天") to Pair(0L, false),
      Triple("Project Alpha", "收到，我来处理 Got it", "昨天") to Pair(0L, false),
      Triple("Carol Wu", "[红包] 恭喜发财", "周一") to Pair(0L, true),
      Triple("Dave Zhang", "[订单] iPhone 15 Pro", "周日") to Pair(0L, false),
    )
    val sample = samples.getOrNull(index) ?: return item
    chatTitles[item.conversationId] = sample.first.first
    return item.copy(title = sample.first.first, preview = sample.first.second, timeText = sample.first.third, unreadCount = sample.second.first, avatarText = sample.first.first.take(1), isOnline = sample.second.second)
  }

  private fun contactsScreen(): View {
    val value = client ?: return View(this)
    val wrap = LinearLayout(this).apply { orientation = LinearLayout.VERTICAL; setBackgroundColor(canvas) }
    val actions = LinearLayout(this).apply { gravity = Gravity.CENTER; setPadding(dp(18), dp(10), dp(18), dp(10)); background = rounded(Color.WHITE, Color.TRANSPARENT, 0) }
    actions.addView(quickButton("添加好友") { businessNotice("添加好友") }, LinearLayout.LayoutParams(0, dp(42), 1f).apply { marginEnd = dp(8) })
    actions.addView(quickButton("发起群聊") { openDemoGroupChat() }, LinearLayout.LayoutParams(0, dp(42), 1f).apply { marginStart = dp(8) })
    wrap.addView(actions)
    wrap.addView(
      PteIMUIKit.createContactListView(this, value, PteIMUIContactListMode.FRIENDS) { id, title -> openChat(id, title) }.apply {
        onLoadError = { error -> Log.w("PteIMUIDemo", "server-backed demo contacts failed", error) }
      },
      LinearLayout.LayoutParams(-1, 0, 1f),
    )
    return wrap
  }

  private fun profileScreen(): View {
    val value = client ?: return View(this)
    val palette = if (darkMode) PteIMUITheme.blueVioletDark() else PteIMUITheme.blueVioletLight()
    val scroll = ScrollView(this).apply { setBackgroundColor(palette.background) }
    val content = LinearLayout(this).apply { orientation = LinearLayout.VERTICAL }
    scroll.addView(content)
    content.addView(profileNavigationBar(), lp(-1, dp(44)))
    content.addView(profileBanner(value.currentUserId()), lp(-1, dp(112)))
    content.addView(profileShortcuts())
    val settings = LinearLayout(this).apply { orientation = LinearLayout.VERTICAL; setPadding(dp(20), dp(16), dp(20), dp(10)) }
    settings.addView(profileSettingRow(
      R.drawable.pte_im_ui_demo_me_theme,
      if (english) if (darkMode) "Dark Mode" else "Light Mode" else if (darkMode) "深色模式" else "浅色模式",
      switchImage(darkMode),
    ) { applyThemeSelection(if (darkMode) PteIMThemeMode.LIGHT else PteIMThemeMode.DARK); setContentView(homeView(PteIMUIDemoTab.ME)) })
    settings.addView(profileDivider())
    settings.addView(profileSettingRow(
      R.drawable.pte_im_ui_demo_me_language,
      if (english) "Language" else "语言",
      languageBadgeView(),
    ) { openLanguageSettings(PteIMUIDemoScreen.HOME) })
    settings.addView(profileDivider())
    settings.addView(profileSettingRow(R.drawable.pte_im_ui_demo_me_notifications, if (english) "Notifications" else "通知设置", arrowView()))
    settings.addView(profileDivider())
    settings.addView(profileSettingRow(R.drawable.pte_im_ui_demo_me_privacy, if (english) "Privacy & Security" else "隐私与安全", arrowView()))
    settings.addView(profileDivider())
    settings.addView(profileSettingRow(R.drawable.pte_im_ui_demo_me_help, if (english) "Help & Feedback" else "帮助与反馈", arrowView()))
    settings.addView(profileDivider())
    settings.addView(profileSettingRow(R.drawable.pte_im_ui_demo_me_settings, if (english) "Settings" else "设置", arrowView()) { openSettings() })
    content.addView(settings)
    content.addView(logoutButton(), lp(-1, dp(48), left = 20, right = 20, top = 4, bottom = 32))
    return scroll
  }

  private fun profileBanner(id: String): View = LinearLayout(this).apply {
    gravity = Gravity.CENTER_VERTICAL; setPadding(dp(20), 0, dp(22), 0)
    background = if (darkMode) rounded(Color.rgb(15, 20, 53), Color.TRANSPARENT, 0) else gradient(Color.rgb(225, 224, 255), Color.rgb(213, 232, 255), 0)
    val avatar = FrameLayout(this@PteIMUIDemoActivity)
    avatar.addView(label(if (english) "ME" else "我").apply { gravity = Gravity.CENTER; textSize = 22f; typeface = android.graphics.Typeface.DEFAULT_BOLD; setTextColor(Color.WHITE); background = gradient(blue, purple, 18) }, FrameLayout.LayoutParams(dp(64), dp(64)))
    avatar.addView(View(this@PteIMUIDemoActivity).apply { background = rounded(Color.rgb(23, 205, 90), Color.WHITE, 8) }, FrameLayout.LayoutParams(dp(16), dp(16), Gravity.BOTTOM or Gravity.END))
    addView(avatar, lp(dp(64), dp(64)))
    val text = LinearLayout(this@PteIMUIDemoActivity).apply { orientation = LinearLayout.VERTICAL; setPadding(dp(16), 0, 0, 0); addView(label("User_$id").apply { textSize = 17f; typeface = android.graphics.Typeface.DEFAULT_BOLD; setTextColor(if (darkMode) darkText else ink) }); addView(label("ID: usr_$id").apply { textSize = 11f; setTextColor(if (darkMode) darkMuted else muted) }, lp(-2, -2, top = 5)) }
    addView(text, LinearLayout.LayoutParams(0, -2, 1f)); addView(arrowView())
  }

  private fun profileShortcuts(): View = LinearLayout(this).apply {
    gravity = Gravity.CENTER; background = rounded(if (darkMode) darkCard else Color.WHITE, Color.TRANSPARENT, 0)
    listOf(
      Triple(R.drawable.pte_im_ui_demo_me_favorites, "12", if (english) "Favorites" else "我的收藏"),
      Triple(R.drawable.pte_im_ui_demo_me_wallet, "¥88", if (english) "Wallet" else "我的钱包"),
      Triple(R.drawable.pte_im_ui_demo_me_qr, "", if (english) "QR Card" else "二维码名片"),
    ).forEach { item ->
      addView(LinearLayout(this@PteIMUIDemoActivity).apply {
        orientation = LinearLayout.VERTICAL; gravity = Gravity.CENTER
        addView(icon(item.first, 24), LinearLayout.LayoutParams(dp(24), dp(24)))
        addView(label(item.second).apply { textSize = 13f; gravity = Gravity.CENTER; setTextColor(if (darkMode) darkText else ink) }, LinearLayout.LayoutParams(-1, dp(18)).apply { topMargin = dp(5) })
        addView(label(item.third).apply { textSize = 10f; gravity = Gravity.CENTER; setTextColor(if (darkMode) darkMuted else muted) }, LinearLayout.LayoutParams(-1, dp(16)))
      }, LinearLayout.LayoutParams(0, dp(94), 1f))
    }
  }

  private fun profileNavigationBar(): View = LinearLayout(this).apply {
    val palette = if (darkMode) PteIMUITheme.blueVioletDark() else PteIMUITheme.blueVioletLight()
    gravity = Gravity.CENTER_VERTICAL; setPadding(dp(20), 0, dp(20), 0); setBackgroundColor(palette.surface)
    addView(ImageView(this@PteIMUIDemoActivity).apply { setImageResource(R.drawable.pte_im_ui_logo); scaleType = ImageView.ScaleType.FIT_CENTER }, LinearLayout.LayoutParams(dp(30), dp(30)))
    addView(label(if (english) "Me" else "我的").apply { textSize = 18f; typeface = android.graphics.Typeface.DEFAULT_BOLD; setTextColor(if (darkMode) darkText else ink); gravity = Gravity.CENTER_VERTICAL; setPadding(dp(8), 0, 0, 0) }, LinearLayout.LayoutParams(0, -1, 1f))
  }

  private fun profileSettingRow(icon: Int, title: String, accessory: View, action: (() -> Unit)? = null): View = LinearLayout(this).apply {
    gravity = Gravity.CENTER_VERTICAL; minimumHeight = dp(54)
    addView(icon(icon, 22), LinearLayout.LayoutParams(dp(22), dp(22)).apply { marginEnd = dp(14) })
    addView(label(title).apply { textSize = 15f; setTextColor(if (darkMode) darkText else ink); gravity = Gravity.CENTER_VERTICAL }, LinearLayout.LayoutParams(0, -1, 1f))
    addView(accessory)
    if (action != null) { isClickable = true; isFocusable = true; setOnClickListener { action() } }
  }

  private fun profileDivider(): View = View(this).apply {
    setBackgroundColor(if (darkMode) Color.rgb(35, 32, 68) else Color.rgb(230, 228, 246))
    layoutParams = LinearLayout.LayoutParams(-1, dp(1))
  }

  private fun languageBadge(): String = when (selectedLanguage) { PteIMLanguage.ZH_CN -> "简体中文"; PteIMLanguage.EN_US -> "English"; PteIMLanguage.SYSTEM -> if (english) "Follow system" else "跟随系统" }
  private fun languageBadgeView(): View = label(if (selectedLanguage == PteIMLanguage.ZH_CN) "中文" else if (selectedLanguage == PteIMLanguage.EN_US) "EN" else if (english) "System" else "系统").apply {
    textSize = 12f; gravity = Gravity.CENTER; setTextColor(purple); background = rounded(if (darkMode) Color.rgb(42, 35, 83) else Color.rgb(235, 229, 255), Color.TRANSPARENT, 15); setPadding(dp(12), 0, dp(12), 0)
  }
  private fun arrowView(): ImageView = icon(R.drawable.pte_im_ui_demo_arrow, 16).apply { setColorFilter(if (darkMode) darkMuted else muted) }
  private fun switchImage(on: Boolean): ImageView = icon(if (on) R.drawable.pte_im_ui_demo_toggle_on else R.drawable.pte_im_ui_demo_toggle_off, 48)
  private fun icon(resource: Int, size: Int): ImageView = ImageView(this).apply { setImageResource(resource); scaleType = ImageView.ScaleType.FIT_CENTER }

  private fun openSettings() { visibleScreen = PteIMUIDemoScreen.SETTINGS; setContentView(settingsScreen()) }
  private fun openLanguageSettings(returnTo: PteIMUIDemoScreen) { languageReturnScreen = returnTo; visibleScreen = PteIMUIDemoScreen.LANGUAGE; setContentView(languageSettingsScreen()) }

  private fun settingsScreen(): View {
    visibleScreen = PteIMUIDemoScreen.SETTINGS
    val palette = if (darkMode) PteIMUITheme.blueVioletDark() else PteIMUITheme.blueVioletLight()
    PteIMUINavigationBar.applySystemBars(this, palette, darkMode)
    return ScrollView(this).apply {
      setBackgroundColor(palette.background)
      setOnApplyWindowInsetsListener { view, insets ->
        view.setPadding(0, insets.getInsets(WindowInsets.Type.statusBars()).top, 0, 0)
        insets
      }
      requestApplyInsets()
      addView(LinearLayout(this@PteIMUIDemoActivity).apply {
        orientation = LinearLayout.VERTICAL
        addView(pageNavigation(if (english) "Settings" else "设置") { setContentView(homeView(PteIMUIDemoTab.ME)) }, lp(-1, dp(44)))
        addView(settingsSection(if (english) "APPEARANCE · 外观" else "外观 · 外观", listOf(
          settingsRow(R.drawable.pte_im_ui_demo_me_theme, if (english) "Light Mode" else "深色模式", if (english) if (darkMode) "Dark" else "Light" else if (darkMode) "深色" else "浅色", switchImage(darkMode)) { applyThemeSelection(if (darkMode) PteIMThemeMode.LIGHT else PteIMThemeMode.DARK); setContentView(settingsScreen()) },
          settingsRow(R.drawable.pte_im_ui_demo_me_language, if (english) "Language" else "语言", languageBadge(), languageBadgeView()) { openLanguageSettings(PteIMUIDemoScreen.SETTINGS) },
        )), lp(-1, -2, left = 20, right = 20, top = 18))
        addView(settingsSection(if (english) "NOTIFICATIONS · 通知" else "通知 · 通知", listOf(
          settingsRow(R.drawable.pte_im_ui_demo_me_notifications, if (english) "Notifications" else "通知设置", if (english) "Push notifications" else "推送通知 Push", switchImage(true)),
          settingsRow(R.drawable.pte_im_ui_demo_settings_sound, if (english) "Sound" else "声音", if (english) "Message alert sound" else "消息提示音 Sound", switchImage(true)),
          settingsRow(R.drawable.pte_im_ui_demo_settings_receipts, if (english) "Read Receipts" else "已读回执", if (english) "Read Receipts" else "已读回执 Receipts", switchImage(true)),
        )), lp(-1, -2, left = 20, right = 20, top = 16))
        addView(settingsSection(if (english) "PRIVACY & SECURITY · 隐私" else "隐私与安全 · 隐私", listOf(
          settingsRow(R.drawable.pte_im_ui_demo_me_privacy, if (english) "Privacy & Security" else "隐私与安全", if (english) "Privacy settings" else "隐私设置", arrowView()),
          settingsRow(R.drawable.pte_im_ui_demo_settings_account, if (english) "Account" else "账号管理", if (english) "Account management" else "账号管理", arrowView()),
          settingsRow(R.drawable.pte_im_ui_demo_me_help, if (english) "Help & Feedback" else "帮助与反馈", if (english) "Help center" else "帮助中心", arrowView()),
          settingsRow(R.drawable.pte_im_ui_demo_settings_about, if (english) "About" else "关于", "v2.4.1", arrowView()),
        )), lp(-1, -2, left = 20, right = 20, top = 16))
        addView(label(if (english) "PrivateChat v1.0.0\n© 2026 PrivateChat Inc." else "私域 v1.0.0\n© 2026 私域直播").apply { gravity = Gravity.CENTER; textSize = 11f; setTextColor(if (darkMode) darkMuted else muted); setLineSpacing(dp(4).toFloat(), 1f) }, lp(-1, -2, top = 28, bottom = 24))
      }, ViewGroup.LayoutParams(-1, -2))
    }
  }

  private fun languageSettingsScreen(): View {
    visibleScreen = PteIMUIDemoScreen.LANGUAGE
    val palette = if (darkMode) PteIMUITheme.blueVioletDark() else PteIMUITheme.blueVioletLight()
    PteIMUINavigationBar.applySystemBars(this, palette, darkMode)
    return LinearLayout(this).apply {
      orientation = LinearLayout.VERTICAL; setBackgroundColor(palette.background)
      setOnApplyWindowInsetsListener { view, insets ->
        view.setPadding(0, insets.getInsets(WindowInsets.Type.statusBars()).top, 0, 0)
        insets
      }
      requestApplyInsets()
      addView(pageNavigation(if (english) "Language" else "语言") { returnFromLanguageSettings() }, lp(-1, dp(44)))
      addView(label(if (english) "Choose app language" else "选择应用语言").apply { textSize = 13f; setTextColor(if (darkMode) darkMuted else muted); setPadding(dp(20), dp(24), dp(20), dp(10)) }, lp(-1, -2))
      val choices = listOf(PteIMLanguage.SYSTEM to (if (english) "Follow system" else "跟随系统"), PteIMLanguage.ZH_CN to "简体中文", PteIMLanguage.EN_US to "English")
      val card = LinearLayout(this@PteIMUIDemoActivity).apply { orientation = LinearLayout.VERTICAL; background = rounded(if (darkMode) darkCard else Color.WHITE, if (darkMode) darkBorder else Color.TRANSPARENT, 18); setPadding(0, dp(4), 0, dp(4)) }
      choices.forEachIndexed { index, (language, title) ->
        card.addView(languageChoiceRow(language, title) { applyLanguageSelection(language); setContentView(languageSettingsScreen()) }, LinearLayout.LayoutParams(-1, dp(58)))
        if (index < choices.lastIndex) card.addView(View(this@PteIMUIDemoActivity).apply { setBackgroundColor(if (darkMode) darkBorder else Color.rgb(231, 226, 250)) }, LinearLayout.LayoutParams(-1, dp(1)).apply { leftMargin = dp(56) })
      }
      addView(card, lp(-1, -2, left = 20, right = 20))
    }
  }

  private fun pageNavigation(title: String, back: () -> Unit): View = LinearLayout(this).apply {
    val palette = if (darkMode) PteIMUITheme.blueVioletDark() else PteIMUITheme.blueVioletLight()
    gravity = Gravity.CENTER_VERTICAL; setPadding(dp(15), 0, dp(15), 0); setBackgroundColor(palette.surface)
    addView(icon(R.drawable.pte_im_ui_demo_back, 28).apply { setColorFilter(if (darkMode) darkText else ink); setPadding(dp(6), dp(6), dp(6), dp(6)); setOnClickListener { back() } }, LinearLayout.LayoutParams(dp(44), dp(44)))
    addView(label(title).apply { textSize = 18f; typeface = android.graphics.Typeface.DEFAULT_BOLD; setTextColor(if (darkMode) darkText else ink); gravity = Gravity.CENTER_VERTICAL }, LinearLayout.LayoutParams(0, -1, 1f))
  }

  private fun settingsSection(title: String, rows: List<View>): View = LinearLayout(this).apply {
    orientation = LinearLayout.VERTICAL; background = rounded(if (darkMode) darkCard else Color.WHITE, if (darkMode) darkBorder else Color.TRANSPARENT, 18)
    addView(label(title).apply { textSize = 11f; typeface = android.graphics.Typeface.DEFAULT_BOLD; setTextColor(if (darkMode) darkMuted else muted); gravity = Gravity.CENTER_VERTICAL; setPadding(dp(16), 0, dp(16), 0) }, LinearLayout.LayoutParams(-1, dp(40)))
    rows.forEach { row ->
      addView(View(this@PteIMUIDemoActivity).apply { setBackgroundColor(if (darkMode) darkBorder else Color.rgb(231, 226, 250)) }, LinearLayout.LayoutParams(-1, dp(1)))
      addView(row, LinearLayout.LayoutParams(-1, dp(68)))
    }
  }

  private fun settingsRow(icon: Int, title: String, subtitle: String, accessory: View, action: (() -> Unit)? = null): View = LinearLayout(this).apply {
    gravity = Gravity.CENTER_VERTICAL; setPadding(dp(16), 0, dp(16), 0)
    addView(icon(icon, 22), LinearLayout.LayoutParams(dp(22), dp(22)).apply { marginEnd = dp(12) })
    addView(LinearLayout(this@PteIMUIDemoActivity).apply {
      orientation = LinearLayout.VERTICAL; gravity = Gravity.CENTER_VERTICAL
      addView(label(title).apply { textSize = 14f; typeface = android.graphics.Typeface.DEFAULT_BOLD; setTextColor(if (darkMode) darkText else ink) })
      addView(label(subtitle).apply { textSize = 11f; setTextColor(if (darkMode) darkMuted else muted); setPadding(0, dp(4), 0, 0) })
    }, LinearLayout.LayoutParams(0, -1, 1f))
    addView(accessory)
    if (action != null) { isClickable = true; isFocusable = true; setOnClickListener { action() } }
  }

  private fun languageChoiceRow(value: PteIMLanguage, title: String, action: () -> Unit): View = LinearLayout(this).apply {
    gravity = Gravity.CENTER_VERTICAL; setPadding(dp(16), 0, dp(16), 0); isClickable = true; isFocusable = true; setOnClickListener { action() }
    addView(label(title).apply { textSize = 16f; setTextColor(if (darkMode) darkText else ink); gravity = Gravity.CENTER_VERTICAL }, LinearLayout.LayoutParams(0, -1, 1f))
    addView(icon(if (selectedLanguage == value) R.drawable.pte_im_ui_demo_check_selected else R.drawable.pte_im_ui_demo_check_unselected, 24), LinearLayout.LayoutParams(dp(24), dp(24)))
  }

  private fun returnFromLanguageSettings() {
    when (languageReturnScreen) {
      PteIMUIDemoScreen.SETTINGS -> setContentView(settingsScreen())
      else -> setContentView(homeView(PteIMUIDemoTab.ME))
    }
  }

  private fun logoutButton(): View = LinearLayout(this).apply {
    gravity = Gravity.CENTER; isClickable = true; isFocusable = true; background = rounded(if (darkMode) Color.rgb(54, 18, 36) else Color.rgb(255, 233, 235), Color.TRANSPARENT, 16)
    addView(icon(R.drawable.pte_im_ui_demo_me_logout, 20), LinearLayout.LayoutParams(dp(20), dp(20)).apply { marginEnd = dp(8) })
    addView(label(if (english) "Log Out" else "退出登录").apply { textSize = 15f; typeface = android.graphics.Typeface.DEFAULT_BOLD; setTextColor(Color.rgb(225, 52, 68)) })
    setOnClickListener {
      credentialListener?.let { listener -> client?.removeListener(listener) }
      client?.stop(); client = null; sessionStore.markLoggedOut(); setContentView(loginView())
    }
  }

  private fun tabBar(selected: PteIMUIDemoTab): View = LinearLayout(this).apply {
    val palette = if (darkMode) PteIMUITheme.blueVioletDark() else PteIMUITheme.blueVioletLight()
    gravity = Gravity.CENTER; setPadding(dp(14), dp(3), dp(14), dp(5)); background = rounded(palette.surface, palette.divider, 0)
    listOf(
      Triple(PteIMUIDemoTab.CHATS, if (english) "Chats" else "会话", com.ptelive.im.ui.R.drawable.pte_im_ui_tab_chats_selected),
      Triple(PteIMUIDemoTab.CONTACTS, if (english) "Contacts" else "联系人", com.ptelive.im.ui.R.drawable.pte_im_ui_tab_contacts_unselected),
      Triple(PteIMUIDemoTab.ME, if (english) "Me" else "我的", com.ptelive.im.ui.R.drawable.pte_im_ui_tab_me_unselected),
    ).forEach { (tab, title, icon) ->
      addView(LinearLayout(this@PteIMUIDemoActivity).apply {
        orientation = LinearLayout.VERTICAL; gravity = Gravity.CENTER; isClickable = true; isFocusable = true; setOnClickListener { setContentView(homeView(tab)) }
        addView(FrameLayout(this@PteIMUIDemoActivity).apply {
          // The supplied tab image has transparent side padding. Reserve a wider
          // hit frame so the unread badge stays fully visible beside the artwork.
          addView(ImageView(this@PteIMUIDemoActivity).apply { setImageResource(icon); scaleType = ImageView.ScaleType.FIT_CENTER; setColorFilter(if (selected == tab) purple else palette.icon) }, FrameLayout.LayoutParams(dp(21), dp(21), Gravity.CENTER))
          if (tab == PteIMUIDemoTab.CHATS) addView(label("7").apply { textSize = 9f; gravity = Gravity.CENTER; setTextColor(Color.WHITE); background = rounded(Color.rgb(239, 49, 59), Color.TRANSPARENT, 8) }, FrameLayout.LayoutParams(dp(16), dp(16), Gravity.TOP or Gravity.END))
        }, LinearLayout.LayoutParams(dp(40), dp(24)))
        addView(label(title).apply { textSize = 10f; typeface = if (selected == tab) android.graphics.Typeface.DEFAULT_BOLD else android.graphics.Typeface.DEFAULT; gravity = Gravity.CENTER; setTextColor(if (selected == tab) purple else palette.secondaryText) }, LinearLayout.LayoutParams(-1, dp(18)))
      }, LinearLayout.LayoutParams(0, dp(50), 1f))
    }
  }

  private fun openChat(id: String, title: String) {
    val value = client ?: return
    activeConversationId = id
    activeConversationTitle = title
    chat = PteIMUIDemoChatView(this, value, id, title).also {
      it.navigationSubtitleText = if (title.contains("群") || title.contains("Team")) if (english) "8 members" else "8 位成员" else if (english) "Online" else "在线"
      it.onBackRequested = { navigateBack() }
      it.onVoiceCallRequested = { businessNotice(if (english) "Voice call" else "语音通话") }
      it.onVideoCallRequested = { businessNotice(if (english) "Video call" else "视频通话") }
      it.onMoreRequested = { businessNotice(if (english) "Conversation settings" else "会话设置") }
      it.onActionRequested = ::handleAction
      it.onAttachmentError = { error ->
        businessNotice(error.message ?: if (english) "Attachment failed" else "附件发送失败")
      }
      // UIKit owns the visible recording state. A production embedding can
      // connect this callback to its recorder without changing the UI kit.
      it.onVoiceRecordingChanged = { }
      it.onVoiceRecordingCancelled = { }
      it.onMessageActionRequested = { action, _ -> businessNotice(action.name) }
      it.receiptStatusProvider = { message ->
        when (message.type) {
          PteIMMessageType.RED_PACKET -> com.ptelive.im.ui.PteIMUIReceiptStatus.UNREAD
          else -> com.ptelive.im.ui.PteIMUIReceiptStatus.READ
        }
      }
      it.setTheme(PteIMUITheme())
    }
    visibleScreen = PteIMUIDemoScreen.CHAT
    setContentView(chatScreen(chat ?: return))
  }

  /** The status bar uses the exact same surface as the PteIMUIChat navigation row. */
  private fun chatScreen(chatView: PteIMUIChatView): View {
    val base = if (darkMode) PteIMUITheme.blueVioletDark() else PteIMUITheme.blueVioletLight()
    val systemPalette = base.copy(background = base.surface)
    PteIMUINavigationBar.applySystemBars(this, systemPalette, darkMode)
    return FrameLayout(this).apply {
      setBackgroundColor(base.surface)
      addView(chatView, FrameLayout.LayoutParams(-1, -1))
      setOnApplyWindowInsetsListener { _, insets ->
        (chatView.layoutParams as FrameLayout.LayoutParams).apply {
          topMargin = insets.getInsets(WindowInsets.Type.statusBars()).top
          // Android 15 edge-to-edge does not resize this host automatically.
          // The explicit IME inset keeps the 40dp composer directly above the
          // keyboard rather than letting it disappear beneath the keyboard.
          bottomMargin = insets.getInsets(WindowInsets.Type.ime()).bottom
          chatView.layoutParams = this
        }
        insets
      }
      requestApplyInsets()
    }
  }

  /** Resolves startup preferences without writing a value for the automatic cases. */
  private fun resolveAppearancePolicy() {
    darkMode = resolvedThemeMode() == PteIMThemeMode.DARK
    selectedLanguage = sessionStore.manualLanguage() ?: PteIMLanguage.SYSTEM
  }

  private fun resolvedThemeMode(): PteIMThemeMode = sessionStore.manualThemeMode() ?: scheduledThemeMode()

  /** Light from 07:00 inclusive to 19:00 exclusive; dark for every other local time. */
  private fun scheduledThemeMode(hour: Int = Calendar.getInstance().get(Calendar.HOUR_OF_DAY)): PteIMThemeMode =
    if (hour in 7..18) PteIMThemeMode.LIGHT else PteIMThemeMode.DARK

  private fun resolvedLanguage(): PteIMLanguage = when (selectedLanguage) {
    PteIMLanguage.SYSTEM -> if (resources.configuration.locales[0]?.language.equals("zh", ignoreCase = true)) PteIMLanguage.ZH_CN else PteIMLanguage.EN_US
    else -> selectedLanguage
  }

  private fun applyThemeSelection(mode: PteIMThemeMode) {
    sessionStore.setManualThemeMode(mode)
    appearanceHandler.removeCallbacks(automaticThemeRefresh)
    darkMode = mode == PteIMThemeMode.DARK
    client?.updateAppearance(themeMode = mode)
  }

  private fun applyLanguageSelection(language: PteIMLanguage) {
    selectedLanguage = language
    sessionStore.setManualLanguage(language.takeUnless { it == PteIMLanguage.SYSTEM })
    client?.updateAppearance(language = language)
  }

  private fun redrawForAppearanceChange() {
    client?.updateAppearance(themeMode = resolvedThemeMode())
    when (visibleScreen) {
      PteIMUIDemoScreen.LOGIN -> setContentView(loginView())
      PteIMUIDemoScreen.HOME -> setContentView(homeView(activeTab))
      PteIMUIDemoScreen.CHAT -> if (activeConversationId.isNotBlank()) openChat(activeConversationId, activeConversationTitle)
      PteIMUIDemoScreen.SETTINGS -> setContentView(settingsScreen())
      PteIMUIDemoScreen.LANGUAGE -> setContentView(languageSettingsScreen())
    }
  }

  /** Schedules the exact next local 07:00 or 19:00 boundary while foregrounded. */
  private fun scheduleAutomaticThemeRefresh() {
    appearanceHandler.removeCallbacks(automaticThemeRefresh)
    if (sessionStore.manualThemeMode() != null) return
    val now = Calendar.getInstance()
    val next = (now.clone() as Calendar).apply {
      when {
        get(Calendar.HOUR_OF_DAY) < 7 -> set(Calendar.HOUR_OF_DAY, 7)
        get(Calendar.HOUR_OF_DAY) < 19 -> set(Calendar.HOUR_OF_DAY, 19)
        else -> { add(Calendar.DAY_OF_YEAR, 1); set(Calendar.HOUR_OF_DAY, 7) }
      }
      set(Calendar.MINUTE, 0)
      set(Calendar.SECOND, 0)
      set(Calendar.MILLISECOND, 0)
    }
    appearanceHandler.postDelayed(automaticThemeRefresh, (next.timeInMillis - now.timeInMillis).coerceAtLeast(1L))
  }

  private fun openDemoGroupChat() {
    client?.createGroupConversation("PteIMUIDemo Group", friends.map { it.userId }) { result -> runOnUiThread {
      result.onSuccess { conversation -> openChat(conversation.id.toString(), conversation.title) }.onFailure { businessNotice("创建群组失败：${it.message}") }
    } }
  }

  private fun handleAction(action: PteIMUIAction) {
    when (action) {
      PteIMUIAction.GIFT -> sendBusiness(PteIMMessageType.GIFT)
      PteIMUIAction.RED_PACKET -> sendBusiness(PteIMMessageType.RED_PACKET)
      PteIMUIAction.ORDER -> sendBusiness(PteIMMessageType.ORDER)
      else -> Unit // Standard attachments are implemented inside PteIMUIKit.
    }
  }

  private fun sendBusiness(type: PteIMMessageType) {
    val content = PteIMBusinessContent("demo-${System.currentTimeMillis()}", type.name, "Handled by PteIMUIDemo business layer")
    when (type) { PteIMMessageType.GIFT -> client?.sendGift(activeConversationId, content); PteIMMessageType.RED_PACKET -> client?.sendRedPacket(activeConversationId, content); else -> client?.sendOrder(activeConversationId, content) }
  }

  @Deprecated("Deprecated in Java")
  override fun onBackPressed() {
    if (navigateBack()) return
    super.onBackPressed()
  }

  private fun navigateBack(): Boolean {
    when (visibleScreen) {
      PteIMUIDemoScreen.CHAT -> setContentView(homeView(PteIMUIDemoTab.CHATS))
      PteIMUIDemoScreen.SETTINGS -> setContentView(homeView(PteIMUIDemoTab.ME))
      PteIMUIDemoScreen.LANGUAGE -> returnFromLanguageSettings()
      else -> return false
    }
    return true
  }

  private fun businessNotice(message: String) { android.widget.Toast.makeText(this, "$message 由业务层实现", android.widget.Toast.LENGTH_SHORT).show() }
  private fun credentialField(hint: String, inputType: Int): EditText = EditText(this).apply {
    this.hint = hint
    this.inputType = inputType
    textSize = 15f
    setTextColor(if (darkMode) darkText else ink)
    setHintTextColor(if (darkMode) darkMuted else muted)
    setPadding(dp(16), 0, dp(16), 0)
    background = rounded(if (darkMode) darkInput else lavender, Color.TRANSPARENT, 18)
    if (inputType and InputType.TYPE_TEXT_VARIATION_PASSWORD != 0) transformationMethod = PasswordTransformationMethod.getInstance()
  }
  private fun formLabel(value: String): TextView = label(value).apply {
    textSize = 13f
    typeface = android.graphics.Typeface.DEFAULT_BOLD
    setTextColor(if (darkMode) darkText else ink)
    setPadding(0, 0, 0, dp(8))
  }
  private fun label(value: String): TextView = TextView(this).apply { text = value; includeFontPadding = false }
  private fun textButton(value: String, action: () -> Unit): Button = Button(this).apply { text = value; isAllCaps = false; background = rounded(Color.TRANSPARENT, Color.TRANSPARENT, 18); setTextColor(muted); setPadding(dp(6), 0, dp(6), 0); setOnClickListener { action() } }
  private fun quickButton(value: String, action: () -> Unit): Button = Button(this).apply { text = value; isAllCaps = false; textSize = 14f; setTextColor(purple); background = rounded(Color.rgb(238, 233, 255), Color.TRANSPARENT, 14); setOnClickListener { action() } }
  private fun gradientButton(value: String, action: () -> Unit): View = LinearLayout(this).apply {
    gravity = Gravity.CENTER; isClickable = true; isFocusable = true
    // The login CTA is a restrained violet gradient in the design, not the
    // broader blue-violet gradient used by general IM actions.
    background = gradient(if (darkMode) Color.rgb(143, 87, 245) else Color.rgb(139, 54, 240), if (darkMode) Color.rgb(139, 79, 236) else Color.rgb(113, 48, 224), 18)
    elevation = if (darkMode) dp(7).toFloat() else 0f
    addView(ImageView(this@PteIMUIDemoActivity).apply { setImageResource(R.drawable.pte_im_ui_login_icon); scaleType = ImageView.ScaleType.FIT_CENTER }, LinearLayout.LayoutParams(dp(18), dp(18)).apply { marginEnd = dp(10) })
    addView(label(value).apply { textSize = 16f; typeface = android.graphics.Typeface.DEFAULT_BOLD; setTextColor(Color.WHITE) })
    setOnClickListener { action() }
  }
  private fun rounded(fill: Int, stroke: Int, radius: Int): GradientDrawable = GradientDrawable().apply { setColor(fill); if (stroke != Color.TRANSPARENT) setStroke(dp(1), stroke); cornerRadius = dp(radius).toFloat() }
  private fun gradient(start: Int, end: Int, radius: Int): GradientDrawable = GradientDrawable(GradientDrawable.Orientation.LEFT_RIGHT, intArrayOf(start, end)).apply { cornerRadius = dp(radius).toFloat() }
  private fun dp(value: Int): Int = (value * resources.displayMetrics.density).toInt()
  private fun lp(width: Int, height: Int, left: Int = 0, top: Int = 0, right: Int = 0, bottom: Int = 0) = LinearLayout.LayoutParams(width, height).apply { setMargins(dp(left), dp(top), dp(right), dp(bottom)) }
}

private data class PteIMUIDemoFriend(val name: String, val userId: Long)
private enum class PteIMUIDemoTab { CHATS, CONTACTS, ME }
private enum class PteIMUIDemoScreen { LOGIN, HOME, CHAT, SETTINGS, LANGUAGE }

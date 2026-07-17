package com.ptelive.im.uidemo

import android.app.Application
import com.ptelive.im.PteIMBaseConfig
import com.ptelive.im.PteIMLanguage
import com.ptelive.im.PteIMSDK
import com.ptelive.im.PteIMThemeMode

/** Domains are app-scoped and configured before the login UI appears. */
class PteIMUIDemoApplication : Application() {
  override fun onCreate() {
    super.onCreate()
    baseConfig.validate()
    bootstrap = PteIMSDK.configure(this, baseConfig)
  }

  companion object {
    /**
     * Debug uses the local Docker IM stack through the Android emulator host
     * bridge. Release keeps the public production domains and never enables
     * the automatic test-account path.
     */
    val baseConfig = PteIMBaseConfig(
      apiDomain = if (BuildConfig.DEBUG) "http://10.0.2.2:11504" else "https://api-im.ptelive.com",
      imDomain = if (BuildConfig.DEBUG) "ws://10.0.2.2:11510/ws" else "wss://wss.ptelive.com/ws",
      cosDomain = if (BuildConfig.DEBUG) "http://10.0.2.2:9000" else "https://cos.ptelive.com",
      themeMode = PteIMThemeMode.SYSTEM,
      language = PteIMLanguage.SYSTEM,
      allowInsecureLocalhost = BuildConfig.DEBUG,
    )
    lateinit var bootstrap: com.ptelive.im.PteIMSDKBootstrap
      private set
  }
}

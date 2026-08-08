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
     * Debug uses the local Docker IM stack through localhost. Release keeps
     * SDK public defaults (api/wss/cos/commerce) and never enables
     * the automatic test-account path.
     */
    val baseConfig = if (BuildConfig.DEBUG) {
      PteIMBaseConfig(
        apiDomain = "http://127.0.0.1:11504",
        imDomain = "ws://127.0.0.1:11510/ws",
        cosDomain = "http://127.0.0.1:9000",
        commerceDomain = null,
        themeMode = PteIMThemeMode.SYSTEM,
        language = PteIMLanguage.SYSTEM,
        allowInsecureLocalhost = true,
      )
    } else {
      PteIMBaseConfig(
        themeMode = PteIMThemeMode.SYSTEM,
        language = PteIMLanguage.SYSTEM,
      )
    }
    lateinit var bootstrap: com.ptelive.im.PteIMSDKBootstrap
      private set
  }
}

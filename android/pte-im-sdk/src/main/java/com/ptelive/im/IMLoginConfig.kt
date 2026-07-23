package com.ptelive.im

import android.net.Uri

enum class PteIMThemeMode { SYSTEM, LIGHT, DARK }
enum class PteIMLanguage { SYSTEM, ZH_CN, EN_US }
data class PteIMAppearance(val themeMode: PteIMThemeMode, val language: PteIMLanguage)

/** App-scoped connection configuration. Supply once during application startup. */
data class PteIMBaseConfig(
  val apiDomain: String,
  val imDomain: String,
  /** HTTPS root used to resolve COS object keys returned by the media API. */
  val cosDomain: String,
  /** Optional HTTPS Commerce extension origin. It reuses this IM session's UserSig. */
  val commerceDomain: String? = null,
  val themeMode: PteIMThemeMode = PteIMThemeMode.SYSTEM,
  val language: PteIMLanguage = PteIMLanguage.ZH_CN,
  /**
   * Explicit development-only opt-in for a local IM stack. Production must
   * keep this false, which enforces HTTPS/WSS for every configured endpoint.
   */
  val allowInsecureLocalhost: Boolean = false,
) {
  fun validate() {
    val api = Uri.parse(apiDomain)
    require((api.scheme == "https" || allowsInsecure(api, "http")) && !api.host.isNullOrBlank()) { "apiDomain must be an HTTPS origin" }
    require(api.path.isNullOrBlank() || api.path == "/") { "apiDomain must not contain a path" }
    val im = Uri.parse(imDomain)
    require((im.scheme == "wss" || allowsInsecure(im, "ws")) && !im.host.isNullOrBlank() && im.path == "/ws") { "imDomain must be a WSS URL ending in /ws" }
    val cos = Uri.parse(cosDomain)
    require((cos.scheme == "https" || allowsInsecure(cos, "http")) && !cos.host.isNullOrBlank()) { "cosDomain must be an HTTPS origin" }
    commerceDomain?.let {
      val commerce = Uri.parse(it)
      require((commerce.scheme == "https" || allowsInsecure(commerce, "http")) && !commerce.host.isNullOrBlank()) { "commerceDomain must be an HTTPS origin" }
      require(commerce.path.isNullOrBlank() || commerce.path == "/") { "commerceDomain must not contain a path" }
    }
  }

  private fun allowsInsecure(uri: Uri, expectedScheme: String): Boolean =
    allowInsecureLocalhost && uri.scheme == expectedScheme && uri.host in setOf("localhost", "127.0.0.1")
}

data class PteIMUserSigRefreshResult(val userSig: String, val expireAt: Long)

/** Host business-auth bridge. It exchanges its own refresh session, never an IM signing secret. */
fun interface PteIMUserSigProvider {
  fun refreshUserSig(callback: (Result<PteIMUserSigRefreshResult>) -> Unit)
}

/** Account-scoped login input. Never log userSig. */
data class PteIMLoginConfig(
  val sdkAppId: Long,
  val userId: String,
  val userSig: String,
  val userSigExpireAt: Long = 0,
  val userSigProvider: PteIMUserSigProvider? = null,
) {
  fun validate() {
    require(sdkAppId > 0) { "sdkAppId must be positive" }
    require(userId.toLongOrNull()?.let { it > 0 } == true) { "userId must be a positive numeric string" }
    require(userSig.isNotBlank()) { "userSig is required" }
  }
}

/** Internal resolved session configuration used by the runtime. */
data class PteIMSessionConfig(val base: PteIMBaseConfig, val login: PteIMLoginConfig) {
  val apiDomain get() = base.apiDomain
  val imDomain get() = base.imDomain
  val cosDomain get() = base.cosDomain
  val commerceDomain get() = base.commerceDomain
  val sdkAppId get() = login.sdkAppId
  val userId get() = login.userId
  val userSig get() = login.userSig
  fun validate() { base.validate(); login.validate() }
  fun storeKey(): String = listOf(
    base.apiDomain.trimEnd('/').lowercase(), base.imDomain.lowercase(), base.cosDomain.trimEnd('/').lowercase(), login.sdkAppId, login.userId,
  ).joinToString("|")
}

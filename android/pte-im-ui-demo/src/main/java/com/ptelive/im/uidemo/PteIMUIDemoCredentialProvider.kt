package com.ptelive.im.uidemo

import android.content.Context
import android.provider.Settings
import com.ptelive.im.PteIMBaseConfig
import com.ptelive.im.PteIMLanguage
import com.ptelive.im.PteIMResponseCipher
import com.ptelive.im.PteIMThemeMode
import org.json.JSONArray
import org.json.JSONObject
import java.net.HttpURLConnection
import java.net.URL
import java.util.UUID

/** A server-issued, short-lived credential. It is deliberately kept in memory only. */
internal data class PteIMUIDemoCredential(
  val sdkAppId: Long,
  val userId: Long,
  val userSig: String,
  val expiresAt: Long,
)

/**
 * Debug-demo business-login adapter.
 *
 * UserSig is always issued by api-im and decrypted only in process. The demo
 * never contains IM signing keys and never persists the returned signature.
 */
internal class PteIMUIDemoCredentialProvider(
  private val baseConfig: PteIMBaseConfig,
  private val deviceId: String,
) {
  fun issue(userId: Long): PteIMUIDemoCredential {
    require(userId > 0) { "demo userId must be positive" }
    val payload = JSONObject().apply {
      // api-im accepts the documented numeric identifiers as JSON strings too;
      // strings keep precision and match its UserSig request contract.
      put("app_id", PteIMUIDemoSessionStore.demoBusinessAppId.toString())
      put("user_id", userId.toString())
      put("identifier", userId.toString())
      put("device_id", deviceId)
      put("platform", "android")
      put("scene", "chat")
      put("expire", 86_400)
    }
    val data = postPublic("/api/v1/im/usersig", payload)
    return PteIMUIDemoCredential(
      sdkAppId = data.getString("sdk_app_id").toLong(),
      userId = data.getString("user_id").toLong(),
      userSig = data.getString("user_sig"),
      expiresAt = data.optLong("expire_at"),
    )
  }

  /** Creates deterministic, server-backed contacts and conversations for UI review. */
  fun seed(primary: PteIMUIDemoCredential) {
    val alice = issue(PteIMUIDemoSessionStore.demoAliceId)
    val bob = issue(PteIMUIDemoSessionStore.demoBobId)
    val carol = issue(PteIMUIDemoSessionStore.demoCarolId)
    val dave = issue(PteIMUIDemoSessionStore.demoDaveId)
    updateProfile(primary, "Pte Demo")
    updateProfile(alice, "Alice")
    updateProfile(bob, "Bob")
    updateProfile(carol, "Carol")
    updateProfile(dave, "Dave")
    follow(primary, alice, "Alice")
    follow(alice, primary, "Pte Demo")
    follow(primary, bob, "Bob")
    follow(bob, primary, "Pte Demo")
    follow(primary, carol, "Carol")
    follow(carol, primary, "Pte Demo")
    follow(primary, dave, "Dave")
    follow(dave, primary, "Pte Demo")
    postSdk(primary, "/v1/im/conversations/open-single", JSONObject().put("peerUserId", alice.userId))
    postSdk(primary, "/v1/im/conversations/open-single", JSONObject().put("peerUserId", bob.userId))
    postSdk(primary, "/v1/im/conversations/open-single", JSONObject().put("peerUserId", carol.userId))
    postSdk(primary, "/v1/im/conversations/open-single", JSONObject().put("peerUserId", dave.userId))
    postSdk(primary, "/v1/im/conversations/create-group", JSONObject().apply {
      put("title", "Work Team 工作群")
      put("memberIds", JSONArray().put(alice.userId).put(bob.userId))
    })
    postSdk(primary, "/v1/im/conversations/create-group", JSONObject().apply {
      put("title", "Project Alpha")
      put("memberIds", JSONArray().put(alice.userId).put(carol.userId).put(dave.userId))
    })
  }

  private fun updateProfile(credential: PteIMUIDemoCredential, nickname: String) {
    postSdk(credential, "/v1/im/profile/update", JSONObject().put("field", "nickname").put("value", nickname))
  }

  private fun follow(owner: PteIMUIDemoCredential, target: PteIMUIDemoCredential, remark: String) {
    postSdk(owner, "/v1/im/follows/follow", JSONObject().put("targetUserId", target.userId).put("remark", remark))
  }

  private fun postPublic(path: String, payload: JSONObject): JSONObject {
    val root = encryptedPost(path, payload) { connection -> Unit }
    check(root.optInt("code", 0) == 1) { root.optString("msg", "business login failed") }
    return root.optJSONObject("data") ?: error("business login returned no data")
  }

  private fun postSdk(credential: PteIMUIDemoCredential, path: String, payload: JSONObject): JSONObject {
    val root = encryptedPost(path, payload) { connection ->
      connection.setRequestProperty("Authorization", "Bearer ${credential.userSig}")
      connection.setRequestProperty("X-Pte-Sdk-AppId", credential.sdkAppId.toString())
      connection.setRequestProperty("X-Pte-User-Id", credential.userId.toString())
    }
    check(root.optInt("code", 1) == 1) { root.optString("msg", "demo seed request failed") }
    return root.optJSONObject("data") ?: JSONObject()
  }

  private fun encryptedPost(path: String, payload: JSONObject, headers: (HttpURLConnection) -> Unit): JSONObject {
    val responseKey = PteIMResponseCipher.createRequestKey()
    val connection = (URL(baseConfig.apiDomain.trimEnd('/') + path).openConnection() as HttpURLConnection).apply {
      requestMethod = "POST"
      connectTimeout = 10_000
      readTimeout = 10_000
      doOutput = true
      setRequestProperty("Content-Type", "application/json")
      setRequestProperty("X-Pte-Response-Public-Key", PteIMResponseCipher.requestPublicKey(responseKey))
      headers(this)
    }
    return try {
      connection.outputStream.use { output -> output.write(payload.toString().toByteArray(Charsets.UTF_8)) }
      check(connection.responseCode in 200..299) { "demo API request failed with HTTP ${connection.responseCode}" }
      val envelope = JSONObject(connection.inputStream.bufferedReader().use { it.readText() })
      JSONObject(PteIMResponseCipher.decrypt(envelope, responseKey))
    } finally {
      connection.disconnect()
    }
  }
}

/** Stores only non-sensitive demo identity state; UserSig remains memory-only. */
internal class PteIMUIDemoSessionStore(private val context: Context) {
  private val preferences = context.getSharedPreferences("pte_im_ui_demo_session", Context.MODE_PRIVATE)

  fun shouldRestore(): Boolean = !preferences.getBoolean(keyExplicitLogout, false)
  fun userId(): Long = preferences.getLong(keyUserId, demoPrimaryUserId)
  fun deviceId(): String = preferences.getString(keyDeviceId, null) ?: stableDeviceId().also {
    preferences.edit().putString(keyDeviceId, it).apply()
  }
  fun markLoggedIn(userId: Long) = preferences.edit().putLong(keyUserId, userId).putBoolean(keyExplicitLogout, false).apply()
  fun markLoggedOut() = preferences.edit().putBoolean(keyExplicitLogout, true).apply()
  fun seeded(): Boolean = preferences.getInt(keySeedVersion, 0) == demoSeedVersion
  fun markSeeded() = preferences.edit().putInt(keySeedVersion, demoSeedVersion).apply()

  /** Null means the demo keeps using its 07:00–19:00 automatic theme policy. */
  fun manualThemeMode(): PteIMThemeMode? = preferences.getString(keyManualThemeMode, null)?.let { value ->
    runCatching { PteIMThemeMode.valueOf(value) }.getOrNull()
  }
  fun setManualThemeMode(value: PteIMThemeMode) {
    require(value != PteIMThemeMode.SYSTEM) { "Manual theme must be LIGHT or DARK" }
    preferences.edit().putString(keyManualThemeMode, value.name).apply()
  }
  fun clearManualThemeMode() = preferences.edit().remove(keyManualThemeMode).apply()

  /** Null means language follows the Android system locale. */
  fun manualLanguage(): PteIMLanguage? = preferences.getString(keyManualLanguage, null)?.let { value ->
    runCatching { PteIMLanguage.valueOf(value) }.getOrNull()?.takeIf { it != PteIMLanguage.SYSTEM }
  }
  fun setManualLanguage(value: PteIMLanguage?) {
    preferences.edit().apply {
      if (value == null || value == PteIMLanguage.SYSTEM) remove(keyManualLanguage) else putString(keyManualLanguage, value.name)
    }.apply()
  }

  private fun stableDeviceId(): String {
    val androidId = Settings.Secure.getString(context.contentResolver, Settings.Secure.ANDROID_ID)
    return "pte-im-demo-${androidId?.takeIf { it.isNotBlank() } ?: UUID.randomUUID()}"
  }

  companion object {
    const val demoBusinessAppId = 10001
    const val demoPrimaryUserId = 990021L
    const val demoAliceId = 990022L
    const val demoBobId = 990023L
    const val demoCarolId = 990024L
    const val demoDaveId = 990025L
    const val demoSeedVersion = 2
    private const val keyUserId = "user_id"
    private const val keyDeviceId = "device_id"
    private const val keyExplicitLogout = "explicit_logout"
    private const val keySeedVersion = "seed_version"
    private const val keyManualThemeMode = "manual_theme_mode"
    private const val keyManualLanguage = "manual_language"
  }
}

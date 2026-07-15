package com.ptelive.im

import android.content.Context
import org.json.JSONArray
import org.json.JSONObject
import java.security.KeyFactory
import java.security.KeyPair
import java.security.KeyPairGenerator
import java.security.PrivateKey
import java.security.SecureRandom
import java.security.interfaces.ECPublicKey
import java.security.spec.ECGenParameterSpec
import java.security.spec.PKCS8EncodedKeySpec
import javax.crypto.Cipher
import javax.crypto.KeyAgreement
import javax.crypto.spec.GCMParameterSpec
import javax.crypto.spec.SecretKeySpec

/** Client-side P-256/AES-GCM envelope implementation for the existing pte-live-im E2EE contract. */
internal class PteIME2EE(context: Context, storeKey: String, private val sdkAppId: Long, private val userId: Long) {
  private val preferences = context.getSharedPreferences("pte_live_im_e2ee", Context.MODE_PRIVATE)
  private val preferenceKey = storeKey.keyHash()
  private val cacheCipher = PteIMLocalCipher(storeKey)
  private val random = SecureRandom()

  fun register(request: (String, JSONObject) -> Any) {
    request("/api/v1/chat/e2ee/device/register", JSONObject().apply {
      put("app_id", sdkAppId)
      put("user_id", userId)
      put("device_id", deviceId())
      put("public_key", PteIMResponseCipher.encode(PteIMResponseCipher.publicKeyBytes(identity().public as ECPublicKey)))
      put("algorithm", algorithm)
    })
  }

  fun encrypt(message: PteIMMessage, request: (String, JSONObject) -> Any): JSONObject {
    val recipients = request("/api/v1/chat/e2ee/device/list", JSONObject().apply {
      put("app_id", sdkAppId); put("user_id", userId); put("conversation_id", message.conversationId.toLong())
    }) as? JSONArray
      ?: error("E2EE device list response is invalid")
    val audit = request("/api/v1/chat/e2ee/audit-key", JSONObject()) as? JSONObject
      ?: error("E2EE audit key response is invalid")
    val contentKey = ByteArray(32).also(random::nextBytes)
    val contentNonce = ByteArray(12).also(random::nextBytes)
    val contentCiphertext = aesGcm(Cipher.ENCRYPT_MODE, contentKey, contentNonce, message.contentJson().toString().toByteArray(Charsets.UTF_8), messageAad)
    return JSONObject().apply {
      put("version", 1); put("algorithm", algorithm)
      put("ciphertext", PteIMResponseCipher.encode(contentCiphertext)); put("nonce", PteIMResponseCipher.encode(contentNonce))
      put("recipients", JSONArray().also { target ->
        for (index in 0 until recipients.length()) {
          val device = recipients.getJSONObject(index)
          target.put(wrapForDevice(contentKey, device.getLong("user_id"), device.getString("device_id"), device.getString("public_key")))
        }
      })
      if (audit.optBoolean("enabled")) {
        require(audit.optString("algorithm") == algorithm) { "unsupported E2EE audit key" }
        val keyId = audit.getString("key_id")
        val wrapped = wrap(contentKey, audit.getString("public_key"))
        put("audit_recipients", JSONArray().put(JSONObject().apply {
          put("key_id", keyId); put("ephemeral_public_key", wrapped.ephemeralPublicKey); put("wrapped_key", wrapped.wrappedKey); put("nonce", wrapped.nonce)
        }))
      } else if (audit.optBoolean("required")) {
        error("E2EE audit recipient is required")
      }
    }
  }

  fun decrypt(envelope: JSONObject): JSONObject {
    require(envelope.optInt("version") == 1 && envelope.optString("algorithm") == algorithm) { "unsupported E2EE message envelope" }
    val recipients = envelope.optJSONArray("recipients") ?: error("E2EE recipients are missing")
    var recipient: JSONObject? = null
    for (index in 0 until recipients.length()) {
      val value = recipients.getJSONObject(index)
      if (value.optString("device_id") == deviceId()) { recipient = value; break }
    }
    val selected = recipient ?: error("this device is not an E2EE recipient")
    val shared = KeyAgreement.getInstance("ECDH").run {
      init(identity().private); doPhase(PteIMResponseCipher.publicKey(PteIMResponseCipher.decode(selected.getString("ephemeral_public_key"))), true); generateSecret()
    }
    val wrapNonce = PteIMResponseCipher.decode(selected.getString("nonce"))
    val contentKey = aesGcm(Cipher.DECRYPT_MODE, PteIMResponseCipher.deriveKey(shared, wrapNonce, wrapAad), wrapNonce, PteIMResponseCipher.decode(selected.getString("wrapped_key")), wrapAadBytes)
    require(contentKey.size == 32) { "invalid E2EE content key" }
    val plaintext = aesGcm(Cipher.DECRYPT_MODE, contentKey, PteIMResponseCipher.decode(envelope.getString("nonce")), PteIMResponseCipher.decode(envelope.getString("ciphertext")), messageAad)
    return JSONObject(plaintext.toString(Charsets.UTF_8))
  }

  private fun wrapForDevice(contentKey: ByteArray, userId: Long, deviceId: String, publicKey: String): JSONObject {
    val wrapped = wrap(contentKey, publicKey)
    return JSONObject().apply {
      put("user_id", userId); put("device_id", deviceId); put("ephemeral_public_key", wrapped.ephemeralPublicKey); put("wrapped_key", wrapped.wrappedKey); put("nonce", wrapped.nonce)
    }
  }

  private fun wrap(contentKey: ByteArray, recipientPublicKey: String): WrappedKey {
    val ephemeral = KeyPairGenerator.getInstance("EC").apply { initialize(ECGenParameterSpec("secp256r1")) }.generateKeyPair()
    val shared = KeyAgreement.getInstance("ECDH").run {
      init(ephemeral.private); doPhase(PteIMResponseCipher.publicKey(PteIMResponseCipher.decode(recipientPublicKey)), true); generateSecret()
    }
    val nonce = ByteArray(12).also(random::nextBytes)
    val wrapped = aesGcm(Cipher.ENCRYPT_MODE, PteIMResponseCipher.deriveKey(shared, nonce, wrapAad), nonce, contentKey, wrapAadBytes)
    return WrappedKey(PteIMResponseCipher.encode(PteIMResponseCipher.publicKeyBytes(ephemeral.public as ECPublicKey)), PteIMResponseCipher.encode(wrapped), PteIMResponseCipher.encode(nonce))
  }

  private fun identity(): KeyPair {
    val stored = preferences.getString("$preferenceKey.private", null)
    if (stored != null) {
      val privateKey = KeyFactory.getInstance("EC").generatePrivate(PKCS8EncodedKeySpec(PteIMResponseCipher.decode(cacheCipher.decrypt(stored))))
      val publicKey = privateKey as? java.security.interfaces.ECPrivateKey ?: error("invalid E2EE private key")
      // Public material is persisted separately so it does not need to be derivable from a private EC key.
      val storedPublicKey = preferences.getString("$preferenceKey.public", null)
        ?: error("missing E2EE public key")
      return KeyPair(PteIMResponseCipher.publicKey(PteIMResponseCipher.decode(storedPublicKey)), publicKey)
    }
    val created = KeyPairGenerator.getInstance("EC").apply { initialize(ECGenParameterSpec("secp256r1")) }.generateKeyPair()
    preferences.edit()
      .putString("$preferenceKey.private", cacheCipher.encrypt(PteIMResponseCipher.encode(created.private.encoded)))
      .putString("$preferenceKey.public", PteIMResponseCipher.encode(PteIMResponseCipher.publicKeyBytes(created.public as ECPublicKey)))
      .apply()
    return created
  }

  private fun deviceId(): String = preferences.getString("$preferenceKey.device", null) ?: java.util.UUID.randomUUID().toString().also {
    preferences.edit().putString("$preferenceKey.device", it).apply()
  }

  private fun aesGcm(mode: Int, key: ByteArray, nonce: ByteArray, value: ByteArray, aad: ByteArray): ByteArray = Cipher.getInstance("AES/GCM/NoPadding").run {
    init(mode, SecretKeySpec(key, "AES"), GCMParameterSpec(128, nonce)); updateAAD(aad); doFinal(value)
  }

  private data class WrappedKey(val ephemeralPublicKey: String, val wrappedKey: String, val nonce: String)

  private companion object {
    const val algorithm = "P-256/A256GCM"
    const val wrapAad = "pte-live-im-audit-wrap-v1"
    val messageAad = "pte-live-im-message-v1".toByteArray(Charsets.UTF_8)
    val wrapAadBytes = wrapAad.toByteArray(Charsets.UTF_8)
  }
}

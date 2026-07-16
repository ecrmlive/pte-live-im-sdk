package com.ptelive.im

import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.Base64
import java.security.KeyStore
import java.security.MessageDigest
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

/** AES-256-GCM payload cipher. The key is non-exportable and remains in Android Keystore. */
internal class PteIMLocalCipher(storeKey: String) {
  private val alias = "pte.im.cache." + storeKey.keyHash()
  private val aad = "pte.im.cache/v2/$storeKey".toByteArray(Charsets.UTF_8)
  private val key: SecretKey = loadOrCreate()

  fun encrypt(value: String): String {
    val cipher = Cipher.getInstance("AES/GCM/NoPadding").apply {
      init(Cipher.ENCRYPT_MODE, key)
      updateAAD(aad)
    }
    return "pte2:" + Base64.encodeToString(cipher.iv + cipher.doFinal(value.toByteArray(Charsets.UTF_8)), Base64.NO_WRAP)
  }

  fun decrypt(value: String): String {
    if (!value.startsWith("pte1:") && !value.startsWith("pte2:")) return value // One-time migration from pre-encryption cache.
    val isV2 = value.startsWith("pte2:")
    val bytes = Base64.decode(value.drop(5), Base64.NO_WRAP)
    require(bytes.size > 12) { "invalid encrypted IM cache payload" }
    val cipher = Cipher.getInstance("AES/GCM/NoPadding").apply {
      init(Cipher.DECRYPT_MODE, key, GCMParameterSpec(128, bytes.copyOfRange(0, 12)))
      if (isV2) updateAAD(aad)
    }
    return cipher.doFinal(bytes.copyOfRange(12, bytes.size)).toString(Charsets.UTF_8)
  }

  private fun loadOrCreate(): SecretKey {
    val store = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
    (store.getKey(alias, null) as? SecretKey)?.let { return it }
    KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, "AndroidKeyStore").apply {
      init(KeyGenParameterSpec.Builder(alias, KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT)
        .setBlockModes(KeyProperties.BLOCK_MODE_GCM).setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE).setKeySize(256).build())
    }.generateKey()
    return store.getKey(alias, null) as? SecretKey ?: throw IllegalStateException("Android Keystore key unavailable")
  }

  companion object {
    /** Removes only this SDK cache key. Use together with the account cache reset recovery API. */
    internal fun removeKey(storeKey: String) {
      KeyStore.getInstance("AndroidKeyStore").apply { load(null) }.deleteEntry("pte.im.cache." + storeKey.keyHash())
    }
  }
}

internal fun String.keyHash(): String = MessageDigest.getInstance("SHA-256")
  .digest(toByteArray()).joinToString("") { "%02x".format(it) }

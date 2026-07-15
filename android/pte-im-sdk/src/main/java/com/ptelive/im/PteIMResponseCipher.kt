package com.ptelive.im

import android.util.Base64
import org.json.JSONObject
import java.math.BigInteger
import java.security.AlgorithmParameters
import java.security.KeyFactory
import java.security.KeyPair
import java.security.KeyPairGenerator
import java.security.PublicKey
import java.security.interfaces.ECPublicKey
import java.security.spec.ECGenParameterSpec
import java.security.spec.ECPoint
import java.security.spec.ECPublicKeySpec
import javax.crypto.Cipher
import javax.crypto.KeyAgreement
import javax.crypto.Mac
import javax.crypto.spec.GCMParameterSpec
import javax.crypto.spec.SecretKeySpec

/** Decrypts the short-lived P-256/A256GCM HTTP response envelopes required by api-im. */
internal object PteIMResponseCipher {
  private const val context = "pte-live-api-response-v1"

  fun createRequestKey(): KeyPair = KeyPairGenerator.getInstance("EC").apply {
    initialize(ECGenParameterSpec("secp256r1"))
  }.generateKeyPair()

  fun requestPublicKey(keyPair: KeyPair): String = encode(publicKeyBytes(keyPair.public as ECPublicKey))

  fun decrypt(envelope: JSONObject, keyPair: KeyPair): String {
    require(envelope.optInt("version") == 1 && envelope.optString("algorithm") == "P-256/A256GCM") { "unsupported API response encryption" }
    val shared = KeyAgreement.getInstance("ECDH").run {
      init(keyPair.private); doPhase(publicKey(decode(envelope.getString("ephemeral_public_key"))), true); generateSecret()
    }
    val salt = decode(envelope.getString("salt"))
    val nonce = decode(envelope.getString("nonce"))
    require(salt.size == 32 && nonce.size == 12) { "invalid API response encryption envelope" }
    val cipher = Cipher.getInstance("AES/GCM/NoPadding").apply {
      init(Cipher.DECRYPT_MODE, SecretKeySpec(deriveKey(shared, salt), "AES"), GCMParameterSpec(128, nonce))
      updateAAD(context.toByteArray(Charsets.UTF_8))
    }
    return cipher.doFinal(decode(envelope.getString("ciphertext"))).toString(Charsets.UTF_8)
  }

  fun publicKeyBytes(publicKey: ECPublicKey): ByteArray = byteArrayOf(4) +
    publicKey.w.affineX.fixed(32) + publicKey.w.affineY.fixed(32)

  fun publicKey(raw: ByteArray): PublicKey {
    require(raw.size == 65 && raw[0].toInt() == 4) { "invalid P-256 public key" }
    val parameters = AlgorithmParameters.getInstance("EC").apply { init(ECGenParameterSpec("secp256r1")) }
    val point = ECPoint(BigInteger(1, raw.copyOfRange(1, 33)), BigInteger(1, raw.copyOfRange(33, 65)))
    return KeyFactory.getInstance("EC").generatePublic(ECPublicKeySpec(point, parameters.getParameterSpec(java.security.spec.ECParameterSpec::class.java)))
  }

  fun deriveKey(shared: ByteArray, salt: ByteArray, label: String = context): ByteArray = Mac.getInstance("HmacSHA256").run {
    init(SecretKeySpec(salt, "HmacSHA256")); doFinal(shared + label.toByteArray(Charsets.UTF_8))
  }

  fun encode(value: ByteArray): String = Base64.encodeToString(value, Base64.URL_SAFE or Base64.NO_PADDING or Base64.NO_WRAP)
  fun decode(value: String): ByteArray = Base64.decode(value, Base64.URL_SAFE or Base64.NO_PADDING or Base64.NO_WRAP)
}

private fun BigInteger.fixed(size: Int): ByteArray {
  val raw = toByteArray().let { if (it.size > size && it[0].toInt() == 0) it.copyOfRange(1, it.size) else it }
  require(raw.size <= size) { "P-256 coordinate is too large" }
  return ByteArray(size - raw.size) + raw
}

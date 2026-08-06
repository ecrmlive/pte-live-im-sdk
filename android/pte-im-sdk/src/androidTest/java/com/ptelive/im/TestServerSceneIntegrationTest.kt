package com.ptelive.im

import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import org.json.JSONObject
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import java.net.HttpURLConnection
import java.net.URL
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicReference

/** SDK-only acceptance against the normal test server; no Demo activity is used. */
@RunWith(AndroidJUnit4::class)
class TestServerSceneIntegrationTest {
  private val context get() = InstrumentationRegistry.getInstrumentation().targetContext

  @Test fun normalUserEntersShowRoomOverWss() {
    val chatCredential = issueUserSig("91000001", "android-chat-show")
    val sceneCredential = issueUserSig("91000001", "android-scene-show", scene = "show", roomId = "sdk-e2e-show")
    val sdk = normalSdk(chatCredential)
    val scene = sdk.createSceneClient()
    val connected = CountDownLatch(1)
    val entered = CountDownLatch(1)
    val failure = AtomicReference<Throwable?>(null)
    scene.addListener(object : PteIMSceneListener {
      override fun onError(message: String) { failure.compareAndSet(null, IllegalStateException(message)) }
    })

    scene.connect(sceneCredential.userId, sceneCredential.userSig, sceneCredential.expireAt) { result ->
      result.onSuccess { connected.countDown() }.onFailure { failure.set(it); connected.countDown() }
    }
    assertTrue("scene connect failed: ${failure.get()}", connected.await(20, TimeUnit.SECONDS) && failure.get() == null)
    scene.enter(PteIMSceneKind.SHOW, "sdk-e2e-show") { result ->
      result.onSuccess { entered.countDown() }.onFailure { failure.set(it); entered.countDown() }
    }
    assertTrue("scene enter failed: ${failure.get()}", entered.await(20, TimeUnit.SECONDS) && failure.get() == null)
    scene.disconnect()
    sdk.close()
  }

  @Test fun normalUsersExchangeEncryptedChatAndReceiveDeliveryAck() {
    val sender = normalSdk(issueUserSig("91000001", "android-chat-sender"))
    val receiver = normalSdk(issueUserSig("91000002", "android-chat-receiver"))
    val sent = CountDownLatch(1)
    val received = CountDownLatch(1)
    val failure = AtomicReference<Throwable?>(null)
    val text = "android-sdk-e2e-${System.currentTimeMillis()}"
    sender.addListener(object : PteIMListener {
      override fun onMessageStateChanged(clientMsgId: String, state: PteIMSendState) { if (state == PteIMSendState.SENT) sent.countDown() }
      override fun onError(error: Throwable) { failure.compareAndSet(null, error) }
    })
    receiver.addListener(object : PteIMListener {
      override fun onMessage(message: PteIMMessage) { if (message.text == text) received.countDown() }
      override fun onError(error: Throwable) { failure.compareAndSet(null, error) }
    })
    try {
      assertTrue("sender did not connect: ${failure.get()}", awaitCondition { sender.isConnected() })
      assertTrue("receiver did not connect: ${failure.get()}", awaitCondition { receiver.isConnected() })
      val conversation = awaitResult<PteIMRemoteConversation> { sender.openSingleConversation(91000002, it) }
      sender.sendText(conversation.id.toString(), text)
      assertTrue("sender did not receive delivery ACK: ${failure.get()}", sent.await(25, TimeUnit.SECONDS))
      assertTrue("receiver did not receive decrypted text: ${failure.get()}", received.await(25, TimeUnit.SECONDS))
      assertTrue("chat transport failed: ${failure.get()}", failure.get() == null)
    } finally {
      sender.close()
      receiver.close()
    }
  }

  @Test fun normalUserCompletesSocialAndCommerceExtensionContracts() {
    val sdk = normalSdk(issueUserSig("91000001", "android-extension"))
    try {
      val profile = awaitResult<PteIMUserProfile> { sdk.fetchMyProfile(it) }
      assertTrue("normal profile user mismatch", profile.userId == 91000001L)
      awaitResult<Unit> { sdk.follow(91000002, "sdk-e2e", it) }
      val follows = awaitResult<PteIMContactPage> { sdk.fetchFollows(limit = 100, callback = it) }
      assertTrue("follow relation was not persisted", follows.list.any { it.userId == "91000002" })
      awaitResult<Unit> { sdk.unfollow(91000002, it) }

      val capabilities = awaitResult<PteIMCommerceCapability> { sdk.commerce.capabilities(it) }
      assertTrue("commerce capability contract is disabled", capabilities.gifts && capabilities.backpack && capabilities.orders)
      awaitResult<List<PteIMGift>> { sdk.commerce.gifts(it) }
      awaitResult<PteIMWallet> { sdk.commerce.wallet(it) }
      awaitResult<List<PteIMBackpackItem>> { sdk.commerce.backpack(it) }
      awaitResult<List<PteIMCommerceOrder>> { sdk.commerce.orders(callback = it) }
    } finally {
      sdk.close()
    }
  }

  @Test fun normalSportsUserEntersBoundSportsRoomOverWss() {
    val chatCredential = issueUserSig("91000001", "android-chat-sports", appId = 20001)
    val sceneCredential = issueUserSig("91000001", "android-scene-sports", appId = 20001, scene = "sports", roomId = "sports-live-910001")
    val sdk = normalSdk(chatCredential)
    val scene = sdk.createSceneClient()
    val connected = CountDownLatch(1)
    val entered = CountDownLatch(1)
    val failure = AtomicReference<Throwable?>(null)
    scene.addListener(object : PteIMSceneListener {
      override fun onError(message: String) { failure.compareAndSet(null, IllegalStateException(message)) }
    })
    try {
      scene.connect(sceneCredential.userId, sceneCredential.userSig, sceneCredential.expireAt) { result ->
        result.onSuccess { connected.countDown() }.onFailure { failure.set(it); connected.countDown() }
      }
      assertTrue("sports scene connect failed: ${failure.get()}", connected.await(20, TimeUnit.SECONDS) && failure.get() == null)
      scene.enter(PteIMSceneKind.SPORTS, "sports-live-910001") { result ->
        result.onSuccess { entered.countDown() }.onFailure { failure.set(it); entered.countDown() }
      }
      assertTrue("sports scene enter failed: ${failure.get()}", entered.await(20, TimeUnit.SECONDS) && failure.get() == null)
    } finally {
      scene.disconnect()
      sdk.close()
    }
  }

  private fun normalSdk(credential: Credential): PteIMSDK = PteIMSDK.configure(context, PteIMBaseConfig(
    apiDomain = "https://api-im.qxkejiwl.top",
    imDomain = "wss://wss.qxkejiwl.top/ws",
    cosDomain = "https://cos.qxkejiwl.top",
    commerceDomain = "https://api-im-commerce.qxkejiwl.top",
  )).login(PteIMLoginConfig(credential.sdkAppId, credential.userId, credential.userSig, credential.expireAt))

  private fun <T> awaitResult(start: ((Result<T>) -> Unit) -> Unit): T {
    val latch = CountDownLatch(1)
    val result = AtomicReference<Result<T>?>(null)
    start { value -> result.set(value); latch.countDown() }
    assertTrue("SDK request timed out", latch.await(25, TimeUnit.SECONDS))
    return checkNotNull(result.get()).getOrThrow()
  }

  private fun awaitCondition(condition: () -> Boolean): Boolean {
    val deadline = System.nanoTime() + TimeUnit.SECONDS.toNanos(25)
    while (System.nanoTime() < deadline) {
      if (condition()) return true
      Thread.sleep(50)
    }
    return condition()
  }

  private fun issueUserSig(userId: String, deviceId: String, appId: Int = 10001, scene: String? = null, roomId: String? = null): Credential {
    val key = PteIMResponseCipher.createRequestKey()
    val connection = (URL("https://api-im.qxkejiwl.top/api/v1/im/usersig").openConnection() as HttpURLConnection).apply {
      requestMethod = "POST"
      doOutput = true
      setRequestProperty("Content-Type", "application/json")
      setRequestProperty("X-Pte-Response-Public-Key", PteIMResponseCipher.requestPublicKey(key))
    }
    return try {
      val request = JSONObject().put("app_id", appId.toString()).put("user_id", userId).put("identifier", userId)
        .put("user_type", "user").put("device_id", deviceId).put("platform", "android").put("expire", 3600)
      if (scene != null) request.put("scene", scene)
      if (roomId != null) request.put("room_id", roomId)
      connection.outputStream.use { it.write(request.toString().toByteArray()) }
      check(connection.responseCode == HttpURLConnection.HTTP_OK) { "UserSig HTTP ${connection.responseCode}" }
      val encrypted = JSONObject(connection.inputStream.bufferedReader().use { it.readText() })
      val root = JSONObject(PteIMResponseCipher.decrypt(encrypted, key))
      check(root.optInt("code") == 1) { root.optString("msg", "UserSig issuance failed") }
      val data = root.getJSONObject("data")
      Credential(data.getLong("sdk_app_id"), data.getString("user_id"), data.getString("user_sig"), data.getLong("expire_at"))
    } finally {
      connection.disconnect()
    }
  }

  private data class Credential(val sdkAppId: Long, val userId: String, val userSig: String, val expireAt: Long)
}

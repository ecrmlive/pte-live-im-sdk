package com.ptelive.im.uidemo

import android.app.Activity
import android.content.Intent
import android.net.Uri
import android.os.Bundle
import android.view.View
import android.widget.Button
import android.widget.EditText
import android.widget.LinearLayout
import android.widget.TextView
import com.ptelive.im.PteIMBaseConfig
import com.ptelive.im.PteIMBusinessContent
import com.ptelive.im.PteIMLocation
import com.ptelive.im.PteIMLoginConfig
import com.ptelive.im.PteIMMessageType
import com.ptelive.im.PteIMSDK
import com.ptelive.im.ui.PteIMUIAction
import com.ptelive.im.ui.PteIMUIChatView
import com.ptelive.im.ui.PteIMUIkit

/**
 * Business-shell sample: the host authenticates its user, obtains a short-lived UserSig,
 * then logs PteIMSDK in and embeds PteIMUIkit screens. No credential is persisted.
 */
class PteIMUIDemoActivity : Activity() {
  private var client: PteIMSDK? = null
  private var chat: PteIMUIChatView? = null
  private lateinit var conversationId: EditText
  private var pendingAction: PteIMUIAction? = null
  private val friends = mutableListOf("Alice (10002)", "Bob (10003)")

  override fun onCreate(savedInstanceState: Bundle?) { super.onCreate(savedInstanceState); setContentView(businessLoginView()) }
  override fun onDestroy() { client?.stop(); super.onDestroy() }

  private fun businessLoginView(): View {
    val root = column()
    val api = field("API domain", "https://api.example.com")
    val im = field("IM WSS URL", "wss://im.example.com/ws")
    val cos = field("COS domain", "https://cos.example.com")
    val appId = field("SDK App ID", "1400000001")
    val account = field("Business account", "demo-user")
    val password = field("Business password (demo only)", "")
    val userId = field("IM user ID returned by business login", "10001")
    val userSig = field("Short-lived UserSig returned by business login", "")
    conversationId = field("Active conversation ID", "")
    conversationId.isEnabled = false
    root.addView(title("PteIMUIDemo · Android"))
    root.addView(note("示例业务流程：业务登录 → 后端返回 IM userId/UserSig → PteIMSDK 登录 → 使用 PteIMUIkit。请替换 demo 账号校验为您的业务 API；UserSig 不写入磁盘。"))
    listOf(api, im, cos, appId, account, password, userId, userSig, conversationId).forEach(root::addView)
    root.addView(button("业务登录并进入 IM") {
      val session = PteIMUIDemoBusinessSession(account.text.toString(), userId.text.toString(), userSig.text.toString())
      if (session.userId.isBlank() || session.userSig.isBlank()) {
        password.error = "业务后端应返回 userId 与短期 UserSig"; return@button
      }
      runCatching {
        client?.stop()
        PteIMSDK.configure(applicationContext, PteIMBaseConfig(api.text.toString(), im.text.toString(), cos.text.toString()))
          .login(PteIMLoginConfig(appId.text.toString().toLong(), session.userId, session.userSig))
      }.onSuccess { value -> client = value; setContentView(businessShell()) }
        .onFailure { password.error = "IM 登录失败：${it.message}" }
    })
    return root
  }

  private fun businessShell(): View {
    val root = column()
    root.addView(title("PteIMUIDemo"))
    root.addView(note("业务层：好友关系、我的；IM UI：会话、聊天、群组。"))
    root.addView(button("会话列表（PteIMUIkit）") { openConversationList() })
    root.addView(button("好友列表 / 关系") { setContentView(friendListView()) })
    root.addView(button("创建群组并聊天（PteIMUIkit）") { openDemoGroupChat() })
    root.addView(button("我的") { setContentView(profileView()) })
    root.addView(button("退出登录") { client?.stop(); client = null; setContentView(businessLoginView()) })
    return root
  }

  private fun openConversationList() {
    val value = client ?: return
    setContentView(PteIMUIkit.createConversationListView(this, value) { id -> openChat(id, id) })
  }

  private fun friendListView(): View {
    val root = column(); root.addView(title("好友列表 / 关系示例")); root.addView(note("添加、删除好友属于业务 API；聊天页面由 PteIMUIkit 提供。"))
    friends.forEach { friend -> root.addView(button(friend) {
      openSingleChat(friend.substringAfter('(').substringBefore(')').toLong(), friend.substringBefore(' '))
    }) }
    root.addView(button("添加示例好友") { friends.add("New friend (10004)"); setContentView(friendListView()) })
    root.addView(button("返回") { setContentView(businessShell()) })
    return root
  }

  private fun profileView(): View {
    return column().apply {
      addView(title("我的")); addView(note("这里承载业务个人资料、设置、主题和语言设置。IM 外观可通过 client.updateAppearance(...) 无需重新登录。"))
      addView(button("返回") { setContentView(businessShell()) })
    }
  }

  private fun openChat(id: String, title: String) {
    val value = client ?: return
    conversationId.setText(id)
    chat = PteIMUIkit.createChatView(this, value, id, title).also { it.onActionRequested = ::handleAction }
    setContentView(chat)
  }

  /** Conversations are server-owned numeric IDs; never synthesize a c2c/group identifier in the client. */
  private fun openSingleChat(peerUserId: Long, title: String) {
    client?.openSingleConversation(peerUserId) { result -> runOnUiThread {
      result.onSuccess { conversation -> openChat(conversation.id.toString(), title) }
        .onFailure { error -> conversationId.error = "无法打开会话：${error.message}" }
    } }
  }

  private fun openDemoGroupChat() {
    val members = friends.map { it.substringAfter('(').substringBefore(')').toLong() }
    client?.createGroupConversation("PteIMUIDemo Group", members) { result -> runOnUiThread {
      result.onSuccess { conversation -> openChat(conversation.id.toString(), conversation.title) }
        .onFailure { error -> conversationId.error = "无法创建群组：${error.message}" }
    } }
  }

  private fun handleAction(action: PteIMUIAction) {
    when (action) {
      PteIMUIAction.IMAGE, PteIMUIAction.VIDEO, PteIMUIAction.VOICE -> {
        pendingAction = action
        startActivityForResult(Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
          type = when (action) { PteIMUIAction.IMAGE -> "image/*"; PteIMUIAction.VIDEO -> "video/*"; else -> "audio/*" }
          addCategory(Intent.CATEGORY_OPENABLE)
        }, 7)
      }
      PteIMUIAction.LOCATION -> client?.sendLocation(conversationId.text.toString(), PteIMLocation(31.2304, 121.4737, "Shanghai", "PteIMUIDemo"))
      PteIMUIAction.GIFT -> sendBusiness(PteIMMessageType.GIFT)
      PteIMUIAction.RED_PACKET -> sendBusiness(PteIMMessageType.RED_PACKET)
      PteIMUIAction.ORDER -> sendBusiness(PteIMMessageType.ORDER)
    }
  }

  @Deprecated("Deprecated in Java")
  override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
    super.onActivityResult(requestCode, resultCode, data)
    val uri: Uri = data?.data ?: return
    when (pendingAction) {
      PteIMUIAction.IMAGE -> client?.uploadAndSendImage(conversationId.text.toString(), uri)
      PteIMUIAction.VIDEO -> client?.uploadAndSendVideo(conversationId.text.toString(), uri)
      PteIMUIAction.VOICE -> client?.uploadAndSendVoice(conversationId.text.toString(), uri, 1_000)
      else -> Unit
    }
  }

  private fun sendBusiness(type: PteIMMessageType) {
    val content = PteIMBusinessContent("demo-${System.currentTimeMillis()}", type.name, "Handled by PteIMUIDemo business layer")
    when (type) { PteIMMessageType.GIFT -> client?.sendGift(conversationId.text.toString(), content); PteIMMessageType.RED_PACKET -> client?.sendRedPacket(conversationId.text.toString(), content); else -> client?.sendOrder(conversationId.text.toString(), content) }
  }

  private fun column() = LinearLayout(this).apply { orientation = LinearLayout.VERTICAL; setPadding(32, 28, 32, 28) }
  private fun title(value: String) = TextView(this).apply { text = value; textSize = 24f }
  private fun note(value: String) = TextView(this).apply { text = value; setPadding(0, 12, 0, 12) }
  private fun button(value: String, action: () -> Unit) = Button(this).apply { text = value; isAllCaps = false; setOnClickListener { action() } }
  private fun field(hint: String, value: String): EditText = EditText(this).apply { this.hint = hint; setText(value); layoutParams = LinearLayout.LayoutParams(-1, -2) }
}

private data class PteIMUIDemoBusinessSession(val account: String, val userId: String, val userSig: String)

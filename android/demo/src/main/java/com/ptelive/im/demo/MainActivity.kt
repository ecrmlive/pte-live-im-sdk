package com.ptelive.im.demo

import android.app.Activity
import android.content.Intent
import android.net.Uri
import android.os.Bundle
import android.view.View
import android.widget.Button
import android.widget.EditText
import android.widget.LinearLayout
import android.widget.TextView
import com.ptelive.im.PteIMBusinessContent
import com.ptelive.im.PteIMLocation
import com.ptelive.im.PteIMMessageType
import com.ptelive.im.PteLiveIM
import com.ptelive.im.PteIMBaseConfig
import com.ptelive.im.PteIMLoginConfig
import com.ptelive.im.ui.PteIMUIAction
import com.ptelive.im.ui.PteIMUIChatView
import com.ptelive.im.ui.PteIMUIKit

/** The demo only handles runtime login and host-owned pickers; chat UI comes from PteIMUIKit. */
class MainActivity : Activity() {
  private var client: PteLiveIM? = null
  private var chat: PteIMUIChatView? = null
  private lateinit var conversationId: EditText
  private var pendingAction: PteIMUIAction? = null

  override fun onCreate(savedInstanceState: Bundle?) { super.onCreate(savedInstanceState); setContentView(loginView()) }
  override fun onDestroy() { client?.stop(); super.onDestroy() }

  private fun loginView(): View {
    val root = LinearLayout(this).apply { orientation = LinearLayout.VERTICAL; setPadding(32, 28, 32, 28) }
    val api = field("API domain", "https://api.example.com")
    val im = field("IM WSS URL", "wss://im.example.com/ws")
    val cos = field("COS domain", "https://cos.example.com")
    val appId = field("SDK App ID", "1400000001")
    val userId = field("Numeric user ID", "10001")
    val userSig = field("UserSig", "")
    conversationId = field("Conversation ID", "c2c:10001:10002")
    root.addView(TextView(this).apply { text = "PteIMUIKit · Android"; textSize = 24f })
    root.addView(TextView(this).apply { text = "仅示例运行时登录；所有聊天 UI 来自 PteIMUIKit。" })
    listOf(api, im, cos, appId, userId, userSig, conversationId).forEach(root::addView)
    root.addView(Button(this).apply { text = "Connect"; setOnClickListener {
      runCatching {
        client?.stop()
        PteLiveIM.configure(applicationContext, PteIMBaseConfig(api.text.toString(), im.text.toString(), cos.text.toString()))
          .login(PteIMLoginConfig(appId.text.toString().toLong(), userId.text.toString(), userSig.text.toString()))
      }.onSuccess { openChat(it) }.onFailure { text = "Configuration error: ${it.message}" }
    } })
    return root
  }

  private fun openChat(value: PteLiveIM) {
    client = value
    chat = PteIMUIKit.createChatView(this, value, conversationId.text.toString()).also { view ->
      view.onActionRequested = ::handleAction
    }
    setContentView(chat)
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
      PteIMUIAction.LOCATION -> client?.sendLocation(conversationId.text.toString(), PteIMLocation(31.2304, 121.4737, "Shanghai", "PteIMUIKit demo"))
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
    val content = PteIMBusinessContent("demo-${System.currentTimeMillis()}", type.name, "Handled by the host app")
    when (type) { PteIMMessageType.GIFT -> client?.sendGift(conversationId.text.toString(), content); PteIMMessageType.RED_PACKET -> client?.sendRedPacket(conversationId.text.toString(), content); else -> client?.sendOrder(conversationId.text.toString(), content) }
  }

  private fun field(hint: String, value: String): EditText = EditText(this).apply { this.hint = hint; setText(value); layoutParams = LinearLayout.LayoutParams(-1, -2) }
}

package com.ptelive.im.ui

import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.viewinterop.AndroidView
import com.ptelive.im.PteIMSDK

/**
 Compose-first entry points for PteIMUIKit.

 The existing View controls remain public so host apps can incrementally adopt
 Compose without losing XML, Fragment, or legacy Activity integrations.
 */
object PteIMUIKitCompose {
  @Composable
  fun Chat(
    client: PteIMSDK,
    conversationId: String,
    title: String = conversationId,
    modifier: Modifier = Modifier,
    theme: PteIMUITheme = PteIMUITheme(),
    onActionRequested: ((PteIMUIAction) -> Unit)? = null,
    onVoiceRecordingChanged: ((Boolean) -> Unit)? = null,
  ) {
    AndroidView(
      modifier = modifier,
      factory = { context ->
        PteIMUIKit.createChatView(context, client, conversationId, title, theme).apply {
          this.onActionRequested = onActionRequested
          this.onVoiceRecordingChanged = onVoiceRecordingChanged
        }
      },
      update = { view ->
        view.setTheme(theme)
        view.onActionRequested = onActionRequested
        view.onVoiceRecordingChanged = onVoiceRecordingChanged
      },
    )
  }

  @Composable
  fun ConversationList(
    client: PteIMSDK,
    modifier: Modifier = Modifier,
    theme: PteIMUITheme = PteIMUITheme(),
    onConversationClick: (String) -> Unit,
  ) {
    AndroidView(
      modifier = modifier,
      factory = { context -> PteIMUIKit.createConversationListView(context, client, theme, onConversationClick) },
      update = { view -> view.setTheme(theme) },
    )
  }

  @Composable
  fun ContactList(
    client: PteIMSDK,
    modifier: Modifier = Modifier,
    mode: PteIMUIContactListMode = PteIMUIContactListMode.FRIENDS,
    theme: PteIMUITheme = PteIMUITheme(),
    onConversationClick: (conversationId: String, title: String) -> Unit,
  ) {
    AndroidView(
      modifier = modifier,
      factory = { context -> PteIMUIKit.createContactListView(context, client, mode, theme, onConversationClick) },
      update = { view -> view.setTheme(theme) },
    )
  }
}

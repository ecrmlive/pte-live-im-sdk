package com.ptelive.im.ui

import androidx.compose.runtime.Composable
import androidx.compose.runtime.rememberUpdatedState
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
    avatarUrl: String? = null,
    avatarText: String? = null,
    navigationSubtitleText: String? = null,
    backIconRes: Int? = null,
    onBackRequested: (() -> Unit)? = null,
    onActionRequested: ((PteIMUIAction) -> Unit)? = null,
    onVoiceRecordingChanged: ((Boolean) -> Unit)? = null,
  ) {
    val latestOnBack = rememberUpdatedState(onBackRequested)
    val latestOnAction = rememberUpdatedState(onActionRequested)
    val latestOnVoice = rememberUpdatedState(onVoiceRecordingChanged)
    AndroidView(
      modifier = modifier,
      factory = { context ->
        PteIMUIKit.createChatView(context, client, conversationId, title, theme).apply {
          this.onBackRequested = { latestOnBack.value?.invoke() }
          this.onActionRequested = { action -> latestOnAction.value?.invoke(action) }
          this.onVoiceRecordingChanged = { recording -> latestOnVoice.value?.invoke(recording) }
          this.navigationSubtitleText = navigationSubtitleText
          backIconRes?.let { backIconResource = it }
          setNavigationPeer(title, avatarUrl, avatarText)
        }
      },
      update = { view ->
        view.setTheme(theme)
        view.onBackRequested = { latestOnBack.value?.invoke() }
        view.onActionRequested = { action -> latestOnAction.value?.invoke(action) }
        view.onVoiceRecordingChanged = { recording -> latestOnVoice.value?.invoke(recording) }
        view.navigationSubtitleText = navigationSubtitleText
        backIconRes?.let { view.backIconResource = it }
        val nextTitle = title.ifBlank { view.navigationTitleText }
        val nextAvatar = avatarUrl?.takeIf { it.isNotBlank() }
        val nextAvatarText = avatarText?.takeIf { it.isNotBlank() }
          ?: nextTitle.take(1).ifBlank { "#" }
        val peerChanged =
          view.navigationTitleText != nextTitle ||
            view.navigationAvatarUrl != nextAvatar ||
            view.navigationAvatarText != nextAvatarText ||
            (backIconRes != null && view.backIconResource != backIconRes)
        if (peerChanged) {
          backIconRes?.let { view.backIconResource = it }
          view.setNavigationPeer(nextTitle, nextAvatar, nextAvatarText)
        } else {
          view.applyTheme()
        }
      },
    )
  }

  @Composable
  fun ConversationList(
    client: PteIMSDK,
    modifier: Modifier = Modifier,
    theme: PteIMUITheme = PteIMUITheme(),
    showHeader: Boolean = true,
    emptyText: String? = null,
    /** Bump to force a list rebuild after host peer-meta enrichment. */
    presentationRevision: Int = 0,
    presentationTransformer: ((PteIMUIConversationPresentation, Int) -> PteIMUIConversationPresentation)? = null,
    onConversationClick: (String) -> Unit,
    onConversationSelected: ((conversationId: String, title: String, avatarUrl: String?) -> Unit)? = null,
  ) {
    val latestClick = rememberUpdatedState(onConversationClick)
    val latestSelected = rememberUpdatedState(onConversationSelected)
    val latestTransformer = rememberUpdatedState(presentationTransformer)
    AndroidView(
      modifier = modifier,
      factory = { context ->
        PteIMUIKit.createConversationListView(context, client, theme) { id ->
          latestClick.value(id)
        }.apply {
          this.showHeader = showHeader
          this.emptyText = emptyText
          this.presentationTransformer = { item, index ->
            latestTransformer.value?.invoke(item, index) ?: item
          }
          this.onConversationSelected = { item ->
            val rich = latestSelected.value
            if (rich != null) {
              rich(item.conversationId, item.title, item.avatarUrl)
            } else {
              latestClick.value(item.conversationId)
            }
          }
          setTheme(theme)
        }
      },
      update = { view ->
        view.showHeader = showHeader
        view.emptyText = emptyText
        view.presentationTransformer = { item, index ->
          latestTransformer.value?.invoke(item, index) ?: item
        }
        view.onConversationSelected = { item ->
          val rich = latestSelected.value
          if (rich != null) {
            rich(item.conversationId, item.title, item.avatarUrl)
          } else {
            latestClick.value(item.conversationId)
          }
        }
        view.setTheme(theme)
        // Keep revision referenced so Compose re-enters update after host meta changes.
        if (presentationRevision >= 0) view.refresh()
      },
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
    val latestClick = rememberUpdatedState(onConversationClick)
    AndroidView(
      modifier = modifier,
      factory = { context ->
        PteIMUIKit.createContactListView(context, client, mode, theme) { id, title ->
          latestClick.value(id, title)
        }
      },
      update = { view -> view.setTheme(theme) },
    )
  }
}

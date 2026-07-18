# PteIMUIKit

`PteIMUIKit` is the native **UIKit** UI layer for the Swift `PteIMSDK` Core SDK. It does not use SwiftUI and does not own connection credentials. Login with `PteIMSDK`, then create UIKit controllers:

Shared conversation, contact and chat images are owned by UIKit itself. Login, launch and business-demo assets belong to `PteIMUIDemo`; no visual assets belong to `PteIMSDK`.

```swift
import PteIMUIKit

let client = try PteIMSDK.configure(baseConfig).login(loginConfig)
let chat = PteIMUIKit.makeChatViewController(
  client: client,
  conversationId: String(conversation.id), // Returned by openSingleConversation/createGroupConversation.
  title: "Alice"
)
chat.onActionRequested = { action, controller in
  // Gift/red-packet/order and host-defined action tiles are business-owned.
  // Use controller.sendCustomMessage(...) or your own server workflow here.
}
navigationController?.pushViewController(chat, animated: true)
```

Included UIKit components:

- `PteIMUIConversationListViewController`: cache-first conversations with pull-to-sync. Set `hostPresentations` when the host already owns display names, avatars, unread counts and row metadata; set it back to `nil` to use the Core cache again.
- `PteIMUIContactListViewController`: cursor-paginated friends, follows or groups (`.friends`, `.follows`, `.groups`); `.custom` retains host-provided rows. `PteIMUIContactPresentation.sectionTitle` enables host-defined sections and `isOnline` renders a host-owned presence dot; Core never fabricates presence.
- `PteIMUIChatViewController`: MessageKit-style renderer registry plus a MessageInputBar-style input delegate. It includes a native multiline text/emoji composer, image/video camera picker, document picker, map picker, durable upload/retry path, failure state, read/unread artwork, reactions, quote/copy/delete/revoke interaction and independent media preview factories. Override `makeMessageRenderers()`, `messageRenderer(for:)`, `makeInputBar()`, or the three `inputBar` callbacks to replace message cells, composer behavior, keyboard send logic, and attachment routing. The native keyboard uses `.send` and calls the same text-send route as the gradient button.
- `PteIMUIMessageCell`: reusable text, emoji and voice renderer.
- `PteIMUIRichMessageCell`: UIKit-native cards for image, video, location map snapshots, red packets, gifts, orders and files. It owns no business/payment state; tapping a card remains a host callback.
- `PteIMUINotice`: non-blocking success, error and information notices. It supports `.bottom` and `.center` presentation, automatic dismissal and replaces a prior notice on the same host view.
- `PteIMUITheme`, `PteIMUISkin`, `PteIMUIIconProvider`: independently configurable light/dark palettes, typography and replaceable images. `PteIMUIThemePalette.composerInputColor` controls the expanded composer field separately from panel items. `PteIMUIIconKey.messageImagePlaceholder`, `.messageImagePreview`, `.messageVideoPlay`, `.messageRedPacketBackground` and `.messageGiftBackground` replace built-in rich-card artwork without copying resources into Core.

`PteIMUIKit` never creates a UserSig, stores COS secrets, or persists application credentials. Image, video, camera, file and location actions are available directly in UIKit. Gift, red-packet, order and custom business payloads remain host-owned through `onActionRequested` and `onCustomMessageRequested`, because payment and order contracts are application-specific.

## Built-in chat interaction

- Mixed text and emoji use the same Unicode draft and are sent through the native keyboard send action. Failed text/business messages can be requeued by tapping the failed outgoing cell; failed media uploads retry from the retained sandbox file.
- Long-press any message for quote and reactions. Text additionally exposes copy; the sender's own messages additionally expose revoke and delete. UIKit applies the visual change immediately and emits `onQuoteRequested`, `onMessageRevoked`, `onMessageDeleted`, `onReactionToggled`, and `onMessageRetryRequested` for the host to persist or reconcile with its server.
- Tapping an image opens `PteIMUIImagePreviewController` (tap to dismiss, long press to save to Photos); video opens `PteIMUIVideoPreviewController` (play/pause, close and progress); file opens `PteIMUIFilePreviewController` (Quick Look and long-press export); location presents only installed third-party map apps in Amap/Baidu/Tencent/Google order, then Apple Maps.
- Override `makeImagePreviewController(for:)`, `makeVideoPreviewController(for:)`, `makeFilePreviewController(for:)`, and `makeLocationPicker()` to extend those pages without replacing the chat timeline.

Read/unread visuals map to Core send state. Server-side per-member read receipts, recalls, deletes and quote payloads remain protocol-owned: connect the callbacks above to the application's corresponding server contract rather than letting UIKit invent a wire format.

## Transient success and error notices

Use the same native notice for application-level outcomes, instead of placing
error text permanently inside a form or message cell:

```swift
PteIMUINotice.showError(
  "验证码加载失败",
  detail: error.localizedDescription,
  position: .bottom,
  in: viewController
)

PteIMUINotice.showSuccess("发送成功", position: .center, in: viewController)
```

`showInfo`, the general `show(_:detail:kind:position:duration:in:)`, and
`hide(in:animated:)` are also available when a host needs custom timing.

## Custom chat architecture

Conversation and contact controllers already expose `makeChatViewController(for:)`; subclass either list to route a person and a group into different chat subclasses. Inside a chat, use the renderer registry rather than branching the controller for every message kind:

```swift
final class OrderChatController: PteIMUIChatViewController {
  override func makeMessageRenderers() -> [PteIMUIChatMessageRenderer] {
    [OrderCardRenderer(), PteIMUIRichMessageRenderer(), PteIMUIBasicMessageRenderer()]
  }

  override func inputBar(_ inputBar: PteIMUIInputBar, didSendText text: String) {
    // Invoked by both the keyboard “发送” action and the gradient send button.
    sendText(text)
  }
}
```

For list-level UI replacement, override `registerConversationCells(in:)` / `conversationCellReuseIdentifier(for:)` / `configure(cell:presentation:at:)` or the corresponding `Contact` methods. The base controllers continue to own cache refresh, paging, search, theme and navigation.

`PteIMSDK` uses `PteIMListener` with `addListener` / `removeListener`, rather than one global callback slot. PteIMUIKit registers and removes its own listener automatically, so an application can keep a business listener for connection, UserSig renewal and error reporting while displaying one or more UIKit surfaces.

## Appearance and language preferences

The default `PteIMThemeMode.system` is automatic: it renders light mode from 07:00 (inclusive) to 19:00 (exclusive) in the device's local time, and dark mode otherwise. UIKit refreshes this at each boundary, when the app enters foreground, and after a significant system-time change. `PteIMLanguage.system` follows the device language (Chinese resolves to `zh-CN`; all other languages currently resolve to `en-US`).

Calling `client.updateAppearance(themeMode: .light)` / `.dark` or selecting `zh-CN` / `en-US` saves that account's choice in the app sandbox and uses it until changed. Call `client.resetAppearancePreferences()` to remove the saved override and return to the `PteIMBaseConfig` defaults.

When a chat is pushed from a tab host, `PteIMUIChatViewController` automatically hides the root tab bar so the composer owns the lower safe area. The conversation and contact controllers restore the host tab navigation when users return.

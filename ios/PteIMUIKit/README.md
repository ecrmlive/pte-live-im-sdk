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
  // Use your own photo/video/audio/location/business picker.
  // Then call controller.sendImage/sendVideo/sendVoice/sendLocation/... .
}
navigationController?.pushViewController(chat, animated: true)
```

Included UIKit components:

- `PteIMUIConversationListViewController`: cache-first conversations with pull-to-sync. Set `hostPresentations` when the host already owns display names, avatars, unread counts and row metadata; set it back to `nil` to use the Core cache again.
- `PteIMUIContactListViewController`: cursor-paginated friends, follows or groups (`.friends`, `.follows`, `.groups`); `.custom` retains host-provided rows.
- `PteIMUIChatViewController`: text composer, emoji helper, message rendering, send states, system light/dark mode, and action sheet for image/video/voice/location/gift/red-packet/order.
- `PteIMUIMessageCell`, `PteIMUIMessageText`, `PteIMUITheme`: reusable presentation layer components.

`PteIMUIKit` never creates a UserSig, stores COS secrets, or persists application credentials. Attachment and business actions are delegated to the host through `onActionRequested` because permission, picker, payment, and order flows are application-specific.

`PteIMSDK` uses `PteIMListener` with `addListener` / `removeListener`, rather than one global callback slot. PteIMUIKit registers and removes its own listener automatically, so an application can keep a business listener for connection, UserSig renewal and error reporting while displaying one or more UIKit surfaces.

When a chat is pushed from a tab host, `PteIMUIChatViewController` automatically hides the root tab bar so the composer owns the lower safe area. The conversation and contact controllers restore the host tab navigation when users return.

# PteIMUIkit

`PteIMUIkit` is the native **UIKit** UI layer for the Swift `PteIMSDK` Core SDK. It does not use SwiftUI and does not own connection credentials. Login with `PteIMSDK`, then create UIKit controllers:

```swift
import PteIMUIkit

let client = try PteIMSDK.configure(baseConfig).login(loginConfig)
let chat = PteIMUIkit.makeChatViewController(
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

- `PteIMUIConversationListViewController`: cache-first conversations with pull-to-sync.
- `PteIMUIChatViewController`: text composer, emoji helper, message rendering, send states, system light/dark mode, and action sheet for image/video/voice/location/gift/red-packet/order.
- `PteIMUIMessageCell`, `PteIMUIMessageText`, `PteIMUITheme`: reusable presentation layer components.

`PteIMUIkit` never creates a UserSig, stores COS secrets, or persists application credentials. Attachment and business actions are delegated to the host through `onActionRequested` because permission, picker, payment, and order flows are application-specific.

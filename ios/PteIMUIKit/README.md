# PteIMUIKit

`PteIMUIKit` is the native **UIKit** UI layer for the Swift `PteLiveIM` Core SDK. It does not use SwiftUI and does not own connection credentials. Login with `PteLiveIM`, then create UIKit controllers:

```swift
import PteIMUIKit

let client = try PteLiveIM.configure(baseConfig).login(loginConfig)
let chat = PteIMUIKit.makeChatViewController(
  client: client,
  conversationId: "c2c:10001:10002",
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

`PteIMUIKit` never creates a UserSig, stores COS secrets, or persists application credentials. Attachment and business actions are delegated to the host through `onActionRequested` because permission, picker, payment, and order flows are application-specific.

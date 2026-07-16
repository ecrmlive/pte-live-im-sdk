# PteIMUIKit UTS

`pte-im-uikit` is the independent uni-app x UI module. It supplies reusable UTS/uvue conversation, contact and chat views for H5/Web and WeChat mini-program applications. It depends on the sibling `pte-im-sdk` Core module, but does not contain Core transport, E2EE, local persistence, or credentials.

Copy both modules to the target application's `uni_modules` directory:

```text
uni_modules/pte-im-sdk
uni_modules/pte-im-uikit
```

Create and log in to `PteIMSDK` first, then pass the logged-in client to the UI component:

```vue
<PteIMUIChat :client="im" :conversation-id="conversationId" @action="handlePteIMAction" />
```

The module includes `PteIMUIConversationList`, `PteIMUIContactList`, `PteIMUIChat`, and the standalone `PteIMUIInputBar`. `PteIMUIKitFacade.uts` exports controllers and `PteIMUITheme` for custom UTS view integrations. Pass the same `PteIMUITheme` to all three surfaces to keep light/dark palettes consistent:

```vue
<PteIMUIConversationList :client="im" :theme="skin" @select="openChat" />
<PteIMUIContactList :client="im" :theme="skin" mode="friends" @select="openChat" />
<PteIMUIChat :client="im" :theme="skin" :conversation-id="conversationId" />
```

Controllers subscribe through Core's `PteIMListener` registration and release that subscription in `dispose()`, so the host's business listener is not replaced by UIKit. UI asset ownership is limited to this module's shared conversation/contact/chat resources; runtime code must not depend on the local design-source directory.

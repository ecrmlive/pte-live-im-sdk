# PteIMSDK architecture

`PteIMSDK` is the transport and state layer: business/API calls, WSS, message envelopes, E2EE, durable Outbox, synchronization, COS upload and platform local storage. It receives `PteIMBaseConfig` once at startup and `PteIMLoginConfig` only after the host business service authenticates the user.

`PteIMUIKit` receives an already-logged-in Core client. It contains conversation lists and one-to-one/group chats, tracks Core message and appearance callbacks, and asks the host to supply permission-sensitive media, location and business workflows. It never generates a UserSig or stores credentials.

`PteIMUIDemo` is not a UI kit alias. It is a separate application-level example: business login → backend response (`userId`, short-lived `userSig`) → PteIMSDK login → business friend/profile pages and embedded PteIMUIKit conversation, chat and group screens.

| Platform | PteIMSDK | PteIMUIKit | PteIMUIDemo |
| --- | --- | --- | --- |
| Android | `android/pte-im-sdk` | `android/pte-im-uikit` | `android/pte-im-ui-demo` |
| iOS | `ios/PteIMSDK` | `ios/PteIMUIKit` | `ios/PteIMUIDemo` |
| HarmonyOS | `harmony/PteIMSDK` | `harmony/PteIMUIKit` | `harmony/PteIMUIDemo` |
| uni-app x | `uni_modules/pte-im-sdk` for H5/Web and WeChat | uvue components and UTS controllers | `uniapp-x/PteIMUIDemo` |

`PteIMBaseConfig` carries `apiDomain`, `imDomain`, `cosDomain`, `themeMode` and `language`. `updateAppearance(themeMode, language)` updates light/dark/system and Chinese/English/system without reconnecting or changing UserSig. Core uses independently registered `PteIMListener` instances, so the business layer plus conversation, contact and chat UIKit surfaces can receive events concurrently; owners unregister their listener when disposed. `PteIMUIKit` consumes the corresponding events to redraw immediately.

The COS flow is: API returns a signed PUT target and object key → client uploads bytes to COS → client stores/sends only the key → host resolves file access under `cosDomain`. The backend, not the client, owns COS secrets and UserSig generation.

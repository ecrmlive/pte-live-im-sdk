# PteIMSDK architecture

`PteIMSDK` is the transport and state layer: business/API calls, WSS, message envelopes, E2EE, durable Outbox, synchronization, COS upload and platform local storage. It receives `PteIMBaseConfig` once at startup and `PteIMLoginConfig` only after the host business service authenticates the user. UserSig lifecycle is Core behavior: the login config can include an expiry and a host-owned `userSigProvider`; Core schedules renewal and reacts to transport/API expiry while the host remains responsible for business authentication and refresh-session persistence.

`PteIMUIKit` receives an already-logged-in Core client. It contains only IM-generic surfaces: conversation lists, contact/group lists, one-to-one/group chat, composer, media preview and reusable notice presentation. It tracks Core message and appearance callbacks, and asks the host to supply permission-sensitive media, location and business workflows. It never generates a UserSig, stores credentials, or owns a business route.

`PteIMUIDemo` is not a UI kit alias. It is a separate application-level example: business registration/login → backend response (`userId`, short-lived `userSig`, `expireAt`, host-owned refresh session) → PteIMSDK login → embedded PteIMUIKit conversation/contact/chat screens. The Demo maps that refresh session into `userSigProvider`; Core, rather than a page timer, owns UserSig renewal. Login, registration, Demo navigation, TabBar, profile, settings, language choice, registered-demo-user list, add-friend/group workflow, demo fixtures and their image assets belong exclusively to this layer.

| Platform | PteIMSDK | PteIMUIKit | PteIMUIDemo |
| --- | --- | --- | --- |
| Android | `android/pte-im-sdk` | `android/pte-im-uikit` | `android/pte-im-ui-demo` |
| iOS | `ios/PteIMSDK` | `ios/PteIMUIKit` | `ios/PteIMUIDemo` |
| HarmonyOS | `harmony/PteIMSDK` | `harmony/PteIMUIKit` | `harmony/PteIMUIDemo` |
| uni-app x | `uni_modules/pte-im-sdk` for H5/Web and WeChat | uvue components and UTS controllers | `uniapp-x/PteIMUIDemo` |
| Browser (standalone) | `packages/im-web-sdk` (`@pte-live/im-web-sdk`) | — | — |

The Browser package is a separate TypeScript Core for secure-context browsers. `PteLiveIMWebClient` speaks the same UserSig, encrypted REST, WSS and E2EE chat contracts as the native/UTS cores. `@pte-live/im-web-sdk/live` only helps hosts apply live-room `eventType` + `roomSeq` catch-up; it does not own WSS join or business HTTP. See [live-event-protocol.md](live-event-protocol.md) and [packages/im-web-sdk/README.md](../packages/im-web-sdk/README.md).

## UI ownership boundary

| Category | PteIMUIKit | PteIMUIDemo |
| --- | --- | --- |
| Pages | Conversation, contact/group and chat only | Login, register, TabBar, profile, settings, language and demo-user pages |
| Navigation | IM-page title/back/action extension points only | Login/register navigation, routing, TabBar and mini-program capsule safe-area treatment |
| Data | SDK-backed IM state only; no fixture fallback | Demo users, preview data and business action samples |
| Assets | Chat/list/input/media assets only | Brand, login, TabBar, profile, settings, language and Demo-only assets |

An application can replace `PteIMUIDemo` entirely. `PteIMUIKit` remains usable with any host navigation and business UI.

`PteIMBaseConfig` carries `apiDomain`, `imDomain`, `cosDomain`, `themeMode` and `language`. `updateAppearance(themeMode, language)` updates light/dark/system and Chinese/English/system without reconnecting or changing UserSig. When login includes both `userSigExpireAt` and `userSigProvider`, Core renews UserSig five minutes before expiry and after IM HTTP `401` or WSS expiry events, then updates its connection and syncs. A failure is reported once through `onUserSigRefreshFailed`, at which point the host returns to business login; the SDK neither stores nor refreshes the business session itself. Core uses independently registered `PteIMListener` instances, so the business layer plus conversation, contact and chat UIKit surfaces can receive events concurrently; owners unregister their listener when disposed. `PteIMUIKit` consumes the corresponding events to redraw immediately.

The COS flow is: API returns a signed PUT target and object key → client uploads bytes to COS → client stores/sends only the key → host resolves file access under `cosDomain`. The backend, not the client, owns COS secrets and UserSig generation.

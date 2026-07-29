# PteIMSDK architecture

`PteIMSDK` is the transport and state layer: business/API calls, WSS, message envelopes, E2EE, durable Outbox, synchronization, COS upload and platform local storage. It receives `PteIMBaseConfig` once at startup and `PteIMLoginConfig` only after the host business service authenticates the user. UserSig lifecycle is Core behavior: the login config can include an expiry and a host-owned `userSigProvider`; Core schedules renewal and reacts to transport/API expiry while the host remains responsible for business authentication and refresh-session persistence.

`PteIMUIKit` receives an already-logged-in Core client. It contains only IM-generic surfaces: conversation lists, contact/group lists, one-to-one/group chat, composer, media preview and reusable notice presentation. It tracks Core message and appearance callbacks, and asks the host to supply permission-sensitive media, location and business workflows. It never generates a UserSig, stores credentials, or owns a business route.

## 消息与 Commerce 边界

消息的创建、E2EE 信封、历史、同步、引用、撤回、单账户删除、表情反应和 `message_event` 实时投递都由 IM Core 与 `api-im` 负责。UIKit 对这些状态只做展示和可选通知；宿主回调不能替代协议状态持久化。

礼物、红包和订单有两层边界：**聊天卡片是 IM 消息**，由 Core 发送、加密、同步和展示；卡片中只引用业务 ID。**资金、库存、领取、支付、履约和订单状态是 Commerce 业务**，由 `pte-live-im-commerce` 保存和处理。当前实现由客户端在 Commerce 成功后显式调用 Core 的 `sendGift`、`sendRedPacket` 或 `sendOrder` 发送引用卡片；Commerce Outbox 发送的是房间业务事件，不会直接创建聊天消息。未来若增加服务端可信写消息桥接，必须以独立内部鉴权、幂等键和审计契约实现，不能由客户端伪造业务状态。

引用、撤回、删除与反应的精确权限、REST/WSS 字段和逐端状态见[消息生命周期](message-lifecycle.md)。

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

# Architecture

## Product boundary

Android (Kotlin), iOS (Swift), and HarmonyOS (ArkTS) each have an independent native Core SDK. `uni_modules/pte-live-im` is a separate uni-app x UTS SDK for H5/Web and WeChat mini-programs only. It does not wrap, bundle, or replace a native SDK.

The Core SDK owns authentication, WSS, REST synchronization, a durable outbox, media upload, and message state. Every target has a separate `PteIMUIKit`: `android/im-ui-kit` (native View), `ios/PteIMUIKit` (UIKit), `harmony/PteIMUIKit` (ArkUI), and UTS `PteIMUIChat` / `PteIMUIConversationList` components. Each receives an already-logged-in Core client, follows Core theme/language callbacks, and delegates permission-sensitive media, location, gift, red-packet, and order flows back to the host.

## Local storage

Android, iOS, and HarmonyOS use SQLite/relational-store with these logical tables:

| Table | Role |
| --- | --- |
| `meta` | schema version and account identity |
| `sync_state` | last committed `syncCursor` |
| `conversations` | summaries, unread counts, version |
| `messages` | message bodies and `serverSeq` |
| `outbox` | pending / uploading / sent / failed messages |

The local-store identity is the normalized `apiDomain`, normalized `imDomain`, normalized `cosDomain`, `sdkAppId`, and `userId`. Switching any of these opens a different store and never erases an old one.

The native Cores expose `localConversations()` and `localMessages()` for cache-first rendering. They never manufacture group metadata: the server remains authoritative for C2C/group membership, unread counts, read receipts, and conversation attributes.

## Outbox retry

Each outgoing metadata message receives a stable `clientMsgId` before it is stored. While connected, the Core records every send attempt and retries unacknowledged outbox rows after a persisted exponential backoff (1, 2, 4, 8, 16, then 32 seconds). Reconnecting or restarting the app resumes due rows. The server must treat `clientMsgId` as an idempotency key. Upload failures are terminal because a local upload source is not retained; the host should begin a new upload.

The three native SDKs retain SQLite account isolation and synchronization. H5/Web and WeChat mini-program UTS only persist the account-isolated outgoing metadata outbox, `syncCursor`, and latest 1,000 confirmed messages when the host provides `localStorageCipher`; otherwise these values stay in memory to avoid a plaintext cache. `localMessages()` and `localConversations()` are cache-first helpers, not a replacement for remote history pagination.

The UTS WSS core for H5/Web and WeChat mini-program has connection, message, ACK, UserSig, send-state, error events, a 1–32 second outgoing retry backoff, and 1–30 second reconnect backoff. It calls the host-provided `POST /v1/im/sync` contract on connection and `sync_required`; synced messages are emitted through `onMessage`. `uploadAndSendImage` and `uploadAndSendVideo` read the selected bytes, request a COS PUT credential, PUT the bytes, then persist an outbox row containing only the returned key when encrypted persistence is configured. It intentionally does not claim native SQLite or remote-history pagination.

## Themes and language

`PteIMBaseConfig` carries the initial `themeMode` and `language` (`system`, light/dark, and `zh-CN`/`en-US`). The Core remains UI-free; `PteIMUIKit` reads these values and follows the OS when `system` is selected. Android, iOS, and HarmonyOS Cores expose `updateAppearance(themeMode, language)` and callbacks so the UI Kit can refresh immediately without reconnecting or replacing `userSig`.

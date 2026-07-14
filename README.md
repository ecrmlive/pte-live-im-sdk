# PteLive IM SDK

Native Android, native iOS, native HarmonyOS, and uni-app x UTS SDKs for PteLive IM.

The SDKs share the same protocol (`protocolVersion: 1`), login parameters, message model, and incremental-sync rules. The native Cores send text, emoji, image, video, voice, location, gift, red-packet, and order messages.

## Packages

| Package | Path | Runtime |
| --- | --- | --- |
| Android Core | `android/im-sdk` | Android API 24+ |
| iOS Core | `ios/PteLiveIM` | iOS 15+ |
| HarmonyOS Core | `harmony/PteLiveIM` | HarmonyOS / ArkTS |
| uni-app x UTS plugin | `uni_modules/pte-live-im` | H5/Web and WeChat mini-program |

The Core packages have no UI. Each exposes system-theme helpers for an optional host-owned chat UI.

## Login

Configure base connectivity once at App startup, then authenticate separately:

```text
apiDomain  HTTPS SDK REST gateway (routes durable data to api-chat and COS credentials to api-im)
imDomain   WSS URL for the real-time connection, including /ws
cosDomain  HTTPS COS/CDN root used to resolve uploaded media object keys
sdkAppId   IM application identifier
userId     authenticated user identifier
userSig    short-lived server-issued credential (login only)
```

`api-im` authenticates the WSS upgrade itself. SDKs add the URL-encoded, short-lived `sdkAppID`、`identifier` and `userSig` handshake parameters internally; hosts pass only the clean `imDomain` configured above and must not log the resulting WebSocket URL.

See [the protocol contract](docs/protocol.md) and [the implementation plan](docs/architecture.md).

## Send media

The Core packages first obtain a short-lived COS PUT credential from `POST /v1/im/media/put-url`, upload the bytes directly to COS, and then send the returned object `key` in one operation:

```text
Android  uploadAndSendImage(conversationId, contentUri)
iOS      uploadAndSendImage(conversationId: conversationId, fileURL: fileURL)
Harmony  uploadAndSendImage(conversationId, filePath, mimeType)
All      uploadAndSendVoice(conversationId, source, durationMs, waveform?)
```

Harmony、H5/Web、微信小程序均支持 `uploadAndSendImage` 和 `uploadAndSendVideo`；相对对象键由 `cosDomain` 解析。也可用 `sendImage`、`sendVideo` 直接发送已有媒体描述符。

`api-im` owns the COS signing credentials. The SDK never receives a COS SecretId or SecretKey; it receives only an expiring URL scoped to one object key. The persistent IM message stores that key, while `cosDomain` resolves keys only when rendering an access URL.

## Cache-first conversations

After realtime delivery or `syncNow`, native Core callers can render the account-isolated SQLite cache without inventing server state:

```text
Android  localConversations(), localMessages(conversationId, beforeCreatedAt, limit)
iOS      localConversations(), localMessages(conversationId:beforeCreatedAt:limit:)
Harmony  localConversations(), localMessages(conversationId, beforeCreatedAt, limit)
```

The server remains authoritative for C2C/group membership, conversation attributes, unread/read state, and remote history pagination.

Create a server-authoritative conversation before sending its first message:

```text
Android  openSingleConversation(peerUserId, callback)
iOS      await openSingleConversation(peerUserId:)
Harmony  await openSingleConversation(peerUserId)
UTS      openSingleConversation(peerUserId, callback)

All      createGroupConversation(title, memberIds, avatar?)
```

The API derives the C2C initiator and group owner from the current UserSig; a client cannot provide a different owner ID.

After rendering a conversation, call `markConversationRead(conversationId, seq)` to advance the authenticated user's read cursor and clear the server-side unread count. Passing `0` reads through the latest message.

Outgoing metadata messages are persisted before transmission. Until a server ACK arrives, the native SDKs retry them with a persisted 1–32 second exponential backoff; reconnecting or restarting resumes the account's outbox. The service must use `clientMsgId` as its idempotency key.

## Security

Use HTTPS and WSS in production. `userSig` is never persisted in the message database. The service must verify the binding among `sdkAppId`, `userId`, and `userSig`.

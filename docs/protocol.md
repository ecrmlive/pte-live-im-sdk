# IM protocol v1

## Login configuration

`PteIMBaseConfig` is configured once at App startup with `apiDomain`, `imDomain`, and `cosDomain`. `PteIMLoginConfig` is supplied only when logging in with `sdkAppId`, `userId`, and `userSig`. `userId` is a positive numeric string such as `"10001"`; the SDK preserves it as a string for cross-platform compatibility but the IM service indexes it as an integer. `apiDomain` must be an HTTPS origin without an API path. Its public gateway routes durable `/v1/im/*` requests to `api-chat`, except `/v1/im/media/put-url`, which routes to `api-im`. `imDomain` must be a complete WSS URL and include `/ws`; `cosDomain` must be the HTTPS root for COS/CDN media objects.

The `userSig` is short-lived. When the SDK emits `userSigWillExpire` or `userSigExpired`, the host obtains a replacement from its own backend and calls `renewUserSig`. `api-im` authenticates the initial WSS upgrade, therefore all SDKs append URL-encoded `sdkAppID`, `identifier` (the numeric `userId`), and `userSig` to `imDomain`; WSS protects these short-lived query values in transit. Do not log complete WebSocket URLs or reuse UserSig values.

## Wire envelope

```json
{
  "protocolVersion": 1,
  "action": "send_message",
  "requestId": "uuid",
  "sdkAppId": 1400000001,
  "userId": "10001",
  "userSig": "credential",
  "payload": {}
}
```

The server responds or pushes an envelope with `action`, `requestId` when applicable, and `payload`. Every data-changing event has a monotonically increasing `syncCursor` and message events additionally have a per-conversation `serverSeq`.

## Message payload

```json
{
  "clientMsgId": "uuid",
  "serverMsgId": "server assigned after acceptance",
  "conversationId": "c2c:user_10001:user_10002",
  "type": "text | emoji | image | video | voice | location | gift | red_packet | order",
  "createdAt": 1760000000000,
  "content": {
    "text": "hello 😀",
    "packageId": "default",
    "emojiId": "smile_001",
    "url": "https://cdn.example.com/media/object",
    "thumbnailUrl": "https://cdn.example.com/media/thumbnail",
    "coverUrl": "https://cdn.example.com/media/cover",
    "width": 1080,
    "height": 1920,
    "durationMs": 12000,
    "sizeBytes": 1048576,
    "waveform": "base64-or-sampled-waveform",
    "latitude": 31.2304,
    "longitude": 121.4737,
    "name": "PteLive",
    "address": "Shanghai",
    "businessId": "gift_or_payment_or_order_id",
    "title": "Business card title",
    "subtitle": "Optional summary",
    "actionUrl": "https://app.example.com/action"
  }
}
```

Only fields applicable to the selected type are present: `voice` uses `url`, `durationMs`, optional `waveform` and `sizeBytes`; `location` uses `latitude`, `longitude`, `name`, and optional `address`; `gift`, `red_packet`, and `order` use `businessId`, `title`, optional `subtitle`, and optional `actionUrl`. The server treats `clientMsgId` as an idempotency key.

## Durable API contract required from `api-chat`

| Endpoint | Purpose |
| --- | --- |
| `POST /v1/im/sync` | Incremental changes after `syncCursor`; returns `nextCursor` and `hasMore` |
| `POST /v1/im/conversations/open-single` | UserSig-protected open/create C2C; body `{ peerUserId }` |
| `POST /v1/im/conversations/create-group` | UserSig-protected group creation; body `{ title, memberIds, avatar? }` |
| `POST /v1/im/conversations/read` | UserSig-protected read cursor; body `{ conversationId, seq }`, with `seq: 0` meaning latest |
| `POST /v1/im/conversations` | UserSig-protected conversation page; body `{ page, pageSize }` |
| `POST /v1/im/conversations/messages` | UserSig-protected history page; body `{ conversationId, beforeSeq, limit }` |
| `POST /v1/im/media/put-url` | `api-im` UserSig-protected COS credential; body `{ mediaType, contentType, contentLength }`, returns `{ key, uploadUrl, headers, expiresAt }` |

Conversation and history schemas belong in `pte-live-im/im-api/docs/openapi.yaml`; the COS credential schema belongs in `pte-live-im/im/docs/openapi.yaml`. This SDK repository only consumes both contracts.

For media, the SDK calls `POST /v1/im/media/put-url` with its UserSig (`Authorization: Bearer`), `X-Pte-Sdk-AppId`, and `X-Pte-User-Id`. `api-im` verifies the UserSig, derives an object key in the verified user's namespace, and returns a short-lived COS `PUT` URL plus mandatory headers. The SDK performs the PUT, then persists/sends only `key` as `media.url` (or `voice.url`). Image/video dimensions and duration may be enriched by the host; `uploadAndSendVoice` requires the recording duration and accepts an optional waveform. `cosDomain` is used only to resolve a key for display. COS secrets are server-side YAML configuration and are never exposed to clients.

## Synchronization rules

1. The client opens its account-scoped local store and reads `syncCursor`. The cursor is the globally monotonic `chat_message.id` represented as a decimal string, and is scoped to the authenticated app/user.
2. It requests all deltas after that cursor, writes each page in one SQLite transaction, and advances the cursor only after commit.
3. Realtime events are committed before their ACK is sent. A missing `serverSeq` triggers an incremental sync.
4. A server `cursor_expired` response triggers a controlled snapshot sync. The client never silently deletes an existing database.

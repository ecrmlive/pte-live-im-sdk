# IM protocol v1

## Login configuration

`PteIMBaseConfig` is configured once at App startup with `apiDomain`, `imDomain`, and `cosDomain`. `PteIMLoginConfig` is supplied only when logging in with `sdkAppId`, `userId`, and `userSig`. `userId` is a positive numeric string such as `"10001"`; the SDK preserves it as a string for cross-platform compatibility but the IM service indexes it as an integer. `apiDomain` must be an HTTPS origin without an API path. It is the host application's API root for `/v1/im/*` requests. `imDomain` must be a complete WSS URL and include `/ws`; `cosDomain` must be the HTTPS root for COS/CDN media objects. Debug can set `allowInsecureLocalhost: true` only for `localhost` or loopback IPs (`127.0.0.1` / `::1`), enabling a local Docker `http`/`ws` stack. The default remains `false`, and non-local endpoints never bypass HTTPS/WSS validation. Android uses `10.0.2.2` through its own configuration; iOS Simulator uses `127.0.0.1`.

The `userSig` is short-lived. A host supplies `userSigExpireAt` and a `userSigProvider` that exchanges its own device-bound refresh session for `{ userSig, expireAt }`. Core schedules renewal five minutes before expiry and retries it after an IM HTTP 401 or WSS expiry event; it applies the renewed credential internally, reconnects when required, and syncs conversations. `onUserSigRefreshFailed` is the only terminal signal for returning to business login. The provider is deliberately the only business-auth extension point: it must not expose a UserSig signing secret, and the SDK does not store the refresh token. The configured real-time service authenticates the initial WSS upgrade, therefore all SDKs append URL-encoded `sdkAppID`, `identifier` (the numeric `userId`), and `userSig` to `imDomain`; WSS protects these short-lived query values in transit. Do not log complete WebSocket URLs or reuse UserSig values.

### AMap configuration for H5 and WeChat Mini Program

Pass the optional `map` field during bootstrap to make location-message navigation use the host's AMap integration. `h5Key` must be restricted to the H5 origin; `wechatMiniProgramKey` must be restricted to the Mini Program AppID. These are client identifiers, not server Web Service keys or other secrets.

```ts
const im = createPteIMSDK({
  apiDomain, imDomain, cosDomain,
  map: { provider: 'amap', h5Key: 'restricted-h5-key', wechatMiniProgramKey: 'restricted-mp-key' },
})
```

`PteIMUIChat` emits `location-navigation` with `location`, the configured map object, and a generated AMap URI. H5 hosts can configure `web.sdkConfigs.maps.amap` in `manifest.json`; H5 AMap additionally requires its `securityJsCode` or `serviceHost` when enabled in the AMap console. WeChat Mini Program does not expose an AMap field in `manifest.json`: its built-in `map` and `uni.openLocation` use Tencent Maps. A WeChat host that requires AMap must add AMap's WeChat Mini Program plugin/SDK and pass a `PteIMUIMapNavigationHandler`, returning `true` after that SDK opens. If no handler consumes the action, UIKit falls back to `uni.openLocation`.

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

For `send_message`, the client sends only routing metadata (`clientMsgId`, `conversationId`, `type`) and an `e2ee` object. Plain `content` is not sent over WSS. The precise E2EE object, device registration endpoints, encrypted API response header, and key-derivation labels are specified in [security.md](security.md).

## Message payload

```json
{
  "clientMsgId": "uuid",
  "serverMsgId": "server assigned after acceptance",
  "conversationId": "9000001",
  "senderId": "10001",
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

`conversationId` and `senderId` are positive numeric strings returned by the server; never construct a `c2c:*` or `group:*` identifier on the client. Compare `senderId` with `IMLoginConfig.userId` to render incoming or outgoing bubbles after cache reload; do not infer direction from `serverMsgId` or send state. Only fields applicable to the selected type are present: `voice` uses `url`, `durationMs`, optional `waveform` and `sizeBytes`; `location` uses `latitude`, `longitude`, `name`, and optional `address`; `gift`, `red_packet`, and `order` use `businessId`, `title`, optional `subtitle`, and optional `actionUrl`. The server treats `clientMsgId` as an idempotency key.

## SDK REST contract expected from the host API

| Endpoint | Purpose |
| --- | --- |
| `POST /v1/im/sync` | Incremental changes after `syncCursor`; returns `nextCursor` and `hasMore` |
| `POST /v1/im/profile/me` | UserSig-protected read of the caller's IM profile |
| `POST /v1/im/profile/update` | UserSig-protected one-field profile update; body `{ field, value }` |
| `POST /v1/im/conversations/open-single` | UserSig-protected open/create C2C; body `{ peerUserId }` |
| `POST /v1/im/conversations/create-group` | UserSig-protected group creation; body `{ title, memberIds, avatar? }` |
| `POST /v1/im/conversations/read` | UserSig-protected read cursor; body `{ conversationId, seq }`, with `seq: 0` meaning latest |
| `POST /v1/im/conversations` | UserSig-protected conversation page; body `{ page, pageSize }` |
| `POST /v1/im/conversations/messages` | UserSig-protected history page; body `{ conversationId, beforeSeq, limit }` |
| `POST /v1/im/media/put-url` | UserSig-protected COS credential; body `{ mediaType, contentType, contentLength }`, returns `{ key, uploadUrl, headers, expiresAt }` |

For the PteLive reference deployment, these requests are served by `api-im`. The SDK consumes the contract and does not depend on the service's internal deployment layout.

For media, the SDK calls `POST /v1/im/media/put-url` with its UserSig (`Authorization: Bearer`), `X-Pte-Sdk-AppId`, and `X-Pte-User-Id`. The host API verifies the UserSig, derives an object key in the verified user's namespace, and returns a short-lived COS `PUT` URL plus mandatory headers. The SDK performs the PUT, then persists/sends only `key` as `media.url` (or `voice.url`). Image/video dimensions and duration may be enriched by the host; `uploadAndSendVoice` requires the recording duration and accepts an optional waveform. `cosDomain` is used only to resolve a key for display. COS secrets are server-side YAML configuration and are never exposed to clients.

`POST /v1/im/profile/update` accepts exactly one `field` from `nickname`, `avatar`, `gender`, `birthday`, `province`, `city`, or `district`, plus one corresponding `value`. `gender` is `unknown`, `male`, or `female`; `birthday` uses `YYYY-MM-DD`. The server derives `userId` exclusively from the verified UserSig and returns the complete updated profile. It must reject unknown fields and malformed values. `avatar` is an already uploaded COS key or an allowed HTTPS URL; no COS secret or direct credential is involved.

## Synchronization rules

1. The client opens its account-scoped local store and reads `syncCursor`. The cursor is the globally monotonic `chat_message.id` represented as a decimal string, and is scoped to the authenticated app/user.
2. It requests all deltas after that cursor, writes each page in one platform-store transaction, and advances the cursor only after commit.
3. Realtime events are committed before their ACK is sent. A missing `serverSeq` triggers an incremental sync.
4. A server `cursor_expired` response triggers a controlled snapshot sync.

## Browser Web client

Standalone package `@pte-live/im-web-sdk` (`packages/im-web-sdk`) implements the same chat wire contract in the browser via `PteLiveIMWebClient`:

- Credentials: `apiUrl`, `wsUrl`, `sdkAppId`, `identifier` / `userId`, `userSig`, `expireAt`
- REST: `POST` to `/v1/im/*` with `Authorization: Bearer <userSig>`, `X-Pte-Sdk-AppId`, `X-Pte-User-Id`, and optional `X-Pte-Response-Public-Key` for encrypted responses
- WSS: append `sdkAppID`, `identifier`, `userSig` to `wsUrl`; envelopes use `protocolVersion: 1` and actions such as `login`, `send_message`, `ack`, `renew_user_sig`
- E2EE: register at `/api/v1/chat/e2ee/device/register`; outbound `send_message` carries only routing fields plus `e2ee` (no plain `content`)

Host renews UserSig through business auth, then calls `renewUserSig({ userSig, expireAt })`. This package does not ship UIKit.

Live-room fan-out (`sports.*` / `shop.*` / `scene.*`) is a separate path: hosts own WSS `scene.enter` and business catch-up HTTP; use `@pte-live/im-web-sdk/live` for `eventType` / `roomSeq` helpers. See [live-event-protocol.md](live-event-protocol.md).

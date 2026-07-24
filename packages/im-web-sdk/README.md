# `@pte-live/im-web-sdk`

独立 Browser Core：现代浏览器中的聊一聊（E2EE + 加密 REST + WSS）与直播房间事件补漏辅助。  
**不是** `PteIMUIKit`，也不包装 Android / iOS / HarmonyOS / uni-app x 原生 SDK。

| 导出 | 职责 |
| --- | --- |
| `@pte-live/im-web-sdk` | `PteLiveIMWebClient`、类型，以及 `live` 的 re-export |
| `@pte-live/im-web-sdk/live` | `LiveRoomSeqTracker`、`eventTypeFromFrame`、`readEnvelope` 等 |

权威直播协议见服务端 [`LIVE_EVENT_PROTOCOL.md`](https://github.com/pte-live/pte-live-im/blob/main/docs/LIVE_EVENT_PROTOCOL.md)；客户端摘要见 [`docs/live-event-protocol.md`](../../docs/live-event-protocol.md)。

## 安装

仓库内路径引用（当前 `private: true`，以源码入口消费）：

```json
{
  "dependencies": {
    "@pte-live/im-web-sdk": "file:../pte-live-im-sdk/packages/im-web-sdk"
  }
}
```

依赖：`@noble/ciphers` / `@noble/curves` / `@noble/hashes`（与 UTS E2EE 同版本基线，见根目录 `THIRD_PARTY_NOTICES.md`）。

## 聊一聊

```ts
import { PteLiveIMWebClient, type PteChatListener } from '@pte-live/im-web-sdk'

const client = new PteLiveIMWebClient({
  apiUrl: 'https://api.example.com',
  wsUrl: 'wss://im.example.com/ws',
  sdkAppId: String(session.sdkAppId),
  identifier: session.userId,
  userId: session.userId,
  userSig: session.userSig,
  expireAt: session.expireAt,
})

const listener: PteChatListener = {
  onConnectionChanged: (ok) => { /* … */ },
  onMessage: (message) => { /* 已解密 content */ },
  onUserSigWillExpire: () => { /* 宿主换签后 renewUserSig */ },
  onUserSigExpired: () => { /* 回业务登录 */ },
  onError: (msg) => { /* … */ },
}
client.addListener(listener)
await client.start()

const conversation = await client.openSingleConversation(peerUserId)
await client.sendText(conversation.id, 'hello')

// UserSig 续期（宿主完成业务换签后）
client.renewUserSig({ userSig: renewed.userSig, expireAt: renewed.expireAt })

client.stop()
client.removeListener(listener)
```

能力概要：

- REST：`/v1/im/*` 会话、好友/关注、群、历史、同步；响应支持 P-256/A256GCM 信封解密
- WSS：`login` / `send_message`（仅 `e2ee`，无明文 `content`）/ `ack` / UserSig 过期事件
- E2EE：设备注册、收件人密钥包装、审计密钥；设备私钥存 IndexedDB（AES-GCM 包装），隐私模式失败时会话仍可用但不持久化身份

不要把 UserSig 签名密钥、COS 密钥或 refresh token 放进本包。

## 直播房间事件

```ts
import { LiveRoomSeqTracker, eventTypeFromFrame } from '@pte-live/im-web-sdk/live'

const tracker = new LiveRoomSeqTracker(0)

// 进房前补漏（HTTP 由宿主实现）
await tracker.catchUp(
  {
    getCurrentRoomSeq: () => api.getDetail(roomId).then((d) => d.currentRoomSeq),
    fetchEventsAfter: (afterSeq, limit) => api.listEvents(roomId, afterSeq, limit),
  },
  (eventType, payload) => applyLiveEvent(eventType, payload),
)

// WSS 在线帧（握手 → scene.enter → scene.ack 之后）
socket.onmessage = (ev) => {
  const frame = JSON.parse(String(ev.data))
  const { eventType, payload } = eventTypeFromFrame(frame)
  if (!eventType || !payload) return
  if (tracker.needsCatchUp(payload)) {
    void tracker.catchUp(source, applyLiveEvent)
    return
  }
  if (tracker.accept(payload)) applyLiveEvent(eventType, payload)
}
```

完整进房顺序、信封字段与排障见 [`docs/live-event-protocol.md`](../../docs/live-event-protocol.md)。

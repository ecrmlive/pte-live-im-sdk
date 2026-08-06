# `@pte-live/pte-im-sdk`

独立 Web SDK（路径 `web/pte-im-sdk`）：聊一聊、Commerce 扩展、房间 SceneClient（`show` / `voice` / `shop` / `sports`）。
**不是** `PteIMUIKit`。

权威协议：服务端 [`LIVE_EVENT_PROTOCOL.md`](https://github.com/pte-live/pte-live-im/blob/main/docs/LIVE_EVENT_PROTOCOL.md)；跨端契约 [`docs/scene-client-contract.md`](../../docs/scene-client-contract.md)。

## 安装

```json
{
  "dependencies": {
    "@pte-live/pte-im-sdk": "file:../pte-live-im-sdk/web/pte-im-sdk"
  }
}
```

## 聊一聊

```ts
import { PteIMWebSDK, type PteChatListener } from '@pte-live/pte-im-sdk'

const client = new PteIMWebSDK({
  apiUrl, wsUrl, commerceDomain, sdkAppId,
  identifier: userId, userId, userSig, expireAt,
})
client.addListener({ onMessage: (m) => { /* decrypted */ } })
await client.start()
await client.sendText(conversationId, 'hello', quoteMessageId)
await client.addReaction(messageId, '👍')
await client.commerce.sendGift({ clientRequestId, sku: 'rose', quantity: 1, sceneType: 'show', roomId })
```

## 房间 Scene（SDK 接管 WSS）

```ts
import { PteIMSceneClient, type LiveCatchUpSource } from '@pte-live/pte-im-sdk'

const scene = new PteIMSceneClient({ wsUrl, sdkAppId, userId, userSig })
scene.addListener({
  onEntered: (info) => console.log('in room', info.groupName),
  onEvent: (eventType, payload) => apply(eventType, payload),
})

const catchUp: LiveCatchUpSource = {
  getCurrentRoomSeq: () => api.getDetail(roomId).then((d) => d.currentRoomSeq),
  fetchEventsAfter: (afterSeq, limit) => api.listEvents(roomId, afterSeq, limit),
}

await scene.enter({ scene: 'show', roomId, catchUp })       // 社交-直播
// await scene.enter({ scene: 'voice', roomId, catchUp })  // 社交-语聊
// await scene.enter({ scene: 'shop', roomId, extend: JSON.stringify({ role: 0 }), catchUp })
// await scene.enter({ scene: 'sports', roomId: 'sports-live-123', catchUp })
```

Chat 与 Scene **独立 WSS**；宿主分别签发 chat / room UserSig。

## 导出

| 路径 | 内容 |
| --- | --- |
| `@pte-live/pte-im-sdk` | chat + commerce + scene |
| `@pte-live/pte-im-sdk/scene` | `PteIMSceneClient`、`RoomSeqTracker` |
| `@pte-live/pte-im-sdk/commerce` | `PteIMCommerce` |
| `@pte-live/pte-im-sdk/live` | scene 的兼容 re-export（废弃路径） |

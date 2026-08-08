# 本仓库只描述 **各端 SceneClient** 如何消费直播房间协议。聊一聊仍走 Chat Core，与房间 fan-out **互不混用**（独立 WSS）。

权威协议在服务端仓库：[`pte-live-im/docs/LIVE_EVENT_PROTOCOL.md`](https://github.com/pte-live/pte-live-im/blob/main/docs/LIVE_EVENT_PROTOCOL.md)。  
跨端 API 契约：[scene-client-contract.md](./scene-client-contract.md)。

## 总原则（客户端必守）

| 原则 | 客户端动作 |
| --- | --- |
| 判别主键是字符串 `eventType` | 用 `sports.*` / `shop.*` / `scene.*` 分支；`code` 仅观测 |
| 信封字段 | 读取 `eventId`、`roomSeq`、`serverTs`、`priority`（兼容 snake_case） |
| SDK 接管进房 | `PteIMSceneClient`：握手 → 可选补漏 → `scene.enter` → `scene.ack` |
| 可补漏 | 宿主注入 `CatchUpSource`（详情 `currentRoomSeq` + `events?after_seq=`） |
| 聊一聊独立 | 一对一/群聊用 Chat Core，不走本协议 |

## 场景映射

| 产品域 | `scene` |
| --- | --- |
| 社交-直播 | `show` |
| 社交-语聊 | `voice` |
| 电商 | `shop` |
| 体育 | `sports` |

## Web 示例

```ts
import { PteIMSceneClient, type LiveCatchUpSource } from '@pte-live/pte-im-sdk'

const scene = new PteIMSceneClient({ wsUrl, sdkAppId, userId, userSig })
const catchUp: LiveCatchUpSource = {
  getCurrentRoomSeq: () => api.getDetail(roomId).then((d) => d.currentRoomSeq),
  fetchEventsAfter: (afterSeq, limit) => api.listEvents(roomId, afterSeq, limit),
}
scene.addListener({ onEvent: (eventType, payload) => apply(eventType, payload) })
await scene.enter({ scene: 'show', roomId, catchUp })
```

烟测辅助：`web/pte-im-sdk/src/scene/smoke.ts` 的 `runSceneSmoke`。

## 原生 / UTS

```text
Android / iOS: im.createSceneClient() → connect(loginUserSig) → enter(...)
HarmonyOS:     im.createSceneClient(credentials) → connect → enter
UTS:           client.scene.create(credentials) → connect → enter
```

## 与聊一聊的边界

| 能力 | 使用 |
| --- | --- |
| 一对一 / 群聊 E2EE、会话同步 | Chat Core（各端 `PteIMSDK` / Web `PteIMWebSDK`） |
| 房间 `show` / `voice` / `shop` / `sports` | `PteIMSceneClient`（独立 WSS） |
| 礼物资金 / 红包领取 | `im.commerce`（HTTP，无 WSS） |

包说明见 [`web/pte-im-sdk/README.md`](../web/pte-im-sdk/README.md)。

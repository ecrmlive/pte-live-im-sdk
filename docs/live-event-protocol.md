# 直播房间事件（客户端）

权威协议在服务端仓库：[`pte-live-im/docs/LIVE_EVENT_PROTOCOL.md`](https://github.com/pte-live/pte-live-im/blob/main/docs/LIVE_EVENT_PROTOCOL.md)。

本仓库只描述 **Browser Web SDK**（`@pte-live/im-web-sdk`）如何消费该协议。聊一聊会话仍走 `PteLiveIMWebClient`（见 [protocol.md](./protocol.md)），与直播房间 fan-out **互不混用**。

## 总原则（客户端必守）

| 原则 | 客户端动作 |
| --- | --- |
| 判别主键是字符串 `eventType` | 用 `sports.*` / `shop.*` / `scene.*` 分支；`code` 仅观测 |
| 信封字段 | 读取 `eventId`、`roomSeq`、`serverTs`、`priority`（兼容 snake_case） |
| 必须先入组 | WSS 握手成功后再发 `scene.enter`，收到 `scene.ack ok=true` 才算在房 |
| 可补漏 | 进房前/出现缺口时用详情 `currentRoomSeq` + `GET …/events?after_seq=` |
| 聊一聊独立 | 一对一/群聊用 `PteLiveIMWebClient`，不走本协议 |

## Web SDK 辅助模块

```ts
import {
  LiveRoomSeqTracker,
  eventTypeFromFrame,
  readEnvelope,
  parseLivePayload,
} from '@pte-live/im-web-sdk/live'
// 也可从主入口 re-export
import { LiveRoomSeqTracker } from '@pte-live/im-web-sdk'
```

| API | 用途 |
| --- | --- |
| `readEnvelope(payload)` | 从扁平 payload 取出 `eventId` / `roomSeq` / `serverTs` / `priority` |
| `parseLivePayload(raw)` | 解析对象或 JSON 字符串 payload |
| `eventTypeFromFrame(frame)` | 从 PTE group/scene 帧取出 `eventType` + `payload`（兼容 scene 嵌套与扁平 `msg`） |
| `LiveRoomSeqTracker` | `roomSeq` 水位 + `eventId` 去重；`accept` / `needsCatchUp` / `catchUp` |

该模块 **不** 建立 WSS、不签发 UserSig、不调用业务 REST；宿主负责连接、进房与补漏 HTTP。

## 推荐进房顺序

```text
1) 业务登录取得 UserSig（房间绑定租户须与 scene/room_id 一致）
2) 连接 wss://…/ws?sdkAppID=&identifier=&userSig=
3) 等待握手帧 code=0
4) （可选）REST 历史 / 详情 currentRoomSeq 种子水位
5) tracker.catchUp(source, apply) 补缺口
6) 发送 scene.enter（带 request_id、scene、room_id）
7) 等待 scene.ack ok=true → 标记已入组
8) 在线帧：eventTypeFromFrame → accept / needsCatchUp → 应用或再补漏
```

旧入口 `/ws?roomId=` 已移除，不要使用。

### `scene.enter` 示例

```json
{
  "action": "scene.enter",
  "request_id": "<uuid>",
  "scene": "sports",
  "room_id": "sports-live-123"
}
```

| `scene` | `room_id` 示例 | fan-out 组名 |
| --- | --- | --- |
| `shop` | `123` | `live:123` |
| `sports` | `sports-live-123` | `sports:sports-live-123` |
| `show` / `voice` | `<roomId>` | `show:<roomId>` / `voice:<roomId>` |

体育场景下 UserSig 内 `room_id` 必须与 `scene.enter.room_id` 同为 `sports-live-{数字id}`，否则 `scene.ack ok=false`。

## 在线帧与补漏

服务端常见两种帧形态，`eventTypeFromFrame` 均可解析：

1. **scene 嵌套**：`data` 含 `event_type` + `scene.payload`
2. **扁平**：`msg` 为 `eventType`，`data` 内直接带信封与业务字段

序号规则：

| 条件 | 动作 |
| --- | --- |
| 无 `roomSeq` | **不要丢弃**；仍按 `eventId` 去重后应用 |
| `roomSeq <= last` | 忽略（可记 `eventId`） |
| `roomSeq == last + 1` | `accept` 后应用 |
| `roomSeq > last + 1` | `needsCatchUp` → HTTP 补漏后再应用 |
| 重复 `eventId` | `accept` 返回 false |

### `LiveRoomSeqTracker.catchUp`

宿主实现 `LiveCatchUpSource`：

```ts
const source = {
  getCurrentRoomSeq: () => businessApi.getLiveDetail(roomId).then((d) => d.currentRoomSeq),
  fetchEventsAfter: (afterSeq, limit = 100) =>
    businessApi.listLiveEvents(roomId, { after_seq: afterSeq, limit }),
}

const tracker = new LiveRoomSeqTracker(0)
await tracker.catchUp(source, (eventType, payload) => {
  // 按 eventType 更新 UI / 状态机
})
```

- 新鲜进房（`lastRoomSeq <= 0`）：用 `currentRoomSeq` 种子水位，避免整房历史回放。
- 已有水位：分页拉取 `after_seq`（单次最多约 20 页 × 100 条），对每条 `accept` 后回调 `apply`。
- 缺口出现在在线过程中时，再次调用 `catchUp`，不要跳过。

业务写操作（购买、禁言等）仍以业务 API 当前状态为准；IM 只保证尽快推送，短暂 UI 不一致可接受，错误成交不可接受。

## 与聊一聊的边界

| 能力 | 使用 |
| --- | --- |
| 一对一 / 群聊 E2EE、会话同步 | `PteLiveIMWebClient`（`@pte-live/im-web-sdk`） |
| 直播间 `sports.*` / `shop.*` 房间事件 | 宿主 WSS + `@pte-live/im-web-sdk/live` |
| 原生四端聊一聊 | `PteIMSDK` / `PteIMUIKit`（本仓库其它目录） |

包说明与最小接入示例见 [`packages/im-web-sdk/README.md`](../packages/im-web-sdk/README.md)。

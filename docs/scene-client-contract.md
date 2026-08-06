# Scene Client 跨端契约

五端统一的房间 IM 客户端：`show`（社交直播）、`voice`（社交语聊）、`shop`（电商）、`sports`（体育）。  
权威进房与 fan-out 协议见服务端 [`LIVE_EVENT_PROTOCOL.md`](https://github.com/pte-live/pte-live-im/blob/main/docs/LIVE_EVENT_PROTOCOL.md)。

## 边界

| SDK 负责 | 宿主负责 |
| --- | --- |
| 独立 WSS 连接、握手、`scene.enter` / `scene.ack`、`scene.leave` | 签发房间绑定 UserSig |
| `roomSeq` 水位、`eventId` 去重、缺口补漏编排 | 实现补漏 HTTP（详情 `currentRoomSeq` + `events?after_seq=`） |
| 按 `eventType` 分发（未知类型仍透传） | 推流/拉流、RTC、业务写操作与房间 UI |

**Chat 与 Scene 使用独立 WSS 连接**（同一 `/ws` 端点，不同 UserSig 生命周期）。进房用 scene 签；聊一聊用 chat 签。

## 场景枚举

| 产品域 | `scene` | `room_id` 示例 | fan-out 组 |
| --- | --- | --- | --- |
| 社交-直播 | `show` | `<roomId>` | `show:<roomId>` |
| 社交-语聊 | `voice` | `<roomId>` | `voice:<roomId>` |
| 电商 | `shop` | `123` | `live:123` |
| 体育 | `sports` | `sports-live-123` | `sports:sports-live-123` |

体育：UserSig 内 `room_id` 必须与 `scene.enter.room_id` 同为 `sports-live-{数字id}`。SDK 在 enter 前做本地格式校验。

## API 语义（五端一致）

```text
scene.connect({ wsUrl, sdkAppId, userId, userSig })
scene.enter({ scene, roomId, extend?, catchUp? })
scene.leave()
scene.disconnect()
scene.addListener / removeListener
scene.renewUserSig({ userSig, expireAt? })
```

### Listener

| 回调 | 时机 |
| --- | --- |
| `onConnectionChanged(connected)` | WSS 开/关 |
| `onEntered({ scene, roomId, groupName })` | `scene.ack ok=true` |
| `onEnterFailed({ scene, roomId, message })` | `scene.ack ok=false` 或超时 |
| `onEvent(eventType, payload, envelope)` | 在线帧或补漏应用后 |
| `onError(message)` | 传输/解析错误 |

### CatchUpSource（宿主注入）

```text
getCurrentRoomSeq(): Promise<number>
fetchEventsAfter(afterSeq, limit?): Promise<{ currentRoomSeq, events[] }>
```

`events[]` 每项至少含 `eventId`、`eventType`、`roomSeq`、`payload`。

## 进房顺序

```text
1) connect → 等握手 code=0
2) 可选 catchUp（水位种子 + after_seq）
3) scene.enter（带 request_id）
4) scene.ack ok=true → onEntered
5) 在线：解析 eventType → needsCatchUp? → accept → onEvent
6) 断线重连后保留水位，必须重新 enter
```

## 事件前缀

| scene | 常见前缀 | 未知事件 |
| --- | --- | --- |
| `show` / `voice` | `scene.*` / `scene.commerce.*` | 透传 `onEvent` |
| `shop` | `shop.*` | 透传 |
| `sports` | `sports.*` | 透传 |

判别主键是字符串 `eventType`；数字 `code` 仅观测。

## 各端挂载

| 端 | 路径 | 访问 |
| --- | --- | --- |
| Web | `web/pte-im-sdk` `@pte-live/pte-im-sdk` | `new PteIMSceneClient(...)` / `PteIMWebSDK.scene` |
| Android | `android/pte-im-sdk` | `im.scene` |
| iOS | `ios/PteIMSDK` | `im.scene` |
| HarmonyOS | `harmony/PteIMSDK` | `im.scene` |
| uni-app x | `uni_modules/pte-im-sdk` | `client.scene` |

Commerce 扩展（`im.commerce`）与 Scene 独立：礼物/红包资金走 Commerce HTTP；房间内广播仍经 Scene `onEvent`。

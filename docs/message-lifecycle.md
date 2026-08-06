# IM 消息生命周期与端能力

本文以当前 `pte-live-im` 服务端和本仓库源码为准，定义聊天消息的引用、撤回、删除和表情反应。它们是 IM Core 协议能力；宿主只接收 UI/业务通知，不负责保存这些状态。

## 语义与权限

| 操作 | IM 服务端行为 | 可见范围 | 权限与限制 |
| --- | --- | --- | --- |
| 引用 | 发送消息时携带原消息的 `quoteMessageId`；服务端保存引用 ID 与快照并随历史/同步返回 | 会话所有成员 | 仅可引用同一会话、已被服务端接受的消息 |
| 撤回 | 将原消息标为 recalled，并推送 `chat.message.recalled` | 会话所有成员 | 仅发送者；普通状态消息；服务端当前限制为发送后 2 分钟内 |
| 删除 | 为当前账户写入消息用户态，并推送 `chat.message.deleted` 给当前账户的在线连接 | 仅当前账户 | 当前会话成员；不修改其他成员历史，也不等同于撤回 |
| 表情反应 | 写入 IM 反应记录并返回汇总；推送 `chat.message.reaction_changed` | 会话所有成员 | 当前会话成员；仅普通状态消息；同一用户对同一消息和 emoji 的添加幂等 |

删除不是 `deleteLocalMessage`：本地缓存删除会在下一次同步时恢复，且无法同步到该用户的其他设备；必须调用 IM 的删除接口。撤回也不是删除：撤回会让所有成员看到“已撤回”的消息状态，删除只从当前账户视图隐藏。

## 协议

### 发送与消息对象

`send_message.payload` 在现有 `clientMsgId`、`conversationId`、`type`、`e2ee` 之外可带：

```json
{ "quoteMessageId": "1000123" }
```

`quoteMessageId` 只是路由和关联元数据；消息正文仍只存在 E2EE 信封中。历史和 `/v1/im/sync` 返回的消息会附带 `quoteMessageId`、`quoteSnapshot`、`status`、`recalledAt`、`deletedAt` 和 `reactions`。`reactions` 是聚合数组：`emoji`、`count`、`reacted_by_me`（REST 服务端字段）。各端 SDK 将其映射到各自的消息模型。

### REST

所有接口都需要 `Authorization: Bearer <UserSig>`、`X-Pte-Sdk-AppId` 和 `X-Pte-User-Id`；操作者由已验证 UserSig 推导，不能由请求体冒充。

| 接口 | 请求体 | 结果 |
| --- | --- | --- |
| `POST /v1/im/messages/recall` | `{ "messageId": "..." }` | 更新为撤回状态并广播 |
| `POST /v1/im/messages/delete` | `{ "messageId": "..." }` | 仅删除当前账户可见记录 |
| `POST /v1/im/messages/reactions/add` | `{ "messageId": "...", "emoji": "👍" }` | 返回该消息最新反应聚合 |
| `POST /v1/im/messages/reactions/remove` | `{ "messageId": "...", "emoji": "👍" }` | 返回该消息最新反应聚合 |

### WSS `message_event`

服务端对状态变化发送 `action: "message_event"`。客户端应先提交本地状态，再刷新 UI；连接丢失或序号缺失后以 `/v1/im/sync` 为最终修复来源。

| `eventType` | 必要字段 | 客户端处理 |
| --- | --- | --- |
| `chat.message.recalled` | `serverMsgId`、`status`、`recalledAt` | 保留消息行并渲染已撤回状态 |
| `chat.message.deleted` | `serverMsgId` | 从当前账户本地列表和缓存移除 |
| `chat.message.reaction_changed` | `serverMsgId`、`userId`、`emoji`、`reactionAction`（`added` / `removed`） | 调整汇总数；`userId` 等于当前用户时同步 `reactedByMe` |

## 当前端能力矩阵

| 端 | 引用发送/读取 | 撤回与删除 | 反应 REST | 反应事件、本地持久化与 UI |
| --- | --- | --- | --- | --- |
| Android 原生 | 已实现 | 已实现 | 已实现 | 已实现 |
| iOS 原生 | 已实现 | 已实现 | 已实现 | 已实现 |
| Browser `@pte-live/pte-im-sdk` | 已实现 | REST + `onMessageEvent` 透传（含反应字段） | 已实现 | 未做本地消息库；宿主消费 `onMessageEvent` |
| HarmonyOS 原生 | 已实现 | 已实现 | 已实现 | 已实现（`message_event` 写入本地 store） |
| uni-app x UTS（H5、微信） | 已实现（发送可选 `quoteMessageId`） | 已实现，并把撤回/删除事件交给 listener | 已实现 | 事件透传；无完整反应聚合持久化 |

“已实现”表示当前源码已有公开 SDK 调用与对应事件/缓存处理；不代表宿主业务可跳过 UserSig、会话成员权限或 UI 刷新。新增平台能力时，必须同时更新本矩阵、[协议](protocol.md)和服务端 `api-im/docs/openapi.yaml`。

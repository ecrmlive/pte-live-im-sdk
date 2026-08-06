# 五端能力矩阵

以源码为准。Scene = `PteIMSceneClient`（独立 WSS + `scene.enter`）；Chat = 聊一聊 Core；Commerce = `im.commerce`。

| 能力 | Android | iOS | HarmonyOS | uni-app x UTS | Web (`web/pte-im-sdk`) |
| --- | --- | --- | --- | --- | --- |
| 聊天 Core（E2EE / 同步 / 收发） | ✓ | ✓ | ✓ | ✓ | ✓ |
| 引用发送 / 读取 | ✓ | ✓ | ✓ | ✓ | ✓ |
| 撤回 / 删除 | ✓ | ✓ | ✓ | ✓ | ✓ |
| 反应 REST | ✓ | ✓ | ✓ | ✓ | ✓ |
| 反应事件本地持久化 | ✓ | ✓ | ✓ | 透传 listener | 透传 listener（无消息库） |
| Commerce 扩展 | ✓ | ✓ | ✓ | ✓ | ✓ |
| SceneClient `show`（社交-直播） | ✓ | ✓ | ✓ | ✓ | ✓ |
| SceneClient `voice`（社交-语聊） | ✓ | ✓ | ✓ | ✓ | ✓ |
| SceneClient `shop`（电商） | ✓ | ✓ | ✓ | ✓ | ✓ |
| SceneClient `sports`（体育） | ✓ | ✓ | ✓ | ✓ | ✓ |
| UIKit | ✓ | ✓ | ✓ | ✓ | — |

## 路径

| 端 | Core | Scene 入口 |
| --- | --- | --- |
| Android | `android/pte-im-sdk` | `im.createSceneClient()` |
| iOS | `ios/PteIMSDK` | `im.createSceneClient()` |
| HarmonyOS | `harmony/PteIMSDK` | `im.createSceneClient(credentials)` |
| UTS | `uni_modules/pte-im-sdk` | `client.scene.create(credentials)` |
| Web | `web/pte-im-sdk` `@pte-live/pte-im-sdk` | `new PteIMSceneClient(...)` / `PteIMWeb.scene(...)` |

契约：[scene-client-contract.md](./scene-client-contract.md)。

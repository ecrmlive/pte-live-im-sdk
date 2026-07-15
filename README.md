# PteIMSDK

PteIM 客户端采用三层一致的产品命名：`PteIMSDK` 是 Core SDK，`PteIMUIkit` 是可复用的会话、聊天和群组 UI，`PteIMUIDemo` 是包含业务登录、好友关系和“我的”入口的示例应用。旧名称不再提供兼容入口。

| 产品 | 职责 | 不负责的内容 |
| --- | --- | --- |
| `PteIMSDK` | 配置、UserSig 登录、WSS、消息、同步、SQLite、COS 上传、E2EE、主题/语言状态 | 业务登录、好友关系、支付、系统选择器 |
| `PteIMUIkit` | 会话列表、一对一/群组聊天、文本/表情、发送状态、亮暗/中英文、业务动作回调 | 签发 UserSig、保存密钥、替宿主完成支付/定位/选文件 |
| `PteIMUIDemo` | 业务登录 → 取得 `userId`/短期 `userSig` → IM 登录 → 好友、会话、群组、我的 | 生产业务后端实现 |

## 仓库

| 项目 | 说明 |
| --- | --- |
| [Pte IM 服务端](https://github.com/ptedom/pte-live-im) | IM 服务、部署、服务端接口实现 |
| [本仓库](https://github.com/ptedom/pte-live-im-sdk) | 四端 PteIMSDK / PteIMUIkit / PteIMUIDemo |
| 项目官网 | 由业务项目配置；客户端不硬编码官网或密钥 |

## 平台与目录

| 平台 | Core | UI | 业务示例 | 最低版本 |
| --- | --- | --- | --- | --- |
| Android 原生 | [android/pte-im-sdk](android/pte-im-sdk) | [android/pte-im-uikit](android/pte-im-uikit) | [android/pte-im-ui-demo](android/pte-im-ui-demo) | Android 12 / API 31 |
| iOS 原生 | [ios/PteIMSDK](ios/PteIMSDK) | [ios/PteIMUIkit](ios/PteIMUIkit) | [ios/PteIMUIDemo](ios/PteIMUIDemo) | iOS 16.0 |
| HarmonyOS 原生 | [harmony/PteIMSDK](harmony/PteIMSDK) | [harmony/PteIMUIkit](harmony/PteIMUIkit) | [harmony/PteIMUIDemo](harmony/PteIMUIDemo) | OpenHarmony API 23 |
| uni-app x UTS | [uni_modules/pte-im-sdk](uni_modules/pte-im-sdk) | `PteIMUIChat`、`PteIMUIConversationList` | [uniapp-x/PteIMUIDemo](uniapp-x/PteIMUIDemo) | H5/Web、微信小程序 |

Android、iOS、HarmonyOS 都是独立原生 SDK；iOS UI 仅使用 UIKit。UTS 版本面向 H5/Web 和微信小程序，不包装原生 SDK。所有 UI 源文件以 `PteIMUI` 开头。

## 支持范围

| 场景 | 内容 |
| --- | --- |
| 一对一聊天 | 文本、图片、视频、语音、表情、定位、礼物、红包、订单 |
| 群聊 | 文本、图片、视频、语音、表情、定位、红包 |
| Core | 连接/重连、ACK、消息状态、会话与消息同步、SQLite 本地缓存、Outbox、UserSig 续期、COS PUT 上传、E2EE 协议封装 |
| 外观 | `light`、`dark`、`system`；`zh-CN`、`en-US`、`system`，可不重新登录即时更新 |

图片、视频和语音使用业务 API 返回的 COS PUT 对象上传；客户端只保存 object key，访问地址由 `cosDomain` 组合。业务动作和系统权限由宿主接管。

## 配置与登录

应用启动阶段只配置域名和显示偏好；登录阶段才传入用户身份。不要把 UserSig、COS 临时凭据或服务器密钥提交到仓库。

```text
PteIMBaseConfig(apiDomain, imDomain, cosDomain, themeMode, language)
PteIMLoginConfig(sdkAppId, userId, userSig)
```

`apiDomain` 是业务/API 域名，`imDomain` 是 IM WebSocket 地址，`cosDomain` 是保存 key 后访问文件的根域名。业务服务应在认证成功后返回短期 `userSig`；客户端不得自行生成。

### Android

```kotlin
val im = PteIMSDK.configure(
  applicationContext,
  PteIMBaseConfig(apiDomain, imDomain, cosDomain)
).login(PteIMLoginConfig(sdkAppId, userId, userSig))

im.openSingleConversation(peerUserId) { result ->
  result.onSuccess { conversation ->
    val chat = PteIMUIkit.createChatView(this, im, conversation.id.toString(), "Alice")
  }
}
```

### iOS

以本地 Swift Package 添加 `ios/PteIMSDK` 与 `ios/PteIMUIkit`：

```swift
import PteIMUIkit

let im = try PteIMSDK.configure(baseConfig).login(loginConfig)
Task {
  let conversation = try await im.openSingleConversation(peerUserId: peerUserId)
  let chat = PteIMUIkit.makeChatViewController(client: im, conversationId: String(conversation.id), title: "Alice")
}
```

### HarmonyOS

添加本地 `@ptelive/pte-im-sdk` 与 `@ptelive/pte-im-uikit` HAR：

```ts
const im = await PteIMSDK.configure(this.context, baseConfig).login(loginConfig)
const conversation = await im.openSingleConversation(peerUserId)
PteIMUIChat({ client: im, conversationId: conversation.id.toString() })
```

### uni-app x UTS

```uts
import { createPteIMSDK } from '@/uni_modules/pte-im-sdk/utssdk/web/index.uts'

const im = createPteIMSDK({ apiDomain, imDomain, cosDomain, themeMode: 'system', language: 'system' })
  .login({ sdkAppId, userId, userSig })
im.start()
```

微信小程序使用同路径下的 `mp-weixin/index.uts`。H5 配置 CORS 和 WebSocket Origin；微信配置 HTTPS/WSS 域名白名单。

## 运行 PteIMUIDemo

每个 Demo 都不保存输入的 UserSig。它们只是业务打通的结构示例：将示例账号校验替换为您的业务登录 API，再使用 API 返回的 `userId` 和短期 `userSig` 登录 PteIMSDK。

```sh
# Android（项目需提供 Gradle 环境）
cd android && gradle :pte-im-ui-demo:assembleDebug

# iOS
xcodebuild -workspace ios/PteIMUIDemo/PteIMUIDemo.xcworkspace -scheme PteIMUIDemo -sdk iphonesimulator CODE_SIGNING_ALLOWED=NO build

# HarmonyOS
cd harmony/PteIMUIDemo && hvigorw --no-daemon assembleApp
```

在 HBuilderX 打开 `uniapp-x/PteIMUIDemo`，选择 H5 或微信小程序运行。

## 外观和语言

登录完成后无需刷新 UserSig 或重连：

```text
updateAppearance(themeMode: dark, language: en-US)
updateAppearance(themeMode: system, language: system)
```

Core 发出外观回调，PteIMUIkit 随即刷新。更多协议、存储与安全约束见 [架构说明](docs/architecture.md) 和 [安全说明](docs/security.md)。

## PteIMUIkit 聊天 UI 架构

PteIMUIkit 采用“消息内容单元 + 独立输入条 + 宿主业务回调”的分层方式，参考 MessageKit 的可定制消息单元与 InputBar 思路，但不引入任何第三方 UI 依赖。四端均提供独立的 `PteIMUIInputBar`；它可以脱离聊天页单独复用。

输入条固定顺序为：`语音切换` → `输入框 / 按住说话` → `+` → `表情` → `发送`。点击语音后，中间区域变为“按住说话”；开始和结束录音只通知宿主，录音权限、编码、上传完成后调用 Core 的 `sendVoice` 仍由业务负责。`+` 面板内置图片、视频、定位、礼物、红包、订单；表情面板内置默认表情项。两种面板均通过回调将选择结果交给宿主。

默认视觉是蓝紫渐变发送气泡与发送按钮，并为亮/暗模式提供两套完全独立的组件色板：背景、会话面、输入栏、收发气泡、渐变、文字、图标、分割线、表情面板和更多面板均可分别配置。

### iOS UIKit

```swift
let theme = PteIMUITheme(
  light: .blueVioletLight,
  dark: .blueVioletDark
)
let chat = PteIMUIkit.makeChatViewController(
  client: im,
  conversationId: String(conversation.id),
  title: "Alice",
  theme: theme
)
chat.onActionRequested = { action, controller in
  // 使用系统选择器或业务页面，完成后调用 controller.sendImage/sendVideo/…
}
chat.onVoiceRecordingChanged = { recording, controller in
  // recording=true 开始录音；false 停止并上传，随后 controller.sendVoice(voice)
}
```

`PteIMUIThemePalette` 的所有字段均为公开参数，因此可以只替换 `light` 或 `dark` 的任意组件颜色，不会影响另一套模式。`themeMode = system` 时 UIKit 会自动随系统外观刷新。

### Android、HarmonyOS、uni-app x

Android 使用 `PteIMUITheme(light = …, dark = …)` 并传给 `PteIMUIkit.createChatView`；HarmonyOS 通过 `PteIMUIChat({ theme: new PteIMUITheme(light, dark) })`；UTS 通过 `<PteIMUIChat :theme="new PteIMUITheme(light, dark)" />`。三端均遵循同一套色板字段和输入回调：`onActionRequested` / `action` 负责更多面板，`onVoiceRecordingChanged` / `voice-recording` 负责按住说话状态。

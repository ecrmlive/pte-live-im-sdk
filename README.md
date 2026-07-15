# PteLive IM SDK

PteLive IM 的客户端 SDK：提供原生 Android、iOS、HarmonyOS，以及 uni-app x UTS（H5/Web、微信小程序）接入能力。每端均提供可直接集成的 `PteIMUIKit`；Core SDK 负责连接、消息、同步、上传和本地缓存，宿主负责签发 UserSig 与处理系统权限、业务流程。

> 当前为 `0.1.0-alpha`。所有接口均使用 `Pte` 前缀，避免与宿主或其他 SDK 冲突。

## 项目入口

| 项目 | 用途 |
| --- | --- |
| [PteLive 官网](https://www.ptelive.com) | 产品与应用入口 |
| [IM 服务端仓库](https://github.com/ptedom/pte-live-im) | IM 服务、部署与服务端接口实现 |
| [本 SDK 仓库](https://github.com/ptedom/pte-live-im-sdk) | Android、iOS、HarmonyOS、UTS 客户端 SDK |
| [协议约定](docs/protocol.md) | WSS、同步、会话和 COS 上传的客户端契约 |
| [安全说明](docs/security.md) | 本地缓存加密、密钥和 E2EE 边界 |
| [示例配置](config/sdk.example.yaml) | 不含任何真实密钥的 YAML 配置模板 |

## 可运行 Demo

每个 Demo 都是 SDK 目录外的独立应用层，运行时输入域名和短期 `userSig`；仓库中没有生产环境参数、COS 密钥或用户凭证。

| 平台 | 工程 | 运行方式 | 演示内容 |
| --- | --- | --- | --- |
| Android 原生 | [android/demo](android/demo) | `cd android && ./gradlew :demo:installDebug` | 运行时登录后直接加载 `android/im-ui-kit` 的原生聊天 View |
| iOS 原生 | [ios/PteIMUIKit](ios/PteIMUIKit) + [ios/demo](ios/demo) | Xcode 打开 `PteLiveIMDemo.xcodeproj` | `PteIMUIKit` UIKit 会话列表/聊天页、消息状态、系统亮暗与业务动作回调 |
| HarmonyOS 原生 | [harmony/demo](harmony/demo) | DevEco Studio 打开后运行 `entry` | 运行时登录后直接加载 `harmony/PteIMUIKit` 的 ArkUI 聊天组件 |
| uni-app x UTS | [uniapp-x/demo](uniapp-x/demo) | HBuilderX 运行 H5 或微信小程序 | 运行时登录后直接加载 UTS/uvue `PteIMUIChat` |

Demo 仅用于验证 SDK 与 UI Kit 接入效果，实际聊天界面均来自 `PteIMUIKit`。请由已认证的业务后端签发短期 `userSig`，不要把它、COS 临时凭证或任何长期密钥填进源码、Git 或打包配置。

## SDK 与平台范围

| SDK | 路径 | 运行环境 | 本地存储 |
| --- | --- | --- | --- |
| Android 原生 | `android/im-sdk` + `android/im-ui-kit` | Android 12+（API 31）/ Kotlin View | SQLite + Android Keystore 加密 |
| iOS 原生 | `ios/PteLiveIM` + `ios/PteIMUIKit` | iOS 16.0+ / UIKit | SQLite + Keychain 加密 |
| HarmonyOS 原生 | `harmony/PteLiveIM` + `harmony/PteIMUIKit` | OpenHarmony API 23 / ArkTS | 加密 relational-store |
| uni-app x UTS | `uni_modules/pte-live-im` | H5/Web、微信小程序 / UTS + uvue | 默认仅内存；配置加密器后才持久化 |

Android、iOS、HarmonyOS 是独立原生 SDK；UTS 插件不包装或替代原生 SDK。四端均提供 `PteIMUIKit`：Android 使用原生 View，iOS 使用 UIKit（不使用 SwiftUI），HarmonyOS 使用 ArkUI，UTS 使用 uvue 组件与 UTS 控制器。所有新增 UI 源文件均以 `PteIMUI` 前缀命名。

## 已提供能力

| 模块 | 能力 |
| --- | --- |
| 连接与登录 | `PteIMBaseConfig`/`PteIMLoginConfig` 分离、WSS 连接、断线重连、UserSig 续期事件 |
| 会话与同步 | 增量同步、会话/历史分页、已读游标、离线 Outbox、幂等 `clientMsgId`、本地缓存读取 |
| 单聊消息 | 文本、表情、图片、视频、语音、定位、礼物、红包、订单 |
| 群聊消息 | 文本、表情、图片、视频、语音、定位、红包 |
| 文件上传 | API 获取一次性腾讯云 COS PUT URL，客户端直传，仅保存 object key |
| 端到端加密 | Android、iOS：P-256 ECDH + AES-256-GCM、设备注册、审计密钥策略与加密 API 响应 |
| 外观与语言 | `system` / `light` / `dark`，`system` / `zh-CN` / `en-US`，可在登录后即时更新 |
| PteIMUIKit | 聊天页、会话列表、消息状态、表情、主题/语言联动；图片/视频/语音、位置、礼物、红包、订单通过宿主动作回调接入 |
| 本地安全 | 原生缓存的消息载荷、Outbox、同步游标加密；`userSig` 不写入本地消息库 |

## 接入前准备

1. 服务端创建或确认 IM 应用，向客户端安全下发短期 `userSig`。
2. 准备三个启动期域名：`apiDomain`、`imDomain`、`cosDomain`。
3. 生产环境使用 HTTPS/WSS；`imDomain` 必须以 `/ws` 结尾。
4. 实现 [协议约定](docs/protocol.md) 中的同步、会话和 COS PUT 凭证接口；SDK 不假设服务端的内部服务名称或部署方式。

配置在应用启动时完成，登录参数独立传入：

```text
PteIMBaseConfig(apiDomain, imDomain, cosDomain, themeMode, language)
PteIMLoginConfig(sdkAppId, userId, userSig)
```

| 参数 | 说明 |
| --- | --- |
| `apiDomain` | HTTPS API 根域名，例如 `https://api.example.com` |
| `imDomain` | WSS 实时连接地址，例如 `wss://im.example.com/ws` |
| `cosDomain` | COS/CDN 对象根域名，用于把 object key 解析为访问 URL |
| `sdkAppId` | 正整数 IM 应用 ID |
| `userId` | 正整数的字符串，例如 `"10001"` |
| `userSig` | 服务端签发的短期凭证；不可写进 App 包、日志或仓库 |

## 最小 Demo

以下示例中的域名、应用 ID、用户 ID、会话 ID 和 UserSig 都应替换成你的实际数据。

### uni-app x UTS（H5 / 微信小程序）

将 `uni_modules/pte-live-im` 放入 uni-app x 项目后：

```uts
import { createPteLiveIM } from '@/uni_modules/pte-live-im'

const bootstrap = createPteLiveIM({
  apiDomain: 'https://api.example.com',
  imDomain: 'wss://im.example.com/ws',
  cosDomain: 'https://cos.example.com',
  themeMode: 'system',
  language: 'zh-CN',
})

const im = bootstrap.login({
  sdkAppId: 1400000001,
  userId: '10001',
  userSig: await fetchUserSigFromYourServer(),
})

im.onConnectionChanged((connected) => console.log('IM connected:', connected))
im.onMessage((message) => renderIncomingMessage(message))
im.onError((message) => console.error('IM error:', message))
im.start()

const clientMsgId = im.sendText('your-conversation-id', '你好，PteLive IM')
```

直接使用 UI Kit 组件：

```vue
<PteIMUIChat :client="im" conversation-id="c2c:10001:10002" @action="handlePteIMAction" />
```

`PteIMUIChat` 和 `PteIMUIConversationList` 位于 `uni_modules/pte-live-im/components`；也可从 `utssdk/PteIMUIKit.uts` 创建 UTS 控制器来渲染自定义 UI。

UTS 如需在重启后恢复消息、Outbox 与同步游标，必须提供 `localStorageCipher`；否则 SDK 为避免明文缓存只在内存中保存数据。详见 [UTS 说明](uni_modules/pte-live-im/readme.md) 和 [安全说明](docs/security.md)。

### Android 原生（Kotlin）

将 `android/im-sdk` 作为 Gradle 本地模块引入，然后在 Application 或依赖注入容器中配置：

```kotlin
val bootstrap = PteLiveIM.configure(
  applicationContext,
  PteIMBaseConfig(
    apiDomain = "https://api.example.com",
    imDomain = "wss://im.example.com/ws",
    cosDomain = "https://cos.example.com",
    themeMode = PteIMThemeMode.SYSTEM,
    language = PteIMLanguage.ZH_CN,
  ),
)

val im = bootstrap.login(
  PteIMLoginConfig(1400000001, "10001", fetchUserSigFromYourServer()),
)
im.addListener(object : PteIMListener {
  override fun onMessage(message: PteIMMessage) = renderIncomingMessage(message)
})
im.sendText("your-conversation-id", "你好，PteLive IM")
```

登录后直接创建 UI Kit View：

```kotlin
val chat = PteIMUIKit.createChatView(this, im, "c2c:10001:10002", "Alice")
chat.onActionRequested = { action -> handlePteIMAction(action) }
setContentView(chat)
```

### iOS 原生（Swift）

在 Xcode 以本地 Swift Package 方式添加 `ios/PteLiveIM` 后：

```swift
let base = try PteIMBaseConfig(
  apiDomain: "https://api.example.com",
  imDomain: "wss://im.example.com/ws",
  cosDomain: "https://cos.example.com",
  themeMode: .system,
  language: .zhCN
)
let im = try PteLiveIM.configure(base).login(
  try PteIMLoginConfig(
    sdkAppId: 1_400_000_001,
    userId: "10001",
    userSig: try await fetchUserSigFromYourServer()
  )
)
im.onMessage = { message in renderIncomingMessage(message) }
im.sendText(conversationId: "your-conversation-id", text: "你好，PteLive IM")
```

### iOS UIKit UI Kit

在应用完成 Core 登录后，直接使用独立的 `PteIMUIKit` Swift Package；它使用 UIKit，不依赖 SwiftUI：

```swift
import PteIMUIKit

let chat = PteIMUIKit.makeChatViewController(
  client: im,
  conversationId: "c2c:10001:10002",
  title: "Alice"
)
chat.onActionRequested = { action, controller in
  // 宿主选择图片/视频/语音或进入定位、礼物、红包、订单业务流程后，
  // 调用 controller.sendImage / sendVideo / sendVoice / sendLocation 等方法。
}
navigationController?.pushViewController(chat, animated: true)
```

`PteIMUIKit` 的 UIKit 源文件均以 `PteIMUI` 前缀命名，包含会话列表、聊天页、消息单元、主题与中英文文案，并跟随 Core 的亮暗和语言回调。

### HarmonyOS 原生（ArkTS）

将 `harmony/PteLiveIM` 作为本地 `@ptelive/im` 依赖加入 DevEco 工程，并配置网络权限与域名白名单：

```ts
const base = new PteIMBaseConfig(
  'https://api.example.com',
  'wss://im.example.com/ws',
  'https://cos.example.com',
  PteIMThemeMode.SYSTEM,
  PteIMLanguage.ZH_CN,
)
const im = await PteLiveIM.configure(this.context, base).login(
  new PteIMLoginConfig(1400000001, '10001', await fetchUserSigFromYourServer()),
)
im.addListener(new PteIMListener())
await im.sendText('your-conversation-id', '你好，PteLive IM')
```

添加本地 `@ptelive/im-ui-kit` HAR 后，在 ArkUI 页面中直接使用：

```ts
PteIMUIChat({
  client: im,
  conversationId: 'c2c:10001:10002',
  onActionRequested: (action: PteIMUIAction) => handlePteIMAction(action),
})
```

## 常见操作

```text
发送表情       sendEmoji(conversationId, packageId, emojiId)
直传图片/视频  uploadAndSendImage / uploadAndSendVideo
直传语音       uploadAndSendVoice(conversationId, source, durationMs, waveform?)
已读同步       markConversationRead(conversationId, seq)
历史消息       fetchMessageHistory(conversationId, beforeSeq, limit)
本地消息       localMessages(conversationId, beforeCreatedAt, limit)
切换亮暗/语言  updateAppearance(themeMode, language)
刷新 UserSig   renewUserSig(userSig)
```

媒体上传流程为：宿主 API 签发一次性 COS PUT URL → SDK 直接 PUT 文件 → SDK 发送并仅保存 object key。SDK 从不接收 COS `SecretId`、`SecretKey` 或 UserSig 生成密钥。

## 开发与验证

```bash
# Android
cd android && ./gradlew :im-sdk:compileDebugKotlin

# iOS（Swift Package）
cd ios/PteLiveIM && swift build
```

HarmonyOS 请在 DevEco Studio 构建；UTS 请在 HBuilderX 针对 H5 或微信小程序目标运行。修改 SDK 前请阅读 [架构说明](docs/architecture.md)、[协议约定](docs/protocol.md) 与 [安全说明](docs/security.md)。

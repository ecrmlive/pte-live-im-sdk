# PteIMSDK

PteIM 客户端采用三层一致的产品命名：`PteIMSDK` 是 Core SDK，`PteIMUIKit` 是可复用的会话、聊天和群组 UI，`PteIMUIDemo` 是包含业务登录、好友关系和“我的”入口的示例应用。旧名称不再提供兼容入口。

视觉资源按模块归属管理：Core `PteIMSDK` 不打包页面切图；会话、联系人、聊天页的公共切图归 `PteIMUIKit`；登录、启动与业务样例切图归 `PteIMUIDemo`。详见 [ASSET_OWNERSHIP.md](ASSET_OWNERSHIP.md)。

提交前可运行 `./scripts/verify_pte_im_asset_ownership.sh`，阻止以 `PteIMUI` 命名的页面切图误进入四端 Core SDK。

| 产品 | 职责 | 不负责的内容 |
| --- | --- | --- |
| `PteIMSDK` | 配置、UserSig 登录、WSS、消息、好友/群组关系、分页同步、本地加密缓存、COS 上传、E2EE、主题/语言状态、可选 Commerce 扩展 | 业务登录、现金支付、系统选择器 |
| `PteIMUIKit` | 会话列表、联系人/群组列表、一对一/群组聊天、文本/表情、标准附件选择与预览、发送状态、亮暗/中英文、业务动作回调 | 签发 UserSig、保存密钥、替宿主完成支付、红包、礼物和订单业务 |
| `PteIMUIDemo` | 手机号/昵称/密码/图形验证码 → 取得 `userId`/短期 `userSig` → IM 登录 → 好友、会话、群组、我的 | 生产业务后端实现 |

## 仓库

| 项目 | 说明 |
| --- | --- |
| [Pte IM 服务端](https://github.com/pte-live/pte-live-im) | IM 服务、部署、服务端接口实现 |
| [本仓库](https://github.com/pte-live/pte-live-im-sdk) | 四端 PteIMSDK / PteIMUIKit / PteIMUIDemo |
| 项目官网 | 由业务项目配置；客户端不硬编码官网或密钥 |

## 发布

统一发布流程请按 [RELEASE.md](/Users/daniel/Documents/GitHub/pte-live-im-sdk/RELEASE.md) 执行。
当前 uni-app x 约定：打 `v*` Tag 后自动发布，版本以 tag 版本自动对齐（如 `v1.0.0`）。

## 平台与目录

| 平台 | Core | UI | 业务示例 | 最低版本 |
| --- | --- | --- | --- | --- |
| Android 原生 | [android/pte-im-sdk](android/pte-im-sdk) | [android/pte-im-uikit](android/pte-im-uikit) | [android/pte-im-ui-demo](android/pte-im-ui-demo) | Android 12 / API 31 |
| iOS 原生 | [ios/PteIMSDK](ios/PteIMSDK) | [ios/PteIMUIKit](ios/PteIMUIKit) | [ios/PteIMUIDemo](ios/PteIMUIDemo) | iOS 16.0 |
| HarmonyOS 原生 | [harmony/PteIMSDK](harmony/PteIMSDK) | [harmony/PteIMUIKit](harmony/PteIMUIKit) | [harmony/PteIMUIDemo](harmony/PteIMUIDemo) | OpenHarmony API 23 |
| uni-app x UTS | [uni_modules/pte-im-sdk](uni_modules/pte-im-sdk) | [uni_modules/pte-im-uikit](uni_modules/pte-im-uikit) | [uniapp-x/PteIMUIDemo](uniapp-x/PteIMUIDemo) | HBuilderX 5.0+；H5/Web、微信小程序 |

Android、iOS、HarmonyOS 都是独立原生 SDK；iOS UI 仅使用 UIKit。UTS 版本面向 H5/Web 和微信小程序，不包装原生 SDK。所有 UI 源文件以 `PteIMUI` 开头。

客户端技术选型、版本基线和三端职责见[客户端技术基础](docs/client-technology-foundation.md)。本地缓存的加密、分页和容量边界见[四端本地存储基线](docs/local-storage-contract.md)。

## 支持范围

| 场景 | 内容 |
| --- | --- |
| 一对一聊天 | 文本、图片、视频、语音、表情、定位、礼物、红包、订单、文件 |
| 群聊 | 文本、图片、视频、语音、表情、定位、红包、文件 |
| 关系与分页 | 关注即好友、好友/关注/群组/群成员分页、会话游标同步、消息历史分页 |
| Core | 连接/重连、ACK、消息状态、会话与消息同步、本地加密缓存、Outbox、UserSig 续期、COS PUT 上传、E2EE 协议封装 |
| 离线推送基础 | 设备令牌登记、单设备通知开关、登出时删除令牌；令牌仅以服务端 AES-256-GCM 密文保存 |
| 外观 | `light`、`dark`、`system`；`zh-CN`、`en-US`、`system`，可不重新登录即时更新 |

图片、视频和语音使用业务 API 返回的 COS PUT 对象上传；客户端只保存 object key，访问地址由 `cosDomain` 组合。业务动作和系统权限由宿主接管。

## 配置与登录

应用启动阶段只配置域名和显示偏好；登录阶段才传入用户身份。不要把 UserSig、COS 临时凭据或服务器密钥提交到仓库。

```text
PteIMBaseConfig(apiDomain, imDomain, cosDomain, commerceDomain?, themeMode, language)
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
    val chat = PteIMUIKit.createChatView(this, im, conversation.id.toString(), "Alice")
  }
}
```

## IM Commerce 扩展

配置可选 `commerceDomain` 后，四端均通过同一个 `im.commerce`（HarmonyOS）或 `im.commerce`（Android/iOS/UTS）访问礼物、背包、订单、红包和虚拟币余额；它复用现有 UserSig，不创建第二次登录或 WebSocket 连接。所有金额均为 `int64` 最小单位，当前仅支持 `COIN` 虚拟币。

```kotlin
im.commerce.sendGift(
  PteIMGiftSendRequest(clientRequestId = requestId, sku = "rose", quantity = 1, roomId = roomId, sceneType = "live")
) { order ->
  order.onSuccess { value ->
    // 如需单聊/群聊卡片，再用既有 sendGift 发送仅含 orderId 的 E2EE 业务引用。
  }
}
```

红包、礼物和订单的业务状态由 `pte-live-im-commerce` 保存，直播、语聊、社交房间事件经可靠 Outbox 投递到 IM。UIKit 仍只负责展示和点击回调，不承担扣币、支付或订单状态。完整端到端契约见 [Commerce SDK 契约](https://github.com/pte-live/pte-live-im-commerce/blob/main/docs/SDK_CONTRACT.md)。

### iOS

以本地 Swift Package 添加 `ios/PteIMSDK` 与 `ios/PteIMUIKit`：

```swift
import PteIMUIKit

let im = try PteIMSDK.configure(baseConfig).login(loginConfig)
Task {
  let conversation = try await im.openSingleConversation(peerUserId: peerUserId)
  let chat = PteIMUIKit.makeChatViewController(client: im, conversationId: String(conversation.id), title: "Alice")
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

每个 Demo 都通过 `api-im` 的真实演示业务流程登录：注册使用手机号、唯一昵称、密码与一次性图形验证码；登录使用手机号、密码与图形验证码。中国大陆手机号可直接输入 11 位号码，国际号码使用 E.164 格式（例如 `+14155552671`）。后端绑定默认 IM App 并返回 `userId` 和短期 `userSig`，客户端仅在内存中使用 UserSig，不保存密码、验证码或 UserSig。登录后可从“联系人 → 添加好友”进入已注册演示用户列表，完成真实的双向好友关系创建。

```sh
# Android（仓库已固定 Gradle Wrapper 9.5.0）
cd android && ./gradlew --offline :pte-im-ui-demo:assembleDebug

# iOS
xcodebuild -workspace ios/PteIMUIDemo/PteIMUIDemo.xcworkspace -scheme PteIMUIDemo -sdk iphonesimulator CODE_SIGNING_ALLOWED=NO build

# HarmonyOS / API 23
cd harmony/PteIMUIDemo && hvigorw --mode module -p module=entry@default -p product=default assembleHap --analyze=normal
```

在 HBuilderX 打开 `uniapp-x/PteIMUIDemo`，选择 H5 或微信小程序运行。

## 外观和语言

Android `PteIMUIDemo` 默认在本地时间 07:00（含）至 19:00（不含）使用亮色，其余时间使用暗色；语言默认跟随系统。用户在 Demo 中手动选择主题或语言后，该选择会持久化并覆盖自动规则；语言选择“跟随系统”会清除手动语言覆盖。

登录完成后无需刷新 UserSig 或重连：

```text
updateAppearance(themeMode: dark, language: en-US)
updateAppearance(themeMode: system, language: system)
```

Core 使用可并行注册的 `PteIMListener` 发出外观、消息、发送状态、UserSig 和错误事件；业务层与多个 PteIMUIKit 页面不会互相覆盖回调。页面/宿主对象销毁时必须注销自己的 listener。更多协议、存储与安全约束见 [架构说明](docs/architecture.md) 和 [安全说明](docs/security.md)。

## 离线推送（U-Push）

业务在系统推送 SDK 成功获取 token 后登记设备；`PteIMSDK` 不包含厂商密钥，也不会在本地缓存该 token。服务端必须通过部署密钥 `CHAT_PUSH_TOKEN_ENCRYPTION_KEY`（base64 编码的 32 字节 AES-256 密钥）开启令牌登记。用户退出登录、关闭推送或设备切换时调用注销接口，服务端会物理删除对应密文令牌。

```swift
let device = try await im.registerPushDevice(
  deviceId: installationId,
  platform: .ios,
  token: providerToken,
  notificationEnabled: true
)
try await im.setPushDeviceNotification(deviceId: device.deviceId, platform: .ios, enabled: false)
try await im.unregisterPushDevice(deviceId: device.deviceId, platform: .ios)
```

当前阶段完成了安全登记与通知偏好闭环。真正的 U-Push 离线投递会在后台默认设置填入 Android/iOS/鸿蒙各环境密钥后启用；端到端加密会话的通知内容只能使用通用“你收到一条新消息”，不得包含消息明文。

## PteIMUIKit 聊天 UI 架构

PteIMUIKit 采用“消息内容单元 + 独立输入条 + 宿主业务回调”的分层方式，参考 MessageKit 的可定制消息单元与 InputBar 思路，但不引入任何第三方 UI 依赖。四端均提供独立的 `PteIMUIInputBar`；它可以脱离聊天页单独复用。

Android 的 `PteIMUINotice` 是 UIKit 内置反馈组件，提供 `success`、`error`、`info` 三种语义提示；默认底部弹出，也可配置居中、显示时长、亮暗色板和独立提示颜色。它会自动避免键盘与导航栏，并替换同一窗口内上一条提示。

输入条固定顺序为：`语音切换` → `输入框 / 按住说话` → `+` → `表情` → `发送`。点击语音后，中间区域变为“按住说话”；开始和结束录音只通知宿主，录音权限、编码、上传完成后调用 Core 的 `sendVoice` 仍由业务负责。Android `+` 面板内置图片、拍摄、视频、文件和位置选择：UIKit 使用系统选择器、COS 上传与 Core 消息发送；位置使用 UIKit 自身的当前位置/地点搜索/坐标确认页。礼物、红包、订单和自定义消息只输出统一 Core 消息格式与宿主回调，不完成支付或业务详情。表情面板内置默认表情项。

默认视觉是蓝紫渐变发送气泡与发送按钮，并为亮/暗模式提供两套完全独立的组件色板：背景、会话面、输入栏、收发气泡、渐变、文字、图标、分割线、表情面板和更多面板均可分别配置。

### iOS UIKit

```swift
let theme = PteIMUITheme(
  light: .blueVioletLight,
  dark: .blueVioletDark
)
let chat = PteIMUIKit.makeChatViewController(
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

`PteIMUIThemePalette` 的所有字段均为公开参数，包含展开输入框专用的 `composerInputColor`，因此可以只替换 `light` 或 `dark` 的任意组件颜色，不会影响另一套模式。`themeMode = system` 时 UIKit 会自动随系统外观刷新。iOS 聊天页还支持 `navigationSubtitleText`（在线状态/群成员数）与 `reactionProvider`（宿主持久化的消息反应汇总）。

iOS 将文本/表情/语音与富消息卡片分离：`PteIMUIMessageCell` 渲染前者，`PteIMUIRichMessageCell` 原生渲染图片、视频、定位地图、红包、礼物、订单与文件。富消息只负责呈现与消息收发；红包、礼物和订单的业务状态、支付和详情页始终通过宿主的消息点击回调处理。宿主可通过 `PteIMUIIconProvider` 替换 `.messageImagePlaceholder`、`.messageVideoPlay`、`.messageRedPacketBackground`、`.messageGiftBackground`，无需把任何页面资源放入 `PteIMSDK`。

### Android、HarmonyOS、uni-app x

Android 使用 `PteIMUITheme(light = …, dark = …)` 并传给 `PteIMUIKit.createChatView`、`createConversationListView` 或 `createContactListView`；HarmonyOS 通过三个组件的 `theme` 属性传入；UTS 通过 `<PteIMUIChat>`、`<PteIMUIConversationList>`、`<PteIMUIContactList>` 的 `:theme` 属性传入。三端均遵循同一套色板字段和输入回调：`onActionRequested` / `action` 负责更多面板，`onVoiceRecordingChanged` / `voice-recording` 负责按住说话状态。

三端聊天页与 iOS 一致提供标题副文案（在线状态/群成员数）、消息状态时间、文本/表情/语音与图片、视频、定位、红包、礼物、订单、文件富消息卡片。Android 使用 `navigationSubtitleText`、`reactionProvider` 和 `onReactionChanged`；其中 `PteIMUIReaction.reactedByCurrentUser` 声明当前用户是否已反应，UIKit 会乐观地执行新增/取消、仅在数量大于 1 时显示数字，并通过回调交由宿主持久化。HarmonyOS 使用 `navigationSubtitleText`、`PteIMUIReactionProvider`；UTS 使用 `subtitle`、`:reaction-provider`。UIKit 不把业务反应写入 Core。

Android 的图片和视频卡片点击后进入 UIKit 原生预览：`PteIMUIMediaPreviewActivity` 是 `open` 页面，图片点击关闭、长按保存相册；视频支持暂停/播放、关闭和底部进度条。文件进入 `PteIMUIFilePreviewActivity`（同为 `open` 页面），点击交给系统预览、长按保存到系统文件。定位卡片使用地图缩略图，不叠加定位图标；点击后按高德、百度、腾讯、Google、系统地图的顺序检测并携带目的地唤起外置地图。二级导航的返回与更多均为 44 dp 点击区并使用满幅图标。长按菜单始终可引用；仅文本消息显示复制；撤回与删除仅对当前用户发送的消息显示。UIKit 会本地即时更新删除/撤回并通过回调交由业务调用其已授权的服务端撤回接口。

会话与联系人页面均提供设计稿对应的品牌标题栏、亮暗切换入口、语言切换入口、搜索/快捷操作区、渐变头像、时间和分隔层级；列表数据、头像点击、添加好友/建群和跳转仍通过公开回调交给宿主业务层。Android 会话页的 `PteIMUIConversationPresentation` 可通过 `presentationTransformer` 重写昵称、预览、时间、头像、在线状态与未读数；`onCreateConversation`、`onThemeModeRequested`、`onLanguageRequested` 交给宿主处理业务路由和持久化，`maxVisibleConversations` 只控制展示数量，不改变 Core 同步或分页。Android 允许覆写 `conversationHeader()`、`conversationRow(item)`、`contactHeader()`、`contactRow()`；HarmonyOS 与 UTS 保持组件属性和事件形式，便于按宿主页面重排。

#### Android 继承与重写

Android 的三个 UIKit 入口均为 `open class`，不需要 fork SDK。`PteIMUIConversationListView` 可覆写 `conversationHeader()`、`searchBar()`、`createConversationCell()`/`conversationRow()`、`selectConversation()`，并使用 `onAvatarTapped` 接管头像事件；固定导航栏与搜索栏、下拉刷新和 Core 分页同步仍由 UIKit 保留。`PteIMUIContactListView` 可覆写 `contactHeader()`、`createContactCell()`/`contactRow()`、`presentation()` 和 `select()`，并使用 `onAvatarTapped` 进入宿主资料页。`PteIMUIChatView` 可覆写 `buildHeader()`、`messageView()`、`messageBody()`、`messageAvatar()`、`voiceBubble()`、`businessCard()`、`showMessageMenu()`；`inputBar` 与 `header` 为 `protected`，可通过 `addNavigationExtension()` 增加宿主导航项。

`PteIMUIChatView` 内置文本和 Unicode 表情混合发送、失败重试、已读上报、引用、复制、仅本地删除、乐观表情反应；`onMessageRevoked`、`onMessageDeleted`、`onMessageRetryRequested` 和 `onReactionChanged` 用于把结果同步到业务服务。图片、视频、文件的选择、COS 上传、发送与失败重试由 UIKit 完成；`mediaPreviewActivityClass`、`filePreviewActivityClass` 可分别替换成继承自 `PteIMUIMediaPreviewActivity`、`PteIMUIFilePreviewActivity` 的宿主页面。`sendCustomMessage(PteIMUICustomMessage)` 为红包、礼物、订单和自定义业务消息提供统一入口，`CUSTOM` 仅触发 `onCustomMessageRequested`。

```kotlin
class OrderChatView(context: Context, client: PteIMSDK, id: String) :
  PteIMUIChatView(context, client, id, title = "订单咨询") {

  override fun messageBody(message: PteIMMessage, outgoing: Boolean): View {
    return if (message.type == PteIMMessageType.ORDER) orderCard(message) else super.messageBody(message, outgoing)
  }

  override fun buildHeader(title: String) {
    super.buildHeader(title)
    addNavigationExtension(makeOrderDetailButton())
  }
}
```

该分层借鉴 MessageKit 的“内容 Cell + 自定义 Cell 工厂”和 MessageInputBar 的“独立输入组件”思路：消息排序、发送状态、缓存同步及输入状态由 UIKit 管理，导航、头像、业务卡片、录音、红包/礼物/订单详情始终由宿主实现。

### 联系人与群组 UIKit

三个原生端均可使用内置分页列表：iOS `PteIMUIContactListViewController(client:mode:)`，Android `PteIMUIKit.createContactListView(context, client, mode, onConversationClick)`，HarmonyOS `PteIMUIContactList({ client, mode, contactHandler, avatarHandler })`。`mode` 为好友、关注、群组或 `custom`；好友点击时 UIKit 通过 Core 的 `openSingleConversation` 获取服务端会话 ID，群组则直接进入群会话。UTS 使用 `<PteIMUIContactList :client="client" mode="friends" @select="openChat" @avatar="openProfile" />`。iOS 的 `PteIMUIContactPresentation` 支持 `sectionTitle` 分区和 `isOnline` 在线状态点，均由宿主资料层提供；所有入口支持外部导航、头像点击、错误处理和自定义行/数据映射，不自行保存关系数据。

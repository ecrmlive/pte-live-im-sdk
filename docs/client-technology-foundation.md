# PteIM 客户端技术基线

PteIMSDK 是 Core SDK，PteIMUIKit 提供会话、联系人和聊天界面，PteIMUIDemo 展示业务注册/登录后获取 UserSig 并进入 IM 的完整流程。所有端使用 `PteIMBaseConfig` 完成域名、皮肤和语言初始化，再使用 `PteIMLoginConfig` 登录。后端返回短期 `userSig`、`expireAt` 和宿主保存的 refresh session；宿主将后者封装为 `userSigProvider`。Core 在到期前 5 分钟、IM HTTP `401` 和 WSS 过期事件后自动续签，失败时通过 `onUserSigRefreshFailed` 让宿主返回业务登录。Core 不保存 refresh session、密码、验证码或签名密钥。

## iOS

| 项目 | 标准 |
| --- | --- |
| 最低版本 | iOS 16.0 |
| 语言 | Swift 6 |
| UI | Swift + UIKit；不使用 SwiftUI |
| 当前模块结构 | Core / UIKit / Demo 分层；未引入 Factory 或 Swinject |
| 网络 | URLSession |
| 长连接 | URLSessionWebSocketTask |
| 本地存储 | Core Data |
| 并发 | async/await、Actor |
| 依赖注入 | 当前由宿主装配；未引入 DI 框架 |
| 日志与监控 | OSLog；崩溃采集由宿主接入 |
| 推送 | 友盟+ U-Push |

`PteIMSDK` 只放 Core、Core Data、E2EE、网络与同步能力；`PteIMUIKit` 只放 UIKit 页面及可配置视觉组件。Core Data 缓存按账号隔离，消息正文、Outbox 内容和同步游标保持 AES-256-GCM 加密，密钥位于 Keychain。

## Android

| 项目 | 标准 |
| --- | --- |
| 最低版本 | Android 12（API 31） |
| 语言 | Kotlin |
| UI | 当前 UIKit 为 Android View；未包含 Compose 页面 |
| 当前模块结构 | Core / UIKit / Demo 分层 |
| 网络 | `HttpURLConnection` |
| 长连接 | SDK 内置 `WssTransport`（TLS Socket） |
| 本地存储 | Room |
| 并发 | Coroutines、Flow |
| 依赖注入 | 当前未引入 Hilt |
| 日志与监控 | 当前未引入 Timber；崩溃采集由宿主接入 |
| 推送 | 友盟+ U-Push |

Room 数据库按账号隔离，消息、会话、Outbox 和同步游标支持分页、索引、去重及持久化重试。加密密钥由 Android Keystore 管理。Android 与 iOS 已将引用、撤回、单账户删除和表情反应写入缓存并消费实时事件；其他端的精确状态见[消息生命周期](message-lifecycle.md)。

## OpenHarmony

| 项目 | 标准 |
| --- | --- |
| 最低版本 | OpenHarmony API 23 |
| 语言 | ArkTS |
| UI | ArkUI |
| 架构 | MVVM + Repository |
| 网络 | ohos.net.http |
| 长连接 | WebSocket API |
| 本地存储 | ArkData RDB |
| 并发 | Promise、TaskPool |
| 依赖注入 | Provider |
| 日志与监控 | HiLog + 崩溃采集 |
| 推送 | 友盟+ U-Push |

RDB 以账号命名空间存放会话、消息、Outbox 和同步游标，并启用系统加密等级。

## uni-app x UTS

| 项目 | 标准 |
| --- | --- |
| 开发工具 | HBuilderX 5.0+ |
| 语言 | UTS / uvue |
| 目标 | H5/Web、微信小程序 |
| Core | `uni_modules/pte-im-sdk` |
| UI | `uni_modules/pte-im-uikit` |

UTS 模块使用宿主提供的 HTTPS、WSS 与本地安全存储能力。H5 必须运行在安全上下文；微信小程序必须配置 API 与 WSS 域名白名单。

## Browser（独立 Web Core）

| 项目 | 标准 |
| --- | --- |
| 运行环境 | 现代浏览器安全上下文（HTTPS / localhost） |
| 语言 | TypeScript（ESM） |
| 包名 | `@pte-live/pte-im-sdk` |
| 路径 | `web/pte-im-sdk` |
| 聊一聊 | `PteIMWebSDK` / `PteLiveIMWebClient`：加密 REST、`/ws`、E2EE 收发 |
| 扩展 | `PteIMCommerce`（需 `commerceDomain`） |
| 房间 | `PteIMSceneClient`：独立 WSS + `scene.enter`（show/voice/shop/sports） |
| 密码学 | `@noble/ciphers` / `@noble/curves` / `@noble/hashes`（与 UTS 同版本） |
| 设备身份 | IndexedDB + 不可导出 AES-GCM 包装；隐私模式失败时不阻断会话 |

Browser 包不包含 UIKit，也不替代 uni-app x UTS。房间业务补漏 HTTP 由宿主完成；协议摘要见 [live-event-protocol.md](live-event-protocol.md) 与 [scene-client-contract.md](scene-client-contract.md)。

# PteIMSDK UTS

This is a uni-app x UTS API plugin for H5/Web and WeChat mini-program targets.

Android, iOS, and HarmonyOS use their own independent native SDK packages in this repository. This plugin uses its UTS cross-platform WSS implementation and has no native AAR, XCFramework, or Harmony HAR dependency.

Configure connectivity once using `PteIMBaseConfig`, then authenticate with `PteIMLoginConfig`.

```uts
import { createPteIMSDK } from '@/uni_modules/pte-im-sdk'

const bootstrap = createPteIMSDK({
  apiDomain: 'https://api.example.com',
  imDomain: 'wss://im.example.com/ws',
  cosDomain: 'https://cos.example.com',
  themeMode: 'system',
  language: 'system',
})
const im = bootstrap.login({
  sdkAppId: 1400000001,
  userId: '10001',
  userSig: 'server-issued-usersig'
})
im.start()
```

H5、微信小程序目标已实现 `onConnectionChanged`、`onMessage`、`onMessageStateChanged`、UserSig 过期和错误事件，并在断线后以 1–30 秒退避重连、收到消息后发送 ACK。默认不将消息、Outbox 或 `syncCursor` 写入 `uni` storage，避免明文缓存；需要重启恢复时，宿主必须在 `PteIMBaseConfig.localStorageCipher` 提供同步加解密器，且密钥不得写入 source 或 `uni` storage。`userSig` 永不写入 storage。配置了加密器后，SDK 会持久化 `syncCursor` 与最新 1,000 条已确认消息，提供 `localMessages()`、`localConversations()` 缓存读取，并在连接成功或服务端发出 `sync_required` 时调用 `syncNow()`；同步消息通过 `onMessage` 分发。

图片、视频和语音可直接上传并发送：`uploadAndSendImage(conversationId, filePath)`、`uploadAndSendVideo(conversationId, filePath)`、`uploadAndSendVoice(conversationId, filePath, durationMs, waveform?)`。它们先调用 `POST /v1/im/media/put-url`，再以 `uni.request` 的二进制 `PUT` 上传到返回的 Tencent COS URL；消息和 Outbox 只保存返回的 object key。上传期间发送 `uploading` 状态，成功后使用相同的 `clientMsgId` 转为 `pending` 并进入持久化 Outbox，失败则发送 `failed`。H5 的 `filePath` 应来自当前页面选择的本地文件，微信小程序应传递其文件选择 API 返回的临时路径；COS 必须允许对应站点的 `PUT`、`Content-Type` 跨域请求。

主题和语言可在不重新登录的情况下更新：

```uts
im.onThemeModeChanged((mode) => refreshTheme(mode))
im.onLanguageChanged((language) => reloadCopy(language))
im.updateAppearance('dark', 'en-US')
// 重新跟随系统：im.updateAppearance('system', 'system')
```

WeChat mini-program must register the HTTPS/WSS domains in its platform allowlist. H5 must allow the API origin through CORS and the IM origin through WebSocket Origin policy.

## PteIMUIkit

`PteIMUIChat` and `PteIMUIConversationList` are reusable uvue components in `components/`; `utssdk/PteIMUIkit.uts` also exports controllers for a custom UTS view. Pass an already-logged-in client. The `action` event delegates image/video/voice pickers, location and business workflows to the host:

```vue
<!-- conversation.id is returned by openSingleConversation/createGroupConversation. -->
<PteIMUIChat :client="im" :conversation-id="String(conversation.id)" @action="handlePteIMAction" />
```

The components follow Core theme and language updates. UI source files use the `PteIMUI` prefix.
# PteIMSDK UTS

## E2EE dependencies

This module implements the same P-256/AES-256-GCM envelope as the native SDKs for H5/Web and WeChat mini-programs. Before building the uni-app x project, install the pinned module dependencies from the project root:

```sh
npm install --prefix uni_modules/pte-im-sdk
```

H5 uses the browser secure random source; the WeChat entry module uses `wx.getRandomValues`. The SDK never substitutes `Math.random()` and never reuses a random-byte buffer. For durable device identity across restarts, configure `localStorageCipher`; without it, the UTS device identity is session-only and a new device is registered on the next start.

See [the repository security contract](../../docs/security.md) and [third-party notices](../../THIRD_PARTY_NOTICES.md).

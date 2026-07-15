# PteIMSDK · HarmonyOS Native SDK

`@ptelive/pte-im-sdk` is an independent ArkTS SDK for HarmonyOS. It is not part of the uni-app x UTS plugin.

The SDK uses platform WebSocket and relational-store (SQLite) APIs only. Add `ohos.permission.INTERNET` and configure the production API/WebSocket domains in the host application's network-security configuration.

```ts
const base = new PteIMBaseConfig(
  'https://api.example.com',
  'wss://im.example.com/ws',
  'https://cos.example.com',
  PteIMThemeMode.SYSTEM,
  PteIMLanguage.SYSTEM,
)
const client = await PteIMSDK.configure(this.context, base).login(
  new PteIMLoginConfig(1400000001, 'user-100', 'usersig'),
)

client.addListener(new PteIMListener())
await client.sendText('c2c:user-200', '你好')
await client.uploadAndSendImage('c2c:user-200', '/data/storage/el2/base/files/photo.jpg', 'image/jpeg')
```

`uploadAndSendImage`, `uploadAndSendVideo`, and `uploadAndSendVoice` first call `POST /v1/im/media/put-url`, PUT the file to the returned Tencent COS URL, and then send only the returned object key. Voice upload requires its recording duration and optionally accepts a waveform. They retain one stable `clientMsgId` through upload and sending; a failed upload is persisted as `failed` but is not put into the retry outbox. `sendImage` and `sendVideo` also accept a `PteIMMedia` descriptor whose URL can be an absolute URL or a COS object key; relative keys are resolved from `cosDomain` for display.

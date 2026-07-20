# PteIMSDK · HarmonyOS Native SDK

`@ptelive/pte-im-sdk` is an independent ArkTS SDK for HarmonyOS. It is not part of the uni-app x UTS plugin.

The SDK uses the platform WebSocket API and ArkData RDB. Add `ohos.permission.INTERNET` and configure the production API/WebSocket domains in the host application's network-security configuration.

```ts
const base = new PteIMBaseConfig(
  'https://api.example.com',
  'wss://im.example.com/ws',
  'https://cos.example.com',
  PteIMThemeMode.SYSTEM,
  PteIMLanguage.SYSTEM,
)
const userSigProvider: PteIMUserSigProvider = {
  refreshUserSig: async (): Promise<PteIMUserSigRefreshResult> => {
    // 使用宿主保存的 refresh session 调用业务接口；不要生成或记录签名。
    const renewed = await businessApi.refreshIMSession()
    return new PteIMUserSigRefreshResult(renewed.userSig, renewed.expireAt)
  },
}
const client = await PteIMSDK.configure(this.context, base).login(
  new PteIMLoginConfig(1400000001, 'user-100', 'usersig', userSigExpireAt, userSigProvider),
)

client.addListener(new PteIMListener())
await client.sendText('c2c:user-200', '你好')
await client.uploadAndSendImage('c2c:user-200', '/data/storage/el2/base/files/photo.jpg', 'image/jpeg')
```

`userSigProvider` 是唯一的业务认证适配点：Core 在 UserSig 到期前 5 分钟、IM HTTP `401` 或 WSS 的 `user_sig_will_expire` / `user_sig_expired` 事件后自动调用它，成功后更新连接凭证并同步会话与消息。不要在 ArkUI 页面自行维护续签计时器。刷新失败时，`PteIMListener.onUserSigRefreshFailed` 会通知宿主清除 refresh session 并返回业务登录。SDK 不保存 refresh session、账号密码、验证码或 UserSig 签名密钥。

`uploadAndSendImage`, `uploadAndSendVideo`, and `uploadAndSendVoice` first call `POST /v1/im/media/put-url`, PUT the file to the returned Tencent COS URL, and then send only the returned object key. Voice upload requires its recording duration and optionally accepts a waveform. They retain one stable `clientMsgId` through upload and sending; a failed upload is persisted as `failed` but is not put into the retry outbox. `sendImage` and `sendVideo` also accept a `PteIMMedia` descriptor whose URL can be an absolute URL or a COS object key; relative keys are resolved from `cosDomain` for display.

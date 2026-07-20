# PteIMUIDemo · iOS

`PteIMUIDemo.xcworkspace` 是原生 UIKit 应用入口。它链接本地 `../PteIMSDK` 与 `../PteIMUIKit` Swift Package，展示完整流程：业务注册/登录 → 后端签发短期 `userId` / `userSig` / `expireAt` 与 refresh session → PteIMSDK 登录 → PteIMUIKit 会话、好友聊天、群聊和“我的”入口。

Its Logo, Launch Screen and business-example images belong in `PteIMUIDemo/Resources/`. It must not read visual assets from `PteIMSDK`; shared conversation, contact and chat images belong to `PteIMUIKit`.

在 Xcode 中打开 `PteIMUIDemo.xcworkspace`，运行到 iOS 16.0+ 模拟器或设备。登录页只要求手机号、密码和图形验证码；点击“创建演示账号”会原生 Push 到独立注册页，注册页额外要求唯一昵称。中国大陆手机号直接输入 11 位号码，国际号码使用 E.164 格式。联系人页的“添加好友”会 Push 到已注册 Demo 用户列表，并创建真实的双向 IM 好友关系。

登录时应把 `expireAt` 和 `PteIMUserSigProvider` 传给 `PteIMLoginConfig`。provider 使用宿主 refresh session 请求业务刷新接口，返回 `PteIMUserSigRefreshResult`；SDK Core 会在到期前 5 分钟、IM HTTP `401` 和 WSS 过期事件后自动续签、更新连接并同步数据。页面不需要自行维护续签定时器。`onUserSigRefreshFailed` 是回到业务登录的终态回调。

示例不把密码、验证码或 UserSig 写入磁盘。Demo 的 refresh session 仅用于演示；生产应用应保存到 Keychain，并在刷新失败时清除它。不要将 UserSig、refresh session、COS 凭据或签名密钥输出到日志或提交到仓库；请将表单示例替换为已认证的业务 API。

For deterministic UI review, the Debug build provides an offline `本地 UI 预览` route. It creates `PteIMSDK.preview(...)`, which uses only an in-memory cache and temporary encryption key: no UserSig is transmitted, and no production Core Data or Keychain record is read or written. The preview contains conversation, contact and chat fixtures; it is not included as a production login path.

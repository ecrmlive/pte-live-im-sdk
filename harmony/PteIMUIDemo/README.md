# HarmonyOS Demo

`PteIMUIDemo` 是独立的 ArkUI Stage 业务示例，链接同级 `PteIMSDK` 与 `PteIMUIKit` HAR。它展示业务注册/登录 → 短期 UserSig → IM 登录、好友关系、个人页、会话、群组、消息控制、同步/缓存事件与主题/语言切换；不会提交 UserSig 或部署密钥。

在 DevEco Studio 打开 `harmony/PteIMUIDemo`，允许本地 `@ptelive/pte-im-sdk` 与 `@ptelive/pte-im-uikit` HAR 依赖，再运行 `entry` 模块。`EntryAbility` 会在登录页出现前配置 `apiDomain`、`imDomain`、`cosDomain`。登录页仅收集手机号、密码和图形验证码；点击“创建演示账号”进入独立注册页，注册页额外要求唯一昵称。中国大陆手机号可输入 11 位号码，国际号码使用 E.164 格式；“联系人 → 添加好友”进入已注册 Demo 用户列表并建立真实双向好友关系。

业务后端返回 SDK App ID、user ID、短期 UserSig、`expireAt` 与 refresh session。登录时将 `expireAt` 和 `PteIMUserSigProvider` 放入 `PteIMLoginConfig`；provider 只使用宿主 refresh session 请求业务刷新接口并返回 `PteIMUserSigRefreshResult`。SDK Core 会在到期前 5 分钟、IM HTTP `401`、WSS 过期事件后自动续签、更新连接并同步，页面不需要自行计时或重连。`PteIMListener.onUserSigRefreshFailed` 是清理 refresh session 并返回业务登录页的终态回调。

示例不持久化密码、验证码或 UserSig。refresh session 在生产环境应交由系统安全存储保护；不要写入源码、日志或 SDK 本地缓存。

The media API needs a host file picker because permission and picker requirements differ by device profile. Pass its returned sandbox path to `uploadAndSendImage`, `uploadAndSendVideo`, or `uploadAndSendVoice`.

底部 Tab 的图标状态由当前页面统一驱动：当前页使用紫色图标和指示线，其他 Tab 使用独立灰色图标滤镜。Chats 的未读角标是会话状态，不依赖 Chats 是否处于选中状态；切换到联系人或我的后仍会持续显示。

系统状态栏背景始终和当前页面的顶部导航栏使用同一颜色。会话、联系人、我的属于一级页面并显示底部 Tab；聊天、设置和语言设置属于二级页面，进入后会隐藏底部 Tab。

# Android Demo

`PteIMUIDemo` is a dependency-free native Android business-sample app for `:pte-im-sdk` and `:pte-im-uikit` (Android 12 / API 31+). It demonstrates business login → short-lived UserSig → `PteIMSDK` login, friend relations, profile entry points, and reusable `PteIMUIKit` conversation/chat/group UI. It also exercises E2EE connection events, COS media upload, local cache/sync, and theme/language callbacks.

```bash
cd android
./gradlew :pte-im-ui-demo:installDebug
```

`PteIMUIDemoApplication` configures `apiDomain`、`imDomain`、`cosDomain` once at application startup. The deployable Demo flow registers with a mobile number, unique nickname, password and one-time graphical captcha; it logs in with mobile number, password and captcha. `api-im` validates China and E.164 international mobile numbers, binds the user to the default IM app, and returns the numeric SDK App ID, user ID and short-lived UserSig. The app never persists the password, captcha or UserSig.

应用从 `PteIMUIDemoSplashActivity` 进入：Android 12+ 使用深紫色系统启动窗口与 Android 专用应用图标，随后显示设计稿提供的「PTE Live IM / PTE LIVE」全屏启动图，再进入业务登录。启动图与 Android 图标仅打包在 `PteIMUIDemo`，不会进入 `PteIMSDK` 或 `PteIMUIKit`。

Debug builds connect to the local `pte-live-im` Docker stack through `127.0.0.1` after the user registers or logs in through the complete Demo business-login form. In Contacts, “Add Friend” opens the registered Demo-user list and creates a real bidirectional IM friendship. Release builds retain HTTPS/WSS validation and use the same mobile/password/captcha flow.

Appearance is intentionally independent of login state. Without a manual preference, the demo uses light mode from local 07:00 (inclusive) to 19:00 (exclusive), and dark mode at all other times. Language follows the Android system locale by default. Choosing a theme or `简体中文`/`English` creates a persisted manual override; choosing `跟随系统` clears the language override. Neither preference stores UserSig or any deployment secret.

`PteIMUIKit` 的会话、联系人导航栏不再放置语言或亮暗操作。`PteIMUIDemo` 的“我的”页是唯一的外观入口：可直接切换皮肤，点击“语言”进入独立设置页（`跟随系统`、`简体中文`、`English`）；“设置”页提供相同的外观和语言入口。Android 13+ 的系统预测返回会按“语言 → 设置/我的 → 我的”链路返回，不会直接退出 Demo。

`PteIMUIConversationListView` 固定 44 dp 导航栏和搜索栏，仅会话行区域可滚动与下拉刷新。用户下拉默认调用 `PteIMSDK.syncConversationsNow()` 的游标同步；宿主如需改接业务刷新流程，可设置 `onPullToRefresh`，并在完成后调用 `finishPullRefresh()`。底部会话未读角标固定在图标右上角，不会偏离到 Tab 中央。

聊天页由 `PteIMUIKit` 提供统一的 44 dp 导航栏、日期分隔线、文本/图片/视频/语音/定位/红包/礼物/订单/文件消息单元、亮暗皮肤、长按消息菜单和独立输入栏。导航仅保留返回与更多按钮，图标满幅位于各自 44 dp 点击区；发送方时间后的已读/未读状态使用 UIKit 内的设计切图。图片点击使用 UIKit 原生全屏预览，视频点击使用原生播放器；定位显示地图缩略图并按高德、百度、腾讯、Google、系统地图顺序携带目的地跳转。长按菜单的表情可直接新增或取消当前用户反应，数量仅在大于 1 时显示；引用始终可见，复制只对文本消息显示，撤回和删除只对当前用户消息显示；点击菜单“+”会关闭菜单并打开表情输入面板。输入栏支持文字发送（软键盘动作键为“发送”）、按住录音回调、Unicode Emoji6 兼容表情选择，以及图片、拍摄、视频、定位、文件、红包、礼物、订单八项扩展动作；文件选择和红包/礼物/订单业务由 Demo 通过回调接入。`PteIMUINotice` 统一处理成功、错误和普通反馈，支持底部或居中弹出、亮暗独立色板、自定义颜色、自动避开键盘与导航栏；同一窗口的新提示会替换旧提示，点击即可关闭。空 Debug 测试会话展示完整本地视觉夹具，方便验收；一旦存在真实缓存消息，UIKit 会立即只显示真实消息。

会话、联系人和聊天视图均可直接继承：会话页覆写 `conversationHeader()`、`searchBar()`、`createConversationCell()`/`selectConversation()`；联系人页覆写 `contactHeader()`、`createContactCell()`/`select()`；聊天页覆写 `buildHeader()`、`messageBody()`、`messageAvatar()`、`showMessageMenu()`。UIKit 始终保留消息缓存、游标同步、发送状态和输入条状态，业务只替换展示与跳转逻辑。

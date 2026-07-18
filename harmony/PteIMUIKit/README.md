# PteIMUIKit · HarmonyOS

`@ptelive/pte-im-uikit` supplies dependency-free ArkUI conversation components. Configure and log in through `@ptelive/pte-im-sdk` first, then embed `PteIMUIChat`, `PteIMUIConversationList` or the cursor-paginated `PteIMUIContactList`. The contact list supports friends, follows and groups, opens C2C conversations through Core, and routes selection through `PteIMUIContactHandler`. The host receives action callbacks for media pickers, location and business messages.

`PteIMUIChat` accepts `navigationSubtitleText` for online state or group-member count, and `reactionProvider: PteIMUIReactionProvider` for host-persisted reaction badges. It renders text, emoji, voice, image, video, location, red packet, gift, order, file and custom messages; payment, gift, order and custom business actions remain host-owned.

## 统一成功与错误提示

`PteIMUINotice` 是 UIKit 内置的无依赖浮层，支持 `BOTTOM`（不遮挡页面交互）和 `CENTER`（带轻遮罩）两种位置。页面保存一个 `PteIMUINoticeHandler`，即可从登录、网络请求或业务操作统一显示成功/错误提示：

```ts
@State noticeVisible = false
@State noticeMessage = ''
@State noticeKind = PteIMUINoticeKind.SUCCESS
@State noticeRevision = 0

private notices = new PteIMUINoticeHandler((notice) => {
  this.noticeMessage = notice.message
  this.noticeKind = notice.kind
  this.noticeVisible = true
  this.noticeRevision++
})

// 放在页面根 Stack 的最后一个子组件，保证显示在业务页面上方。
PteIMUINotice({
  visible: this.noticeVisible,
  message: this.noticeMessage,
  kind: this.noticeKind,
  revision: this.noticeRevision,
  dismissHandler: new PteIMUINoticeDismissHandler(() => this.noticeVisible = false),
})

// 业务代码中：
this.notices.success('保存成功')
this.notices.error('网络不可用，请重试', PteIMUINoticePosition.CENTER)
```

## 继承与重写

ArkUI 页面使用组合而非组件继承。UIKit 提供可继承的展示转换器，使宿主仅重写显示数据，不破坏 SDK 的同步、分页、发送状态和本地存储：

- `PteIMUIConversationPresentationTransformer`：改写会话标题、摘要、时间、头像及未读数。
- `PteIMUIContactPresentationTransformer`：改写联系人/群组行的名称、说明和头像。
- `PteIMUIMessagePresentationTransformer`：改写聊天单元的文案、时间、发送者名称和头像。
- `PteIMUIChatNavigationHandler`：由宿主接收聊天返回事件，因此会话与联系人可各自决定返回页面。

输入栏独立为 `PteIMUIInputBar`，支持以下完整交互：

- 点击语音/键盘切换；按住录音时展示“正在说话”，手指移出按钮后展示“松开手取消录音”，松开或取消会通知 `PteIMUIVoiceRecordingHandler`。
- 输入框为多行 `TextArea`：最少高 `40`、最多高 `120`、最多 `200` 字符，左右内边距 `10`、上下内边距 `5`；超过最大高度时输入框自身滚动。键盘显示时仅使用系统键盘的“发送”键提交，UIKit 不显示第二个发送按钮；仅在表情面板打开且键盘未显示时，面板内保留发送按钮。
- 表情分为“常用表情”和“全部表情”两个数据集。通过 `PteIMUIEmojiDataSource(common, all)` 传入；每项占 `44 × 44`，自定义图片在单元中按 `24 × 32` 显示。点击表情会插入输入框，底部回撤删除最后一个字符，发送会复用 `client.sendText`。
- 图片、视频走系统媒体选择器；拍摄走系统相机选择器；文件走系统文档选择器；定位读取当前坐标后调用对应 SDK 发送 API。接入应用需声明相机、麦克风、近似位置和精确位置权限。
- 红包、礼物、订单只调用 `PteIMUIActionHandler.requestBusiness`，由继承/组合 UIKit 的宿主打开各自业务流程。自定义入口通过 `PteIMUICustomAction` 和 `requestCustom` 外露。
- 功能区默认两行八项；`PteIMUIChat.customActions` 可追加最多四项，形成第三行，最多三行十二项。功能项高 `75`、图标 `52 × 52`、图标到文字间距 `8`、文字高 `15`、行间距 `20`。

## 聊天消息交互与媒体页面

UIKit 默认处理选择图片/相机拍摄/选择视频/文件、上传后入可靠发送队列、失败重试、本地持久化、长按菜单、引用、文本复制、删除、输入混合文本与表情，以及本地表情反应的即时显示。`PteIMUIChat` 中的图片、视频、文件预览已拆分为可独立嵌入的页面组件：

- `PteIMUIImagePreview`：单击遮罩关闭，长按回调保存到相册。
- `PteIMUIVideoPreview`：原生播放/暂停、关闭和底部进度条，长按回调保存视频。
- `PteIMUIFilePreview`：点击预览、长按保存系统文件。
- 位置消息仅显示 `bundleManager.canOpenLink` 可解析的地图目标，避免向未安装地图应用发起跳转。

预览页面的实际保存/文件打开、地图选点、服务器已读回执，以及全端撤回/删除/表情反应由宿主协议决定。通过以下处理器接入即可保持 UIKit 的 UI 与交互不变：

```ts
PteIMUIChat({
  // ...client / conversationId
  readReceiptProvider: new PteIMUIReadReceiptProvider(),
  locationPickerHandler: new PteIMUILocationPickerHandler(),
  mediaPreviewHandler: new PteIMUIMediaPreviewHandler(),
  operationHandler: new PteIMUIMessageOperationHandler(
    (message, emoji, selected) => { /* 持久化表情反应 */ },
    (message) => { /* 记录引用行为（发送时由 UIKit 写入 quote 元数据） */ },
    (message) => { /* 调用服务端全端撤回 */ },
    (message) => { /* 调用服务端删除或仅保留 UIKit 的本地删除 */ },
  ),
})
```

`PteIMSDK.retryMessage(clientMsgId)` 会将失败或中断的消息恢复到本地可靠队列；`deleteLocalMessage(clientMsgId)` 只删除本机缓存，不能替代服务端撤回。红包、礼物、订单和 `PteIMMessageType.CUSTOM` 只提供统一发送格式与通用的发送状态、引用、删除、撤回、反应 UI；业务内容与服务端协议由宿主实现。

示例：

```ts
PteIMUIChat({
  // ...client / conversationId
  emojiDataSource: new PteIMUIEmojiDataSource(commonEmoji, allEmoji),
  customActions: [new PteIMUICustomAction('coupon', '优惠券', 'Coupon', $r('app.media.coupon'))],
  actionHandler: new PteIMUIActionHandler(
    () => {},
    (businessAction) => { /* 红包、礼物、订单 */ },
    (customAction) => { /* 自定义入口 */ },
  ),
})
```

# PteIMUIKit · HarmonyOS

`@ptelive/pte-im-uikit` supplies dependency-free ArkUI conversation components. Configure and log in through `@ptelive/pte-im-sdk` first, then embed `PteIMUIChat`, `PteIMUIConversationList` or the cursor-paginated `PteIMUIContactList`. The contact list supports friends, follows and groups, opens C2C conversations through Core, and routes selection through `PteIMUIContactHandler`. The host receives action callbacks for media pickers, location and business messages.

`PteIMUIChat` accepts `navigationSubtitleText` for online state or group-member count, and `reactionProvider: PteIMUIReactionProvider` for host-persisted reaction badges. It renders text, emoji, voice, image, video, location, red packet, gift, order and file messages; payment, gift and order actions remain host-owned.

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

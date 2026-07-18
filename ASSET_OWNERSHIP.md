# PteIM 视觉资源归属

设计源文件位于本机 `~/Downloads/PTE Live IMSDK设计图/切图`，它不是 SDK 工程资源目录，也不能整目录复制或打包。每一张切图只能复制到实际使用它的模块，并由该模块独立维护。

| 模块 | 可以存放 | 禁止存放 |
| --- | --- | --- |
| `PteIMSDK` | 协议、网络、SQLite、加密等 Core 运行必需的非视觉数据；当前不需要任何页面切图 | Logo、启动图、会话/联系人/聊天页图标、Demo 业务页图片 |
| `PteIMUIKit` | 会话列表、联系人列表、聊天页面共同使用的亮/暗切图；外部可通过图片配置替换 | 登录、我的、好友关系、钱包、收藏、二维码等业务页面切图 |
| `PteIMUIDemo` | 登录、启动图、测试账号、好友关系示例、我的页面等 Demo 业务页面实际使用的资源 | 不使用的整套设计切图；不得把 UIKit 的整包资源再复制一份 |
| 宿主 App | 宿主业务页面资源及通过 UIKit 配置注入的替换图片 | 不应修改或依赖 SDK Core 内部资源 |

## 各端资源目录

| 端 | `PteIMUIKit` 公共页面资源 | `PteIMUIDemo` 业务资源 |
| --- | --- | --- |
| iOS | `ios/PteIMUIKit/Sources/PteIMUIKit/Resources/` | `ios/PteIMUIDemo/PteIMUIDemo/Resources/` |
| Android | `android/pte-im-uikit/src/main/res/` | `android/pte-im-ui-demo/src/main/res/` |
| 鸿蒙 | `harmony/PteIMUIKit/src/main/resources/` | `harmony/PteIMUIDemo/entry/src/main/resources/` |
| uni-app x | `uni_modules/pte-im-uikit/components/**/static/` | `uniapp-x/PteIMUIDemo/static/` |

资源命名统一使用 `PteIMUI` 前缀。例如：`PteIMUIChatVoiceLight`、`PteIMUIChatVoiceDark`、`PteIMUIDemoLogo`。iOS 保留 `@2x`、`@3x` 后缀；其他端按各自资源密度目录管理。

## 引入切图的规则

1. 先确定页面所有者：会话、联系人、聊天归 `PteIMUIKit`；登录、启动、我的及业务样例归 `PteIMUIDemo`。
2. 只复制当前页面实际引用的亮色、暗色及必要分辨率文件，不能把 `切图` 目录整体导入。
3. 图片引用必须在同一所有者模块内解析；`PteIMSDK` 不得引用视觉资源。
4. UIKit 的默认图可被宿主配置替换，替换图由宿主自己管理，不需要复制进 SDK 或 Demo。
5. 新增或删除页面时，同时更新该页面的资源清单和此文档中的归属说明。

当前已核验：`PteIMSDK` 四端没有页面切图；iOS Demo 的 Logo 与启动图均位于 Demo 自己的资源目录中。

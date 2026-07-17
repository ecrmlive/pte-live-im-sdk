# PteIMUINavigationBar

`PteIMUINavigationBar` 是 PteIMUIKit 的统一导航层。它覆盖应用内容上方的**状态栏配色**与**页面导航栏**两个部分；业务页面不再自行放置“切换中文”、`☾`、`☀` 或 Unicode 图标。

## 一致交互

| 区域 | 行为 |
| --- | --- |
| 左侧语言 | 显示当前值：`简体中文`、`English` 或 `跟随系统`；点击弹出按 `跟随系统`、`简体中文`、`English` 排列的三项选择菜单。 |
| 中间标题 | 可选，由会话、联系人、聊天或宿主页面设置。 |
| 右侧主题 | 使用设计切图：亮色显示月亮，暗黑显示太阳；点击在亮/暗之间切换。 |
| 系统栏 | Android 同步状态栏和手势导航栏背景/图标对比度；iOS 由 UIKit 外观覆盖系统状态栏；鸿蒙与 UTS 由宿主窗口和页面背景继承同一色板。 |

语言或主题改变后调用 Core 的 `updateAppearance(themeMode:, language:)`，不重新登录，也不重新建立 IM 长连接。

## 四端入口

| 平台 | 组件 |
| --- | --- |
| iOS UIKit | `PteIMUINavigationBar` |
| Android View / Compose 宿主 | `PteIMUINavigationBar` 与 `applySystemBars(...)` |
| OpenHarmony ArkUI | `PteIMUINavigationBar` + `PteIMUINavigationHandler` |
| uni-app x UTS | `<PteIMUINavigationBar>`，事件 `language-select`、`theme-select` |

导航图标是 PteIMUIKit 资源：`PteIMUINavigationThemeLight` 与 `PteIMUINavigationThemeDark`。Core `PteIMSDK` 不包含任何页面切图。

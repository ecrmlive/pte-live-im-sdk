# HarmonyOS Demo

`PteIMUIDemo` is an independent ArkUI Stage business sample linking the sibling `PteIMSDK` and `PteIMUIKit` HARs. It demonstrates business login → short-lived UserSig → IM login, friend-list/relationship entry points, profile entry point, conversations, groups, message controls, sync/cache events, and theme/language switching. No UserSig or deployment secret is committed.

Open `harmony/PteIMUIDemo` in DevEco Studio, allow the local `@ptelive/pte-im-sdk` and `@ptelive/pte-im-uikit` HAR dependencies, then run the `entry` module on a HarmonyOS device/emulator. `EntryAbility` configures `apiDomain`、`imDomain`、`cosDomain` before the login page appears; the login page receives only the numeric SDK App ID, user ID, and a UserSig obtained from your business backend.

The media API needs a host file picker because permission and picker requirements differ by device profile. Pass its returned sandbox path to `uploadAndSendImage`, `uploadAndSendVideo`, or `uploadAndSendVoice`.

底部 Tab 的图标状态由当前页面统一驱动：当前页使用紫色图标和指示线，其他 Tab 使用独立灰色图标滤镜。Chats 的未读角标是会话状态，不依赖 Chats 是否处于选中状态；切换到联系人或我的后仍会持续显示。

系统状态栏背景始终和当前页面的顶部导航栏使用同一颜色。会话、联系人、我的属于一级页面并显示底部 Tab；聊天、设置和语言设置属于二级页面，进入后会隐藏底部 Tab。

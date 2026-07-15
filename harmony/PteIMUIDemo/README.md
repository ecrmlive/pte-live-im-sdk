# HarmonyOS Demo

`PteIMUIDemo` is an independent ArkUI Stage business sample linking the sibling `PteIMSDK` and `PteIMUIkit` HARs. It demonstrates business login → short-lived UserSig → IM login, friend-list/relationship entry points, profile entry point, conversations, groups, message controls, sync/cache events, and theme/language switching. No UserSig or deployment secret is committed.

Open `harmony/PteIMUIDemo` in DevEco Studio, allow the local `@ptelive/pte-im-sdk` and `@ptelive/pte-im-uikit` HAR dependencies, then run the `entry` module on a HarmonyOS device/emulator. Configure the production domains and a UserSig obtained from your own backend.

The media API needs a host file picker because permission and picker requirements differ by device profile. Pass its returned sandbox path to `uploadAndSendImage`, `uploadAndSendVideo`, or `uploadAndSendVoice`.

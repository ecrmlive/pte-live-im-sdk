# HarmonyOS Demo

This independent ArkUI Stage application links the sibling native HAR at `../PteLiveIM`. It has a runtime-only configuration screen, message-type controls, sync/cache events, and theme/language switching. No UserSig or deployment secret is committed.

Open `harmony/demo` in DevEco Studio, allow the local `@ptelive/im` HAR dependency, then run the `entry` module on a HarmonyOS device/emulator. Configure the production domains and a UserSig obtained from your own backend.

The media API needs a host file picker because permission and picker requirements differ by device profile. Pass its returned sandbox path to `uploadAndSendImage`, `uploadAndSendVideo`, or `uploadAndSendVoice`.

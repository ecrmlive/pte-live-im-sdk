# uni-app x UTS Demo

This is an independent uni-app x application for the UTS SDK on **H5/Web and WeChat mini-program**. It conditionally imports `web/index.uts` or `mp-weixin/index.uts`; it does not use the Android/iOS/Harmony native SDKs and it is not a TypeScript implementation.

Open `uniapp-x/PteIMUIDemo` in HBuilderX. The demo references the sibling checkout at `../../uni_modules/pte-im-sdk`, so keep the repository layout intact. For a standalone app, copy `uni_modules/pte-im-sdk` to the app root and change imports to `@/uni_modules/pte-im-sdk/...`. `PteIMUIDemo` demonstrates business login → short-lived UserSig → `PteIMSDK` → `PteIMUIkit` conversation/chat/group views, plus business friend and profile entry points.

Run against H5 or 微信小程序. Enter domains, numeric App ID/user ID, and a short-lived UserSig issued by your own backend. The default UTS setting intentionally keeps messages/outbox/cursor only in memory; add a reviewed runtime `localStorageCipher` if durable encrypted storage is required.

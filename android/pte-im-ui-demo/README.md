# Android Demo

`PteIMUIDemo` is a dependency-free native Android business-sample app for `:pte-im-sdk` and `:pte-im-uikit` (Android 12 / API 31+). It demonstrates business login → short-lived UserSig → `PteIMSDK` login, friend relations, profile entry points, and reusable `PteIMUIKit` conversation/chat/group UI. It also exercises E2EE connection events, COS media upload, local cache/sync, and theme/language callbacks.

```bash
cd android
./gradlew :demo:installDebug
```

Enter the three deployed domains, a numeric SDK App ID/user ID, and a short-lived UserSig issued by your own backend. The app does not store these values and contains no live credentials.

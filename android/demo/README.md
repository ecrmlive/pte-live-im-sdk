# Android Demo

This is a dependency-free native Android sample app for `:im-sdk` (Android 12 / API 31+). It renders a simple chat-control UI and demonstrates runtime connection configuration, E2EE connection events, all message categories, direct COS media upload, local cache/sync, and theme/language callbacks.

```bash
cd android
./gradlew :demo:installDebug
```

Enter the three deployed domains, a numeric SDK App ID/user ID, and a short-lived UserSig issued by your own backend. The app does not store these values and contains no live credentials.

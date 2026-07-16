# PteIMUIDemo · iOS

`PteIMUIDemo.xcworkspace` is the iOS entry point for this native UIKit application. It links the local `../PteIMSDK` and `../PteIMUIKit` Swift packages and demonstrates the application flow: business login → backend-issued short-lived `userId`/`userSig` → PteIMSDK login → PteIMUIKit conversations, friend chat, group chat and profile entry point.

Its Logo, Launch Screen and business-example images belong in `PteIMUIDemo/Resources/`. It must not read visual assets from `PteIMSDK`; shared conversation, contact and chat images belong to `PteIMUIKit`.

Open `PteIMUIDemo.xcworkspace` in Xcode and run on an iOS 16.0+ simulator or device. The sample never writes domains, UserSig or COS credentials to disk. Replace the form-based credential example with your authenticated business API.

For deterministic UI review, the Debug build provides an offline `本地 UI 预览` route. It creates `PteIMSDK.preview(...)`, which uses only an in-memory cache and temporary encryption key: no UserSig is transmitted, and no production Core Data or Keychain record is read or written. The preview contains conversation, contact and chat fixtures; it is not included as a production login path.

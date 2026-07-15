# PteIMUIDemo · iOS

`PteIMUIDemo.xcworkspace` is the iOS entry point for this native UIKit application. It links the local `../PteIMSDK` and `../PteIMUIkit` Swift packages and demonstrates the application flow: business login → backend-issued short-lived `userId`/`userSig` → PteIMSDK login → PteIMUIkit conversations, friend chat, group chat and profile entry point.

Open `PteIMUIDemo.xcworkspace` in Xcode and run on an iOS 16.0+ simulator or device. The sample never writes domains, UserSig or COS credentials to disk. Replace the form-based credential example with your authenticated business API.

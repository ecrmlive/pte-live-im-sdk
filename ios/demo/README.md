# iOS Demo

`PteLiveIMDemo.xcodeproj` is a native **UIKit** app that links the sibling `../PteIMUIKit` package. It only performs runtime `PteIMBaseConfig` / `PteIMLoginConfig` login, then presents the reusable `PteIMUIChatViewController` from `PteIMUIKit`.

Open `PteLiveIMDemo.xcodeproj` in Xcode and run on an iOS 16.0+ simulator or device. Enter deployment domains and a UserSig issued by your authenticated backend; the demo never writes them to disk.

`project.yml` is retained so the project can be regenerated with `xcodegen generate` after changing the app structure. UIKit source filenames all begin with `PteIMUI`.

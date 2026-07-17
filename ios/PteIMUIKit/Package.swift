// swift-tools-version: 6.0
import PackageDescription

let package = Package(
  name: "PteIMUIKit",
  platforms: [.iOS(.v16)],
  products: [.library(name: "PteIMUIKit", targets: ["PteIMUIKit"])],
  dependencies: [.package(path: "../PteIMSDK")],
  targets: [.target(
    name: "PteIMUIKit",
    dependencies: [.product(name: "PteIMSDK", package: "PteIMSDK")],
    path: "Sources/PteIMUIKit",
    resources: [.process("Resources")]
  )]
)

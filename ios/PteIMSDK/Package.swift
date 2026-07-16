// swift-tools-version: 6.0
import PackageDescription

let package = Package(
  name: "PteIMSDK",
  platforms: [.iOS(.v16)],
  products: [.library(name: "PteIMSDK", targets: ["PteIMSDK"])],
  targets: [.target(name: "PteIMSDK", path: "Sources/PteIMSDK")]
)

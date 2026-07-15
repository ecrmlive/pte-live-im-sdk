// swift-tools-version: 5.9
import PackageDescription

let package = Package(
  name: "PteIMSDK",
  platforms: [.iOS(.v16)],
  products: [.library(name: "PteIMSDK", targets: ["PteIMSDK"])],
  targets: [.target(name: "PteIMSDK", path: "Sources/PteIMSDK")]
)

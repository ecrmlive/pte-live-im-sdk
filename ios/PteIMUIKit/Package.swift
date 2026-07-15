// swift-tools-version: 5.9
import PackageDescription

let package = Package(
  name: "PteIMUIkit",
  platforms: [.iOS(.v16)],
  products: [.library(name: "PteIMUIkit", targets: ["PteIMUIkit"])],
  dependencies: [.package(path: "../PteIMSDK")],
  targets: [.target(
    name: "PteIMUIkit",
    dependencies: [.product(name: "PteIMSDK", package: "PteIMSDK")],
    path: "Sources/PteIMUIkit"
  )]
)

// swift-tools-version: 5.9
import PackageDescription

let package = Package(
  name: "PteIMUIKit",
  platforms: [.iOS(.v16)],
  products: [.library(name: "PteIMUIKit", targets: ["PteIMUIKit"])],
  dependencies: [.package(path: "../PteLiveIM")],
  targets: [.target(
    name: "PteIMUIKit",
    dependencies: [.product(name: "PteLiveIM", package: "PteLiveIM")],
    path: "Sources/PteIMUIKit"
  )]
)

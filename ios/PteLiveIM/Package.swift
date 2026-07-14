// swift-tools-version: 5.9
import PackageDescription

let package = Package(
  name: "PteLiveIM",
  platforms: [.iOS(.v15)],
  products: [.library(name: "PteLiveIM", targets: ["PteLiveIM"])],
  targets: [.target(name: "PteLiveIM", path: "Sources/PteLiveIM")]
)

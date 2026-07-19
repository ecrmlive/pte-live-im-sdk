import UIKit

/** Demo-owned artwork (Tab、我的、设置) is intentionally outside PteIMUIKit. */
enum PteIMUIDemoAssets {
  static func image(named name: String, traitCollection: UITraitCollection? = nil) -> UIImage? {
    guard let url = Bundle.main.url(
      forResource: name,
      withExtension: "png",
      subdirectory: "DemoBusinessAssets"
    ) else { return nil }
    return UIImage(contentsOfFile: url.path)
  }
}

import UIKit

public enum PteIMTheme { case light, dark }

public func systemTheme(for traits: UITraitCollection) -> PteIMTheme {
  traits.userInterfaceStyle == .dark ? .dark : .light
}

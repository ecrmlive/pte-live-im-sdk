import UIKit

/** Resolves the platform-neutral Core appearance value from UIKit traits. */
public func pteIMSystemTheme(for traits: UITraitCollection) -> PteIMTheme {
  traits.userInterfaceStyle == .dark ? .dark : .light
}

/**
 A fully independent colour set for one appearance. Hosts may customise every
 visible PteIMUI component without deriving dark mode from light mode.
 */
@MainActor public struct PteIMUIThemePalette {
  public var backgroundColor: UIColor
  public var surfaceColor: UIColor
  public var composerColor: UIColor
  public var incomingBubbleColor: UIColor
  public var outgoingGradientStartColor: UIColor
  public var outgoingGradientEndColor: UIColor
  public var primaryTextColor: UIColor
  public var secondaryTextColor: UIColor
  public var incomingTextColor: UIColor
  public var outgoingTextColor: UIColor
  public var iconColor: UIColor
  public var dividerColor: UIColor
  public var panelColor: UIColor
  public var panelItemColor: UIColor

  public init(
    backgroundColor: UIColor,
    surfaceColor: UIColor,
    composerColor: UIColor,
    incomingBubbleColor: UIColor,
    outgoingGradientStartColor: UIColor,
    outgoingGradientEndColor: UIColor,
    primaryTextColor: UIColor,
    secondaryTextColor: UIColor,
    incomingTextColor: UIColor,
    outgoingTextColor: UIColor,
    iconColor: UIColor,
    dividerColor: UIColor,
    panelColor: UIColor,
    panelItemColor: UIColor
  ) {
    self.backgroundColor = backgroundColor
    self.surfaceColor = surfaceColor
    self.composerColor = composerColor
    self.incomingBubbleColor = incomingBubbleColor
    self.outgoingGradientStartColor = outgoingGradientStartColor
    self.outgoingGradientEndColor = outgoingGradientEndColor
    self.primaryTextColor = primaryTextColor
    self.secondaryTextColor = secondaryTextColor
    self.incomingTextColor = incomingTextColor
    self.outgoingTextColor = outgoingTextColor
    self.iconColor = iconColor
    self.dividerColor = dividerColor
    self.panelColor = panelColor
    self.panelItemColor = panelItemColor
  }
}

/**
 PteIMUIKit appearance tokens. `light` and `dark` are explicit palettes, so a
 host can independently brand the composer, emoji panel and more panel.
 */
@MainActor public struct PteIMUITheme {
  public var light: PteIMUIThemePalette
  public var dark: PteIMUIThemePalette

  public init(light: PteIMUIThemePalette = .blueVioletLight, dark: PteIMUIThemePalette = .blueVioletDark) {
    self.light = light
    self.dark = dark
  }

  public func palette(for traits: UITraitCollection) -> PteIMUIThemePalette {
    traits.userInterfaceStyle == .dark ? dark : light
  }

  public static let `default` = PteIMUITheme()
}

public extension PteIMUIThemePalette {
  static let blueVioletLight = PteIMUIThemePalette(
    backgroundColor: UIColor(red: 0.94, green: 0.94, blue: 1.00, alpha: 1),
    surfaceColor: .white,
    composerColor: .white,
    incomingBubbleColor: UIColor(red: 1.00, green: 1.00, blue: 1.00, alpha: 1),
    outgoingGradientStartColor: UIColor(red: 0.48, green: 0.20, blue: 0.95, alpha: 1),
    outgoingGradientEndColor: UIColor(red: 0.57, green: 0.32, blue: 0.98, alpha: 1),
    primaryTextColor: UIColor(red: 0.10, green: 0.10, blue: 0.20, alpha: 1),
    secondaryTextColor: UIColor(red: 0.40, green: 0.43, blue: 0.52, alpha: 1),
    incomingTextColor: UIColor(red: 0.11, green: 0.13, blue: 0.22, alpha: 1),
    outgoingTextColor: .white,
    iconColor: UIColor(red: 0.27, green: 0.30, blue: 0.42, alpha: 1),
    dividerColor: UIColor(red: 0.88, green: 0.87, blue: 0.98, alpha: 1),
    panelColor: UIColor(red: 1.00, green: 1.00, blue: 1.00, alpha: 1),
    panelItemColor: .white
  )

  static let blueVioletDark = PteIMUIThemePalette(
    backgroundColor: UIColor(red: 0.035, green: 0.035, blue: 0.12, alpha: 1),
    surfaceColor: UIColor(red: 0.075, green: 0.075, blue: 0.20, alpha: 1),
    composerColor: UIColor(red: 0.06, green: 0.06, blue: 0.16, alpha: 1),
    incomingBubbleColor: UIColor(red: 0.08, green: 0.08, blue: 0.20, alpha: 1),
    outgoingGradientStartColor: UIColor(red: 0.52, green: 0.30, blue: 0.98, alpha: 1),
    outgoingGradientEndColor: UIColor(red: 0.61, green: 0.39, blue: 1.00, alpha: 1),
    primaryTextColor: UIColor(red: 0.94, green: 0.95, blue: 1.00, alpha: 1),
    secondaryTextColor: UIColor(red: 0.63, green: 0.67, blue: 0.79, alpha: 1),
    incomingTextColor: UIColor(red: 0.94, green: 0.95, blue: 1.00, alpha: 1),
    outgoingTextColor: .white,
    iconColor: UIColor(red: 0.79, green: 0.82, blue: 0.95, alpha: 1),
    dividerColor: UIColor(red: 0.16, green: 0.14, blue: 0.32, alpha: 1),
    panelColor: UIColor(red: 0.06, green: 0.06, blue: 0.16, alpha: 1),
    panelItemColor: UIColor(red: 0.11, green: 0.10, blue: 0.25, alpha: 1)
  )
}

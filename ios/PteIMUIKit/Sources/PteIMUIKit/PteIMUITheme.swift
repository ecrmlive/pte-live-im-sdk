import UIKit

/**
 A fully independent colour set for one appearance. Hosts may customise every
 visible PteIMUI component without deriving dark mode from light mode.
 */
public struct PteIMUIThemePalette {
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
 PteIMUIkit appearance tokens. `light` and `dark` are explicit palettes, so a
 host can independently brand the composer, emoji panel and more panel.
 */
public struct PteIMUITheme {
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
    backgroundColor: UIColor(red: 0.97, green: 0.98, blue: 1.00, alpha: 1),
    surfaceColor: .white,
    composerColor: .white,
    incomingBubbleColor: UIColor(red: 0.93, green: 0.95, blue: 0.99, alpha: 1),
    outgoingGradientStartColor: UIColor(red: 0.20, green: 0.37, blue: 0.96, alpha: 1),
    outgoingGradientEndColor: UIColor(red: 0.49, green: 0.23, blue: 0.96, alpha: 1),
    primaryTextColor: UIColor(red: 0.09, green: 0.11, blue: 0.18, alpha: 1),
    secondaryTextColor: UIColor(red: 0.40, green: 0.43, blue: 0.52, alpha: 1),
    incomingTextColor: UIColor(red: 0.11, green: 0.13, blue: 0.22, alpha: 1),
    outgoingTextColor: .white,
    iconColor: UIColor(red: 0.27, green: 0.30, blue: 0.42, alpha: 1),
    dividerColor: UIColor(red: 0.87, green: 0.89, blue: 0.95, alpha: 1),
    panelColor: UIColor(red: 0.95, green: 0.96, blue: 1.00, alpha: 1),
    panelItemColor: .white
  )

  static let blueVioletDark = PteIMUIThemePalette(
    backgroundColor: UIColor(red: 0.055, green: 0.065, blue: 0.10, alpha: 1),
    surfaceColor: UIColor(red: 0.08, green: 0.095, blue: 0.15, alpha: 1),
    composerColor: UIColor(red: 0.095, green: 0.11, blue: 0.18, alpha: 1),
    incomingBubbleColor: UIColor(red: 0.15, green: 0.17, blue: 0.25, alpha: 1),
    outgoingGradientStartColor: UIColor(red: 0.25, green: 0.39, blue: 1.00, alpha: 1),
    outgoingGradientEndColor: UIColor(red: 0.54, green: 0.29, blue: 1.00, alpha: 1),
    primaryTextColor: UIColor(red: 0.94, green: 0.95, blue: 1.00, alpha: 1),
    secondaryTextColor: UIColor(red: 0.63, green: 0.67, blue: 0.79, alpha: 1),
    incomingTextColor: UIColor(red: 0.94, green: 0.95, blue: 1.00, alpha: 1),
    outgoingTextColor: .white,
    iconColor: UIColor(red: 0.79, green: 0.82, blue: 0.95, alpha: 1),
    dividerColor: UIColor(red: 0.18, green: 0.20, blue: 0.30, alpha: 1),
    panelColor: UIColor(red: 0.10, green: 0.12, blue: 0.19, alpha: 1),
    panelItemColor: UIColor(red: 0.15, green: 0.17, blue: 0.26, alpha: 1)
  )
}

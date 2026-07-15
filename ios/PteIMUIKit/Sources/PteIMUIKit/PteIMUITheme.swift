import UIKit

/** UIKit appearance tokens. Dynamic system colors keep `.system` mode in sync with iOS. */
public struct PteIMUITheme {
  public var backgroundColor: UIColor
  public var surfaceColor: UIColor
  public var incomingBubbleColor: UIColor
  public var outgoingBubbleColor: UIColor
  public var primaryTextColor: UIColor
  public var secondaryTextColor: UIColor
  public var accentColor: UIColor

  public init(
    backgroundColor: UIColor = .systemBackground,
    surfaceColor: UIColor = .secondarySystemBackground,
    incomingBubbleColor: UIColor = .secondarySystemBackground,
    outgoingBubbleColor: UIColor = UIColor { traits in traits.userInterfaceStyle == .dark ? UIColor.systemBlue.withAlphaComponent(0.55) : UIColor.systemBlue.withAlphaComponent(0.16) },
    primaryTextColor: UIColor = .label,
    secondaryTextColor: UIColor = .secondaryLabel,
    accentColor: UIColor = .systemBlue
  ) {
    self.backgroundColor = backgroundColor
    self.surfaceColor = surfaceColor
    self.incomingBubbleColor = incomingBubbleColor
    self.outgoingBubbleColor = outgoingBubbleColor
    self.primaryTextColor = primaryTextColor
    self.secondaryTextColor = secondaryTextColor
    self.accentColor = accentColor
  }

  public static let `default` = PteIMUITheme()
}

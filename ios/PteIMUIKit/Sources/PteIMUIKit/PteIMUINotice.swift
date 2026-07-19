import UIKit

/** Presentation location for a transient PteIMUIKit notice. */
public enum PteIMUINoticePosition: Sendable {
  /// Floats above the current view controller's bottom safe area.
  case bottom
  /// Floats in the visual centre of the current view controller.
  case center
}

/** Semantic appearance for a transient PteIMUIKit notice. */
public enum PteIMUINoticeKind: Sendable {
  case success
  case error
  case warning
  case info
}

/**
 A UIKit-native, non-blocking success/error notice.

 The notice is intentionally owned by PteIMUIKit rather than an application
 screen: hosts can use the same presentation for login, list and chat flows.
 Calling `show` again on the same view replaces the existing notice.
 */
@MainActor public enum PteIMUINotice {
  public static func showSuccess(
    _ title: String,
    detail: String? = nil,
    position: PteIMUINoticePosition = .bottom,
    duration: TimeInterval = 2.6,
    in viewController: UIViewController
  ) {
    show(title, detail: detail, kind: .success, position: position, duration: duration, in: viewController.view)
  }

  public static func showError(
    _ title: String,
    detail: String? = nil,
    position: PteIMUINoticePosition = .bottom,
    duration: TimeInterval = 3.6,
    in viewController: UIViewController
  ) {
    show(title, detail: detail, kind: .error, position: position, duration: duration, in: viewController.view)
  }

  public static func showInfo(
    _ title: String,
    detail: String? = nil,
    position: PteIMUINoticePosition = .bottom,
    duration: TimeInterval = 2.8,
    in viewController: UIViewController
  ) {
    show(title, detail: detail, kind: .info, position: position, duration: duration, in: viewController.view)
  }

  public static func showWarning(
    _ title: String,
    detail: String? = nil,
    position: PteIMUINoticePosition = .bottom,
    duration: TimeInterval = 3.0,
    in viewController: UIViewController
  ) {
    show(title, detail: detail, kind: .warning, position: position, duration: duration, in: viewController.view)
  }

  public static func show(
    _ title: String,
    detail: String? = nil,
    kind: PteIMUINoticeKind = .info,
    position: PteIMUINoticePosition = .bottom,
    duration: TimeInterval = 2.8,
    in view: UIView
  ) {
    view.subviews.compactMap { $0 as? PteIMUINoticeView }.forEach { $0.dismiss(animated: false) }
    let notice = PteIMUINoticeView(title: title, detail: detail, kind: kind, position: position, palette: palette(for: view))
    notice.translatesAutoresizingMaskIntoConstraints = false
    view.addSubview(notice)
    NSLayoutConstraint.activate([
      notice.leadingAnchor.constraint(equalTo: view.leadingAnchor),
      notice.trailingAnchor.constraint(equalTo: view.trailingAnchor),
      notice.topAnchor.constraint(equalTo: view.topAnchor),
      notice.bottomAnchor.constraint(equalTo: view.bottomAnchor)
    ])
    view.layoutIfNeeded()
    notice.present(duration: duration)
  }

  public static func hide(in viewController: UIViewController, animated: Bool = true) {
    hide(in: viewController.view, animated: animated)
  }

  public static func hide(in view: UIView, animated: Bool = true) {
    view.subviews.compactMap { $0 as? PteIMUINoticeView }.forEach { $0.dismiss(animated: animated) }
  }

  private static func palette(for view: UIView) -> PteIMUIThemePalette {
    view.traitCollection.userInterfaceStyle == .dark ? .blueVioletDark : .blueVioletLight
  }
}

@MainActor private final class PteIMUINoticeView: UIView {
  private let card = UIView()
  private let iconBackground = UIView()
  private let iconView = UIImageView()
  private let titleLabel = UILabel()
  private let detailLabel = UILabel()
  private let position: PteIMUINoticePosition
  private var dismissWorkItem: DispatchWorkItem?

  init(title: String, detail: String?, kind: PteIMUINoticeKind, position: PteIMUINoticePosition, palette: PteIMUIThemePalette) {
    self.position = position
    super.init(frame: .zero)
    isUserInteractionEnabled = false
    backgroundColor = .clear
    accessibilityViewIsModal = false

    let dark = palette.backgroundColor.isDarkColor
    let accent: UIColor
    let symbolName: String
    switch kind {
    case .success:
      accent = UIColor(red: 0.10, green: 0.76, blue: 0.45, alpha: 1)
      symbolName = "checkmark"
    case .error:
      accent = UIColor(red: 0.96, green: 0.27, blue: 0.31, alpha: 1)
      symbolName = "exclamationmark"
    case .warning:
      accent = UIColor(red: 0.90, green: 0.57, blue: 0.09, alpha: 1)
      symbolName = "exclamationmark"
    case .info:
      accent = UIColor(red: 0.47, green: 0.28, blue: 0.95, alpha: 1)
      symbolName = "info"
    }

    card.backgroundColor = dark ? UIColor(red: 0.11, green: 0.11, blue: 0.25, alpha: 0.98) : UIColor.white.withAlphaComponent(0.98)
    card.layer.cornerRadius = 16
    card.layer.cornerCurve = .continuous
    card.layer.borderWidth = 1
    card.layer.borderColor = (dark ? UIColor.white.withAlphaComponent(0.12) : UIColor.black.withAlphaComponent(0.07)).cgColor
    card.layer.shadowColor = UIColor.black.cgColor
    card.layer.shadowOpacity = dark ? 0.30 : 0.15
    card.layer.shadowRadius = 16
    card.layer.shadowOffset = CGSize(width: 0, height: 8)
    card.translatesAutoresizingMaskIntoConstraints = false
    addSubview(card)

    iconBackground.backgroundColor = accent
    iconBackground.layer.cornerRadius = 16
    iconBackground.layer.cornerCurve = .continuous
    iconBackground.translatesAutoresizingMaskIntoConstraints = false
    iconView.image = UIImage(systemName: symbolName, withConfiguration: UIImage.SymbolConfiguration(pointSize: 15, weight: .bold))
    iconView.tintColor = .white
    iconView.contentMode = .scaleAspectFit
    iconView.translatesAutoresizingMaskIntoConstraints = false
    iconBackground.addSubview(iconView)

    titleLabel.text = title
    titleLabel.textColor = palette.primaryTextColor
    titleLabel.font = .systemFont(ofSize: 15, weight: .semibold)
    titleLabel.numberOfLines = 2
    titleLabel.setContentCompressionResistancePriority(.required, for: .vertical)
    detailLabel.text = detail
    detailLabel.textColor = palette.secondaryTextColor
    detailLabel.font = .systemFont(ofSize: 13, weight: .regular)
    detailLabel.numberOfLines = 2
    detailLabel.isHidden = detail?.isEmpty != false

    let labels = UIStackView(arrangedSubviews: [titleLabel, detailLabel])
    labels.axis = .vertical
    labels.spacing = 3
    labels.translatesAutoresizingMaskIntoConstraints = false
    card.addSubview(iconBackground)
    card.addSubview(labels)
    NSLayoutConstraint.activate([
      iconBackground.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 14),
      iconBackground.centerYAnchor.constraint(equalTo: card.centerYAnchor),
      iconBackground.widthAnchor.constraint(equalToConstant: 32),
      iconBackground.heightAnchor.constraint(equalToConstant: 32),
      iconView.centerXAnchor.constraint(equalTo: iconBackground.centerXAnchor),
      iconView.centerYAnchor.constraint(equalTo: iconBackground.centerYAnchor),
      labels.leadingAnchor.constraint(equalTo: iconBackground.trailingAnchor, constant: 10),
      labels.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -14),
      labels.topAnchor.constraint(equalTo: card.topAnchor, constant: 12),
      labels.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -12)
    ])

    let maxWidth: CGFloat = position == .center ? 320 : 420
    NSLayoutConstraint.activate([
      card.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 20),
      card.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -20),
      card.centerXAnchor.constraint(equalTo: centerXAnchor),
      card.widthAnchor.constraint(lessThanOrEqualToConstant: maxWidth)
    ])
    switch position {
    case .bottom:
      card.bottomAnchor.constraint(equalTo: safeAreaLayoutGuide.bottomAnchor, constant: -16).isActive = true
    case .center:
      card.centerYAnchor.constraint(equalTo: centerYAnchor, constant: -18).isActive = true
    }
    isAccessibilityElement = true
    accessibilityLabel = [title, detail].compactMap { $0 }.joined(separator: "，")
    accessibilityTraits = kind == .error ? [.staticText, .updatesFrequently] : [.staticText]
  }

  required init?(coder: NSCoder) { nil }

  func present(duration: TimeInterval) {
    card.alpha = 0
    card.transform = CGAffineTransform(translationX: 0, y: position == .bottom ? 18 : 8).scaledBy(x: 0.98, y: 0.98)
    let notification: UINotificationFeedbackGenerator = .init()
    notification.prepare()
    UIAccessibility.post(notification: .announcement, argument: accessibilityLabel)
    UIView.animate(withDuration: 0.24, delay: 0, options: [.curveEaseOut, .beginFromCurrentState]) { [weak self] in
      self?.card.alpha = 1
      self?.card.transform = .identity
    }
    dismissWorkItem?.cancel()
    let workItem = DispatchWorkItem { [weak self] in self?.dismiss(animated: true) }
    dismissWorkItem = workItem
    DispatchQueue.main.asyncAfter(deadline: .now() + max(0.5, duration), execute: workItem)
  }

  func dismiss(animated: Bool) {
    dismissWorkItem?.cancel()
    let finish = { [weak self] in self?.removeFromSuperview() }
    guard animated else { finish(); return }
    UIView.animate(withDuration: 0.18, delay: 0, options: [.curveEaseIn, .beginFromCurrentState]) { [weak self] in
      self?.card.alpha = 0
      self?.card.transform = CGAffineTransform(translationX: 0, y: self?.position == .bottom ? 12 : -6)
    } completion: { _ in finish() }
  }
}

private extension UIColor {
  var isDarkColor: Bool {
    var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
    guard getRed(&red, green: &green, blue: &blue, alpha: &alpha) else { return false }
    return (red * 0.299) + (green * 0.587) + (blue * 0.114) < 0.45
  }
}

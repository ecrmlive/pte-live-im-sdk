import UIKit
import PteIMSDK

/** Actions shown below a long-pressed chat message. */
public enum PteIMUIMessageAction: Sendable { case quote, copy, revoke, delete }

/**
 A message-anchored reaction/action tray. It deliberately sits above the
 pressed cell (falling back below only when the message is at the very top of
 the visible timeline), matching the supplied IM interaction artwork.
 */
@MainActor final class PteIMUIMessageActionMenu: UIView, UIGestureRecognizerDelegate {
  private let container = UIStackView()
  private let reactionTray = UIStackView()
  private let actionTray = UIStackView()
  private weak var panel: UIView?
  private var onAction: ((PteIMUIMessageAction) -> Void)?
  private var onReaction: ((String) -> Void)?
  private var onAddReaction: (() -> Void)?

  static func present(
    over host: UIView,
    anchor: CGRect,
    palette: PteIMUIThemePalette,
    language: PteIMLanguage,
    actions: [PteIMUIMessageAction],
    onReaction: @escaping (String) -> Void,
    onAddReaction: @escaping () -> Void,
    onAction: @escaping (PteIMUIMessageAction) -> Void
  ) {
    host.subviews.filter { $0 is PteIMUIMessageActionMenu }.forEach { $0.removeFromSuperview() }
    let menu = PteIMUIMessageActionMenu(
      palette: palette,
      language: language,
      actions: actions,
      onReaction: onReaction,
      onAddReaction: onAddReaction,
      onAction: onAction
    )
    menu.translatesAutoresizingMaskIntoConstraints = false
    host.addSubview(menu)
    NSLayoutConstraint.activate([
      menu.leadingAnchor.constraint(equalTo: host.leadingAnchor),
      menu.trailingAnchor.constraint(equalTo: host.trailingAnchor),
      menu.topAnchor.constraint(equalTo: host.topAnchor),
      menu.bottomAnchor.constraint(equalTo: host.bottomAnchor)
    ])

    let panelWidth = min(max(288, host.bounds.width - 32), 580)
    let halfWidth = panelWidth / 2
    let centerX = min(max(anchor.midX, 16 + halfWidth), host.bounds.width - 16 - halfWidth)
    let hasRoomAbove = anchor.minY - host.safeAreaInsets.top >= 146
    let vertical: NSLayoutConstraint
    if hasRoomAbove {
      vertical = menu.container.bottomAnchor.constraint(equalTo: menu.topAnchor, constant: anchor.minY - 8)
    } else {
      vertical = menu.container.topAnchor.constraint(equalTo: menu.topAnchor, constant: anchor.maxY + 8)
    }
    NSLayoutConstraint.activate([
      menu.container.widthAnchor.constraint(equalToConstant: panelWidth),
      menu.container.centerXAnchor.constraint(equalTo: menu.leadingAnchor, constant: centerX),
      vertical
    ])
  }

  init(
    palette: PteIMUIThemePalette,
    language: PteIMLanguage,
    actions: [PteIMUIMessageAction],
    onReaction: @escaping (String) -> Void,
    onAddReaction: @escaping () -> Void,
    onAction: @escaping (PteIMUIMessageAction) -> Void
  ) {
    self.onAction = onAction
    self.onReaction = onReaction
    self.onAddReaction = onAddReaction
    super.init(frame: .zero)
    backgroundColor = .clear
    let tap = UITapGestureRecognizer(target: self, action: #selector(dismiss))
    tap.delegate = self
    addGestureRecognizer(tap)

    container.axis = .vertical
    container.alignment = .leading
    container.spacing = 10
    container.translatesAutoresizingMaskIntoConstraints = false
    addSubview(container)
    panel = container

    reactionTray.axis = .horizontal
    reactionTray.alignment = .center
    reactionTray.distribution = .fill
    reactionTray.spacing = 5
    reactionTray.backgroundColor = palette.surfaceColor
    reactionTray.layer.cornerRadius = 23
    reactionTray.layer.borderWidth = 1
    reactionTray.layer.borderColor = palette.dividerColor.cgColor
    reactionTray.clipsToBounds = true
    reactionTray.isLayoutMarginsRelativeArrangement = true
    reactionTray.directionalLayoutMargins = .init(top: 4, leading: 12, bottom: 4, trailing: 8)
    reactionTray.heightAnchor.constraint(equalToConstant: 54).isActive = true

    ["👍", "❤️", "😂", "😮", "😭", "🙏"].forEach { emoji in
      let button = UIButton(type: .system)
      button.setTitle(emoji, for: .normal)
      button.titleLabel?.font = .systemFont(ofSize: 25)
      button.widthAnchor.constraint(equalToConstant: 42).isActive = true
      button.heightAnchor.constraint(equalToConstant: 42).isActive = true
      button.addAction(UIAction { [weak self] _ in self?.selectReaction(emoji) }, for: .touchUpInside)
      reactionTray.addArrangedSubview(button)
    }
    let separator = UIView()
    separator.backgroundColor = palette.dividerColor
    separator.translatesAutoresizingMaskIntoConstraints = false
    NSLayoutConstraint.activate([separator.widthAnchor.constraint(equalToConstant: 1), separator.heightAnchor.constraint(equalToConstant: 28)])
    reactionTray.addArrangedSubview(separator)
    let add = UIButton(type: .system)
    add.setImage(UIImage(systemName: "plus", withConfiguration: UIImage.SymbolConfiguration(pointSize: 21, weight: .semibold)), for: .normal)
    add.tintColor = palette.primaryTextColor
    add.widthAnchor.constraint(equalToConstant: 40).isActive = true
    add.heightAnchor.constraint(equalToConstant: 40).isActive = true
    add.addAction(UIAction { [weak self] _ in self?.selectAddReaction() }, for: .touchUpInside)
    reactionTray.addArrangedSubview(add)

    actionTray.axis = .horizontal
    actionTray.alignment = .fill
    actionTray.distribution = .fillEqually
    actionTray.backgroundColor = palette.surfaceColor
    actionTray.layer.cornerRadius = 16
    actionTray.layer.borderWidth = 1
    actionTray.layer.borderColor = palette.dividerColor.cgColor
    actionTray.clipsToBounds = true
    actionTray.heightAnchor.constraint(equalToConstant: 52).isActive = true
    let allEntries: [(PteIMUIMessageAction, String, String, Bool)] = [
      (.quote, "arrowshape.turn.up.left", PteIMUILocalization.value("引用", "Quote", language: language), false),
      (.copy, "doc.on.doc", PteIMUILocalization.value("复制", "Copy", language: language), false),
      (.revoke, "arrow.uturn.backward", PteIMUILocalization.value("撤回", "Revoke", language: language), false),
      (.delete, "trash", PteIMUILocalization.value("删除", "Delete", language: language), true)
    ]
    let entries = allEntries.filter { actions.contains($0.0) }
    // Do not stretch a single action (for example, Quote on a non-text
    // incoming message) across the entire reaction tray. Keep it compact and
    // left-aligned; broader menus grow by the number of available actions.
    let actionWidth: CGFloat = entries.count == 1 ? 112 : 82
    actionTray.widthAnchor.constraint(equalToConstant: actionWidth * CGFloat(entries.count)).isActive = true
    for (_, entry) in entries.enumerated() {
      let (action, imageName, title, destructive) = entry
      let button = UIButton(type: .system)
      var config = UIButton.Configuration.plain()
      config.image = UIImage(systemName: imageName, withConfiguration: UIImage.SymbolConfiguration(pointSize: 16, weight: .medium))
      config.title = title
      config.imagePadding = 6
      config.contentInsets = .zero
      config.baseForegroundColor = destructive ? .systemRed : palette.primaryTextColor
      button.configuration = config
      button.titleLabel?.font = .systemFont(ofSize: 13, weight: .semibold)
      button.addAction(UIAction { [weak self] _ in self?.select(action) }, for: .touchUpInside)
      actionTray.addArrangedSubview(button)
      // The action labels are deliberately evenly distributed; the rounded
      // tray stays compact on iPhone widths without squeezing any title.
    }
    container.addArrangedSubview(reactionTray)
    reactionTray.widthAnchor.constraint(equalTo: container.widthAnchor).isActive = true
    container.addArrangedSubview(actionTray)
  }

  required init?(coder: NSCoder) { nil }

  func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
    guard let panel else { return true }
    return !touch.view!.isDescendant(of: panel)
  }

  private func selectReaction(_ emoji: String) { dismiss(); onReaction?(emoji) }
  private func selectAddReaction() { dismiss(); onAddReaction?() }
  private func select(_ action: PteIMUIMessageAction) { dismiss(); onAction?(action) }
  @objc private func dismiss() { removeFromSuperview() }
}

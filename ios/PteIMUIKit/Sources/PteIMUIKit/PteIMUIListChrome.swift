import UIKit

/**
 Shared top chrome for the UIKit conversation and contact surfaces. It keeps
 the product header, search field and quick actions out of application code
 while leaving navigation and business actions overrideable by the host.
 */
@MainActor open class PteIMUIListChrome: UIView {
  public var onSearchChanged: ((String) -> Void)?
  public var onAddTapped: (() -> Void)?
  /// The header's fixed height.  The visible navigation row is always 44pt;
  /// quick actions extend the body below it without changing that row.
  public let preferredHeight: CGFloat

  private let mark = UIImageView()
  private let topSurface = UIView()
  private let titleLabel = UILabel()
  private let addButton = UIButton(type: .system)
  private let searchContainer = UIView()
  private let searchIcon = UIImageView()
  private let searchField = UITextField()
  private let quickActions = UIStackView()
  private var quickActionButtons = [(button: UIButton, icon: PteIMUIIconKey)]()

  public init(title: String, showsQuickActions: Bool = false) {
    preferredHeight = showsQuickActions ? 164 : 110
    super.init(frame: .zero)
    // A tableHeaderView is frame-driven by UITableView. Its internal content
    // uses constraints, but the header itself must retain autoresizing masks.
    translatesAutoresizingMaskIntoConstraints = true
    setup(title: title, showsQuickActions: showsQuickActions)
  }
  required public init?(coder: NSCoder) { nil }

  public func apply(palette: PteIMUIThemePalette, title: String, language: PteIMLanguage, icons: PteIMUIIconProvider = PteIMUISystemIconProvider()) {
    backgroundColor = palette.backgroundColor
    topSurface.backgroundColor = palette.surfaceColor
    mark.image = icons.image(for: .brand, traitCollection: traitCollection) ?? UIImage(named: "PteIMUIBrandMark", in: .module, compatibleWith: traitCollection)
    titleLabel.text = title
    titleLabel.textColor = palette.primaryTextColor
    addButton.setImage(icons.image(for: .add, traitCollection: traitCollection), for: .normal)
    searchIcon.image = icons.image(for: .search, traitCollection: traitCollection) ?? UIImage(named: "PteIMUISearchIcon", in: .module, compatibleWith: traitCollection)
    [addButton, searchIcon].forEach { $0.tintColor = palette.iconColor }
    var red: CGFloat = 1
    palette.backgroundColor.getRed(&red, green: nil, blue: nil, alpha: nil)
    let dark = red < 0.5
    if dark {
      searchContainer.backgroundColor = UIColor(red: 0.12, green: 0.115, blue: 0.30, alpha: 1)
      searchContainer.layer.borderWidth = 0
      searchContainer.layer.borderColor = nil
    } else {
      // Keep the search control distinct from the page canvas in light mode.
      // The previous background reused the canvas colour and made the field
      // disappear visually in both Chats and Contacts.
      searchContainer.backgroundColor = UIColor(red: 0.90, green: 0.89, blue: 0.99, alpha: 1)
      searchContainer.layer.borderWidth = 1 / UIScreen.main.scale
      searchContainer.layer.borderColor = UIColor(red: 0.84, green: 0.82, blue: 0.96, alpha: 1).cgColor
    }
    searchField.textColor = palette.primaryTextColor
    searchField.attributedPlaceholder = NSAttributedString(
      string: PteIMUILocalization.value("搜索", "Search", language: language),
      attributes: [.foregroundColor: palette.secondaryTextColor]
    )
    quickActionButtons.forEach { button, icon in
      button.setImage(icons.image(for: icon, traitCollection: traitCollection), for: .normal)
      button.tintColor = palette.outgoingGradientStartColor
      button.setTitleColor(palette.primaryTextColor, for: .normal)
    }
  }

  private func setup(title: String, showsQuickActions: Bool) {
    mark.contentMode = .scaleAspectFit
    titleLabel.text = title; titleLabel.font = .systemFont(ofSize: 18, weight: .bold)
    configure(button: addButton, image: "plus")
    addButton.addTarget(self, action: #selector(tapAdd), for: .touchUpInside)

    let top = UIStackView(arrangedSubviews: [mark, titleLabel, UIView(), addButton])
    top.alignment = .center; top.spacing = 10
    [mark, addButton].forEach { $0.translatesAutoresizingMaskIntoConstraints = false }
    mark.widthAnchor.constraint(equalToConstant: 30).isActive = true; mark.heightAnchor.constraint(equalTo: mark.widthAnchor).isActive = true
    addButton.widthAnchor.constraint(equalToConstant: 24).isActive = true
    addButton.heightAnchor.constraint(equalToConstant: 44).isActive = true

    searchContainer.layer.cornerRadius = 14
    searchIcon.contentMode = .scaleAspectFit
    searchField.borderStyle = .none; searchField.font = .systemFont(ofSize: 14, weight: .regular); searchField.clearButtonMode = .whileEditing
    searchField.addTarget(self, action: #selector(searchChanged), for: .editingChanged)
    [searchIcon, searchField].forEach { $0.translatesAutoresizingMaskIntoConstraints = false; searchContainer.addSubview($0) }
    NSLayoutConstraint.activate([
      searchIcon.leadingAnchor.constraint(equalTo: searchContainer.leadingAnchor, constant: 14), searchIcon.centerYAnchor.constraint(equalTo: searchContainer.centerYAnchor), searchIcon.widthAnchor.constraint(equalToConstant: 16), searchIcon.heightAnchor.constraint(equalTo: searchIcon.widthAnchor),
      searchField.leadingAnchor.constraint(equalTo: searchIcon.trailingAnchor, constant: 8), searchField.trailingAnchor.constraint(equalTo: searchContainer.trailingAnchor, constant: -12), searchField.topAnchor.constraint(equalTo: searchContainer.topAnchor), searchField.bottomAnchor.constraint(equalTo: searchContainer.bottomAnchor)
    ])

    quickActions.axis = .horizontal; quickActions.alignment = .fill; quickActions.distribution = .fillEqually; quickActions.spacing = 12
    if showsQuickActions {
      [
        makeQuickAction(title: "添加好友", icon: .contactAddFriend, selector: #selector(tapAdd)),
        makeQuickAction(title: "发起群聊", icon: .contactCreateGroup, selector: #selector(tapAdd))
      ].forEach { quickActions.addArrangedSubview($0) }
    }
    let content = UIStackView(arrangedSubviews: showsQuickActions ? [top, searchContainer, quickActions] : [top, searchContainer])
    content.axis = .vertical; content.spacing = 12
    insertSubview(topSurface, at: 0)
    addSubview(content); content.translatesAutoresizingMaskIntoConstraints = false
    topSurface.translatesAutoresizingMaskIntoConstraints = false
    NSLayoutConstraint.activate([
      topSurface.leadingAnchor.constraint(equalTo: leadingAnchor), topSurface.trailingAnchor.constraint(equalTo: trailingAnchor), topSurface.topAnchor.constraint(equalTo: topAnchor), topSurface.bottomAnchor.constraint(equalTo: searchContainer.topAnchor, constant: -12),
      content.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 20), content.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -20),
      content.topAnchor.constraint(equalTo: topAnchor), content.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -12),
      top.heightAnchor.constraint(equalToConstant: 44),
      searchContainer.heightAnchor.constraint(equalToConstant: 42)
    ])
    if showsQuickActions { quickActions.heightAnchor.constraint(equalToConstant: 42).isActive = true }
  }

  private func configure(button: UIButton, image: String) {
    button.setImage(UIImage(systemName: image), for: .normal)
    button.setPreferredSymbolConfiguration(.init(pointSize: 17, weight: .medium), forImageIn: .normal)
  }
  private func makeQuickAction(title: String, icon: PteIMUIIconKey, selector: Selector) -> UIButton {
    let button = UIButton(type: .system)
    button.setTitle("  \(title)", for: .normal)
    button.imageView?.contentMode = .scaleAspectFit
    button.titleLabel?.font = .systemFont(ofSize: 14, weight: .semibold)
    button.contentHorizontalAlignment = .leading
    button.addTarget(self, action: selector, for: .touchUpInside)
    quickActionButtons.append((button, icon))
    return button
  }
  @objc private func searchChanged() { onSearchChanged?(searchField.text ?? "") }
  @objc private func tapAdd() { onAddTapped?() }
}

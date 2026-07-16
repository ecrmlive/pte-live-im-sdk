import UIKit

/**
 Shared top chrome for the UIKit conversation and contact surfaces. It keeps
 the product header, search field and quick actions out of application code
 while leaving navigation and business actions overrideable by the host.
 */
@MainActor open class PteIMUIListChrome: UIView {
  public var onSearchChanged: ((String) -> Void)?
  public var onAppearanceTapped: (() -> Void)?
  public var onLanguageTapped: (() -> Void)?
  public var onAddTapped: (() -> Void)?

  private let mark = UILabel()
  private let topSurface = UIView()
  private let titleLabel = UILabel()
  private let appearanceButton = UIButton(type: .system)
  private let languageButton = UIButton(type: .system)
  private let addButton = UIButton(type: .system)
  private let searchContainer = UIView()
  private let searchField = UITextField()
  private let quickActions = UIStackView()
  private var quickActionButtons = [UIButton]()

  public init(title: String, showsQuickActions: Bool = false) {
    super.init(frame: .zero)
    // A tableHeaderView is frame-driven by UITableView. Its internal content
    // uses constraints, but the header itself must retain autoresizing masks.
    translatesAutoresizingMaskIntoConstraints = true
    setup(title: title, showsQuickActions: showsQuickActions)
  }
  required public init?(coder: NSCoder) { nil }

  public func apply(palette: PteIMUIThemePalette, title: String, language: PteIMLanguage) {
    backgroundColor = palette.backgroundColor
    topSurface.backgroundColor = palette.surfaceColor
    mark.backgroundColor = palette.outgoingGradientStartColor
    titleLabel.text = title
    titleLabel.textColor = palette.primaryTextColor
    [appearanceButton, languageButton, addButton].forEach { $0.tintColor = palette.iconColor }
    searchContainer.backgroundColor = palette.backgroundColor
    searchField.textColor = palette.primaryTextColor
    searchField.attributedPlaceholder = NSAttributedString(
      string: PteIMUILocalization.value("搜索", "Search", language: language),
      attributes: [.foregroundColor: palette.secondaryTextColor]
    )
    quickActionButtons.forEach { button in
      button.tintColor = palette.outgoingGradientStartColor
      button.setTitleColor(palette.primaryTextColor, for: .normal)
    }
  }

  private func setup(title: String, showsQuickActions: Bool) {
    mark.text = "P"; mark.textAlignment = .center; mark.font = .systemFont(ofSize: 18, weight: .bold); mark.textColor = .white
    mark.layer.cornerRadius = 18; mark.clipsToBounds = true
    titleLabel.text = title; titleLabel.font = .systemFont(ofSize: 21, weight: .bold)
    configure(button: appearanceButton, image: "moon")
    configure(button: languageButton, image: "globe")
    configure(button: addButton, image: "plus")
    appearanceButton.addTarget(self, action: #selector(tapAppearance), for: .touchUpInside)
    languageButton.addTarget(self, action: #selector(tapLanguage), for: .touchUpInside)
    addButton.addTarget(self, action: #selector(tapAdd), for: .touchUpInside)

    let top = UIStackView(arrangedSubviews: [mark, titleLabel, UIView(), appearanceButton, languageButton, addButton])
    top.alignment = .center; top.spacing = 12
    [mark, appearanceButton, languageButton, addButton].forEach { $0.translatesAutoresizingMaskIntoConstraints = false }
    mark.widthAnchor.constraint(equalToConstant: 36).isActive = true; mark.heightAnchor.constraint(equalToConstant: 36).isActive = true
    [appearanceButton, languageButton, addButton].forEach { button in
      button.widthAnchor.constraint(equalToConstant: 30).isActive = true
      button.heightAnchor.constraint(equalToConstant: 36).isActive = true
    }

    searchContainer.layer.cornerRadius = 14
    let icon = UIImageView(image: UIImage(systemName: "magnifyingglass")); icon.contentMode = .scaleAspectFit
    searchField.borderStyle = .none; searchField.font = .systemFont(ofSize: 14, weight: .regular); searchField.clearButtonMode = .whileEditing
    searchField.addTarget(self, action: #selector(searchChanged), for: .editingChanged)
    [icon, searchField].forEach { $0.translatesAutoresizingMaskIntoConstraints = false; searchContainer.addSubview($0) }
    NSLayoutConstraint.activate([
      icon.leadingAnchor.constraint(equalTo: searchContainer.leadingAnchor, constant: 14), icon.centerYAnchor.constraint(equalTo: searchContainer.centerYAnchor), icon.widthAnchor.constraint(equalToConstant: 16), icon.heightAnchor.constraint(equalToConstant: 16),
      searchField.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 8), searchField.trailingAnchor.constraint(equalTo: searchContainer.trailingAnchor, constant: -12), searchField.topAnchor.constraint(equalTo: searchContainer.topAnchor), searchField.bottomAnchor.constraint(equalTo: searchContainer.bottomAnchor)
    ])

    quickActions.axis = .horizontal; quickActions.alignment = .fill; quickActions.distribution = .fillEqually; quickActions.spacing = 12
    if showsQuickActions {
      [makeQuickAction(title: "添加好友", image: "person.badge.plus", selector: #selector(tapAdd)), makeQuickAction(title: "发起群聊", image: "person.3", selector: #selector(tapAdd))].forEach { quickActions.addArrangedSubview($0) }
    }
    let content = UIStackView(arrangedSubviews: showsQuickActions ? [top, searchContainer, quickActions] : [top, searchContainer])
    content.axis = .vertical; content.spacing = 16
    insertSubview(topSurface, at: 0)
    addSubview(content); content.translatesAutoresizingMaskIntoConstraints = false
    topSurface.translatesAutoresizingMaskIntoConstraints = false
    NSLayoutConstraint.activate([
      topSurface.leadingAnchor.constraint(equalTo: leadingAnchor), topSurface.trailingAnchor.constraint(equalTo: trailingAnchor), topSurface.topAnchor.constraint(equalTo: topAnchor), topSurface.bottomAnchor.constraint(equalTo: searchContainer.topAnchor, constant: -8),
      content.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 20), content.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -20),
      content.topAnchor.constraint(equalTo: topAnchor, constant: 14), content.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -14),
      searchContainer.heightAnchor.constraint(equalToConstant: 42)
    ])
    if showsQuickActions { quickActions.heightAnchor.constraint(equalToConstant: 42).isActive = true }
  }

  private func configure(button: UIButton, image: String) {
    button.setImage(UIImage(systemName: image), for: .normal)
    button.setPreferredSymbolConfiguration(.init(pointSize: 17, weight: .medium), forImageIn: .normal)
  }
  private func makeQuickAction(title: String, image: String, selector: Selector) -> UIButton {
    let button = UIButton(type: .system); button.setTitle("  \(title)", for: .normal); button.setImage(UIImage(systemName: image), for: .normal)
    button.titleLabel?.font = .systemFont(ofSize: 14, weight: .semibold); button.contentHorizontalAlignment = .leading; button.addTarget(self, action: selector, for: .touchUpInside); quickActionButtons.append(button); return button
  }
  @objc private func searchChanged() { onSearchChanged?(searchField.text ?? "") }
  @objc private func tapAppearance() { onAppearanceTapped?() }
  @objc private func tapLanguage() { onLanguageTapped?() }
  @objc private func tapAdd() { onAddTapped?() }
}

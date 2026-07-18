import UIKit
import PteIMSDK

/**
 A shared PteIMUIKit navigation row. The host keeps ownership of routing, but
 this component owns the language menu, the light/dark artwork and the visual
 contract shared by conversations, contacts and chat screens.
 */
@MainActor open class PteIMUINavigationBar: UIView {
  public var onLanguageSelected: ((PteIMLanguage) -> Void)?
  public var onThemeSelected: ((PteIMThemeMode) -> Void)?
  /** Optional secondary-page action. When present it replaces the language control with a back button. */
  public var onBack: (() -> Void)? { didSet { updateLeadingControl() } }

  private let languageButton = UIButton(type: .system)
  private let backButton = UIButton(type: .system)
  private let titleLabel = UILabel()
  private let appearanceButton = UIButton(type: .system)
  private var themeMode: PteIMThemeMode = .light
  private var palette: PteIMUIThemePalette = .blueVioletLight
  private var language: PteIMLanguage = .enUS
  private var languageMenuOverlay: PteIMUILanguageMenuOverlay?

  public init(title: String? = nil) {
    super.init(frame: .zero)
    translatesAutoresizingMaskIntoConstraints = false
    setup(title: title)
    apply(palette: .blueVioletLight, themeMode: .light, language: .enUS)
  }
  required public init?(coder: NSCoder) { nil }

  public func apply(palette: PteIMUIThemePalette, themeMode: PteIMThemeMode, language: PteIMLanguage) {
    self.palette = palette
    self.themeMode = themeMode
    self.language = language
    backgroundColor = palette.surfaceColor
    languageButton.setTitle(languageTitle(language.resolved()), for: .normal)
    languageButton.setTitleColor(palette.iconColor, for: .normal)
    backButton.tintColor = palette.iconColor
    titleLabel.textColor = palette.primaryTextColor
    let dark = isDark(themeMode)
    languageButton.backgroundColor = dark ? UIColor(red: 0.145, green: 0.133, blue: 0.30, alpha: 1) : .clear
    languageButton.layer.cornerRadius = 18
    appearanceButton.backgroundColor = dark ? UIColor(red: 0.133, green: 0.125, blue: 0.27, alpha: 1) : .clear
    appearanceButton.layer.cornerRadius = 20
    appearanceButton.clipsToBounds = true
    appearanceButton.setImage(UIImage(named: dark ? "PteIMUINavigationThemeDark" : "PteIMUINavigationThemeLight", in: .module, compatibleWith: traitCollection)?.withRenderingMode(.alwaysOriginal), for: .normal)
    appearanceButton.tintColor = nil
  }

  public func setTitle(_ title: String?) { titleLabel.text = title }

  /** Hosts call this while applying an appearance so status text remains legible. */
  public static func applySystemBars(to controller: UIViewController, themeMode: PteIMThemeMode) {
    controller.overrideUserInterfaceStyle = themeMode == .dark ? .dark : themeMode == .light ? .light : .unspecified
    controller.setNeedsStatusBarAppearanceUpdate()
  }

  private func setup(title: String?) {
    titleLabel.text = title
    titleLabel.font = .systemFont(ofSize: 18, weight: .semibold)
    titleLabel.textAlignment = .center
    languageButton.titleLabel?.font = .systemFont(ofSize: 14, weight: .medium)
    // The dark pill has a fixed width. Centering its title keeps the label on
    // the same visual axis in both themes instead of making it look offset.
    languageButton.contentHorizontalAlignment = .center
    languageButton.addTarget(self, action: #selector(showLanguageMenu), for: .touchUpInside)
    appearanceButton.imageView?.contentMode = .scaleAspectFit
    appearanceButton.addTarget(self, action: #selector(toggleTheme), for: .touchUpInside)
    backButton.tintColor = palette.iconColor
    backButton.contentHorizontalAlignment = .fill
    backButton.contentVerticalAlignment = .fill
    backButton.imageView?.contentMode = .scaleAspectFit
    backButton.setImage(UIImage(named: "PteIMUIBack", in: .module, compatibleWith: traitCollection)?.withRenderingMode(.alwaysTemplate), for: .normal)
    backButton.addTarget(self, action: #selector(backTapped), for: .touchUpInside)
    [languageButton, backButton, titleLabel, appearanceButton].forEach { $0.translatesAutoresizingMaskIntoConstraints = false; addSubview($0) }
    NSLayoutConstraint.activate([
      heightAnchor.constraint(equalToConstant: 44),
      languageButton.leadingAnchor.constraint(equalTo: leadingAnchor), languageButton.centerYAnchor.constraint(equalTo: centerYAnchor), languageButton.widthAnchor.constraint(equalToConstant: 104), languageButton.heightAnchor.constraint(equalToConstant: 44),
      backButton.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 6), backButton.centerYAnchor.constraint(equalTo: centerYAnchor), backButton.widthAnchor.constraint(equalToConstant: 44), backButton.heightAnchor.constraint(equalToConstant: 44),
      appearanceButton.trailingAnchor.constraint(equalTo: trailingAnchor), appearanceButton.centerYAnchor.constraint(equalTo: centerYAnchor), appearanceButton.widthAnchor.constraint(equalToConstant: 44), appearanceButton.heightAnchor.constraint(equalToConstant: 44),
      titleLabel.leadingAnchor.constraint(equalTo: languageButton.trailingAnchor, constant: 4), titleLabel.trailingAnchor.constraint(equalTo: appearanceButton.leadingAnchor, constant: -4), titleLabel.centerYAnchor.constraint(equalTo: centerYAnchor)
    ])
    updateLeadingControl()
  }

  private func updateLeadingControl() {
    let showsBack = onBack != nil
    backButton.isHidden = !showsBack
    languageButton.isHidden = showsBack
  }

  @objc private func showLanguageMenu() {
    guard languageMenuOverlay == nil, let window else { return }
    let anchorFrame = languageButton.convert(languageButton.bounds, to: window)
    let menu = PteIMUILanguageMenuOverlay(
      frame: window.bounds,
      anchorFrame: anchorFrame,
      themeMode: themeMode,
      selectedLanguage: language,
      onDismiss: { [weak self] in self?.languageMenuOverlay = nil }
    ) { [weak self] selectedLanguage in
      self?.onLanguageSelected?(selectedLanguage)
    }
    languageMenuOverlay = menu
    window.addSubview(menu)
  }

  @objc private func toggleTheme() {
    onThemeSelected?(isDark(themeMode) ? .light : .dark)
  }

  @objc private func backTapped() { onBack?() }

  private func isDark(_ mode: PteIMThemeMode) -> Bool {
    switch mode {
    case .dark: return true
    case .light: return false
    case .system: return traitCollection.userInterfaceStyle == .dark
    }
  }

  private func languageTitle(_ language: PteIMLanguage) -> String {
    switch language {
    case .zhCN: return "简体中文"
    case .enUS: return "English"
    case .system: return "跟随系统"
    }
  }
}

/**
 A lightweight custom popup rather than UIMenu so the language picker remains
 visually consistent with the app's light and dark themes.
 */
@MainActor private final class PteIMUILanguageMenuOverlay: UIView {
  private let panel = UIView()
  private let onDismiss: () -> Void
  private let onSelection: (PteIMLanguage) -> Void

  init(
    frame: CGRect,
    anchorFrame: CGRect,
    themeMode: PteIMThemeMode,
    selectedLanguage: PteIMLanguage,
    onDismiss: @escaping () -> Void,
    onSelection: @escaping (PteIMLanguage) -> Void
  ) {
    self.onDismiss = onDismiss
    self.onSelection = onSelection
    super.init(frame: frame)
    backgroundColor = .clear
    isAccessibilityElement = false

    let dismissControl = UIControl(frame: bounds)
    dismissControl.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    dismissControl.addTarget(self, action: #selector(dismiss), for: .touchUpInside)
    addSubview(dismissControl)

    let dark = themeMode == .dark
    panel.backgroundColor = dark
      ? UIColor(red: 0.067, green: 0.063, blue: 0.165, alpha: 1)
      : .white
    panel.layer.cornerRadius = 20
    panel.layer.borderWidth = 1
    panel.layer.borderColor = (dark
      ? UIColor(red: 0.26, green: 0.23, blue: 0.45, alpha: 1)
      : UIColor(red: 0.88, green: 0.84, blue: 0.98, alpha: 1)).cgColor
    if !dark {
      panel.layer.shadowColor = UIColor(red: 0.28, green: 0.20, blue: 0.55, alpha: 0.12).cgColor
      panel.layer.shadowOpacity = 1
      panel.layer.shadowRadius = 12
      panel.layer.shadowOffset = CGSize(width: 0, height: 5)
    }
    addSubview(panel)

    let panelWidth: CGFloat = 180
    let panelHeight: CGFloat = 160
    let panelX = min(max(16, anchorFrame.minX), bounds.width - panelWidth - 16)
    let panelY = min(anchorFrame.maxY + 6, bounds.height - panelHeight - 12)
    panel.frame = CGRect(x: panelX, y: panelY, width: panelWidth, height: panelHeight)

    let stack = UIStackView()
    stack.axis = .vertical
    stack.spacing = 2
    stack.translatesAutoresizingMaskIntoConstraints = false
    panel.addSubview(stack)
    NSLayoutConstraint.activate([
      stack.topAnchor.constraint(equalTo: panel.topAnchor, constant: 8),
      stack.leadingAnchor.constraint(equalTo: panel.leadingAnchor, constant: 9),
      stack.trailingAnchor.constraint(equalTo: panel.trailingAnchor, constant: -9),
      stack.bottomAnchor.constraint(equalTo: panel.bottomAnchor, constant: -8)
    ])

    [
      (PteIMLanguage.system, "跟随系统"),
      (PteIMLanguage.zhCN, "简体中文"),
      (PteIMLanguage.enUS, "English")
    ].forEach { language, title in
      stack.addArrangedSubview(menuRow(
        title: title,
        language: language,
        selected: selectedLanguage == language,
        dark: dark
      ))
    }
  }

  required init?(coder: NSCoder) { nil }

  private func menuRow(title: String, language: PteIMLanguage, selected: Bool, dark: Bool) -> UIButton {
    let titleColor = dark
      ? UIColor(red: 0.91, green: 0.89, blue: 1, alpha: 1)
      : UIColor(red: 0.12, green: 0.11, blue: 0.22, alpha: 1)
    var configuration = UIButton.Configuration.plain()
    configuration.title = title
    configuration.titleAlignment = .leading
    configuration.baseForegroundColor = titleColor
    configuration.contentInsets = NSDirectionalEdgeInsets(top: 0, leading: 18, bottom: 0, trailing: 18)
    configuration.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { incoming in
      var attributes = incoming
      attributes.font = .systemFont(ofSize: 18, weight: .medium)
      return attributes
    }
    let button = UIButton(configuration: configuration)
    button.heightAnchor.constraint(equalToConstant: 46).isActive = true
    button.contentHorizontalAlignment = .leading
    button.backgroundColor = selected
      ? (dark ? UIColor(red: 0.18, green: 0.16, blue: 0.36, alpha: 1) : UIColor(red: 0.94, green: 0.90, blue: 1, alpha: 1))
      : .clear
    button.layer.cornerRadius = 15
    button.accessibilityLabel = title
    button.addAction(UIAction { [weak self] _ in
      self?.finish(selection: language)
    }, for: .touchUpInside)

    guard selected else { return button }
    let selectedIndicator = UIView()
    selectedIndicator.translatesAutoresizingMaskIntoConstraints = false
    selectedIndicator.backgroundColor = UIColor(red: 0.58, green: 0.29, blue: 1, alpha: 1)
    selectedIndicator.layer.cornerRadius = 5
    selectedIndicator.isUserInteractionEnabled = false
    button.addSubview(selectedIndicator)
    NSLayoutConstraint.activate([
      selectedIndicator.centerYAnchor.constraint(equalTo: button.centerYAnchor),
      selectedIndicator.trailingAnchor.constraint(equalTo: button.trailingAnchor, constant: -22),
      selectedIndicator.widthAnchor.constraint(equalToConstant: 10),
      selectedIndicator.heightAnchor.constraint(equalToConstant: 10)
    ])
    return button
  }

  @objc private func dismiss() {
    finish(selection: nil)
  }

  private func finish(selection: PteIMLanguage?) {
    guard superview != nil else { return }
    removeFromSuperview()
    onDismiss()
    if let selection {
      onSelection(selection)
    }
  }
}

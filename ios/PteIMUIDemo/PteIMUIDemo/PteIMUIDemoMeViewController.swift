import UIKit
import PteIMSDK
import PteIMUIKit

struct PteIMUIDemoProfilePalette {
  let dark: Bool
  let background: UIColor
  let surface: UIColor
  let groupedSurface: UIColor
  let text: UIColor
  let secondary: UIColor
  let separator: UIColor
  let accent = UIColor(red: 0.50, green: 0.24, blue: 0.98, alpha: 1)
  let danger = UIColor(red: 1.00, green: 0.23, blue: 0.25, alpha: 1)

  init(dark: Bool) {
    self.dark = dark
    background = dark ? UIColor(red: 0.045, green: 0.042, blue: 0.125, alpha: 1) : UIColor(red: 0.945, green: 0.945, blue: 1, alpha: 1)
    surface = dark ? UIColor(red: 0.067, green: 0.063, blue: 0.165, alpha: 1) : .white
    groupedSurface = dark ? UIColor(red: 0.075, green: 0.071, blue: 0.180, alpha: 1) : .white
    text = dark ? UIColor(red: 0.92, green: 0.90, blue: 1, alpha: 1) : UIColor(red: 0.10, green: 0.11, blue: 0.22, alpha: 1)
    secondary = dark ? UIColor(red: 0.62, green: 0.60, blue: 0.74, alpha: 1) : UIColor(red: 0.40, green: 0.43, blue: 0.53, alpha: 1)
    separator = dark ? UIColor(red: 0.16, green: 0.14, blue: 0.31, alpha: 1) : UIColor(red: 0.89, green: 0.87, blue: 0.98, alpha: 1)
  }
}

private final class PteIMUIDemoGradientSurface: UIView {
  private let gradient = CAGradientLayer()

  init(colors: [CGColor]) {
    super.init(frame: .zero)
    clipsToBounds = true
    gradient.colors = colors
    gradient.startPoint = CGPoint(x: 0, y: 0)
    gradient.endPoint = CGPoint(x: 1, y: 1)
    layer.insertSublayer(gradient, at: 0)
  }

  required init?(coder: NSCoder) { nil }

  override func layoutSubviews() {
    super.layoutSubviews()
    gradient.frame = bounds
  }
}

private final class PteIMUIDemoImageToggle: UIControl {
  private let imageView = UIImageView()
  private let changed: (Bool) -> Void
  private(set) var isOn: Bool

  init(isOn: Bool, changed: @escaping (Bool) -> Void) {
    self.isOn = isOn
    self.changed = changed
    super.init(frame: .zero)
    imageView.contentMode = .scaleAspectFit
    imageView.translatesAutoresizingMaskIntoConstraints = false
    addSubview(imageView)
    NSLayoutConstraint.activate([
      imageView.leadingAnchor.constraint(equalTo: leadingAnchor),
      imageView.trailingAnchor.constraint(equalTo: trailingAnchor),
      imageView.topAnchor.constraint(equalTo: topAnchor),
      imageView.bottomAnchor.constraint(equalTo: bottomAnchor),
      widthAnchor.constraint(equalToConstant: 48),
      heightAnchor.constraint(equalToConstant: 24)
    ])
    setOn(isOn, notify: false)
    addTarget(self, action: #selector(tapped), for: .touchUpInside)
  }

  required init?(coder: NSCoder) { nil }

  @objc private func tapped() { setOn(!isOn, notify: true) }

  private func setOn(_ value: Bool, notify: Bool) {
    isOn = value
    imageView.image = PteIMUIDemoAssets.image(named: value ? "PteIMUIToggleOn" : "PteIMUIToggleOff")
    accessibilityValue = value ? "On" : "Off"
    if notify { changed(value) }
  }
}

class PteIMUIDemoProfileBaseController: UIViewController {
  let client: PteIMSDK
  let appearanceListener = PteIMListener()

  init(client: PteIMSDK) { self.client = client; super.init(nibName: nil, bundle: nil) }
  required init?(coder: NSCoder) { nil }
  deinit { client.removeListener(appearanceListener) }

  var dark: Bool { client.resolvedTheme() == .dark }
  var palette: PteIMUIDemoProfilePalette { .init(dark: dark) }
  var isEnglish: Bool { client.resolvedLanguage() == .enUS }
  func copy(_ zh: String, _ en: String) -> String { isEnglish ? en : zh }

  override func viewDidLoad() {
    super.viewDidLoad()
    appearanceListener.onThemeModeChanged = { [weak self] _ in DispatchQueue.main.async { self?.refreshAppearance() } }
    appearanceListener.onLanguageChanged = { [weak self] _ in DispatchQueue.main.async { self?.refreshAppearance() } }
    client.addListener(appearanceListener)
    refreshAppearance()
  }

  override func viewWillAppear(_ animated: Bool) {
    super.viewWillAppear(animated)
    navigationController?.setNavigationBarHidden(true, animated: false)
    refreshAppearance()
  }

  func refreshAppearance() {
    overrideUserInterfaceStyle = dark ? .dark : .light
    view.backgroundColor = palette.background
    setNeedsStatusBarAppearanceUpdate()
  }

  override var preferredStatusBarStyle: UIStatusBarStyle { dark ? .lightContent : .darkContent }

  /** A fixed 44pt navigation bar whose background also fills the status-bar area. */
  @discardableResult
  func installNavigationChrome(_ bar: UIView) -> UIView {
    let chrome = UIView()
    chrome.backgroundColor = palette.surface
    chrome.translatesAutoresizingMaskIntoConstraints = false
    view.addSubview(chrome)
    bar.translatesAutoresizingMaskIntoConstraints = false
    chrome.addSubview(bar)
    NSLayoutConstraint.activate([
      chrome.leadingAnchor.constraint(equalTo: view.leadingAnchor),
      chrome.trailingAnchor.constraint(equalTo: view.trailingAnchor),
      chrome.topAnchor.constraint(equalTo: view.topAnchor),
      chrome.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 44),
      bar.leadingAnchor.constraint(equalTo: chrome.leadingAnchor),
      bar.trailingAnchor.constraint(equalTo: chrome.trailingAnchor),
      bar.bottomAnchor.constraint(equalTo: chrome.bottomAnchor)
    ])
    return chrome
  }

  func icon(_ name: String, fallback: String) -> UIImage? {
    PteIMUIDemoAssets.image(named: name, traitCollection: traitCollection) ?? UIImage(systemName: fallback)
  }

  func makeTopBar(title: String, backAction: Selector? = nil) -> UIView {
    let palette = palette
    let bar = UIView(); bar.backgroundColor = palette.surface
    let titleLabel = UILabel(); titleLabel.text = title; titleLabel.font = .systemFont(ofSize: 18, weight: .bold); titleLabel.textColor = palette.text
    titleLabel.translatesAutoresizingMaskIntoConstraints = false; bar.addSubview(titleLabel)
    NSLayoutConstraint.activate([
      bar.heightAnchor.constraint(equalToConstant: 44),
      titleLabel.centerYAnchor.constraint(equalTo: bar.centerYAnchor),
      titleLabel.leadingAnchor.constraint(equalTo: bar.leadingAnchor, constant: backAction == nil ? 54 : 58)
    ])
    if let backAction {
      let back = UIButton(type: .system); back.setImage(UIImage(systemName: "chevron.left"), for: .normal); back.tintColor = palette.text; back.addTarget(self, action: backAction, for: .touchUpInside); back.translatesAutoresizingMaskIntoConstraints = false; bar.addSubview(back)
      NSLayoutConstraint.activate([back.leadingAnchor.constraint(equalTo: bar.leadingAnchor, constant: 8), back.centerYAnchor.constraint(equalTo: bar.centerYAnchor), back.widthAnchor.constraint(equalToConstant: 44), back.heightAnchor.constraint(equalToConstant: 44)])
    } else {
      let mark = UIImageView(image: icon("PteIMUIBrandMark", fallback: "lock.shield.fill")); mark.contentMode = .scaleAspectFit; mark.layer.cornerRadius = 15; mark.clipsToBounds = true; mark.translatesAutoresizingMaskIntoConstraints = false; bar.addSubview(mark)
      NSLayoutConstraint.activate([mark.leadingAnchor.constraint(equalTo: bar.leadingAnchor, constant: 16), mark.centerYAnchor.constraint(equalTo: bar.centerYAnchor), mark.widthAnchor.constraint(equalToConstant: 30), mark.heightAnchor.constraint(equalTo: mark.widthAnchor)])
    }
    return bar
  }

  func makeDisclosureRow(icon: UIImage?, title: String, subtitle: String? = nil, action: Selector? = nil, accessory: UIView? = nil) -> UIView {
    let palette = palette
    let row = UIControl(); row.backgroundColor = palette.groupedSurface
    if let action { row.addTarget(self, action: action, for: .touchUpInside) }
    let image = UIImageView(image: icon); image.contentMode = .scaleAspectFit; image.tintColor = palette.accent; image.translatesAutoresizingMaskIntoConstraints = false
    let titleLabel = UILabel(); titleLabel.text = title; titleLabel.font = .systemFont(ofSize: 15, weight: .medium); titleLabel.textColor = palette.text; titleLabel.translatesAutoresizingMaskIntoConstraints = false
    let labels = UIStackView(arrangedSubviews: [titleLabel]); labels.axis = .vertical; labels.spacing = 2; labels.translatesAutoresizingMaskIntoConstraints = false
    if let subtitle {
      let label = UILabel(); label.text = subtitle; label.font = .systemFont(ofSize: 12, weight: .regular); label.textColor = palette.secondary; labels.addArrangedSubview(label)
    }
    let trailing = accessory ?? UIImageView(image: PteIMUIDemoAssets.image(named: palette.dark ? "PteIMUIMeArrowDark" : "PteIMUIMeArrowLight"))
    if let arrow = trailing as? UIImageView { arrow.contentMode = .scaleAspectFit }
    trailing.translatesAutoresizingMaskIntoConstraints = false
    row.addSubview(image); row.addSubview(labels); row.addSubview(trailing)
    NSLayoutConstraint.activate([
      row.heightAnchor.constraint(greaterThanOrEqualToConstant: subtitle == nil ? 54 : 66),
      image.leadingAnchor.constraint(equalTo: row.leadingAnchor, constant: 18), image.centerYAnchor.constraint(equalTo: row.centerYAnchor), image.widthAnchor.constraint(equalToConstant: 20), image.heightAnchor.constraint(equalTo: image.widthAnchor),
      labels.leadingAnchor.constraint(equalTo: image.trailingAnchor, constant: 14), labels.centerYAnchor.constraint(equalTo: row.centerYAnchor),
      trailing.trailingAnchor.constraint(equalTo: row.trailingAnchor, constant: -16), trailing.centerYAnchor.constraint(equalTo: row.centerYAnchor), trailing.widthAnchor.constraint(lessThanOrEqualToConstant: 48), trailing.heightAnchor.constraint(lessThanOrEqualToConstant: 32),
      labels.trailingAnchor.constraint(lessThanOrEqualTo: trailing.leadingAnchor, constant: -12)
    ])
    return row
  }

  func makeGroup(_ rows: [UIView]) -> UIView {
    let palette = palette
    let panel = UIView(); panel.backgroundColor = palette.groupedSurface; panel.layer.cornerRadius = 16; panel.clipsToBounds = true
    let stack = UIStackView(); stack.axis = .vertical; stack.spacing = 0; stack.translatesAutoresizingMaskIntoConstraints = false; panel.addSubview(stack)
    rows.enumerated().forEach { index, row in
      stack.addArrangedSubview(row)
      if index < rows.count - 1 {
        let line = UIView(); line.backgroundColor = palette.separator; line.heightAnchor.constraint(equalToConstant: 1 / UIScreen.main.scale).isActive = true
        let wrap = UIView(); wrap.addSubview(line); line.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([line.leadingAnchor.constraint(equalTo: wrap.leadingAnchor, constant: 18), line.trailingAnchor.constraint(equalTo: wrap.trailingAnchor), line.centerYAnchor.constraint(equalTo: wrap.centerYAnchor)])
        stack.addArrangedSubview(wrap); wrap.heightAnchor.constraint(equalToConstant: 1 / UIScreen.main.scale).isActive = true
      }
    }
    NSLayoutConstraint.activate([stack.leadingAnchor.constraint(equalTo: panel.leadingAnchor), stack.trailingAnchor.constraint(equalTo: panel.trailingAnchor), stack.topAnchor.constraint(equalTo: panel.topAnchor), stack.bottomAnchor.constraint(equalTo: panel.bottomAnchor)])
    return panel
  }

  func switchControl(isOn: Bool, changed: @escaping (Bool) -> Void) -> UIView {
    PteIMUIDemoImageToggle(isOn: isOn, changed: changed)
  }
}

final class PteIMUIDemoMeViewController: PteIMUIDemoProfileBaseController {
  private let onLogout: () -> Void
  init(client: PteIMSDK, onLogout: @escaping () -> Void) { self.onLogout = onLogout; super.init(client: client) }
  required init?(coder: NSCoder) { nil }

  override func refreshAppearance() {
    super.refreshAppearance()
    guard isViewLoaded else { return }
    view.subviews.forEach { $0.removeFromSuperview() }
    build()
  }

  private func build() {
    let palette = palette
    let scroll = UIScrollView(); scroll.alwaysBounceVertical = true; scroll.showsVerticalScrollIndicator = false; scroll.translatesAutoresizingMaskIntoConstraints = false
    let content = UIStackView(); content.axis = .vertical; content.spacing = 0; content.translatesAutoresizingMaskIntoConstraints = false
    view.addSubview(scroll); scroll.addSubview(content)
    let chrome = installNavigationChrome(rootTopBar())
    NSLayoutConstraint.activate([scroll.leadingAnchor.constraint(equalTo: view.leadingAnchor), scroll.trailingAnchor.constraint(equalTo: view.trailingAnchor), scroll.topAnchor.constraint(equalTo: chrome.bottomAnchor), scroll.bottomAnchor.constraint(equalTo: view.bottomAnchor), content.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor), content.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor), content.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor), content.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor), content.widthAnchor.constraint(equalTo: scroll.frameLayoutGuide.widthAnchor)])
    content.addArrangedSubview(profileBanner())
    content.addArrangedSubview(quickActions())
    let spacer = UIView(); spacer.backgroundColor = palette.background; spacer.heightAnchor.constraint(equalToConstant: 16).isActive = true; content.addArrangedSubview(spacer)
    let language = languageBadge()
    let sections = makeGroup([
      makeDisclosureRow(icon: icon("PteIMUIMeTheme", fallback: "moon"), title: copy("深色模式", "Dark Mode"), subtitle: client.appearance.themeMode == .system ? copy("跟随时间", "Time based") : nil, accessory: switchControl(isOn: dark) { [weak self] isOn in self?.client.updateAppearance(themeMode: isOn ? .dark : .light) }),
      makeDisclosureRow(icon: icon("PteIMUIMeLanguage", fallback: "globe"), title: copy("语言", "Language"), action: #selector(openLanguage), accessory: language),
      makeDisclosureRow(icon: icon("PteIMUIMeNotifications", fallback: "bell"), title: copy("通知设置", "Notifications"), action: #selector(showNotice)),
      makeDisclosureRow(icon: icon("PteIMUIMePrivacy", fallback: "shield"), title: copy("隐私与安全", "Privacy & Security"), action: #selector(showNotice)),
      makeDisclosureRow(icon: icon("PteIMUIMeFeedback", fallback: "questionmark.circle"), title: copy("帮助与反馈", "Help & Feedback"), action: #selector(showNotice)),
      makeDisclosureRow(icon: icon("PteIMUIMeSettings", fallback: "gearshape"), title: copy("设置", "Settings"), action: #selector(openSettings))
    ])
    let wrap = UIView(); wrap.backgroundColor = palette.background; wrap.addSubview(sections); sections.translatesAutoresizingMaskIntoConstraints = false
    NSLayoutConstraint.activate([sections.leadingAnchor.constraint(equalTo: wrap.leadingAnchor, constant: 20), sections.trailingAnchor.constraint(equalTo: wrap.trailingAnchor, constant: -20), sections.topAnchor.constraint(equalTo: wrap.topAnchor), sections.bottomAnchor.constraint(equalTo: wrap.bottomAnchor)])
    content.addArrangedSubview(wrap)
    let logout = UIButton(type: .system); logout.setTitle(copy("退出登录", "Log Out"), for: .normal); logout.setImage(UIImage(systemName: "rectangle.portrait.and.arrow.right"), for: .normal); logout.tintColor = palette.danger; logout.setTitleColor(palette.danger, for: .normal); logout.titleLabel?.font = .systemFont(ofSize: 15, weight: .semibold); logout.backgroundColor = palette.danger.withAlphaComponent(palette.dark ? 0.12 : 0.10); logout.layer.cornerRadius = 15; logout.addTarget(self, action: #selector(logoutTapped), for: .touchUpInside); logout.translatesAutoresizingMaskIntoConstraints = false
    let logoutWrap = UIView(); logoutWrap.backgroundColor = palette.background; logoutWrap.addSubview(logout)
    NSLayoutConstraint.activate([logout.leadingAnchor.constraint(equalTo: logoutWrap.leadingAnchor, constant: 20), logout.trailingAnchor.constraint(equalTo: logoutWrap.trailingAnchor, constant: -20), logout.topAnchor.constraint(equalTo: logoutWrap.topAnchor, constant: 18), logout.heightAnchor.constraint(equalToConstant: 48), logout.bottomAnchor.constraint(equalTo: logoutWrap.bottomAnchor, constant: -50)])
    content.addArrangedSubview(logoutWrap)
  }

  private func rootTopBar() -> UIView {
    let bar = makeTopBar(title: copy("我的", "Me"))
    let settings = navigationButton(imageName: "PteIMUIMeSettings", action: #selector(openSettings))
    bar.addSubview(settings)
    NSLayoutConstraint.activate([
      settings.trailingAnchor.constraint(equalTo: bar.trailingAnchor, constant: -12),
      settings.centerYAnchor.constraint(equalTo: bar.centerYAnchor),
      settings.widthAnchor.constraint(equalToConstant: 44),
      settings.heightAnchor.constraint(equalToConstant: 44)
    ])
    return bar
  }

  private func navigationButton(imageName: String, action: Selector) -> UIButton {
    let button = UIButton(type: .custom)
    button.setImage(PteIMUIDemoAssets.image(named: imageName), for: .normal)
    button.imageView?.contentMode = .scaleAspectFit
    button.addTarget(self, action: action, for: .touchUpInside)
    button.translatesAutoresizingMaskIntoConstraints = false
    return button
  }

  private func profileBanner() -> UIView {
    let panel = PteIMUIDemoGradientSurface(colors: palette.dark ? [UIColor(red: 0.07, green: 0.08, blue: 0.23, alpha: 1).cgColor, UIColor(red: 0.04, green: 0.10, blue: 0.23, alpha: 1).cgColor] : [UIColor(red: 0.83, green: 0.83, blue: 1, alpha: 1).cgColor, UIColor(red: 0.82, green: 0.91, blue: 1, alpha: 1).cgColor])
    let avatar = UILabel(); avatar.text = copy("我", "Me"); avatar.textAlignment = .center; avatar.font = .systemFont(ofSize: 25, weight: .bold); avatar.textColor = .white; avatar.layer.cornerRadius = 16; avatar.clipsToBounds = true; avatar.backgroundColor = UIColor(red: 0.22, green: 0.43, blue: 0.96, alpha: 1)
    let online = UIView(); online.backgroundColor = UIColor(red: 0.10, green: 0.82, blue: 0.40, alpha: 1); online.layer.cornerRadius = 9; online.layer.borderWidth = 2; online.layer.borderColor = palette.dark ? UIColor(red: 0.07, green: 0.08, blue: 0.23, alpha: 1).cgColor : UIColor(red: 0.83, green: 0.87, blue: 1, alpha: 1).cgColor
    let name = UILabel(); name.text = "User_\(client.currentUserId)"; name.font = .systemFont(ofSize: 17, weight: .bold); name.textColor = palette.text
    let identifier = UILabel(); identifier.text = "ID: usr_\(client.currentUserId)"; identifier.font = .systemFont(ofSize: 11); identifier.textColor = palette.secondary
    let copyStack = UIStackView(arrangedSubviews: [name, identifier]); copyStack.axis = .vertical; copyStack.spacing = 4
    let arrow = UIImageView(image: PteIMUIDemoAssets.image(named: palette.dark ? "PteIMUIMeArrowDark" : "PteIMUIMeArrowLight")); arrow.contentMode = .scaleAspectFit
    [avatar, online, copyStack, arrow].forEach { $0.translatesAutoresizingMaskIntoConstraints = false; panel.addSubview($0) }
    NSLayoutConstraint.activate([panel.heightAnchor.constraint(equalToConstant: 112), avatar.leadingAnchor.constraint(equalTo: panel.leadingAnchor, constant: 20), avatar.centerYAnchor.constraint(equalTo: panel.centerYAnchor), avatar.widthAnchor.constraint(equalToConstant: 64), avatar.heightAnchor.constraint(equalTo: avatar.widthAnchor), online.trailingAnchor.constraint(equalTo: avatar.trailingAnchor, constant: 4), online.bottomAnchor.constraint(equalTo: avatar.bottomAnchor, constant: 4), online.widthAnchor.constraint(equalToConstant: 18), online.heightAnchor.constraint(equalTo: online.widthAnchor), copyStack.leadingAnchor.constraint(equalTo: avatar.trailingAnchor, constant: 16), copyStack.centerYAnchor.constraint(equalTo: panel.centerYAnchor), arrow.trailingAnchor.constraint(equalTo: panel.trailingAnchor, constant: -28), arrow.centerYAnchor.constraint(equalTo: panel.centerYAnchor)])
    return panel
  }

  private func quickActions() -> UIView {
    let palette = palette
    let row = UIStackView(); row.axis = .horizontal; row.distribution = .fillEqually; row.backgroundColor = palette.surface
    [("PteIMUIMeFavorites", "star", "12", copy("我的收藏", "Favorites")), ("PteIMUIMeWallet", "creditcard", "¥88", copy("我的钱包", "Wallet")), ("PteIMUIMeQRCode", "qrcode", "", copy("二维码名片", "QR Card"))].enumerated().forEach { index, item in
      let icon = UIImageView(image: self.icon(item.0, fallback: item.1)); icon.contentMode = .scaleAspectFit; icon.tintColor = palette.accent
      let value = UILabel(); value.text = item.2; value.textAlignment = .center; value.font = .systemFont(ofSize: 13, weight: .semibold); value.textColor = palette.text
      let title = UILabel(); title.text = item.3; title.textAlignment = .center; title.font = .systemFont(ofSize: 10); title.textColor = palette.secondary
      let stack = UIStackView(arrangedSubviews: [icon, value, title]); stack.axis = .vertical; stack.alignment = .center; stack.spacing = 3; stack.isLayoutMarginsRelativeArrangement = true; stack.directionalLayoutMargins = .init(top: 15, leading: 0, bottom: 14, trailing: 0); row.addArrangedSubview(stack)
      if index < 2 {
        let line = UIView(); line.backgroundColor = palette.separator; line.translatesAutoresizingMaskIntoConstraints = false; row.addSubview(line)
        let relativeLeading = NSLayoutConstraint(item: line, attribute: .leading, relatedBy: .equal, toItem: row, attribute: .trailing, multiplier: CGFloat(index + 1) / 3, constant: 0)
        NSLayoutConstraint.activate([relativeLeading, line.centerYAnchor.constraint(equalTo: row.centerYAnchor), line.widthAnchor.constraint(equalToConstant: 1 / UIScreen.main.scale), line.heightAnchor.constraint(equalTo: row.heightAnchor, multiplier: 0.72)])
      }
    }
    row.heightAnchor.constraint(equalToConstant: 96).isActive = true; return row
  }

  private func languageBadge() -> UILabel {
    let badge = UILabel(); badge.text = isEnglish ? "EN" : "中文"; badge.textAlignment = .center; badge.font = .systemFont(ofSize: 12, weight: .semibold); badge.textColor = palette.accent; badge.backgroundColor = palette.accent.withAlphaComponent(palette.dark ? 0.16 : 0.12); badge.layer.cornerRadius = 16; badge.clipsToBounds = true; badge.widthAnchor.constraint(equalToConstant: 48).isActive = true; badge.heightAnchor.constraint(equalToConstant: 32).isActive = true; return badge
  }
  @objc private func openLanguage() {
    let controller = PteIMUIDemoLanguageSettingsViewController(client: client)
    controller.hidesBottomBarWhenPushed = true
    navigationController?.pushViewController(controller, animated: true)
  }
  @objc private func openSettings() {
    let controller = PteIMUIDemoSettingsViewController(client: client)
    controller.hidesBottomBarWhenPushed = true
    navigationController?.pushViewController(controller, animated: true)
  }
  @objc private func showNotice() { let alert = UIAlertController(title: copy("业务设置", "Business Setting"), message: copy("该入口由业务层接入。", "This setting is connected by the host app."), preferredStyle: .alert); alert.addAction(UIAlertAction(title: copy("确定", "OK"), style: .default)); present(alert, animated: true) }
  @objc private func logoutTapped() { onLogout() }
}

private final class PteIMUIDemoSettingsViewController: PteIMUIDemoProfileBaseController {
  override func refreshAppearance() {
    super.refreshAppearance(); guard isViewLoaded else { return }; view.subviews.forEach { $0.removeFromSuperview() }; build()
  }
  private func build() {
    let palette = palette
    let scroll = UIScrollView(); scroll.alwaysBounceVertical = true; scroll.showsVerticalScrollIndicator = false; scroll.translatesAutoresizingMaskIntoConstraints = false
    let content = UIStackView(); content.axis = .vertical; content.spacing = 18; content.translatesAutoresizingMaskIntoConstraints = false
    view.addSubview(scroll); scroll.addSubview(content)
    let chrome = installNavigationChrome(makeTopBar(title: copy("设置", "Settings"), backAction: #selector(back)))
    NSLayoutConstraint.activate([scroll.leadingAnchor.constraint(equalTo: view.leadingAnchor), scroll.trailingAnchor.constraint(equalTo: view.trailingAnchor), scroll.topAnchor.constraint(equalTo: chrome.bottomAnchor), scroll.bottomAnchor.constraint(equalTo: view.bottomAnchor), content.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor, constant: 20), content.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor, constant: -20), content.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor, constant: 18), content.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor, constant: -18), content.widthAnchor.constraint(equalTo: scroll.frameLayoutGuide.widthAnchor, constant: -40)])
    content.addArrangedSubview(section(title: copy("外观 · 外观", "APPEARANCE · 外观"), rows: [
      makeDisclosureRow(icon: icon("PteIMUIMeTheme", fallback: "moon"), title: copy("深色模式", "Dark Mode"), subtitle: client.appearance.themeMode == .system ? copy("跟随时间", "Time based") : (dark ? copy("深色", "Dark") : copy("浅色", "Light")), accessory: switchControl(isOn: dark) { [weak self] isOn in self?.client.updateAppearance(themeMode: isOn ? .dark : .light) }),
      makeDisclosureRow(icon: icon("PteIMUIMeLanguage", fallback: "globe"), title: copy("语言", "Language"), subtitle: isEnglish ? "English" : "简体中文", action: #selector(openLanguage), accessory: languageBadge())
    ]))
    content.addArrangedSubview(section(title: copy("通知 · 通知", "NOTIFICATIONS · 通知"), rows: [
      makeDisclosureRow(icon: icon("PteIMUIMeNotifications", fallback: "bell"), title: copy("通知设置", "Notifications"), subtitle: copy("推送通知 Push", "Push Notifications"), accessory: switchControl(isOn: true) { _ in }),
      makeDisclosureRow(icon: icon("PteIMUISettingsSound", fallback: "speaker.wave.2"), title: copy("声音", "Sound"), subtitle: copy("消息提示音 Sound", "Message alert sound"), accessory: switchControl(isOn: true) { _ in }),
      makeDisclosureRow(icon: icon("PteIMUISettingsReceipts", fallback: "checkmark"), title: copy("已读回执", "Read Receipts"), subtitle: copy("已读回执 Receipts", "Read receipts"), accessory: switchControl(isOn: true) { _ in })
    ]))
    content.addArrangedSubview(section(title: copy("隐私与安全 · 隐私", "PRIVACY & SECURITY · 隐私"), rows: [
      makeDisclosureRow(icon: icon("PteIMUIMePrivacy", fallback: "shield"), title: copy("隐私与安全", "Privacy & Security"), subtitle: copy("隐私设置", "Privacy settings"), action: #selector(showNotice)),
      makeDisclosureRow(icon: icon("PteIMUISettingsAccount", fallback: "person"), title: copy("账号管理", "Account"), subtitle: copy("账号管理", "Account management"), action: #selector(showNotice)),
      makeDisclosureRow(icon: icon("PteIMUIMeFeedback", fallback: "questionmark.circle"), title: copy("帮助与反馈", "Help & Feedback"), subtitle: copy("帮助中心", "Help center"), action: #selector(showNotice)),
      makeDisclosureRow(icon: icon("PteIMUISettingsAbout", fallback: "star"), title: copy("关于", "About"), subtitle: "v2.4.1", action: #selector(showNotice))
    ]))
    let footer = UILabel(); footer.text = copy("PrivateChat v1.0.0\n© 2026 PTE Live", "PrivateChat v1.0.0\n© 2026 PTE Live"); footer.numberOfLines = 2; footer.textAlignment = .center; footer.font = .systemFont(ofSize: 11); footer.textColor = palette.secondary; content.addArrangedSubview(footer)
  }
  private func section(title: String, rows: [UIView]) -> UIView {
    let panel = makeGroup(rows); let label = UILabel(); label.text = title; label.font = .systemFont(ofSize: 10, weight: .bold); label.textColor = palette.secondary
    let stack = UIStackView(arrangedSubviews: [label, panel]); stack.axis = .vertical; stack.spacing = 12; return stack
  }
  private func languageBadge() -> UILabel { let label = UILabel(); label.text = isEnglish ? "EN" : "中文"; label.textAlignment = .center; label.font = .systemFont(ofSize: 12, weight: .semibold); label.textColor = palette.accent; label.backgroundColor = palette.accent.withAlphaComponent(palette.dark ? 0.16 : 0.12); label.layer.cornerRadius = 16; label.clipsToBounds = true; label.widthAnchor.constraint(equalToConstant: 48).isActive = true; label.heightAnchor.constraint(equalToConstant: 32).isActive = true; return label }
  @objc private func back() { navigationController?.popViewController(animated: true) }
  @objc private func openLanguage() { navigationController?.pushViewController(PteIMUIDemoLanguageSettingsViewController(client: client), animated: true) }
  @objc private func showNotice() { let alert = UIAlertController(title: copy("业务设置", "Business Setting"), message: copy("该入口由业务层接入。", "This setting is connected by the host app."), preferredStyle: .alert); alert.addAction(UIAlertAction(title: copy("确定", "OK"), style: .default)); present(alert, animated: true) }
}

private final class PteIMUIDemoLanguageSettingsViewController: PteIMUIDemoProfileBaseController {
  override func refreshAppearance() {
    super.refreshAppearance(); guard isViewLoaded else { return }; view.subviews.forEach { $0.removeFromSuperview() }; build()
  }
  private func build() {
    let scroll = UIScrollView(); scroll.translatesAutoresizingMaskIntoConstraints = false
    let content = UIStackView(); content.axis = .vertical; content.spacing = 18; content.translatesAutoresizingMaskIntoConstraints = false
    view.addSubview(scroll); scroll.addSubview(content)
    let chrome = installNavigationChrome(makeTopBar(title: copy("语言", "Language"), backAction: #selector(back)))
    NSLayoutConstraint.activate([scroll.leadingAnchor.constraint(equalTo: view.leadingAnchor), scroll.trailingAnchor.constraint(equalTo: view.trailingAnchor), scroll.topAnchor.constraint(equalTo: chrome.bottomAnchor), scroll.bottomAnchor.constraint(equalTo: view.bottomAnchor), content.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor, constant: 20), content.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor, constant: -20), content.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor, constant: 18), content.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor, constant: -18), content.widthAnchor.constraint(equalTo: scroll.frameLayoutGuide.widthAnchor, constant: -40)])
    let system = languageRow(title: copy("跟随系统", "Follow System"), language: .system)
    let chinese = languageRow(title: "简体中文", language: .zhCN)
    let english = languageRow(title: "English", language: .enUS)
    content.addArrangedSubview(makeGroup([system, chinese, english]))
  }
  private func languageRow(title: String, language: PteIMLanguage) -> UIView {
    let selected = client.appearance.language == language
    let row = UIControl(); row.backgroundColor = palette.groupedSurface; row.addTarget(self, action: #selector(selectLanguage(_:)), for: .touchUpInside); row.accessibilityIdentifier = language.rawValue
    let label = UILabel(); label.text = title; label.font = .systemFont(ofSize: 16, weight: .medium); label.textColor = palette.text; label.translatesAutoresizingMaskIntoConstraints = false; row.addSubview(label)
    let tick = UIImageView(image: UIImage(systemName: selected ? "checkmark.circle.fill" : "circle")); tick.tintColor = selected ? palette.accent : palette.secondary; tick.translatesAutoresizingMaskIntoConstraints = false; row.addSubview(tick)
    NSLayoutConstraint.activate([row.heightAnchor.constraint(equalToConstant: 56), label.leadingAnchor.constraint(equalTo: row.leadingAnchor, constant: 18), label.centerYAnchor.constraint(equalTo: row.centerYAnchor), tick.trailingAnchor.constraint(equalTo: row.trailingAnchor, constant: -18), tick.centerYAnchor.constraint(equalTo: row.centerYAnchor), tick.widthAnchor.constraint(equalToConstant: 20), tick.heightAnchor.constraint(equalTo: tick.widthAnchor)])
    return row
  }
  @objc private func selectLanguage(_ sender: UIControl) { guard let raw = sender.accessibilityIdentifier, let language = PteIMLanguage(rawValue: raw) else { return }; client.updateAppearance(language: language) }
  @objc private func back() { navigationController?.popViewController(animated: true) }
}

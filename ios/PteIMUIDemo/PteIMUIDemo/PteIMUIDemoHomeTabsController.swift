import UIKit
import PteIMSDK
import PteIMUIKit

/**
 Business-layer container used after a successful IM login. PteIMUIKit owns
 the first two tabs; profile and business navigation remain in the Demo.
 */
final class PteIMUIDemoHomeTabsController: UITabBarController {
  private let client: PteIMSDK
  private let onLogout: () -> Void
  private let onAddDemoFriend: ((UIViewController) -> Void)?
  private let isPreview: Bool
  private let appearanceListener = PteIMListener()
  #if DEBUG
  private var didOpenPreviewChat = false
  #endif

  init(client: PteIMSDK, isPreview: Bool = false, onLogout: @escaping () -> Void, onAddDemoFriend: ((UIViewController) -> Void)? = nil) {
    self.client = client; self.isPreview = isPreview; self.onLogout = onLogout; self.onAddDemoFriend = onAddDemoFriend
    super.init(nibName: nil, bundle: nil)
  }
  required init?(coder: NSCoder) { nil }
  deinit { client.removeListener(appearanceListener) }

  override func viewDidLoad() {
    super.viewDidLoad()
    appearanceListener.onThemeModeChanged = { [weak self] _ in
      DispatchQueue.main.async { self?.applyTabBarAppearance() }
    }
    appearanceListener.onLanguageChanged = { [weak self] _ in
      DispatchQueue.main.async { self?.applyTabTitles() }
    }
    client.addListener(appearanceListener)
    let conversations = PteIMUIConversationListViewController(client: client)
    if isPreview {
      let calendar = Calendar.current
      let now = Date()
      let aliceTime = calendar.date(bySettingHour: 10, minute: 24, second: 0, of: now) ?? now
      let teamTime = calendar.date(bySettingHour: 9, minute: 51, second: 0, of: now) ?? now
      conversations.hostPresentations = [
        .init(conversationId: "990022", title: "Alice Chen", subtitle: "明天见！See you tomorrow!", avatarText: "A", avatarBackgroundColor: UIColor(red: 0.52, green: 0.27, blue: 0.94, alpha: 1), isOnline: true, unreadCount: 2, updatedAt: aliceTime),
        .init(conversationId: "990023", kind: .group, title: "Work Team 工作群", subtitle: "[图片] [Image]", avatarText: "#", avatarBackgroundColor: UIColor(red: 0.00, green: 0.58, blue: 0.72, alpha: 1), unreadCount: 5, updatedAt: teamTime),
        .init(conversationId: "990024", title: "Bob Li", subtitle: "[语音] 12秒", avatarText: "B", avatarBackgroundColor: UIColor(red: 0.00, green: 0.62, blue: 0.42, alpha: 1), updatedAt: now.addingTimeInterval(-86_400)),
        .init(conversationId: "990025", kind: .group, title: "Project Alpha", subtitle: "收到，我来处理 Got it", avatarText: "#", avatarBackgroundColor: UIColor(red: 0.92, green: 0.48, blue: 0.00, alpha: 1), updatedAt: now.addingTimeInterval(-86_700)),
        .init(conversationId: "990026", title: "Carol Wu", subtitle: "[红包] 恭喜发财", avatarText: "C", avatarBackgroundColor: UIColor(red: 0.87, green: 0.12, blue: 0.45, alpha: 1), updatedAt: now.addingTimeInterval(-345_600)),
        .init(conversationId: "990027", title: "Dave Zhang", subtitle: "[订单] iPhone 15 Pro", avatarText: "D", avatarBackgroundColor: UIColor(red: 0.43, green: 0.20, blue: 0.90, alpha: 1), updatedAt: now.addingTimeInterval(-432_000))
      ]
    }
    conversations.onConversationSelected = { [weak self] item, controller in self?.openChat(conversationId: item.conversationId, title: item.title, isGroup: item.kind == .group, presenter: controller) }
    conversations.onAddRequested = { [weak self] controller in self?.showBusinessNotice(from: controller, title: "创建会话") }

    let contacts = PteIMUIContactListViewController(client: client, mode: isPreview ? .custom : .friends)
    if isPreview {
      contacts.contacts = [
        .init(identifier: "990022", title: "Alice Chen", subtitle: "在线 · Online", avatarText: "A", avatarBackgroundColor: .systemPink, sectionTitle: "Personal", isOnline: true),
        .init(identifier: "990023", title: "Bob Li", subtitle: "今天 10:30 · Today 10:30", avatarText: "B", avatarBackgroundColor: .systemTeal, sectionTitle: "Personal"),
        .init(identifier: "990024", title: "Carol Wu", subtitle: "在线 · Online", avatarText: "C", avatarBackgroundColor: .systemOrange, sectionTitle: "Personal", isOnline: true),
        .init(identifier: "990025", title: "Dave Zhang", subtitle: "昨天 · Yesterday", avatarText: "D", avatarBackgroundColor: .systemIndigo, sectionTitle: "Personal"),
        .init(identifier: "990026", title: "Eve Wang", subtitle: "在线 · Online", avatarText: "E", avatarBackgroundColor: .systemGreen, sectionTitle: "Personal", isOnline: true),
        .init(identifier: "990027", kind: .group, title: "Work Team 工作群", subtitle: "8 members · 刚刚 Just now", avatarText: "#", avatarBackgroundColor: .systemTeal, sectionTitle: "Groups"),
        .init(identifier: "990028", kind: .group, title: "Family 家庭群", subtitle: "5 members · 今天 Today", avatarText: "#", avatarBackgroundColor: .systemGreen, sectionTitle: "Groups")
      ]
    }
    contacts.onContactSelected = { [weak self] item, controller in self?.openChat(conversationId: item.identifier, title: item.title, isGroup: item.kind == .group, presenter: controller) }
    contacts.onAddRequested = { [weak self] controller in
      guard let self else { return }
      if let onAddDemoFriend = self.onAddDemoFriend { onAddDemoFriend(controller) }
      else { self.showBusinessNotice(from: controller, title: "添加好友 / 发起群聊") }
    }

    let me = PteIMUIDemoMeViewController(client: client, onLogout: onLogout)
    let conversationNav = UINavigationController(rootViewController: conversations)
    let contactNav = UINavigationController(rootViewController: contacts)
    let meNav = UINavigationController(rootViewController: me)
    [conversationNav, contactNav, meNav].forEach { $0.navigationBar.prefersLargeTitles = false }
    let language = client.resolvedLanguage()
    conversationNav.tabBarItem = makeTabItem(
      title: PteIMUILocalization.value("会话", "Chats", language: language),
      normalArtwork: "PteIMUITabChatsSelected",
      selectedArtwork: "PteIMUITabChatsSelected"
    )
    conversationNav.tabBarItem.badgeValue = isPreview ? "7" : nil
    contactNav.tabBarItem = makeTabItem(
      title: PteIMUILocalization.value("联系人", "Contacts", language: language),
      normalArtwork: "PteIMUITabContactsNormal",
      selectedArtwork: "PteIMUITabContactsSelected"
    )
    meNav.tabBarItem = makeTabItem(
      title: PteIMUILocalization.value("我的", "Me", language: language),
      normalArtwork: "PteIMUITabMeNormal",
      selectedArtwork: "PteIMUITabMeSelected"
    )
    viewControllers = [conversationNav, contactNav, meNav]
    tabBar.tintColor = UIColor(red: 0.48, green: 0.20, blue: 0.95, alpha: 1)
    tabBar.unselectedItemTintColor = UIColor(red: 0.40, green: 0.43, blue: 0.52, alpha: 1)
    applyTabBarAppearance()
  }

  override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
    super.traitCollectionDidChange(previousTraitCollection)
    if previousTraitCollection?.userInterfaceStyle != traitCollection.userInterfaceStyle {
      applyTabBarAppearance()
    }
  }

  private func applyTabBarAppearance() {
    let dark = client.resolvedTheme() == .dark
    let appearance = UITabBarAppearance()
    appearance.configureWithOpaqueBackground()
    appearance.backgroundColor = dark ? UIColor(red: 0.05, green: 0.045, blue: 0.15, alpha: 1) : .white
    appearance.shadowColor = dark ? UIColor(red: 0.15, green: 0.13, blue: 0.30, alpha: 1) : UIColor(red: 0.88, green: 0.87, blue: 0.98, alpha: 1)
    let normalColor = dark ? UIColor(red: 0.61, green: 0.60, blue: 0.72, alpha: 1) : UIColor(red: 0.40, green: 0.43, blue: 0.52, alpha: 1)
    let selectedColor = UIColor(red: 0.48, green: 0.20, blue: 0.95, alpha: 1)
    appearance.stackedLayoutAppearance.normal.iconColor = normalColor
    appearance.stackedLayoutAppearance.normal.titleTextAttributes = [.foregroundColor: normalColor]
    appearance.stackedLayoutAppearance.selected.iconColor = selectedColor
    appearance.stackedLayoutAppearance.selected.titleTextAttributes = [.foregroundColor: selectedColor]
    tabBar.standardAppearance = appearance
    tabBar.scrollEdgeAppearance = appearance
  }

  /** Uses the supplied @3x PNG cuts. UIKit applies normal/selected tinting. */
  private func makeTabItem(title: String, normalArtwork: String, selectedArtwork: String) -> UITabBarItem {
    let item = UITabBarItem(
      title: title,
      image: PteIMUIDemoAssets.image(named: normalArtwork)?.withRenderingMode(.alwaysTemplate),
      selectedImage: PteIMUIDemoAssets.image(named: selectedArtwork)?.withRenderingMode(.alwaysTemplate)
    )
    item.imageInsets = .zero
    item.titlePositionAdjustment = .zero
    return item
  }

  private func applyTabTitles() {
    guard let navigationControllers = viewControllers as? [UINavigationController], navigationControllers.count == 3 else { return }
    let language = client.resolvedLanguage()
    navigationControllers[0].tabBarItem.title = PteIMUILocalization.value("会话", "Chats", language: language)
    navigationControllers[1].tabBarItem.title = PteIMUILocalization.value("联系人", "Contacts", language: language)
    navigationControllers[2].tabBarItem.title = PteIMUILocalization.value("我的", "Me", language: language)
  }

  override func viewDidAppear(_ animated: Bool) {
    super.viewDidAppear(animated)
    #if DEBUG
    guard isPreview else { return }
    let arguments = ProcessInfo.processInfo.arguments
    if arguments.contains("--pte-im-ui-preview-me") {
      selectedIndex = 2
    } else if arguments.contains("--pte-im-ui-preview-contacts") {
      selectedIndex = 1
    } else if arguments.contains("--pte-im-ui-preview-chat"), !didOpenPreviewChat,
              let navigation = viewControllers?.first as? UINavigationController,
              let conversation = navigation.viewControllers.first as? PteIMUIConversationListViewController {
      didOpenPreviewChat = true
      let panelPreview = arguments.contains("--pte-im-ui-preview-chat-emoji") || arguments.contains("--pte-im-ui-preview-chat-more")
      let groupPreview = panelPreview || arguments.contains("--pte-im-ui-preview-chat-group")
      openChat(conversationId: groupPreview ? "990024" : "990022", title: groupPreview ? "Work Team 工作群" : "Alice Chen", isGroup: groupPreview, presenter: conversation)
    }
    #endif
  }

  private func openChat(conversationId: String, title: String, isGroup: Bool = false, presenter: UIViewController) {
    let chat = PteIMUIChatViewController(client: client, conversationId: conversationId, title: title)
    chat.showsIncomingSenderNames = isGroup
    chat.senderDisplayNameProvider = { message in
      switch message.senderId {
      case "A": return "Alice Chen"
      case "W": return "Work Team 工作群"
      default: return message.senderId
      }
    }
    if isPreview {
      chat.isOutgoing = { $0.senderId == "M" }
      chat.reactionProvider = { message in
        guard message.type == .text else { return [] }
        if message.senderId == "A" { return [.init(emoji: "😂", count: 3), .init(emoji: "👍", count: 2)] }
        return [.init(emoji: "❤️", count: 1)]
      }
      let mediaFocus = ProcessInfo.processInfo.arguments.contains("--pte-im-ui-preview-chat-media")
      let voiceFocus = ProcessInfo.processInfo.arguments.contains("--pte-im-ui-preview-chat-voice")
      let panelFocus = ProcessInfo.processInfo.arguments.contains("--pte-im-ui-preview-chat-emoji") || ProcessInfo.processInfo.arguments.contains("--pte-im-ui-preview-chat-more")
      if panelFocus { chat.navigationSubtitleText = "8 members" }
      PteIMUIDemoPreviewMessages.install(into: chat, conversationId: conversationId, mediaFocus: mediaFocus, voiceFocus: voiceFocus, panelFocus: panelFocus)
      let arguments = ProcessInfo.processInfo.arguments
      // Wait until the pushed chat has laid out its input bar. Opening a
      // panel before the navigation transition completes can be overwritten
      // by the input bar's initial layout pass in a launch preview.
      if arguments.contains("--pte-im-ui-preview-chat-emoji") {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { chat.openEmojiPanel() }
      }
      if arguments.contains("--pte-im-ui-preview-chat-more") {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { chat.openMorePanel() }
      }
    }
    chat.onActionRequested = { [weak self] action, controller in self?.showBusinessNotice(from: controller, title: action.title(language: self?.client.appearance.language ?? .zhCN)) }
    chat.onVoiceRecordingChanged = { recording, controller in controller.navigationItem.prompt = recording ? "正在录音…" : nil }
    presenter.navigationController?.pushViewController(chat, animated: true)
  }
  private func showBusinessNotice(from controller: UIViewController, title: String) {
    let alert = UIAlertController(title: title, message: "该入口由业务层实现；PteIMUIKit 负责展示、回调和消息收发。", preferredStyle: .alert)
    alert.addAction(UIAlertAction(title: "确定", style: .default)); controller.present(alert, animated: true)
  }
}

private final class PteIMUIDemoLegacyMeViewController: UIViewController {
  private let client: PteIMSDK
  private let onLogout: () -> Void
  private let colors = (background: UIColor(red: 0.94, green: 0.94, blue: 1, alpha: 1), text: UIColor(red: 0.10, green: 0.11, blue: 0.22, alpha: 1), muted: UIColor(red: 0.39, green: 0.42, blue: 0.53, alpha: 1), accent: UIColor(red: 0.47, green: 0.20, blue: 0.95, alpha: 1))
  init(client: PteIMSDK, onLogout: @escaping () -> Void) { self.client = client; self.onLogout = onLogout; super.init(nibName: nil, bundle: nil) }
  required init?(coder: NSCoder) { nil }
  override func viewDidLoad() {
    super.viewDidLoad(); navigationItem.largeTitleDisplayMode = .never; view.backgroundColor = colors.background
    let scroll = UIScrollView(); scroll.alwaysBounceVertical = true; scroll.showsVerticalScrollIndicator = false
    let content = UIStackView(); content.axis = .vertical; content.spacing = 0
    [scroll, content].forEach { $0.translatesAutoresizingMaskIntoConstraints = false }; view.addSubview(scroll); scroll.addSubview(content)
    NSLayoutConstraint.activate([scroll.leadingAnchor.constraint(equalTo: view.leadingAnchor), scroll.trailingAnchor.constraint(equalTo: view.trailingAnchor), scroll.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor), scroll.bottomAnchor.constraint(equalTo: view.bottomAnchor), content.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor), content.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor), content.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor), content.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor), content.widthAnchor.constraint(equalTo: scroll.frameLayoutGuide.widthAnchor)])
    content.addArrangedSubview(header())
    content.addArrangedSubview(profileBanner())
    content.addArrangedSubview(quickActions())
    let settings = UIStackView(); settings.axis = .vertical; settings.spacing = 0; settings.backgroundColor = colors.background; settings.isLayoutMarginsRelativeArrangement = true; settings.directionalLayoutMargins = .init(top: 18, leading: 20, bottom: 16, trailing: 20)
    settings.addArrangedSubview(settingRow(icon: "sun.max", title: "Light Mode", accessory: themeSwitch()))
    settings.addArrangedSubview(settingRow(icon: "globe", title: "Language", accessory: languageBadge()))
    settings.addArrangedSubview(settingRow(icon: "bell", title: "Notifications"))
    settings.addArrangedSubview(settingRow(icon: "shield", title: "Privacy & Security"))
    settings.addArrangedSubview(settingRow(icon: "questionmark.circle", title: "Help & Feedback"))
    settings.addArrangedSubview(settingRow(icon: "gearshape", title: "Settings"))
    content.addArrangedSubview(settings)
    let logout = UIButton(type: .system); logout.setTitle("⇥  Log Out", for: .normal); logout.setTitleColor(.systemRed, for: .normal); logout.titleLabel?.font = .systemFont(ofSize: 15, weight: .semibold); logout.backgroundColor = UIColor.systemRed.withAlphaComponent(0.12); logout.layer.cornerRadius = 16; logout.addTarget(self, action: #selector(logoutTapped), for: .touchUpInside); logout.heightAnchor.constraint(equalToConstant: 48).isActive = true
    let logoutWrap = UIView(); logoutWrap.backgroundColor = colors.background; logoutWrap.addSubview(logout); logout.translatesAutoresizingMaskIntoConstraints = false; NSLayoutConstraint.activate([logout.leadingAnchor.constraint(equalTo: logoutWrap.leadingAnchor, constant: 20), logout.trailingAnchor.constraint(equalTo: logoutWrap.trailingAnchor, constant: -20), logout.topAnchor.constraint(equalTo: logoutWrap.topAnchor, constant: 12), logout.bottomAnchor.constraint(equalTo: logoutWrap.bottomAnchor, constant: -50)])
    content.addArrangedSubview(logoutWrap)
  }
  override func viewWillAppear(_ animated: Bool) { super.viewWillAppear(animated); navigationController?.setNavigationBarHidden(true, animated: animated) }
  private func header() -> UIView {
    let row = UIStackView(); row.axis = .horizontal; row.alignment = .center; row.spacing = 12; row.isLayoutMarginsRelativeArrangement = true; row.directionalLayoutMargins = .init(top: 12, leading: 20, bottom: 12, trailing: 20); row.backgroundColor = .systemBackground
    let logo = UIImageView(image: UIImage(named: "PteIMUILogo")); logo.contentMode = .scaleAspectFit; logo.layer.cornerRadius = 16; logo.clipsToBounds = true; logo.widthAnchor.constraint(equalToConstant: 32).isActive = true; logo.heightAnchor.constraint(equalToConstant: 32).isActive = true
    let title = UILabel(); title.text = "Me"; title.font = .systemFont(ofSize: 20, weight: .bold); title.textColor = colors.text
    let moon = iconButton("moon", #selector(toggleTheme)); let language = iconButton("globe", #selector(toggleLanguage)); let add = iconButton("plus", nil)
    row.addArrangedSubview(logo); row.addArrangedSubview(title); row.addArrangedSubview(UIView()); row.addArrangedSubview(moon); row.addArrangedSubview(language); row.addArrangedSubview(add)
    return row
  }
  private func profileBanner() -> UIView {
    let panel = UIView(); let gradient = CAGradientLayer(); gradient.frame = UIScreen.main.bounds; gradient.colors = [UIColor(red: 0.87, green: 0.88, blue: 1, alpha: 1).cgColor, UIColor(red: 0.82, green: 0.91, blue: 1, alpha: 1).cgColor]; gradient.startPoint = CGPoint(x: 0, y: 0); gradient.endPoint = CGPoint(x: 1, y: 1); panel.layer.insertSublayer(gradient, at: 0); panel.layer.cornerRadius = 0; panel.clipsToBounds = true
    let avatar = UILabel(); avatar.text = "我"; avatar.textAlignment = .center; avatar.textColor = .white; avatar.font = .systemFont(ofSize: 24, weight: .bold); avatar.layer.cornerRadius = 16; avatar.clipsToBounds = true; avatar.backgroundColor = UIColor(red: 0.24, green: 0.47, blue: 0.97, alpha: 1)
    let name = UILabel(); name.text = "User_\(client.currentUserId)"; name.font = .systemFont(ofSize: 17, weight: .bold); name.textColor = colors.text
    let identifier = UILabel(); identifier.text = "ID: usr_\(client.currentUserId)"; identifier.font = .systemFont(ofSize: 11); identifier.textColor = colors.muted
    let copy = UIStackView(arrangedSubviews: [name, identifier]); copy.axis = .vertical; copy.spacing = 5
    let chevron = UIImageView(image: UIImage(systemName: "chevron.right")); chevron.tintColor = colors.muted
    [avatar, copy, chevron].forEach { $0.translatesAutoresizingMaskIntoConstraints = false; panel.addSubview($0) }
    NSLayoutConstraint.activate([panel.heightAnchor.constraint(equalToConstant: 112), avatar.leadingAnchor.constraint(equalTo: panel.leadingAnchor, constant: 20), avatar.centerYAnchor.constraint(equalTo: panel.centerYAnchor), avatar.widthAnchor.constraint(equalToConstant: 64), avatar.heightAnchor.constraint(equalTo: avatar.widthAnchor), copy.leadingAnchor.constraint(equalTo: avatar.trailingAnchor, constant: 16), copy.centerYAnchor.constraint(equalTo: panel.centerYAnchor), chevron.trailingAnchor.constraint(equalTo: panel.trailingAnchor, constant: -28), chevron.centerYAnchor.constraint(equalTo: panel.centerYAnchor)])
    return panel
  }
  private func quickActions() -> UIView {
    let row = UIStackView(); row.axis = .horizontal; row.distribution = .fillEqually; row.backgroundColor = .systemBackground
    [("star", "12", "Favorites"), ("creditcard", "¥88", "Wallet"), ("qrcode", "", "QR Card")].forEach { symbol, value, title in
      let icon = UIImageView(image: UIImage(systemName: symbol)); icon.tintColor = colors.accent; icon.contentMode = .scaleAspectFit; icon.preferredSymbolConfiguration = .init(pointSize: 19, weight: .medium)
      let number = UILabel(); number.text = value; number.textAlignment = .center; number.font = .systemFont(ofSize: 13, weight: .semibold); number.textColor = colors.text
      let caption = UILabel(); caption.text = title; caption.textAlignment = .center; caption.font = .systemFont(ofSize: 10); caption.textColor = colors.muted
      let stack = UIStackView(arrangedSubviews: [icon, number, caption]); stack.axis = .vertical; stack.alignment = .center; stack.spacing = 4; stack.isLayoutMarginsRelativeArrangement = true; stack.directionalLayoutMargins = .init(top: 16, leading: 0, bottom: 16, trailing: 0); row.addArrangedSubview(stack)
    }
    row.heightAnchor.constraint(equalToConstant: 96).isActive = true; return row
  }
  private func settingRow(icon: String, title: String, accessory: UIView? = nil) -> UIView {
    let row = UIStackView(); row.axis = .horizontal; row.alignment = .center; row.spacing = 14; row.backgroundColor = colors.background
    let image = UIImageView(image: UIImage(systemName: icon)); image.tintColor = colors.accent; image.preferredSymbolConfiguration = .init(pointSize: 18, weight: .regular); image.widthAnchor.constraint(equalToConstant: 20).isActive = true
    let label = UILabel(); label.text = title; label.font = .systemFont(ofSize: 15, weight: .medium); label.textColor = colors.text
    row.addArrangedSubview(image); row.addArrangedSubview(label); row.addArrangedSubview(UIView()); row.addArrangedSubview(accessory ?? UIImageView(image: UIImage(systemName: "chevron.right")))
    let wrap = UIView(); wrap.addSubview(row); row.translatesAutoresizingMaskIntoConstraints = false; NSLayoutConstraint.activate([row.leadingAnchor.constraint(equalTo: wrap.leadingAnchor), row.trailingAnchor.constraint(equalTo: wrap.trailingAnchor), row.topAnchor.constraint(equalTo: wrap.topAnchor), row.bottomAnchor.constraint(equalTo: wrap.bottomAnchor), wrap.heightAnchor.constraint(equalToConstant: 54)])
    return wrap
  }
  private func themeSwitch() -> UISwitch { let control = UISwitch(); control.isOn = client.appearance.themeMode != .dark; control.onTintColor = colors.accent; control.addTarget(self, action: #selector(themeSwitchChanged(_:)), for: .valueChanged); return control }
  private func languageBadge() -> UILabel { let label = UILabel(); label.text = client.appearance.language == .enUS ? "EN" : "中文"; label.textAlignment = .center; label.font = .systemFont(ofSize: 12, weight: .semibold); label.textColor = colors.accent; label.backgroundColor = colors.accent.withAlphaComponent(0.12); label.layer.cornerRadius = 15; label.clipsToBounds = true; label.widthAnchor.constraint(equalToConstant: 48).isActive = true; label.heightAnchor.constraint(equalToConstant: 30).isActive = true; return label }
  private func iconButton(_ name: String, _ action: Selector?) -> UIButton { let button = UIButton(type: .system); button.setImage(UIImage(systemName: name), for: .normal); button.tintColor = colors.muted; button.widthAnchor.constraint(equalToConstant: 30).isActive = true; if let action { button.addTarget(self, action: action, for: .touchUpInside) }; return button }
  @objc private func toggleTheme() { let next: PteIMThemeMode = client.appearance.themeMode == .dark ? .light : .dark; client.updateAppearance(themeMode: next); overrideUserInterfaceStyle = next == .dark ? .dark : .light }
  @objc private func toggleLanguage() { let next: PteIMLanguage = client.appearance.language == .enUS ? .zhCN : .enUS; client.updateAppearance(language: next); view.subviews.forEach { $0.removeFromSuperview() }; viewDidLoad() }
  @objc private func themeSwitchChanged(_ control: UISwitch) { client.updateAppearance(themeMode: control.isOn ? .light : .dark); overrideUserInterfaceStyle = control.isOn ? .light : .dark }
  @objc private func logoutTapped() { onLogout() }
}

@MainActor private enum PteIMUIDemoPreviewMessages {
  static func install(into chat: PteIMUIChatViewController, conversationId: String, mediaFocus: Bool = false, voiceFocus: Bool = false, panelFocus: Bool = false) {
    let now = Int64(Date().timeIntervalSince1970 * 1000)
    if mediaFocus {
      chat.append(message: .init(conversationId: conversationId, senderId: "A", type: .text, text: "这里是我们约见的位置。", createdAt: now - 90_000, state: .sent))
      chat.append(message: .init(conversationId: conversationId, senderId: "A", type: .location, location: .init(latitude: 31.2304, longitude: 121.4737, name: "上海市浦东新区张江科技园", address: "Zhangjiang Hi-Tech Park, Pudong"), createdAt: now - 60_000, state: .sent))
      chat.append(message: .init(conversationId: conversationId, senderId: "M", type: .image, media: .init(width: 1080, height: 1350, fileName: "PteIMUIKit Preview"), createdAt: now - 20_000, state: .sent))
      return
    }
    if voiceFocus {
      chat.append(message: .init(conversationId: conversationId, senderId: "A", type: .voice, voice: .init(url: "preview/incoming-voice.m4a", durationMs: 8_000), createdAt: now - 20_000, state: .sent))
      chat.append(message: .init(conversationId: conversationId, senderId: "M", type: .voice, voice: .init(url: "preview/outgoing-voice.m4a", durationMs: 15_000), createdAt: now - 8_000, state: .sent))
      return
    }
    if panelFocus {
      chat.append(message: .init(conversationId: conversationId, senderId: "A", type: .text, text: "你好！在吗？ Hey!\nAre you there?", createdAt: now - 220_000, state: .sent))
      chat.append(message: .init(conversationId: conversationId, senderId: "M", type: .text, text: "在的，什么事？\nYes, what's up?", createdAt: now - 180_000, state: .sent))
      chat.append(message: .init(conversationId: conversationId, senderId: "A", type: .text, text: "我发个图片给你看，待会儿来这里。\nI'll share my location, come here later.", createdAt: now - 120_000, state: .sent))
      chat.append(message: .init(conversationId: conversationId, senderId: "M", type: .image, media: .init(width: 1080, height: 1350, fileName: "PteIMUIKit Preview"), createdAt: now - 80_000, state: .sent))
      return
    }
    chat.append(message: .init(conversationId: conversationId, senderId: "A", type: .text, text: "你好！在吗？ Hey!\nAre you there?", createdAt: now - 220_000, state: .sent))
    chat.append(message: .init(conversationId: conversationId, senderId: "M", type: .text, text: "在的，什么事？\nYes, what's up?", createdAt: now - 180_000, state: .sent))
    chat.append(message: .init(conversationId: conversationId, senderId: "A", type: .emoji, text: "🎉", createdAt: now - 160_000, state: .sent))
    chat.append(message: .init(conversationId: conversationId, senderId: "A", type: .location, location: .init(latitude: 31.2304, longitude: 121.4737, name: "上海市浦东新区张江科技园", address: "Zhangjiang Hi-Tech Park, Pudong"), createdAt: now - 120_000, state: .sent))
    chat.append(message: .init(conversationId: conversationId, senderId: "M", type: .image, media: .init(width: 1080, height: 1350, fileName: "聊天图片预览"), createdAt: now - 105_000, state: .sent))
    chat.append(message: .init(conversationId: conversationId, senderId: "A", type: .video, media: .init(durationMs: 32_000, fileName: "产品功能介绍"), createdAt: now - 80_000, state: .sent))
    chat.append(message: .init(conversationId: conversationId, senderId: "M", type: .voice, voice: .init(url: "preview/voice.m4a", durationMs: 15_000), createdAt: now - 60_000, state: .sent))
    chat.append(message: .init(conversationId: conversationId, senderId: "M", type: .red_packet, business: .init(businessId: "preview-packet-1", title: "Alice", subtitle: "恭喜发财，大吉大利"), createdAt: now - 40_000, state: .sent))
    chat.append(message: .init(conversationId: conversationId, senderId: "A", type: .gift, business: .init(businessId: "preview-gift-1", title: "Alice", subtitle: "星光礼盒 · 送给你"), createdAt: now - 34_000, state: .sent))
    chat.append(message: .init(conversationId: conversationId, senderId: "A", type: .order, business: .init(businessId: "preview-order-1", title: "iPhone 15 Pro 256GB 深空黑色", subtitle: "¥8,999"), createdAt: now - 20_000, state: .sent))
    chat.append(message: .init(conversationId: conversationId, senderId: "A", type: .file, media: .init(sizeBytes: 2_400_000, fileName: "活动方案.pdf", mimeType: "PDF · 2.4 MB"), createdAt: now - 12_000, state: .sent))
    chat.append(message: .init(conversationId: conversationId, senderId: "M", type: .text, text: "收到，稍后处理！Got it, I'll handle it shortly!", createdAt: now - 4_000, state: .pending))
  }
}

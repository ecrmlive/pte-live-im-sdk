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
  private let isPreview: Bool
  #if DEBUG
  private var didOpenPreviewChat = false
  #endif

  init(client: PteIMSDK, isPreview: Bool = false, onLogout: @escaping () -> Void) {
    self.client = client; self.isPreview = isPreview; self.onLogout = onLogout
    super.init(nibName: nil, bundle: nil)
  }
  required init?(coder: NSCoder) { nil }

  override func viewDidLoad() {
    super.viewDidLoad()
    let conversations = PteIMUIConversationListViewController(client: client)
    if isPreview {
      let now = Date()
      conversations.hostPresentations = [
        .init(conversationId: "990022", title: "Alice Chen", subtitle: "好的，明天见！See you tomorrow!", avatarText: "A", avatarBackgroundColor: .systemPink, unreadCount: 2, updatedAt: now),
        .init(conversationId: "990023", title: "Bob Li", subtitle: "视频已发送 · Video sent", avatarText: "B", avatarBackgroundColor: .systemTeal, updatedAt: now.addingTimeInterval(-240)),
        .init(conversationId: "990024", kind: .group, title: "Pte Live Design", subtitle: "Carol: 新版设计已更新", avatarText: "P", avatarBackgroundColor: .systemOrange, unreadCount: 5, updatedAt: now.addingTimeInterval(-1_200)),
        .init(conversationId: "990025", title: "David Zhang", subtitle: "[语音] 00:15", avatarText: "D", avatarBackgroundColor: .systemIndigo, updatedAt: now.addingTimeInterval(-3_600)),
        .init(conversationId: "990026", title: "Eve Wang", subtitle: "订单已确认", avatarText: "E", avatarBackgroundColor: .systemGreen, updatedAt: now.addingTimeInterval(-86_400))
      ]
    }
    conversations.onConversationSelected = { [weak self] item, controller in self?.openChat(conversationId: item.conversationId, title: item.title, presenter: controller) }
    conversations.onAddRequested = { [weak self] controller in self?.showBusinessNotice(from: controller, title: "创建会话") }

    let contacts = PteIMUIContactListViewController(client: client, mode: isPreview ? .custom : .friends)
    if isPreview {
      contacts.contacts = [
        .init(identifier: "990022", title: "Alice Chen", subtitle: "在线 · Online", avatarText: "A", avatarBackgroundColor: .systemPink),
        .init(identifier: "990023", title: "Bob Li", subtitle: "今天 10:30 · Today 10:30", avatarText: "B", avatarBackgroundColor: .systemTeal),
        .init(identifier: "990024", title: "Carol Wu", subtitle: "在线 · Online", avatarText: "C", avatarBackgroundColor: .systemOrange),
        .init(identifier: "990025", title: "Dave Zhang", subtitle: "昨天 · Yesterday", avatarText: "D", avatarBackgroundColor: .systemIndigo),
        .init(identifier: "990026", title: "Eve Wang", subtitle: "在线 · Online", avatarText: "E", avatarBackgroundColor: .systemGreen)
      ]
    }
    contacts.onContactSelected = { [weak self] item, controller in self?.openChat(conversationId: item.identifier, title: item.title, presenter: controller) }
    contacts.onAddRequested = { [weak self] controller in self?.showBusinessNotice(from: controller, title: "添加好友 / 发起群聊") }

    let me = PteIMUIDemoMeViewController(client: client, onLogout: onLogout)
    let conversationNav = UINavigationController(rootViewController: conversations)
    let contactNav = UINavigationController(rootViewController: contacts)
    let meNav = UINavigationController(rootViewController: me)
    [conversationNav, contactNav, meNav].forEach { $0.navigationBar.prefersLargeTitles = false }
    conversationNav.tabBarItem = UITabBarItem(title: "Chats", image: UIImage(systemName: "bubble.left.and.bubble.right"), selectedImage: UIImage(systemName: "bubble.left.and.bubble.right.fill"))
    contactNav.tabBarItem = UITabBarItem(title: "Contacts", image: UIImage(systemName: "person.2"), selectedImage: UIImage(systemName: "person.2.fill"))
    meNav.tabBarItem = UITabBarItem(title: "Me", image: UIImage(systemName: "person"), selectedImage: UIImage(systemName: "person.fill"))
    viewControllers = [conversationNav, contactNav, meNav]
    tabBar.tintColor = UIColor(red: 0.48, green: 0.20, blue: 0.95, alpha: 1)
    tabBar.unselectedItemTintColor = UIColor(red: 0.40, green: 0.43, blue: 0.52, alpha: 1)
  }

  override func viewDidAppear(_ animated: Bool) {
    super.viewDidAppear(animated)
    #if DEBUG
    guard isPreview else { return }
    let arguments = ProcessInfo.processInfo.arguments
    if arguments.contains("--pte-im-ui-preview-contacts") {
      selectedIndex = 1
    } else if arguments.contains("--pte-im-ui-preview-chat"), !didOpenPreviewChat,
              let navigation = viewControllers?.first as? UINavigationController,
              let conversation = navigation.viewControllers.first as? PteIMUIConversationListViewController {
      didOpenPreviewChat = true
      openChat(conversationId: "990022", title: "Alice Chen", presenter: conversation)
    }
    #endif
  }

  private func openChat(conversationId: String, title: String, presenter: UIViewController) {
    let chat = PteIMUIChatViewController(client: client, conversationId: conversationId, title: title)
    if isPreview {
      chat.isOutgoing = { $0.senderId == "M" }
      PteIMUIDemoPreviewMessages.install(into: chat, conversationId: conversationId)
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

private final class PteIMUIDemoMeViewController: UIViewController {
  private let client: PteIMSDK
  private let onLogout: () -> Void
  init(client: PteIMSDK, onLogout: @escaping () -> Void) { self.client = client; self.onLogout = onLogout; super.init(nibName: nil, bundle: nil) }
  required init?(coder: NSCoder) { nil }
  override func viewDidLoad() {
    super.viewDidLoad(); title = "Me"; view.backgroundColor = UIColor(red: 0.94, green: 0.94, blue: 1, alpha: 1)
    let avatar = UILabel(); avatar.text = "P"; avatar.textAlignment = .center; avatar.textColor = .white; avatar.font = .systemFont(ofSize: 28, weight: .bold); avatar.backgroundColor = UIColor(red: 0.48, green: 0.20, blue: 0.95, alpha: 1); avatar.layer.cornerRadius = 34; avatar.clipsToBounds = true
    let name = UILabel(); name.text = client.currentUserId; name.font = .systemFont(ofSize: 21, weight: .bold)
    let caption = UILabel(); caption.text = "Pte Live IM"; caption.textColor = .secondaryLabel; caption.font = .systemFont(ofSize: 13)
    let profile = UIStackView(arrangedSubviews: [avatar, name, caption]); profile.axis = .vertical; profile.alignment = .center; profile.spacing = 6
    avatar.widthAnchor.constraint(equalToConstant: 68).isActive = true; avatar.heightAnchor.constraint(equalToConstant: 68).isActive = true
    let logout = UIButton(type: .system); logout.setTitle("退出登录", for: .normal); logout.setTitleColor(.systemRed, for: .normal); logout.titleLabel?.font = .systemFont(ofSize: 16, weight: .semibold); logout.backgroundColor = .systemBackground; logout.layer.cornerRadius = 16; logout.addTarget(self, action: #selector(logoutTapped), for: .touchUpInside)
    [profile, logout].forEach { $0.translatesAutoresizingMaskIntoConstraints = false; view.addSubview($0) }
    NSLayoutConstraint.activate([
      profile.centerXAnchor.constraint(equalTo: view.centerXAnchor), profile.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 46),
      logout.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20), logout.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20), logout.topAnchor.constraint(equalTo: profile.bottomAnchor, constant: 42), logout.heightAnchor.constraint(equalToConstant: 52)
    ])
  }
  @objc private func logoutTapped() { onLogout() }
}

@MainActor private enum PteIMUIDemoPreviewMessages {
  static func install(into chat: PteIMUIChatViewController, conversationId: String) {
    let now = Int64(Date().timeIntervalSince1970 * 1000)
    chat.append(message: .init(conversationId: conversationId, senderId: "A", type: .text, text: "你好！在吗？ Hey!\nAre you there?", createdAt: now - 220_000, state: .sent))
    chat.append(message: .init(conversationId: conversationId, senderId: "M", type: .text, text: "在的，什么事？\nYes, what's up?", createdAt: now - 180_000, state: .sent))
    chat.append(message: .init(conversationId: conversationId, senderId: "A", type: .location, location: .init(latitude: 31.2304, longitude: 121.4737, name: "上海市浦东新区张江科技园", address: "Zhangjiang Hi-Tech Park, Pudong"), createdAt: now - 120_000, state: .sent))
    chat.append(message: .init(conversationId: conversationId, senderId: "M", type: .voice, voice: .init(url: "preview/voice.m4a", durationMs: 15_000), createdAt: now - 60_000, state: .sent))
    chat.append(message: .init(conversationId: conversationId, senderId: "A", type: .order, business: .init(businessId: "preview-order-1", title: "iPhone 15 Pro 256GB 深空黑色", subtitle: "¥8,999"), createdAt: now - 20_000, state: .sent))
  }
}

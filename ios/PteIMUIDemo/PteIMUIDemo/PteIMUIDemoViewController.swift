import UIKit
import ObjectiveC
import PteIMUIkit

/**
 `PteIMUIDemo` is an application-layer example. Its business service signs a user in and
 returns a short-lived IM credential; only then does it create PteIMSDK and present PteIMUIkit.
 */
final class PteIMUIDemoViewController: UIViewController {
  private let applicationSession: PteIMUIDemoApplicationSession
  private let appId = PteIMUIDemoViewController.field("", "SDK App ID returned by business login", keyboard: .numberPad)
  private let account = PteIMUIDemoViewController.field("demo-user", "Business account")
  private let password = PteIMUIDemoViewController.field("", "Business password (demo only)", secure: true)
  private let userId = PteIMUIDemoViewController.field("10001", "IM user ID returned by business login", keyboard: .numberPad)
  private let userSig = PteIMUIDemoViewController.field("", "Short-lived UserSig returned by business login", secure: true)
  private let conversationId = PteIMUIDemoViewController.field("", "Active conversation ID (set by IM service)")
  private let status = UILabel()
  private var client: PteIMSDK?
  private var friends = [PteIMUIDemoFriend(name: "Alice", userId: "10002"), PteIMUIDemoFriend(name: "Bob", userId: "10003")]
  private var configurationStack: UIStackView?
  #if DEBUG
  private var didRunAutomation = false
  private var didOpenLocalPreview = false
  #endif

  init(applicationSession: PteIMUIDemoApplicationSession) {
    self.applicationSession = applicationSession
    super.init(nibName: nil, bundle: nil)
  }
  required init?(coder: NSCoder) { nil }

  override func viewDidLoad() {
    super.viewDidLoad()
    title = "Pte Live IM"
    navigationItem.largeTitleDisplayMode = .never
    view.backgroundColor = .systemBackground
    conversationId.isEnabled = false
    account.text = "PteIMUIDemo"
    userId.text = ""
    userSig.text = ""

    let scrollView = UIScrollView(); scrollView.alwaysBounceVertical = true; scrollView.showsVerticalScrollIndicator = false
    let content = UIStackView(); content.axis = .vertical; content.spacing = 18
    view.addSubview(scrollView); scrollView.translatesAutoresizingMaskIntoConstraints = false
    scrollView.addSubview(content); content.translatesAutoresizingMaskIntoConstraints = false

    let hero = PteIMUIDemoHeroView()
    let eyebrow = PteIMUIDemoLabel("PTE LIVE · SECURE MESSAGING", style: .caption1, color: .secondaryLabel)
    let heading = PteIMUIDemoLabel("连接你的私域关系", style: .largeTitle, color: .label); heading.font = .systemFont(ofSize: 30, weight: .bold)
    let subtitle = PteIMUIDemoLabel("从业务登录到实时会话，一次完成 Core、UIkit 与加密消息链路验证。", style: .body, color: .secondaryLabel); subtitle.numberOfLines = 0
    let heroCopy = UIStackView(arrangedSubviews: [eyebrow, heading, subtitle]); heroCopy.axis = .vertical; heroCopy.spacing = 8

    let card = UIView(); card.backgroundColor = .secondarySystemBackground; card.layer.cornerRadius = 24
    let cardTitle = PteIMUIDemoLabel("快速开始", style: .title2, color: .label); cardTitle.font = .systemFont(ofSize: 21, weight: .bold)
    let cardNote = PteIMUIDemoLabel("自动申请短期测试 UserSig，不会保存凭据。", style: .footnote, color: .secondaryLabel)
    let demoLogin = PteIMUIDemoGradientButton(title: "使用测试账号进入 Demo")
    demoLogin.addTarget(self, action: #selector(demoLoginTapped), for: .touchUpInside)
    let preview = UIButton(type: .system); preview.setTitle("先查看 PteIMUIkit 视觉预览", for: .normal); preview.titleLabel?.font = .systemFont(ofSize: 15, weight: .semibold); preview.addTarget(self, action: #selector(previewTapped), for: .touchUpInside)
    status.font = .preferredFont(forTextStyle: .footnote); status.textColor = .secondaryLabel; status.textAlignment = .center; status.numberOfLines = 0; status.text = "准备就绪"

    let configToggle = UIButton(type: .system); configToggle.setTitle("手动登录凭据", for: .normal); configToggle.setImage(UIImage(systemName: "person.badge.key"), for: .normal); configToggle.tintColor = .systemIndigo; configToggle.addTarget(self, action: #selector(toggleConfiguration), for: .touchUpInside)
    let login = UIButton(type: .system); login.setTitle("使用手动凭据登录", for: .normal); login.addTarget(self, action: #selector(loginTapped), for: .touchUpInside)
    let note = PteIMUIDemoLabel("生产环境应由你的业务后端返回 userId 与短期 UserSig；Demo 的测试入口仅用于本地开发验证。", style: .footnote, color: .secondaryLabel); note.numberOfLines = 0
    let config = UIStackView(arrangedSubviews: [appId, userId, userSig, login, note]); config.axis = .vertical; config.spacing = 10; config.isHidden = true
    configurationStack = config
    let cardStack = UIStackView(arrangedSubviews: [cardTitle, cardNote, demoLogin, preview, status, configToggle, config]); cardStack.axis = .vertical; cardStack.spacing = 13
    card.addSubview(cardStack); cardStack.translatesAutoresizingMaskIntoConstraints = false
    NSLayoutConstraint.activate([cardStack.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 18), cardStack.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -18), cardStack.topAnchor.constraint(equalTo: card.topAnchor, constant: 20), cardStack.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -20), demoLogin.heightAnchor.constraint(equalToConstant: 52)])

    let privacy = PteIMUIDemoLabel("端到端加密 · SQLite 本地缓存 · 亮/暗模式", style: .footnote, color: .tertiaryLabel); privacy.textAlignment = .center
    content.addArrangedSubview(hero); content.addArrangedSubview(heroCopy); content.addArrangedSubview(card); content.addArrangedSubview(privacy)
    NSLayoutConstraint.activate([
      scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor), scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
      scrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor), scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
      content.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor, constant: 22), content.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor, constant: -22),
      content.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor, constant: 22), content.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor, constant: -28),
      content.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor, constant: -44),
      hero.heightAnchor.constraint(equalToConstant: 168)
    ])
  }

  @objc private func toggleConfiguration() {
    configurationStack?.isHidden.toggle()
    UIView.animate(withDuration: 0.24) { self.view.layoutIfNeeded() }
  }

  /** Obtains an ephemeral, server-issued UserSig for a non-persistent numeric test user. */
  @objc private func demoLoginTapped() {
    let endpoint = applicationSession.baseConfig.apiDomain.appendingPathComponent("api/v1/im/usersig")
    let testUserId = String(9_000_000_000 + Int64(Date().timeIntervalSince1970) % 900_000_000)
    status.text = "正在申请测试账号…"
    Task {
      do {
        var request = URLRequest(url: endpoint); request.httpMethod = "POST"; request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["app_id": 10001, "user_id": testUserId, "identifier": testUserId, "device_id": UIDevice.current.identifierForVendor?.uuidString ?? "ios-demo", "platform": "ios", "scene": "chat", "expire": 3600])
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { throw PteIMUIDemoLoginError.requestFailed }
        let result = try JSONDecoder().decode(PteIMUIDemoCredentialEnvelope.self, from: data)
        guard result.code == 1, let credential = result.data, !credential.userSig.isEmpty else { throw PteIMUIDemoLoginError.server(result.msg) }
        await MainActor.run {
          self.appId.text = credential.sdkAppId
          self.userId.text = credential.userId
          self.userSig.text = credential.userSig
          self.status.text = "测试账号 \(credential.userId) 已就绪，正在进入 IM…"
          self.loginTapped()
        }
      } catch {
        await MainActor.run { self.status.text = "无法申请测试签名：\(error.localizedDescription)" }
      }
    }
  }

  override func viewDidAppear(_ animated: Bool) {
    super.viewDidAppear(animated)
    #if DEBUG
    runAutomationIfRequested()
    if !didOpenLocalPreview && (ProcessInfo.processInfo.environment["PTE_IM_UI_DEMO_LOCAL_PREVIEW"] == "1" || ProcessInfo.processInfo.arguments.contains("--pte-im-ui-preview")) {
      didOpenLocalPreview = true
      previewTapped()
    }
    #endif
  }

  @objc private func loginTapped() {
    guard let session = PteIMUIDemoBusinessSession(account: account.text ?? "", userId: userId.text ?? "", userSig: userSig.text ?? "") else { status.text = "业务后端应返回 userId 与短期 UserSig"; return }
    do {
      let login = try PteIMLoginConfig(sdkAppId: Int64(appId.text ?? "") ?? 0, userId: session.userId, userSig: session.userSig)
      client = try applicationSession.bootstrap.login(login)
      showBusinessHome(session: session)
    } catch { status.text = "IM 登录失败：\(error.localizedDescription)" }
  }

  /** Local-only UIKit inspection route. It never uses a business credential or calls `start()`. */
  @objc private func previewTapped() {
    do {
      // A dedicated numeric account/conversation keeps visual fixtures separate
      // from the host's normal offline SQLite cache.
      let login = try PteIMLoginConfig(sdkAppId: 1, userId: "990021", userSig: "local-ui-preview")
      let previewClient = try PteIMSDK.preview(baseConfig: applicationSession.baseConfig, loginConfig: login)
      let chat = self.chat(client: previewClient, conversationId: "990210", title: "Alice")
      let now = Int64(Date().timeIntervalSince1970 * 1000)
      chat.append(message: PteIMMessage(conversationId: "990210", senderId: "990021", type: .text, text: "蓝紫渐变在暗色模式也很清晰。", createdAt: now - 120_000, state: .sent))
      chat.append(message: PteIMMessage(conversationId: "990210", senderId: "990022", type: .emoji, packageId: "default", emojiId: "heart_001", createdAt: now - 60_000, state: .sent))
      chat.append(message: PteIMMessage(conversationId: "990210", senderId: "990022", type: .location, location: PteIMLocation(latitude: 30.5728, longitude: 104.0668, name: "Pte Live 成都", address: "天府软件园"), createdAt: now - 15_000, state: .sent))
      navigationController?.pushViewController(chat, animated: true)
    } catch { status.text = "无法创建本地 UI 预览：\(error.localizedDescription)" }
  }

  private func showBusinessHome(session: PteIMUIDemoBusinessSession) {
    let home = UITableViewController(style: .insetGrouped); home.title = "PteIMUIDemo"
    let items = ["会话列表（PteIMUIkit）", "好友列表 / 关系", "群组聊天（PteIMUIkit）", "我的"]
    let dataSource = PteIMUIDemoMenuDataSource(items: items) { [weak self, weak home] index in
      guard let self, let home, let client = self.client else { return }
      switch index {
      case 0: home.navigationController?.pushViewController(PteIMUIkit.makeConversationListViewController(client: client), animated: true)
      case 1: home.navigationController?.pushViewController(self.friendListController(client: client), animated: true)
      case 2: self.openDemoGroupChat(client: client, presenter: home)
      default: home.navigationController?.pushViewController(self.profileController(session: session), animated: true)
      }
    }; home.tableView.dataSource = dataSource; home.tableView.delegate = dataSource; objc_setAssociatedObject(home, "PteIMUIDemoMenuDataSource", dataSource, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
    navigationController?.pushViewController(home, animated: true)
  }

  private func friendListController(client: PteIMSDK) -> UITableViewController {
    let list = UITableViewController(style: .insetGrouped); list.title = "好友列表 / 关系"
    let dataSource = PteIMUIDemoMenuDataSource(items: friends.map { "\($0.name) (\($0.userId))" }) { [weak self, weak list] index in
      guard let self, let list else { return }; let friend = self.friends[index]
      self.openSingleChat(client: client, peerUserId: Int64(friend.userId) ?? 0, title: friend.name, presenter: list)
    }; list.tableView.dataSource = dataSource; list.tableView.delegate = dataSource; objc_setAssociatedObject(list, "PteIMUIDemoFriendDataSource", dataSource, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
    return list
  }

  private func profileController(session: PteIMUIDemoBusinessSession) -> UIViewController {
    let controller = UIViewController(); controller.title = "我的"; controller.view.backgroundColor = .systemBackground
    let label = UILabel(); label.numberOfLines = 0; label.text = "业务账号：\(session.account)\nIM 用户：\(session.userId)\n\n个人资料、好友关系、主题/语言设置由业务 App 管理；可调用 PteIMSDK.updateAppearance(...) 即时更新 UI。"; controller.view.addSubview(label); label.translatesAutoresizingMaskIntoConstraints = false
    NSLayoutConstraint.activate([label.leadingAnchor.constraint(equalTo: controller.view.layoutMarginsGuide.leadingAnchor), label.trailingAnchor.constraint(equalTo: controller.view.layoutMarginsGuide.trailingAnchor), label.topAnchor.constraint(equalTo: controller.view.safeAreaLayoutGuide.topAnchor, constant: 24)])
    return controller
  }

  private func chat(client: PteIMSDK, conversationId: String, title: String) -> PteIMUIChatViewController {
    let chat = PteIMUIkit.makeChatViewController(client: client, conversationId: conversationId, title: title)
    chat.onActionRequested = { action, controller in
      let alert = UIAlertController(title: action.title(language: client.appearance.language), message: "请在宿主业务 App 中接入选择器、定位或支付流程，再调用 PteIMUIkit 的发送方法。", preferredStyle: .alert)
      alert.addAction(UIAlertAction(title: "确定", style: .default)); controller.present(alert, animated: true)
    }
    chat.onVoiceRecordingChanged = { recording, controller in
      controller.navigationItem.prompt = recording ? "正在录音，松开后由业务层上传" : nil
    }
    return chat
  }

  #if DEBUG
  /** Test-only process injection. It is compiled out of Release and never persists a UserSig. */
  private func runAutomationIfRequested() {
    guard !didRunAutomation,
          ProcessInfo.processInfo.environment["PTE_IM_UI_DEMO_AUTOMATION"] == "1",
          let userSigValue = ProcessInfo.processInfo.environment["PTE_IM_UI_DEMO_USERSIG"], !userSigValue.isEmpty,
          let appIDValue = ProcessInfo.processInfo.environment["PTE_IM_UI_DEMO_APP_ID"],
          let userIDValue = ProcessInfo.processInfo.environment["PTE_IM_UI_DEMO_USER_ID"] else { return }
    didRunAutomation = true
    appId.text = appIDValue; account.text = "ui-qa"; userId.text = userIDValue; userSig.text = userSigValue
    loginTapped()
    if ProcessInfo.processInfo.environment["PTE_IM_UI_DEMO_OPEN_PEER"] == "1", let client {
      // UI acceptance uses a deterministic server-owned ID only; it never fabricates
      // a conversation on the service. Production navigation keeps using openSingleChat.
      DispatchQueue.main.async { [weak self] in
        guard let self else { return }
        self.navigationController?.pushViewController(self.chat(client: client, conversationId: "1", title: "Alice"), animated: false)
      }
    }
  }
  #endif

  /** Server APIs own conversation identifiers. The client only consumes their numeric IDs. */
  private func openSingleChat(client: PteIMSDK, peerUserId: Int64, title: String, presenter: UIViewController) {
    Task { [weak self, weak presenter] in
      do {
        let conversation = try await client.openSingleConversation(peerUserId: peerUserId)
        await MainActor.run {
          self?.conversationId.text = String(conversation.id)
          presenter?.navigationController?.pushViewController(self?.chat(client: client, conversationId: String(conversation.id), title: title) ?? UIViewController(), animated: true)
        }
      } catch { await MainActor.run { self?.status.text = "无法打开会话：\(error.localizedDescription)" } }
    }
  }

  private func openDemoGroupChat(client: PteIMSDK, presenter: UIViewController) {
    let members = friends.compactMap { Int64($0.userId) }
    Task { [weak self, weak presenter] in
      do {
        let conversation = try await client.createGroupConversation(title: "PteIMUIDemo Group", memberIds: members)
        await MainActor.run {
          self?.conversationId.text = String(conversation.id)
          presenter?.navigationController?.pushViewController(self?.chat(client: client, conversationId: String(conversation.id), title: conversation.title) ?? UIViewController(), animated: true)
        }
      } catch { await MainActor.run { self?.status.text = "无法创建群组：\(error.localizedDescription)" } }
    }
  }

  private static func field(_ value: String, _ placeholder: String, keyboard: UIKeyboardType = .default, secure: Bool = false) -> UITextField { let field = UITextField(); field.text = value; field.placeholder = placeholder; field.borderStyle = .roundedRect; field.keyboardType = keyboard; field.isSecureTextEntry = secure; field.autocapitalizationType = .none; return field }
}

private struct PteIMUIDemoBusinessSession { let account: String; let userId: String; let userSig: String; init?(account: String, userId: String, userSig: String) { guard !account.isEmpty, !userId.isEmpty, !userSig.isEmpty else { return nil }; self.account = account; self.userId = userId; self.userSig = userSig } }
private struct PteIMUIDemoFriend { let name: String; let userId: String }
private final class PteIMUIDemoMenuDataSource: NSObject, UITableViewDataSource, UITableViewDelegate { let items: [String]; let selected: (Int) -> Void; init(items: [String], selected: @escaping (Int) -> Void) { self.items = items; self.selected = selected }; func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { items.count }; func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell { let cell = UITableViewCell(style: .default, reuseIdentifier: nil); cell.textLabel?.text = items[indexPath.row]; cell.accessoryType = .disclosureIndicator; return cell }; func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) { selected(indexPath.row) } }

private struct PteIMUIDemoCredentialEnvelope: Decodable {
  let code: Int
  let msg: String
  let data: PteIMUIDemoCredential?
}
private struct PteIMUIDemoCredential: Decodable {
  let userSig: String
  let userId: String
  let sdkAppId: String
  let wsURL: String
  enum CodingKeys: String, CodingKey { case userSig = "user_sig"; case userId = "user_id"; case sdkAppId = "sdk_app_id"; case wsURL = "ws_url" }
}
private enum PteIMUIDemoLoginError: LocalizedError {
  case requestFailed
  case server(String)
  var errorDescription: String? { switch self { case .requestFailed: return "请求失败"; case let .server(message): return message.isEmpty ? "服务未返回凭据" : message } }
}

private final class PteIMUIDemoLabel: UILabel {
  init(_ text: String, style: UIFont.TextStyle, color: UIColor) {
    super.init(frame: .zero)
    self.text = text; font = .preferredFont(forTextStyle: style); textColor = color; adjustsFontForContentSizeCategory = true
  }
  required init?(coder: NSCoder) { nil }
}

private final class PteIMUIDemoGradientButton: UIButton {
  private let gradient = CAGradientLayer()
  init(title: String) {
    super.init(frame: .zero)
    setTitle(title, for: .normal); setTitleColor(.white, for: .normal); titleLabel?.font = .systemFont(ofSize: 16, weight: .semibold)
    layer.cornerRadius = 16; clipsToBounds = true
    gradient.colors = [UIColor(red: 0.12, green: 0.40, blue: 0.98, alpha: 1).cgColor, UIColor(red: 0.47, green: 0.22, blue: 0.98, alpha: 1).cgColor]
    gradient.startPoint = CGPoint(x: 0, y: 0); gradient.endPoint = CGPoint(x: 1, y: 1); layer.insertSublayer(gradient, at: 0)
  }
  required init?(coder: NSCoder) { nil }
  override func layoutSubviews() { super.layoutSubviews(); gradient.frame = bounds }
}

/** A vector brand mark derived from the supplied PTE Live microphone identity. */
private final class PteIMUIDemoHeroView: UIView {
  private let gradient = CAGradientLayer()
  private let core = UIView()
  private let mic = UIImageView(image: UIImage(systemName: "mic.fill"))
  private let recording = UIView()
  override init(frame: CGRect) {
    super.init(frame: frame)
    layer.cornerRadius = 28; clipsToBounds = true
    gradient.colors = [UIColor(red: 0.05, green: 0.12, blue: 0.34, alpha: 1).cgColor, UIColor(red: 0.19, green: 0.19, blue: 0.67, alpha: 1).cgColor, UIColor(red: 0.45, green: 0.18, blue: 0.82, alpha: 1).cgColor]
    gradient.startPoint = CGPoint(x: 0, y: 0); gradient.endPoint = CGPoint(x: 1, y: 1); layer.insertSublayer(gradient, at: 0)
    let wave = UIImageView(image: UIImage(systemName: "wave.3.right.circle.fill")); wave.tintColor = UIColor.white.withAlphaComponent(0.22); wave.translatesAutoresizingMaskIntoConstraints = false; wave.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 96, weight: .thin)
    core.backgroundColor = UIColor.white.withAlphaComponent(0.14); core.layer.cornerRadius = 48; core.layer.borderWidth = 1; core.layer.borderColor = UIColor.white.withAlphaComponent(0.26).cgColor; core.translatesAutoresizingMaskIntoConstraints = false
    mic.tintColor = .white; mic.translatesAutoresizingMaskIntoConstraints = false; mic.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 42, weight: .medium)
    recording.backgroundColor = UIColor(red: 1, green: 0.24, blue: 0.25, alpha: 1); recording.layer.cornerRadius = 9; recording.layer.borderWidth = 4; recording.layer.borderColor = UIColor.white.cgColor; recording.translatesAutoresizingMaskIntoConstraints = false
    addSubview(wave); addSubview(core); core.addSubview(mic); addSubview(recording)
    NSLayoutConstraint.activate([
      wave.trailingAnchor.constraint(equalTo: trailingAnchor, constant: 36), wave.centerYAnchor.constraint(equalTo: centerYAnchor), wave.widthAnchor.constraint(equalToConstant: 144), wave.heightAnchor.constraint(equalToConstant: 144),
      core.centerXAnchor.constraint(equalTo: centerXAnchor), core.centerYAnchor.constraint(equalTo: centerYAnchor), core.widthAnchor.constraint(equalToConstant: 96), core.heightAnchor.constraint(equalToConstant: 96),
      mic.centerXAnchor.constraint(equalTo: core.centerXAnchor), mic.centerYAnchor.constraint(equalTo: core.centerYAnchor),
      recording.centerXAnchor.constraint(equalTo: core.centerXAnchor), recording.bottomAnchor.constraint(equalTo: core.topAnchor, constant: 10), recording.widthAnchor.constraint(equalToConstant: 18), recording.heightAnchor.constraint(equalToConstant: 18)
    ])
  }
  required init?(coder: NSCoder) { nil }
  override func layoutSubviews() { super.layoutSubviews(); gradient.frame = bounds }
}

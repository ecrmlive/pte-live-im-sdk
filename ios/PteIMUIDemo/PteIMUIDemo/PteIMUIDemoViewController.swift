import UIKit
import ObjectiveC
import PteIMUIKit
import PteIMSDK

/**
 `PteIMUIDemo` is an application-layer example. Its business service signs a user in and
 returns a short-lived IM credential; only then does it create PteIMSDK and present PteIMUIKit.
 */
final class PteIMUIDemoViewController: UIViewController {
  private let applicationSession: PteIMUIDemoApplicationSession
  /** The registration flow is pushed as its own controller, rather than toggling fields in place. */
  private let isRegistrationPage: Bool
  private let appId = PteIMUIDemoViewController.field("", "SDK App ID returned by business login", keyboard: .numberPad)
  private let account = PteIMUIDemoViewController.field("demo-user", "Business account")
  private let password = PteIMUIDemoViewController.field("", "Business password (demo only)", secure: true)
  private let userId = PteIMUIDemoViewController.field("10001", "IM user ID returned by business login", keyboard: .numberPad)
  private let userSig = PteIMUIDemoViewController.field("", "Short-lived UserSig returned by business login", secure: true)
  private let conversationId = PteIMUIDemoViewController.field("", "Active conversation ID (set by IM service)")
  private let captchaImage = UIImageView()
  private var client: PteIMSDK?
  private let businessAPI: PteIMUIDemoBusinessAPI
  private var captchaID = ""
  private var businessCredential: PteIMUIDemoBusinessCredential?
  private var credentialListener: PteIMListener?
  private var friends = [PteIMUIDemoFriend(name: "Alice", userId: "10002"), PteIMUIDemoFriend(name: "Bob", userId: "10003")]
  private var configurationStack: UIStackView?
  /** Login happens before an SDK user exists, so its preference is app-scoped. */
  private var loginThemeMode: PteIMThemeMode = .system
  private var loginLanguage: PteIMLanguage = .system
  private var loginThemeTransitionTimer: Timer?
  private weak var loginNavigationBar: PteIMUIDemoAuthNavigationBar?
  private weak var loginNavigationChrome: UIView?
  private weak var loginCard: UIView?
  private weak var loginScrollView: UIScrollView?
  private weak var loginTitleLabel: UILabel?
  private weak var loginSubtitleLabel: UILabel?
  private weak var loginButton: PteIMUIDemoGradientButton?
  private var loginFormLabels = [UILabel]()
  private weak var mobileFormLabel: UILabel?
  private weak var nicknameFormLabel: UILabel?
  private weak var passwordFormLabel: UILabel?
  private weak var captchaFormLabel: UILabel?
  #if DEBUG
  private var didRunAutomation = false
  private var didOpenLocalPreview = false
  #endif

  init(applicationSession: PteIMUIDemoApplicationSession, isRegistrationPage: Bool = false) {
    self.applicationSession = applicationSession
    self.isRegistrationPage = isRegistrationPage
    self.businessAPI = PteIMUIDemoBusinessAPI(apiDomain: applicationSession.baseConfig.apiDomain)
    super.init(nibName: nil, bundle: nil)
  }
  required init?(coder: NSCoder) { nil }

  override func viewDidLoad() {
    super.viewDidLoad()
    restoreLoginAppearancePreferences()
    navigationItem.hidesBackButton = true
    navigationController?.setNavigationBarHidden(true, animated: false)
    view.backgroundColor = UIColor(red: 0.957, green: 0.957, blue: 1.00, alpha: 1)
    conversationId.isEnabled = false
    // iOS uses Demo account 01. The registration page reuses the same values.
    account.text = "星河入梦"; password.text = "12345678"
    appId.text = "13500000001"
    userId.text = ""
    userSig.text = ""

    let scrollView = UIScrollView(); scrollView.alwaysBounceVertical = true; scrollView.showsVerticalScrollIndicator = false; scrollView.backgroundColor = view.backgroundColor
    loginScrollView = scrollView
    let content = UIStackView(); content.axis = .vertical; content.spacing = 13
    view.addSubview(scrollView); scrollView.translatesAutoresizingMaskIntoConstraints = false
    scrollView.addSubview(content); content.translatesAutoresizingMaskIntoConstraints = false

    let header = PteIMUIDemoAuthNavigationBar()
    loginNavigationBar = header
    header.onLanguageSelected = { [weak self] language in
      guard let self else { return }
      self.loginLanguage = language
      PteIMUIDemoLoginAppearancePreferences.save(language: language)
      self.applyLoginAppearance()
    }
    header.onThemeSelected = { [weak self] mode in
      guard let self else { return }
      self.loginThemeMode = mode
      PteIMUIDemoLoginAppearancePreferences.save(themeMode: mode)
      self.applyLoginAppearance()
    }
    if isRegistrationPage {
      header.onBack = { [weak self] in self?.navigationController?.popViewController(animated: true) }
    }
    let navigationChrome = UIView(); navigationChrome.translatesAutoresizingMaskIntoConstraints = false; navigationChrome.backgroundColor = loginNavigationPalette().surfaceColor
    loginNavigationChrome = navigationChrome
    view.addSubview(navigationChrome); navigationChrome.addSubview(header)
    NSLayoutConstraint.activate([
      navigationChrome.leadingAnchor.constraint(equalTo: view.leadingAnchor), navigationChrome.trailingAnchor.constraint(equalTo: view.trailingAnchor),
      navigationChrome.topAnchor.constraint(equalTo: view.topAnchor), navigationChrome.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 44),
      header.leadingAnchor.constraint(equalTo: navigationChrome.leadingAnchor), header.trailingAnchor.constraint(equalTo: navigationChrome.trailingAnchor), header.bottomAnchor.constraint(equalTo: navigationChrome.bottomAnchor)
    ])

    let logo = UIImageView(image: UIImage(named: "PteIMUILogo")); logo.contentMode = .scaleAspectFit; logo.layer.cornerRadius = 24; logo.clipsToBounds = true; logo.translatesAutoresizingMaskIntoConstraints = false
    let titleLabel = PteIMUIDemoLabel("PrivateChat", style: .largeTitle, color: UIColor(red: 0.11, green: 0.11, blue: 0.20, alpha: 1)); titleLabel.textAlignment = .center; titleLabel.font = .systemFont(ofSize: 29, weight: .bold)
    let subtitle = PteIMUIDemoLabel("Secure · Private · Efficient", style: .subheadline, color: UIColor(red: 0.42, green: 0.43, blue: 0.53, alpha: 1)); subtitle.textAlignment = .center
    let brand = UIStackView(arrangedSubviews: [logo, titleLabel, subtitle]); brand.axis = .vertical; brand.alignment = .center; brand.spacing = 8; brand.setCustomSpacing(28, after: logo); logo.widthAnchor.constraint(equalToConstant: 96).isActive = true; logo.heightAnchor.constraint(equalToConstant: 96).isActive = true

    let card = UIView(); card.backgroundColor = .white; card.layer.cornerRadius = 24; card.layer.shadowColor = UIColor.black.cgColor; card.layer.shadowOpacity = 0.12; card.layer.shadowRadius = 18; card.layer.shadowOffset = CGSize(width: 0, height: 9)
    let login = PteIMUIDemoGradientButton(title: isRegistrationPage ? "Register" : "Login"); login.addTarget(self, action: #selector(loginTapped), for: .touchUpInside)
    let register = UIButton(type: .system); register.setTitle("Create demo account", for: .normal); register.addTarget(self, action: #selector(registerTapped), for: .touchUpInside)
    [appId, account, userId, userSig].forEach { field in
      field.borderStyle = .none
      field.backgroundColor = UIColor(red: 0.929, green: 0.914, blue: 1.00, alpha: 1)
      field.layer.cornerRadius = 18
      field.setLeftPadding(16)
      field.heightAnchor.constraint(equalToConstant: 46).isActive = true
    }
    appId.placeholder = "Mobile (+86 or international)"; account.placeholder = "Nickname (required to register)"; userId.placeholder = "Verification code"; userSig.placeholder = "Password"
    captchaImage.contentMode = .scaleAspectFit; captchaImage.backgroundColor = UIColor(red: 0.929, green: 0.914, blue: 1, alpha: 1); captchaImage.layer.cornerRadius = 12; captchaImage.clipsToBounds = true; captchaImage.isUserInteractionEnabled = true; captchaImage.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(refreshCaptcha)))
    captchaImage.widthAnchor.constraint(equalToConstant: 132).isActive = true
    captchaImage.heightAnchor.constraint(equalToConstant: 46).isActive = true
    // The reference keeps a deliberate breath between credentials and the primary action.
    let mobileLabel = PteIMUIDemoLabel("Mobile", style: .subheadline, color: .label)
    let nickLabel = PteIMUIDemoLabel("Nickname", style: .subheadline, color: .label)
    let passwordLabel = PteIMUIDemoLabel("Password", style: .subheadline, color: .label)
    let captchaLabel = PteIMUIDemoLabel("Verification code", style: .subheadline, color: .label)
    let captchaRow = UIStackView(arrangedSubviews: [userId, captchaImage])
    captchaRow.axis = .horizontal
    captchaRow.alignment = .fill
    captchaRow.distribution = .fill
    captchaRow.spacing = 10
    var formViews: [UIView] = [mobileLabel, appId]
    if isRegistrationPage { formViews += [nickLabel, account] }
    formViews += [passwordLabel, userSig, captchaLabel, captchaRow, login]
    if !isRegistrationPage { formViews.append(register) }
    let cardStack = UIStackView(arrangedSubviews: formViews); cardStack.axis = .vertical; cardStack.spacing = 9
    card.addSubview(cardStack); cardStack.translatesAutoresizingMaskIntoConstraints = false
    NSLayoutConstraint.activate([cardStack.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 24), cardStack.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -24), cardStack.topAnchor.constraint(equalTo: card.topAnchor, constant: 26), cardStack.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -24), login.heightAnchor.constraint(equalToConstant: 50)])

    let topSpacer = UIView(); topSpacer.heightAnchor.constraint(equalToConstant: 50).isActive = true
    content.addArrangedSubview(topSpacer); content.addArrangedSubview(brand); content.setCustomSpacing(40, after: brand); content.addArrangedSubview(card)
    loginCard = card; loginTitleLabel = titleLabel; loginSubtitleLabel = subtitle; loginButton = login; loginFormLabels = isRegistrationPage ? [mobileLabel, nickLabel, passwordLabel, captchaLabel] : [mobileLabel, passwordLabel, captchaLabel]
    mobileFormLabel = mobileLabel; nicknameFormLabel = isRegistrationPage ? nickLabel : nil; passwordFormLabel = passwordLabel; captchaFormLabel = captchaLabel
    NSLayoutConstraint.activate([
      scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor), scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
      scrollView.topAnchor.constraint(equalTo: navigationChrome.bottomAnchor), scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
      content.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor, constant: 15), content.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor, constant: -15),
      content.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor), content.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor, constant: -28),
      content.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor, constant: -30),
    ])
    applyLoginAppearance(); refreshCaptcha()
  }

  override func viewWillAppear(_ animated: Bool) {
    super.viewWillAppear(animated)
    // The demo is always a root screen. Make that explicit so it cannot
    // inherit a sheet-style presentation from an embedding host.
    modalPresentationStyle = .fullScreen
    navigationController?.modalPresentationStyle = .fullScreen
    navigationController?.setNavigationBarHidden(true, animated: false)
    applyLoginAppearance()
  }

  private func applyLoginAppearance() {
    let resolvedThemeMode = resolvedLoginThemeMode()
    let resolvedLanguage = loginLanguage.resolved()
    PteIMUIDemoAuthNavigationBar.applySystemBars(to: self, themeMode: resolvedThemeMode)
    let dark = resolvedThemeMode == .dark
    let primary = dark ? UIColor(red: 0.94, green: 0.93, blue: 1.00, alpha: 1) : UIColor(red: 0.11, green: 0.11, blue: 0.20, alpha: 1)
    let secondary = dark ? UIColor(red: 0.65, green: 0.62, blue: 0.78, alpha: 1) : UIColor(red: 0.42, green: 0.43, blue: 0.53, alpha: 1)
    view.backgroundColor = dark ? UIColor(red: 0.051, green: 0.051, blue: 0.129, alpha: 1) : UIColor(red: 0.957, green: 0.957, blue: 1.00, alpha: 1)
    loginScrollView?.backgroundColor = view.backgroundColor
    loginCard?.backgroundColor = dark ? UIColor(red: 0.067, green: 0.063, blue: 0.165, alpha: 1) : .white
    loginCard?.layer.borderWidth = dark ? 1 : 0
    loginCard?.layer.borderColor = dark ? UIColor(red: 0.23, green: 0.21, blue: 0.36, alpha: 1).cgColor : UIColor.clear.cgColor
    loginCard?.layer.shadowOpacity = dark ? 0 : 0.12
    loginTitleLabel?.text = resolvedLanguage == .zhCN ? "私域" : "PrivateChat"
    loginSubtitleLabel?.text = resolvedLanguage == .zhCN ? "安全 · 私密 · 高效通讯" : "Secure · Private · Efficient"
    loginTitleLabel?.textColor = primary
    loginSubtitleLabel?.textColor = secondary
    loginFormLabels.forEach { $0.textColor = primary }
    [appId, account, userId, userSig].forEach { field in
      field.backgroundColor = dark ? UIColor(red: 0.125, green: 0.118, blue: 0.30, alpha: 1) : UIColor(red: 0.929, green: 0.914, blue: 1.00, alpha: 1)
      field.textColor = primary
      field.attributedPlaceholder = NSAttributedString(string: field.placeholder ?? "", attributes: [.foregroundColor: secondary])
    }
    captchaImage.backgroundColor = dark ? UIColor(red: 0.125, green: 0.118, blue: 0.30, alpha: 1) : UIColor(red: 0.929, green: 0.914, blue: 1.00, alpha: 1)
    appId.placeholder = resolvedLanguage == .zhCN ? "手机号（中国或国际）" : "Mobile (+86 or international)"
    account.placeholder = resolvedLanguage == .zhCN ? "昵称（注册必填）" : "Nickname (required to register)"
    userId.placeholder = resolvedLanguage == .zhCN ? "图形验证码" : "Verification code"
    userSig.placeholder = resolvedLanguage == .zhCN ? "密码" : "Password"
    mobileFormLabel?.text = resolvedLanguage == .zhCN ? "手机号" : "Mobile"
    nicknameFormLabel?.text = resolvedLanguage == .zhCN ? "昵称" : "Nickname"
    passwordFormLabel?.text = resolvedLanguage == .zhCN ? "密码" : "Password"
    captchaFormLabel?.text = resolvedLanguage == .zhCN ? "图形验证码" : "Verification code"
    [appId, account, userId, userSig].forEach { field in field.attributedPlaceholder = NSAttributedString(string: field.placeholder ?? "", attributes: [.foregroundColor: secondary]) }
    loginButton?.setTitle(isRegistrationPage ? (resolvedLanguage == .zhCN ? "注册" : "Register") : (resolvedLanguage == .zhCN ? "登录" : "Login"), for: .normal)
    loginButton?.applyTheme(dark: dark)
    loginNavigationBar?.apply(palette: loginNavigationPalette(), themeMode: resolvedThemeMode, language: loginLanguage)
    loginNavigationChrome?.backgroundColor = loginNavigationPalette().surfaceColor
    scheduleAutomaticLoginThemeTransition()
  }

  private func loginNavigationPalette() -> PteIMUIThemePalette {
    let dark = resolvedLoginThemeMode() == .dark
    var palette = dark ? PteIMUIThemePalette.blueVioletDark : PteIMUIThemePalette.blueVioletLight
    let canvas = dark
      ? UIColor(red: 0.04, green: 0.04, blue: 0.13, alpha: 1)
      : UIColor(red: 0.957, green: 0.957, blue: 1.00, alpha: 1)
    palette.backgroundColor = canvas
    palette.surfaceColor = canvas
    return palette
  }

  private func restoreLoginAppearancePreferences() {
    loginThemeMode = PteIMUIDemoLoginAppearancePreferences.themeMode ?? .system
    loginLanguage = PteIMUIDemoLoginAppearancePreferences.language ?? .system
  }

  private func resolvedLoginThemeMode() -> PteIMThemeMode {
    switch loginThemeMode {
    case .light, .dark: return loginThemeMode
    case .system:
      return PteIMAppearance(themeMode: .system, language: loginLanguage).resolvedTheme() == .dark ? .dark : .light
    }
  }

  private func scheduleAutomaticLoginThemeTransition() {
    loginThemeTransitionTimer?.invalidate()
    loginThemeTransitionTimer = nil
    guard loginThemeMode == .system else { return }

    let calendar = Calendar.current
    let now = Date()
    let morning = calendar.nextDate(after: now, matching: DateComponents(hour: 7, minute: 0, second: 0), matchingPolicy: .nextTime)
    let evening = calendar.nextDate(after: now, matching: DateComponents(hour: 19, minute: 0, second: 0), matchingPolicy: .nextTime)
    guard let nextTransition = [morning, evening].compactMap({ $0 }).min() else { return }
    loginThemeTransitionTimer = Timer(fire: nextTransition, interval: 0, repeats: false) { [weak self] _ in
      Task { @MainActor in self?.applyLoginAppearance() }
    }
    RunLoop.main.add(loginThemeTransitionTimer!, forMode: .common)
  }

  @objc private func toggleConfiguration() {
    configurationStack?.isHidden.toggle()
    UIView.animate(withDuration: 0.24) { self.view.layoutIfNeeded() }
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

  @objc private func refreshCaptcha() { Task { @MainActor in do { let captcha = try await businessAPI.captcha(); captchaID = captcha.id; captchaImage.image = UIImage(data: captcha.imageData) } catch { showError("验证码加载失败", detail: error.localizedDescription) } } }

  @objc private func loginTapped() { authenticate(register: isRegistrationPage) }
  @objc private func registerTapped() {
    let registration = PteIMUIDemoViewController(applicationSession: applicationSession, isRegistrationPage: true)
    navigationController?.pushViewController(registration, animated: true)
  }
  private func authenticate(register: Bool) {
    let mobile = appId.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "", nickname = account.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "", secret = userSig.text ?? "", code = userId.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    guard !mobile.isEmpty, secret.count >= 8, !code.isEmpty, !captchaID.isEmpty, (!register || nickname.count >= 2) else { showError("请完善登录信息", detail: register ? "请输入手机号、昵称、密码和验证码" : "请输入手机号、密码和验证码"); return }
    Task { @MainActor in do {
      let credential = try await (register ? businessAPI.register(mobile: mobile, nickname: nickname, password: secret, captchaID: captchaID, captchaCode: code) : businessAPI.login(mobile: mobile, password: secret, captchaID: captchaID, captchaCode: code))
      guard let session = PteIMUIDemoBusinessSession(account: credential.nickname, userId: credential.userId, userSig: credential.userSig) else { throw PteIMError.invalidResponse }
      businessCredential = credential
      let sdk = try applicationSession.bootstrap.login(PteIMLoginConfig(
        sdkAppId: credential.sdkAppId,
        userId: credential.userId,
        userSig: credential.userSig,
        userSigExpireAt: credential.expiresAt,
        userSigProvider: makeUserSigProvider()
      ))
      client = sdk; attachCredentialLifecycle(to: sdk); showBusinessHome(session: session)
    } catch { showError(register ? "注册失败" : "登录失败", detail: error.localizedDescription); userId.text = ""; refreshCaptcha() } }
  }

  /** Local-only UIKit inspection route. It never uses a business credential or calls `start()`. */
  @objc private func previewTapped() {
    do {
      let login = try PteIMLoginConfig(sdkAppId: 1, userId: "990021", userSig: "local-ui-preview")
      let previewClient = try PteIMSDK.preview(baseConfig: applicationSession.baseConfig, loginConfig: login)
      let home = PteIMUIDemoHomeTabsController(client: previewClient, isPreview: true) { [weak self, weak previewClient] in
        previewClient?.stop(); self?.navigationController?.popToRootViewController(animated: true)
      }
      home.modalPresentationStyle = .fullScreen
      navigationController?.pushViewController(home, animated: true)
    } catch { showError("无法创建本地 UI 预览", detail: error.localizedDescription, position: .center) }
  }

  private func showError(_ title: String, detail: String? = nil, position: PteIMUINoticePosition = .bottom) {
    PteIMUINotice.showError(title, detail: detail, position: position, in: self)
  }

  private func attachCredentialLifecycle(to sdk: PteIMSDK) {
    let listener = PteIMListener()
    listener.onUserSigRefreshFailed = { [weak self, weak sdk] _ in
      guard let self, let sdk else { return }
      Task { @MainActor in self.endExpiredSession(sdk) }
    }
    credentialListener = listener
    sdk.addListener(listener)
  }

  /** The SDK calls this Provider itself; the Demo only rotates its refresh session. */
  private func makeUserSigProvider() -> PteIMUserSigProvider {
    { [weak self] in
      try await Task { @MainActor [weak self] () throws -> PteIMUserSigRefreshResult in
        guard let self, let credential = self.businessCredential else { throw PteIMError.invalidCredentials }
        let refreshed = try await self.businessAPI.refresh(credential: credential)
        self.businessCredential = refreshed
        return PteIMUserSigRefreshResult(userSig: refreshed.userSig, expireAt: refreshed.expiresAt)
      }.value
    }
  }

  private func endExpiredSession(_ sdk: PteIMSDK) {
    guard client === sdk else { return }
    if let credentialListener { sdk.removeListener(credentialListener) }
    credentialListener = nil; sdk.stop(); client = nil; businessCredential = nil
    navigationController?.popToRootViewController(animated: true)
    showError("登录状态已失效", detail: "请重新登录")
  }

  private func showBusinessHome(session: PteIMUIDemoBusinessSession) {
    guard let client else { return }
    let home = PteIMUIDemoHomeTabsController(client: client, onLogout: { [weak self] in
      guard let self else { return }
      if let listener = self.credentialListener, let client = self.client { client.removeListener(listener) }
      self.credentialListener = nil; self.client?.stop(); self.client = nil; self.businessCredential = nil; self.navigationController?.popToRootViewController(animated: true)
    }, onAddDemoFriend: { [weak self] presenter in self?.showDemoUserList(from: presenter) })
    navigationController?.pushViewController(home, animated: true)
  }

  private func showDemoUserList(from presenter: UIViewController) {
    guard let credential = businessCredential else { return }
    let controller = UITableViewController(style: .insetGrouped); controller.title = "已注册演示用户"
    Task { @MainActor [weak self, weak controller] in
      guard let self, let controller else { return }
      do {
        let users = try await businessAPI.users(credential: credential)
        let source = PteIMUIDemoMenuDataSource(items: users.map { "\($0.nickname) · \($0.mobile)" }) { index in
          Task { @MainActor [weak controller] in
            do { try await self.businessAPI.addFriend(users[index], credential: credential); controller?.navigationItem.prompt = "已添加 \(users[index].nickname)，现在可在联系人中单聊" }
            catch { controller?.navigationItem.prompt = "添加失败：\(error.localizedDescription)" }
          }
        }
        controller.tableView.dataSource = source; controller.tableView.delegate = source; objc_setAssociatedObject(controller, "PteIMUIDemoDemoUserDataSource", source, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
      } catch { controller.navigationItem.prompt = "加载失败：\(error.localizedDescription)" }
    }
    presenter.navigationController?.pushViewController(controller, animated: true)
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
    let chat = PteIMUIKit.makeChatViewController(client: client, conversationId: conversationId, title: title)
    chat.onActionRequested = { action, controller in
      let alert = UIAlertController(title: action.title(language: client.appearance.language), message: "请在宿主业务 App 中接入选择器、定位或支付流程，再调用 PteIMUIKit 的发送方法。", preferredStyle: .alert)
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
      } catch { await MainActor.run { self?.showError("无法打开会话", detail: error.localizedDescription) } }
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
      } catch { await MainActor.run { self?.showError("无法创建群组", detail: error.localizedDescription) } }
    }
  }

  private static func field(_ value: String, _ placeholder: String, keyboard: UIKeyboardType = .default, secure: Bool = false) -> UITextField { let field = UITextField(); field.text = value; field.placeholder = placeholder; field.borderStyle = .roundedRect; field.keyboardType = keyboard; field.isSecureTextEntry = secure; field.autocapitalizationType = .none; return field }
}

private struct PteIMUIDemoBusinessSession { let account: String; let userId: String; let userSig: String; init?(account: String, userId: String, userSig: String) { guard !account.isEmpty, !userId.isEmpty, !userSig.isEmpty else { return nil }; self.account = account; self.userId = userId; self.userSig = userSig } }
private struct PteIMUIDemoFriend { let name: String; let userId: String }
private final class PteIMUIDemoMenuDataSource: NSObject, UITableViewDataSource, UITableViewDelegate { let items: [String]; let selected: (Int) -> Void; init(items: [String], selected: @escaping (Int) -> Void) { self.items = items; self.selected = selected }; func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { items.count }; func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell { let cell = UITableViewCell(style: .default, reuseIdentifier: nil); cell.textLabel?.text = items[indexPath.row]; cell.accessoryType = .disclosureIndicator; return cell }; func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) { selected(indexPath.row) } }

/** The pre-login screen has no IM account yet, so its manual choices are app-wide. */
private enum PteIMUIDemoLoginAppearancePreferences {
  private static let themeModeKey = "com.ptelive.im.uidemo.login.themeMode"
  private static let languageKey = "com.ptelive.im.uidemo.login.language"

  static var themeMode: PteIMThemeMode? {
    UserDefaults.standard.string(forKey: themeModeKey).flatMap(PteIMThemeMode.init(rawValue:))
  }

  static var language: PteIMLanguage? {
    UserDefaults.standard.string(forKey: languageKey).flatMap(PteIMLanguage.init(rawValue:))
  }

  static func save(themeMode: PteIMThemeMode) {
    UserDefaults.standard.set(themeMode.rawValue, forKey: themeModeKey)
  }

  static func save(language: PteIMLanguage) {
    UserDefaults.standard.set(language.rawValue, forKey: languageKey)
  }
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
    setImage(UIImage(systemName: "lock"), for: .normal); tintColor = .white; imageView?.preferredSymbolConfiguration = .init(pointSize: 15, weight: .semibold); semanticContentAttribute = .forceLeftToRight; imageEdgeInsets = .init(top: 0, left: -6, bottom: 0, right: 6)
    layer.cornerRadius = 16; clipsToBounds = true
    gradient.colors = [UIColor(red: 0.545, green: 0.212, blue: 0.941, alpha: 1).cgColor, UIColor(red: 0.443, green: 0.188, blue: 0.878, alpha: 1).cgColor]
    gradient.startPoint = CGPoint(x: 0, y: 0.5); gradient.endPoint = CGPoint(x: 1, y: 0.5); layer.insertSublayer(gradient, at: 0)
  }
  func applyTheme(dark: Bool) {
    gradient.colors = (dark
      ? [UIColor(red: 0.561, green: 0.341, blue: 0.961, alpha: 1).cgColor, UIColor(red: 0.545, green: 0.310, blue: 0.925, alpha: 1).cgColor]
      : [UIColor(red: 0.545, green: 0.212, blue: 0.941, alpha: 1).cgColor, UIColor(red: 0.443, green: 0.188, blue: 0.878, alpha: 1).cgColor])
    layer.shadowColor = dark ? UIColor(red: 0.54, green: 0.30, blue: 0.95, alpha: 0.45).cgColor : UIColor.clear.cgColor
    layer.shadowOpacity = dark ? 0.75 : 0
    layer.shadowRadius = dark ? 12 : 0
    layer.shadowOffset = CGSize(width: 0, height: 7)
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

private extension UITextField {
  func setLeftPadding(_ value: CGFloat) {
    leftView = UIView(frame: CGRect(x: 0, y: 0, width: value, height: 1))
    leftViewMode = .always
  }
}

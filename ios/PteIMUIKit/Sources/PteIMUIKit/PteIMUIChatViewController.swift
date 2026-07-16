import UIKit
import PteIMSDK

public enum PteIMUIAction: CaseIterable, Hashable {
  case image, camera, video, voice, location, gift, redPacket, order, file
  public func title(language: PteIMLanguage) -> String {
    switch self {
    case .image: return PteIMUILocalization.value("图片", "Image", language: language)
    case .camera: return PteIMUILocalization.value("拍摄", "Camera", language: language)
    case .video: return PteIMUILocalization.value("视频", "Video", language: language)
    case .voice: return PteIMUILocalization.value("语音", "Voice", language: language)
    case .location: return PteIMUILocalization.value("位置", "Location", language: language)
    case .gift: return PteIMUILocalization.value("礼物", "Gift", language: language)
    case .redPacket: return PteIMUILocalization.value("红包", "Red packet", language: language)
    case .order: return PteIMUILocalization.value("订单", "Order", language: language)
    case .file: return PteIMUILocalization.value("文件", "File", language: language)
    }
  }
}

/** A UIKit conversation screen. The host supplies attachment, location, and business payloads through [onActionRequested]. */
open class PteIMUIChatViewController: UIViewController, UITableViewDataSource, UITableViewDelegate, UITextFieldDelegate {
  public let client: PteIMSDK
  public let conversationId: String
  public var skin: PteIMUISkin { didSet { theme = skin.theme; inputBar.skin = skin; applySkin() } }
  public var theme: PteIMUITheme { didSet { applyTheme() } }
  public private(set) var language: PteIMLanguage
  public var onActionRequested: ((PteIMUIAction, PteIMUIChatViewController) -> Void)?
  /** `true` starts host recording; `false` finalises/cancels it. The host then calls [sendVoice]. */
  public var onVoiceRecordingChanged: ((Bool, PteIMUIChatViewController) -> Void)?
  public var onAvatarTapped: ((PteIMMessage, PteIMUIChatViewController) -> Void)?
  public var onMessageTapped: ((PteIMMessage, PteIMUIChatViewController) -> Void)?
  public var isOutgoing: ((PteIMMessage) -> Bool) = { _ in false }

  public let tableView = UITableView(frame: .zero, style: .plain)
  public let composerBar = UIView()
  public private(set) lazy var inputBar = PteIMUIInputBar(skin: skin)
  /// The current ordered timeline. Subclasses receive items through the open
  /// cell hooks; keeping mutation private preserves Core/cache consistency.
  public private(set) var messages: [PteIMMessage] = []
  private var previousMessageCallback: ((PteIMMessage) -> Void)?
  private var previousStateCallback: ((String, PteIMSendState) -> Void)?
  private var previousThemeCallback: ((PteIMThemeMode) -> Void)?
  private var previousLanguageCallback: ((PteIMLanguage) -> Void)?

  public init(client: PteIMSDK, conversationId: String, title: String? = nil, skin: PteIMUISkin = .default) {
    self.client = client; self.conversationId = conversationId; self.skin = skin; self.theme = skin.theme; self.language = client.appearance.language
    self.isOutgoing = { message in message.senderId == client.currentUserId }
    super.init(nibName: nil, bundle: nil)
    self.title = title ?? conversationId
  }
  public convenience init(client: PteIMSDK, conversationId: String, title: String? = nil, theme: PteIMUITheme) { self.init(client: client, conversationId: conversationId, title: title, skin: PteIMUISkin(theme: theme)) }
  required public init?(coder: NSCoder) { nil }

  public override func viewDidLoad() {
    super.viewDidLoad()
    configureViews(); bindClient(); reloadFromCache(); applySkin()
  }

  public override func viewDidAppear(_ animated: Bool) {
    super.viewDidAppear(animated)
    // Messages can be injected by a host before the controller is presented.
    // Once the table is in the view hierarchy, it is safe to reveal them.
    scrollToLatest()
  }
  // Core callbacks are chained with weak UI references. They remain safe after dismissal and are not reset here,
  // so an application that replaces a callback after presenting this controller is never overwritten on deinit.

  /**
   Buffers messages supplied before presentation. UIKit does not install the
   table view's data source until `viewDidLoad`, so an eager scroll here would
   otherwise attempt to scroll an empty table.
   */
  public func append(message: PteIMMessage) {
    upsert(message)
    guard isViewLoaded else { return }
    tableView.reloadData()
    tableView.layoutIfNeeded()
    scrollToLatest()
  }
  public func sendText(_ text: String) { guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }; append(message: client.sendText(conversationId: conversationId, text: text)); inputBar.clearText() }
  public func sendEmoji(packageId: String = "default", emojiId: String) { append(message: client.sendEmoji(conversationId: conversationId, packageId: packageId, emojiId: emojiId)) }
  public func sendImage(_ media: PteIMMedia) { append(message: client.sendImage(conversationId: conversationId, media: media)) }
  public func sendVideo(_ media: PteIMMedia) { append(message: client.sendVideo(conversationId: conversationId, media: media)) }
  public func sendVoice(_ voice: PteIMVoice) { append(message: client.sendVoice(conversationId: conversationId, voice: voice)) }
  public func sendLocation(_ location: PteIMLocation) { append(message: client.sendLocation(conversationId: conversationId, location: location)) }
  public func sendGift(_ content: PteIMBusinessContent) { append(message: client.sendGift(conversationId: conversationId, content: content)) }
  public func sendRedPacket(_ content: PteIMBusinessContent) { append(message: client.sendRedPacket(conversationId: conversationId, content: content)) }
  public func sendOrder(_ content: PteIMBusinessContent) { append(message: client.sendOrder(conversationId: conversationId, content: content)) }
  public func sendFile(_ media: PteIMMedia) { append(message: client.sendFile(conversationId: conversationId, media: media)) }

  /** Override to add a title view, call buttons or group-management controls. */
  open func configureNavigationBar() { navigationItem.largeTitleDisplayMode = .never }
  /** Override and register custom cells such as gifts, red packets or business cards. */
  open func registerMessageCells(in tableView: UITableView) { tableView.register(PteIMUIMessageCell.self, forCellReuseIdentifier: PteIMUIMessageCell.reuseIdentifier) }
  open func messageCellReuseIdentifier(for message: PteIMMessage) -> String { PteIMUIMessageCell.reuseIdentifier }
  /**
   Register any `UITableViewCell`, return its reuse identifier above, then
   override this method. The default branch configures PteIMUIMessageCell.
   This is intentionally not restricted to an SDK cell subclass.
   */
  open func configureMessageCell(_ cell: UITableViewCell, message: PteIMMessage, outgoing: Bool, at indexPath: IndexPath) {
    (cell as? PteIMUIMessageCell)?.configure(message: message, outgoing: outgoing, theme: theme, language: language, style: skin.chat)
  }
  /** Dedicated hook for avatar actions in the default SDK message cell. */
  open func configureAvatarAction(on cell: UITableViewCell, message: PteIMMessage) {
    (cell as? PteIMUIMessageCell)?.onAvatarTapped = { [weak self] in self?.didTapAvatar(for: message) }
  }
  open func didTapAvatar(for message: PteIMMessage) { onAvatarTapped?(message, self) }
  open func didTapMessage(_ message: PteIMMessage) { onMessageTapped?(message, self) }
  /** Gift/order/red-packet actions are routed to the host business app. */
  open func didRequestAction(_ action: PteIMUIAction) { onActionRequested?(action, self) }

  private func configureViews() {
    view.addSubview(tableView); view.addSubview(composerBar)
    tableView.translatesAutoresizingMaskIntoConstraints = false; composerBar.translatesAutoresizingMaskIntoConstraints = false
    NSLayoutConstraint.activate([tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor), tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor), tableView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor), tableView.bottomAnchor.constraint(equalTo: composerBar.topAnchor), composerBar.leadingAnchor.constraint(equalTo: view.leadingAnchor), composerBar.trailingAnchor.constraint(equalTo: view.trailingAnchor), composerBar.bottomAnchor.constraint(equalTo: view.keyboardLayoutGuide.topAnchor), composerBar.heightAnchor.constraint(greaterThanOrEqualToConstant: 58)])
    registerMessageCells(in: tableView); tableView.dataSource = self; tableView.delegate = self; tableView.separatorStyle = .none; tableView.keyboardDismissMode = .interactive
    composerBar.addSubview(inputBar)
    NSLayoutConstraint.activate([inputBar.leadingAnchor.constraint(equalTo: composerBar.leadingAnchor), inputBar.trailingAnchor.constraint(equalTo: composerBar.trailingAnchor), inputBar.topAnchor.constraint(equalTo: composerBar.topAnchor), inputBar.bottomAnchor.constraint(equalTo: composerBar.bottomAnchor)])
    inputBar.onSendText = { [weak self] text in self?.sendText(text) }
    inputBar.onAction = { [weak self] selection in
      guard let self else { return }
      switch selection {
      case let .emoji(packageId, emojiId): self.sendEmoji(packageId: packageId, emojiId: emojiId)
      case let .action(action): self.didRequestAction(action)
      }
    }
    inputBar.onVoiceRecordingChanged = { [weak self] isRecording in
      guard let self else { return }
      self.onVoiceRecordingChanged?(isRecording, self)
    }
    configureNavigationBar()
  }
  private func bindClient() {
    previousMessageCallback = client.onMessage; previousStateCallback = client.onMessageStateChanged; previousThemeCallback = client.onThemeModeChanged; previousLanguageCallback = client.onLanguageChanged
    client.onMessage = { [weak self] message in self?.previousMessageCallback?(message); guard message.conversationId == self?.conversationId else { return }; DispatchQueue.main.async { self?.append(message: message) } }
    client.onMessageStateChanged = { [weak self] id, state in self?.previousStateCallback?(id, state); DispatchQueue.main.async { guard let self, let index = self.messages.firstIndex(where: { $0.clientMsgId == id }) else { return }; self.messages[index].state = state; self.tableView.reloadRows(at: [IndexPath(row: index, section: 0)], with: .none) } }
    client.onThemeModeChanged = { [weak self] mode in self?.previousThemeCallback?(mode); DispatchQueue.main.async { self?.overrideUserInterfaceStyle = mode == .dark ? .dark : (mode == .light ? .light : .unspecified) } }
    client.onLanguageChanged = { [weak self] language in self?.previousLanguageCallback?(language); DispatchQueue.main.async { self?.language = language; self?.applyLocalizedStrings() } }
  }
  private func reloadFromCache() {
    // Keep host-provided optimistic/preview messages. The local store may be
    // empty on a first launch and must never erase that in-memory input.
    ((try? client.localMessages(conversationId: conversationId, limit: 200)) ?? []).forEach(upsert)
    tableView.reloadData()
    scrollToLatest()
  }
  private func upsert(_ message: PteIMMessage) { if let index = messages.firstIndex(where: { $0.clientMsgId == message.clientMsgId }) { messages[index] = message } else { messages.append(message); messages.sort { $0.createdAt < $1.createdAt } } }
  private func scrollToLatest(animated: Bool = true, retryCount: Int = 0) {
    // `reloadData()` does not guarantee that UITableView has re-queried its
    // data source at this exact point. Scrolling with the model count before
    // that happens produces UIKit's out-of-bounds-row exception.
    guard Thread.isMainThread else {
      DispatchQueue.main.async { [weak self] in self?.scrollToLatest(animated: animated, retryCount: retryCount) }
      return
    }
    guard isViewLoaded, view.window != nil, tableView.dataSource != nil, !messages.isEmpty else { return }
    let target = IndexPath(row: messages.count - 1, section: 0)
    tableView.layoutIfNeeded()
    guard tableView.numberOfSections > target.section,
          tableView.numberOfRows(inSection: target.section) > target.row else {
      // Let UITableView consume its pending reload/layout pass, then re-check
      // its authoritative row count instead of trusting the model blindly.
      guard retryCount < 2 else { return }
      DispatchQueue.main.async { [weak self] in self?.scrollToLatest(animated: animated, retryCount: retryCount + 1) }
      return
    }
    tableView.scrollToRow(at: target, at: .bottom, animated: animated)
  }
  private func applyTheme() {
    guard isViewLoaded else { return }
    let palette = theme.palette(for: traitCollection)
    view.backgroundColor = palette.backgroundColor
    tableView.backgroundColor = palette.backgroundColor
    composerBar.backgroundColor = palette.composerColor
    inputBar.theme = theme
    inputBar.language = language
    applyLocalizedStrings()
    tableView.reloadData()
  }
  private func applySkin() {
    guard isViewLoaded else { return }
    tableView.rowHeight = UITableView.automaticDimension; tableView.estimatedRowHeight = 72
    inputBar.enabledActions = skin.chat.enabledActions
    applyTheme()
  }
  private func applyLocalizedStrings() { guard isViewLoaded else { return }; inputBar.language = language; tableView.reloadData() }
  public override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) { super.traitCollectionDidChange(previousTraitCollection); if previousTraitCollection?.userInterfaceStyle != traitCollection.userInterfaceStyle { applyTheme() } }
  public func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { messages.count }
  open func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
    let message = messages[indexPath.row]
    let cell = tableView.dequeueReusableCell(withIdentifier: messageCellReuseIdentifier(for: message), for: indexPath)
    configureMessageCell(cell, message: message, outgoing: isOutgoing(message), at: indexPath)
    configureAvatarAction(on: cell, message: message)
    return cell
  }
  open func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) { tableView.deselectRow(at: indexPath, animated: true); didTapMessage(messages[indexPath.row]) }
}

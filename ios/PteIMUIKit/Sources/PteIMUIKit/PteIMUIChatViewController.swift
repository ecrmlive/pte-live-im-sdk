import UIKit
import PhotosUI
import UniformTypeIdentifiers
import CoreLocation
import MapKit
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

/** Host-owned reaction summary shown below a message bubble. */
public struct PteIMUIReaction: Hashable, Sendable {
  public let emoji: String
  public let count: Int
  public init(emoji: String, count: Int) { self.emoji = emoji; self.count = max(0, count) }
}

/**
 A host-defined business message. Gift, red-packet and order map directly to
 Core message types; `custom` deliberately stays a host callback because the
 wire protocol must be agreed by the integrating application.
 */
public struct PteIMUICustomMessage: Sendable {
  public enum Kind: Sendable { case gift, redPacket, order, custom }
  public let kind: Kind
  public let content: PteIMBusinessContent
  public let payload: String?
  public init(kind: Kind, content: PteIMBusinessContent, payload: String? = nil) {
    self.kind = kind; self.content = content; self.payload = payload
  }
}

/** A UIKit conversation screen. The host supplies attachment, location, and business payloads through [onActionRequested]. */
@MainActor
open class PteIMUIChatViewController: UIViewController, UITableViewDataSource, UITableViewDelegate, UITextFieldDelegate, PteIMUIInputBarDelegate, PHPickerViewControllerDelegate, UIDocumentPickerDelegate, UIImagePickerControllerDelegate, UINavigationControllerDelegate, @preconcurrency CLLocationManagerDelegate {
  public let client: PteIMSDK
  public let conversationId: String
  public var skin: PteIMUISkin { didSet { theme = skin.theme; inputBar.skin = skin; applySkin() } }
  public var theme: PteIMUITheme { didSet { applyTheme() } }
  public private(set) var language: PteIMLanguage
  public var onActionRequested: ((PteIMUIAction, PteIMUIChatViewController) -> Void)?
  /** Routes host-defined attachment tiles without overloading SDK business types. */
  public var onCustomInputActionRequested: ((PteIMUICustomInputAction, PteIMUIChatViewController) -> Void)?
  /** `true` starts host recording; `false` finalises/cancels it. The host then calls [sendVoice]. */
  public var onVoiceRecordingChanged: ((Bool, PteIMUIChatViewController) -> Void)?
  public var onVoiceRecordingCancelled: ((PteIMUIChatViewController) -> Void)?
  public var onAvatarTapped: ((PteIMMessage, PteIMUIChatViewController) -> Void)?
  public var onMessageTapped: ((PteIMMessage, PteIMUIChatViewController) -> Void)?
  public var onMessageAction: ((PteIMUIMessageAction, PteIMMessage, PteIMUIChatViewController) -> Void)?
  /** Called after PteIMUIKit has retried a failed message or accepted a retry request. */
  public var onMessageRetryRequested: ((PteIMMessage, PteIMUIChatViewController) -> Void)?
  /** Server-authoritative recall/delete remains business-owned; UIKit updates its local timeline immediately. */
  public var onMessageRevoked: ((PteIMMessage, PteIMUIChatViewController) -> Void)?
  public var onMessageDeleted: ((PteIMMessage, PteIMUIChatViewController) -> Void)?
  /** Receives the target message for a quote before the draft is sent. */
  public var onQuoteRequested: ((PteIMMessage, PteIMUIChatViewController) -> Void)?
  /** Custom business payloads are intentionally emitted to the integrator instead of inventing an unsupported Core message type. */
  public var onCustomMessageRequested: ((PteIMUICustomMessage, PteIMUIChatViewController) -> Void)?
  /** Optional host-owned navigation subtitle, e.g. an online state or group member count. */
  public var navigationSubtitleText: String?
  /** Optional host-owned group/avatar presentation for the compact 44pt chat navigation bar. */
  public var navigationAvatarText: String?
  public var navigationAvatarColor: UIColor?
  /** Shows the sender nickname above incoming messages. Enable this for group
   conversations; direct chats intentionally keep the compact one-to-one layout. */
  public var showsIncomingSenderNames = false
  /** Lets the host resolve a group member ID to its current nickname. When no
   provider is supplied, the SDK safely falls back to the sender ID. */
  public var senderDisplayNameProvider: ((PteIMMessage) -> String?)?
  /** Supplies persisted reaction summaries; PteIMUIKit never fabricates them. */
  public var reactionProvider: ((PteIMMessage) -> [PteIMUIReaction])?
  /** Receives a local reaction toggle so the host can persist it to its own
   repository. The UIKit timeline updates optimistically either way. */
  public var onReactionToggled: ((String, PteIMMessage, Bool, PteIMUIChatViewController) -> Void)?
  public var isOutgoing: ((PteIMMessage) -> Bool) = { _ in false }

  // Grouped tables keep the day separator inside the timeline instead of
  // floating it below the navigation bar while the messages scroll.
  public let tableView = UITableView(frame: .zero, style: .grouped)
  public let composerBar = UIView()
  public let chatNavigationBar = PteIMUIChatNavigationBar()
  public private(set) lazy var inputBar: PteIMUIInputBar = makeInputBar()
  /** Override to install an app-specific input bar while retaining keyboard and panel handling. */
  open func makeInputBar() -> PteIMUIInputBar { PteIMUIInputBar(skin: skin) }
  /**
   Override this ordered collection to add or replace message renderers. The
   first renderer that supports a message owns registration and configuration.
   */
  public private(set) lazy var messageRenderers: [PteIMUIChatMessageRenderer] = makeMessageRenderers()
  /// The current ordered timeline. Subclasses receive items through the open
  /// cell hooks; keeping mutation private preserves Core/cache consistency.
  public private(set) var messages: [PteIMMessage] = []
  private let listener = PteIMListener()
  private let locationManager = CLLocationManager()
  private lazy var appearanceController = PteIMUIAppearanceController(client: client, viewController: self)
  // The provider represents the host's persisted baseline. These deltas keep
  // the press feedback immediate while a host optionally writes that change
  // back to its repository/network layer.
  private var reactionDeltas: [String: [String: Int]] = [:]
  private var locallySelectedReactionKeys = Set<String>()
  private var reactionTarget: PteIMMessage?
  private var quotedMessage: PteIMMessage?
  private var uploadRetrySources: [String: (PteIMUIAction, URL)] = [:]
  private var messageSections: [[PteIMMessage]] {
    let calendar = Calendar.current
    let grouped = Dictionary(grouping: messages) { calendar.startOfDay(for: Date(timeIntervalSince1970: TimeInterval($0.createdAt) / 1000)) }
    return grouped.keys.sorted().map { grouped[$0]?.sorted { $0.createdAt < $1.createdAt } ?? [] }
  }

  public init(client: PteIMSDK, conversationId: String, title: String? = nil, skin: PteIMUISkin = .default) {
    self.client = client; self.conversationId = conversationId; self.skin = skin; self.theme = skin.theme; self.language = client.resolvedLanguage()
    self.isOutgoing = { message in message.senderId == client.currentUserId }
    super.init(nibName: nil, bundle: nil)
    self.title = title ?? conversationId
    // A chat owns the entire lower safe area. In a tab-hosted application it
    // must replace, rather than compete with, the root tab navigation.
    hidesBottomBarWhenPushed = true
  }
  public convenience init(client: PteIMSDK, conversationId: String, title: String? = nil, theme: PteIMUITheme) { self.init(client: client, conversationId: conversationId, title: title, skin: PteIMUISkin(theme: theme)) }
  required public init?(coder: NSCoder) { nil }

  public override func viewDidLoad() {
    super.viewDidLoad()
    configureViews(); bindClient(); appearanceController.start(); reloadFromCache(); applySkin()
  }

  public override func viewDidAppear(_ animated: Bool) {
    super.viewDidAppear(animated)
    // Messages can be injected by a host before the controller is presented.
    // Once the table is in the view hierarchy, it is safe to reveal them.
    scrollToLatest()
  }
  public override func viewWillAppear(_ animated: Bool) {
    super.viewWillAppear(animated)
    appearanceController.refresh()
    navigationController?.setNavigationBarHidden(true, animated: animated)
    configureNavigationBar()
  }
  public override func viewWillDisappear(_ animated: Bool) {
    super.viewWillDisappear(animated)
    // The tab/list screens continue to use their own navigation treatment.
    if isMovingFromParent || navigationController?.topViewController !== self {
      navigationController?.setNavigationBarHidden(false, animated: animated)
    }
  }
  deinit { client.removeListener(listener) }

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
  public func sendText(_ text: String) {
    guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
    // The current IM wire format carries plain Unicode text, which naturally
    // supports mixed text and emoji. Quoting remains host-renderable metadata
    // until the server quote contract is enabled.
    append(message: client.sendText(conversationId: conversationId, text: text))
    quotedMessage = nil
    inputBar.clearText()
  }
  public func sendEmoji(packageId: String = "default", emojiId: String) { append(message: client.sendEmoji(conversationId: conversationId, packageId: packageId, emojiId: emojiId)) }
  public func sendImage(_ media: PteIMMedia) { append(message: client.sendImage(conversationId: conversationId, media: media)) }
  public func sendVideo(_ media: PteIMMedia) { append(message: client.sendVideo(conversationId: conversationId, media: media)) }
  public func sendVoice(_ voice: PteIMVoice) { append(message: client.sendVoice(conversationId: conversationId, voice: voice)) }
  public func sendLocation(_ location: PteIMLocation) { append(message: client.sendLocation(conversationId: conversationId, location: location)) }
  public func sendGift(_ content: PteIMBusinessContent) { append(message: client.sendGift(conversationId: conversationId, content: content)) }
  public func sendRedPacket(_ content: PteIMBusinessContent) { append(message: client.sendRedPacket(conversationId: conversationId, content: content)) }
  public func sendOrder(_ content: PteIMBusinessContent) { append(message: client.sendOrder(conversationId: conversationId, content: content)) }
  public func sendFile(_ media: PteIMMedia) { append(message: client.sendFile(conversationId: conversationId, media: media)) }
  /** Uses Core's durable COS upload queue and keeps the local file for an explicit retry. */
  public func uploadAndSendImage(fileURL: URL) {
    let message = client.uploadAndSendImage(conversationId: conversationId, fileURL: fileURL)
    uploadRetrySources[message.clientMsgId] = (.image, fileURL)
    append(message: message)
  }
  /** Uses Core's durable COS upload queue and keeps the local file for an explicit retry. */
  public func uploadAndSendVideo(fileURL: URL) {
    let message = client.uploadAndSendVideo(conversationId: conversationId, fileURL: fileURL)
    uploadRetrySources[message.clientMsgId] = (.video, fileURL)
    append(message: message)
  }
  /** Uses Core's durable COS upload queue and keeps the local file for an explicit retry. */
  public func uploadAndSendFile(fileURL: URL) {
    let message = client.uploadAndSendFile(conversationId: conversationId, fileURL: fileURL)
    uploadRetrySources[message.clientMsgId] = (.file, fileURL)
    append(message: message)
  }
  /** Business messages with supported wire types are sent through Core. Custom payloads are emitted to the host. */
  public func sendCustomMessage(_ message: PteIMUICustomMessage) {
    switch message.kind {
    case .gift: sendGift(message.content)
    case .redPacket: sendRedPacket(message.content)
    case .order: sendOrder(message.content)
    case .custom: onCustomMessageRequested?(message, self)
    }
  }
  public func openEmojiPanel() { inputBar.openEmojiPanel() }
  public func openMorePanel() { inputBar.openMorePanel() }
  public func closeInputPanel() { inputBar.closePanel() }

  /** Configures the fixed 44pt chat header directly below the status bar. */
  open func configureNavigationBar() {
    let palette = skin.theme.palette(for: traitCollection)
    let isGroup = navigationAvatarText != nil || (title?.contains("群") ?? false) || (title?.localizedCaseInsensitiveContains("team") ?? false)
    let subtitle = navigationSubtitleText ?? (isGroup ? PteIMUILocalization.value("8 位成员", "8 members", language: language) : PteIMUILocalization.value("在线", "Online", language: language))
    chatNavigationBar.configure(
      title: title,
      subtitle: subtitle,
      avatarText: isGroup ? (navigationAvatarText ?? "#") : nil,
      avatarColor: navigationAvatarColor,
      palette: palette,
      iconProvider: skin.icons,
      traitCollection: traitCollection
    )
  }
  /** MessageKit-style default renderer registry; subclasses may replace it. */
  open func makeMessageRenderers() -> [PteIMUIChatMessageRenderer] {
    [PteIMUIRichMessageRenderer(), PteIMUIVoiceMessageRenderer(), PteIMUIBasicMessageRenderer()]
  }
  /** Override to choose a custom renderer for a message while retaining the default registry. */
  open func messageRenderer(for message: PteIMMessage) -> PteIMUIChatMessageRenderer? {
    messageRenderers.first { $0.supports(message) }
  }
  /** Override and register custom cells such as gifts, red packets or business cards. */
  open func registerMessageCells(in tableView: UITableView) {
    messageRenderers.forEach { $0.register(in: tableView) }
  }
  open func messageCellReuseIdentifier(for message: PteIMMessage) -> String {
    messageRenderer(for: message)?.reuseIdentifier ?? PteIMUIMessageCell.reuseIdentifier
  }
  /**
   Register any `UITableViewCell`, return its reuse identifier above, then
   override this method. The default branch configures PteIMUIMessageCell.
   This is intentionally not restricted to an SDK cell subclass.
   */
  open func configureMessageCell(_ cell: UITableViewCell, message: PteIMMessage, outgoing: Bool, at indexPath: IndexPath) {
    messageRenderer(for: message)?.configure(cell: cell, message: message, outgoing: outgoing, in: self, at: indexPath)
  }
  /** Override when reaction data is carried by a host repository instead of Core. */
  open func reactions(for message: PteIMMessage) -> [PteIMUIReaction] {
    var orderedEmoji: [String] = []
    var counts: [String: Int] = [:]
    for reaction in reactionProvider?(message) ?? [] where !reaction.emoji.isEmpty {
      if counts[reaction.emoji] == nil { orderedEmoji.append(reaction.emoji) }
      counts[reaction.emoji, default: 0] += reaction.count
    }
    for (emoji, delta) in reactionDeltas[message.clientMsgId] ?? [:] {
      if counts[emoji] == nil { orderedEmoji.append(emoji) }
      counts[emoji, default: 0] += delta
    }
    return orderedEmoji.compactMap { emoji in
      guard let count = counts[emoji], count > 0 else { return nil }
      return PteIMUIReaction(emoji: emoji, count: count)
    }
  }
  /** Override to source a group member nickname from a directory/cache. */
  open func senderDisplayName(for message: PteIMMessage) -> String? {
    guard showsIncomingSenderNames, !isOutgoing(message) else { return nil }
    return senderDisplayNameProvider?(message) ?? message.senderId
  }
  /** Dedicated hook for avatar actions in the default SDK message cell. */
  open func configureAvatarAction(on cell: UITableViewCell, message: PteIMMessage) {
    let callback: () -> Void = { [weak self] in
      guard let self else { return }
      self.didTapAvatar(for: message)
    }
    (cell as? PteIMUIMessageCell)?.onAvatarTapped = callback
    (cell as? PteIMUIRichMessageCell)?.onAvatarTapped = callback
    (cell as? PteIMUIVoiceMessageCell)?.onAvatarTapped = callback
  }
  open func didTapAvatar(for message: PteIMMessage) { onAvatarTapped?(message, self) }
  open func didTapMessage(_ message: PteIMMessage) {
    switch message.type {
    case .image: presentImagePreview(for: message)
    case .video: presentVideoPlayer(for: message)
    case .file: presentFilePreview(for: message)
    case .location: presentMapDestinations(for: message)
    default: break
    }
    onMessageTapped?(message, self)
  }
  /** Gift/order/red-packet actions are routed to the host business app. */
  open func didRequestAction(_ action: PteIMUIAction) { onActionRequested?(action, self) }

  private func configureViews() {
    view.addSubview(chatNavigationBar); view.addSubview(tableView); view.addSubview(composerBar)
    tableView.translatesAutoresizingMaskIntoConstraints = false; composerBar.translatesAutoresizingMaskIntoConstraints = false
    NSLayoutConstraint.activate([
      chatNavigationBar.leadingAnchor.constraint(equalTo: view.leadingAnchor), chatNavigationBar.trailingAnchor.constraint(equalTo: view.trailingAnchor), chatNavigationBar.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
      tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor), tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor), tableView.topAnchor.constraint(equalTo: chatNavigationBar.bottomAnchor), tableView.bottomAnchor.constraint(equalTo: composerBar.topAnchor),
      composerBar.leadingAnchor.constraint(equalTo: view.leadingAnchor), composerBar.trailingAnchor.constraint(equalTo: view.trailingAnchor), composerBar.bottomAnchor.constraint(equalTo: view.keyboardLayoutGuide.topAnchor), composerBar.heightAnchor.constraint(greaterThanOrEqualToConstant: 58)
    ])
    registerMessageCells(in: tableView); tableView.dataSource = self; tableView.delegate = self; tableView.separatorStyle = .none; tableView.keyboardDismissMode = .interactive
    tableView.sectionHeaderTopPadding = 0
    tableView.contentInset = .zero
    let longPress = UILongPressGestureRecognizer(target: self, action: #selector(messageLongPressed(_:)))
    tableView.addGestureRecognizer(longPress)
    // A tap anywhere in the timeline is an explicit dismissal action. It
    // preserves normal cell taps while removing keyboard/emoji/more chrome.
    let dismissTap = UITapGestureRecognizer(target: self, action: #selector(dismissInputPresentation))
    dismissTap.cancelsTouchesInView = false
    dismissTap.require(toFail: longPress)
    tableView.addGestureRecognizer(dismissTap)
    composerBar.addSubview(inputBar)
    NSLayoutConstraint.activate([inputBar.leadingAnchor.constraint(equalTo: composerBar.leadingAnchor), inputBar.trailingAnchor.constraint(equalTo: composerBar.trailingAnchor), inputBar.topAnchor.constraint(equalTo: composerBar.topAnchor), inputBar.bottomAnchor.constraint(equalTo: composerBar.bottomAnchor)])
    inputBar.delegate = self
    inputBar.onEmojiSelected = { [weak self] emoji in
      guard let self, let target = self.reactionTarget else { return false }
      self.reactionTarget = nil
      self.toggleReaction(emoji, for: target)
      self.inputBar.closePanel()
      return true
    }
    chatNavigationBar.onBack = { [weak self] in self?.backTapped() }
    chatNavigationBar.onMore = { [weak self] in self?.moreTapped() }
    locationManager.delegate = self
    locationManager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    configureNavigationBar()
  }
  private func bindClient() {
    listener.onMessage = { [weak self] message in guard message.conversationId == self?.conversationId else { return }; DispatchQueue.main.async { self?.append(message: message) } }
    listener.onMessageStateChanged = { [weak self] id, state in DispatchQueue.main.async { guard let self, let index = self.messages.firstIndex(where: { $0.clientMsgId == id }) else { return }; self.messages[index].state = state; self.tableView.reloadData() } }
    listener.onThemeModeChanged = { [weak self] _ in DispatchQueue.main.async { self?.appearanceController.refresh() } }
    listener.onLanguageChanged = { [weak self] _ in DispatchQueue.main.async {
      guard let self else { return }
      self.language = self.client.resolvedLanguage()
      self.applyLocalizedStrings()
    } }
    client.addListener(listener)
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
    let sections = messageSections
    guard let lastSection = sections.indices.last, let lastRow = sections[lastSection].indices.last else { return }
    let target = IndexPath(row: lastRow, section: lastSection)
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
    // With the system bar hidden, the controller itself paints the status-bar
    // area. Keep it identical to the fixed 44pt navigation row.
    view.backgroundColor = palette.surfaceColor
    tableView.backgroundColor = palette.backgroundColor
    composerBar.backgroundColor = palette.composerColor
    inputBar.theme = theme
    inputBar.language = language
    configureNavigationBar()
    applyLocalizedStrings()
    tableView.reloadData()
  }
  private func applySkin() {
    guard isViewLoaded else { return }
    tableView.rowHeight = UITableView.automaticDimension; tableView.estimatedRowHeight = 72
    inputBar.enabledActions = skin.chat.enabledActions
    applyTheme()
  }
  private func applyLocalizedStrings() { guard isViewLoaded else { return }; inputBar.language = language; configureNavigationBar(); tableView.reloadData() }
  @objc private func backTapped() { navigationController?.popViewController(animated: true) }
  @objc private func moreTapped() { didRequestAction(.gift) }
  @objc private func dismissInputPresentation() {
    inputBar.closePanel()
    inputBar.endEditingInput()
  }
  @objc private func messageLongPressed(_ recognizer: UILongPressGestureRecognizer) {
    guard recognizer.state == .began, let indexPath = tableView.indexPathForRow(at: recognizer.location(in: tableView)) else { return }
    let message = messageSections[indexPath.section][indexPath.row]
    guard let cell = tableView.cellForRow(at: indexPath) else { return }
    // The menu is anchored to the visible cell, not to the full-screen
    // overlay. This keeps it immediately above the message being acted on.
    let anchor = cell.convert(cell.bounds, to: view)
    PteIMUIMessageActionMenu.present(
      over: view,
      anchor: anchor,
      palette: theme.palette(for: traitCollection),
      language: language,
      actions: availableLongPressActions(for: message),
      onReaction: { [weak self] emoji in self?.toggleReaction(emoji, for: message) },
      onAddReaction: { [weak self] in
        guard let self else { return }
        self.reactionTarget = message
        self.inputBar.openEmojiPanel()
      }
    ) { [weak self] action in
      guard let self else { return }
      self.performMessageAction(action, for: message)
    }
  }

  private func availableLongPressActions(for message: PteIMMessage) -> [PteIMUIMessageAction] {
    var actions: [PteIMUIMessageAction] = [.quote]
    if message.type == .text { actions.append(.copy) }
    if isOutgoing(message) { actions.append(contentsOf: [.revoke, .delete]) }
    return actions
  }

  private func toggleReaction(_ emoji: String, for message: PteIMMessage) {
    let key = "\(message.clientMsgId)|\(emoji)"
    let wasSelected = locallySelectedReactionKeys.contains(key)
    if wasSelected {
      locallySelectedReactionKeys.remove(key)
      reactionDeltas[message.clientMsgId, default: [:]][emoji, default: 0] -= 1
    } else {
      locallySelectedReactionKeys.insert(key)
      reactionDeltas[message.clientMsgId, default: [:]][emoji, default: 0] += 1
    }
    if reactionDeltas[message.clientMsgId]?[emoji] == 0 { reactionDeltas[message.clientMsgId]?[emoji] = nil }
    if let indexPath = indexPath(for: message) {
      tableView.reloadRows(at: [indexPath], with: .none)
    }
    onReactionToggled?(emoji, message, !wasSelected, self)
  }

  /**
   Executes UIKit-owned operations immediately and then emits the same action
   to the host for a server-side audit/recall/delete implementation.
   */
  open func performMessageAction(_ action: PteIMUIMessageAction, for message: PteIMMessage) {
    switch action {
    case .quote:
      quotedMessage = message
      // Quote context is made visible to a host through the callback. The
      // server quote format is intentionally not guessed by the SDK.
      onQuoteRequested?(message, self)
    case .copy:
      UIPasteboard.general.string = PteIMUIMessageText.render(message, language: language)
    case .delete:
      removeMessageLocally(message)
      onMessageDeleted?(message, self)
    case .revoke:
      removeMessageLocally(message)
      onMessageRevoked?(message, self)
    }
    onMessageAction?(action, message, self)
  }

  /** Retries an upload from its retained sandbox file, or requeues a text/business message through Core. */
  open func retryMessage(_ message: PteIMMessage) {
    if let source = uploadRetrySources.removeValue(forKey: message.clientMsgId) {
      removeMessageLocally(message, scroll: false)
      switch source.0 {
      case .image: uploadAndSendImage(fileURL: source.1)
      case .video: uploadAndSendVideo(fileURL: source.1)
      case .file: uploadAndSendFile(fileURL: source.1)
      default: break
      }
    } else {
      append(message: client.retry(message: message))
    }
    onMessageRetryRequested?(message, self)
  }

  private func removeMessageLocally(_ message: PteIMMessage, scroll: Bool = true) {
    messages.removeAll { $0.clientMsgId == message.clientMsgId }
    reactionDeltas[message.clientMsgId] = nil
    locallySelectedReactionKeys = locallySelectedReactionKeys.filter { !$0.hasPrefix("\(message.clientMsgId)|") }
    guard isViewLoaded else { return }
    tableView.reloadData()
    if scroll { scrollToLatest() }
  }

  private func indexPath(for message: PteIMMessage) -> IndexPath? {
    for section in messageSections.indices {
      if let row = messageSections[section].firstIndex(where: { $0.clientMsgId == message.clientMsgId }) {
        return IndexPath(row: row, section: section)
      }
    }
    return nil
  }
  /** Default keyboard and gradient-send action. Subclasses can override to validate or intercept drafts. */
  open func inputBar(_ inputBar: PteIMUIInputBar, didSendText text: String) { sendText(text) }
  /** Default attachment/emoji route. Subclasses can override a single interaction boundary. */
  open func inputBar(_ inputBar: PteIMUIInputBar, didSelect selection: PteIMUIInputBarAction) {
    switch selection {
    case let .emoji(_, emojiId):
      if let target = reactionTarget {
        reactionTarget = nil
        toggleReaction(emojiId, for: target)
        inputBar.closePanel()
      }
    case let .action(action):
      switch action {
      case .image, .camera, .video, .location, .file: presentBuiltInAttachment(action)
      case .gift, .redPacket, .order, .voice: didRequestAction(action)
      }
    case let .custom(action): onCustomInputActionRequested?(action, self)
    }
  }
  open func inputBar(_ inputBar: PteIMUIInputBar, voiceRecordingChanged isRecording: Bool) {
    onVoiceRecordingChanged?(isRecording, self)
  }

  open func inputBarDidCancelVoiceRecording(_ inputBar: PteIMUIInputBar) {
    onVoiceRecordingCancelled?(self)
  }

  // MARK: Built-in attachment routes

  /// Image, camera, video, location and document selection are available out
  /// of the box. Business content remains intentionally host-owned.
  open func presentBuiltInAttachment(_ action: PteIMUIAction) {
    switch action {
    case .image, .video:
      var configuration = PHPickerConfiguration(photoLibrary: .shared())
      configuration.selectionLimit = 1
      configuration.filter = action == .image ? .images : .videos
      let picker = PHPickerViewController(configuration: configuration)
      picker.delegate = self
      present(picker, animated: true)
    case .camera:
      guard UIImagePickerController.isSourceTypeAvailable(.camera) else { return }
      let picker = UIImagePickerController()
      picker.sourceType = .camera
      picker.delegate = self
      // Keep the built-in camera route useful for both supported media kinds.
      // Apps can still override this action to supply a custom capture surface.
      picker.mediaTypes = [UTType.image.identifier, UTType.movie.identifier]
      present(picker, animated: true)
    case .file:
      let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.data, .pdf, .image, .movie], asCopy: true)
      picker.delegate = self; picker.allowsMultipleSelection = false
      present(picker, animated: true)
    case .location:
      let picker = makeLocationPicker()
      picker.onLocationSelected = { [weak self] location in self?.sendLocation(location) }
      present(UINavigationController(rootViewController: picker), animated: true)
    case .gift, .redPacket, .order, .voice: break
    }
  }

  public func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
    dismiss(animated: true)
    guard let result = results.first else { return }
    if result.itemProvider.hasItemConformingToTypeIdentifier(UTType.movie.identifier) {
      result.itemProvider.loadFileRepresentation(forTypeIdentifier: UTType.movie.identifier) { [weak self] url, _ in
        guard let self, let url, let local = Self.persistMedia(at: url, preferredName: "video.mov") else { return }
        DispatchQueue.main.async { self.uploadAndSendVideo(fileURL: local) }
      }
    } else if result.itemProvider.canLoadObject(ofClass: UIImage.self) {
      result.itemProvider.loadObject(ofClass: UIImage.self) { [weak self] image, _ in
        guard let self, let image = image as? UIImage, let local = Self.persist(image: image) else { return }
        DispatchQueue.main.async { self.uploadAndSendImage(fileURL: local) }
      }
    }
  }

  public func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
    picker.dismiss(animated: true)
    if let type = info[.mediaType] as? String,
       type == UTType.movie.identifier,
       let source = info[.mediaURL] as? URL,
       let local = Self.persistMedia(at: source, preferredName: source.lastPathComponent) {
      uploadAndSendVideo(fileURL: local)
      return
    }
    guard let image = info[.originalImage] as? UIImage, let local = Self.persist(image: image) else { return }
    uploadAndSendImage(fileURL: local)
  }
  public func imagePickerControllerDidCancel(_ picker: UIImagePickerController) { picker.dismiss(animated: true) }

  public func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
    guard let source = urls.first, let local = Self.persistMedia(at: source, preferredName: source.lastPathComponent) else { return }
    uploadAndSendFile(fileURL: local)
  }
  public func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
    if manager.authorizationStatus == .authorizedAlways || manager.authorizationStatus == .authorizedWhenInUse { manager.requestLocation() }
  }
  public func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
    guard let coordinate = locations.last?.coordinate else { return }
    sendLocation(PteIMLocation(latitude: coordinate.latitude, longitude: coordinate.longitude, name: PteIMUILocalization.value("当前位置", "Current location", language: language)))
  }
  public func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) { }

  // MARK: Built-in message interactions

  /** Factory hook for an inheritable full-screen image preview controller. */
  open func makeImagePreviewController(for message: PteIMMessage) -> PteIMUIImagePreviewController {
    let url = usableMediaURL(message.media?.url)
    let fallback = skin.icons.image(for: .messageImagePreview, traitCollection: traitCollection)
      ?? PteIMUIResources.image(named: "PteIMUIChatPreviewImage", traitCollection: traitCollection)
    return PteIMUIImagePreviewController(
      image: fallback,
      remoteImageURL: url,
      title: message.media?.fileName ?? PteIMUILocalization.value("图片预览", "Image preview", language: language)
    )
  }
  /** Tap closes the image preview; long press exports it to Photos. */
  open func presentImagePreview(for message: PteIMMessage) {
    let preview = makeImagePreviewController(for: message)
    preview.modalPresentationStyle = .fullScreen
    present(preview, animated: true)
  }

  /** Factory hook for an inheritable video player with explicit play/pause, close and progress controls. */
  open func makeVideoPreviewController(for message: PteIMMessage) -> PteIMUIVideoPreviewController {
    PteIMUIVideoPreviewController(
      videoURL: usableMediaURL(message.media?.url),
      placeholderImage: skin.icons.image(for: .messageImagePreview, traitCollection: traitCollection),
      title: message.media?.fileName ?? PteIMUILocalization.value("视频", "Video", language: language)
    )
  }
  open func presentVideoPlayer(for message: PteIMMessage) {
    let controller = makeVideoPreviewController(for: message)
    controller.modalPresentationStyle = .fullScreen
    present(controller, animated: true)
  }

  /** Factory hook for a QuickLook-backed file preview/export page. */
  open func makeFilePreviewController(for message: PteIMMessage) -> PteIMUIFilePreviewController? {
    guard let url = usableMediaURL(message.media?.url) else { return nil }
    return PteIMUIFilePreviewController(fileURL: url, title: message.media?.fileName ?? url.lastPathComponent)
  }
  open func presentFilePreview(for message: PteIMMessage) {
    guard let controller = makeFilePreviewController(for: message) else { return }
    present(controller, animated: true)
  }
  /** Factory hook for the built-in map picker used by the location action. */
  open func makeLocationPicker() -> PteIMUILocationPickerViewController {
    PteIMUILocationPickerViewController(language: language)
  }
  /** Shows only installed third-party map apps, followed by Apple Maps. */
  open func presentMapDestinations(for message: PteIMMessage) {
    guard let location = message.location else { return }
    let apps = PteIMUIMapDestination.installedApps(for: location)
    let title = location.name
    let sheet = UIAlertController(title: title, message: PteIMUILocalization.value("选择导航地图", "Choose a navigation app", language: language), preferredStyle: .actionSheet)
    apps.forEach { destination in
      sheet.addAction(UIAlertAction(title: destination.title, style: .default) { [weak self] _ in
        destination.open(from: self, location: location)
      })
    }
    sheet.addAction(UIAlertAction(title: PteIMUILocalization.value("取消", "Cancel", language: language), style: .cancel))
    if let popover = sheet.popoverPresentationController {
      popover.sourceView = view
      popover.sourceRect = view.bounds
    }
    present(sheet, animated: true)
  }

  private func usableMediaURL(_ rawValue: String?) -> URL? {
    guard let rawValue, !rawValue.isEmpty else { return nil }
    if let url = URL(string: rawValue), url.scheme != nil { return url }
    guard FileManager.default.fileExists(atPath: rawValue) else { return nil }
    return URL(fileURLWithPath: rawValue)
  }

  private nonisolated static func persist(image: UIImage) -> URL? {
    guard let data = image.jpegData(compressionQuality: 0.88) else { return nil }
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("pte-im-\(UUID().uuidString).jpg")
    do { try data.write(to: url, options: .atomic); return url } catch { return nil }
  }
  private nonisolated static func persistMedia(at source: URL, preferredName: String) -> URL? {
    let target = FileManager.default.temporaryDirectory.appendingPathComponent("pte-im-\(UUID().uuidString)-\(preferredName)")
    do { try FileManager.default.copyItem(at: source, to: target); return target } catch { return nil }
  }
  public override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) { super.traitCollectionDidChange(previousTraitCollection); if previousTraitCollection?.userInterfaceStyle != traitCollection.userInterfaceStyle { applyTheme() } }
  public func numberOfSections(in tableView: UITableView) -> Int { messageSections.count }
  public func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { messageSections[section].count }
  open func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
    let message = messageSections[indexPath.section][indexPath.row]
    let cell = tableView.dequeueReusableCell(withIdentifier: messageCellReuseIdentifier(for: message), for: indexPath)
    configureMessageCell(cell, message: message, outgoing: isOutgoing(message), at: indexPath)
    configureAvatarAction(on: cell, message: message)
    return cell
  }
  open func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
    tableView.deselectRow(at: indexPath, animated: true)
    let message = messageSections[indexPath.section][indexPath.row]
    if message.state == .failed, isOutgoing(message) { retryMessage(message) }
    else { didTapMessage(message) }
  }
  public func scrollViewWillBeginDragging(_ scrollView: UIScrollView) { dismissInputPresentation() }
  open func tableView(_ tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat { 34 }
  open func tableView(_ tableView: UITableView, viewForHeaderInSection section: Int) -> UIView? {
    let header = PteIMUITimelineHeaderView()
    header.configure(date: Date(timeIntervalSince1970: TimeInterval(messageSections[section].first?.createdAt ?? 0) / 1000), language: language, color: theme.palette(for: traitCollection).secondaryTextColor)
    return header
  }
}

@MainActor private enum PteIMUIMapDestination: CaseIterable {
  case amap, baidu, tencent, google, system

  var title: String {
    switch self {
    case .amap: return "高德地图"
    case .baidu: return "百度地图"
    case .tencent: return "腾讯地图"
    case .google: return "Google Maps"
    case .system: return PteIMUILocalization.value("系统地图", "Apple Maps", language: .system)
    }
  }

  static func installedApps(for location: PteIMLocation) -> [PteIMUIMapDestination] {
    // Keep the requested order and only expose installed third-party apps.
    [.amap, .baidu, .tencent, .google].filter { $0.url(for: location).map(UIApplication.shared.canOpenURL) ?? false } + [.system]
  }

  func open(from controller: UIViewController?, location: PteIMLocation) {
    guard self != .system else {
      let placemark = MKPlacemark(coordinate: .init(latitude: location.latitude, longitude: location.longitude))
      let item = MKMapItem(placemark: placemark)
      item.name = location.name
      item.openInMaps(launchOptions: [MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeDriving])
      return
    }
    guard let url = url(for: location) else { return }
    UIApplication.shared.open(url)
  }

  private func url(for location: PteIMLocation) -> URL? {
    let latitude = String(format: "%.6f", location.latitude)
    let longitude = String(format: "%.6f", location.longitude)
    let name = location.name
    var components: URLComponents
    switch self {
    case .amap:
      components = URLComponents(string: "iosamap://navi")!
      components.queryItems = [
        .init(name: "sourceApplication", value: "PteIMUIKit"),
        .init(name: "poiname", value: name),
        .init(name: "lat", value: latitude),
        .init(name: "lon", value: longitude),
        .init(name: "dev", value: "0"),
        .init(name: "style", value: "2")
      ]
    case .baidu:
      components = URLComponents(string: "baidumap://map/direction")!
      components.queryItems = [
        .init(name: "destination", value: "name:\(name)|latlng:\(latitude),\(longitude)"),
        .init(name: "mode", value: "driving"),
        .init(name: "coord_type", value: "gcj02")
      ]
    case .tencent:
      components = URLComponents(string: "qqmap://map/routeplan")!
      components.queryItems = [
        .init(name: "type", value: "drive"),
        .init(name: "tocoord", value: "\(latitude),\(longitude)"),
        .init(name: "to", value: name),
        .init(name: "policy", value: "0")
      ]
    case .google:
      components = URLComponents(string: "comgooglemaps://")!
      components.queryItems = [
        .init(name: "daddr", value: "\(latitude),\(longitude)"),
        .init(name: "directionsmode", value: "driving")
      ]
    case .system:
      return nil
    }
    return components.url
  }
}

private final class PteIMUITimelineHeaderView: UIView {
  private let leading = UIView(); private let trailing = UIView(); private let label = UILabel()
  override init(frame: CGRect) {
    super.init(frame: frame)
    [leading, trailing, label].forEach { $0.translatesAutoresizingMaskIntoConstraints = false; addSubview($0) }
    label.font = .systemFont(ofSize: 11, weight: .regular); label.textAlignment = .center
    NSLayoutConstraint.activate([
      label.centerXAnchor.constraint(equalTo: centerXAnchor), label.centerYAnchor.constraint(equalTo: centerYAnchor),
      leading.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 20), leading.trailingAnchor.constraint(equalTo: label.leadingAnchor, constant: -16), leading.centerYAnchor.constraint(equalTo: label.centerYAnchor), leading.heightAnchor.constraint(equalToConstant: 1),
      trailing.leadingAnchor.constraint(equalTo: label.trailingAnchor, constant: 16), trailing.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -20), trailing.centerYAnchor.constraint(equalTo: label.centerYAnchor), trailing.heightAnchor.constraint(equalToConstant: 1)
    ])
  }
  required init?(coder: NSCoder) { nil }
  func configure(date: Date, language: PteIMLanguage, color: UIColor) {
    let calendar = Calendar.current
    if calendar.isDateInToday(date) { label.text = PteIMUILocalization.value("今天 · Today", "Today", language: language) }
    else if calendar.isDateInYesterday(date) { label.text = PteIMUILocalization.value("昨天 · Yesterday", "Yesterday", language: language) }
    else { let formatter = DateFormatter(); formatter.dateFormat = "MM/dd"; label.text = formatter.string(from: date) }
    label.textColor = color; leading.backgroundColor = color.withAlphaComponent(0.20); trailing.backgroundColor = color.withAlphaComponent(0.20)
  }
}

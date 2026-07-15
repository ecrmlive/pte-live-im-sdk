import UIKit
import PteLiveIM

public enum PteIMUIAction: CaseIterable {
  case image, video, voice, location, gift, redPacket, order
  public func title(language: PteIMLanguage) -> String {
    switch self {
    case .image: return PteIMUILocalization.value("图片", "Image", language: language)
    case .video: return PteIMUILocalization.value("视频", "Video", language: language)
    case .voice: return PteIMUILocalization.value("语音", "Voice", language: language)
    case .location: return PteIMUILocalization.value("位置", "Location", language: language)
    case .gift: return PteIMUILocalization.value("礼物", "Gift", language: language)
    case .redPacket: return PteIMUILocalization.value("红包", "Red packet", language: language)
    case .order: return PteIMUILocalization.value("订单", "Order", language: language)
    }
  }
}

/** A UIKit conversation screen. The host supplies attachment, location, and business payloads through [onActionRequested]. */
public final class PteIMUIChatViewController: UIViewController, UITableViewDataSource, UITableViewDelegate, UITextFieldDelegate {
  public let client: PteLiveIM
  public let conversationId: String
  public var theme: PteIMUITheme { didSet { applyTheme() } }
  public private(set) var language: PteIMLanguage
  public var onActionRequested: ((PteIMUIAction, PteIMUIChatViewController) -> Void)?
  public var isOutgoing: ((PteIMMessage) -> Bool) = { $0.state != .sent }

  private let tableView = UITableView(frame: .zero, style: .plain)
  private let composer = UITextField()
  private let sendButton = UIButton(type: .system)
  private let actionButton = UIButton(type: .system)
  private let composerBar = UIView()
  private var messages: [PteIMMessage] = []
  private var previousMessageCallback: ((PteIMMessage) -> Void)?
  private var previousStateCallback: ((String, PteIMSendState) -> Void)?
  private var previousThemeCallback: ((PteIMThemeMode) -> Void)?
  private var previousLanguageCallback: ((PteIMLanguage) -> Void)?

  public init(client: PteLiveIM, conversationId: String, title: String? = nil, theme: PteIMUITheme = .default) {
    self.client = client; self.conversationId = conversationId; self.theme = theme; self.language = client.appearance.language
    super.init(nibName: nil, bundle: nil)
    self.title = title ?? conversationId
  }
  required init?(coder: NSCoder) { nil }

  public override func viewDidLoad() {
    super.viewDidLoad()
    configureViews(); bindClient(); reloadFromCache(); applyTheme()
  }
  // Core callbacks are chained with weak UI references. They remain safe after dismissal and are not reset here,
  // so an application that replaces a callback after presenting this controller is never overwritten on deinit.

  public func append(message: PteIMMessage) { upsert(message); tableView.reloadData(); scrollToLatest() }
  public func sendText(_ text: String) { guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }; append(message: client.sendText(conversationId: conversationId, text: text)); composer.text = nil }
  public func sendEmoji(packageId: String = "default", emojiId: String) { append(message: client.sendEmoji(conversationId: conversationId, packageId: packageId, emojiId: emojiId)) }
  public func sendImage(_ media: PteIMMedia) { append(message: client.sendImage(conversationId: conversationId, media: media)) }
  public func sendVideo(_ media: PteIMMedia) { append(message: client.sendVideo(conversationId: conversationId, media: media)) }
  public func sendVoice(_ voice: PteIMVoice) { append(message: client.sendVoice(conversationId: conversationId, voice: voice)) }
  public func sendLocation(_ location: PteIMLocation) { append(message: client.sendLocation(conversationId: conversationId, location: location)) }
  public func sendGift(_ content: PteIMBusinessContent) { append(message: client.sendGift(conversationId: conversationId, content: content)) }
  public func sendRedPacket(_ content: PteIMBusinessContent) { append(message: client.sendRedPacket(conversationId: conversationId, content: content)) }
  public func sendOrder(_ content: PteIMBusinessContent) { append(message: client.sendOrder(conversationId: conversationId, content: content)) }

  private func configureViews() {
    view.addSubview(tableView); view.addSubview(composerBar)
    tableView.translatesAutoresizingMaskIntoConstraints = false; composerBar.translatesAutoresizingMaskIntoConstraints = false
    NSLayoutConstraint.activate([tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor), tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor), tableView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor), tableView.bottomAnchor.constraint(equalTo: composerBar.topAnchor), composerBar.leadingAnchor.constraint(equalTo: view.leadingAnchor), composerBar.trailingAnchor.constraint(equalTo: view.trailingAnchor), composerBar.bottomAnchor.constraint(equalTo: view.keyboardLayoutGuide.topAnchor), composerBar.heightAnchor.constraint(greaterThanOrEqualToConstant: 58)])
    tableView.register(PteIMUIMessageCell.self, forCellReuseIdentifier: PteIMUIMessageCell.reuseIdentifier); tableView.dataSource = self; tableView.delegate = self; tableView.separatorStyle = .none; tableView.keyboardDismissMode = .interactive
    actionButton.setTitle("＋", for: .normal); actionButton.titleLabel?.font = .systemFont(ofSize: 26); actionButton.addTarget(self, action: #selector(showActions), for: .touchUpInside)
    composer.borderStyle = .roundedRect; composer.placeholder = "输入消息"; composer.returnKeyType = .send; composer.delegate = self
    sendButton.setTitle("发送", for: .normal); sendButton.addTarget(self, action: #selector(sendTapped), for: .touchUpInside)
    let stack = UIStackView(arrangedSubviews: [actionButton, composer, sendButton]); stack.spacing = 8; stack.alignment = .center
    composerBar.addSubview(stack); stack.translatesAutoresizingMaskIntoConstraints = false
    NSLayoutConstraint.activate([stack.leadingAnchor.constraint(equalTo: composerBar.leadingAnchor, constant: 12), stack.trailingAnchor.constraint(equalTo: composerBar.trailingAnchor, constant: -12), stack.topAnchor.constraint(equalTo: composerBar.topAnchor, constant: 8), stack.bottomAnchor.constraint(equalTo: composerBar.safeAreaLayoutGuide.bottomAnchor, constant: -8), actionButton.widthAnchor.constraint(equalToConstant: 34), sendButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 44)])
  }
  private func bindClient() {
    previousMessageCallback = client.onMessage; previousStateCallback = client.onMessageStateChanged; previousThemeCallback = client.onThemeModeChanged; previousLanguageCallback = client.onLanguageChanged
    client.onMessage = { [weak self] message in self?.previousMessageCallback?(message); guard message.conversationId == self?.conversationId else { return }; DispatchQueue.main.async { self?.append(message: message) } }
    client.onMessageStateChanged = { [weak self] id, state in self?.previousStateCallback?(id, state); DispatchQueue.main.async { guard let self, let index = self.messages.firstIndex(where: { $0.clientMsgId == id }) else { return }; self.messages[index].state = state; self.tableView.reloadRows(at: [IndexPath(row: index, section: 0)], with: .none) } }
    client.onThemeModeChanged = { [weak self] mode in self?.previousThemeCallback?(mode); DispatchQueue.main.async { self?.overrideUserInterfaceStyle = mode == .dark ? .dark : (mode == .light ? .light : .unspecified) } }
    client.onLanguageChanged = { [weak self] language in self?.previousLanguageCallback?(language); DispatchQueue.main.async { self?.language = language; self?.applyLocalizedStrings() } }
  }
  private func reloadFromCache() { messages = (try? client.localMessages(conversationId: conversationId, limit: 200)) ?? []; tableView.reloadData(); scrollToLatest() }
  private func upsert(_ message: PteIMMessage) { if let index = messages.firstIndex(where: { $0.clientMsgId == message.clientMsgId }) { messages[index] = message } else { messages.append(message); messages.sort { $0.createdAt < $1.createdAt } } }
  private func scrollToLatest() { guard !messages.isEmpty else { return }; tableView.scrollToRow(at: IndexPath(row: messages.count - 1, section: 0), at: .bottom, animated: true) }
  private func applyTheme() { guard isViewLoaded else { return }; view.backgroundColor = theme.backgroundColor; tableView.backgroundColor = theme.backgroundColor; composerBar.backgroundColor = theme.surfaceColor; sendButton.tintColor = theme.accentColor; actionButton.tintColor = theme.accentColor; applyLocalizedStrings(); tableView.reloadData() }
  private func applyLocalizedStrings() { guard isViewLoaded else { return }; composer.placeholder = PteIMUILocalization.value("输入消息", "Message", language: language); sendButton.setTitle(PteIMUILocalization.value("发送", "Send", language: language), for: .normal); tableView.reloadData() }
  @objc private func sendTapped() { sendText(composer.text ?? "") }
  @objc private func showActions() { let sheet = UIAlertController(title: PteIMUILocalization.value("发送消息", "Send message", language: language), message: nil, preferredStyle: .actionSheet); PteIMUIAction.allCases.forEach { action in sheet.addAction(UIAlertAction(title: action.title(language: self.language), style: .default) { [weak self] _ in guard let self else { return }; self.onActionRequested?(action, self) }) }; sheet.addAction(UIAlertAction(title: PteIMUILocalization.value("取消", "Cancel", language: language), style: .cancel)); present(sheet, animated: true) }
  public func textFieldShouldReturn(_ textField: UITextField) -> Bool { sendTapped(); return false }
  public func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { messages.count }
  public func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell { let cell = tableView.dequeueReusableCell(withIdentifier: PteIMUIMessageCell.reuseIdentifier, for: indexPath) as! PteIMUIMessageCell; let message = messages[indexPath.row]; cell.configure(message: message, outgoing: isOutgoing(message), theme: theme, language: language); return cell }
}

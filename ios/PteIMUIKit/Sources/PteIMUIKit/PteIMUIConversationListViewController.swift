import UIKit
import PteIMSDK

/** Cache-first conversation list with a blue–violet visual language shared by the chat screen. */
public final class PteIMUIConversationListViewController: UITableViewController {
  public let client: PteIMSDK
  public var theme: PteIMUITheme { didSet { applyTheme() } }
  public var onConversationSelected: ((PteIMConversation, PteIMUIConversationListViewController) -> Void)?
  private var conversations: [PteIMConversation] = []
  private var previousMessageCallback: ((PteIMMessage) -> Void)?

  public init(client: PteIMSDK, theme: PteIMUITheme = .default) {
    self.client = client
    self.theme = theme
    super.init(style: .plain)
    title = PteIMUILocalization.value("消息", "Messages", language: client.appearance.language)
  }
  required init?(coder: NSCoder) { nil }

  public override func viewDidLoad() {
    super.viewDidLoad()
    tableView.register(PteIMUIConversationCell.self, forCellReuseIdentifier: PteIMUIConversationCell.reuseIdentifier)
    tableView.separatorStyle = .none
    tableView.rowHeight = 78
    tableView.contentInset = UIEdgeInsets(top: 8, left: 0, bottom: 12, right: 0)
    refreshControl = UIRefreshControl()
    refreshControl?.addTarget(self, action: #selector(refresh), for: .valueChanged)
    bindClient()
    reloadConversations()
    applyTheme()
  }

  @objc public func refresh() {
    client.syncNow()
    reloadConversations()
    refreshControl?.endRefreshing()
  }

  public func reloadConversations() {
    conversations = (try? client.localConversations(limit: 100)) ?? []
    tableView.reloadData()
  }

  private func bindClient() {
    previousMessageCallback = client.onMessage
    client.onMessage = { [weak self] message in
      self?.previousMessageCallback?(message)
      DispatchQueue.main.async { self?.reloadConversations() }
    }
  }

  private func applyTheme() {
    guard isViewLoaded else { return }
    let palette = theme.palette(for: traitCollection)
    tableView.backgroundColor = palette.backgroundColor
    refreshControl?.tintColor = palette.outgoingGradientStartColor
    navigationController?.navigationBar.tintColor = palette.outgoingGradientStartColor
    tableView.reloadData()
  }

  public override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
    super.traitCollectionDidChange(previousTraitCollection)
    if previousTraitCollection?.userInterfaceStyle != traitCollection.userInterfaceStyle { applyTheme() }
  }

  public override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { conversations.count }

  public override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
    let cell = tableView.dequeueReusableCell(withIdentifier: PteIMUIConversationCell.reuseIdentifier, for: indexPath) as! PteIMUIConversationCell
    let conversation = conversations[indexPath.row]
    cell.configure(conversation: conversation, theme: theme, language: client.appearance.language)
    return cell
  }

  public override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
    tableView.deselectRow(at: indexPath, animated: true)
    let conversation = conversations[indexPath.row]
    if let onConversationSelected { onConversationSelected(conversation, self) }
    else {
      navigationController?.pushViewController(
        PteIMUIkit.makeChatViewController(client: client, conversationId: conversation.conversationId, title: conversation.conversationId, theme: theme),
        animated: true
      )
    }
  }
}

private final class PteIMUIConversationCell: UITableViewCell {
  static let reuseIdentifier = "PteIMUIConversationCell"
  private let card = UIView()
  private let avatar = UILabel()
  private let titleLabel = UILabel()
  private let previewLabel = UILabel()
  private let timeLabel = UILabel()
  private let unreadDot = UIView()

  override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
    super.init(style: style, reuseIdentifier: reuseIdentifier)
    selectionStyle = .none
    backgroundColor = .clear

    card.layer.cornerRadius = 18
    card.translatesAutoresizingMaskIntoConstraints = false
    contentView.addSubview(card)
    avatar.textAlignment = .center
    avatar.font = .systemFont(ofSize: 14, weight: .bold)
    avatar.layer.cornerRadius = 23
    avatar.clipsToBounds = true
    avatar.translatesAutoresizingMaskIntoConstraints = false
    card.addSubview(avatar)
    [titleLabel, previewLabel, timeLabel, unreadDot].forEach { $0.translatesAutoresizingMaskIntoConstraints = false; card.addSubview($0) }
    titleLabel.font = .preferredFont(forTextStyle: .headline)
    previewLabel.font = .preferredFont(forTextStyle: .subheadline)
    previewLabel.numberOfLines = 1
    timeLabel.font = .preferredFont(forTextStyle: .caption2)
    unreadDot.layer.cornerRadius = 4
    NSLayoutConstraint.activate([
      card.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 12), card.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -12),
      card.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 4), card.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -4),
      avatar.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 12), avatar.centerYAnchor.constraint(equalTo: card.centerYAnchor), avatar.widthAnchor.constraint(equalToConstant: 46), avatar.heightAnchor.constraint(equalToConstant: 46),
      titleLabel.leadingAnchor.constraint(equalTo: avatar.trailingAnchor, constant: 12), titleLabel.topAnchor.constraint(equalTo: card.topAnchor, constant: 15), titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: timeLabel.leadingAnchor, constant: -10),
      previewLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor), previewLabel.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -34), previewLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 5),
      timeLabel.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -13), timeLabel.topAnchor.constraint(equalTo: card.topAnchor, constant: 16),
      unreadDot.widthAnchor.constraint(equalToConstant: 8), unreadDot.heightAnchor.constraint(equalToConstant: 8), unreadDot.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -13), unreadDot.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -16)
    ])
  }
  required init?(coder: NSCoder) { nil }

  func configure(conversation: PteIMConversation, theme: PteIMUITheme, language: PteIMLanguage) {
    let palette = theme.palette(for: traitCollection)
    let seed = conversation.conversationId
    card.backgroundColor = palette.surfaceColor
    avatar.text = PteIMUIMessageText.avatarText(for: seed)
    avatar.backgroundColor = palette.outgoingGradientEndColor
    avatar.textColor = .white
    titleLabel.text = seed
    titleLabel.textColor = palette.primaryTextColor
    previewLabel.text = PteIMUIMessageText.render(conversation.lastMessage, language: language).replacingOccurrences(of: "\n", with: " · ")
    previewLabel.textColor = palette.secondaryTextColor
    timeLabel.text = PteIMUIConversationCell.time(conversation.updatedAt)
    timeLabel.textColor = palette.secondaryTextColor
    unreadDot.backgroundColor = palette.outgoingGradientStartColor
    unreadDot.isHidden = conversation.lastMessage.senderId == nil
  }

  private static func time(_ milliseconds: Int64) -> String {
    let date = Date(timeIntervalSince1970: TimeInterval(milliseconds) / 1000)
    return formatter.string(from: date)
  }
  private static let formatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.dateFormat = "HH:mm"
    return formatter
  }()
}
